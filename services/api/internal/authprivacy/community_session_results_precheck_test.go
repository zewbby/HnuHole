package authprivacy

import (
	"context"
	"errors"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type sessionPrecheckGate struct {
	AuthorizationGate
	snapshots, commits, aborts atomic.Int32
	beforeSnapshot             func(context.Context)
	beforeCommit               func()
}

func (g *sessionPrecheckGate) Snapshot(ctx context.Context) (AuthorizationDecision, error) {
	g.snapshots.Add(1)
	if g.beforeSnapshot != nil {
		g.beforeSnapshot(ctx)
	}
	return g.AuthorizationGate.Snapshot(ctx)
}

func (g *sessionPrecheckGate) CommitAuthorized(ctx context.Context, tx pgx.Tx, generation uint64, checks ...func(AuthorizationDecision) error) (AuthorizationDecision, error) {
	g.commits.Add(1)
	if g.beforeCommit != nil {
		g.beforeCommit()
	}
	return g.AuthorizationGate.CommitAuthorized(ctx, tx, generation, checks...)
}

func (g *sessionPrecheckGate) Abort(ctx context.Context, tx pgx.Tx) error {
	g.aborts.Add(1)
	return g.AuthorizationGate.Abort(ctx, tx)
}

func sessionPrecheckSpy(l *lab) *sessionPrecheckGate {
	g := &sessionPrecheckGate{AuthorizationGate: l.c.gate}
	l.c.gate = g
	return g
}

func sessionPrecheckInsert(t *testing.T, q interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}, expires time.Time) []byte {
	t.Helper()
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	mac, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	_, err = q.Exec(context.Background(), `INSERT INTO c_auth.request_results
		(operation,key_digest,state,request_hmac,hmac_key_version,result_code,expires_at)
		VALUES('SESSION_CREATE',$1,'LIVE',$2,1,'SESSION_CREATED',$3)`, key[:], mac[:], expires)
	if err != nil {
		t.Fatal(err)
	}
	return key[:]
}

func sessionPrecheckClean(t *testing.T, c *Community, limit int, expected int64) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	got, err := c.CleanupSessionResults(ctx, limit)
	if err != nil || got != expected {
		t.Fatalf("cleaned=%d want=%d err=%v", got, expected, err)
	}
}

func TestSessionResultPrecheckEmptyAndCancelledPostgres(t *testing.T) {
	l := newLab(t)
	g := sessionPrecheckSpy(l)
	sessionPrecheckClean(t, l.c, 1, 0)
	// Permanent tombstones and other operation classes do not constitute work.
	mustExec(t, l.cp, `INSERT INTO c_auth.request_results(operation,key_digest,state)
		SELECT 'SESSION_CREATE',decode(md5(i::text)||md5(i::text),'hex'),'EXPIRED'
		FROM generate_series(1,10000) i`)
	mustExec(t, l.cp, `INSERT INTO c_auth.request_results
		(operation,key_digest,state,request_hmac,hmac_key_version,result_code,expires_at)
		VALUES('OTHER_OPERATION',decode(repeat('ff',32),'hex'),'LIVE',decode(repeat('ef',32),'hex'),1,'OK',clock_timestamp())`)
	if err := l.gate.Freeze(context.Background(), "empty worker is not a health check"); err != nil {
		t.Fatal(err)
	}
	anchor, err := os.ReadFile(l.gate.anchor.Path)
	if err != nil {
		t.Fatal(err)
	}
	started := time.Now()
	sessionPrecheckClean(t, l.c, 1, 0)
	t.Logf("W1 empty with 10000 tombstones: duration=%s Gate snapshots=%d", time.Since(started), g.snapshots.Load())
	after, err := os.ReadFile(l.gate.anchor.Path)
	if err != nil || string(anchor) != string(after) {
		t.Fatal("empty pass changed independent anchor")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results`) != 10001 {
		t.Fatal("empty pass changed rows")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.authorization_gate WHERE gate_state='FROZEN'`) != 1 {
		t.Fatal("empty pass changed freeze")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := l.c.CleanupSessionResults(ctx, 0); !errors.Is(err, ErrIntentInvalid) {
		t.Fatal("lost invalid limit priority")
	}
	if _, err := l.c.CleanupSessionResults(ctx, 1); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("cancelled empty pass succeeded")
	}
	if g.snapshots.Load() != 0 || g.commits.Load() != 0 || g.aborts.Load() != 0 {
		t.Fatal("empty hint entered Gate")
	}
}

func TestSessionResultPrecheckCandidatesBatchAndLocksPostgres(t *testing.T) {
	l := newLab(t)
	g := sessionPrecheckSpy(l)
	future := sessionPrecheckInsert(t, l.cp, time.Now().Add(8*24*time.Hour))
	sessionPrecheckClean(t, l.c, 2, 0)
	if g.snapshots.Load() != 1 || g.commits.Load() != 1 || g.aborts.Load() != 1 {
		t.Fatal("unexpired LIVE bypassed original Gate")
	}
	keys := make([][]byte, 3)
	for i := range keys {
		keys[i] = sessionPrecheckInsert(t, l.cp, time.Now().Add(-time.Hour))
	}
	hold, err := l.cp.Begin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(context.Background())
	if _, err := hold.Exec(context.Background(), `SELECT key_digest FROM c_auth.request_results WHERE key_digest=$1 FOR UPDATE`, keys[0]); err != nil {
		t.Fatal(err)
	}
	sessionPrecheckClean(t, l.c, 2, 2)
	sessionPrecheckClean(t, l.c, 2, 0)
	if err := hold.Rollback(context.Background()); err != nil {
		t.Fatal(err)
	}
	sessionPrecheckClean(t, l.c, 2, 1)
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE state='EXPIRED'
		AND request_hmac IS NULL AND hmac_key_version IS NULL AND intent_id IS NULL
		AND reset_intent_id IS NULL AND result_code IS NULL AND expires_at IS NULL`) != 3 {
		t.Fatal("missing permanent clean tombstones")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE key_digest=$1 AND state='LIVE'`, future) != 1 {
		t.Fatal("unexpired result changed")
	}
	if g.commits.Load() != 4 || g.aborts.Load() != 4 {
		t.Fatal("candidate batches changed final authorization/abort")
	}
	if _, err := l.cp.Exec(context.Background(), `DELETE FROM c_auth.request_results WHERE key_digest=$1`, keys[0]); err == nil {
		t.Fatal("permanent key deleted")
	}
	if _, err := l.cp.Exec(context.Background(), `INSERT INTO c_auth.request_results(operation,key_digest,state) VALUES('SESSION_CREATE',$1,'EXPIRED')`, keys[0]); err == nil {
		t.Fatal("permanent key reused")
	}
}

type sessionPrecheckTrace struct {
	onStart func(context.Context, *pgx.Conn) context.Context
	onEnd   func(context.Context, pgx.TraceQueryEndData)
	hints   atomic.Int32
}

type sessionPrecheckTraceKey struct{}

func (q *sessionPrecheckTrace) TraceQueryStart(ctx context.Context, conn *pgx.Conn, data pgx.TraceQueryStartData) context.Context {
	if strings.Contains(data.SQL, "SELECT EXISTS (") && strings.Contains(data.SQL, "operation='SESSION_CREATE' AND state='LIVE'") {
		q.hints.Add(1)
		if q.onStart != nil {
			ctx = q.onStart(ctx, conn)
		}
		return context.WithValue(ctx, sessionPrecheckTraceKey{}, true)
	}
	return ctx
}

func (q *sessionPrecheckTrace) TraceQueryEnd(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryEndData) {
	if ctx.Value(sessionPrecheckTraceKey{}) == true && q.onEnd != nil {
		q.onEnd(ctx, data)
	}
}

func sessionPrecheckPool(t *testing.T, l *lab, tracer *sessionPrecheckTrace, maxConns int32) *pgxpool.Pool {
	t.Helper()
	cfg := l.cp.Config()
	cfg.ConnConfig.Tracer = tracer
	if maxConns > 0 {
		cfg.MaxConns = maxConns
	}
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	l.c.pool = pool
	return pool
}

func TestSessionResultPrecheckTimeoutFallsBackPostgres(t *testing.T) {
	l := newLab(t)
	sessionPrecheckInsert(t, l.cp, time.Now().Add(-time.Hour))
	hold, err := l.cp.Begin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(context.Background())
	if _, err := hold.Exec(context.Background(), `LOCK TABLE c_auth.request_results IN ACCESS EXCLUSIVE MODE`); err != nil {
		t.Fatal(err)
	}
	var hintFailed bool
	tracer := &sessionPrecheckTrace{onStart: func(ctx context.Context, _ *pgx.Conn) context.Context {
		deadline, ok := ctx.Deadline()
		if !ok || time.Until(deadline) > 50*time.Millisecond {
			t.Error("hint missing short child deadline")
		}
		return ctx
	}, onEnd: func(_ context.Context, d pgx.TraceQueryEndData) { hintFailed = d.Err != nil }}
	pool := sessionPrecheckPool(t, l, tracer, 2)
	g := sessionPrecheckSpy(l)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	parentDeadline, _ := ctx.Deadline()
	g.beforeSnapshot = func(actual context.Context) {
		d, _ := actual.Deadline()
		if actual.Err() != nil || d != parentDeadline {
			t.Error("fallback lost live original parent context")
		}
		if err := hold.Rollback(context.Background()); err != nil {
			t.Error(err)
		}
	}
	got, err := l.c.CleanupSessionResults(ctx, 1)
	if err != nil || got != 1 || !hintFailed || tracer.hints.Load() != 1 {
		t.Fatalf("timeout fallback: count=%d failed=%v err=%v", got, hintFailed, err)
	}
	if g.snapshots.Load() != 1 || g.commits.Load() != 1 || g.aborts.Load() != 1 || pool.Stat().AcquiredConns() != 0 {
		t.Fatal("fallback retried or leaked connection")
	}
	t.Log("W3 blocked hint expired; original parent completed one authorized cleanup; no hint retry")
}

func TestSessionResultPrecheckQueryFailureAndCancellationPostgres(t *testing.T) {
	for _, mode := range []string{"query-error", "cancel-after-result", "pool-full", "pool-closed"} {
		t.Run(mode, func(t *testing.T) {
			l := newLab(t)
			sessionPrecheckInsert(t, l.cp, time.Now().Add(-time.Hour))
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			tracer := &sessionPrecheckTrace{}
			if mode == "query-error" {
				// An owned fixture schema error affects only the hint. Restore the
				// table in the Gate wrapper before running the original operation.
				mustExec(t, l.cp, `ALTER TABLE c_auth.request_results RENAME TO precheck_hidden_results`)
				t.Cleanup(func() {
					_, _ = l.cp.Exec(context.Background(), `ALTER TABLE IF EXISTS c_auth.precheck_hidden_results RENAME TO request_results`)
				})
				tracer.onEnd = func(queryCtx context.Context, d pgx.TraceQueryEndData) {
					var pgerr *pgconn.PgError
					if !errors.As(d.Err, &pgerr) || pgerr.Code != "42P01" {
						t.Errorf("expected SQL relation error, got %v", d.Err)
					}
				}
			}
			if mode == "cancel-after-result" {
				tracer.onEnd = func(context.Context, pgx.TraceQueryEndData) { cancel() }
			}
			pool := sessionPrecheckPool(t, l, tracer, 1)
			g := sessionPrecheckSpy(l)
			if mode == "query-error" {
				g.beforeSnapshot = func(context.Context) {
					mustExec(t, l.cp, `ALTER TABLE c_auth.precheck_hidden_results RENAME TO request_results`)
				}
			}
			if mode == "pool-full" {
				conn, err := pool.Acquire(ctx)
				if err != nil {
					t.Fatal(err)
				}
				defer conn.Release()
				g.beforeSnapshot = func(context.Context) { conn.Release() }
			}
			if mode == "pool-closed" {
				pool.Close()
			}
			got, err := l.c.CleanupSessionResults(ctx, 1)
			if mode == "query-error" || mode == "pool-full" {
				if err != nil || got != 1 || g.commits.Load() != 1 {
					t.Fatalf("unknown hint did not fall back: %d %v", got, err)
				}
			} else if err == nil || got != 0 {
				t.Fatal("failed/cancelled query reported empty success")
			}
			if mode == "cancel-after-result" && g.snapshots.Load() != 0 {
				t.Fatal("cancelled parent entered Gate")
			}
			if pool.Stat().AcquiredConns() != 0 {
				t.Fatal("hint retained pooled connection")
			}
		})
	}
}

func TestSessionResultPrecheckParentBudgetPostgres(t *testing.T) {
	l := newLab(t)
	var observed time.Duration
	tracer := &sessionPrecheckTrace{onStart: func(ctx context.Context, _ *pgx.Conn) context.Context {
		d, ok := ctx.Deadline()
		if !ok {
			t.Error("hint has no deadline")
		}
		observed = time.Until(d)
		return ctx
	}}
	pool := sessionPrecheckPool(t, l, tracer, 1)
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	if !l.c.sessionResultsKnownEmpty(ctx) || observed <= 0 || observed > 20*time.Millisecond {
		t.Fatalf("hint exceeds remaining budget fraction: %s", observed)
	}
	short, stop := context.WithTimeout(context.Background(), 5*time.Millisecond)
	defer stop()
	if l.c.sessionResultsKnownEmpty(short) || tracer.hints.Load() != 1 {
		t.Fatal("tiny remaining budget attempted optional SQL")
	}
}

func TestSessionResultPrecheckConcurrentArrivalAndRebuildPostgres(t *testing.T) {
	l := newLab(t)
	g := sessionPrecheckSpy(l)
	arrival, err := l.cp.Begin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer arrival.Rollback(context.Background())
	sessionPrecheckInsert(t, arrival, time.Now().Add(-time.Hour))
	sessionPrecheckClean(t, l.c, 1, 0)
	if g.snapshots.Load() != 0 {
		t.Fatal("uncommitted arrival was treated as committed work")
	}
	if err := arrival.Commit(context.Background()); err != nil {
		t.Fatal(err)
	}
	// A new service object has no in-memory empty result to carry across restart.
	rebuilt, err := NewCommunity(l.cp, l.c.verifier, l.c.signingEpoch, l.c.requestKey, g)
	if err != nil {
		t.Fatal(err)
	}
	sessionPrecheckClean(t, rebuilt, 1, 1)
	sessionPrecheckClean(t, rebuilt, 1, 0)
	if g.snapshots.Load() != 1 || g.commits.Load() != 1 || g.aborts.Load() != 1 {
		t.Fatal("arrival was lost or empty result cached")
	}
	for i := 0; i < 5; i++ {
		sessionPrecheckInsert(t, l.cp, time.Now().Add(-time.Hour))
	}
	type outcome struct {
		count int64
		err   error
	}
	answers := make(chan outcome, 2)
	start := make(chan struct{})
	for i := 0; i < 2; i++ {
		go func() {
			<-start
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			n, e := rebuilt.CleanupSessionResults(ctx, 3)
			answers <- outcome{n, e}
		}()
	}
	close(start)
	var total int64
	for i := 0; i < 2; i++ {
		a := <-answers
		if a.err != nil || a.count > 3 {
			t.Fatalf("concurrent bounded cleanup: %+v", a)
		}
		total += a.count
	}
	if total != 5 || count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE state='LIVE'`) != 0 {
		t.Fatal("concurrent cleanup omitted or double-counted candidates")
	}
}

func TestSessionResultPrecheckFinalGateAndAbortPostgres(t *testing.T) {
	for _, mode := range []string{"already-frozen", "freeze-before-commit", "generation-before-commit", "ahead-anchor"} {
		t.Run(mode, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			key := sessionPrecheckInsert(t, l.cp, control.clock.now().Add(-time.Hour))
			g := sessionPrecheckSpy(l)
			if mode == "already-frozen" {
				if err := control.gate.Freeze(context.Background(), mode); err != nil {
					t.Fatal(err)
				}
			}
			if mode == "ahead-anchor" {
				if err := control.gate.anchor.withLocked(func(a *authorizationAnchor, _ bool) error {
					a.Highwater = a.Highwater.Add(time.Second)
					return control.gate.anchor.writeLocked(*a)
				}); err != nil {
					t.Fatal(err)
				}
			}
			if mode == "freeze-before-commit" || mode == "generation-before-commit" {
				g.beforeCommit = func() {
					if err := control.gate.Freeze(context.Background(), mode); err != nil {
						t.Fatal(err)
					}
					if mode == "generation-before-commit" {
						control.recover(t, AuthorizationRecoveryBreakGlass, 3, 3)
					}
				}
			}
			n, err := l.c.CleanupSessionResults(context.Background(), 1)
			if err == nil || n != 0 || g.snapshots.Load() != 1 {
				t.Fatal("real candidate bypassed Gate failure")
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE key_digest=$1 AND state='LIVE' AND request_hmac IS NOT NULL`, key) != 1 {
				t.Fatal("failed final Gate changed result")
			}
			if strings.Contains(mode, "before-commit") && (g.commits.Load() != 1 || g.aborts.Load() != 1) {
				t.Fatal("final boundary or Abort removed")
			}
			if mode != "generation-before-commit" && count(t, l.cp, `SELECT count(*) FROM c_auth.authorization_gate WHERE gate_state='FROZEN'`) != 1 {
				t.Fatal("freeze not durable")
			}
		})
	}
}

func TestSessionResultPrecheckWorkerAndGateContentionPostgres(t *testing.T) {
	l := newLab(t)
	g := sessionPrecheckSpy(l)
	tracer := &sessionPrecheckTrace{}
	sessionPrecheckPool(t, l, tracer, 2)
	hold, err := l.cp.Begin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(context.Background())
	if _, err := hold.Exec(context.Background(), `SELECT singleton_id FROM c_auth.authorization_gate FOR UPDATE`); err != nil {
		t.Fatal(err)
	}
	cfg := DefaultWorkerConfig()
	var observations []WorkerObservation
	worker, err := NewCommunityWorker(l.c, cfg,
		func(context.Context, uint32, []byte) ([]byte, error) { return nil, nil },
		func(context.Context, string, protocol.Purpose) error { return nil },
		func(o WorkerObservation) { observations = append(observations, o) })
	if err != nil {
		t.Fatal(err)
	}
	var selected []durableTask
	for _, task := range worker.tasks {
		if task.name == "session_results_cleanup" {
			selected = append(selected, task)
		}
	}
	if len(selected) != 1 {
		t.Fatal("real cleanup worker registration missing")
	}
	original := selected[0].run
	selected[0].run = func(ctx context.Context, n int) (int, error) {
		d, ok := ctx.Deadline()
		if n != cfg.BatchSize || !ok || time.Until(d) > cfg.TaskTimeout {
			t.Error("worker lost task bounds")
		}
		return original(ctx, n)
	}
	worker.tasks = selected // Run only the changed task, with the production dispatcher.
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := worker.RunOnce(ctx); err != nil {
		t.Fatal(err)
	}
	if len(observations) != 1 || observations[0].Failed || observations[0].Processed != 0 || observations[0].BatchLimit != cfg.BatchSize || tracer.hints.Load() != 1 || g.snapshots.Load() != 0 {
		t.Fatal("empty task entered held Gate, retried, or changed observation bounds")
	}
	t.Logf("W6 Gate row held: empty task returned in %s with zero Gate calls", observations[0].Duration)
	sessionPrecheckInsert(t, l.cp, time.Now().Add(-time.Hour))
	blocked, stop := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer stop()
	n, err := l.c.CleanupSessionResults(blocked, 1)
	if err == nil || n != 0 || g.snapshots.Load() != 1 || g.commits.Load() != 0 {
		t.Fatal("nonempty task bypassed held Gate")
	}
	if err := hold.Rollback(context.Background()); err != nil {
		t.Fatal(err)
	}
	sessionPrecheckClean(t, l.c, 1, 1)
	sessionPrecheckClean(t, l.c, 1, 0)
}
