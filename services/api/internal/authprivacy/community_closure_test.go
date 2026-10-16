package authprivacy

import (
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func closureTestRequest(t *testing.T, bearer [32]byte) (ClosureRequest, [32]byte) {
	t.Helper()
	id, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	secret, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	return ClosureRequest{Bearer: bearer, ID: id, StatusDigest: digest("HNUHOLE/CLOSE-STATUS/V1", secret[:]), Password: labLoginPassword}, secret
}

func advanceClosureClock(t *testing.T, control *gateControl, at time.Time) {
	t.Helper()
	var generation, version uint64
	if err := control.lab.cp.QueryRow(context.Background(), `SELECT authorization_generation,evidence_version
		FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&generation, &version); err != nil {
		t.Fatal(err)
	}
	control.clock.set(at)
	evidence := control.signed(t, control.evidence, generation, version+1, at, at.Add(5*time.Minute))
	if err := control.provider.Store(context.Background(), evidence); err != nil {
		t.Fatal(err)
	}
}

func TestClosureRequestCapabilityAndFreshPasswordPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_status_user")
	passwords := sessionTestPasswordWorker(t, 2)
	request, secret := closureTestRequest(t, initial.SessionToken)
	wrong := request
	wrong.Password = "an incorrect independent credential phrase"
	if _, err := l.c.RequestAccountClosure(ctx, wrong, passwords); !errors.Is(err, ErrAuthenticationFailed) {
		t.Fatalf("wrong password submitted closure: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.closure_requests`) != 0 {
		t.Fatal("failed password left a closure")
	}
	mustExec(t, l.cp, `UPDATE c_auth.account_restrictions SET mute_state='MUTED',version=version+1 WHERE account_id=$1`, initial.AccountID)
	accepted, err := l.c.RequestAccountClosure(ctx, request, passwords)
	if err != nil || accepted.ID != request.ID || !accepted.DueAt.Equal(control.clock.now().Add(closureWaitingPeriod)) {
		t.Fatalf("wrong accepted closure: %+v %v", accepted, err)
	}
	status, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "PENDING" || status.DueAt == nil || status.ReleaseReceipt != "" {
		t.Fatalf("bad pending status: %+v %v", status, err)
	}
	if _, err = l.c.GetCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("closure left community access: %v", err)
	}
	if _, err = l.c.RenewCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("renewal revived pending closure: %v", err)
	}
	if _, err = l.c.RequestAccountClosure(ctx, request, passwords); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("historical bearer gained closure replay authority: %v", err)
	}
	wrongSecret := secret
	wrongSecret[0] ^= 1
	if _, err = l.c.GetAccountClosureStatus(ctx, request.ID, wrongSecret); !errors.Is(err, ErrClosureNotFound) {
		t.Fatalf("wrong capability disclosed status: %v", err)
	}
	if _, err = l.c.GetCurrentSession(ctx, secret); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("status capability became bearer: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.closure_requests WHERE account_id=$1 AND state='PENDING'`, initial.AccountID) != 1 {
		t.Fatal("pending authority missing")
	}
}

func TestClosureLoginCancellationAndExactDeadlinePostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_login_user")
	passwords := sessionTestPasswordWorker(t, 2)
	request, secret := closureTestRequest(t, initial.SessionToken)
	if _, err := l.c.RequestAccountClosure(ctx, request, passwords); err != nil {
		t.Fatal(err)
	}
	fresh, err := l.c.CreateSession(ctx, sessionTestRequest(t, "closure_login_user"), passwords)
	if err != nil {
		t.Fatalf("explicit login did not cancel before deadline: %v", err)
	}
	status, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "CANCELLED" || status.DueAt != nil || status.ReleaseReceipt != "" {
		t.Fatalf("cancelled response retained private state: %+v %v", status, err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.closure_requests WHERE closure_id=$1 AND state='CANCELLED'
		AND account_id IS NULL AND slot_id IS NULL AND due_at IS NULL AND request_generation IS NULL`, request.ID[:]) != 1 {
		t.Fatal("cancellation retained account mapping")
	}
	replay := request
	replay.Bearer = fresh.SessionToken
	if _, err = l.c.RequestAccountClosure(ctx, replay, passwords); !errors.Is(err, ErrConflict) {
		t.Fatalf("cancelled old ID recreated request: %v", err)
	}
	second, secondSecret := closureTestRequest(t, fresh.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, second, passwords)
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	status, err = l.c.GetAccountClosureStatus(ctx, second.ID, secondSecret)
	if err != nil || status.State != "FINALIZING" || status.DueAt == nil {
		t.Fatalf("deadline did not become finalizing without worker: %+v %v", status, err)
	}
	if _, err = l.c.CreateSession(ctx, sessionTestRequest(t, "closure_login_user"), passwords); !errors.Is(err, ErrAccountUnavailable) {
		t.Fatalf("login cancelled at deadline: %v", err)
	}
	if err = l.c.ApplyAccountBan(ctx, initial.AccountID, 1, nil); err != nil {
		t.Fatalf("late trusted moderation write failed: %v", err)
	}
	status, err = l.c.GetAccountClosureStatus(ctx, second.ID, secondSecret)
	if err != nil || status.State != "FINALIZING" {
		t.Fatalf("late ban cancelled finalizing request: %+v %v", status, err)
	}
	closed, err := l.c.FinalizeDueClosures(ctx, 10)
	if err != nil || closed != 1 {
		t.Fatalf("deadline close failed: %d %v", closed, err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='CLOSED'
		AND username IS NULL AND password_hash IS NULL AND password_salt IS NULL AND active_reset_intent_id IS NULL`, initial.AccountID) != 1 {
		t.Fatal("close did not erase active credentials")
	}
}

func TestClosureBlockedLoginCannotUseStartTimePostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_wait_user")
	passwords := sessionTestPasswordWorker(t, 2)
	request, secret := closureTestRequest(t, initial.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, passwords)
	if err != nil {
		t.Fatal(err)
	}
	hold, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(ctx)
	var state string
	if err = hold.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, initial.AccountID).Scan(&state); err != nil {
		t.Fatal(err)
	}
	loginRequest := sessionTestRequest(t, "closure_wait_user")
	answer := make(chan error, 1)
	go func() { _, e := l.c.CreateSession(ctx, loginRequest, passwords); answer <- e }()
	waitLock(t, l.cp, "transactionid", 1)
	advanceClosureClock(t, control, accepted.DueAt)
	if err = hold.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err = <-answer; !errors.Is(err, ErrAccountUnavailable) {
		t.Fatalf("login used lock-wait start time: %v", err)
	}
	status, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "FINALIZING" {
		t.Fatalf("waiter cancelled closure: %+v %v", status, err)
	}
}

func TestClosureFreezeAndRecoveryFencePostgres(t *testing.T) {
	for _, mode := range []string{"credential_change", "freeze"} {
		t.Run(mode, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			ctx := context.Background()
			initial := sessionTestAccount(t, l, "closure_proof_user")
			passwords := sessionTestPasswordWorker(t, 2)
			request, _ := closureTestRequest(t, initial.SessionToken)
			paused := &pausingPasswordVerifier{inner: passwords, ready: make(chan struct{}), resume: make(chan struct{})}
			answer := make(chan error, 1)
			go func() { _, e := l.c.RequestAccountClosure(ctx, request, paused); answer <- e }()
			<-paused.ready
			if mode == "freeze" {
				if err := control.gate.Freeze(ctx, "closure KDF pause"); err != nil {
					t.Fatal(err)
				}
			} else {
				newMaterial, err := passwords.PreparePassword(ctx, "a newly replaced independent credential phrase", "closure_proof_user")
				if err != nil {
					t.Fatal(err)
				}
				mustExec(t, l.cp, `UPDATE c_auth.accounts SET password_hash=$2,password_salt=$3,credential_version=credential_version+1
					WHERE account_id=$1`, initial.AccountID, newMaterial.Hash[:], newMaterial.Salt[:])
			}
			close(paused.resume)
			want := ErrCredentialStateChanged
			if mode == "freeze" {
				want = ErrAuthorizationUnavailable
			}
			if err := <-answer; !errors.Is(err, want) {
				t.Fatalf("stale closure proof committed: %v", err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.closure_requests`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE operation='CLOSURE'`) != 0 {
				t.Fatal("rejected closure left state or tombstone")
			}
			if mode == "freeze" {
				control.clock.set(control.clock.now().Add(time.Second))
				control.recover(t, AuthorizationRecoveryNormal, 3, 3)
				if _, err := l.c.RequestAccountClosure(ctx, request, passwords); !errors.Is(err, ErrSessionInvalid) {
					t.Fatalf("old generation bearer survived recovery: %v", err)
				}
			}
		})
	}
}

func TestClosureBanCancelsBeforeDeadlineAndRevokesPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_ban_user")
	passwords := sessionTestPasswordWorker(t, 2)
	if err := l.c.ApplyAccountBan(ctx, initial.AccountID, 1, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.GetCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("banned bearer still active: %v", err)
	}
	mustExec(t, l.cp, `UPDATE c_auth.account_restrictions SET ban_state='NONE',ban_ends_at=NULL,version=version+1 WHERE account_id=$1`, initial.AccountID)
	if _, err := l.c.GetCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("unban revived revoked bearer: %v", err)
	}
	fresh, err := l.c.CreateSession(ctx, sessionTestRequest(t, "closure_ban_user"), passwords)
	if err != nil {
		t.Fatal(err)
	}
	request, secret := closureTestRequest(t, fresh.SessionToken)
	if _, err = l.c.RequestAccountClosure(ctx, request, passwords); err != nil {
		t.Fatal(err)
	}
	if err = l.c.ApplyAccountBan(ctx, initial.AccountID, 3, nil); err != nil {
		t.Fatal(err)
	}
	status, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "CANCELLED" || status.DueAt != nil {
		t.Fatalf("predeadline ban did not cancel: %+v %v", status, err)
	}
	if err = l.c.ApplyAccountBan(ctx, initial.AccountID, 3, nil); !errors.Is(err, ErrRestrictionStateChanged) {
		t.Fatalf("stale moderation version changed authority: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='ACTIVE'`, initial.AccountID) != 1 {
		t.Fatal("predeadline ban left pending account")
	}
}

func TestClosureReleaseACKAndStatusRetentionPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_release_user")
	passwords := sessionTestPasswordWorker(t, 2)
	request, secret := closureTestRequest(t, initial.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, passwords)
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	if closed, err := l.c.FinalizeDueClosures(ctx, 10); err != nil || closed != 1 {
		t.Fatalf("close failed: %d %v", closed, err)
	}
	status, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "CLOSED_RELEASE_PENDING" || status.ReleaseReceipt != "" {
		t.Fatalf("unsigned close was not pending: %+v %v", status, err)
	}
	var slot protocol.SlotID
	var rawSlot []byte
	if err = l.cp.QueryRow(ctx, `SELECT slot_id FROM c_auth.closure_requests WHERE closure_id=$1`, request.ID[:]).Scan(&rawSlot); err != nil {
		t.Fatal(err)
	}
	copy(slot[:], rawSlot)
	if _, err = l.c.SignReceipt(ctx, slot, func(context.Context, uint32, []byte) ([]byte, error) {
		return nil, errors.New("isolated signer outage")
	}); err == nil {
		t.Fatal("signer fault unexpectedly succeeded")
	}
	status, err = l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "CLOSED_RELEASE_PENDING" {
		t.Fatalf("signing fault changed committed terminal: %+v %v", status, err)
	}
	signer := func(_ context.Context, _ uint32, message []byte) ([]byte, error) {
		return ed25519.Sign(l.cPrivate, message), nil
	}
	if ok, err := l.c.SignReceipt(ctx, slot, signer); err != nil || !ok {
		t.Fatalf("postcommit signing failed: %v %v", ok, err)
	}
	if err = l.c.DeliverReceipt(ctx, slot, func(context.Context, string, protocol.Purpose) error { return errors.New("isolated ACK outage") }); err == nil {
		t.Fatal("ACK fault unexpectedly succeeded")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1 AND receipt_acknowledged`, slot[:]) != 0 {
		t.Fatal("failed ACK changed release authority")
	}
	if err = l.c.DeliverReceipt(ctx, slot, func(context.Context, string, protocol.Purpose) error { return nil }); err != nil {
		t.Fatal(err)
	}
	status, err = l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "RELEASED" || status.ReleaseReceipt == "" || status.DueAt != nil {
		t.Fatalf("ACK did not yield bounded released status: %+v %v", status, err)
	}
	var firstACK time.Time
	if err = l.cp.QueryRow(ctx, `SELECT released_at FROM c_auth.closure_requests WHERE closure_id=$1`, request.ID[:]).Scan(&firstACK); err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, firstACK.Add(24*time.Hour))
	if err = l.c.recordACK(ctx, slot, protocol.PurposeReleased); err != nil {
		t.Fatal(err)
	}
	var repeatedACK time.Time
	if err = l.cp.QueryRow(ctx, `SELECT released_at FROM c_auth.closure_requests WHERE closure_id=$1`, request.ID[:]).Scan(&repeatedACK); err != nil || !repeatedACK.Equal(firstACK) {
		t.Fatalf("repeat ACK reset retention: %v", err)
	}
	if _, err = l.c.CleanupAcknowledged(ctx, control.clock.now()); err != nil {
		t.Fatal(err)
	}
	l.c.receiptSigner = signer
	status, err = l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "RELEASED" || status.ReleaseReceipt == "" {
		t.Fatalf("cleaned outbox could not be read-only re-signed: %+v %v", status, err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1`, slot[:]) != 0 {
		t.Fatal("status page recreated acknowledged outbox")
	}
	advanceClosureClock(t, control, firstACK.Add(29*24*time.Hour))
	if n, err := l.c.CleanupClosureStatuses(ctx, 10); err != nil || n != 0 {
		t.Fatalf("status erased before thirty days: %d %v", n, err)
	}
	advanceClosureClock(t, control, firstACK.Add(30*24*time.Hour))
	if n, err := l.c.CleanupClosureStatuses(ctx, 10); err != nil || n != 1 {
		t.Fatalf("released status not erased at retention: %d %v", n, err)
	}
	if _, err = l.c.GetAccountClosureStatus(ctx, request.ID, secret); !errors.Is(err, ErrClosureNotFound) {
		t.Fatalf("expired capability remained readable: %v", err)
	}
	if _, err = l.c.RequestAccountClosure(ctx, request, passwords); !errors.Is(err, ErrExpired) {
		t.Fatalf("cleaned old ID was reusable: %v", err)
	}
	key := closureKey(request.ID)
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE key_digest=$1 AND operation='CLOSURE' AND state='EXPIRED'
		AND request_hmac IS NULL AND expires_at IS NULL`, key[:]) != 1 {
		t.Fatal("closure tombstone retained request material or disappeared")
	}
}

func TestClosureFinalizerRollbackAndFreezePostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_fault_user")
	passwords := sessionTestPasswordWorker(t, 2)
	request, secret := closureTestRequest(t, initial.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, passwords)
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	mustExec(t, l.cp, `CREATE FUNCTION c_auth.fail_release_fixture() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
		IF NEW.purpose='RELEASED' THEN RAISE EXCEPTION 'isolated release insert fault'; END IF; RETURN NEW; END $$;
		CREATE TRIGGER release_fault_fixture BEFORE INSERT ON c_auth.receipt_outbox FOR EACH ROW EXECUTE FUNCTION c_auth.fail_release_fixture()`)
	if _, err = l.c.FinalizeDueClosures(ctx, 10); err == nil {
		t.Fatal("release insertion fault unexpectedly committed")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='PENDING_CLOSE' AND password_hash IS NOT NULL`, initial.AccountID) != 1 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE account_id=$1 AND state='ACTIVE'`, initial.AccountID) != 1 {
		t.Fatal("failed release insert partially closed account or slot")
	}
	if err = control.gate.Freeze(ctx, "finalizer checkpoint failure"); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.FinalizeDueClosures(ctx, 10); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen finalizer progressed: %v", err)
	}
	if _, err = l.c.GetAccountClosureStatus(ctx, request.ID, secret); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen restricted status read succeeded: %v", err)
	}
	mustExec(t, l.cp, `DROP TRIGGER release_fault_fixture ON c_auth.receipt_outbox;DROP FUNCTION c_auth.fail_release_fixture()`)
	control.clock.set(control.clock.now().Add(time.Second))
	control.recover(t, AuthorizationRecoveryNormal, 3, 4)
	if n, err := l.c.FinalizeDueClosures(ctx, 10); err != nil || n != 1 {
		t.Fatalf("verified recovery did not finish pending close: %d %v", n, err)
	}
}

func TestConcurrentClosureAndLoginNeverLeaveActivePendingAccountPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_race_user")
	passwords := sessionTestPasswordWorker(t, 3)
	request, secret := closureTestRequest(t, initial.SessionToken)
	loginRequest := sessionTestRequest(t, "closure_race_user")
	start := make(chan struct{})
	var group sync.WaitGroup
	var closureErr, loginErr error
	var login SessionCreateResult
	group.Add(2)
	go func() {
		defer group.Done()
		<-start
		_, closureErr = l.c.RequestAccountClosure(ctx, request, passwords)
	}()
	go func() { defer group.Done(); <-start; login, loginErr = l.c.CreateSession(ctx, loginRequest, passwords) }()
	close(start)
	group.Wait()
	if loginErr != nil {
		t.Fatalf("concurrent explicit login failed: %v", loginErr)
	}
	if closureErr != nil && !errors.Is(closureErr, ErrSessionInvalid) {
		t.Fatalf("unexpected closure race outcome: %v", closureErr)
	}
	if closureErr == nil {
		status, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret)
		if err != nil || status.State != "CANCELLED" {
			t.Fatalf("login following accepted close did not cancel: %+v %v", status, err)
		}
	}
	if _, err := l.c.GetCurrentSession(ctx, login.SessionToken); err != nil {
		t.Fatalf("race failed to retain sole new session: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.closure_requests WHERE state='PENDING'`) != 0 {
		t.Fatal("race retained a pending request for an active account")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 1 {
		t.Fatal("race left multiple or missing sessions")
	}
}

func TestClosureInvalidShapesRejectedPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_shape_user")
	id, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	status := sha256.Sum256(id[:])
	if _, err := l.cp.Exec(ctx, `INSERT INTO c_auth.closure_requests(closure_id,account_id,status_digest,due_at,state)
		VALUES($1,$2,$3,clock_timestamp()+interval '7 days','PENDING')`, id[:], initial.AccountID, status[:]); err == nil {
		t.Fatal("NULL request generation passed CHECK")
	}
	if _, err := l.cp.Exec(ctx, `INSERT INTO c_auth.closure_requests(closure_id,status_digest,state,terminal_at)
		VALUES($1,$2,'CLOSED_RELEASE_PENDING',clock_timestamp())`, id[:], status[:]); err == nil {
		t.Fatal("NULL terminal slot passed CHECK")
	}
}

func TestCrossAccountClosureIDsDoNotDeadlockPostgres(t *testing.T) {
	l := newLab(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	first := sessionTestAccount(t, l, "closure_cross_first")
	second := sessionTestAccount(t, l, "closure_cross_second")
	passwords := sessionTestPasswordWorker(t, 3)
	a, _ := closureTestRequest(t, first.SessionToken)
	b, _ := closureTestRequest(t, second.SessionToken)
	if _, err := l.c.RequestAccountClosure(ctx, a, passwords); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.RequestAccountClosure(ctx, b, passwords); err != nil {
		t.Fatal(err)
	}
	a.ID, b.ID = b.ID, a.ID
	start := make(chan struct{})
	answers := make(chan error, 2)
	for _, request := range []ClosureRequest{a, b} {
		go func(request ClosureRequest) {
			<-start
			_, err := l.c.RequestAccountClosure(ctx, request, passwords)
			answers <- err
		}(request)
	}
	close(start)
	for range 2 {
		if err := <-answers; !errors.Is(err, ErrSessionInvalid) {
			t.Fatalf("cross-account historical bearer did not reject promptly: %v", err)
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.closure_requests WHERE state='PENDING'`) != 2 {
		t.Fatal("cross ID requests changed authoritative closures")
	}
}

func TestConcurrentDeadlineLoginAndFinalizerPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_due_race_user")
	passwords := sessionTestPasswordWorker(t, 3)
	request, secret := closureTestRequest(t, initial.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, passwords)
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	loginRequest := sessionTestRequest(t, "closure_due_race_user")
	start := make(chan struct{})
	var group sync.WaitGroup
	var closed int64
	var closeErr, loginErr error
	group.Add(2)
	go func() { defer group.Done(); <-start; closed, closeErr = l.c.FinalizeDueClosures(ctx, 10) }()
	go func() { defer group.Done(); <-start; _, loginErr = l.c.CreateSession(ctx, loginRequest, passwords) }()
	close(start)
	group.Wait()
	if closeErr != nil || closed != 1 {
		t.Fatalf("concurrent due finalizer failed: %d %v", closed, closeErr)
	}
	if loginErr == nil {
		t.Fatal("concurrent deadline login regained account")
	}
	if !errors.Is(loginErr, ErrAuthenticationFailed) && !errors.Is(loginErr, ErrAccountUnavailable) &&
		!errors.Is(loginErr, ErrCredentialStateChanged) {
		t.Fatalf("terminal credentials were mistaken for an infrastructure failure: %v", loginErr)
	}
	status, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "CLOSED_RELEASE_PENDING" {
		t.Fatalf("deadline race lacks unique terminal result: %+v %v", status, err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 0 {
		t.Fatal("deadline race created a live session")
	}
}

func TestClosureCancelledStatusExpiresWithoutReusingIDPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_cancel_ttl_user")
	passwords := sessionTestPasswordWorker(t, 2)
	request, secret := closureTestRequest(t, initial.SessionToken)
	if _, err := l.c.RequestAccountClosure(ctx, request, passwords); err != nil {
		t.Fatal(err)
	}
	fresh, err := l.c.CreateSession(ctx, sessionTestRequest(t, "closure_cancel_ttl_user"), passwords)
	if err != nil {
		t.Fatal(err)
	}
	var cancelledAt time.Time
	if err = l.cp.QueryRow(ctx, `SELECT terminal_at FROM c_auth.closure_requests WHERE closure_id=$1`, request.ID[:]).Scan(&cancelledAt); err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, cancelledAt.Add(29*24*time.Hour))
	if n, err := l.c.CleanupClosureStatuses(ctx, 10); err != nil || n != 0 {
		t.Fatalf("cancelled status removed early: %d %v", n, err)
	}
	advanceClosureClock(t, control, cancelledAt.Add(30*24*time.Hour))
	if n, err := l.c.CleanupClosureStatuses(ctx, 10); err != nil || n != 1 {
		t.Fatalf("cancelled status not expired at thirty days: %d %v", n, err)
	}
	if _, err = l.c.GetAccountClosureStatus(ctx, request.ID, secret); !errors.Is(err, ErrClosureNotFound) {
		t.Fatalf("expired cancelled status remains readable: %v", err)
	}
	request.Bearer = fresh.SessionToken
	if _, err = l.c.RequestAccountClosure(ctx, request, passwords); !errors.Is(err, ErrExpired) {
		t.Fatalf("cancelled ID became reusable after cleanup: %v", err)
	}
}

func TestUnacknowledgedClosureKeepsStatusButClearsRequestBindingPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "closure_unacked_ttl_user")
	passwords := sessionTestPasswordWorker(t, 1)
	request, secret := closureTestRequest(t, initial.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, passwords)
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	if n, err := l.c.FinalizeDueClosures(ctx, 1); err != nil || n != 1 {
		t.Fatalf("closure did not reach its committed terminal: %d %v", n, err)
	}
	advanceClosureClock(t, control, accepted.DueAt.Add(24*time.Hour+time.Second))
	if n, err := l.c.CleanupClosureStatuses(ctx, 1); err != nil || n != 0 {
		t.Fatalf("unacknowledged status was erased: %d %v", n, err)
	}
	status, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "CLOSED_RELEASE_PENDING" {
		t.Fatalf("pending release lost its status capability: %+v %v", status, err)
	}
	key := closureKey(request.ID)
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE key_digest=$1 AND operation='CLOSURE'
		AND state='EXPIRED' AND request_hmac IS NULL AND hmac_key_version IS NULL AND intent_id IS NULL
		AND reset_intent_id IS NULL AND result_code IS NULL AND expires_at IS NULL`, key[:]) != 1 {
		t.Fatal("unacknowledged release kept expired request binding instead of its anonymous anchor")
	}
	if _, err := l.c.RequestAccountClosure(ctx, request, passwords); !errors.Is(err, ErrExpired) {
		t.Fatalf("old request did not remain permanently rejected: %v", err)
	}
}
