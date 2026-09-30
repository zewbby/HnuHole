package authprivacy

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
)

const labResetPassword = "fresh unrelated restoration phrase"

func recoveryTestAccount(t *testing.T, l *lab, username string) (SignupResult, string) {
	t.Helper()
	ticket, private := l.ticket(t)
	intent, request := l.intent(t, ticket, private, username)
	created, err := l.c.CommitSignup(context.Background(), request)
	if err != nil {
		t.Fatal(err)
	}
	return created, intent.RecoveryCode
}

func recoveryTestRequest(t *testing.T, intent PasswordResetIntent) PasswordResetRequest {
	t.Helper()
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	return PasswordResetRequest{IntentID: intent.ID, IdempotencyKey: key, NewPassword: labResetPassword, NewRecoveryCodeConfirmation: intent.NewRecoveryCode}
}

type fixedRecoveryProcessor struct{ calls int }

func (p *fixedRecoveryProcessor) PreparePassword(context.Context, string, string) (PasswordMaterial, error) {
	p.calls++
	return PasswordMaterial{Hash: [32]byte{2}, Salt: [16]byte{2}, ParametersVersion: 1}, nil
}

func TestRecoveryCodeResetRevokesAllOldAuthorityPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, code := recoveryTestAccount(t, l, "recover_account_user")
	intent, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
	if err != nil {
		t.Fatal(err)
	}
	if intent.Username != "recover_account_user" || intent.NewRecoveryCode == code || len(intent.NewRecoveryCode) != 26 {
		t.Fatalf("bad one-time intent: %+v", intent)
	}
	if _, err = l.c.GetCurrentSession(ctx, initial.SessionToken); err != nil {
		t.Fatalf("intent creation revoked old session: %v", err)
	}
	mustExec(t, l.cp, `INSERT INTO c_auth.passkeys(credential_id,account_id,public_key,created_at) VALUES($1,$2,$3,clock_timestamp())`, []byte{1}, initial.AccountID, []byte{2})
	request := recoveryTestRequest(t, intent)
	worker := sessionTestPasswordWorker(t, 2)
	if err = l.c.CommitPasswordReset(ctx, request, worker); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.GetCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("old bearer survived reset: %v", err)
	}
	if _, err = l.c.CreateRecoveryCodeResetIntent(ctx, code); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("old recovery code survived: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 0 {
		t.Fatal("old Passkey survived reset")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.security_events WHERE account_id=$1 AND action='PASSWORD_RESET'`, initial.AccountID) != 1 {
		t.Fatal("reset security event missing")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND credential_version=2 AND session_generation=2 AND active_reset_intent_id IS NULL`, initial.AccountID) != 1 {
		t.Fatal("control versions did not advance")
	}
	replayProcessor := &fixedRecoveryProcessor{}
	if err = l.c.CommitPasswordReset(ctx, request, replayProcessor); err != nil || replayProcessor.calls != 0 {
		t.Fatalf("replay reran KDF or failed: %d %v", replayProcessor.calls, err)
	}
	state, err := l.c.GetPasswordResetResult(ctx, request.IdempotencyKey, intent.ID)
	if err != nil || state != "COMMITTED" {
		t.Fatalf("lost response result: %q %v", state, err)
	}
	changed := request
	changed.NewPassword = "a different reset password phrase"
	if err = l.c.CommitPasswordReset(ctx, changed, replayProcessor); !errors.Is(err, ErrConflict) {
		t.Fatalf("same key accepted changed payload: %v", err)
	}
	login := sessionTestRequest(t, "recover_account_user")
	login.Password = labResetPassword
	if _, err = l.c.CreateSession(ctx, login, worker); err != nil {
		t.Fatalf("new password cannot login: %v", err)
	}
	if _, err = l.c.CreateRecoveryCodeResetIntent(ctx, intent.NewRecoveryCode); err != nil {
		t.Fatalf("new recovery code inactive: %v", err)
	}
}

func TestReplacementResetIntentAbandonsPreviousProofPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	_, code := recoveryTestAccount(t, l, "recover_replace_user")
	first, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
	if err != nil {
		t.Fatal(err)
	}
	second, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
	if err != nil {
		t.Fatal(err)
	}
	processor := &fixedRecoveryProcessor{}
	if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, first), processor); !errors.Is(err, ErrResetIntentInvalid) {
		t.Fatalf("lost first response left valid old intent: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.reset_intents WHERE state='ACTIVE'`) != 1 {
		t.Fatal("more than one active reset intent")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.reset_intents WHERE intent_id=$1 AND state='ABANDONED' AND new_recovery_digest IS NULL`, first.ID[:]) != 1 {
		t.Fatal("abandoned intent retained secret digest")
	}
	request := recoveryTestRequest(t, second)
	if state, err := l.c.GetPasswordResetResult(ctx, request.IdempotencyKey, second.ID); err != nil || state != "PENDING" {
		t.Fatalf("absence before expiry became final: %q %v", state, err)
	}
	if err = l.c.CommitPasswordReset(ctx, request, processor); err != nil {
		t.Fatal(err)
	}
}

func TestConcurrentPasswordResetOnlyOneSubmissionCommitsPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, code := recoveryTestAccount(t, l, "recover_concurrent_user")
	intent, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
	if err != nil {
		t.Fatal(err)
	}
	requests := []PasswordResetRequest{recoveryTestRequest(t, intent), recoveryTestRequest(t, intent)}
	answers := make([]error, 2)
	var group sync.WaitGroup
	for i := range requests {
		group.Add(1)
		go func(i int) {
			defer group.Done()
			answers[i] = l.c.CommitPasswordReset(ctx, requests[i], &fixedRecoveryProcessor{})
		}(i)
	}
	group.Wait()
	success := 0
	for _, err := range answers {
		if err == nil {
			success++
		} else if !errors.Is(err, ErrResetIntentInvalid) {
			t.Fatalf("unexpected concurrent reset error: %v", err)
		}
	}
	if success != 1 || count(t, l.cp, `SELECT count(*) FROM c_auth.security_events WHERE account_id=$1`, initial.AccountID) != 1 {
		t.Fatalf("reset committed %d times", success)
	}
}

type pausingRecoveryProcessor struct {
	ready, resume chan struct{}
	once          sync.Once
}

func (p *pausingRecoveryProcessor) PreparePassword(ctx context.Context, _ string, _ string) (PasswordMaterial, error) {
	p.once.Do(func() { close(p.ready) })
	select {
	case <-p.resume:
	case <-ctx.Done():
		return PasswordMaterial{}, ctx.Err()
	}
	return PasswordMaterial{Hash: [32]byte{2}, Salt: [16]byte{2}, ParametersVersion: 1}, nil
}

func TestResetPasswordWorkCannotCrossCredentialChangeOrFreezePostgres(t *testing.T) {
	for _, mode := range []string{"version", "freeze", "gate_recovery"} {
		t.Run(mode, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			ctx := context.Background()
			initial, code := recoveryTestAccount(t, l, "recover_paused_user")
			intent, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
			if err != nil {
				t.Fatal(err)
			}
			request := recoveryTestRequest(t, intent)
			processor := &pausingRecoveryProcessor{ready: make(chan struct{}), resume: make(chan struct{})}
			answer := make(chan error, 1)
			go func() { answer <- l.c.CommitPasswordReset(ctx, request, processor) }()
			<-processor.ready
			want := ErrResetIntentInvalid
			if mode == "version" {
				mustExec(t, l.cp, `UPDATE c_auth.accounts SET credential_version=credential_version+1 WHERE account_id=$1`, initial.AccountID)
			} else {
				if err = control.gate.Freeze(ctx, "paused reset proof"); err != nil {
					t.Fatal(err)
				}
				want = ErrAuthorizationUnavailable
				if mode == "gate_recovery" {
					control.clock.set(control.clock.now().Add(time.Second))
					control.recover(t, AuthorizationRecoveryNormal, 3, 3)
				}
			}
			close(processor.resume)
			if err = <-answer; !errors.Is(err, want) {
				t.Fatalf("stale reset proof committed: %v", err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE operation='PASSWORD_RESET'`) != 0 {
				t.Fatal("failed reset left committed result")
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.security_events`) != 0 {
				t.Fatal("failed reset left security event")
			}
		})
	}
}

func TestRecoveryProofAccountLockRecheckPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, code := recoveryTestAccount(t, l, "recover_proof_wait_user")
	hold, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(ctx)
	mustLock := hold.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, initial.AccountID)
	var state string
	if err = mustLock.Scan(&state); err != nil {
		t.Fatal(err)
	}
	answer := make(chan error, 1)
	go func() { _, e := l.c.CreateRecoveryCodeResetIntent(ctx, code); answer <- e }()
	waitLock(t, l.cp, "transactionid", 1)
	if _, err = hold.Exec(ctx, `UPDATE c_auth.accounts SET credential_version=credential_version+1 WHERE account_id=$1`, initial.AccountID); err != nil {
		t.Fatal(err)
	}
	if err = hold.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err = <-answer; !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("old recovery proof attached to new version: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.reset_intents`) != 0 {
		t.Fatal("stale proof created intent")
	}
}

func TestResetResultExpiryAndPermanentTombstonePostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "recover_cleanup_user")
	id, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	keyDigest := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", key[:])
	mac := requestMAC(l.c.requestKey, []byte("PASSWORD_RESET"), id[:], []byte(labResetPassword), make([]byte, 32))
	mustExec(t, l.cp, `INSERT INTO c_auth.reset_intents(intent_id,account_id,credential_version,reset_generation,authorization_generation,state,created_at,expires_at,terminal_at)
		VALUES($1,$2,1,1,1,'CONSUMED',clock_timestamp()-interval '10 days',clock_timestamp()-interval '10 days'+interval '9 minutes',clock_timestamp()-interval '9 days')`, id[:], initial.AccountID)
	mustExec(t, l.cp, `INSERT INTO c_auth.request_results(operation,key_digest,state,request_hmac,hmac_key_version,reset_intent_id,result_code,expires_at)
		VALUES('PASSWORD_RESET',$1,'LIVE',$2,1,$3,'COMMITTED',clock_timestamp()-interval '1 day')`, keyDigest[:], mac[:], id[:])
	if cleaned, err := l.c.CleanupRecoveryState(ctx, 10); err != nil || cleaned != 1 {
		t.Fatalf("cleanup failed: %d %v", cleaned, err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.reset_intents WHERE intent_id=$1`, id[:]) != 0 {
		t.Fatal("terminal metadata outlived cleanup with no references")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE key_digest=$1 AND state='EXPIRED' AND reset_intent_id IS NULL AND request_hmac IS NULL AND expires_at IS NULL`, keyDigest[:]) != 1 {
		t.Fatal("result tombstone removed or retained metadata")
	}
	if _, err = l.c.GetPasswordResetResult(ctx, key, id); !errors.Is(err, ErrExpired) {
		t.Fatalf("expired result interpreted as uncommitted: %v", err)
	}
	request := PasswordResetRequest{IntentID: id, IdempotencyKey: key, NewPassword: labResetPassword, NewRecoveryCodeConfirmation: "AAAAAAAAAAAAAAAAAAAAAAAAAA"}
	processor := &fixedRecoveryProcessor{}
	if err = l.c.CommitPasswordReset(ctx, request, processor); !errors.Is(err, ErrExpired) || processor.calls != 0 {
		t.Fatalf("expired key reran reset: %d %v", processor.calls, err)
	}
}

func TestExpiredResetIntentCannotSubmitAfterNotCommittedResultPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "recover_expired_user")
	id, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	code, codeDigest, err := generateRecoveryCode()
	if err != nil {
		t.Fatal(err)
	}
	decision, err := l.gate.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, `INSERT INTO c_auth.reset_intents(intent_id,account_id,credential_version,reset_generation,authorization_generation,state,new_recovery_digest,created_at,expires_at)
		VALUES($1,$2,1,1,$3,'ACTIVE',$4,clock_timestamp()-interval '11 minutes',clock_timestamp()-interval '2 minutes')`, id[:], initial.AccountID, int64(decision.Generation), codeDigest[:])
	mustExec(t, l.cp, `UPDATE c_auth.accounts SET reset_generation=1,active_reset_intent_id=$2 WHERE account_id=$1`, initial.AccountID, id[:])
	request := recoveryTestRequest(t, PasswordResetIntent{ID: id, NewRecoveryCode: code})
	if state, err := l.c.GetPasswordResetResult(ctx, request.IdempotencyKey, id); err != nil || state != "NOT_COMMITTED" {
		t.Fatalf("expiry wasn't determined under lock: %q %v", state, err)
	}
	if err = l.c.CommitPasswordReset(ctx, request, &fixedRecoveryProcessor{}); !errors.Is(err, ErrResetIntentExpired) {
		t.Fatalf("late POST committed after NOT_COMMITTED: %v", err)
	}
	if cleaned, err := l.c.CleanupRecoveryState(ctx, 10); err != nil || cleaned != 1 {
		t.Fatalf("expired secret not cleared: %d %v", cleaned, err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.reset_intents WHERE intent_id=$1 AND state='EXPIRED' AND new_recovery_digest IS NULL`, id[:]) != 1 {
		t.Fatal("cleanup did not keep minimal terminal metadata")
	}
}

func TestRecoveryKeepsBanAndPendingClosurePostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, code := recoveryTestAccount(t, l, "recover_banned_user")
	mustExec(t, l.cp, `UPDATE c_auth.account_restrictions SET ban_state='BANNED',ban_ends_at=NULL,version=version+1 WHERE account_id=$1`, initial.AccountID)
	intent, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
	if err != nil {
		t.Fatalf("ban blocked independent recovery: %v", err)
	}
	request := recoveryTestRequest(t, intent)
	if err = l.c.CommitPasswordReset(ctx, request, &fixedRecoveryProcessor{}); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.account_restrictions WHERE account_id=$1 AND ban_state='BANNED' AND ban_ends_at IS NULL`, initial.AccountID) != 1 {
		t.Fatal("recovery lifted punishment")
	}
	closureID, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	statusDigest, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	// The shared closure schema remains authoritative: recovery neither changes
	// its identity/deadline nor returns a session during the buffer window.
	mustExec(t, l.cp, `UPDATE c_auth.accounts SET state='PENDING_CLOSE',closure_generation=1 WHERE account_id=$1`, initial.AccountID)
	mustExec(t, l.cp, `INSERT INTO c_auth.closure_requests(closure_id,status_digest,account_id,request_generation,state,due_at)
		VALUES($1,$2,$3,1,'PENDING',clock_timestamp()+interval '7 days')`, closureID[:], statusDigest[:], initial.AccountID)
	pending, err := l.c.CreateRecoveryCodeResetIntent(ctx, intent.NewRecoveryCode)
	if err != nil {
		t.Fatalf("pending closure blocked timely reset: %v", err)
	}
	if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, pending), &fixedRecoveryProcessor{}); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='PENDING_CLOSE'`, initial.AccountID) != 1 || count(t, l.cp, `SELECT count(*) FROM c_auth.closure_requests WHERE closure_id=$1 AND state='PENDING'`, closureID[:]) != 1 {
		t.Fatal("reset cancelled pending closure")
	}
}

func TestPasswordResetMakesPausedOldPasswordLoginFailPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, code := recoveryTestAccount(t, l, "recover_login_race_user")
	intent, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
	if err != nil {
		t.Fatal(err)
	}
	worker := sessionTestPasswordWorker(t, 2)
	paused := &pausingPasswordVerifier{inner: worker, ready: make(chan struct{}), resume: make(chan struct{})}
	login := sessionTestRequest(t, "recover_login_race_user")
	answer := make(chan error, 1)
	go func() { _, e := l.c.CreateSession(ctx, login, paused); answer <- e }()
	<-paused.ready
	if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, intent), worker); err != nil {
		close(paused.resume)
		t.Fatal(err)
	}
	close(paused.resume)
	if err = <-answer; !errors.Is(err, ErrCredentialStateChanged) {
		t.Fatalf("old-password proof created a new session after reset: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 0 {
		t.Fatal("reset race left a valid old-password session")
	}
}

func TestResetRecoveryDigestCollisionRollsBackEverythingPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, oldCode := recoveryTestAccount(t, l, "recover_collision_user")
	_, otherCode := recoveryTestAccount(t, l, "recover_other_code_user")
	collision, err := recoveryDigest(otherCode)
	if err != nil {
		t.Fatal(err)
	}
	id, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	decision, err := l.gate.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, `INSERT INTO c_auth.reset_intents(intent_id,account_id,credential_version,reset_generation,authorization_generation,state,new_recovery_digest,created_at,expires_at)
		VALUES($1,$2,1,1,$3,'ACTIVE',$4,clock_timestamp(),clock_timestamp()+interval '9 minutes')`, id[:], initial.AccountID, int64(decision.Generation), collision[:])
	mustExec(t, l.cp, `UPDATE c_auth.accounts SET reset_generation=1,active_reset_intent_id=$2 WHERE account_id=$1`, initial.AccountID, id[:])
	mustExec(t, l.cp, `INSERT INTO c_auth.passkeys(credential_id,account_id,public_key,created_at) VALUES($1,$2,$3,clock_timestamp())`, []byte{3}, initial.AccountID, []byte{4})
	request := recoveryTestRequest(t, PasswordResetIntent{ID: id, NewRecoveryCode: otherCode})
	if err = l.c.CommitPasswordReset(ctx, request, &fixedRecoveryProcessor{}); !errors.Is(err, ErrConflict) {
		t.Fatalf("collision did not fail safely: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND credential_version=1 AND session_generation=1`, initial.AccountID) != 1 {
		t.Fatal("collision changed password/control versions")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 1 {
		t.Fatal("collision consumed old Passkey")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.reset_intents WHERE intent_id=$1 AND state='ACTIVE' AND new_recovery_digest IS NOT NULL`, id[:]) != 1 {
		t.Fatal("collision consumed intent")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE operation='PASSWORD_RESET'`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_auth.security_events`) != 0 {
		t.Fatal("collision committed result or audit event")
	}
	if _, err = l.c.GetCurrentSession(ctx, initial.SessionToken); err != nil {
		t.Fatalf("collision revoked old session: %v", err)
	}
	if _, err = l.c.CreateRecoveryCodeResetIntent(ctx, oldCode); err != nil {
		t.Fatalf("collision consumed old recovery code: %v", err)
	}
}

func TestPendingClosureDeadlineRejectsBothRecoveryStagesPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, code := recoveryTestAccount(t, l, "recover_due_close_user")
	intent, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
	if err != nil {
		t.Fatal(err)
	}
	if err = l.c.RevokeSession(ctx, initial.RevokeSecret); err != nil {
		t.Fatal(err)
	}
	closureID, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	status, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, `UPDATE c_auth.accounts SET state='PENDING_CLOSE',closure_generation=1 WHERE account_id=$1`, initial.AccountID)
	mustExec(t, l.cp, `INSERT INTO c_auth.closure_requests(closure_id,status_digest,account_id,request_generation,state,due_at)
		VALUES($1,$2,$3,1,'PENDING',clock_timestamp()-interval '1 second')`, closureID[:], status[:], initial.AccountID)
	if _, err = l.c.CreateRecoveryCodeResetIntent(ctx, code); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("expired closure exposed recovery proof or created intent: %v", err)
	}
	if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, intent), &fixedRecoveryProcessor{}); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("late reset crossed closure deadline: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='PENDING_CLOSE' AND credential_version=1`, initial.AccountID) != 1 {
		t.Fatal("expired closure reset changed credentials/state")
	}
}

func TestResetWaitsCannotCrossGateFreezePostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial, code := recoveryTestAccount(t, l, "recover_frozen_wait_user")
	intent, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
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
	request := recoveryTestRequest(t, intent)
	answer := make(chan error, 1)
	go func() { answer <- l.c.CommitPasswordReset(ctx, request, &fixedRecoveryProcessor{}) }()
	waitLock(t, l.cp, "transactionid", 1)
	if err = control.gate.Freeze(ctx, "recovery waited across freeze"); err != nil {
		t.Fatal(err)
	}
	if err = hold.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err = <-answer; !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("reset crossed freeze during account wait: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE operation='PASSWORD_RESET'`) != 0 {
		t.Fatal("frozen reset left result")
	}
}

func TestRestrictedRecoveryEventsExpireAfterSevenDaysPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "recovery_event_ttl_user")
	oldID, recentID := uuid.New(), uuid.New()
	mustExec(t, l.cp, `INSERT INTO c_auth.security_events(event_id,account_id,action,credential_version,session_generation,recorded_at)
		VALUES($1,$3,'PASSWORD_RESET',1,1,$4),($2,$3,'PASSWORD_RESET',1,1,$5)`, oldID, recentID, initial.AccountID,
		control.clock.now().Add(-7*24*time.Hour-time.Second), control.clock.now().Add(-6*24*time.Hour))
	if _, err := l.c.CleanupRecoveryState(ctx, 1); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.security_events WHERE event_id=$1`, oldID) != 0 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.security_events WHERE event_id=$1`, recentID) != 1 {
		t.Fatal("restricted event cleanup erased recent evidence or kept expired account metadata")
	}
	advanceClosureClock(t, control, control.clock.now().Add(24*time.Hour))
	if err := control.gate.Freeze(ctx, "event retention remains subject to trusted time"); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.CleanupRecoveryState(ctx, 1); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen cleanup changed event evidence: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.security_events WHERE event_id=$1`, recentID) != 1 {
		t.Fatal("frozen cleanup removed restricted event evidence")
	}
}
