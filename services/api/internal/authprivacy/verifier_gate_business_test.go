package authprivacy

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func TestVerifierRequiresIndependentGate(t *testing.T) {
	pool := new(pgxpool.Pool)
	verifier := new(protocol.Verifier)
	key := [32]byte{1}
	var typedNil *PostgresAuthorizationGate
	for _, gate := range []AuthorizationGate{nil, typedNil, &PostgresAuthorizationGate{schema: "c_auth"}, &PostgresAuthorizationGate{}, &PostgresAuthorizationGate{schema: "v_auth", pool: pool}} {
		if _, err := NewVerifierStore(pool, verifier, key, gate); err == nil {
			t.Fatal("nil or community gate accepted for V")
		}
	}
	if _, err := NewVerifierStore(pool, verifier, key, &PostgresAuthorizationGate{schema: "v_auth"}); err != nil {
		t.Fatal(err)
	}
}

func controlVerifierGate(t *testing.T, l *lab) *gateControl {
	t.Helper()
	ctx := context.Background()
	if err := l.vGate.Freeze(ctx, "controlled V setup"); err != nil {
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
	config := AuthorizationGateConfig{Pool: l.vGate.pool, Schema: "v_auth", Domain: "controlled-lab-v-business", Evidence: provider, EvidencePublicKey: ep, RecoveryPublicKey: rp, BreakGlassPublicKey: bp, Anchor: anchor, Clock: clock.now}
	gate, err := NewPostgresAuthorizationGate(config)
	if err != nil {
		t.Fatal(err)
	}
	control := &gateControl{lab: l, gate: gate, config: config, provider: provider, clock: clock, evidence: ek, recovery: rk, glass: bk}
	control.recover(t, AuthorizationRecoveryBreakGlass, 2, 2)
	l.vGate, l.v.gate = gate, gate
	return control
}

func TestVerifierGateRefreshRemainsAvailableWhenBusinessPoolIsFull(t *testing.T) {
	l, e, _ := newOTPTestEligibility(t, MailSent)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	config := l.vp.Config().Copy()
	config.MaxConns = 2
	business, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	defer business.Close()
	store, err := NewVerifierStore(business, l.v.verifier, l.v.addressLockKey, l.vGate)
	if err != nil {
		t.Fatal(err)
	}
	e.store = store
	req := otpFixtureRequest(t, "v-full-business-pool@hainanu.edu.cn")
	blocker, err := begin(ctx, business)
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	if err = store.lockAddress(ctx, blocker, []byte(req.Email)); err != nil {
		t.Fatal(err)
	}
	result := make(chan error, 1)
	go func() { _, err := e.queueOTP(ctx, req); result <- err }()
	waitBlocked(t, l.vp, 1)
	if business.Stat().AcquiredConns() != 2 {
		t.Fatal("saturation barrier did not occupy all business connections")
	}
	if _, err = l.vGate.Snapshot(ctx); err != nil {
		t.Fatalf("business pool starvation blocked independent V refresh: %v", err)
	}
	if err = blocker.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err = <-result; err != nil {
		t.Fatalf("business operation failed after saturated lock release: %v", err)
	}
}

func recoverVerifierBusinessGate(t *testing.T, c *gateControl) {
	t.Helper()
	if err := c.gate.Freeze(context.Background(), "external-stage recovery"); err != nil {
		t.Fatal(err)
	}
	c.recover(t, AuthorizationRecoveryNormal, 3, 3)
}

func TestVerifierFrozenProtectsOTPResultsMailReceiptsAndCleanup(t *testing.T) {
	l, e, mail := newConfirmationTestEligibility(t)
	ctx := context.Background()
	req := confirmationFixture(t, l, e, mail, "v-freeze-all@hainanu.edu.cn")
	queued := otpFixtureRequest(t, "v-freeze-mail@hainanu.edu.cn")
	if _, err := e.queueOTP(ctx, queued); err != nil {
		t.Fatal(err)
	}
	ticket, _ := l.ticket(t)
	if _, err := l.v.ReserveAfterQualification(ctx, []byte("v-freeze-receipt@hainanu.edu.cn"), ticket.BootstrapKey); err != nil {
		t.Fatal(err)
	}
	beforeBudgets := count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events`)
	if err := l.vGate.Freeze(ctx, "V business fail closed"); err != nil {
		t.Fatal(err)
	}
	checks := []struct {
		name string
		run  func() error
	}{
		{"request", func() error {
			_, err := e.RequestOTP(ctx, otpFixtureRequest(t, "v-freeze-new@hainanu.edu.cn"))
			return err
		}},
		{"confirm", func() error { _, err := e.ConfirmOTP(ctx, req); return err }},
		{"request_result", func() error { _, err := e.GetOTPRequestResult(ctx, queued.Key, queued.InstallationID); return err }},
		{"confirmation_result", func() error {
			_, err := e.GetOTPConfirmationResult(ctx, req.Key, req.FlowID, req.InstallationID)
			return err
		}},
		{"mail", func() error { _, err := e.DispatchMail(ctx, queued.Key); return err }},
		{"receipt", func() error {
			return l.v.ProcessReceipt(ctx, confirmationReceipt(t, l, ticket.Slot, protocol.PurposeReleased), protocol.PurposeReleased)
		}},
		{"cleanup_otp", func() error { return e.CleanupOTP(ctx, 50) }},
		{"cleanup_confirmation", func() error { _, err := e.CleanupConfirmations(ctx, 50); return err }},
		{"mail_worker", func() error { _, err := e.ResumeQueuedMail(ctx, 50); return err }},
		{"confirmation_worker", func() error { _, err := e.ResumePendingConfirmations(ctx, 50); return err }},
	}
	for _, check := range checks {
		t.Run(check.name, func(t *testing.T) {
			if err := check.run(); !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatalf("frozen V operation returned %v", err)
			}
		})
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events`) != beforeBudgets || count(t, l.vp, `SELECT count(*) FROM v_auth.mail_outbox WHERE state='QUEUED'`) != 1 || count(t, l.vp, `SELECT count(*) FROM v_auth.processed_receipts`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota`) != 1 {
		t.Fatal("frozen V changed business state")
	}
}

func TestVerifierGateIsIndependentOfCommunityFreeze(t *testing.T) {
	l, e, _ := newOTPTestEligibility(t, MailSent)
	if err := l.gate.Freeze(context.Background(), "C domain only"); err != nil {
		t.Fatal(err)
	}
	if _, err := e.RequestOTP(context.Background(), otpFixtureRequest(t, "v-independent@hainanu.edu.cn")); err != nil {
		t.Fatalf("C freeze disabled independent V: %v", err)
	}
	if err := l.vGate.Freeze(context.Background(), "V domain only"); err != nil {
		t.Fatal(err)
	}
}

func TestVerifierUnanchoredOldOTPResultCanEndWithoutAllocatingKeys(t *testing.T) {
	l, e, mail := newConfirmationTestEligibility(t)
	control := controlVerifierGate(t, l)
	ctx := context.Background()
	req := confirmationFixture(t, l, e, mail, "v-unanchored-result@hainanu.edu.cn")
	before := count(t, l.vp, `SELECT count(*) FROM v_auth.request_results`)
	assertState := func(key, flow [32]byte, installation [16]byte, wanted string) {
		t.Helper()
		result, err := e.GetOTPConfirmationResult(ctx, key, flow, installation)
		if err != nil || result.State != wanted || result.RegistrationTicket != "" {
			t.Fatalf("unanchored result: state=%s wanted=%s err=%v", result.State, wanted, err)
		}
	}
	assertState(req.Key, req.FlowID, req.InstallationID, "PENDING")
	if err := control.gate.Freeze(ctx, "unconfirmed flow freeze"); err != nil {
		t.Fatal(err)
	}
	if _, err := e.GetOTPConfirmationResult(ctx, req.Key, req.FlowID, req.InstallationID); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen result query authorized: %v", err)
	}
	control.recover(t, AuthorizationRecoveryNormal, 3, 3)
	if _, err := e.ConfirmOTP(ctx, req); !errors.Is(err, ErrOTPExpired) {
		t.Fatalf("old unconfirmed generation accepted: %v", err)
	}
	assertState(req.Key, req.FlowID, req.InstallationID, "REVERIFY_REQUIRED")
	wrongInstallation := req.InstallationID
	wrongInstallation[0] ^= 1
	assertState(req.Key, req.FlowID, wrongInstallation, "PENDING")
	assertState(req.Key, [32]byte{9}, req.InstallationID, "PENDING")
	assertState([32]byte{8}, req.FlowID, req.InstallationID, "REVERIFY_REQUIRED")
	if count(t, l.vp, `SELECT count(*) FROM v_auth.request_results`) != before ||
		count(t, l.vp, `SELECT count(*) FROM v_auth.otp_confirmations`) != 0 ||
		count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_sign_jobs`) != 0 {
		t.Fatal("result queries allocated keys, qualification or signing jobs")
	}
	current := confirmationFixture(t, l, e, mail, "v-current-unanchored@hainanu.edu.cn")
	assertState(current.Key, current.FlowID, current.InstallationID, "PENDING")
}

func TestVerifierLateSignatureCannotCrossFreezeOrRecovery(t *testing.T) {
	for _, recoverGate := range []bool{false, true} {
		t.Run(map[bool]string{false: "freeze", true: "recovery"}[recoverGate], func(t *testing.T) {
			l, e, mail := newConfirmationTestEligibility(t)
			control := controlVerifierGate(t, l)
			req := confirmationFixture(t, l, e, mail, "v-sign-generation@hainanu.edu.cn")
			calls := 0
			e.signer = func(ctx context.Context, _ uint32, message []byte) ([]byte, error) {
				calls++
				if recoverGate {
					recoverVerifierBusinessGate(t, control)
				} else if err := control.gate.Freeze(ctx, "signer in flight"); err != nil {
					t.Fatal(err)
				}
				return ed25519.Sign(l.vPrivate, message), nil
			}
			if result, err := e.ConfirmOTP(context.Background(), req); !errors.Is(err, ErrAuthorizationUnavailable) || result.RegistrationTicket != "" {
				t.Fatalf("late signature accepted: %+v %v", result, err)
			}
			if count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_sign_jobs WHERE state='READY' OR signature IS NOT NULL`) != 0 {
				t.Fatal("late signature persisted")
			}
			if recoverGate {
				if _, err := e.ConfirmOTP(context.Background(), req); !errors.Is(err, ErrReverifyRequired) {
					t.Fatalf("original command rebound to new generation: %v", err)
				}
				if result, err := e.GetOTPConfirmationResult(context.Background(), req.Key, req.FlowID, req.InstallationID); err != nil || result.State != "REVERIFY_REQUIRED" {
					t.Fatalf("stale pending result: %+v %v", result, err)
				}
				if _, err := e.ResumePendingConfirmations(context.Background(), 10); err != nil {
					t.Fatal(err)
				}
			}
			if calls != 1 {
				t.Fatal("old signing job restarted")
			}
		})
	}
}

type verifierMailFunc func(context.Context, [32]byte, string, string) (MailOutcome, error)

func (f verifierMailFunc) SendOTP(ctx context.Context, operation [32]byte, email, code string) (MailOutcome, error) {
	return f(ctx, operation, email, code)
}

func TestVerifierLateSMTPResultCannotReopenClaimAfterRecovery(t *testing.T) {
	l, e, _ := newOTPTestEligibility(t, MailSent)
	control := controlVerifierGate(t, l)
	req := otpFixtureRequest(t, "v-mail-generation@hainanu.edu.cn")
	if _, err := e.queueOTP(context.Background(), req); err != nil {
		t.Fatal(err)
	}
	calls := 0
	e.mail = verifierMailFunc(func(context.Context, [32]byte, string, string) (MailOutcome, error) {
		calls++
		recoverVerifierBusinessGate(t, control)
		return MailSent, nil
	})
	if outcome, err := e.DispatchMail(context.Background(), req.Key); outcome != MailUnknown || !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("late SMTP result accepted: %s %v", outcome, err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.mail_outbox WHERE state='DISPATCHING'`) != 1 {
		t.Fatal("old claim terminal was overwritten after recovery")
	}
	if _, err := e.ResumeQueuedMail(context.Background(), 10); err != nil {
		t.Fatal(err)
	}
	if _, err := e.DispatchMail(context.Background(), req.Key); err != nil {
		t.Fatal(err)
	}
	if calls != 1 {
		t.Fatal("ambiguous SMTP sent twice")
	}
}

func TestVerifierLateRetirementReplyCannotContinueOldQualification(t *testing.T) {
	l, e, mail := newConfirmationTestEligibility(t)
	control := controlVerifierGate(t, l)
	ctx := context.Background()
	email := "v-retirement-generation@hainanu.edu.cn"
	old, _ := l.ticket(t)
	if _, err := l.v.ReserveAfterQualification(ctx, []byte(email), old.BootstrapKey); err != nil {
		t.Fatal(err)
	}
	req := confirmationFixture(t, l, e, mail, email)
	peerCalls := 0
	receipt := confirmationReceipt(t, l, old.Slot, protocol.PurposeRetired)
	e.retirePeer = confirmationPeerFunc(func(context.Context, string) (RetirementReply, error) {
		peerCalls++
		recoverVerifierBusinessGate(t, control)
		return RetirementReply{Receipt: receipt}, nil
	})
	if _, err := e.ConfirmOTP(ctx, req); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("late peer reply continued qualification: %v", err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.processed_receipts`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE current_slot=$1`, req.SlotID[:]) != 0 {
		t.Fatal("late peer reply changed old/new reservation")
	}
	// An independently pushed, authenticated C terminal is historical evidence.
	// Current V authorization may release it, but must not revive its old OTP.
	if err := l.v.ProcessReceipt(ctx, receipt, protocol.PurposeRetired); err != nil {
		t.Fatal(err)
	}
	if _, err := e.ResumePendingConfirmations(ctx, 10); err != nil {
		t.Fatal(err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota`) != 0 || peerCalls != 1 {
		t.Fatal("old confirmation recreated quota or repeated retirement")
	}
}

func TestVerifierAddressLockWaitCannotCrossRecoveryGeneration(t *testing.T) {
	l, e, _ := newOTPTestEligibility(t, MailSent)
	control := controlVerifierGate(t, l)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	req := otpFixtureRequest(t, "v-address-lock-generation@hainanu.edu.cn")
	blocker, err := begin(ctx, l.vp)
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	if err = l.v.lockAddress(ctx, blocker, []byte(req.Email)); err != nil {
		t.Fatal(err)
	}
	result := make(chan error, 1)
	go func() { _, err := e.queueOTP(ctx, req); result <- err }()
	waitBlocked(t, l.vp, 1)
	recoverVerifierBusinessGate(t, control)
	if err = blocker.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err = <-result; !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("old generation survived address lock wait: %v", err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.otp_flows`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.mail_outbox`) != 0 {
		t.Fatal("lock waiter persisted old generation work")
	}
}

type verifierFinalTimeGate struct {
	AuthorizationGate
	beforeCommit func()
}

func (g *verifierFinalTimeGate) CommitAuthorized(ctx context.Context, tx pgx.Tx, generation uint64, checks ...func(AuthorizationDecision) error) (AuthorizationDecision, error) {
	if g.beforeCommit != nil {
		hook := g.beforeCommit
		g.beforeCommit = nil
		hook()
	}
	return g.AuthorizationGate.CommitAuthorized(ctx, tx, generation, checks...)
}

func TestVerifierMailClaimChecksExpiryAtFinalAuthorityPoint(t *testing.T) {
	l, e, capture := newOTPTestEligibility(t, MailSent)
	control := controlVerifierGate(t, l)
	ctx := context.Background()
	req := otpFixtureRequest(t, "v-final-mail-deadline@hainanu.edu.cn")
	if _, err := e.queueOTP(ctx, req); err != nil {
		t.Fatal(err)
	}
	l.v.gate = &verifierFinalTimeGate{AuthorizationGate: control.gate, beforeCommit: func() {
		at := control.clock.now().Add(5 * time.Minute)
		control.clock.set(at)
		signed := control.signed(t, control.evidence, 2, 3, at, at.Add(5*time.Minute))
		if err := control.provider.Store(ctx, signed); err != nil {
			t.Fatal(err)
		}
	}}
	if _, err := e.DispatchMail(ctx, req.Key); !errors.Is(err, ErrExpired) {
		t.Fatalf("mail claim passed final deadline: %v", err)
	}
	if calls, _ := capture.captured(); calls != 0 {
		t.Fatal("expired claim invoked SMTP")
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.mail_outbox WHERE state='QUEUED'`) != 1 {
		t.Fatal("expired claim was committed")
	}
	if _, err := control.gate.Snapshot(ctx); err != nil {
		t.Fatalf("ordinary mail expiry froze valid gate: %v", err)
	}
}

func TestVerifierConfirmationChecksOTPExpiryAtFinalAuthorityPoint(t *testing.T) {
	l, e, mail := newConfirmationTestEligibility(t)
	control := controlVerifierGate(t, l)
	ctx := context.Background()
	req := confirmationFixture(t, l, e, mail, "v-final-otp-deadline@hainanu.edu.cn")
	l.v.gate = &verifierFinalTimeGate{AuthorizationGate: control.gate, beforeCommit: func() {
		at := control.clock.now().Add(5 * time.Minute)
		control.clock.set(at)
		signed := control.signed(t, control.evidence, 2, 3, at, at.Add(5*time.Minute))
		if err := control.provider.Store(ctx, signed); err != nil {
			t.Fatal(err)
		}
	}}
	if _, err := e.ConfirmOTP(ctx, req); !errors.Is(err, ErrOTPExpired) {
		t.Fatalf("qualification passed final OTP deadline: %v", err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.otp_flows WHERE state='CONSUMED'`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_sign_jobs`) != 0 {
		t.Fatal("expired qualification committed consumption, quota or signature")
	}
	if _, err := control.gate.Snapshot(ctx); err != nil {
		t.Fatalf("ordinary OTP expiry froze valid gate: %v", err)
	}
}
