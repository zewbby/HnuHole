package authprivacy

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestCredentialChangeResultReconcilesAllThreeCommandsWithoutSecretsPostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	initial, _ := recoveryTestAccount(t, l, "result_commands_user")
	worker := sessionTestPasswordWorker(t, 1)
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	confirmation := rotationConfirmation(t, rotation)
	check := func(id, key [32]byte, want string) {
		t.Helper()
		result, err := l.c.GetCredentialChangeResult(ctx, initial.SessionToken, id, key)
		if err != nil || result.State != want || result.SessionExpiresAt.IsZero() {
			t.Fatalf("result state=%s want=%s: %v", result.State, want, err)
		}
	}
	check(rotation.ID, confirmation.IdempotencyKey, "PENDING")
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, confirmation); err != nil {
		t.Fatal(err)
	}
	check(rotation.ID, confirmation.IdempotencyKey, "COMMITTED")
	if _, err = l.c.GetCredentialChangeResult(ctx, initial.SessionToken, rotation.ID, credentialRequestKey(t)); !errors.Is(err, ErrConflict) {
		t.Fatal("different opaque key inferred result from consumed intent")
	}
	options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	fixture, registration := credentialRegistration(t, options, 0x71)
	check(options.ChallengeID, registration.IdempotencyKey, "PENDING")
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, registration); err != nil {
		t.Fatal(err)
	}
	check(options.ChallengeID, registration.IdempotencyKey, "COMMITTED")
	removal, err := l.c.CreatePasskeyRemovalIntent(ctx, initial.SessionToken, labLoginPassword, passkeyEncode(fixture.credentialID), worker)
	if err != nil {
		t.Fatal(err)
	}
	remove := PasskeyRemoval{IntentID: removal.ID, CredentialID: passkeyEncode(fixture.credentialID), IdempotencyKey: credentialRequestKey(t)}
	check(removal.ID, remove.IdempotencyKey, "PENDING")
	if _, err = l.c.RemovePasskey(ctx, initial.SessionToken, remove); err != nil {
		t.Fatal(err)
	}
	check(removal.ID, remove.IdempotencyKey, "COMMITTED")
	check(rotation.ID, confirmation.IdempotencyKey, "COMMITTED")
	if _, err = l.c.GetCredentialChangeResult(ctx, initial.SessionToken, rotation.ID, remove.IdempotencyKey); !errors.Is(err, ErrConflict) {
		t.Fatal("cross-operation key read a different command's result")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.security_events WHERE account_id=$1 AND action IN ('ROTATE_CODE','CREATE_PASSKEY','REMOVE_PASSKEY')`, initial.AccountID) != 3 {
		t.Fatal("result queries repeated a credential mutation")
	}
}

func TestCredentialChangeResultNeverInfersFailureFromMissingRowsPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	initial, _ := recoveryTestAccount(t, l, "result_expiry_user")
	worker := sessionTestPasswordWorker(t, 1)
	key := credentialRequestKey(t)
	if result, err := l.c.GetCredentialChangeResult(ctx, initial.SessionToken, credentialRequestKey(t), key); !errors.Is(err, ErrCredentialIntentInvalid) || result.State != "" {
		t.Fatal("missing intent inferred NOT_COMMITTED")
	}
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, rotation.ExpiresAt)
	result, err := l.c.GetCredentialChangeResult(ctx, initial.SessionToken, rotation.ID, key)
	if err != nil || result.State != "NOT_COMMITTED" {
		t.Fatalf("expired known intent could not be terminalized: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.credential_change_intents WHERE intent_id=$1 AND state='EXPIRED' AND new_recovery_digest IS NULL AND terminal_at IS NOT NULL`, rotation.ID[:]) != 1 {
		t.Fatal("NOT_COMMITTED lacked irreversible durable evidence")
	}
	confirmation := CodeRotationConfirmation{IntentID: rotation.ID, IdempotencyKey: key, NewRecoveryCodeConfirmation: rotation.NewRecoveryCode}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, confirmation); !errors.Is(err, ErrCredentialIntentInvalid) {
		t.Fatal("NOT_COMMITTED intent could later commit")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE operation='ROTATE_CODE'`) != 0 {
		t.Fatal("failed late confirmation created a COMMITTED result")
	}
}

func TestCredentialChangeResultRejectsForeignAndReplacementSessionsPostgres(t *testing.T) {
	l := newLab(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	initial, _ := recoveryTestAccount(t, l, "result_owner_user")
	foreign, _ := recoveryTestAccount(t, l, "result_foreign_user")
	worker := sessionTestPasswordWorker(t, 1)
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	key := credentialRequestKey(t)
	if _, err = l.c.GetCredentialChangeResult(ctx, foreign.SessionToken, rotation.ID, key); !errors.Is(err, ErrCredentialIntentInvalid) {
		t.Fatal("foreign account read another account's intent")
	}
	login, err := l.c.CreateSession(ctx, sessionTestRequest(t, "result_owner_user"), worker)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.GetCredentialChangeResult(ctx, initial.SessionToken, rotation.ID, key); !errors.Is(err, ErrSessionReplaced) && !errors.Is(err, ErrSessionInvalid) {
		t.Fatal("replaced session read result")
	}
	if _, err = l.c.GetCredentialChangeResult(ctx, login.SessionToken, rotation.ID, key); !errors.Is(err, ErrCredentialIntentInvalid) {
		t.Fatal("successor adopted old session's pending command")
	}
}

func TestCredentialChangeResultOldVersionHasNoPendingAuthorityPostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	initial, _ := recoveryTestAccount(t, l, "result_version_user")
	worker := sessionTestPasswordWorker(t, 1)
	options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil { t.Fatal(err) }
	_, registration := credentialRegistration(t, options, 0x72)
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil { t.Fatal(err) }
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, rotationConfirmation(t, rotation)); err != nil { t.Fatal(err) }
	result, err := l.c.GetCredentialChangeResult(ctx, initial.SessionToken, options.ChallengeID, registration.IdempotencyKey)
	if err != nil || result.State != "NOT_COMMITTED" { t.Fatalf("old credential version remained pending: %v", err) }
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, registration); err == nil { t.Fatal("terminalized old ceremony committed") }
	if count(t, l.cp, `SELECT count(*) FROM c_auth.auth_challenges WHERE challenge_id=$1 AND state='ABANDONED' AND nonce IS NULL`, options.ChallengeID[:]) != 1 { t.Fatal("old native proof retained challenge authority") }
}

func TestCredentialChangeResultForeignPasskeyDoesNotLockAnotherAccountChallengePostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	initial, _ := recoveryTestAccount(t, l, "result_lock_owner")
	foreign, _ := recoveryTestAccount(t, l, "result_lock_foreign")
	options, err := l.c.CreatePasskeyOptions(ctx, foreign.SessionToken, labLoginPassword, sessionTestPasswordWorker(t, 1))
	if err != nil { t.Fatal(err) }
	_, registration := credentialRegistration(t, options, 0x74)
	if _, err = l.c.RegisterPasskey(ctx, foreign.SessionToken, registration); err != nil { t.Fatal(err) }
	hold, err := l.cp.Begin(ctx)
	if err != nil { t.Fatal(err) }
	defer hold.Rollback(ctx)
	var state string
	if err = hold.QueryRow(ctx, `SELECT state FROM c_auth.auth_challenges WHERE challenge_id=$1 FOR UPDATE`, options.ChallengeID[:]).Scan(&state); err != nil { t.Fatal(err) }
	// Holding a different account's consumed challenge must not delay owner
	// rejection or create result -> foreign-challenge lock acquisition. The
	// ordinary SQL lock timeout is 5s; this query deadline exposes that error
	// without requiring a deadlock or sleeps in the regression test.
	queryCtx, stop := context.WithTimeout(ctx, 2*time.Second)
	defer stop()
	result, err := l.c.GetCredentialChangeResult(queryCtx, initial.SessionToken, options.ChallengeID, registration.IdempotencyKey)
	if !errors.Is(err, ErrCredentialIntentInvalid) || result.State != "" {
		t.Fatalf("foreign challenge was locked or exposed: %v", err)
	}
	if err = hold.Rollback(ctx); err != nil { t.Fatal(err) }
	if _, err = l.c.GetCurrentSession(ctx, foreign.SessionToken); err != nil { t.Fatal("foreign result query changed its owner's session") }
	if count(t, l.cp, `SELECT count(*) FROM c_auth.auth_challenges WHERE challenge_id=$1 AND state='CONSUMED'`, options.ChallengeID[:]) != 1 { t.Fatal("foreign result query changed terminal challenge") }
}

func TestCredentialChangeResultFinalGateRejectsFreezeAndRecoveryWhileWaitingPostgres(t *testing.T) {
	for _, recoverGate := range []bool{false, true} {
		t.Run(map[bool]string{false: "freeze", true: "recover"}[recoverGate], func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			initial, _ := recoveryTestAccount(t, l, "result_gate_user")
			rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, sessionTestPasswordWorker(t, 1))
			if err != nil {
				t.Fatal(err)
			}
			key := credentialRequestKey(t)
			hold, err := l.cp.Begin(ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer hold.Rollback(ctx)
			var state string
			if err = hold.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, initial.AccountID).Scan(&state); err != nil {
				t.Fatal(err)
			}
			answer := make(chan error, 1)
			go func() {
				result, err := l.c.GetCredentialChangeResult(ctx, initial.SessionToken, rotation.ID, key)
				if err == nil && result.State != "" {
					answer <- errors.New("late result crossed Gate")
					return
				}
				answer <- err
			}()
			waitLock(t, l.cp, "transactionid", 1)
			if err = control.gate.Freeze(ctx, "result query waiting for account lock"); err != nil {
				t.Fatal(err)
			}
			if recoverGate {
				control.recover(t, AuthorizationRecoveryNormal, 3, 3)
			}
			if err = hold.Commit(ctx); err != nil {
				t.Fatal(err)
			}
			if err = <-answer; !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatalf("late result survived Gate change: %v", err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.credential_change_intents WHERE intent_id=$1 AND state='ACTIVE'`, rotation.ID[:]) != 1 {
				t.Fatal("rejected query terminalized authority")
			}
		})
	}
}

func TestCredentialChangeResultExpiresPermanentTombstoneAtomicallyPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	credentialWebAuthnLab(t, l)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	initial, _ := recoveryTestAccount(t, l, "result_retention_user")
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	request := rotationConfirmation(t, rotation)
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, request); err != nil {
		t.Fatal(err)
	}
	options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, sessionTestPasswordWorker(t, 1))
	if err != nil { t.Fatal(err) }
	_, registration := credentialRegistration(t, options, 0x73)
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, registration); err != nil { t.Fatal(err) }
	advanceClosureClock(t, control, control.clock.now().Add(7*24*time.Hour))
	if _, err = l.c.CleanupCredentialState(ctx, 10); err != nil { t.Fatal(err) }
	if result, err := l.c.GetCredentialChangeResult(ctx, initial.SessionToken, options.ChallengeID, registration.IdempotencyKey); err != nil || result.State != "COMMITTED" {
		t.Fatalf("retained bind result depended on already cleaned transient intent: %v", err)
	}
	advanceClosureClock(t, control, control.clock.now().Add(24*time.Hour))
	if result, err := l.c.GetCredentialChangeResult(ctx, initial.SessionToken, rotation.ID, request.IdempotencyKey); !errors.Is(err, ErrExpired) || result.State != "" {
		t.Fatal("expired result disclosed original conclusion")
	}
	key := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", request.IdempotencyKey[:])
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE key_digest=$1 AND state='EXPIRED' AND request_hmac IS NULL AND credential_change_id IS NULL AND auth_challenge_id IS NULL AND result_code IS NULL AND expires_at IS NULL`, key[:]) != 1 {
		t.Fatal("result expiry did not retain only permanent no-identity anchor")
	}
	if _, err = l.c.CleanupCredentialState(ctx, 10); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.GetCredentialChangeResult(ctx, initial.SessionToken, rotation.ID, request.IdempotencyKey); !errors.Is(err, ErrExpired) {
		t.Fatal("metadata deletion converted old result to a fresh request")
	}
	if _, err = l.c.GetCredentialChangeResult(ctx, initial.SessionToken, options.ChallengeID, registration.IdempotencyKey); !errors.Is(err, ErrExpired) {
		t.Fatal("cleaned bind result did not retain permanent result tombstone")
	}
}
