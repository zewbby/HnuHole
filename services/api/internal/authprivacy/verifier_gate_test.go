package authprivacy

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type authorizationEvidenceFunc func(context.Context) (SignedAuthorizationEvidence, error)

func (f authorizationEvidenceFunc) Current(ctx context.Context) (SignedAuthorizationEvidence, error) {
	return f(ctx)
}

// The same state machine has separate V SQL state, signing keys, domain and
// external checkpoint. C's gate remains open throughout V fault scenarios.
func newVerifierGateControl(t *testing.T) *gateControl {
	t.Helper()
	l := newLab(t)
	ctx := context.Background()
	if err := l.vGate.Freeze(ctx, "controlled verifier setup"); err != nil {
		t.Fatal(err)
	}
	ep, ek, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	rp, rk, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	bp, bk, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	_, ak, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	provider := NewFileAuthorizationEvidenceProvider(filepath.Join(dir, "v-evidence.json"))
	anchor, err := NewFileAuthorizationAnchorStore(filepath.Join(dir, "v-anchor.json"), ak)
	if err != nil {
		t.Fatal(err)
	}
	clock := &gateTestClock{at: time.Now().UTC().Truncate(time.Microsecond)}
	cfg := AuthorizationGateConfig{
		Pool: l.vGate.pool, Schema: "v_auth", Domain: "controlled-lab-v", Evidence: provider,
		EvidencePublicKey: ep, RecoveryPublicKey: rp, BreakGlassPublicKey: bp,
		Anchor: anchor, Clock: clock.now,
	}
	gate, err := NewPostgresAuthorizationGate(cfg)
	if err != nil {
		t.Fatal(err)
	}
	c := &gateControl{lab: l, gate: gate, config: cfg, provider: provider, clock: clock, evidence: ek, recovery: rk, glass: bk}
	c.recover(t, AuthorizationRecoveryBreakGlass, 2, 2)
	l.vGate, l.v.gate = gate, gate
	return c
}

func assertVerifierFrozen(t *testing.T, c *gateControl) {
	t.Helper()
	if _, err := c.gate.Snapshot(context.Background()); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("V gate permitted authorization: %v", err)
	}
	var state string
	if err := c.lab.vp.QueryRow(context.Background(), `SELECT gate_state FROM v_auth.authorization_gate WHERE singleton_id=1`).Scan(&state); err != nil || state != "FROZEN" {
		t.Fatalf("V freeze not durable: state=%q err=%v", state, err)
	}
}

func TestAuthorizationGateSchemaWhitelist(t *testing.T) {
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	anchor, err := NewFileAuthorizationAnchorStore(filepath.Join(dir, "anchor.json"), private)
	if err != nil {
		t.Fatal(err)
	}
	cfg := AuthorizationGateConfig{
		Pool: &pgxpool.Pool{}, Domain: "schema-test", Evidence: NewFileAuthorizationEvidenceProvider(filepath.Join(dir, "evidence.json")),
		EvidencePublicKey: public, RecoveryPublicKey: public, BreakGlassPublicKey: public,
		Anchor: anchor, Clock: time.Now,
	}
	for _, schema := range []string{"", "c_auth", "v_auth"} {
		cfg.Schema = schema
		gate, err := NewPostgresAuthorizationGate(cfg)
		if err != nil {
			t.Fatalf("valid schema %q rejected: %v", schema, err)
		}
		expected := schema
		if expected == "" {
			expected = "c_auth"
		}
		if gate.schema != expected {
			t.Fatalf("schema %q resolved to %q", schema, gate.schema)
		}
	}
	for _, schema := range []string{"public", "V_AUTH", "v_auth; DROP SCHEMA c_auth CASCADE", "v_auth.authorization_gate", "\"v_auth\"", " v_auth"} {
		cfg.Schema = schema
		if _, err := NewPostgresAuthorizationGate(cfg); err == nil {
			t.Fatalf("untrusted SQL schema %q accepted", schema)
		}
	}
}

func TestVerifierGateRollbackBoundaryRestartAndIndependencePostgres(t *testing.T) {
	for _, back := range []time.Duration{authorizationSkew, authorizationSkew + time.Nanosecond} {
		t.Run(back.String(), func(t *testing.T) {
			c := newVerifierGateControl(t)
			ctx := context.Background()
			baseline, err := c.gate.Snapshot(ctx)
			if err != nil {
				t.Fatal(err)
			}
			c.clock.set(baseline.TrustedAt.Add(-back))
			decision, err := c.gate.Snapshot(ctx)
			if back <= authorizationSkew {
				if err != nil || !decision.TrustedAt.Equal(baseline.TrustedAt) {
					t.Fatalf("V jitter lowered watermark: %+v %v", decision, err)
				}
				return
			}
			if !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatalf("V rollback accepted: %v", err)
			}
			assertVerifierFrozen(t, c)
			if _, err := c.lab.gate.Snapshot(ctx); err != nil {
				t.Fatalf("V freeze affected C: %v", err)
			}
			restarted, err := NewPostgresAuthorizationGate(c.config)
			if err != nil {
				t.Fatal(err)
			}
			c.clock.set(baseline.TrustedAt.Add(time.Second))
			if err := c.provider.Store(ctx, c.signed(t, c.evidence, 3, 3, c.clock.now(), c.clock.now().Add(authorizationEvidenceTTL))); err != nil {
				t.Fatal(err)
			}
			if _, err = restarted.Snapshot(ctx); !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatal("restart or fresh evidence reopened V")
			}
			c.recover(t, AuthorizationRecoveryNormal, 3, 3)
			if decision, err = restarted.Snapshot(ctx); err != nil || decision.Generation != 3 {
				t.Fatalf("trusted recovery failed: %+v %v", decision, err)
			}
			if count(t, c.lab.vp, `SELECT count(*) FROM v_auth.authorization_gate_audit WHERE event_kind='RECOVER' AND authorization_generation=3 AND actor='test-recovery-role'`) != 1 {
				t.Fatal("V recovery audit missing")
			}
		})
	}
	// The other direction is independent too: C freezing cannot substitute for
	// or invalidate V's own trusted authorization decision.
	c := newVerifierGateControl(t)
	if err := c.lab.gate.Freeze(context.Background(), "C-only fault"); err != nil {
		t.Fatal(err)
	}
	if _, err := c.gate.Snapshot(context.Background()); err != nil {
		t.Fatalf("C freeze affected V: %v", err)
	}
}

func TestVerifierGateEvidenceAndReplicaFailuresPostgres(t *testing.T) {
	for _, scenario := range []string{"ttl_boundary", "expired", "missing", "bad_signature", "cross_domain", "older_version", "missing_anchor", "replica"} {
		t.Run(scenario, func(t *testing.T) {
			c := newVerifierGateControl(t)
			ctx := context.Background()
			if _, err := c.gate.Snapshot(ctx); err != nil {
				t.Fatal(err)
			}
			at := c.clock.now()
			switch scenario {
			case "ttl_boundary":
				c.clock.set(at.Add(authorizationEvidenceTTL))
				if _, err := c.gate.Snapshot(ctx); err != nil {
					t.Fatalf("valid TTL boundary rejected: %v", err)
				}
				return
			case "expired":
				c.clock.set(at.Add(authorizationEvidenceTTL + time.Nanosecond))
			case "missing":
				if err := os.Remove(c.provider.Path); err != nil {
					t.Fatal(err)
				}
			case "bad_signature":
				s := c.signed(t, c.evidence, 2, 3, at, at.Add(authorizationEvidenceTTL))
				s.Signature[0] ^= 1
				if err := c.provider.Store(ctx, s); err != nil {
					t.Fatal(err)
				}
			case "cross_domain":
				e := AuthorizationEvidence{Domain: "controlled-lab-c", Generation: 2, Version: 3, IssuedAt: at, TrustedAt: at, ValidUntil: at.Add(authorizationEvidenceTTL)}
				s, err := SignAuthorizationEvidence(c.evidence, e)
				if err != nil {
					t.Fatal(err)
				}
				if err := c.provider.Store(ctx, s); err != nil {
					t.Fatal(err)
				}
			case "older_version":
				if err := c.provider.Store(ctx, c.signed(t, c.evidence, 2, 1, at, at.Add(authorizationEvidenceTTL))); err != nil {
					t.Fatal(err)
				}
			case "missing_anchor":
				if err := os.Remove(c.config.Anchor.Path); err != nil {
					t.Fatal(err)
				}
			case "replica":
				pool, err := pgxpool.New(ctx, os.Getenv("AUTHLAB_V_DSN"))
				if err != nil {
					t.Fatal(err)
				}
				defer pool.Close()
				cfg := c.config
				cfg.Pool = pool
				other, err := NewPostgresAuthorizationGate(cfg)
				if err != nil {
					t.Fatal(err)
				}
				if err := c.gate.Freeze(ctx, "V replica A fault"); err != nil {
					t.Fatal(err)
				}
				if _, err := other.Snapshot(ctx); !errors.Is(err, ErrAuthorizationUnavailable) {
					t.Fatal("V replica B ignored persisted freeze")
				}
			}
			assertVerifierFrozen(t, c)
			if _, err := c.lab.gate.Snapshot(ctx); err != nil {
				t.Fatalf("V fault affected C: %v", err)
			}
		})
	}
}

func TestVerifierGateCompleteGateSnapshotCannotReopenPostgres(t *testing.T) {
	c := newVerifierGateControl(t)
	ctx := context.Background()
	if _, err := c.gate.Snapshot(ctx); err != nil {
		t.Fatal(err)
	}
	// Preserve the whole old row and audit image, not just one regressed field.
	// These owner-only replacements model the gate portion of an old DB image;
	// the current, DB-external checkpoint is deliberately not restored.
	mustExec(t, c.lab.vp, `CREATE TABLE v_auth.old_gate_image AS SELECT * FROM v_auth.authorization_gate`)
	mustExec(t, c.lab.vp, `CREATE TABLE v_auth.old_audit_image AS SELECT * FROM v_auth.authorization_gate_audit`)
	if err := c.gate.Freeze(ctx, "after snapshot"); err != nil {
		t.Fatal(err)
	}
	c.clock.set(c.clock.now().Add(time.Second))
	c.recover(t, AuthorizationRecoveryNormal, 3, 3)
	mustExec(t, c.lab.vp, `TRUNCATE v_auth.authorization_gate,v_auth.authorization_gate_audit;
		INSERT INTO v_auth.authorization_gate SELECT * FROM v_auth.old_gate_image;
		INSERT INTO v_auth.authorization_gate_audit OVERRIDING SYSTEM VALUE SELECT * FROM v_auth.old_audit_image`)
	restarted, err := NewPostgresAuthorizationGate(c.config)
	if err != nil {
		t.Fatal(err)
	}
	c.gate = restarted
	assertVerifierFrozen(t, c)
	if count(t, c.lab.vp, `SELECT count(*) FROM v_auth.authorization_gate_audit WHERE event_kind='FREEZE' AND reason='SNAPSHOT_OR_ANCHOR_MISMATCH'`) != 1 {
		t.Fatal("complete old V gate image did not trigger audited freeze")
	}
	c.recover(t, AuthorizationRecoveryNormal, 4, 4)
	if decision, err := c.gate.Snapshot(ctx); err != nil || decision.Generation != 4 {
		t.Fatalf("recovery did not fence external generation: %+v %v", decision, err)
	}
}

func TestVerifierGateFinalCommitAndPendingGenerationPostgres(t *testing.T) {
	c := newVerifierGateControl(t)
	ctx := context.Background()
	mustExec(t, c.lab.vp, `CREATE TABLE v_auth.test_authorized_effects(id integer PRIMARY KEY)`)
	pending, err := c.gate.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	tx, err := begin(ctx, c.lab.vp)
	if err != nil {
		t.Fatal(err)
	}
	defer c.gate.Abort(ctx, tx)
	if _, err := tx.Exec(ctx, `INSERT INTO v_auth.test_authorized_effects VALUES(1)`); err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Freeze(ctx, "freeze before V final commit"); err != nil {
		t.Fatal(err)
	}
	if _, err := c.gate.CommitAuthorized(ctx, tx, pending.Generation); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen provisional V write committed: %v", err)
	}
	if err := c.gate.Abort(ctx, tx); err != nil {
		t.Fatal(err)
	}
	if count(t, c.lab.vp, `SELECT count(*) FROM v_auth.test_authorized_effects`) != 0 {
		t.Fatal("failed V authority left a committed effect")
	}
	c.clock.set(c.clock.now().Add(time.Second))
	c.recover(t, AuthorizationRecoveryNormal, 3, 3)
	stale, err := begin(ctx, c.lab.vp)
	if err != nil {
		t.Fatal(err)
	}
	defer c.gate.Abort(ctx, stale)
	if _, err := c.gate.CommitAuthorized(ctx, stale, pending.Generation); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("old V pending generation accepted: %v", err)
	}
	if err := c.gate.Abort(ctx, stale); err != nil {
		t.Fatal(err)
	}
}

func TestVerifierGateRefreshWithSingleConnectionBusinessPoolPostgres(t *testing.T) {
	l := newLab(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	config := l.vp.Config().Copy()
	config.MaxConns = 1
	config.MinConns = 0
	businessPool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	defer businessPool.Close()
	store, err := NewVerifierStore(businessPool, l.v.verifier, l.v.addressLockKey, l.vGate)
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.vp, `CREATE TABLE v_auth.test_pool_authorized_effects(id integer PRIMARY KEY)`)
	tx, err := store.beginAuthorized(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	// The open transaction owns the business pool's only connection. Both
	// explicit and SQL-template clock refresh must use the separate gate pool.
	var at, sqlAt time.Time
	if err := verifierTrustedAt(ctx, tx, &at); err != nil {
		t.Fatalf("trusted refresh starved behind its own business connection: %v", err)
	}
	if err := tx.QueryRow(ctx, `SELECT {trusted_at}`).Scan(&sqlAt); err != nil {
		t.Fatalf("trusted SQL refresh starved behind its own business connection: %v", err)
	}
	if at.IsZero() || sqlAt.Before(at) {
		t.Fatal("isolated clock refresh failed to preserve trusted time")
	}
	if _, err := tx.Exec(ctx, `INSERT INTO v_auth.test_pool_authorized_effects VALUES(1)`); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatalf("single-connection business transaction failed final gate commit: %v", err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.test_pool_authorized_effects`) != 1 {
		t.Fatal("separate gate pool lost the business transaction's committed effect")
	}
}

func TestVerifierGateRecoveryWaitRechecksEvidencePostgres(t *testing.T) {
	c := newVerifierGateControl(t)
	ctx := context.Background()
	if err := c.gate.Freeze(ctx, "V recovery lock-wait test"); err != nil {
		t.Fatal(err)
	}
	proof := c.signed(t, c.evidence, 3, 3, c.clock.now(), c.clock.now().Add(authorizationEvidenceTTL))
	if err := c.provider.Store(ctx, proof); err != nil {
		t.Fatal(err)
	}
	request, err := SignAuthorizationRecovery(c.recovery, AuthorizationRecoveryRequest{
		Role: "authorization-recovery", Actor: "wait-test", Reason: "fresh proof before row wait",
		OperationID: "V-wait-expiry", Mode: AuthorizationRecoveryNormal, Evidence: proof,
	})
	if err != nil {
		t.Fatal(err)
	}
	hold, err := begin(ctx, c.lab.vp)
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(ctx)
	if _, err := hold.Exec(ctx, `SELECT singleton_id FROM v_auth.authorization_gate WHERE singleton_id=1 FOR UPDATE`); err != nil {
		t.Fatal(err)
	}
	answer := make(chan error, 1)
	go func() { answer <- c.gate.Recover(ctx, request) }()
	// Gate FOR UPDATE waits on the holding transaction's row lock; the common
	// waitBlocked helper observes advisory business locks and cannot see it.
	waitLock(t, c.lab.vp, "transactionid", 1)
	c.clock.set(c.clock.now().Add(authorizationEvidenceTTL + time.Nanosecond))
	if err := hold.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-answer; !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("expired recovery proof reopened V after lock wait: %v", err)
	}
	assertVerifierFrozen(t, c)
	if count(t, c.lab.vp, `SELECT count(*) FROM v_auth.authorization_gate_audit WHERE operation_id='V-wait-expiry'`) != 0 {
		t.Fatal("expired waiting recovery was recorded as successful")
	}
}

func TestVerifierGateRestrictedRecoveryAndReplayPostgres(t *testing.T) {
	c := newVerifierGateControl(t)
	ctx := context.Background()
	if err := c.gate.Freeze(ctx, "V signed recovery test"); err != nil {
		t.Fatal(err)
	}
	c.clock.set(c.clock.now().Add(time.Second))
	proof := c.signed(t, c.evidence, 3, 3, c.clock.now(), c.clock.now().Add(authorizationEvidenceTTL))
	if err := c.provider.Store(ctx, proof); err != nil {
		t.Fatal(err)
	}
	request := AuthorizationRecoveryRequest{Role: "authorization-recovery", Actor: "V-recovery-role", Reason: "independent evidence verified", OperationID: "V-restricted-recovery", Mode: AuthorizationRecoveryNormal, Evidence: proof}
	for _, scenario := range []string{"unsigned", "wrong_role", "wrong_domain"} {
		invalid := request
		var err error
		if scenario == "wrong_role" {
			invalid.Role = "ordinary-api"
		}
		if scenario == "wrong_domain" {
			e := proof.Evidence
			e.Domain = "controlled-lab-c"
			invalid.Evidence, err = SignAuthorizationEvidence(c.evidence, e)
			if err != nil {
				t.Fatal(err)
			}
		}
		if scenario != "unsigned" {
			invalid, err = SignAuthorizationRecovery(c.recovery, invalid)
			if err != nil {
				t.Fatal(err)
			}
		}
		if err := c.gate.Recover(ctx, invalid); !errors.Is(err, ErrAuthorizationUnavailable) {
			t.Fatalf("%s V recovery accepted: %v", scenario, err)
		}
	}
	assertVerifierFrozen(t, c)
	valid, err := SignAuthorizationRecovery(c.recovery, request)
	if err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Recover(ctx, valid); err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Recover(ctx, valid); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("replayed V recovery accepted: %v", err)
	}
	if count(t, c.lab.vp, `SELECT count(*) FROM v_auth.authorization_gate_audit WHERE event_kind='RECOVER' AND operation_id='V-restricted-recovery' AND mode='NORMAL'`) != 1 {
		t.Fatal("V signed recovery audit missing or duplicated")
	}
}

func TestVerifierGateEvidenceProviderWaitUsesFinalClockPostgres(t *testing.T) {
	for _, scenario := range []string{"expired", "rollback"} {
		t.Run(scenario, func(t *testing.T) {
			c := newVerifierGateControl(t)
			ctx := context.Background()
			if _, err := c.gate.Snapshot(ctx); err != nil {
				t.Fatal(err)
			}
			proof, err := c.provider.Current(ctx)
			if err != nil {
				t.Fatal(err)
			}
			at := c.clock.now()
			c.gate.evidence = authorizationEvidenceFunc(func(context.Context) (SignedAuthorizationEvidence, error) {
				if scenario == "expired" {
					c.clock.set(at.Add(authorizationEvidenceTTL + time.Nanosecond))
				} else {
					c.clock.set(at.Add(-authorizationSkew - time.Nanosecond))
				}
				return proof, nil
			})
			if _, err := c.gate.Snapshot(ctx); !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatalf("%s during evidence retrieval escaped final V clock check: %v", scenario, err)
			}
			assertVerifierFrozen(t, c)
		})
	}
	// A normal recovery's second provider read occurs while both authority
	// locks are held. Its wait cannot reuse the pre-fetch validity decision.
	c := newVerifierGateControl(t)
	ctx := context.Background()
	if err := c.gate.Freeze(ctx, "provider wait during V recovery"); err != nil {
		t.Fatal(err)
	}
	proof := c.signed(t, c.evidence, 3, 3, c.clock.now(), c.clock.now().Add(authorizationEvidenceTTL))
	calls := 0
	c.gate.evidence = authorizationEvidenceFunc(func(context.Context) (SignedAuthorizationEvidence, error) {
		calls++
		if calls == 2 {
			c.clock.set(c.clock.now().Add(authorizationEvidenceTTL + time.Nanosecond))
		}
		return proof, nil
	})
	request, err := SignAuthorizationRecovery(c.recovery, AuthorizationRecoveryRequest{Role: "authorization-recovery", Actor: "provider-wait-test", Reason: "expired during final provider fetch", OperationID: "V-provider-wait", Mode: AuthorizationRecoveryNormal, Evidence: proof})
	if err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Recover(ctx, request); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("provider wait expired proof but V recovery succeeded: %v", err)
	}
	assertVerifierFrozen(t, c)
	if count(t, c.lab.vp, `SELECT count(*) FROM v_auth.authorization_gate_audit WHERE operation_id='V-provider-wait'`) != 0 {
		t.Fatal("expired provider-wait recovery audit was committed")
	}
}

func TestVerifierGateOfflineBreakGlassExpiresPostgres(t *testing.T) {
	c := newVerifierGateControl(t)
	ctx := context.Background()
	if _, err := c.gate.Snapshot(ctx); err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Freeze(ctx, "V online evidence outage"); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(c.provider.Path); err != nil {
		t.Fatal(err)
	}
	c.clock.set(c.clock.now().Add(time.Second))
	proof := c.signed(t, c.glass, 3, 3, c.clock.now(), c.clock.now().Add(authorizationEvidenceTTL))
	request, err := SignAuthorizationRecovery(c.glass, AuthorizationRecoveryRequest{Role: "authorization-recovery", Actor: "V-offline-test", Reason: "isolated offline material", OperationID: "V-offline-recovery", Mode: AuthorizationRecoveryBreakGlass, Evidence: proof})
	if err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Recover(ctx, request); err != nil {
		t.Fatal(err)
	}
	if decision, err := c.gate.Snapshot(ctx); err != nil || decision.Generation != 3 {
		t.Fatalf("V break-glass failed without online provider: %+v %v", decision, err)
	}
	c.clock.set(c.clock.now().Add(authorizationEvidenceTTL + time.Nanosecond))
	assertVerifierFrozen(t, c)
	if count(t, c.lab.vp, `SELECT count(*) FROM v_auth.authorization_gate_audit WHERE operation_id='V-offline-recovery' AND mode='BREAK_GLASS'`) != 1 {
		t.Fatal("V break-glass audit missing")
	}
}
