package ratelimit

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

//go:embed atomic.lua
var atomicSource string

type Config struct {
	Address              string `json:"address"`
	Username             string `json:"username,omitempty"`
	Namespace            string `json:"namespace"`
	DeadlineMilliseconds int    `json:"deadlineMilliseconds"`
	PoolSize             int    `json:"poolSize"`
	MaxSubjects          int    `json:"maxSubjects"`
	MaxEvents            int    `json:"maxEvents"`
	MaxDedup             int    `json:"maxDedup"`
	MaxReserves          int    `json:"maxReserves"`
	MaxStateBytes        int    `json:"maxStateBytes"`
	DedupSeconds         int    `json:"dedupSeconds"`
	ReadSeconds          int    `json:"readSeconds"`
	Rules                []Rule `json:"rules"`
}

func (c Config) Validate() error {
	if _, _, err := net.SplitHostPort(c.Address); err != nil {
		return errors.New("invalid shared admission address")
	}
	if !regexp.MustCompile(`^[a-z][a-z0-9_-]{0,63}$`).MatchString(c.Namespace) || c.DeadlineMilliseconds < 10 || c.DeadlineMilliseconds > 1000 || c.PoolSize < 1 || c.PoolSize > 64 || c.MaxSubjects < 1 || c.MaxSubjects > 65536 || c.MaxEvents < 1 || c.MaxEvents > 16384 || c.MaxDedup < 1 || c.MaxDedup > 4096 || c.MaxReserves < 1 || c.MaxReserves > 64 || c.MaxStateBytes < 1024 || c.MaxStateBytes > 1048576 || c.DedupSeconds < 1 || c.DedupSeconds > 86400 || c.ReadSeconds < 1 || c.ReadSeconds > 60 || len(c.Rules) < 1 || len(c.Rules) > 32 {
		return errors.New("invalid bounded shared admission configuration")
	}
	actions := map[string]bool{}
	for _, r := range c.Rules {
		if !regexp.MustCompile(`^[a-z][a-z0-9_.]{0,47}$`).MatchString(r.Action) || actions[r.Action] || (r.Mode != Off && r.Mode != Observe && r.Mode != Enforce) || (r.Failure != "reject" && r.Failure != "local-read" && r.Failure != "verified-db") || (r.Bucket == nil) == (len(r.Windows) == 0) || len(r.Windows) > 4 {
			return errors.New("invalid shared admission rule")
		}
		if _, ok := actionService[r.Action]; !ok {
			return errors.New("unknown shared admission action")
		}
		actions[r.Action] = true
		if r.Action == "upload.bytes" && r.Bucket != nil {
			return errors.New("upload bytes requires exact sliding windows")
		}
		// Only these actions have verified final SQL budgets. Configuration
		// cannot turn an unbounded high-cost action into a DB fallback.
		if r.Failure == "verified-db" && r.Action != "post.create" && r.Action != "comment.publish" && r.Action != "otp.request" && r.Action != "otp.verify" {
			return errors.New("unverified database admission fallback")
		}
		if r.Failure == "local-read" && r.Action != "entry.query" && r.Action != "read.account" && r.Action != "read.control" {
			return errors.New("invalid local read admission fallback")
		}
		for _, w := range r.Windows {
			if w.Milliseconds < 1 || w.Milliseconds > int64(86400-c.ReadSeconds-1)*1000 || w.Limit < 1 || w.Limit > 1<<40 {
				return errors.New("invalid bounded sliding window")
			}
		}
		if r.Bucket != nil && (r.Bucket.Capacity < 1 || r.Bucket.Capacity > 1000000 || r.Bucket.PerSecond < 1 || r.Bucket.PerSecond > 1000000 || (r.Bucket.Capacity+r.Bucket.PerSecond-1)/r.Bucket.PerSecond > 86399) {
			return errors.New("invalid bounded token bucket")
		}
	}
	return nil
}

type Controller struct {
	policyHash     string
	subjectKeyHash string
	config         Config
	client         *redis.Client
	store          NamespaceStore
	rules          map[string]Rule
	retention      time.Duration
	recoveryWindow time.Duration
	transferWindow time.Duration
	Metrics        Metrics
}

// New does not initialize a namespace. Missing durable metadata is an error,
// including on a newly deployed API instance. The owner explicitly initializes
// a new environment before enabling these rules.
func New(config Config, password string, store NamespaceStore, subjectKey ...[32]byte) (*Controller, error) {
	if err := config.Validate(); err != nil {
		return nil, err
	}
	if store == nil {
		return nil, ErrUnavailable
	}
	// Freeze all rule slices; callers cannot mutate a running policy in place.
	rules := make([]Rule, len(config.Rules))
	for i, r := range config.Rules {
		rules[i] = r
		rules[i].Windows = append([]Window(nil), r.Windows...)
		if r.Bucket != nil {
			b := *r.Bucket
			rules[i].Bucket = &b
		}
	}
	config.Rules = rules
	if len(subjectKey) > 1 {
		return nil, ErrUnavailable
	}
	deadline := time.Duration(config.DeadlineMilliseconds) * time.Millisecond
	client := redis.NewClient(&redis.Options{Addr: config.Address, Username: config.Username, Password: password, PoolSize: config.PoolSize, MinIdleConns: 0, MaxRetries: -1, DialTimeout: deadline, ReadTimeout: deadline, WriteTimeout: deadline, PoolTimeout: deadline, ContextTimeoutEnabled: true})
	c := &Controller{config: config, client: client, store: store, rules: map[string]Rule{}, retention: time.Duration(config.DedupSeconds) * time.Second}
	c.recoveryWindow = time.Millisecond
	for _, r := range config.Rules {
		c.rules[r.Action] = r
		if r.Action == "upload.bytes" {
			for _, w := range r.Windows {
				if d := time.Duration(w.Milliseconds) * time.Millisecond; d > c.transferWindow {
					c.transferWindow = d
				}
			}
		}
		if r.Mode == Off {
			continue
		}
		for _, w := range r.Windows {
			d := time.Duration(w.Milliseconds)*time.Millisecond + time.Duration(config.ReadSeconds)*time.Second
			if d > c.recoveryWindow {
				c.recoveryWindow = d
			}
		}
		if r.Bucket != nil {
			d := time.Duration((r.Bucket.Capacity+r.Bucket.PerSecond-1)/r.Bucket.PerSecond) * time.Second
			if d > c.recoveryWindow {
				c.recoveryWindow = d
			}
		}
	}
	// The previous API may have an EVAL in flight for the maximum permitted
	// deadline. Transport deadlines do not enter policy meaning, so grace is
	// fixed rather than inherited from only the new API's connection options.
	c.recoveryWindow += time.Second
	if c.recoveryWindow > c.retention {
		c.retention = c.recoveryWindow
	}
	if len(subjectKey) == 1 {
		if subjectKey[0] == ([32]byte{}) {
			client.Close()
			return nil, ErrUnavailable
		}
		digest := sha256.Sum256(subjectKey[0][:])
		c.subjectKeyHash = hex.EncodeToString(digest[:])
	}
	ordered := append([]Rule(nil), config.Rules...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i].Action < ordered[j].Action })
	material := struct {
		Namespace                                                                               string
		Rules                                                                                   []Rule
		MaxSubjects, MaxEvents, MaxDedup, MaxReserves, MaxStateBytes, DedupSeconds, ReadSeconds int
		SubjectKeyHash                                                                          string
	}{config.Namespace, ordered, config.MaxSubjects, config.MaxEvents, config.MaxDedup, config.MaxReserves, config.MaxStateBytes, config.DedupSeconds, config.ReadSeconds, c.subjectKeyHash}
	encoded, _ := json.Marshal(material)
	digest := sha256.Sum256(encoded)
	c.policyHash = hex.EncodeToString(digest[:])
	return c, nil
}
func (c *Controller) Close() error                    { return c.client.Close() }
func (c *Controller) Rule(action string) (Rule, bool) { r, ok := c.rules[action]; return r, ok }
func randomDigest() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return ""
	}
	return hex.EncodeToString(b[:])
}
func (c *Controller) sentinel() string { return "hnuhole:" + c.config.Namespace + ":namespace" }
func infoValue(info, name string) string {
	for _, line := range strings.Split(info, "\n") {
		if strings.HasPrefix(line, name+":") {
			return strings.TrimSpace(strings.TrimPrefix(line, name+":"))
		}
	}
	return ""
}
func sentinelValue(ns Namespace) string {
	return fmt.Sprintf("%d:%s:%d", ns.Generation, ns.RunID, ns.Evicted)
}
func runID(info string) string {
	for _, line := range strings.Split(info, "\n") {
		if strings.HasPrefix(line, "run_id:") {
			return strings.TrimSpace(strings.TrimPrefix(line, "run_id:"))
		}
	}
	return ""
}

func (c *Controller) namespace(ctx context.Context) (Namespace, error) {
	ns, err := c.store.Load(ctx)
	if err != nil || ns.Generation < 1 || ns.RunID == "" {
		return ns, ErrUnavailable
	}
	if ns.PolicyHash != c.policyHash {
		return ns, ErrPolicyMismatch
	}
	info, err := c.client.Info(ctx, "server", "memory", "stats").Result()
	if err != nil {
		return ns, ErrUnavailable
	}
	id := runID(info)
	if id == "" {
		return ns, ErrUnavailable
	}
	evicted, e := strconv.ParseInt(infoValue(info, "evicted_keys"), 10, 64)
	if e != nil || evicted < 0 {
		return ns, ErrUnavailable
	}
	if infoValue(info, "maxmemory_policy") != "noeviction" || infoValue(info, "maxmemory") == "0" {
		_, _ = c.store.Recover(ctx, ns.Generation, id, c.recoveryWindow)
		return ns, ErrLost
	}
	ns.Evicted = evicted
	if ns.State == "READY" && ns.DirtyUntil != nil {
		_, _ = c.store.Recover(ctx, ns.Generation, id, c.recoveryWindow)
		return ns, ErrUnavailable
	}
	if ns.State == "READY" && ns.RunID != id {
		_, _ = c.store.Recover(ctx, ns.Generation, id, c.recoveryWindow)
		return ns, ErrLost
	}
	if ns.State == "RECOVERING" {
		if time.Now().Before(ns.BarrierUntil) {
			return ns, ErrUnavailable
		}
		if ns.RunID != id {
			_, _ = c.store.Recover(ctx, ns.Generation, id, c.recoveryWindow)
			return ns, ErrLost
		}
		if err = c.client.Set(ctx, c.sentinel(), sentinelValue(ns), 0).Err(); err != nil {
			return ns, ErrUnavailable
		}
		ns, err = c.store.Activate(ctx, ns.Generation, id)
		if err != nil {
			return ns, ErrUnavailable
		}
		ns.Evicted = evicted
	}
	if ns.State != "READY" {
		return ns, ErrUnavailable
	}
	ns.Evicted = evicted
	return ns, nil
}

// InitializeRedis is used only by an explicit administration command after its
// durable namespace row has been created. APIs never call it on missing state.
func (c *Controller) InitializeRedis(ctx context.Context, ns Namespace) error {
	if ns.Generation < 1 || ns.State != "READY" || ns.PolicyHash != c.policyHash {
		return ErrUnavailable
	}
	info, err := c.client.Info(ctx, "server", "memory", "stats").Result()
	if err != nil || runID(info) != ns.RunID {
		return ErrUnavailable
	}
	policy, err := c.client.ConfigGet(ctx, "maxmemory-policy").Result()
	if err != nil || policy["maxmemory-policy"] != "noeviction" {
		return ErrUnavailable
	}
	maximum, err := c.client.ConfigGet(ctx, "maxmemory").Result()
	if err != nil || maximum["maxmemory"] == "0" {
		return ErrUnavailable
	}
	ns.Evicted, _ = strconv.ParseInt(infoValue(info, "evicted_keys"), 10, 64)
	ok, err := c.client.SetNX(ctx, c.sentinel(), sentinelValue(ns), 0).Result()
	if err != nil || !ok {
		return ErrUnavailable
	}
	return nil
}

type luaCharge struct {
	Rule    Rule  `json:"rule"`
	Cost    int64 `json:"cost"`
	Reserve bool  `json:"reserve,omitempty"`
}
type atomicRequest struct {
	Kind        string      `json:"kind"`
	Subject     string      `json:"subject"`
	Sentinel    string      `json:"sentinel"`
	Generation  int64       `json:"generation"`
	Incarnation string      `json:"incarnation"`
	Proof       Proof       `json:"proof"`
	Charges     []luaCharge `json:"charges"`
	Retention   int64       `json:"retention"`
	DedupMS     int64       `json:"dedupMS"`
	MaxSubjects int         `json:"maxSubjects"`
	MaxEvents   int         `json:"maxEvents"`
	MaxDedup    int         `json:"maxDedup"`
	MaxReserves int         `json:"maxReserves"`
	MaxBytes    int         `json:"maxBytes"`
	Transfer    string      `json:"transfer,omitempty"`
	Amount      int64       `json:"amount,omitempty"`
	Actual      int64       `json:"actual"`
	ReadMS      int64       `json:"readMS"`
	ReserveMS   int64       `json:"reserveMS"`
}

func (c *Controller) Admit(ctx context.Context, subject string, charges []Charge, proof Proof) (Decision, error) {
	return c.execute(ctx, "admit", subject, charges, proof, "", 0, 0)
}
func (c *Controller) Probe(ctx context.Context, subject string, proof Proof) (Decision, error) {
	return c.execute(ctx, "probe", subject, nil, proof, "", 0, 0)
}
func (c *Controller) Confirm(ctx context.Context, subject string, proof Proof) error {
	_, err := c.execute(ctx, "confirm", subject, nil, proof, "", 0, 0)
	return err
}
func (c *Controller) BeginTransfer(ctx context.Context, subject, transfer string, amount int64) (Decision, error) {
	if rule, ok := c.rules["upload.bytes"]; ok && rule.Mode == Off {
		d, err := c.Admit(ctx, subject, []Charge{{"upload.attempt", 1}}, Proof{})
		d.Reserved = amount
		return d, err
	}
	return c.execute(ctx, "reserve", subject, []Charge{{"upload.attempt", 1}, {"upload.bytes", amount}}, Proof{}, transfer, amount, 0)
}
func (c *Controller) ReserveChunk(ctx context.Context, subject, transfer string, amount int64) (Decision, error) {
	if rule, ok := c.rules["upload.bytes"]; ok && rule.Mode == Off {
		return Decision{Allowed: true, Reserved: amount}, nil
	}
	return c.execute(ctx, "reserve", subject, []Charge{{"upload.bytes", amount}}, Proof{}, transfer, amount, 0)
}
func (c *Controller) SettleChunk(ctx context.Context, subject, transfer string, actual int64) error {
	if rule, ok := c.rules["upload.bytes"]; ok && rule.Mode == Off {
		return nil
	}
	_, err := c.execute(ctx, "settle", subject, []Charge{{"upload.bytes", 0}}, Proof{}, transfer, 0, actual)
	return err
}

// Enforced and observed actions never share capacity. Hard actions stay one
// atomic decision; observation is a separate, bounded best-effort lane.
func (c *Controller) execute(parent context.Context, kind, subject string, charges []Charge, proof Proof, transfer string, amount, actual int64) (Decision, error) {
	if e := c.ValidatePolicy(parent); e != nil {
		if errors.Is(e, ErrPolicyMismatch) {
			return Decision{}, e
		}
		hasHard := kind == "probe" || kind == "confirm"
		for _, v := range charges {
			if rule, ok := c.rules[v.Action]; ok && rule.Mode == Enforce {
				hasHard = true
			}
		}
		if hasHard {
			return Decision{}, e
		}
		return Decision{Allowed: true, Reserved: amount}, nil
	}
	if kind == "probe" || kind == "confirm" {
		d, e := c.executeLane(parent, false, kind, subject, nil, proof, transfer, amount, actual)
		if e == nil {
			_, _ = c.executeLane(parent, true, kind, subject, nil, proof, transfer, amount, actual)
		}
		return d, e
	}
	var hard, soft []Charge
	hardBytes, softBytes := false, false
	for _, charge := range charges {
		rule, ok := c.rules[charge.Action]
		if !ok {
			return Decision{}, ErrUnavailable
		}
		if rule.Mode == Enforce {
			hard = append(hard, charge)
			hardBytes = hardBytes || charge.Action == "upload.bytes"
		} else if rule.Mode == Observe {
			soft = append(soft, charge)
			softBytes = softBytes || charge.Action == "upload.bytes"
		}
	}
	d := Decision{Allowed: true, Reserved: amount}
	var err error
	if len(hard) > 0 {
		hardKind := kind
		if kind == "reserve" && !hardBytes {
			hardKind = "admit"
		}
		d, err = c.executeLane(parent, false, hardKind, subject, hard, proof, transfer, amount, actual)
		if err != nil || !d.Allowed {
			return d, err
		}
	}
	if kind == "reserve" && !hardBytes {
		d.Reserved = amount
	}
	if len(soft) > 0 {
		softKind := kind
		if kind == "reserve" && !softBytes {
			softKind = "admit"
		}
		observed, observeErr := c.executeLane(parent, true, softKind, subject, soft, proof, transfer, amount, actual)
		if errors.Is(observeErr, ErrPolicyMismatch) {
			return Decision{}, observeErr
		}
		d.WouldDeny = observed.WouldDeny
	}
	return d, nil
}
func (c *Controller) executeLane(parent context.Context, observer bool, kind, subject string, charges []Charge, proof Proof, transfer string, amount, actual int64) (result Decision, resultErr error) {
	if !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(subject) || len(charges) > 8 || amount > 65536 || actual > 65536 || amount < 0 || actual < 0 || len(transfer) > 96 {
		return result, ErrUnavailable
	}
	req := atomicRequest{Kind: kind, Subject: subject, Proof: proof, Incarnation: randomDigest(), Charges: []luaCharge{}, Retention: c.retention.Milliseconds(), DedupMS: int64(c.config.DedupSeconds) * 1000, MaxSubjects: c.config.MaxSubjects, MaxEvents: c.config.MaxEvents, MaxDedup: c.config.MaxDedup, MaxReserves: c.config.MaxReserves, MaxBytes: c.config.MaxStateBytes, Transfer: transfer, Amount: amount, Actual: actual, ReadMS: int64(c.config.ReadSeconds) * 1000, ReserveMS: c.transferWindow.Milliseconds()}
	enforcing := !observer && (kind == "probe" || kind == "confirm")
	seen := map[string]bool{}
	for _, charge := range charges {
		r, ok := c.rules[charge.Action]
		if !ok || seen[charge.Action] || charge.Cost < 0 {
			return result, ErrUnavailable
		}
		seen[charge.Action] = true
		if r.Mode == Off {
			continue
		}
		if !observer && r.Mode == Enforce {
			enforcing = true
		}
		req.Charges = append(req.Charges, luaCharge{r, charge.Cost, kind == "reserve" && charge.Action == "upload.bytes"})
	}
	if len(req.Charges) == 0 && kind != "probe" && kind != "confirm" {
		return Decision{Allowed: true, Reserved: amount}, nil
	}
	start := time.Now()
	defer func() {
		outcome := "allow"
		if resultErr != nil {
			outcome = "error"
		} else if result.WouldDeny {
			outcome = "would-deny"
		} else if !result.Allowed {
			outcome = "deny"
		}
		for _, v := range req.Charges {
			c.Metrics.add(v.Rule.Action, outcome, time.Since(start))
		}
		if !enforcing && resultErr != nil && !errors.Is(resultErr, ErrPolicyMismatch) {
			result = Decision{Allowed: true, Reserved: amount}
			resultErr = nil
		}
	}()
	ctx, cancel := context.WithTimeout(parent, time.Duration(c.config.DeadlineMilliseconds)*time.Millisecond)
	defer cancel()
	if proof.ExpectedGeneration > 0 {
		n, e := c.store.Load(ctx)
		if e != nil {
			return result, ErrUnavailable
		}
		if n.Generation != proof.ExpectedGeneration {
			return result, ErrStaleProof
		}
	}
	ns, err := c.namespace(ctx)
	if err != nil {
		return result, err
	}
	if proof.ExpectedGeneration > 0 && ns.Generation != proof.ExpectedGeneration {
		return result, ErrStaleProof
	}
	req.Generation = ns.Generation
	req.Sentinel = sentinelValue(ns)
	encoded, err := json.Marshal(req)
	if err != nil {
		return result, ErrUnavailable
	}
	base := fmt.Sprintf("hnuhole:%s:g%d:", c.config.Namespace, ns.Generation)
	if observer {
		base += "observe:"
	}
	// EVAL is deliberately not retried on connection/deadline/OOM errors.
	response, err := c.client.Eval(ctx, atomicSource, []string{c.sentinel(), base + "s:" + subject, base + "subjects"}, encoded).StringSlice()
	if err != nil {
		return result, ErrUnavailable
	}
	if len(response) < 1 {
		return result, ErrUnavailable
	}
	result.Generation = ns.Generation
	switch response[0] {
	case "ALLOW", "REPLAY":
		if len(response) < 2 || len(response) > 4 {
			return result, ErrUnavailable
		}
		result.Allowed = true
		result.Replay = response[0] == "REPLAY"
		result.Incarnation = response[1]
		result.WouldDeny = len(response) >= 3 && response[2] == "1"
		if len(response) == 4 {
			result.Reserved, _ = strconv.ParseInt(response[3], 10, 64)
		}
		return result, nil
	case "ABSENT":
		if len(response) == 2 {
			result.Incarnation = response[1]
		}
		return result, nil
	case "DENY":
		if len(response) != 2 {
			return result, ErrUnavailable
		}
		result.RetryAfter, _ = strconv.Atoi(response[1])
		if result.RetryAfter < 1 || result.RetryAfter > 86400 {
			return Decision{}, ErrUnavailable
		}
		if !enforcing {
			result.Allowed = true
			result.WouldDeny = true
		}
		return result, nil
	case "STALE":
		return result, ErrStaleProof
	case "CONFLICT":
		return result, ErrConflict
	case "CAPACITY":
		return result, ErrCapacity
	case "NAMESPACE_LOST":
		_, _ = c.store.Recover(parent, ns.Generation, ns.RunID, c.recoveryWindow)
		return result, ErrLost
	case "LOST":
		if observer {
			return result, ErrLost
		}
		_, _ = c.store.Recover(parent, ns.Generation, ns.RunID, c.recoveryWindow)
		return result, ErrLost
	default:
		return result, ErrUnavailable
	}
}

func (c *Controller) CanDBFallback(ctx context.Context) bool {
	ns, err := c.store.Load(ctx)
	return err == nil && ns.State == "READY" && ns.Generation > 0 && ns.PolicyHash == c.policyHash
}
func (c *Controller) Check(ctx context.Context, subject string, charges []Charge) (Decision, error) {
	return c.execute(ctx, "check", subject, charges, Proof{}, "", 0, 0)
}
func (c *Controller) ResetAction(ctx context.Context, subject, action string) error {
	_, err := c.execute(ctx, "reset", subject, []Charge{{Action: action, Cost: 0}}, Proof{}, "", 0, 0)
	return err
}

func (c *Controller) Metadata(ctx context.Context) (Namespace, error) {
	n, e := c.store.Load(ctx)
	if e == nil && n.PolicyHash != c.policyHash {
		e = ErrPolicyMismatch
	}
	return n, e
}

func (c *Controller) RecoveryWindow() time.Duration { return c.recoveryWindow }
func (c *Controller) ReadWindow() time.Duration {
	return time.Duration(c.config.ReadSeconds) * time.Second
}
func (c *Controller) PrepareWindow() time.Duration {
	d := time.Duration(c.config.DedupSeconds)*time.Second - 5*time.Second
	if d > 2*time.Minute {
		d = 2 * time.Minute
	}
	return d
}
func (c *Controller) TransferEnforced() bool {
	for _, action := range []string{"upload.attempt", "upload.bytes"} {
		if rule, ok := c.rules[action]; ok && rule.Mode == Enforce {
			return true
		}
	}
	return false
}

func (c *Controller) PolicyHash() string { return c.policyHash }
func (c *Controller) ValidatePolicy(ctx context.Context) error {
	n, e := c.store.Load(ctx)
	if e != nil {
		return ErrUnavailable
	}
	if n.PolicyHash != c.policyHash {
		return ErrPolicyMismatch
	}
	return nil
}
func (c *Controller) MatchesSubjectKey(key [32]byte) bool {
	if c.subjectKeyHash == "" {
		return true
	}
	digest := sha256.Sum256(key[:])
	return c.subjectKeyHash == hex.EncodeToString(digest[:])
}

// Resume a completed recovery barrier even if broad entry rules are off. The
// caller invokes this only after its normal Gate/session transaction is valid.
func (c *Controller) ResumeRecovery(ctx context.Context) error {
	bounded, cancel := context.WithTimeout(ctx, time.Duration(c.config.DeadlineMilliseconds)*time.Millisecond)
	defer cancel()
	_, e := c.namespace(bounded)
	return e
}
