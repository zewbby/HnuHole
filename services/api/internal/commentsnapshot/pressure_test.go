package commentsnapshot

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

// This adapter scopes the isolation assertion to live Redis admission. Durable
// PostgreSQL recovery is separately covered by the shared admission runner.
type pressureNamespace struct{ value ratelimit.Namespace }

func (n *pressureNamespace) Load(context.Context) (ratelimit.Namespace, error) { return n.value, nil }
func (n *pressureNamespace) Recover(context.Context, int64, string, time.Duration) (ratelimit.Namespace, error) {
	return n.value, errors.New("unexpected recovery in isolated pressure assertion")
}
func (n *pressureNamespace) Activate(context.Context, int64, string) (ratelimit.Namespace, error) {
	return n.value, errors.New("unexpected activation in isolated pressure assertion")
}

func TestRealRedisPressureEnvelopeAndSeparateAdmission(t *testing.T) {
	s, _ := realStore(t, 65536)
	admissionRedis, _ := realStore(t, 2) // second owned OS process, not just a prefix
	ctx := context.Background()
	policy := ratelimit.TrialConfig(admissionRedis.config.Redis.Address, "snapshot_pressure")
	for i := range policy.Rules {
		policy.Rules[i].Mode = ratelimit.Off
		if policy.Rules[i].Action == "entry.mutation" {
			policy.Rules[i].Mode = ratelimit.Enforce
			policy.Rules[i].Bucket = &ratelimit.Bucket{Capacity: 2, PerSecond: 1}
		}
	}
	info := admissionRedis.client.Info(ctx, "server").Val()
	runID := strings.Split(strings.Split(info, "run_id:")[1], "\r\n")[0]
	namespace := &pressureNamespace{value: ratelimit.Namespace{Generation: 1, RunID: runID, State: "READY"}}
	engine, e := ratelimit.New(policy, "", namespace)
	if e != nil {
		t.Fatal(e)
	}
	defer engine.Close()
	namespace.value.PolicyHash, namespace.value.RecoveryWindow = engine.PolicyHash(), engine.RecoveryWindow()
	if e = engine.InitializeRedis(ctx, namespace.value); e != nil {
		t.Fatal(e)
	}
	owner := sha256.Sum256([]byte("maximum ID pressure owner"))
	ids := make([]uuid.UUID, 10000)
	for i := range ids {
		ids[i] = uuid.New()
	}
	baseline := s.client.Info(ctx, "memory").Val()
	var first Prepared
	count := 0
	for ; count < 300; count++ {
		value, request := sample(s, owner)
		value.IDs = ids
		p, err := s.Prepare(ctx, value, request, LegacyUsage{})
		if errors.Is(err, ErrCapacity) {
			break
		}
		if err != nil {
			t.Fatalf("pressure prepare %d: %v", count, err)
		}
		if err = s.Publish(ctx, p); err != nil {
			t.Fatal(err)
		}
		if count == 0 {
			first = p
		}
	}
	if count < 100 || count >= 300 {
		t.Fatalf("unexpected bounded capacity %d", count)
	}
	usage, e := s.Usage(ctx, owner)
	if e != nil || usage.ReservedBytes > s.config.MaxModuleBytes || usage.AccountCount != count {
		t.Fatal(usage, e)
	}
	if _, e = s.Load(ctx, first.Snapshot.Scope, first.Snapshot.Ref, time.Now()); e != nil {
		t.Fatal("capacity blocked old read", e)
	}
	// Actual Redis OOM in the snapshot process must not disable the other
	// instance's admission writes, its exact denies or its bounded memory.
	if e = s.client.ConfigSet(ctx, "maxmemory", "1").Err(); e != nil {
		t.Fatal(e)
	}
	defer s.client.ConfigSet(ctx, "maxmemory", "64mb")
	if _, e = s.Load(ctx, first.Snapshot.Scope, first.Snapshot.Ref, time.Now()); e != nil {
		t.Fatal("OOM blocked read", e)
	}
	for i := 0; i < 3; i++ {
		decision, err := engine.Admit(ctx, strings.Repeat("a", 64), []ratelimit.Charge{{Action: "entry.mutation", Cost: 1}}, ratelimit.Proof{})
		if err != nil || decision.Allowed != (i < 2) {
			t.Fatalf("admission under snapshot OOM: %+v %v", decision, err)
		}
	}
	if e = admissionRedis.Check(ctx); e != nil {
		t.Fatal("separate instance changed", e)
	}
	t.Logf("maximumIDs=%d snapshots=%d payloadBytes=%d dataMemoryBytes=%d ledgerMemoryBytes=%d reservedBytes=%d moduleLimitBytes=%d admissionDecision=allow,allow,deny", len(ids), count, len(first.Payload), s.client.MemoryUsage(ctx, s.key(first.Snapshot.Ref.ID)).Val(), s.client.MemoryUsage(ctx, s.keys()[1]).Val(), usage.ReservedBytes, s.config.MaxModuleBytes)
	t.Logf("memoryBaseline=%q memoryAfterPressure=%q", baseline, s.client.Info(ctx, "memory").Val())
}

func TestRealRedisFailedCompensationAndBoundedBulkRecovery(t *testing.T) {
	s, _ := realStore(t, 65536)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("compensation owner"))
	value, request := sample(s, owner)
	p, e := s.Prepare(ctx, value, request, LegacyUsage{})
	if e != nil {
		t.Fatal(e)
	}
	if e = s.client.Do(ctx, "ACL", "SETUSER", "default", "-del").Err(); e != nil {
		t.Fatal(e)
	}
	e = s.Abort(ctx, p)
	if e == nil {
		t.Fatal("failed DEL compensation reported success")
	}
	usage, e := s.Usage(ctx, owner)
	if e != nil || usage.AccountCount != 1 {
		t.Fatal("failed compensation released quota", usage, e)
	}
	if e = s.Publish(ctx, p); !errors.Is(e, ErrUnavailable) {
		t.Fatal("aborting value published", e)
	}
	if e = s.client.Do(ctx, "ACL", "SETUSER", "default", "+del").Err(); e != nil {
		t.Fatal(e)
	}
	raw, e := s.client.Get(ctx, s.keys()[1]).Bytes()
	if e != nil || len(raw) != 274 {
		t.Fatal("packed fixture", len(raw), e)
	}
	seed := append([]byte(nil), raw[68:]...)
	// Synthetic multiplication of one real ABORTING record is cleanup pressure,
	// not 6000 successful creations. Each UUID and request identity is unique.
	const total = 6000
	pipe := s.client.Pipeline()
	for i := 1; i < total; i++ {
		id := uuid.New()
		entry := append([]byte(nil), seed...)
		copy(entry[:16], id[:])
		requestHash := sha256.Sum256([]byte(fmt.Sprint(i)))
		copy(entry[48:80], requestHash[:])
		raw = append(raw, entry...)
		pipe.Set(ctx, s.key(id), "orphan", 30*time.Minute)
	}
	binary.BigEndian.PutUint32(raw[64:68], total)
	if _, e = pipe.Exec(ctx); e != nil {
		t.Fatal(e)
	}
	if len(raw) > s.config.MaxLedgerBytes {
		t.Fatal("bulk fixture envelope", len(raw))
	}
	if e = s.client.Set(ctx, s.keys()[1], raw, 31*time.Minute).Err(); e != nil {
		t.Fatal(e)
	}
	s.client.AddHook(delayedDeleteHook{})
	started := time.Now()
	if e = s.Collect(ctx); e != nil {
		t.Fatal("bulk cleanup", e)
	}
	usage, e = s.Usage(ctx, owner)
	if e != nil || usage.AccountCount != 0 || time.Since(started) >= 5*time.Second {
		t.Fatal("recovery goal", usage, e)
	}
	if s.client.Exists(ctx, s.key(p.Snapshot.Ref.ID)).Val() != 0 {
		t.Fatal("original orphan remains")
	}
	t.Logf("failedCompensationKeptQuota=true injectedDeleteDelayMilliseconds=88 entries=%d ledgerBytes=%d recoveryMilliseconds=%d", total, len(raw), time.Since(started).Milliseconds())
}

func TestRealRedisDeadlineStateLossAndControlledExpiry(t *testing.T) {
	s, _ := realStore(t, 2)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("deadline owner"))
	value, request := sample(s, owner)
	p, e := s.Prepare(ctx, value, request, LegacyUsage{})
	if e != nil {
		t.Fatal(e)
	}
	if e = s.Publish(ctx, p); e != nil {
		t.Fatal(e)
	}
	old, found, e := s.Lookup(ctx, value.Scope, request, time.Now())
	if e != nil || !found || old.Ref.ID != p.Snapshot.Ref.ID {
		t.Fatal("committed nonce lookup", found, e)
	}
	if _, e = s.Load(ctx, value.Scope, p.Snapshot.Ref, p.Snapshot.Ref.Expires.Add(-time.Millisecond)); e != nil {
		t.Fatal("controlled instant before fixed expiry", e)
	}
	if _, e = s.Load(ctx, value.Scope, p.Snapshot.Ref, p.Snapshot.Ref.Expires); !errors.Is(e, ErrInvalid) {
		t.Fatal("controlled exact fixed expiry", e)
	}
	absent := request
	absent.Key = ownerString(sha256.Sum256([]byte("absent nonce")))
	if _, found, e = s.Lookup(ctx, value.Scope, absent, time.Now()); e != nil || found {
		t.Fatal("lookup allocated absent nonce", found, e)
	}
	wrong := value.Scope
	wrong.Post = uuid.New()
	wrongIdentity := Request(s.mac, owner, wrong, []byte("scope mismatch"))
	wrongIdentity.Key = request.Key
	if _, _, e = s.Lookup(ctx, wrong, wrongIdentity, time.Now()); !errors.Is(e, ErrRequest) {
		t.Fatal("lookup scope rebound", e)
	}
	if e = s.client.Do(ctx, "CLIENT", "PAUSE", 350, "ALL").Err(); e != nil {
		t.Fatal(e)
	}
	started := time.Now()
	if _, e = s.Load(ctx, value.Scope, p.Snapshot.Ref, time.Now()); !errors.Is(e, ErrUnavailable) {
		t.Fatal("real timeout", e)
	}
	if time.Since(started) > 500*time.Millisecond {
		t.Fatal("deadline budget escaped")
	}
	time.Sleep(400 * time.Millisecond)
	if _, e = s.Load(ctx, value.Scope, p.Snapshot.Ref, time.Now()); e != nil {
		t.Fatal("transport did not recover", e)
	}
	if e = s.client.PExpire(ctx, s.key(p.Snapshot.Ref.ID), time.Millisecond).Err(); e != nil {
		t.Fatal(e)
	}
	time.Sleep(20 * time.Millisecond)
	if _, e = s.Load(ctx, value.Scope, p.Snapshot.Ref, time.Now()); !errors.Is(e, ErrInvalid) {
		t.Fatal("controlled expiry", e)
	}
	if e = s.client.Del(ctx, s.keys()[0]).Err(); e != nil {
		t.Fatal(e)
	}
	if e = s.Check(ctx); !errors.Is(e, ErrIntegrity) {
		t.Fatal("lost control auto initialized", e)
	}
	other, identity := sample(s, owner)
	if _, e = s.Prepare(ctx, other, identity, LegacyUsage{}); !errors.Is(e, ErrIntegrity) {
		t.Fatal("lost control accepted writes", e)
	}
	// Operator initialization must also refuse surviving domain data.
	if e = s.InitializeNew(ctx); e == nil {
		t.Fatal("operator reset nonempty state")
	}
}

func TestRealRedisSnapshotOperationMeasurements(t *testing.T) {
	s, _ := realStore(t, 1024)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("operation measurement"))
	ids := make([]uuid.UUID, 500)
	for i := range ids {
		ids[i] = uuid.New()
	}
	create, load := []float64{}, []float64{}
	var first Prepared
	for i := 0; i < 530; i++ {
		value, request := sample(s, owner)
		value.IDs = ids
		started := time.Now()
		p, e := s.Prepare(ctx, value, request, LegacyUsage{})
		if e != nil {
			t.Fatal(e)
		}
		if e = s.Publish(ctx, p); e != nil {
			t.Fatal(e)
		}
		if i == 0 {
			first = p
		}
		if i >= 30 {
			create = append(create, float64(time.Since(started).Nanoseconds())/1e6)
		}
	}
	for i := 0; i < 530; i++ {
		started := time.Now()
		if _, e := s.Load(ctx, first.Snapshot.Scope, first.Snapshot.Ref, time.Now()); e != nil {
			t.Fatal(e)
		}
		if i >= 30 {
			load = append(load, float64(time.Since(started).Nanoseconds())/1e6)
		}
	}
	summary := map[string]any{"ids": 500, "ledgerEntries": 530, "warmup": 30, "samples": 500, "concurrency": 1, "errors": 0, "includesSQL": false}
	for name, values := range map[string][]float64{"prepareAndPublish": create, "load": load} {
		sort.Float64s(values)
		summary[name] = map[string]float64{"p50Milliseconds": values[249], "p95Milliseconds": values[474], "p99Milliseconds": values[494]}
		if values[474] > float64(s.config.OperationBudgetMilliseconds) {
			t.Fatal("snapshot operation P95 exceeds operation budget", name)
		}
	}
	raw, _ := json.Marshal(summary)
	t.Log(string(raw))
	// Empty order is valid, 10001 IDs is a distinct single-snapshot error.
	empty, request := sample(s, owner)
	empty.IDs = nil
	p, e := s.Prepare(ctx, empty, request, LegacyUsage{})
	if e != nil || len(p.Payload) != 153 {
		t.Fatal("empty payload envelope", len(p.Payload), e)
	}
	if e = s.Abort(ctx, p); e != nil {
		t.Fatal(e)
	}
	tooLarge, request := sample(s, owner)
	tooLarge.IDs = make([]uuid.UUID, 10001)
	if _, e = s.Prepare(ctx, tooLarge, request, LegacyUsage{}); !errors.Is(e, ErrTooLarge) {
		t.Fatal("ID limit distinction", e)
	}
}

func TestRealRedisReusedStatisticsStillValidateWholeLedger(t *testing.T) {
	s, _ := realStore(t, 1024)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("validated statistics"))
	value, request := sample(s, owner)
	p, err := s.Prepare(ctx, value, request, LegacyUsage{})
	if err != nil {
		t.Fatal(err)
	}
	if err = s.Publish(ctx, p); err != nil {
		t.Fatal(err)
	}
	usage, err := s.Usage(ctx, owner)
	if err != nil || usage.AccountCount != 1 {
		t.Fatal(usage, err)
	}
	s.reserved.Store(0)
	if err = s.Collect(ctx); err != nil || s.Metrics().ReservedBytes != uint64(usage.ReservedBytes) {
		t.Fatal("no-due collection must publish its own validated statistics", err, s.Metrics())
	}
	raw, err := s.client.Get(ctx, s.keys()[1]).Bytes()
	if err != nil || len(raw) != 274 {
		t.Fatal("packed fixture", len(raw), err)
	}
	peer := append([]byte(nil), raw[68:]...)
	id := uuid.New()
	copy(peer[:16], id[:])
	requestHash := sha256.Sum256([]byte("corrupt peer"))
	copy(peer[48:80], requestHash[:])
	binary.BigEndian.PutUint32(peer[176:180], 0)
	raw = append(raw, peer...)
	binary.BigEndian.PutUint32(raw[64:68], 2)
	if err = s.client.Set(ctx, s.keys()[1], raw, 31*time.Minute).Err(); err != nil {
		t.Fatal(err)
	}
	if _, _, err = s.Lookup(ctx, value.Scope, request, time.Now()); !errors.Is(err, ErrIntegrity) {
		t.Fatal("nonce lookup skipped corrupt peer entry", err)
	}
	if _, err = s.Prepare(ctx, value, request, LegacyUsage{}); !errors.Is(err, ErrIntegrity) {
		t.Fatal("prepare reuse skipped corrupt peer entry", err)
	}
	if _, err = s.Usage(ctx, owner); !errors.Is(err, ErrIntegrity) {
		t.Fatal("usage skipped corrupt peer entry", err)
	}
}
