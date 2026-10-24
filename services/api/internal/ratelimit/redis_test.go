package ratelimit

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// This fixture owns a real isolated Redis process. The namespace adapter here
// is an explicit unit fixture; it is NOT evidence of PostgreSQL/Gate recovery.
type memoryNamespace struct {
	mu sync.Mutex
	n  Namespace
}

func (m *memoryNamespace) Load(context.Context) (Namespace, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.n, nil
}
func (m *memoryNamespace) Recover(_ context.Context, g int64, id string, d time.Duration) (Namespace, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.n.Generation == g && (m.n.State == "READY" || m.n.RunID != id) {
		m.n = Namespace{Generation: g + 1, RunID: id, State: "RECOVERING", BarrierUntil: time.Now().Add(d), PolicyHash: m.n.PolicyHash, RecoveryWindow: m.n.RecoveryWindow}
	}
	return m.n, nil
}
func (m *memoryNamespace) Activate(_ context.Context, g int64, id string) (Namespace, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.n.Generation == g && m.n.RunID == id && !time.Now().Before(m.n.BarrierUntil) {
		m.n.State = "READY"
	}
	return m.n, nil
}

func redisFixture(t *testing.T, edit func(*Config)) (*Controller, *memoryNamespace) {
	t.Helper()
	binary := os.Getenv("HNULIMIT_REDIS_SERVER")
	if binary == "" {
		t.Skip("owned Redis binary not supplied; not real-Redis acceptance")
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	dir := t.TempDir()
	command := exec.Command(binary, "--bind", "127.0.0.1", "--port", strconv.Itoa(port), "--save", "", "--appendonly", "no", "--maxmemory", "64mb", "--maxmemory-policy", "noeviction", "--dir", dir, "--logfile", filepath.Join(dir, "redis.log"))
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	if err = command.Start(); err != nil {
		t.Fatal("owned Redis cannot start:", err)
	}
	t.Cleanup(func() { _ = command.Process.Kill(); _ = command.Wait() })
	config := TrialConfig(fmt.Sprintf("127.0.0.1:%d", port), "isolated_unit")
	config.DeadlineMilliseconds = 500
	config.DedupSeconds = 2
	config.ReadSeconds = 1
	for i := range config.Rules {
		config.Rules[i].Mode = Off
	}
	if edit != nil {
		edit(&config)
	}
	store := &memoryNamespace{}
	engine, err := New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = engine.Close() })
	ctx := context.Background()
	var info string
	for i := 0; i < 100; i++ {
		info, err = engine.client.Info(ctx, "server").Result()
		if err == nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if err != nil {
		t.Fatal("owned Redis not ready")
	}
	store.n = Namespace{Generation: 1, RunID: runID(info), State: "READY", BarrierUntil: time.Now(), PolicyHash: engine.PolicyHash(), RecoveryWindow: engine.RecoveryWindow()}
	if err = engine.InitializeRedis(ctx, store.n); err != nil {
		t.Fatal(err)
	}
	return engine, store
}
func testRule(c *Config, action string, limit, window int64) {
	for i := range c.Rules {
		if c.Rules[i].Action == action {
			c.Rules[i].Mode = Enforce
			c.Rules[i].Bucket = nil
			c.Rules[i].Windows = []Window{{window, limit}}
		}
	}
}
func testProof(i int) Proof {
	return Proof{Operation: fmt.Sprintf("%064x", i), Fingerprint: strings.Repeat("b", 64), Nonce: fmt.Sprintf("%032x", i), Deadline: time.Now().Add(time.Minute).UnixMilli()}
}

const testSubject = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

func TestRealRedisSharedConcurrentReplayConflictAndAPIClientRestart(t *testing.T) {
	engine, store := redisFixture(t, func(c *Config) { testRule(c, "post.create", 5, 5000) })
	second, err := New(engine.config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	var allowed atomic.Int64
	var group sync.WaitGroup
	var mu sync.Mutex
	accepted := []int{}
	for i := 1; i <= 20; i++ {
		group.Add(1)
		go func(i int) {
			defer group.Done()
			client := engine
			if i%2 == 0 {
				client = second
			}
			d, e := client.Admit(context.Background(), testSubject, []Charge{{"post.create", 1}}, testProof(i))
			if e != nil {
				t.Error(e)
				return
			}
			if d.Allowed {
				allowed.Add(1)
				mu.Lock()
				accepted = append(accepted, i)
				mu.Unlock()
			} else if d.RetryAfter < 1 {
				t.Error("missing bounded wait")
			}
		}(i)
	}
	group.Wait()
	if allowed.Load() != 5 {
		t.Fatalf("two clients admitted %d instead of 5", allowed.Load())
	}
	proof := testProof(accepted[0])
	d, err := second.Admit(context.Background(), testSubject, []Charge{{"post.create", 1}}, proof)
	if err != nil || !d.Replay {
		t.Fatal("exhausted budget lost replay", d, err)
	}
	proof.Fingerprint = strings.Repeat("c", 64)
	_, err = second.Admit(context.Background(), testSubject, []Charge{{"post.create", 1}}, proof)
	if !errors.Is(err, ErrConflict) {
		t.Fatal("same key changed content did not conflict", err)
	}
	second.Close()
	second, err = New(engine.config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	d, err = second.Admit(context.Background(), testSubject, []Charge{{"post.create", 1}}, testProof(99))
	if err != nil || d.Allowed {
		t.Fatal("API client restart reset shared quota", d, err)
	}
}

func TestRealRedisTrustedConfirmReleasesOnlyHotDedupCapacity(t *testing.T) {
	engine, _ := redisFixture(t, func(c *Config) { c.MaxDedup = 1; testRule(c, "post.create", 3, 5000) })
	proof := testProof(1)
	d, err := engine.Admit(context.Background(), testSubject, []Charge{{"post.create", 1}}, proof)
	if err != nil || !d.Allowed {
		t.Fatal(d, err)
	}
	proof.Nonce = "" // Trusted permanent-receipt confirmation has no transient nonce.
	if err = engine.Confirm(context.Background(), testSubject, proof); err != nil {
		t.Fatal("permanent receipt confirmation failed", err)
	}
	d, err = engine.Admit(context.Background(), testSubject, []Charge{{"post.create", 1}}, testProof(2))
	if err != nil || !d.Allowed {
		t.Fatal("hot marker was not removed", d, err)
	}
	proof = testProof(2)
	proof.Fingerprint = strings.Repeat("d", 64)
	if err = engine.Confirm(context.Background(), testSubject, proof); !errors.Is(err, ErrConflict) {
		t.Fatal("confirmation erased another fingerprint", err)
	}
}

func TestRealRedisJointDenyDoesNotPartiallyCharge(t *testing.T) {
	engine, _ := redisFixture(t, func(c *Config) { testRule(c, "dm.send", 1, 5000); testRule(c, "dm.conversation.create", 1, 5000) })
	ctx := context.Background()
	if d, err := engine.Admit(ctx, testSubject, []Charge{{"dm.conversation.create", 1}}, Proof{}); err != nil || !d.Allowed {
		t.Fatal(d, err)
	}
	if d, err := engine.Admit(ctx, testSubject, []Charge{{"dm.send", 1}, {"dm.conversation.create", 1}}, testProof(1)); err != nil || d.Allowed {
		t.Fatal("joint request not denied", d, err)
	}
	if d, err := engine.Admit(ctx, testSubject, []Charge{{"dm.send", 1}}, testProof(2)); err != nil || !d.Allowed {
		t.Fatal("denial partially spent send quota", d, err)
	}
}

func TestRealRedisTinyByteBudgetPartialReservationAndRetransmission(t *testing.T) {
	engine, _ := redisFixture(t, func(c *Config) { testRule(c, "upload.attempt", 10, 5000); testRule(c, "upload.bytes", 1024, 5000) })
	ctx := context.Background()
	data, err := engine.ReadBody(ctx, testSubject, bytes.NewReader(make([]byte, 128)), 10240, -1)
	if err != nil || len(data) != 128 {
		t.Fatal("small unknown-length body rejected by 64KiB quantum", len(data), err)
	}
	data, err = engine.ReadBody(ctx, testSubject, bytes.NewReader(make([]byte, 896)), 10240, 896)
	if err != nil || len(data) != 896 {
		t.Fatal("unused reservation not released", len(data), err)
	}
	_, err = engine.ReadBody(ctx, testSubject, bytes.NewReader([]byte{1}), 10240, 1)
	var limited *Limited
	if !errors.As(err, &limited) {
		t.Fatal("retransmitted physical byte was free", err)
	}
}

func TestRealRedisMissingSubjectCreatesRecoveryBarrier(t *testing.T) {
	engine, store := redisFixture(t, func(c *Config) { testRule(c, "post.create", 3, 100) })
	ctx := context.Background()
	if d, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(1)); err != nil || !d.Allowed {
		t.Fatal(d, err)
	}
	if err := engine.client.Del(ctx, "hnuhole:isolated_unit:g1:s:"+testSubject).Err(); err != nil {
		t.Fatal(err)
	}
	_, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(2))
	if !errors.Is(err, ErrLost) {
		t.Fatal("missing live state treated as empty", err)
	}
	ns, _ := store.Load(ctx)
	if ns.State != "RECOVERING" || ns.Generation != 2 {
		t.Fatal("recovery generation not persisted", ns)
	}
	if engine.CanDBFallback(ctx) {
		t.Fatal("recovery barrier allowed unaccounted SQL writes")
	}
	_, err = engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(3))
	if err == nil {
		t.Fatal("barrier did not block high-cost writes")
	}
}

func TestRealRedisMixedUploadModeDoesNotLeakCompletedReservations(t *testing.T) {
	engine, _ := redisFixture(t, func(c *Config) { c.MaxReserves = 2; testRule(c, "upload.attempt", 10, 5000) })
	for i := 0; i < 5; i++ {
		data, err := engine.ReadBody(context.Background(), testSubject, bytes.NewReader([]byte{1, 2, 3}), 1024, 3)
		if err != nil || len(data) != 3 {
			t.Fatal("bytes-off leaked a reservation slot", i, len(data), err)
		}
	}
}

func TestRealRedisObserveAndOffDoNotAddFaultRejection(t *testing.T) {
	for _, mode := range []Mode{Observe, Off} {
		t.Run(string(mode), func(t *testing.T) {
			engine, _ := redisFixture(t, func(c *Config) {
				for i := range c.Rules {
					c.Rules[i].Mode = mode
				}
			})
			engine.client.Close() // Known component outage; no user violation or new503.
			data, err := engine.ReadBody(context.Background(), testSubject, bytes.NewReader([]byte{1}), 1024, 1)
			if err != nil || len(data) != 1 {
				t.Fatal("non-enforcing mode rejected component outage", err)
			}
		})
	}
}

func TestRealRedisOOMTimeoutFlushAndRecovery(t *testing.T) {
	t.Run("actual-oom", func(t *testing.T) {
		engine, _ := redisFixture(t, func(c *Config) { testRule(c, "post.create", 5, 100) })
		ctx := context.Background()
		if err := engine.client.ConfigSet(ctx, "maxmemory", "1").Err(); err != nil {
			t.Fatal(err)
		}
		defer engine.client.ConfigSet(ctx, "maxmemory", "64mb")
		// Assert the actual Redis fixture is in write-OOM before exercising
		// our Lua path; a configured byte limit alone is not evidence of OOM.
		if e := engine.client.Set(ctx, "owned-oom-probe", "x", time.Minute).Err(); e == nil || !strings.Contains(e.Error(), "OOM") {
			t.Fatal("owned Redis did not enter actual write OOM", e)
		}
		_, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(1))
		if !errors.Is(err, ErrUnavailable) {
			t.Fatal("real OOM became quota429/allow", err)
		}
	})
	t.Run("bounded-timeout", func(t *testing.T) {
		engine, _ := redisFixture(t, func(c *Config) { c.DeadlineMilliseconds = 50; testRule(c, "post.create", 5, 100) })
		ctx := context.Background()
		if err := engine.client.Do(ctx, "CLIENT", "PAUSE", 500, "ALL").Err(); err != nil {
			t.Fatal(err)
		}
		start := time.Now()
		_, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(1))
		if !errors.Is(err, ErrUnavailable) || time.Since(start) > 300*time.Millisecond {
			t.Fatal("timeout not bounded or was retried", err, time.Since(start))
		}
	})
	t.Run("flush-and-auto-recover", func(t *testing.T) {
		engine, store := redisFixture(t, func(c *Config) { c.DedupSeconds = 1; testRule(c, "post.create", 5, 100) })
		ctx := context.Background()
		if d, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(1)); err != nil || !d.Allowed {
			t.Fatal(d, err)
		}
		if err := engine.client.FlushDB(ctx).Err(); err != nil {
			t.Fatal(err)
		}
		_, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(2))
		if !errors.Is(err, ErrLost) {
			t.Fatal("flush silently reset shared quotas", err)
		}
		ns, _ := store.Load(ctx)
		wait := time.Until(ns.BarrierUntil) + 30*time.Millisecond
		if wait > 3*time.Second {
			t.Fatal("inactive rules unexpectedly stretched recovery", wait)
		}
		time.Sleep(wait)
		d, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(3))
		if err != nil || !d.Allowed {
			t.Fatal("healthy Redis failed to automatically recover after barrier", d, err)
		}
		ns, _ = store.Load(ctx)
		if ns.State != "READY" || ns.Generation != 2 {
			t.Fatal("recovery lost generation", ns)
		}
	})
}

type delayedBytes struct {
	delay time.Duration
	data  []byte
}

func (r *delayedBytes) Read(p []byte) (int, error) {
	time.Sleep(r.delay)
	n := copy(p, r.data)
	r.data = r.data[n:]
	return n, io.ErrUnexpectedEOF
}
func TestRealRedisLateReadSettlesActualAndRejectsBusiness(t *testing.T) {
	engine, _ := redisFixture(t, func(c *Config) { testRule(c, "upload.attempt", 10, 5000); testRule(c, "upload.bytes", 64, 100) })
	reader := &delayedBytes{delay: 1100 * time.Millisecond, data: make([]byte, 32)}
	data, err := engine.ReadBody(context.Background(), testSubject, reader, 1024, 64)
	if !errors.Is(err, ErrUnavailable) || len(data) != 0 {
		t.Fatal("read exceeded real deadline but reached decoder", len(data), err)
	}
	// Reservation event is older than its 100ms window, but the actual n remains
	// charged at settlement even when n>0 accompanies an error.
	d, err := engine.BeginTransfer(context.Background(), testSubject, "next", 64)
	if err != nil || !d.Allowed || d.Reserved != 32 {
		t.Fatal("late n/error escaped byte accounting", d, err)
	}
	if err = engine.SettleChunk(context.Background(), testSubject, "next", 0); err != nil {
		t.Fatal(err)
	}
}
func TestRealRedisStalePreparedProofCannotTouchNewNamespace(t *testing.T) {
	engine, store := redisFixture(t, func(c *Config) { c.DedupSeconds = 86400; testRule(c, "post.create", 3, 100) })
	if engine.RecoveryWindow() > 2200*time.Millisecond {
		t.Fatal("dedup retention inflated quota recovery", engine.RecoveryWindow())
	}
	ctx := context.Background()
	proof := testProof(1)
	proof.ExpectedGeneration = 1
	if d, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, proof); err != nil || !d.Allowed {
		t.Fatal(d, err)
	}
	store.mu.Lock()
	store.n.Generation = 2
	store.n.State = "READY"
	store.mu.Unlock()
	_, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, proof)
	if !errors.Is(err, ErrStaleProof) {
		t.Fatal("old prepared proof silently charged a new epoch", err)
	}
	ns, _ := store.Load(ctx)
	if ns.Generation != 2 || ns.State != "READY" {
		t.Fatal("stale proof initiated another global recovery", ns)
	}
}

func TestRealRedisCorruptStateIsLossNotFallback(t *testing.T) {
	for _, kind := range []string{"subject-type", "directory-type", "malformed-json"} {
		t.Run(kind, func(t *testing.T) {
			engine, store := redisFixture(t, func(c *Config) { testRule(c, "post.create", 3, 100) })
			ctx := context.Background()
			if _, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(1)); err != nil {
				t.Fatal(err)
			}
			state := "hnuhole:isolated_unit:g1:s:" + testSubject
			directory := "hnuhole:isolated_unit:g1:subjects"
			switch kind {
			case "subject-type":
				engine.client.Del(ctx, state)
				engine.client.LPush(ctx, state, "broken")
			case "directory-type":
				engine.client.Del(ctx, directory)
				engine.client.Set(ctx, directory, "broken", 0)
			case "malformed-json":
				engine.client.Set(ctx, state, `{"generation":1,"incarnation":"bad","actions":null,"dedup":{},"reserves":{}}`, time.Minute)
			}
			_, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(2))
			if !errors.Is(err, ErrLost) {
				t.Fatal("corruption treated as ordinary temporary failure", err)
			}
			ns, _ := store.Load(ctx)
			if ns.State != "RECOVERING" || engine.CanDBFallback(ctx) {
				t.Fatal("corruption did not close unaccounted fallback")
			}
		})
	}
}

func TestRealRedisConcurrentReservationBoundedTTLAndPrivateState(t *testing.T) {
	engine, _ := redisFixture(t, func(c *Config) {
		c.MaxReserves = 2
		c.MaxSubjects = 2
		testRule(c, "upload.attempt", 10, 5000)
		testRule(c, "upload.bytes", 100, 5000)
	})
	ctx := context.Background()
	key := [32]byte{71}
	subject := Digest(key, "community", "account", "private-account-id")
	if subject == Digest(key, "verifier", "account", "private-account-id") {
		t.Fatal("C/V digest domains overlap")
	}
	type admitted struct {
		id       string
		decision Decision
		err      error
	}
	results := make(chan admitted, 2)
	for _, id := range []string{"physical-one", "physical-two"} {
		go func(id string) { d, e := engine.BeginTransfer(ctx, subject, id, 80); results <- admitted{id, d, e} }(id)
	}
	a, b := <-results, <-results
	if a.err != nil || b.err != nil || !a.decision.Allowed || !b.decision.Allowed || a.decision.Reserved+b.decision.Reserved != 100 {
		t.Fatal("concurrent reservations overspent or lost partial allowance", a.decision, b.decision, a.err, b.err)
	}
	d, err := engine.BeginTransfer(ctx, subject, "physical-three", 1)
	if err != nil || d.Allowed {
		t.Fatal("reserved bytes were available to another reader", d, err)
	}
	if err = engine.SettleChunk(ctx, subject, a.id, a.decision.Reserved/2); err != nil {
		t.Fatal(err)
	}
	if err = engine.SettleChunk(ctx, subject, b.id, b.decision.Reserved/2); err != nil {
		t.Fatal(err)
	}
	stateKey := "hnuhole:isolated_unit:g1:s:" + subject
	raw, err := engine.client.Get(ctx, stateKey).Bytes()
	if err != nil {
		t.Fatal(err)
	}
	for _, private := range []string{"private-account-id", "synthetic-body-text", "student@hainanu.edu.cn", "session-token-value", "otp-code-value"} {
		if strings.Contains(string(raw), private) || strings.Contains(stateKey, private) {
			t.Fatal("private state retained unapproved plaintext")
		}
	}
	var state struct {
		Reserves map[string]any `json:"reserves"`
		Actions  map[string]map[string][]struct {
			Cost int64 `json:"cost"`
		} `json:"actions"`
	}
	if json.Unmarshal(raw, &state) != nil || len(state.Reserves) != 0 {
		t.Fatal("completed transfers retained reservations")
	}
	attempts := int64(0)
	for _, event := range state.Actions["upload.attempt"]["1"] {
		attempts += event.Cost
	}
	if attempts != 2 {
		t.Fatal("joint denied transfer partially charged attempt", attempts)
	}
	ttl, err := engine.client.PTTL(ctx, stateKey).Result()
	if err != nil || ttl <= 0 || ttl > engine.retention {
		t.Fatal("subject TTL is absent or unbounded", ttl, err)
	}
	if _, err = engine.Admit(ctx, Digest(key, "community", "account", "second"), []Charge{{"upload.attempt", 1}}, Proof{}); err != nil {
		t.Fatal(err)
	}
	_, err = engine.Admit(ctx, Digest(key, "community", "account", "third"), []Charge{{"upload.attempt", 1}}, Proof{})
	if !errors.Is(err, ErrCapacity) {
		t.Fatal("subject directory capacity is unbounded", err)
	}
	if n, err := engine.client.ZCard(ctx, "hnuhole:isolated_unit:g1:subjects").Result(); err != nil || n != 2 {
		t.Fatal("subject cap check mutated directory", n, err)
	}
}

func TestRealRedisMixedObserveCapacityIsIndependent(t *testing.T) {
	for _, bytesMode := range []Mode{Observe, Enforce} {
		t.Run(string(bytesMode), func(t *testing.T) {
			engine, _ := redisFixture(t, func(c *Config) {
				c.MaxEvents = 1
				c.MaxReserves = 1
				testRule(c, "upload.attempt", 10, 1000)
				testRule(c, "upload.bytes", 1024, 1000)
				for i := range c.Rules {
					if c.Rules[i].Action == "upload.bytes" {
						c.Rules[i].Mode = bytesMode
					} else if c.Rules[i].Action == "upload.attempt" && bytesMode == Enforce {
						c.Rules[i].Mode = Observe
					}
				}
			})
			ctx := context.Background()
			d, err := engine.BeginTransfer(ctx, testSubject, "mixed", 1)
			if err != nil || !d.Allowed || d.Reserved != 1 {
				t.Fatal("observe event contaminated hard capacity", d, err)
			}
			if err = engine.SettleChunk(ctx, testSubject, "mixed", 1); err != nil {
				t.Fatal("observe settlement blocked enforced action", err)
			}
		})
	}
	engine, store := redisFixture(t, func(c *Config) {
		c.MaxEvents = 1
		c.MaxStateBytes = 1024
		testRule(c, "upload.attempt", 10, 1000)
		testRule(c, "upload.bytes", 1024, 1000)
		for i := range c.Rules {
			if c.Rules[i].Action == "upload.bytes" {
				c.Rules[i].Mode = Observe
			}
		}
	})
	ctx := context.Background()
	observer := "hnuhole:isolated_unit:g1:observe:s:" + testSubject
	// A full/corrupt historical observer lane cannot close the real namespace.
	engine.client.Set(ctx, observer, strings.Repeat("observer-only", 100), time.Minute)
	d, err := engine.BeginTransfer(ctx, testSubject, "after-observer", 1)
	if err != nil || !d.Allowed {
		t.Fatal("observer-only state blocked enforced action", d, err)
	}
	if err = engine.SettleChunk(ctx, testSubject, "after-observer", 0); err != nil {
		t.Fatal(err)
	}
	ns, _ := store.Load(ctx)
	if ns.State != "READY" || ns.Generation != 1 {
		t.Fatal("observer lane loss restarted global recovery", ns)
	}
}
func TestRealRedisGlobalEventCapAndColdExpiry(t *testing.T) {
	engine, _ := redisFixture(t, func(c *Config) {
		c.MaxEvents = 1
		testRule(c, "post.create", 10, 100)
		testRule(c, "comment.publish", 10, 100)
	})
	ctx := context.Background()
	if _, err := engine.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, Proof{}); err != nil {
		t.Fatal(err)
	}
	if _, err := engine.Admit(ctx, testSubject, []Charge{{"comment.publish", 1}}, Proof{}); !errors.Is(err, ErrCapacity) {
		t.Fatal("MaxEvents was only per charged action", err)
	}
	time.Sleep(120 * time.Millisecond)
	if _, err := engine.Admit(ctx, testSubject, []Charge{{"comment.publish", 1}}, Proof{}); err != nil {
		t.Fatal("cold action's expired event permanently occupied subject cap", err)
	}
}

type flippingPolicyStore struct {
	base  *memoryNamespace
	loads int
}

func (s *flippingPolicyStore) Load(ctx context.Context) (Namespace, error) {
	s.loads++
	n, e := s.base.Load(ctx)
	if s.loads >= 2 {
		n.PolicyHash = strings.Repeat("f", 64)
	}
	return n, e
}
func (s *flippingPolicyStore) Recover(ctx context.Context, g int64, id string, w time.Duration) (Namespace, error) {
	return s.base.Recover(ctx, g, id, w)
}
func (s *flippingPolicyStore) Activate(ctx context.Context, g int64, id string) (Namespace, error) {
	return s.base.Activate(ctx, g, id)
}
func TestRealRedisObserveCannotSwallowRacingPolicyMismatch(t *testing.T) {
	original, store := redisFixture(t, func(c *Config) {
		for i := range c.Rules {
			if c.Rules[i].Action == "post.create" {
				c.Rules[i].Mode = Observe
			}
		}
	})
	racing, err := New(original.config, "", &flippingPolicyStore{base: store})
	if err != nil {
		t.Fatal(err)
	}
	defer racing.Close()
	_, err = racing.Admit(context.Background(), testSubject, []Charge{{"post.create", 1}}, testProof(1))
	if !errors.Is(err, ErrPolicyMismatch) {
		t.Fatal("best-effort observe swallowed incompatible policy during lane execution", err)
	}
}

func TestRealRedisRestrictedRuntimeACLAndOperatorCredentials(t *testing.T) {
	engine, store := redisFixture(t, func(c *Config) { testRule(c, "post.create", 2, 1000) })
	ctx := context.Background()
	password := "synthetic-runtime-only"
	commands := []any{"ACL", "SETUSER", "community_ratelimit", "on", ">" + password, "~hnuhole:isolated_unit:*", "-@all", "+type", "+get", "+set", "+pttl", "+time", "+zscore", "+zcard", "+zadd", "+zremrangebyscore", "+pexpire", "+eval", "+info", "+ping", "+hello", "+auth", "+client|setname"}
	if err := engine.client.Do(ctx, commands...).Err(); err != nil {
		t.Fatal(err)
	}
	config := engine.config
	config.Username = "community_ratelimit"
	runtime, err := New(config, password, store)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	if runtime.PolicyHash() != engine.PolicyHash() {
		t.Fatal("ACL credentials polluted accounting policy hash")
	}
	d, err := runtime.Admit(ctx, testSubject, []Charge{{"post.create", 1}}, testProof(1))
	if err != nil || !d.Allowed {
		t.Fatal("documented runtime ACL cannot execute actual script", d, err)
	}
	if err = runtime.client.ConfigGet(ctx, "maxmemory").Err(); err == nil {
		t.Fatal("runtime obtained operator CONFIG privilege")
	}
	if err = runtime.client.Set(ctx, "hnuhole:verifier_other:namespace", "foreign", time.Minute).Err(); err == nil {
		t.Fatal("runtime ACL crossed C/V namespace")
	}
}
