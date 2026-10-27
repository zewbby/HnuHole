package commentsnapshot

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

func publishLedger(t *testing.T, s *Store) ([]byte, int64) {
	t.Helper()
	ctx := context.Background()
	raw, err := s.client.Get(ctx, s.keys()[1]).Bytes()
	if err != nil {
		t.Fatal(err)
	}
	expiry, err := s.client.Do(ctx, "PEXPIRETIME", s.keys()[1]).Int64()
	if err != nil {
		t.Fatal(err)
	}
	return raw, expiry
}

func publishWriteCounts(t *testing.T, s *Store) [2]int64 {
	t.Helper()
	info, err := s.client.Info(context.Background(), "commandstats").Result()
	if err != nil {
		t.Fatal(err)
	}
	var counts [2]int64
	for i, name := range []string{"set", "setrange"} {
		for _, line := range strings.Split(info, "\n") {
			if strings.HasPrefix(line, "cmdstat_"+name+":calls=") {
				_, _ = fmt.Sscanf(line, "cmdstat_"+name+":calls=%d,", &counts[i])
			}
		}
	}
	return counts
}

func expectPublishWrites(t *testing.T, s *Store, before [2]int64, set, patch int64) {
	t.Helper()
	after := publishWriteCounts(t, s)
	if after[0]-before[0] != set || after[1]-before[1] != patch {
		t.Fatalf("SET/SETRANGE delta: got %v, want [%d %d]", [2]int64{after[0] - before[0], after[1] - before[1]}, set, patch)
	}
}

// Remove the new branch to exercise the pre-optimization v2 writer against
// exactly the same ledger, keys and handles, without a second implementation.
func legacyPublishScript(t *testing.T) *redis.Script {
	t.Helper()
	start := strings.Index(writeSource, "    -- Only patch when save")
	end := strings.Index(writeSource, "    e.stateCode=2;l.patch=e;save(l);return {'ACTIVE'}")
	if start < 0 || end <= start {
		t.Fatal("legacy Publish branch not found")
	}
	return redis.NewScript("#!lua flags=no-cluster\n" + commonSource + writeSource[:start] + writeSource[end:])
}

func TestRealRedisPublishPatchMatchesLegacyAtEveryPosition(t *testing.T) {
	s, mac := realStore(t, 4)
	legacy, err := New(s.config, "", mac)
	if err != nil {
		t.Fatal(err)
	}
	defer legacy.Close()
	legacy.write = legacyPublishScript(t)
	ctx := context.Background()
	owner := sha256.Sum256([]byte(t.Name()))
	var prepared []Prepared
	for i := 0; i < 3; i++ {
		v, id := sample(s, owner)
		p, err := legacy.Prepare(ctx, v, id, LegacyUsage{})
		if err != nil {
			t.Fatal(err)
		}
		prepared = append(prepared, p)
	}
	for _, i := range []int{1, 2, 0} { // middle, last, first, with the same v2 handles
		before, expiry := publishLedger(t, s)
		counts := publishWriteCounts(t, s)
		if err := legacy.Publish(ctx, prepared[i]); err != nil {
			t.Fatal("legacy writer", err)
		}
		want, wantExpiry := publishLedger(t, s)
		expectPublishWrites(t, s, counts, 1, 0)
		if err := s.client.Do(ctx, "SET", s.keys()[1], before, "PXAT", expiry).Err(); err != nil {
			t.Fatal(err)
		}
		counts = publishWriteCounts(t, s)
		if err := s.Publish(ctx, prepared[i]); err != nil {
			t.Fatal("patch writer", err)
		}
		got, gotExpiry := publishLedger(t, s)
		expectPublishWrites(t, s, counts, 0, 1)
		if !bytes.Equal(got, want) || gotExpiry != wantExpiry || gotExpiry != expiry {
			t.Fatal("legacy/patch bytes or absolute expiration differ")
		}
		changed := 0
		for offset := range before {
			if before[offset] != got[offset] {
				changed++
				if offset != 273+206*i || before[offset] != 1 || got[offset] != 2 {
					t.Fatal("changed a byte other than the target binary state", offset)
				}
			}
		}
		if changed != 1 {
			t.Fatal("expected one changed byte", changed)
		}
	}
	u, err := s.Usage(ctx, owner)
	if err != nil || u.AccountCount != 3 {
		t.Fatal("publication changed reservation accounting", u, err)
	}
}

func TestRealRedisPublishPatchAfterCompaction(t *testing.T) {
	s, mac := realStore(t, 2)
	legacy, err := New(s.config, "", mac)
	if err != nil {
		t.Fatal(err)
	}
	defer legacy.Close()
	legacy.write = legacyPublishScript(t)
	ctx := context.Background()
	owner := sha256.Sum256([]byte(t.Name()))
	a, key := sample(s, owner)
	first, err := legacy.Prepare(ctx, a, key, LegacyUsage{})
	if err != nil {
		t.Fatal(err)
	}
	b, key := sample(s, owner)
	second, err := s.Prepare(ctx, b, key, LegacyUsage{})
	if err != nil {
		t.Fatal(err)
	}
	if err := legacy.Abort(ctx, first); err != nil {
		t.Fatal(err)
	}
	before, expiry := publishLedger(t, s)
	if len(before) != 274 || before[273] != 1 {
		t.Fatal("pending peer not compacted to first position")
	}
	counts := publishWriteCounts(t, s)
	if err := s.Publish(ctx, second); err != nil {
		t.Fatal(err)
	}
	expectPublishWrites(t, s, counts, 0, 1)
	before[273] = 2
	after, afterExpiry := publishLedger(t, s)
	if !bytes.Equal(before, after) || expiry != afterExpiry {
		t.Fatal("compaction damaged surviving entry")
	}
	if err := legacy.Publish(ctx, second); err != nil {
		t.Fatal("old v2 writer did not recognize active patch", err)
	}
	if err := legacy.Abort(ctx, second); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Load(ctx, b.Scope, second.Snapshot.Ref, time.Now()); err != nil {
		t.Fatal("abort removed published data", err)
	}
	u, err := s.Usage(ctx, owner)
	if err != nil || u.AccountCount != 1 {
		t.Fatal("compaction/publication accounting", u, err)
	}
}

func TestRealRedisPublishPatchFallsBackForWatermarkAndExpiry(t *testing.T) {
	for _, name := range []string{"control-ahead", "ledger-ahead", "short-expiry", "long-expiry", "persistent", "large-exact-header"} {
		t.Run(name, func(t *testing.T) {
			s, _ := realStore(t, 2)
			ctx := context.Background()
			v, id := sample(s, sha256.Sum256([]byte(t.Name())))
			p, err := s.Prepare(ctx, v, id, LegacyUsage{})
			if err != nil {
				t.Fatal(err)
			}
			raw, h := publishLedger(t, s)
			controlRaw, err := s.client.Get(ctx, s.keys()[0]).Bytes()
			if err != nil {
				t.Fatal(err)
			}
			var control map[string]any
			if err := json.Unmarshal(controlRaw, &control); err != nil {
				t.Fatal(err)
			}
			want := h
			switch name {
			case "control-ahead":
				want = h + 1000
				control["until_ms"] = want
			case "ledger-ahead":
				control["until_ms"] = h - 1000
			case "short-expiry":
				if err := s.client.PExpire(ctx, s.keys()[1], time.Minute).Err(); err != nil {
					t.Fatal(err)
				}
			case "long-expiry":
				if err := s.client.Do(ctx, "PEXPIREAT", s.keys()[1], h+1000).Err(); err != nil {
					t.Fatal(err)
				}
			case "persistent":
				if err := s.client.Persist(ctx, s.keys()[1]).Err(); err != nil {
					t.Fatal(err)
				}
			case "large-exact-header":
				want = 9007199254740991
				binary.BigEndian.PutUint64(raw[56:64], uint64(want))
				control["until_ms"] = want
				if err := s.client.Do(ctx, "SET", s.keys()[1], raw, "PXAT", want).Err(); err != nil {
					t.Fatal(err)
				}
			}
			controlRaw, err = json.Marshal(control)
			if err != nil {
				t.Fatal(err)
			}
			if err := s.client.Set(ctx, s.keys()[0], controlRaw, 0).Err(); err != nil {
				t.Fatal(err)
			}
			counts := publishWriteCounts(t, s)
			err = s.Publish(ctx, p)
			if name == "large-exact-header" {
				if !errors.Is(err, ErrUnavailable) {
					t.Fatal("original SET must still reject scientific-notation expiry", err)
				}
			} else if err != nil {
				t.Fatal(err)
			}
			expectPublishWrites(t, s, counts, 1, 0)
			after, afterExpiry := publishLedger(t, s)
			if name != "large-exact-header" {
				binary.BigEndian.PutUint64(raw[56:64], uint64(want))
				raw[273] = 2
			}
			if !bytes.Equal(raw, after) || afterExpiry != want {
				t.Fatal("fallback did not preserve original save result", afterExpiry, want)
			}
		})
	}
}

func TestRealRedisPublishPatchACLAndOOM(t *testing.T) {
	s, mac := realStore(t, 8)
	ctx := context.Background()
	password := "fixture-only-publish-password"
	args := []any{"ACL", "SETUSER", "publish_runtime", "reset", "on", ">" + password, "~" + s.Namespace() + "*", "+get", "+set", "+del", "+exists", "+pttl", "+time", "+info", "+eval", "+evalsha", "+ping", "+hello", "+client|setname"}
	if err := s.client.Do(ctx, args...).Err(); err != nil {
		t.Fatal(err)
	}
	cfg := s.config
	cfg.Redis.Username = "publish_runtime"
	runtime, err := New(cfg, password, mac)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	for _, name := range []string{"old-acl", "no-setrange", "no-pexpiretime", "full-acl", "revoked-set", "oom"} {
		t.Run(name, func(t *testing.T) {
			if err := s.client.Do(ctx, "ACL", "SETUSER", "publish_runtime", "+set", "+setrange", "+pexpiretime").Err(); err != nil {
				t.Fatal(err)
			}
			v, id := sample(runtime, sha256.Sum256([]byte(t.Name())))
			p, err := runtime.Prepare(ctx, v, id, LegacyUsage{})
			if err != nil {
				t.Fatal(err)
			}
			deny := []any{"ACL", "SETUSER", "publish_runtime"}
			switch name {
			case "old-acl":
				deny = append(deny, "-setrange", "-pexpiretime")
			case "no-setrange":
				deny = append(deny, "-setrange")
			case "no-pexpiretime":
				deny = append(deny, "-pexpiretime")
			case "revoked-set":
				deny = append(deny, "-set")
			}
			if len(deny) > 3 {
				if err := s.client.Do(ctx, deny...).Err(); err != nil {
					t.Fatal(err)
				}
			}
			before, expiry := publishLedger(t, s)
			counts := publishWriteCounts(t, s)
			if name == "oom" {
				if err := s.client.ConfigSet(ctx, "maxmemory", "1").Err(); err != nil {
					t.Fatal(err)
				}
				defer s.client.ConfigSet(ctx, "maxmemory", "64mb")
			}
			err = runtime.Publish(ctx, p)
			switch name {
			case "revoked-set", "oom":
				want := ErrUnavailable
				if name == "oom" {
					want = ErrCapacity
				}
				if !errors.Is(err, want) {
					t.Fatal("denied publication", err)
				}
				expectPublishWrites(t, s, counts, 0, 0)
			default:
				if err != nil {
					t.Fatal(err)
				}
				for offset := 68; offset < len(before); offset += 206 {
					if bytes.Equal(before[offset:offset+16], p.Snapshot.Ref.ID[:]) {
						before[offset+205] = 2
					}
				}
				if name == "full-acl" {
					expectPublishWrites(t, s, counts, 0, 1)
				} else {
					expectPublishWrites(t, s, counts, 1, 0)
				}
			}
			after, afterExpiry := publishLedger(t, s)
			if !bytes.Equal(before, after) || expiry != afterExpiry {
				t.Fatal("ACL/OOM changed unintended state or expiry")
			}
		})
	}
}

func TestRealRedisPublishPatchRetainsValidationAndPendingFences(t *testing.T) {
	for _, name := range []string{"corrupt-peer", "expired-lease", "aborting", "missing-data", "wrong-payload", "wrong-owner", "wrong-token", "wrong-digest", "old-json"} {
		t.Run(name, func(t *testing.T) {
			s, _ := realStore(t, 2)
			ctx := context.Background()
			v, id := sample(s, sha256.Sum256([]byte(t.Name())))
			p, err := s.Prepare(ctx, v, id, LegacyUsage{})
			if err != nil {
				t.Fatal(err)
			}
			wantError := ErrUnavailable
			switch name {
			case "corrupt-peer":
				peer, key := sample(s, v.Scope.Owner)
				if _, err := s.Prepare(ctx, peer, key, LegacyUsage{}); err != nil {
					t.Fatal(err)
				}
				raw, expiry := publishLedger(t, s)
				raw[479] = 4
				if err := s.client.Do(ctx, "SET", s.keys()[1], raw, "PXAT", expiry).Err(); err != nil {
					t.Fatal(err)
				}
				wantError = ErrIntegrity
			case "expired-lease":
				raw, expiry := publishLedger(t, s)
				binary.BigEndian.PutUint64(raw[264:272], uint64(p.Snapshot.Created.UnixMilli()))
				if err := s.client.Do(ctx, "SET", s.keys()[1], raw, "PXAT", expiry).Err(); err != nil {
					t.Fatal(err)
				}
			case "aborting":
				if _, err := s.call(ctx, true, append(s.keys(), s.key(p.Snapshot.Ref.ID)), s.preparedRequest("abort", p), nil); err != nil {
					t.Fatal(err)
				}
			case "missing-data":
				if err := s.client.Del(ctx, s.key(p.Snapshot.Ref.ID)).Err(); err != nil {
					t.Fatal(err)
				}
			case "wrong-payload":
				p.Payload = append([]byte(nil), p.Payload...)
				p.Payload[len(p.Payload)-1] ^= 1
			case "wrong-owner":
				p.Snapshot.Scope.Owner = sha256.Sum256([]byte("another owner"))
			case "wrong-token":
				p.Token = base64.RawURLEncoding.EncodeToString(make([]byte, 32))
			case "wrong-digest":
				p.Digest = strings.Repeat("0", 64)
			case "old-json":
				if err := s.client.Set(ctx, s.keys()[1], `{"entries":{}}`, time.Minute).Err(); err != nil {
					t.Fatal(err)
				}
				wantError = ErrIntegrity
			}
			before, expiry := publishLedger(t, s)
			counts := publishWriteCounts(t, s)
			if err := s.Publish(ctx, p); !errors.Is(err, wantError) {
				t.Fatal("invalid publication accepted or misclassified", err)
			}
			expectPublishWrites(t, s, counts, 0, 0)
			after, afterExpiry := publishLedger(t, s)
			if !bytes.Equal(before, after) || expiry != afterExpiry {
				t.Fatal("rejected Publish mutated ledger")
			}
		})
	}
}

type lostPublishResponseHook struct {
	redis.Hook
	before  bool
	dropped atomic.Bool
}

func (h *lostPublishResponseHook) DialHook(next redis.DialHook) redis.DialHook { return next }
func (h *lostPublishResponseHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return next
}
func (h *lostPublishResponseHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		publish := false
		if cmd.Name() == "eval" || cmd.Name() == "evalsha" {
			for _, arg := range cmd.Args() {
				if value, ok := arg.(string); ok && strings.Contains(value, `"op":"publish"`) {
					publish = true
				}
			}
		}
		if publish && h.before && h.dropped.CompareAndSwap(false, true) {
			return errors.New("fixture disconnected before Publish")
		}
		err := next(ctx, cmd)
		if publish && err == nil && !h.before && h.dropped.CompareAndSwap(false, true) {
			return errors.New("fixture lost successful Publish reply")
		}
		return err
	}
}

func TestRealRedisPublishPatchUnknownOutcomeProbe(t *testing.T) {
	for _, before := range []bool{true, false} {
		t.Run(fmt.Sprintf("before-write=%v", before), func(t *testing.T) {
			s, _ := realStore(t, 2)
			ctx := context.Background()
			owner := sha256.Sum256([]byte(t.Name()))
			v, id := sample(s, owner)
			p, err := s.Prepare(ctx, v, id, LegacyUsage{})
			if err != nil {
				t.Fatal(err)
			}
			hook := &lostPublishResponseHook{before: before}
			s.client.AddHook(hook)
			counts := publishWriteCounts(t, s)
			err = s.Publish(ctx, p)
			if !hook.dropped.Load() {
				t.Fatal("fault was not injected")
			}
			if before {
				if !errors.Is(err, ErrUnavailable) {
					t.Fatal("unpublished state accepted by probe", err)
				}
				expectPublishWrites(t, s, counts, 0, 0)
			} else {
				if err != nil {
					t.Fatal("probe lost acknowledged active state", err)
				}
				expectPublishWrites(t, s, counts, 0, 1)
			}
			raw, _ := publishLedger(t, s)
			want := byte(2)
			if before {
				want = 1
			}
			if raw[273] != want {
				t.Fatal("unexpected state", raw[273])
			}
			u, err := s.Usage(ctx, owner)
			if err != nil || u.AccountCount != 1 {
				t.Fatal("unknown outcome released reservation", u, err)
			}
		})
	}
}

func TestRealRedisPublishPatchAOFReplay(t *testing.T) {
	s, _ := realStore(t, 2)
	ctx := context.Background()
	for _, setting := range [][2]string{{"appendfsync", "always"}, {"appendonly", "yes"}} {
		if err := s.client.ConfigSet(ctx, setting[0], setting[1]).Err(); err != nil {
			t.Fatal(err)
		}
	}
	ready := false
	for i := 0; i < 200; i++ {
		info, err := s.client.Info(ctx, "persistence").Result()
		if err == nil && strings.Contains(info, "aof_rewrite_in_progress:0\r\n") && strings.Contains(info, "aof_rewrite_scheduled:0\r\n") && strings.Contains(info, "aof_last_bgrewrite_status:ok\r\n") {
			ready = true
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !ready {
		t.Fatal("owned AOF initialization did not finish")
	}
	v, id := sample(s, sha256.Sum256([]byte(t.Name())))
	p, err := s.Prepare(ctx, v, id, LegacyUsage{})
	if err != nil {
		t.Fatal(err)
	}
	counts := publishWriteCounts(t, s)
	if err := s.Publish(ctx, p); err != nil {
		t.Fatal(err)
	}
	expectPublishWrites(t, s, counts, 0, 1)
	want, expiry := publishLedger(t, s)
	dir, err := s.client.ConfigGet(ctx, "dir").Result()
	if err != nil {
		t.Fatal(err)
	}
	if err := s.client.ShutdownNoSave(ctx).Err(); err != nil {
		t.Fatal(err)
	}
	_, port, err := net.SplitHostPort(s.config.Redis.Address)
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(os.Getenv("COMMENT_SNAPSHOT_REDIS_SERVER"), "--bind", "127.0.0.1", "--port", port, "--save", "", "--appendonly", "yes", "--appendfsync", "always", "--maxmemory", "64mb", "--maxmemory-policy", "noeviction", "--dir", dir["dir"], "--logfile", dir["dir"]+"/aof-replay.log")
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	ready = false
	for i := 0; i < 100; i++ {
		info, err := s.client.Info(ctx, "server").Result()
		if err == nil && strings.Contains(info, "process_id:"+strconv.Itoa(cmd.Process.Pid)+"\r\n") {
			ready = true
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !ready {
		t.Fatal("owned AOF replay process not ready")
	}
	got, gotExpiry := publishLedger(t, s)
	if !bytes.Equal(got, want) || gotExpiry != expiry {
		t.Fatal("AOF replay changed ledger or fixed expiry")
	}
	if err := s.Publish(ctx, p); err != nil {
		t.Fatal("replayed active publication", err)
	}
	if _, err := s.Load(ctx, v.Scope, p.Snapshot.Ref, time.Now()); err != nil {
		t.Fatal("replayed data", err)
	}
}
