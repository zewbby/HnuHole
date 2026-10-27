package commentsnapshot

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

func TestRealRedisPackedLedgerRejectsCorruptPeerBeforeReuse(t *testing.T) {
	s, _ := realStore(t, 1024)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("packed validation"))
	value, request := sample(s, owner)
	p, err := s.Prepare(ctx, value, request, LegacyUsage{})
	if err != nil {
		t.Fatal(err)
	}
	if err = s.Publish(ctx, p); err != nil {
		t.Fatal(err)
	}
	peer, identity := sample(s, owner)
	q, err := s.Prepare(ctx, peer, identity, LegacyUsage{})
	if err != nil {
		t.Fatal(err)
	}
	if err = s.Publish(ctx, q); err != nil {
		t.Fatal(err)
	}
	original, err := s.client.Get(ctx, s.keys()[1]).Bytes()
	if err != nil || len(original) != 68+2*206 {
		t.Fatal(len(original), err)
	}
	if string(original[:8]) != "HNCSL02\x00" || binary.BigEndian.Uint32(original[64:68]) != 2 || original[273] != 2 || original[479] != 2 {
		t.Fatal("layout/state patch mismatch")
	}
	cases := map[string]func([]byte) []byte{
		"truncated":               func(b []byte) []byte { return b[:len(b)-1] },
		"count":                   func(b []byte) []byte { binary.BigEndian.PutUint32(b[64:68], 1); return b },
		"epoch":                   func(b []byte) []byte { b[8] ^= 1; return b },
		"policy":                  func(b []byte) []byte { b[24] ^= 1; return b },
		"header uint64 precision": func(b []byte) []byte { binary.BigEndian.PutUint64(b[56:64], 1<<53); return b },
		"duplicate UUID":          func(b []byte) []byte { copy(b[274:290], b[68:84]); return b },
		"duplicate request":       func(b []byte) []byte { copy(b[322:354], b[116:148]); return b },
		"zero owner":              func(b []byte) []byte { clear(b[290:322]); return b },
		"cost":                    func(b []byte) []byte { binary.BigEndian.PutUint32(b[450:454], 0); return b },
		"timestamp precision":     func(b []byte) []byte { binary.BigEndian.PutUint64(b[454:462], 1<<53); return b },
		"expiry precision":        func(b []byte) []byte { binary.BigEndian.PutUint64(b[462:470], 1<<53); return b },
		"lease precision":         func(b []byte) []byte { binary.BigEndian.PutUint64(b[470:478], 1<<53); return b },
		"expiry":                  func(b []byte) []byte { b[469] ^= 1; return b },
		"lease":                   func(b []byte) []byte { clear(b[470:478]); return b },
		"flags":                   func(b []byte) []byte { b[478] = 14; return b },
		"state":                   func(b []byte) []byte { b[479] = 4; return b },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			raw := mutate(append([]byte(nil), original...))
			if e := s.client.Set(ctx, s.keys()[1], raw, 31*time.Minute).Err(); e != nil {
				t.Fatal(e)
			}
			if _, _, e := s.Lookup(ctx, value.Scope, request, time.Now()); !errors.Is(e, ErrIntegrity) {
				t.Fatal("lookup", e)
			}
			if _, e := s.Prepare(ctx, value, request, LegacyUsage{}); !errors.Is(e, ErrIntegrity) {
				t.Fatal("prepare", e)
			}
			if _, e := s.Usage(ctx, owner); !errors.Is(e, ErrIntegrity) {
				t.Fatal("usage", e)
			}
			if e := s.Collect(ctx); !errors.Is(e, ErrIntegrity) {
				t.Fatal("collect", e)
			}
			if _, e := s.Load(ctx, value.Scope, p.Snapshot.Ref, time.Now()); e != nil {
				t.Fatal("immutable old read", e)
			}
		})
	}
	if err = s.client.Set(ctx, s.keys()[1], original, 31*time.Minute).Err(); err != nil {
		t.Fatal(err)
	}
	// Verify an exactly representable high uint64 boundary, then reject 2^53.
	high := append([]byte(nil), original...)
	const safe uint64 = 9007199254740991
	binary.BigEndian.PutUint64(high[56:64], safe)
	for start := 68; start < len(high); start += 206 {
		binary.BigEndian.PutUint64(high[start+180:start+188], safe-1860000)
		binary.BigEndian.PutUint64(high[start+188:start+196], safe-60000)
		binary.BigEndian.PutUint64(high[start+196:start+204], safe-1860000)
	}
	if err = s.client.Set(ctx, s.keys()[1], high, 31*time.Minute).Err(); err != nil {
		t.Fatal(err)
	}
	if u, e := s.Usage(ctx, owner); e != nil || u.AccountCount != 2 {
		t.Fatal("safe integer vector", u, e)
	}
}

func TestRealRedisDrainPreservesPendingPublicationAndOldReads(t *testing.T) {
	s, _ := realStore(t, 1024)
	ctx := context.Background()
	owner := sha256.Sum256([]byte("drain"))
	value, request := sample(s, owner)
	p, err := s.Prepare(ctx, value, request, LegacyUsage{})
	if err != nil {
		t.Fatal(err)
	}
	if err = s.Drain(ctx); err != nil {
		t.Fatal(err)
	}
	if err = s.Drain(ctx); err != nil {
		t.Fatal("idempotent drain", err)
	}
	if err = s.Publish(ctx, p); err != nil {
		t.Fatal("committed pending publication", err)
	}
	if _, err = s.Load(ctx, value.Scope, p.Snapshot.Ref, time.Now()); err != nil {
		t.Fatal(err)
	}
	other, identity := sample(s, owner)
	if _, err = s.Prepare(ctx, other, identity, LegacyUsage{}); !errors.Is(err, ErrUnavailable) {
		t.Fatal("draining accepted new preparation", err)
	}
	if _, found, e := s.Lookup(ctx, value.Scope, request, time.Now()); e != nil || !found {
		t.Fatal("draining lookup", found, e)
	}
	if e := s.Check(ctx); e != nil {
		t.Fatal(e)
	}
}

type delayedDeleteHook struct{ redis.Hook }

func (h delayedDeleteHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		if cmd.Name() == "del" {
			select {
			case <-time.After(88 * time.Millisecond):
			case <-ctx.Done():
				return ctx.Err()
			}
		}
		return next(ctx, cmd)
	}
}
func (h delayedDeleteHook) DialHook(next redis.DialHook) redis.DialHook { return next }
func (h delayedDeleteHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return next
}

func TestCleanupRuntimeEnvelopeAndEmissionConfiguration(t *testing.T) {
	c := DefaultConfig()
	c.ReadRedis = true
	c.Redis.Address = "127.0.0.1:16381"
	c.Redis.Namespace = "hnuhole:comment-snapshot:v2:test:"
	c.Redis.Epoch = "00000000-0000-4000-8000-000000000001"
	if e := c.ValidateRuntime(); e != nil {
		t.Fatal("default envelope", e)
	}
	for _, pool := range []int{1, 2, 3, 4} {
		bad := c
		bad.Redis.PoolSize = pool
		if bad.ValidateRuntime() == nil {
			t.Fatal("insufficient cleanup envelope accepted", pool)
		}
	}
	old := c
	old.Redis.Namespace = "hnuhole:comment-snapshot:v1:test:"
	if old.Validate() == nil {
		t.Fatal("old live namespace accepted")
	}
	for _, version := range []int{-1, 3} {
		bad := c
		bad.PostgresCursorVersion = version
		if bad.Validate() == nil {
			t.Fatal("unknown emission version", version)
		}
	}
}
