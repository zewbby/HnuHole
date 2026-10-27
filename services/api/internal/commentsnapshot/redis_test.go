package commentsnapshot

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
)

func testMAC() MAC {
	var key [32]byte
	_, _ = rand.Read(key[:])
	return func(d [32]byte) (out [32]byte) {
		m := hmac.New(sha256.New, key[:])
		_, _ = m.Write(d[:])
		copy(out[:], m.Sum(nil))
		return
	}
}
func sample(s *Store, owner [32]byte) (Snapshot, RequestIdentity) {
	scope := Scope{Owner: owner, Post: uuid.New(), Kind: comments.MainComments, Sort: comments.Relevant}
	nonce := uuid.New()
	identity := Request(s.mac, owner, scope, nonce[:])
	created := time.Now().UTC().Truncate(time.Millisecond)
	return Snapshot{Ref: Ref{Backend: Redis, Epoch: s.epoch, ID: uuid.New(), Expires: created.Add(30 * time.Minute), Kind: scope.Kind, Sort: scope.Sort}, Scope: scope, Created: created, IDs: []uuid.UUID{uuid.New(), uuid.New()}}, identity
}

// Each fixture starts its own Redis and verifies the process ID before mutation.
// It never accepts an external Redis address or flushes an existing database.
func realStore(t *testing.T, quota int) (*Store, MAC) {
	t.Helper()
	binary := os.Getenv("COMMENT_SNAPSHOT_REDIS_SERVER")
	if binary == "" {
		t.Skip("owned Redis binary absent; not real-Redis acceptance")
	}
	listener, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	_ = listener.Close()
	dir := t.TempDir()
	cmd := exec.Command(binary, "--bind", "127.0.0.1", "--port", strconv.Itoa(port), "--save", "", "--appendonly", "no", "--maxmemory", "64mb", "--maxmemory-policy", "noeviction", "--dir", dir, "--logfile", filepath.Join(dir, "redis.log"))
	if e = cmd.Start(); e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	config := DefaultConfig()
	config.CreateBackend = "redis"
	config.ReadPostgres = false
	config.ReadRedis = true
	config.MaxPerAccount = quota
	config.Redis.Address = net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
	config.Redis.Namespace = "hnuhole:comment-snapshot:v2:test:"
	config.Redis.Epoch = uuid.NewString()
	mac := testMAC()
	s, e := New(config, "", mac)
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { _ = s.Close() })
	ctx := context.Background()
	ready := false
	for attempt := 0; attempt < 100; attempt++ {
		info, err := s.client.Info(ctx, "server").Result()
		if err == nil {
			if !strings.Contains(info, "process_id:"+strconv.Itoa(cmd.Process.Pid)+"\r\n") {
				t.Fatal("Redis fixture ownership mismatch")
			}
			ready = true
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !ready {
		t.Fatal("owned Redis did not start")
	}
	if e = s.InitializeNew(ctx); e != nil {
		t.Fatal(e)
	}
	return s, mac
}

func TestCodecBindsValueAndCursor(t *testing.T) {
	config := DefaultConfig()
	mac := testMAC()
	owner := sha256.Sum256([]byte("fixture account"))
	at := time.Now().UTC().Truncate(time.Millisecond)
	for _, sort := range []comments.SortMode{comments.Relevant, comments.Recent, comments.MostLiked} {
		scope := Scope{Owner: owner, Post: uuid.New(), Kind: comments.MainComments, Sort: sort}
		ref := Ref{Backend: Redis, Epoch: uuid.New(), ID: uuid.New(), Expires: at.Add(30 * time.Minute), Kind: scope.Kind, Sort: sort}
		value := Snapshot{Ref: ref, Scope: scope, Created: at, IDs: []uuid.UUID{uuid.New()}}
		b, e := Encode(mac, value, config.MaxSnapshotBytes)
		if e != nil {
			t.Fatal(e)
		}
		got, e := Decode(mac, b, scope, ref, at, config.MaxSnapshotBytes)
		if e != nil || got.IDs[0] != value.IDs[0] {
			t.Fatal("roundtrip", e)
		}
		cursor, e := EncodeCursor(mac, ref, 50)
		if e != nil || len(cursor) != 104 {
			t.Fatal("cursor", e)
		}
		decoded, offset, e := DecodeCursor(mac, cursor)
		if e != nil || offset != 50 || decoded != ref {
			t.Fatal("cursor binding", decoded, e)
		}
		badScope := scope
		badScope.Owner = sha256.Sum256([]byte("other fixture account"))
		if _, e = Decode(mac, b, badScope, ref, at, config.MaxSnapshotBytes); !errors.Is(e, ErrInvalid) {
			t.Fatal("cross account", e)
		}
		b[len(b)-1] ^= 1
		if _, e = Decode(mac, b, scope, ref, at, config.MaxSnapshotBytes); !errors.Is(e, ErrIntegrity) {
			t.Fatal("bad MAC", e)
		}
	}
}
func TestRealRedisPublishedNonceQuotaAndFixedExpiry(t *testing.T) {
	s, _ := realStore(t, 2)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("owner"))
	snapshot, identity := sample(s, owner)
	p, e := s.Prepare(ctx, snapshot, identity, LegacyUsage{})
	if e != nil {
		t.Fatal(e)
	}
	if e = s.Publish(ctx, p); e != nil {
		t.Fatal(e)
	}
	ttl := s.client.PTTL(ctx, s.key(p.Snapshot.Ref.ID)).Val()
	if ttl < 29*time.Minute || ttl > 30*time.Minute {
		t.Fatal("TTL", ttl)
	}
	if e = s.Publish(ctx, p); e != nil {
		t.Fatal(e)
	}
	changed := snapshot
	changed.Ref.ID = uuid.New()
	changed.IDs = []uuid.UUID{uuid.New()}
	reused, e := s.Prepare(ctx, changed, identity, LegacyUsage{})
	if e != nil || reused.NewlyCreated || reused.Snapshot.Ref.ID != p.Snapshot.Ref.ID || reused.Snapshot.IDs[0] != snapshot.IDs[0] {
		t.Fatal("nonce changed list", e)
	}
	if s.client.PTTL(ctx, s.key(p.Snapshot.Ref.ID)).Val() > ttl {
		t.Fatal("read renewed TTL")
	}
	other, otherIdentity := sample(s, owner)
	q, e := s.Prepare(ctx, other, otherIdentity, LegacyUsage{})
	if e != nil {
		t.Fatal(e)
	}
	third, thirdIdentity := sample(s, owner)
	_, e = s.Prepare(ctx, third, thirdIdentity, LegacyUsage{})
	var quota *QuotaError
	if !errors.As(e, &quota) || quota.RetryAfter < 1 {
		t.Fatal("quota", e)
	}
	if e = s.Abort(ctx, q); e != nil {
		t.Fatal(e)
	}
	usage, e := s.Usage(ctx, owner)
	if e != nil || usage.AccountCount != 1 {
		t.Fatal("compensation", usage, e)
	}
	if e = s.Abort(ctx, p); e != nil {
		t.Fatal(e)
	}
	if s.client.Exists(ctx, s.key(p.Snapshot.Ref.ID)).Val() != 1 {
		t.Fatal("abort deleted active")
	}
}
func TestRealRedisTwoInstancesConcurrentQuota(t *testing.T) {
	s, mac := realStore(t, 3)
	other, e := New(s.config, "", mac)
	if e != nil {
		t.Fatal(e)
	}
	defer other.Close()
	ctx := context.Background()
	owner := sha256.Sum256([]byte("same owner"))
	var wg sync.WaitGroup
	var mu sync.Mutex
	allowed := 0
	unexpected := []error{}
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			engine := s
			if n%2 != 0 {
				engine = other
			}
			snap, id := sample(engine, owner)
			_, err := engine.Prepare(ctx, snap, id, LegacyUsage{})
			mu.Lock()
			defer mu.Unlock()
			if err == nil {
				allowed++
			} else {
				var quota *QuotaError
				if !errors.As(err, &quota) {
					unexpected = append(unexpected, err)
				}
			}
		}(i)
	}
	wg.Wait()
	if allowed != 3 || len(unexpected) > 0 {
		t.Fatal("concurrent quota", allowed, unexpected)
	}
	usage, e := other.Usage(ctx, owner)
	if e != nil || usage.AccountCount != 3 {
		t.Fatal(usage, e)
	}
}

func TestRealRedisRuntimeACLAndInitializationFence(t *testing.T) {
	s, mac := realStore(t, 3)
	ctx := context.Background()
	if e := s.InitializeNew(ctx); !errors.Is(e, ErrIntegrity) {
		t.Fatal("existing namespace reinitialized", e)
	}
	foreign := "hnuhole:community_test:namespace"
	if e := s.client.Set(ctx, foreign, "admission-state", 0).Err(); e != nil {
		t.Fatal(e)
	}
	password := uuid.NewString()
	if e := s.client.Do(ctx, "ACL", "SETUSER", "snapshot_runtime", "reset", "on", ">"+password, "~"+s.Namespace()+"*", "+get", "+set", "+del", "+exists", "+pttl", "+time", "+info", "+eval", "+evalsha", "+ping", "+hello", "+client|setname").Err(); e != nil {
		t.Fatal(e)
	}
	cfg := s.config
	cfg.Redis.Username = "snapshot_runtime"
	runtime, e := New(cfg, password, mac)
	if e != nil {
		t.Fatal(e)
	}
	defer runtime.Close()
	if e = runtime.Check(ctx); e != nil {
		t.Fatal("runtime ACL startup", e)
	}
	value, id := sample(runtime, sha256.Sum256([]byte("ACL owner")))
	p, e := runtime.Prepare(ctx, value, id, LegacyUsage{})
	if e != nil {
		t.Fatal("runtime prepare", e)
	}
	if e = runtime.Publish(ctx, p); e != nil {
		t.Fatal("runtime publish", e)
	}
	if _, e = runtime.Load(ctx, value.Scope, p.Snapshot.Ref, time.Now()); e != nil {
		t.Fatal("runtime load", e)
	}
	if e = runtime.Collect(ctx); e != nil {
		t.Fatal("runtime cleanup", e)
	}
	if e = runtime.client.Get(ctx, foreign).Err(); e == nil || !strings.Contains(e.Error(), "NOPERM") {
		t.Fatal("runtime accessed admission namespace")
	}
	if s.client.Get(ctx, foreign).Val() != "admission-state" {
		t.Fatal("admission state changed")
	}
	if e = runtime.client.ConfigSet(ctx, "maxmemory", "1").Err(); e == nil {
		t.Fatal("runtime changed server configuration")
	}
	if e = runtime.InitializeNew(ctx); e == nil {
		t.Fatal("runtime gained operator SCAN")
	}
}
func TestRealRedisPartialWriteRemainsChargedUntilCompensation(t *testing.T) {
	s, _ := realStore(t, 2)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("owner"))
	snapshot, id := sample(s, owner)
	old := s.write
	s.write = redis.NewScript("#!lua flags=no-cluster\n" + commonSource + strings.Replace(writeSource, "redis.call('SET',KEYS[3],ARGV[2],'NX','PXAT',tostring(r.expires))", "error('INJECTED_DATA_WRITE_FAILURE')", 1))
	p, e := s.Prepare(ctx, snapshot, id, LegacyUsage{})
	if !errors.Is(e, ErrUnavailable) {
		t.Fatal("injected write", e)
	}
	s.write = old
	usage, e := s.Usage(ctx, owner)
	if e != nil || usage.AccountCount != 1 || s.client.Exists(ctx, s.key(p.Snapshot.Ref.ID)).Val() != 0 {
		t.Fatal("partial reservation lost", usage, e)
	}
	if e = s.Abort(ctx, p); e != nil {
		t.Fatal(e)
	}
	usage, e = s.Usage(ctx, owner)
	if e != nil || usage.AccountCount != 0 {
		t.Fatal("orphan quota", usage, e)
	}
}
func TestRealRedisMissingDataLedgerAndOOMRemainDistinct(t *testing.T) {
	s, _ := realStore(t, 2)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("owner"))
	snapshot, id := sample(s, owner)
	p, e := s.Prepare(ctx, snapshot, id, LegacyUsage{})
	if e != nil {
		t.Fatal(e)
	}
	if e = s.Publish(ctx, p); e != nil {
		t.Fatal(e)
	}
	if e = s.client.ConfigSet(ctx, "maxmemory", "1").Err(); e != nil {
		t.Fatal(e)
	}
	defer s.client.ConfigSet(ctx, "maxmemory", "64mb")
	second, key := sample(s, owner)
	_, e = s.Prepare(ctx, second, key, LegacyUsage{})
	if !errors.Is(e, ErrCapacity) {
		t.Fatal("actual OOM not capacity", e)
	}
	if _, e = s.Load(ctx, snapshot.Scope, p.Snapshot.Ref, time.Now()); e != nil {
		t.Fatal("OOM blocked read-only load", e)
	}
	if e = s.client.ConfigSet(ctx, "maxmemory", "64mb").Err(); e != nil {
		t.Fatal(e)
	}
	if e = s.client.Del(ctx, s.key(p.Snapshot.Ref.ID)).Err(); e != nil {
		t.Fatal(e)
	}
	if _, e = s.Load(ctx, snapshot.Scope, p.Snapshot.Ref, time.Now()); !errors.Is(e, ErrInvalid) {
		t.Fatal("missing data misclassified", e)
	}
	if e = s.client.Del(ctx, s.keys()[1]).Err(); e != nil {
		t.Fatal(e)
	}
	_, e = s.Prepare(ctx, second, key, LegacyUsage{})
	if !errors.Is(e, ErrIntegrity) {
		t.Fatal("lost ledger became empty budget", e)
	}
}
func TestRealRedisAbortingFenceAndExpiredPendingRecovery(t *testing.T) {
	s, _ := realStore(t, 2)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("owner"))
	snapshot, id := sample(s, owner)
	p, e := s.Prepare(ctx, snapshot, id, LegacyUsage{})
	if e != nil {
		t.Fatal(e)
	}
	v, e := s.call(ctx, true, append(s.keys(), s.key(p.Snapshot.Ref.ID)), s.preparedRequest("abort", p), nil)
	if e != nil || code(v) != "ABORTING" {
		t.Fatal(e)
	}
	if e = s.Publish(ctx, p); !errors.Is(e, ErrUnavailable) {
		t.Fatal("aborting candidate resurrected", e)
	}
	if e = s.Collect(ctx); e != nil {
		t.Fatal(e)
	}
	usage, e := s.Usage(ctx, owner)
	if e != nil || usage.AccountCount != 0 {
		t.Fatal(usage, e)
	}
	second, key := sample(s, owner)
	_, e = s.Prepare(ctx, second, key, LegacyUsage{})
	if e != nil {
		t.Fatal(e)
	}
	// One actual prepare lease, not a shortened product TTL or mocked clock.
	time.Sleep(31 * time.Second)
	if e = s.Collect(ctx); e != nil {
		t.Fatal(e)
	}
	usage, e = s.Usage(ctx, owner)
	if e != nil || usage.AccountCount != 0 {
		t.Fatal("pending not reclaimed", usage, e)
	}
}
