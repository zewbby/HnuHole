package authprivacy

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func gateCancellationParties(t *testing.T, run func(*testing.T, *gateControl)) {
	t.Helper()
	for _, party := range []struct {
		name string
		new  func(*testing.T) *gateControl
	}{{"C", newGateControl}, {"V", newVerifierGateControl}} {
		t.Run(party.name, func(t *testing.T) { run(t, party.new(t)) })
	}
}

func assertGateCheckpointOpen(t *testing.T, c *gateControl) {
	t.Helper()
	var state string
	var generation, version int64
	var highwater time.Time
	if err := c.gate.pool.QueryRow(context.Background(), `SELECT gate_state,authorization_generation,evidence_version,trusted_high_watermark FROM `+c.gate.schema+`.authorization_gate WHERE singleton_id=1`).Scan(&state, &generation, &version, &highwater); err != nil {
		t.Fatal(err)
	}
	if err := c.gate.anchor.withLocked(func(a *authorizationAnchor, exists bool) error {
		if state != "OPEN" || !exists || a.Frozen || a.Generation != uint64(generation) || a.Version != uint64(version) || !a.Highwater.Equal(highwater) {
			t.Fatalf("checkpoint inconsistent after ordinary cancellation: SQL=%s/%d/%d/%v anchor=%+v", state, generation, version, highwater, a)
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.gate.Snapshot(context.Background()); err != nil {
		t.Fatalf("fresh request required recovery after ordinary cancellation: %v", err)
	}
}

func TestGateCancelledEvidenceDoesNotFreezePostgres(t *testing.T) {
	gateCancellationParties(t, func(t *testing.T, c *gateControl) {
		for _, operation := range []string{"snapshot", "recheck", "commit"} {
			for _, validResult := range []bool{false, true} {
				t.Run(operation+map[bool]string{false: "/cancelled-provider", true: "/valid-result-after-cancel"}[validResult], func(t *testing.T) {
					before, err := c.gate.Snapshot(context.Background())
					if err != nil {
						t.Fatal(err)
					}
					anchorBefore, err := os.ReadFile(c.gate.anchor.Path)
					if err != nil {
						t.Fatal(err)
					}
					c.clock.set(c.clock.now().Add(time.Second))
					ctx, cancel := context.WithCancel(context.Background())
					defer cancel()
					c.gate.evidence = authorizationEvidenceFunc(func(ctx context.Context) (SignedAuthorizationEvidence, error) {
						proof, err := c.provider.Current(ctx)
						cancel()
						if validResult {
							return proof, err
						}
						return c.provider.Current(ctx)
					})
					if operation == "snapshot" {
						_, err = c.gate.Snapshot(ctx)
					} else {
						tx, beginErr := begin(ctx, c.gate.pool)
						if beginErr != nil {
							t.Fatal(beginErr)
						}
						if operation == "recheck" {
							_, err = c.gate.RecheckForCommit(ctx, tx, before.Generation)
						} else {
							_, err = c.gate.CommitAuthorized(ctx, tx, before.Generation)
						}
						if abortErr := c.gate.Abort(ctx, tx); abortErr != nil {
							t.Fatal(abortErr)
						}
					}
					c.gate.evidence = c.provider
					if err == nil {
						t.Fatal("cancelled request was authorized")
					}
					anchorAfter, readErr := os.ReadFile(c.gate.anchor.Path)
					if readErr != nil {
						t.Fatal(readErr)
					}
					if string(anchorAfter) != string(anchorBefore) {
						t.Fatal("request cancellation changed the independent checkpoint")
					}
					assertGateCheckpointOpen(t, c)
				})
			}
		}
	})
}

type gateCancellationTracer struct {
	once    sync.Once
	match   func(string) bool
	onStart func(context.Context) context.Context
}

func (q *gateCancellationTracer) TraceQueryStart(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryStartData) context.Context {
	if q.match(data.SQL) {
		q.once.Do(func() { ctx = q.onStart(ctx) })
	}
	return ctx
}
func (*gateCancellationTracer) TraceQueryEnd(context.Context, *pgx.Conn, pgx.TraceQueryEndData) {}

func gatePoolWithTrace(t *testing.T, c *gateControl, tracer *gateCancellationTracer) *pgxpool.Pool {
	t.Helper()
	config := c.gate.pool.Config()
	config.ConnConfig.Tracer = tracer
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	c.gate.pool = pool
	return pool
}

func gateCancellationProbe(t *testing.T, c *gateControl) {
	t.Helper()
	_, err := c.gate.pool.Exec(context.Background(), `CREATE TABLE public.gate_cancellation_probe(value int NOT NULL); INSERT INTO public.gate_cancellation_probe VALUES(0)`)
	if err != nil {
		t.Fatal(err)
	}
	pool := c.gate.pool
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DROP TABLE public.gate_cancellation_probe`) })
}

func TestGateCancellationAfterCheckpointCompletesPostgres(t *testing.T) {
	for _, operation := range []string{"snapshot", "commit"} {
		for _, boundary := range []string{"update", "commit"} {
			t.Run(operation+"/"+boundary, func(t *testing.T) {
				gateCancellationParties(t, func(t *testing.T, c *gateControl) {
					initial, err := c.gate.Snapshot(context.Background())
					if err != nil {
						t.Fatal(err)
					}
					gateCancellationProbe(t, c)
					c.clock.set(c.clock.now().Add(time.Second))
					ctx, cancel := context.WithCancel(context.Background())
					defer cancel()
					fired, detached, bounded := false, false, false
					tracer := &gateCancellationTracer{match: func(sql string) bool {
						if boundary == "commit" {
							return sql == "commit"
						}
						return strings.Contains(sql, "authorization_gate SET trusted_high_watermark=")
					}, onStart: func(queryCtx context.Context) context.Context {
						fired = true
						cancel()
						detached = queryCtx.Err() == nil
						deadline, ok := queryCtx.Deadline()
						bounded = ok && time.Until(deadline) > 0 && time.Until(deadline) <= 10*time.Second
						return queryCtx
					}}
					pool := gatePoolWithTrace(t, c, tracer)
					if operation == "snapshot" {
						_, err = c.gate.Snapshot(ctx)
					} else {
						tx, beginErr := begin(ctx, pool)
						if beginErr != nil {
							t.Fatal(beginErr)
						}
						if _, err := tx.Exec(ctx, `UPDATE public.gate_cancellation_probe SET value=1`); err != nil {
							t.Fatal(err)
						}
						_, err = c.gate.CommitAuthorized(ctx, tx, initial.Generation)
						if abortErr := c.gate.Abort(ctx, tx); abortErr != nil {
							t.Fatal(abortErr)
						}
					}
					if err != nil || !fired || !detached || !bounded {
						t.Fatalf("checkpoint finalization: err=%v fired=%v detached=%v bounded=%v", err, fired, detached, bounded)
					}
					if operation == "commit" {
						var value int
						if err := pool.QueryRow(context.Background(), `SELECT value FROM public.gate_cancellation_probe`).Scan(&value); err != nil || value != 1 {
							t.Fatalf("authorized transaction did not complete: value=%d err=%v", value, err)
						}
					}
					assertGateCheckpointOpen(t, c)
				})
			})
		}
	}
}

func TestGateCancellationBeforeCheckpointRollsBackPostgres(t *testing.T) {
	gateCancellationParties(t, func(t *testing.T, c *gateControl) {
		initial, err := c.gate.Snapshot(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		gateCancellationProbe(t, c)
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		tx, err := begin(ctx, c.gate.pool)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := tx.Exec(ctx, `UPDATE public.gate_cancellation_probe SET value=1`); err != nil {
			t.Fatal(err)
		}
		_, err = c.gate.CommitAuthorized(ctx, tx, initial.Generation, func(AuthorizationDecision) error { cancel(); return nil })
		if err == nil {
			t.Fatal("cancelled pre-checkpoint operation committed")
		}
		if err := c.gate.Abort(ctx, tx); err != nil {
			t.Fatal(err)
		}
		var value int
		if err := c.gate.pool.QueryRow(context.Background(), `SELECT value FROM public.gate_cancellation_probe`).Scan(&value); err != nil || value != 0 {
			t.Fatalf("cancelled operation left a write: value=%d err=%v", value, err)
		}
		assertGateCheckpointOpen(t, c)
	})
}

func TestGateDatabaseFailureAfterCheckpointStillFreezesPostgres(t *testing.T) {
	gateCancellationParties(t, func(t *testing.T, c *gateControl) {
		initial, err := c.gate.Snapshot(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		gateCancellationProbe(t, c)
		c.clock.set(c.clock.now().Add(time.Second))
		tracer := &gateCancellationTracer{match: func(sql string) bool { return strings.Contains(sql, "authorization_gate SET trusted_high_watermark=") }, onStart: func(ctx context.Context) context.Context {
			failed, cancel := context.WithCancel(ctx)
			cancel() // Database execution failure independent of the live caller.
			return failed
		}}
		pool := gatePoolWithTrace(t, c, tracer)
		tx, err := begin(context.Background(), pool)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := tx.Exec(context.Background(), `UPDATE public.gate_cancellation_probe SET value=1`); err != nil {
			t.Fatal(err)
		}
		if _, err := c.gate.CommitAuthorized(context.Background(), tx, initial.Generation); err == nil {
			t.Fatal("database failure reported success")
		}
		if err := c.gate.Abort(context.Background(), tx); err != nil {
			t.Fatal(err)
		}
		if _, err := c.gate.Snapshot(context.Background()); !errors.Is(err, ErrAuthorizationUnavailable) {
			t.Fatalf("uncertain SQL commit bypassed freeze: %v", err)
		}
		var state string
		if err := pool.QueryRow(context.Background(), `SELECT gate_state FROM `+c.gate.schema+`.authorization_gate WHERE singleton_id=1`).Scan(&state); err != nil || state != "FROZEN" {
			t.Fatalf("SQL freeze not durable: %s %v", state, err)
		}
		var value int
		if err := pool.QueryRow(context.Background(), `SELECT value FROM public.gate_cancellation_probe`).Scan(&value); err != nil || value != 0 {
			t.Fatalf("failed transaction leaked writes: %d %v", value, err)
		}
	})
}

func TestGateCancelledTLSRequestDoesNotFreezePostgres(t *testing.T) {
	gateCancellationParties(t, func(t *testing.T, c *gateControl) {
		// Leave the fixture's initial break-glass setup and model the live
		// online checkpoint before the browser disconnects.
		if _, err := c.gate.Snapshot(context.Background()); err != nil {
			t.Fatal(err)
		}
		c.clock.set(c.clock.now().Add(time.Second))
		entered, completed := make(chan struct{}), make(chan struct{})
		c.gate.evidence = authorizationEvidenceFunc(func(ctx context.Context) (SignedAuthorizationEvidence, error) {
			close(entered)
			<-ctx.Done()
			return c.provider.Current(ctx)
		})
		server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer close(completed)
			if _, err := c.gate.Snapshot(r.Context()); err != nil {
				w.WriteHeader(503)
				return
			}
			w.WriteHeader(200)
		}))
		defer server.Close()
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		request, err := http.NewRequestWithContext(ctx, "GET", server.URL, nil)
		if err != nil {
			t.Fatal(err)
		}
		answer := make(chan error, 1)
		go func() {
			response, err := server.Client().Do(request)
			if response != nil {
				response.Body.Close()
			}
			answer <- err
		}()
		select {
		case <-entered:
		case <-time.After(5 * time.Second):
			t.Fatal("TLS request did not reach evidence provider")
		}
		cancel()
		select {
		case err := <-answer:
			if !errors.Is(err, context.Canceled) {
				t.Fatalf("client did not cancel: %v", err)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("TLS client cancellation stalled")
		}
		select {
		case <-completed:
		case <-time.After(5 * time.Second):
			t.Fatal("cancelled handler did not exit")
		}
		c.gate.evidence = c.provider
		assertGateCheckpointOpen(t, c)
	})
}
