package authprivacy

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type gateTestClock struct {
	mu sync.Mutex
	at time.Time
}

func (c *gateTestClock) now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.at
}

func (c *gateTestClock) set(at time.Time) {
	c.mu.Lock()
	c.at = at
	c.mu.Unlock()
}

type gateControl struct {
	lab      *lab
	gate     *PostgresAuthorizationGate
	config   AuthorizationGateConfig
	provider *FileAuthorizationEvidenceProvider
	clock    *gateTestClock
	evidence ed25519.PrivateKey
	recovery ed25519.PrivateKey
	glass    ed25519.PrivateKey
}

func newGateControl(t *testing.T) *gateControl {
	t.Helper()
	l := newLab(t)
	ctx := context.Background()
	if err := l.gate.Freeze(ctx, "controlled test setup"); err != nil {
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
	provider := NewFileAuthorizationEvidenceProvider(filepath.Join(dir, "evidence.json"))
	anchor, err := NewFileAuthorizationAnchorStore(filepath.Join(dir, "anchor.json"), ak)
	if err != nil {
		t.Fatal(err)
	}
	clock := &gateTestClock{at: time.Now().UTC()}
	cfg := AuthorizationGateConfig{
		Pool: l.cp, Domain: "controlled-lab-c", Evidence: provider,
		EvidencePublicKey: ep, RecoveryPublicKey: rp, BreakGlassPublicKey: bp,
		Anchor: anchor, Clock: clock.now,
	}
	g, err := NewPostgresAuthorizationGate(cfg)
	if err != nil {
		t.Fatal(err)
	}
	c := &gateControl{lab: l, gate: g, config: cfg, provider: provider, clock: clock, evidence: ek, recovery: rk, glass: bk}
	c.recover(t, AuthorizationRecoveryBreakGlass, 2, 2)
	l.gate, l.c.gate = g, g
	return c
}

func (c *gateControl) signed(t *testing.T, key ed25519.PrivateKey, generation, version uint64, issued, until time.Time) SignedAuthorizationEvidence {
	t.Helper()
	s, err := SignAuthorizationEvidence(key, AuthorizationEvidence{
		Domain: c.config.Domain, Generation: generation, Version: version,
		IssuedAt: issued, TrustedAt: issued, ValidUntil: until,
	})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func (c *gateControl) recover(t *testing.T, mode AuthorizationRecoveryMode, generation, version uint64) {
	t.Helper()
	at := c.clock.now()
	online := c.signed(t, c.evidence, generation, version, at, at.Add(5*time.Minute))
	if err := c.provider.Store(context.Background(), online); err != nil {
		t.Fatal(err)
	}
	proof, key := online, c.recovery
	if mode == AuthorizationRecoveryBreakGlass {
		proof, key = c.signed(t, c.glass, generation, version, at, at.Add(5*time.Minute)), c.glass
	}
	request, err := SignAuthorizationRecovery(key, AuthorizationRecoveryRequest{
		Role: "authorization-recovery", Actor: "test-recovery-role", Reason: "verified isolated recovery",
		OperationID: "recovery-" + time.Now().Format("150405.000000000"), Mode: mode, Evidence: proof,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Recover(context.Background(), request); err != nil {
		t.Fatal(err)
	}
}

func assertFrozen(t *testing.T, c *gateControl) {
	t.Helper()
	if _, err := c.gate.Snapshot(context.Background()); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("gate permitted authorization: %v", err)
	}
	var state string
	if err := c.lab.cp.QueryRow(context.Background(), `SELECT gate_state FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&state); err != nil || state != "FROZEN" {
		t.Fatalf("freeze not durable: state=%q err=%v", state, err)
	}
}

func TestAuthorizationGateRollbackBoundaryAndPersistence(t *testing.T) {
	for _, delta := range []struct {
		name   string
		back   time.Duration
		frozen bool
	}{{"five_seconds_tolerated", 5 * time.Second, false}, {"more_than_five_seconds_frozen", 5*time.Second + time.Nanosecond, true}} {
		t.Run(delta.name, func(t *testing.T) {
			c := newGateControl(t)
			ctx := context.Background()
			baseline, err := c.gate.Snapshot(ctx)
			if err != nil {
				t.Fatal(err)
			}
			c.clock.set(baseline.TrustedAt.Add(-delta.back))
			decision, err := c.gate.Snapshot(ctx)
			if delta.frozen {
				if !errors.Is(err, ErrAuthorizationUnavailable) {
					t.Fatalf("rollback %v accepted: %v", delta.back, err)
				}
				assertFrozen(t, c)
				restarted, err := NewPostgresAuthorizationGate(c.config)
				if err != nil {
					t.Fatal(err)
				}
				if _, err = restarted.Snapshot(ctx); !errors.Is(err, ErrAuthorizationUnavailable) {
					t.Fatal("process restart erased freeze")
				}
				return
			}
			if err != nil || !decision.TrustedAt.Equal(baseline.TrustedAt) {
				t.Fatalf("tolerated jitter lowered high-watermark: %+v %v", decision, err)
			}
		})
	}
}

func TestAuthorizationGateEvidenceAndReplicaFailures(t *testing.T) {
	for _, scenario := range []string{"ttl_boundary", "expired", "missing", "bad_signature", "older_version", "future", "missing_anchor", "replica", "database_unavailable"} {
		t.Run(scenario, func(t *testing.T) {
			c := newGateControl(t)
			ctx := context.Background()
			// A successful online refresh retires the emergency offline proof.
			if _, err := c.gate.Snapshot(ctx); err != nil {
				t.Fatal(err)
			}
			at := c.clock.now()
			switch scenario {
			case "ttl_boundary":
				c.clock.set(at.Add(5 * time.Minute))
				if _, err := c.gate.Snapshot(ctx); err != nil {
					t.Fatalf("evidence at the five-minute boundary was rejected: %v", err)
				}
				return
			case "expired":
				c.clock.set(at.Add(5*time.Minute + time.Nanosecond))
			case "missing":
				if err := os.Remove(c.provider.Path); err != nil {
					t.Fatal(err)
				}
			case "bad_signature":
				s := c.signed(t, c.evidence, 2, 3, at, at.Add(5*time.Minute))
				s.Signature[0] ^= 1
				if err := c.provider.Store(ctx, s); err != nil {
					t.Fatal(err)
				}
			case "older_version":
				if err := c.provider.Store(ctx, c.signed(t, c.evidence, 2, 1, at, at.Add(5*time.Minute))); err != nil {
					t.Fatal(err)
				}
			case "future":
				future := at.Add(authorizationSkew + time.Nanosecond)
				if err := c.provider.Store(ctx, c.signed(t, c.evidence, 2, 3, future, future.Add(5*time.Minute))); err != nil {
					t.Fatal(err)
				}
			case "missing_anchor":
				if err := os.Remove(c.config.Anchor.Path); err != nil {
					t.Fatal(err)
				}
			case "replica":
				otherPool, err := pgxpool.New(ctx, os.Getenv("AUTHLAB_C_DSN"))
				if err != nil {
					t.Fatal(err)
				}
				defer otherPool.Close()
				otherConfig := c.config
				otherConfig.Pool = otherPool
				other, err := NewPostgresAuthorizationGate(otherConfig)
				if err != nil {
					t.Fatal(err)
				}
				if err = c.gate.Freeze(ctx, "replica A detected failure"); err != nil {
					t.Fatal(err)
				}
				if _, err = other.Snapshot(ctx); !errors.Is(err, ErrAuthorizationUnavailable) {
					t.Fatal("replica B authorized after A froze")
				}
			case "database_unavailable":
				c.lab.cp.Close()
			}
			if scenario == "database_unavailable" {
				if _, err := c.gate.Snapshot(ctx); !errors.Is(err, ErrAuthorizationUnavailable) {
					t.Fatalf("failed database query fell back to wall clock: %v", err)
				}
				return
			}
			assertFrozen(t, c)
		})
	}
}

func TestAuthorizationGateExplicitRecoveryFencesPendingAndBearer(t *testing.T) {
	c := newGateControl(t)
	l := c.lab
	ctx := context.Background()
	ticket, private := l.ticket(t)
	_, pending := l.intent(t, ticket, private, "pending_gate_user")
	validTicket, validPrivate := l.ticket(t)
	_, valid := l.intent(t, validTicket, validPrivate, "committed_gate_user")
	committed, err := l.c.CommitSignup(ctx, valid)
	if err != nil {
		t.Fatal(err)
	}
	if account, err := l.c.AuthorizeExistingSession(ctx, committed.SessionToken); err != nil || account != committed.AccountID {
		t.Fatalf("fresh bearer rejected: %v", err)
	}
	if err := c.gate.Freeze(ctx, "recovery scenario"); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.AuthorizeExistingSession(ctx, committed.SessionToken); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("old bearer read escaped freeze: %v", err)
	}
	if _, err := l.c.CommitSignup(ctx, pending); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("pending signup escaped freeze: %v", err)
	}
	if _, err := l.c.CommitSignup(ctx, valid); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("old idempotency key escaped freeze: %v", err)
	}
	// Fresh evidence alone never reopens a frozen gate.
	c.clock.set(c.clock.now().Add(time.Second))
	if err := c.provider.Store(ctx, c.signed(t, c.evidence, 3, 3, c.clock.now(), c.clock.now().Add(5*time.Minute))); err != nil {
		t.Fatal(err)
	}
	assertFrozen(t, c)
	c.recover(t, AuthorizationRecoveryNormal, 3, 3)
	decision, err := c.gate.Snapshot(ctx)
	if err != nil || decision.Generation != 3 {
		t.Fatalf("explicit recovery failed to advance generation: %+v %v", decision, err)
	}
	if _, err := l.c.CommitSignup(ctx, pending); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("old pending generation was reused: %v", err)
	}
	if _, err := l.c.AuthorizeExistingSession(ctx, committed.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("old bearer revived after generation advance: %v", err)
	}
	if replay, err := l.c.CommitSignup(ctx, valid); err != nil || !replay.Replay || replay.SessionToken != ([32]byte{}) {
		t.Fatalf("historical replay gained authority or lost its tombstone: %+v %v", replay, err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE username='committed_gate_user'`) != 1 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE username='pending_gate_user'`) != 0 {
		t.Fatal("recovery rolled back a committed fact or admitted old command")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.authorization_gate_audit WHERE event_kind='RECOVER' AND authorization_generation=3 AND actor='test-recovery-role' AND mode='NORMAL'`) != 1 {
		t.Fatal("recovery was not audited")
	}
}

func TestAuthorizationGateOldSnapshotCannotReopen(t *testing.T) {
	for _, mode := range []string{"generation", "evidence_version", "high_watermark"} {
		t.Run(mode, func(t *testing.T) {
			c := newGateControl(t)
			ctx := context.Background()
			decision, err := c.gate.Snapshot(ctx)
			if err != nil {
				t.Fatal(err)
			}
			ticket, private := c.lab.ticket(t)
			_, request := c.lab.intent(t, ticket, private, "snapshot_bearer_user")
			created, err := c.lab.c.CommitSignup(ctx, request)
			if err != nil {
				t.Fatal(err)
			}
			// A schema owner simulates an old database image. Ordinary updates
			// cannot do this because of the trigger; the external anchor remains.
			mustExec(t, c.lab.cp, `ALTER TABLE c_auth.authorization_gate DISABLE TRIGGER authorization_gate_monotonic`)
			switch mode {
			case "generation":
				mustExec(t, c.lab.cp, `UPDATE c_auth.authorization_gate SET authorization_generation=1 WHERE singleton_id=1`)
			case "evidence_version":
				mustExec(t, c.lab.cp, `UPDATE c_auth.authorization_gate SET evidence_version=1 WHERE singleton_id=1`)
			case "high_watermark":
				mustExec(t, c.lab.cp, `UPDATE c_auth.authorization_gate SET trusted_high_watermark=$1 WHERE singleton_id=1`, decision.TrustedAt.Add(-time.Second))
			}
			mustExec(t, c.lab.cp, `ALTER TABLE c_auth.authorization_gate ENABLE TRIGGER authorization_gate_monotonic`)
			assertFrozen(t, c)
			if _, err := c.lab.c.AuthorizeExistingSession(ctx, created.SessionToken); !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatalf("restored bearer escaped old-snapshot freeze: %v", err)
			}
			if count(t, c.lab.cp, `SELECT count(*) FROM c_auth.authorization_gate_audit WHERE event_kind='FREEZE' AND reason='SNAPSHOT_OR_ANCHOR_MISMATCH'`) != 1 {
				t.Fatal("old snapshot was not recorded as a security freeze")
			}
		})
	}
}

func TestAuthorizationGateRecoveryRequiresRestrictedSignedAction(t *testing.T) {
	c := newGateControl(t)
	ctx := context.Background()
	if err := c.gate.Freeze(ctx, "recovery authorization test"); err != nil {
		t.Fatal(err)
	}
	c.clock.set(c.clock.now().Add(time.Second))
	at := c.clock.now()
	evidence := c.signed(t, c.evidence, 3, 3, at, at.Add(5*time.Minute))
	if err := c.provider.Store(ctx, evidence); err != nil {
		t.Fatal(err)
	}
	request := AuthorizationRecoveryRequest{
		Role: "authorization-recovery", Actor: "restricted-test-role", Reason: "independent evidence checked",
		OperationID: "restricted-recovery-1", Mode: AuthorizationRecoveryNormal, Evidence: evidence,
	}
	wrongRole := request
	wrongRole.Role = "ordinary-api"
	wrongRole, err := SignAuthorizationRecovery(c.recovery, wrongRole)
	if err != nil {
		t.Fatal(err)
	}
	if err = c.gate.Recover(ctx, wrongRole); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("ordinary role reopened gate")
	}
	unsigned := request
	if err = c.gate.Recover(ctx, unsigned); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("unsigned recovery reopened gate")
	}
	stale := request
	stale.Evidence = c.signed(t, c.evidence, 2, 2, at, at.Add(5*time.Minute))
	stale, err = SignAuthorizationRecovery(c.recovery, stale)
	if err != nil {
		t.Fatal(err)
	}
	if err = c.gate.Recover(ctx, stale); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("old evidence reopened gate")
	}
	assertFrozen(t, c)
	valid, err := SignAuthorizationRecovery(c.recovery, request)
	if err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Recover(ctx, valid); err != nil {
		t.Fatal(err)
	}
	if _, err = c.gate.Snapshot(ctx); err != nil {
		t.Fatal(err)
	}
	if err = c.gate.Recover(ctx, valid); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("replayed recovery action advanced generation")
	}
	if count(t, c.lab.cp, `SELECT count(*) FROM c_auth.authorization_gate_audit WHERE event_kind='RECOVER' AND operation_id='restricted-recovery-1' AND mode='NORMAL'`) != 1 {
		t.Fatal("restricted recovery audit missing or duplicated")
	}
}

func TestAuthorizationGateOfflineBreakGlassExpiresWithoutProvider(t *testing.T) {
	c := newGateControl(t)
	ctx := context.Background()
	if err := c.gate.Freeze(ctx, "online source outage"); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(c.provider.Path); err != nil {
		t.Fatal(err)
	}
	c.clock.set(c.clock.now().Add(time.Second))
	at := c.clock.now()
	proof := c.signed(t, c.glass, 3, 3, at, at.Add(5*time.Minute))
	request, err := SignAuthorizationRecovery(c.glass, AuthorizationRecoveryRequest{
		Role: "authorization-recovery", Actor: "isolated-break-glass-role", Reason: "offline recovery material",
		OperationID: "offline-recovery-1", Mode: AuthorizationRecoveryBreakGlass, Evidence: proof,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Recover(ctx, request); err != nil {
		t.Fatal(err)
	}
	if decision, err := c.gate.Snapshot(ctx); err != nil || decision.Generation != 3 {
		t.Fatalf("offline recovery failed without provider: %+v %v", decision, err)
	}
	c.clock.set(at.Add(5*time.Minute + time.Nanosecond))
	assertFrozen(t, c)
	if count(t, c.lab.cp, `SELECT count(*) FROM c_auth.authorization_gate_audit WHERE event_kind='RECOVER' AND mode='BREAK_GLASS' AND operation_id='offline-recovery-1'`) != 1 {
		t.Fatal("break-glass recovery audit missing")
	}
}

func TestAuthorizationGateFinalTransactionFreezeAndRenewal(t *testing.T) {
	c := newGateControl(t)
	l := c.lab
	ctx := context.Background()
	ticket, private := l.ticket(t)
	_, request := l.intent(t, ticket, private, "frozen_signup_user")
	hold, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(ctx)
	if err := lockSlot(ctx, hold, ticket.Slot[:]); err != nil {
		t.Fatal(err)
	}
	answer := make(chan error, 1)
	go func() { _, e := l.c.CommitSignup(ctx, request); answer <- e }()
	waitBlocked(t, l.cp, 1)
	if err := c.gate.Freeze(ctx, "freeze after request start"); err != nil {
		t.Fatal(err)
	}
	if err := hold.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-answer; !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("in-flight signup committed after freeze: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE username='frozen_signup_user'`) != 0 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.sessions`) != 0 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.recovery_codes`) != 0 {
		t.Fatal("frozen signup left a privilege-bearing row")
	}
	// Restore explicitly, create a real session, then stage a renewal before a
	// second freeze. The provisional UPDATE must roll back unchanged.
	c.clock.set(c.clock.now().Add(time.Second))
	c.recover(t, AuthorizationRecoveryNormal, 3, 3)
	freshTicket, freshPrivate := l.ticket(t)
	_, fresh := l.intent(t, freshTicket, freshPrivate, "renewal_gate_user")
	created, err := l.c.CommitSignup(ctx, fresh)
	if err != nil {
		t.Fatal(err)
	}
	var before time.Time
	if err := l.cp.QueryRow(ctx, `SELECT expires_at FROM c_auth.sessions WHERE account_id=$1`, created.AccountID).Scan(&before); err != nil {
		t.Fatal(err)
	}
	expected, err := c.gate.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	tx, err := begin(ctx, l.cp)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(ctx, `UPDATE c_auth.sessions SET expires_at=expires_at+interval '1 day' WHERE account_id=$1`, created.AccountID); err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Freeze(ctx, "renewal final-check fault"); err != nil {
		t.Fatal(err)
	}
	if _, err := c.gate.CommitAuthorized(ctx, tx, expected.Generation); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("provisional renewal survived freeze: %v", err)
	}
	if err := c.gate.Abort(ctx, tx); err != nil {
		t.Fatal(err)
	}
	var after time.Time
	if err := l.cp.QueryRow(ctx, `SELECT expires_at FROM c_auth.sessions WHERE account_id=$1`, created.AccountID).Scan(&after); err != nil || !after.Equal(before) {
		t.Fatalf("frozen renewal changed expiry: %v old=%v new=%v", err, before, after)
	}
}

func TestAuthorizationGateVectorTimeRollback(t *testing.T) {
	var fixture struct {
		TimeCases []struct {
			ID        string `json:"id"`
			At        int64  `json:"lockedDecisionUnixSeconds"`
			Watermark int64  `json:"timeHighWatermarkUnixSeconds"`
			Decision  string `json:"expectedDecision"`
		} `json:"timeCases"`
	}
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "packages", "auth-protocol-vectors", "v1.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	var back time.Duration
	for _, vector := range fixture.TimeCases {
		if vector.ID == "TIME_RESTORE_CLOCK_ROLLBACK" {
			if vector.Decision != "FREEZE" {
				t.Fatal("fixed vector decision changed")
			}
			back = time.Duration(vector.Watermark-vector.At) * time.Second
		}
	}
	if back <= authorizationSkew {
		t.Fatal("rollback vector absent or no longer exceeds 5 seconds")
	}
	c := newGateControl(t)
	decision, err := c.gate.Snapshot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	c.clock.set(decision.TrustedAt.Add(-back))
	assertFrozen(t, c)
}

// Ensure the compiler keeps the public final transaction contract exercised
// by a future login/renewal caller even before those endpoints exist.
func TestAuthorizationGatePendingCommandGenerationFence(t *testing.T) {
	c := newGateControl(t)
	ctx := context.Background()
	ticket, private := c.lab.ticket(t)
	_, request := c.lab.intent(t, ticket, private, "staged_login_user")
	created, err := c.lab.c.CommitSignup(ctx, request)
	if err != nil {
		t.Fatal(err)
	}
	pending, err := c.gate.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	// Model the final SQL mutation of a future new-device login after its
	// expensive credential check. No username/password endpoint is implemented.
	tx, err := begin(ctx, c.lab.cp)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(ctx, `UPDATE c_auth.sessions SET revoked_at=$2 WHERE account_id=$1 AND revoked_at IS NULL`, created.AccountID, pending.TrustedAt); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(ctx, `UPDATE c_auth.accounts SET session_generation=2 WHERE account_id=$1`, created.AccountID); err != nil {
		t.Fatal(err)
	}
	token, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	newDigest := sha256.Sum256(token[:])
	revoke := digest("HNUHOLE/REVOKE-STORAGE/V1", token[:])
	var installation [16]byte
	if _, err := rand.Read(installation[:]); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO c_auth.sessions
		(token_digest,revoke_digest,account_id,installation_id,session_generation,
		 created_at,last_activity_at,expires_at,authorization_generation)
		VALUES($1,$2,$3,$4,2,$5,$5,$5::timestamptz+interval '30 days',$6)`,
		newDigest[:], revoke[:], created.AccountID, installation[:], pending.TrustedAt, int64(pending.Generation)); err != nil {
		t.Fatal(err)
	}
	if err := c.gate.Freeze(ctx, "work finished after freeze"); err != nil {
		t.Fatal(err)
	}
	if _, err := c.gate.CommitAuthorized(ctx, tx, pending.Generation); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("staged login command committed after freeze: %v", err)
	}
	if err := c.gate.Abort(ctx, tx); err != nil && !errors.Is(err, pgx.ErrTxClosed) {
		t.Fatal(err)
	}
	if count(t, c.lab.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1`, created.AccountID) != 1 ||
		count(t, c.lab.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, created.AccountID) != 1 {
		t.Fatal("frozen staged login changed the old or new session")
	}
	c.clock.set(c.clock.now().Add(time.Second))
	c.recover(t, AuthorizationRecoveryNormal, 3, 3)
	stale, err := begin(ctx, c.lab.cp)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c.gate.CommitAuthorized(ctx, stale, pending.Generation); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("old pre-KDF generation used after recovery: %v", err)
	}
	if err := c.gate.Abort(ctx, stale); err != nil {
		t.Fatal(err)
	}
}
