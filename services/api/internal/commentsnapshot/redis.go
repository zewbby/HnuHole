package commentsnapshot

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	_ "embed"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/readtiming"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

//go:embed ledger_v2.lua
var commonSource string

//go:embed write.lua
var writeSource string

//go:embed read.lua
var readSource string

type Store struct {
	config                                       Config
	client                                       *redis.Client
	mac                                          MAC
	keyCommitment                                [32]byte
	epoch                                        uuid.UUID
	hash                                         string
	write, read                                  *redis.Script
	created, loaded, rejected, failures, elapsed atomic.Uint64
	invalid, reserved, memory                    atomic.Uint64
}
type LegacyUsage struct{ Count, RetryAfter int }
type Usage struct {
	AccountCount  int
	ReservedBytes int64
	RetryAfter    int
}
type Metrics struct{ Created, Loaded, Invalid, Rejected, Errors, DurationNanoseconds, ReservedBytes, RedisUsedMemoryBytes uint64 }

func New(config Config, password string, mac MAC) (*Store, error) {
	if err := config.Validate(); err != nil {
		return nil, err
	}
	if !config.ReadRedis || mac == nil {
		return nil, ErrIntegrity
	}
	epoch, _ := uuid.Parse(config.Redis.Epoch)
	commit := tag(mac, "HNUHOLE/COMMENT-SNAPSHOT-KEY-COMMITMENT/V1", nil)
	policy := struct {
		LedgerFormat, RecordBytes                                 int
		Namespace, Epoch, Key                                     string
		TTL, IDs, Account, Payload, Entries, Ledger, Lease, Clock int
		Module, Fixed                                             int64
	}{2, 206, config.Redis.Namespace, config.Redis.Epoch, hex.EncodeToString(commit[:]), config.TTLSeconds, config.MaxIDs, config.MaxPerAccount, config.MaxSnapshotBytes, config.MaxLedgerEntries, config.MaxLedgerBytes, config.PrepareLeaseSeconds, config.ClockSkewMilliseconds, config.MaxModuleBytes, config.LedgerFixedReserveBytes}
	b, _ := json.Marshal(policy)
	hash := sha256.Sum256(b)
	deadline := time.Duration(config.Redis.DeadlineMilliseconds) * time.Millisecond
	s := &Store{config: config, mac: mac, epoch: epoch, hash: hex.EncodeToString(hash[:]), client: redis.NewClient(&redis.Options{Addr: config.Redis.Address, Username: config.Redis.Username, Password: password, PoolSize: config.Redis.PoolSize, MaxRetries: -1, DialTimeout: deadline, ReadTimeout: deadline, WriteTimeout: deadline, PoolTimeout: deadline, ContextTimeoutEnabled: true})}
	s.write = redis.NewScript("#!lua flags=no-cluster\n" + commonSource + writeSource)
	s.keyCommitment = commit
	s.read = redis.NewScript("#!lua flags=no-writes,no-cluster\n" + commonSource + readSource)
	return s, nil
}
func (s *Store) Close() error      { return s.client.Close() }
func (s *Store) Config() Config    { return s.config }
func (s *Store) Epoch() uuid.UUID  { return s.epoch }
func (s *Store) Namespace() string { return s.config.Redis.Namespace }
func (s *Store) MatchesMAC(mac MAC) bool {
	return mac != nil && s.keyCommitment == tag(mac, "HNUHOLE/COMMENT-SNAPSHOT-KEY-COMMITMENT/V1", nil)
}
func (s *Store) Metrics() Metrics {
	return Metrics{Created: s.created.Load(), Loaded: s.loaded.Load(), Invalid: s.invalid.Load(), Rejected: s.rejected.Load(), Errors: s.failures.Load(), DurationNanoseconds: s.elapsed.Load(), ReservedBytes: s.reserved.Load(), RedisUsedMemoryBytes: s.memory.Load()}
}
func (s *Store) key(id uuid.UUID) string {
	return s.config.Redis.Namespace + "data:" + s.epoch.String() + ":" + id.String()
}
func (s *Store) keys() []string {
	return []string{s.config.Redis.Namespace + "control", s.config.Redis.Namespace + "ledger:" + s.epoch.String()}
}
func (s *Store) request(op string) map[string]any {
	return map[string]any{"op": op, "epoch": s.epoch.String(), "hash": s.hash, "maxLedgerBytes": s.config.MaxLedgerBytes, "maxEntries": s.config.MaxLedgerEntries, "maxModuleBytes": s.config.MaxModuleBytes, "fixedBytes": s.config.LedgerFixedReserveBytes, "maxAccount": s.config.MaxPerAccount, "maxPayload": s.config.MaxSnapshotBytes, "clockSkew": s.config.ClockSkewMilliseconds}
}
func ownerString(owner [32]byte) string { return base64.RawURLEncoding.EncodeToString(owner[:]) }

func classify(err error) error {
	if err == nil {
		return nil
	}
	m := err.Error()
	switch {
	case strings.Contains(m, "SNAPSHOT_INTEGRITY") || strings.Contains(m, "WRONGTYPE"):
		return ErrIntegrity
	case strings.Contains(m, "SNAPSHOT_CAPACITY") || strings.Contains(m, "OOM "):
		return ErrCapacity
	case strings.Contains(m, "SNAPSHOT_TOO_LARGE"):
		return ErrTooLarge
	case strings.Contains(m, "SNAPSHOT_REQUEST"):
		return ErrRequest
	default:
		return ErrUnavailable
	}
}
func (s *Store) call(ctx context.Context, write bool, keys []string, req map[string]any, payload []byte) ([]any, error) {
	defer readtiming.Span(ctx, "redis_rpc")()
	bounded, cancel, e := bound(ctx, time.Duration(s.config.Redis.DeadlineMilliseconds)*time.Millisecond)
	if e != nil {
		return nil, e
	}
	defer cancel()
	started := time.Now()
	defer func() { s.elapsed.Add(uint64(time.Since(started))) }()
	b, e := json.Marshal(req)
	if e != nil {
		return nil, ErrIntegrity
	}
	script := s.read
	if write {
		script = s.write
	}
	metadata, e := packedArguments(req)
	if e != nil {
		return nil, e
	}
	args := append([]any{string(b), payload}, metadata...)
	values, e := script.Run(bounded, s.client, keys, args...).Slice()
	if e != nil {
		s.failures.Add(1)
		return nil, classify(e)
	}
	return values, nil
}
func str(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case []byte:
		return string(t)
	default:
		return ""
	}
}
func code(v []any) string {
	if len(v) == 0 {
		return ""
	}
	return str(v[0])
}

// InitializeNew is an explicit operator action. New/Check never initialize,
// reset, rotate an epoch, or clear another module's namespace.
func (s *Store) InitializeNew(ctx context.Context) error {
	if e := s.checkServer(ctx); e != nil {
		return e
	}
	var cursor uint64
	for {
		keys, next, e := s.client.Scan(ctx, cursor, s.config.Redis.Namespace+"*", 64).Result()
		if e != nil {
			return classify(e)
		}
		if len(keys) > 0 {
			return ErrIntegrity
		}
		cursor = next
		if cursor == 0 {
			break
		}
	}
	b, _ := json.Marshal(map[string]any{"ledgerFormat": 2, "epoch": s.epoch.String(), "hash": s.hash, "state": "READY", "until_ms": 0})
	ok, e := s.client.SetNX(ctx, s.keys()[0], b, 0).Result()
	if e != nil {
		return classify(e)
	}
	if !ok {
		return ErrIntegrity
	}
	return nil
}
func (s *Store) checkServer(ctx context.Context) error {
	b, c, e := bound(ctx, time.Duration(s.config.Redis.DeadlineMilliseconds)*time.Millisecond)
	if e != nil {
		return e
	}
	defer c()
	info, e := s.client.Info(b, "server", "memory", "replication").Result()
	if e != nil {
		return classify(e)
	}
	if !strings.Contains(info, "redis_version:7.") || !strings.Contains(info, "role:master\r\n") || !strings.Contains(info, "maxmemory_policy:noeviction\r\n") || strings.Contains(info, "maxmemory:0\r\n") {
		return ErrIntegrity
	}
	for _, line := range strings.Split(info, "\n") {
		if strings.HasPrefix(line, "used_memory:") {
			if n, err := strconv.ParseUint(strings.TrimSpace(strings.TrimPrefix(line, "used_memory:")), 10, 64); err == nil {
				s.memory.Store(n)
			}
		}
	}
	return nil
}
func (s *Store) Check(ctx context.Context) error {
	if e := s.checkServer(ctx); e != nil {
		return e
	}
	_, e := s.Usage(ctx, [32]byte{})
	return e
}

func (s *Store) Prepare(ctx context.Context, snapshot Snapshot, identity RequestIdentity, legacy LegacyUsage) (Prepared, error) {
	defer readtiming.Span(ctx, "redis_prepare")()
	p := Prepared{Snapshot: snapshot, NewlyCreated: true}
	p.Snapshot.Ref.Backend = Redis
	p.Snapshot.Ref.Epoch = s.epoch
	if p.Snapshot.Ref.ID == uuid.Nil {
		p.Snapshot.Ref.ID = uuid.New()
	}
	p.Snapshot.Created = p.Snapshot.Created.UTC().Truncate(time.Millisecond)
	p.Snapshot.Ref.Expires = p.Snapshot.Created.Add(30 * time.Minute)
	f, e := flags(p.Snapshot.Ref)
	if e != nil {
		return p, e
	}
	p.Payload, e = Encode(s.mac, p.Snapshot, s.config.MaxSnapshotBytes)
	if e != nil {
		return p, e
	}
	var token [32]byte
	if _, e = rand.Read(token[:]); e != nil {
		return p, ErrUnavailable
	}
	p.Token = base64.RawURLEncoding.EncodeToString(token[:])
	digest := sha256.Sum256(p.Payload)
	p.Digest = hex.EncodeToString(digest[:])
	if len(identity.Key) != 43 || len(identity.Scope) != 43 || legacy.Count < 0 {
		return p, ErrRequest
	}
	if legacy.RetryAfter < 1 {
		legacy.RetryAfter = 1
	}
	r := s.request("prepare")
	r["id"] = p.Snapshot.Ref.ID.String()
	r["owner"] = ownerString(snapshot.Scope.Owner)
	r["request"] = identity.Key
	r["scope"] = identity.Scope
	r["token"] = p.Token
	r["digest"] = p.Digest
	r["created"] = p.Snapshot.Created.UnixMilli()
	r["expires"] = p.Snapshot.Ref.Expires.UnixMilli()
	r["flags"] = f
	r["legacy"] = legacy.Count
	r["legacyWait"] = legacy.RetryAfter
	r["cost"] = ((int64(2*len(p.Payload)+len(s.key(p.Snapshot.Ref.ID))+4096) + 4095) / 4096) * 4096
	values, e := s.call(ctx, true, append(s.keys(), s.key(p.Snapshot.Ref.ID)), r, p.Payload)
	if e != nil {
		return p, e
	}
	switch code(values) {
	case "QUOTA":
		s.rejected.Add(1)
		if len(values) != 2 {
			return p, ErrIntegrity
		}
		retry, _ := strconv.Atoi(str(values[1]))
		return p, &QuotaError{RetryAfter: max(1, retry)}
	case "PREPARED":
		s.created.Add(1)
		return p, nil
	case "REUSED":
		old, err := s.reused(ctx, snapshot.Scope, values, snapshot.Created)
		if err != nil {
			return p, err
		}
		return Prepared{Snapshot: old, NewlyCreated: false}, nil
	default:
		return p, ErrIntegrity
	}
}

// Lookup preserves an already committed initial-read nonce if the current
// comment order has since grown past the single-snapshot limit. It never
// reserves a new entry or renews an existing value's expiry.
func (s *Store) Lookup(ctx context.Context, scope Scope, identity RequestIdentity, at time.Time) (Snapshot, bool, error) {
	if !scope.Valid() || len(identity.Key) != 43 || len(identity.Scope) != 43 {
		return Snapshot{}, false, ErrRequest
	}
	r := s.request("lookup")
	r["owner"], r["request"], r["scope"] = ownerString(scope.Owner), identity.Key, identity.Scope
	values, err := s.call(ctx, false, s.keys(), r, nil)
	if err != nil {
		return Snapshot{}, false, err
	}
	if code(values) == "ABSENT" {
		return Snapshot{}, false, nil
	}
	if code(values) != "REUSED" {
		return Snapshot{}, false, ErrIntegrity
	}
	old, err := s.reused(ctx, scope, values, at)
	return old, err == nil, err
}

func (s *Store) reused(ctx context.Context, scope Scope, values []any, at time.Time) (Snapshot, error) {
	if len(values) != 4 {
		return Snapshot{}, ErrIntegrity
	}
	id, err := uuid.Parse(str(values[1]))
	if err != nil {
		return Snapshot{}, ErrIntegrity
	}
	exp, err := strconv.ParseInt(str(values[2]), 10, 64)
	if err != nil {
		return Snapshot{}, ErrIntegrity
	}
	flag, err := strconv.Atoi(str(values[3]))
	if err != nil || flag < 0 || flag > 255 {
		return Snapshot{}, ErrIntegrity
	}
	ref, err := parseFlags(byte(flag))
	if err != nil {
		return Snapshot{}, ErrIntegrity
	}
	ref.ID, ref.Epoch, ref.Expires = id, s.epoch, time.UnixMilli(exp).UTC()
	return s.Load(ctx, scope, ref, at)
}
func (s *Store) preparedRequest(op string, p Prepared) map[string]any {
	r := s.request(op)
	r["id"] = p.Snapshot.Ref.ID.String()
	r["owner"] = ownerString(p.Snapshot.Scope.Owner)
	r["token"] = p.Token
	r["digest"] = p.Digest
	return r
}
func (s *Store) Publish(ctx context.Context, p Prepared) error {
	defer readtiming.Span(ctx, "redis_publish")()
	if !p.NewlyCreated {
		return nil
	}
	values, e := s.call(ctx, true, append(s.keys(), s.key(p.Snapshot.Ref.ID)), s.preparedRequest("publish", p), p.Payload)
	if e == nil && code(values) == "ACTIVE" {
		return nil
	}
	if errors.Is(e, ErrUnavailable) {
		v, probe := s.call(ctx, false, s.keys(), s.preparedRequest("probe", p), nil)
		if probe == nil && code(v) == "ACTIVE" {
			return nil
		}
	}
	if e == nil {
		return ErrIntegrity
	}
	return e
}
func (s *Store) Load(ctx context.Context, scope Scope, ref Ref, at time.Time) (out Snapshot, err error) {
	defer readtiming.Span(ctx, "redis_load")()
	defer func() {
		if errors.Is(err, ErrInvalid) {
			s.invalid.Add(1)
		}
	}()
	if ref.Backend != Redis || ref.Epoch != s.epoch || !ref.Expires.After(at) {
		return Snapshot{}, ErrInvalid
	}
	values, e := s.call(ctx, false, []string{s.keys()[0], s.key(ref.ID)}, s.request("load"), nil)
	if e != nil {
		return Snapshot{}, e
	}
	if code(values) == "INVALID" {
		return Snapshot{}, ErrInvalid
	}
	if code(values) != "DATA" || len(values) != 3 {
		return Snapshot{}, ErrIntegrity
	}
	now, e := strconv.ParseInt(str(values[2]), 10, 64)
	if e != nil {
		return Snapshot{}, ErrIntegrity
	}
	if now > at.UnixMilli() {
		at = time.UnixMilli(now)
	}
	snapshot, e := Decode(s.mac, []byte(str(values[1])), scope, ref, at, s.config.MaxSnapshotBytes)
	if e == nil {
		s.loaded.Add(1)
	}
	return snapshot, e
}
func (s *Store) Abort(ctx context.Context, p Prepared) error {
	if !p.NewlyCreated {
		return nil
	}
	v, e := s.call(ctx, true, append(s.keys(), s.key(p.Snapshot.Ref.ID)), s.preparedRequest("abort", p), nil)
	if e != nil {
		return e
	}
	if code(v) == "ACTIVE" {
		return nil
	}
	if code(v) != "ABORTING" {
		return ErrIntegrity
	}
	if e = s.delete(ctx, []uuid.UUID{p.Snapshot.Ref.ID}); e != nil {
		return e
	}
	return s.release(ctx, []uuid.UUID{p.Snapshot.Ref.ID})
}
func (s *Store) Usage(ctx context.Context, owner [32]byte) (Usage, error) {
	defer readtiming.Span(ctx, "redis_usage")()
	r := s.request("usage")
	r["owner"] = ownerString(owner)
	v, e := s.call(ctx, false, s.keys(), r, nil)
	if e != nil {
		return Usage{}, e
	}
	if len(v) != 3 {
		return Usage{}, ErrIntegrity
	}
	n, e := strconv.Atoi(str(v[0]))
	if e != nil {
		return Usage{}, ErrIntegrity
	}
	bytes, e := strconv.ParseInt(str(v[1]), 10, 64)
	if e != nil {
		return Usage{}, ErrIntegrity
	}
	retry, e := strconv.Atoi(str(v[2]))
	if e != nil {
		return Usage{}, ErrIntegrity
	}
	s.reserved.Store(uint64(bytes))
	return Usage{n, bytes, retry}, nil
}
func (s *Store) delete(ctx context.Context, ids []uuid.UUID) error {
	for start := 0; start < len(ids); start += s.config.CleanupBatchSize {
		end := min(start+s.config.CleanupBatchSize, len(ids))
		keys := make([]string, 0, end-start)
		for _, id := range ids[start:end] {
			keys = append(keys, s.key(id))
		}
		b, c, e := bound(ctx, time.Duration(s.config.Redis.DeadlineMilliseconds)*time.Millisecond)
		if e != nil {
			return e
		}
		e = s.client.Del(b, keys...).Err()
		c()
		if e != nil {
			return classify(e)
		}
	}
	return nil
}
func (s *Store) release(ctx context.Context, ids []uuid.UUID) error {
	r := s.request("release")
	names := make([]string, 0, len(ids))
	keys := s.keys()
	for _, id := range ids {
		names = append(names, id.String())
		keys = append(keys, s.key(id))
	}
	r["ids"] = names
	v, e := s.call(ctx, true, keys, r, nil)
	if e != nil {
		return e
	}
	if len(v) != 2 || code(v) != "RELEASED" {
		return ErrIntegrity
	}
	return s.observeReserved(v[1])
}
func (s *Store) observeReserved(value any) error {
	bytes, err := strconv.ParseInt(str(value), 10, 64)
	if err != nil || bytes < s.config.LedgerFixedReserveBytes || bytes > s.config.MaxModuleBytes {
		return ErrIntegrity
	}
	s.reserved.Store(uint64(bytes))
	return nil
}

// Only background collection parallelizes deletes. Request/Abort budgets keep
// their sequential accounting, and one pool slot remains available to reads.
func (s *Store) collectDelete(ctx context.Context, ids []uuid.UUID) error {
	workers := min(8, s.config.Redis.PoolSize-1)
	if workers < 2 || len(ids) <= s.config.CleanupBatchSize {
		return s.delete(ctx, ids)
	}
	work, cancel := context.WithCancel(ctx)
	defer cancel()
	jobs := make(chan []uuid.UUID)
	failures := make(chan error, workers)
	var wg sync.WaitGroup
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for batch := range jobs {
				if err := s.delete(work, batch); err != nil {
					failures <- err
					cancel()
					return
				}
			}
		}()
	}
dispatch:
	for start := 0; start < len(ids); start += s.config.CleanupBatchSize {
		end := min(start+s.config.CleanupBatchSize, len(ids))
		select {
		case jobs <- ids[start:end]:
		case <-work.Done():
			break dispatch
		}
	}
	close(jobs)
	wg.Wait()
	close(failures)
	for err := range failures {
		if err != nil {
			return err
		}
	}
	if work.Err() != nil {
		return ErrUnavailable
	}
	return nil
}
func (s *Store) Drain(ctx context.Context) error {
	if err := s.checkServer(ctx); err != nil {
		return err
	}
	v, err := s.call(ctx, true, s.keys(), s.request("drain"), nil)
	if err != nil {
		return err
	}
	if code(v) != "DRAINING" {
		return ErrIntegrity
	}
	return nil
}
func (s *Store) Collect(ctx context.Context) error {
	b, c := context.WithTimeout(ctx, 5*time.Second)
	defer c()
	v, e := s.call(b, false, s.keys(), s.request("due"), nil)
	if e != nil {
		return e
	}
	if len(v) < 2 || code(v) != "DUE" || len(v)-2 > s.config.MaxLedgerEntries {
		return ErrIntegrity
	}
	ids := make([]uuid.UUID, 0, len(v)-2)
	for _, value := range v[2:] {
		id, err := uuid.FromBytes([]byte(str(value)))
		if err != nil {
			return ErrIntegrity
		}
		ids = append(ids, id)
	}
	if len(ids) == 0 {
		return s.observeReserved(v[1])
	}
	if e = s.collectDelete(b, ids); e != nil {
		return e
	}
	return s.release(b, ids)
}
func (s *Store) RunCleanup(ctx context.Context, observe func(Metrics)) {
	t := time.NewTicker(time.Duration(s.config.CleanupIntervalSeconds) * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			_ = s.Collect(ctx)
			_ = s.checkServer(ctx)
			if observe != nil {
				observe(s.Metrics())
			}
		}
	}
}

// String is safe for logs: it deliberately omits namespace, address and keys.
func (s *Store) String() string {
	return fmt.Sprintf("comment-snapshot-store(%d)", s.config.MaxPerAccount)
}
