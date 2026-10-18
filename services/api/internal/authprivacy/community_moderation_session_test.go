package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func moderationAccessRead(ctx context.Context, c *Community, token [32]byte, allowed bool) (PostResponse, error) {
	return c.withModerationSession(ctx, token, allowed, func(_ pgx.Tx, account uuid.UUID, _ AuthorizationDecision) (any, error) { return account, nil })
}

func TestModerationAccessBannedAccountScopePostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "moderation_scope_user")
	passwords := sessionTestPasswordWorker(t, 1)
	if err := l.c.ApplyAccountBan(ctx, initial.AccountID, 1, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.CreateSession(ctx, sessionTestRequest(t, "moderation_scope_user"), passwords); !errors.Is(err, ErrAccountUnavailable) {
		t.Fatalf("ordinary login crossed ban: %v", err)
	}
	if _, err := moderationAccessRead(ctx, l.c, initial.SessionToken, true); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("revoked mobile bearer became an appeal capability: %v", err)
	}
	limited, err := l.c.CreateModerationAccessSession(ctx, ModerationAccessRequest{"moderation_scope_user", labLoginPassword}, passwords)
	if err != nil {
		t.Fatal(err)
	}
	view, err := moderationAccessRead(ctx, l.c, limited.SessionToken, true)
	if err != nil || view.Value != initial.AccountID || !view.ExpiresAt.Equal(limited.ExpiresAt) {
		t.Fatalf("self-service unavailable: %+v %v", view, err)
	}
	if remaining := limited.ExpiresAt.Sub(view.ServerTime); remaining > moderationAccessLifetime || remaining < moderationAccessLifetime-time.Minute {
		t.Fatal("restricted session expiry or renewal drifted")
	}
	for _, allowed := range []bool{false} {
		if _, err = moderationAccessRead(ctx, l.c, limited.SessionToken, allowed); !errors.Is(err, ErrSessionInvalid) {
			t.Fatalf("limited token entered report/management scope: %v", err)
		}
	}
	if _, err = l.c.GetCurrentSession(ctx, limited.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("limited token became ordinary session: %v", err)
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID); n != 0 {
		t.Fatal("limited login created a mobile session")
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND session_generation=2`, initial.AccountID); n != 1 {
		t.Fatal("limited login advanced ordinary generation")
	}
	replaced, err := l.c.CreateModerationAccessSession(ctx, ModerationAccessRequest{"moderation_scope_user", labLoginPassword}, passwords)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = moderationAccessRead(ctx, l.c, limited.SessionToken, true); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("replaced restricted token survived: %v", err)
	}
	if err = l.c.RevokeModerationAccessSession(ctx, replaced.SessionToken); err != nil {
		t.Fatal(err)
	}
	if _, err = moderationAccessRead(ctx, l.c, replaced.SessionToken, true); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("restricted logout failed: %v", err)
	}
}

func TestModerationAccessExpiryCredentialAndSessionFencesPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "moderation_fence_user")
	passwords := sessionTestPasswordWorker(t, 1)
	request := ModerationAccessRequest{"moderation_fence_user", labLoginPassword}
	for _, invalid := range []ModerationAccessRequest{{"missing_moderation_user", labLoginPassword}, {request.Username, "wrong password"}} {
		if _, err := l.c.CreateModerationAccessSession(ctx, invalid, passwords); !errors.Is(err, ErrAuthenticationFailed) {
			t.Fatalf("unknown and wrong credentials differ: %v", err)
		}
	}
	for _, fence := range []string{"expiry", "credential", "session"} {
		limited, err := l.c.CreateModerationAccessSession(ctx, request, passwords)
		if err != nil {
			t.Fatal(err)
		}
		switch fence {
		case "expiry":
			hash := sha256.Sum256(limited.SessionToken[:])
			mustExec(t, l.cp, `UPDATE c_moderation.access_sessions SET expires_at=clock_timestamp()-interval '1 second' WHERE token_digest=$1`, hash[:])
		case "credential":
			mustExec(t, l.cp, `UPDATE c_auth.accounts SET credential_version=credential_version+1 WHERE account_id=$1`, initial.AccountID)
		case "session":
			if _, err = l.c.CreateSession(ctx, sessionTestRequest(t, request.Username), passwords); err != nil {
				t.Fatal(err)
			}
		}
		if _, err = moderationAccessRead(ctx, l.c, limited.SessionToken, true); !errors.Is(err, ErrSessionInvalid) {
			t.Fatalf("%s fence failed: %v", fence, err)
		}
	}
}

func TestModerationAccessDoesNotCancelClosurePostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "moderation_closure_user")
	passwords := sessionTestPasswordWorker(t, 1)
	request, _ := closureTestRequest(t, initial.SessionToken)
	if _, err := l.c.RequestAccountClosure(ctx, request, passwords); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.CreateModerationAccessSession(ctx, ModerationAccessRequest{"moderation_closure_user", labLoginPassword}, passwords); !errors.Is(err, ErrAccountUnavailable) {
		t.Fatalf("restricted login cancelled closure: %v", err)
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='PENDING_CLOSE'`, initial.AccountID); n != 1 {
		t.Fatal("restricted login changed closure state")
	}
}

func TestModerationAccountRestrictionAtomicRollbackPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	actor := sessionTestAccount(t, l, "moderation_actor_user")
	target := sessionTestAccount(t, l, "moderation_target_user")
	var locked moderationRestrictionState
	prepare := func(tx pgx.Tx, _ uuid.UUID) error {
		var err error
		locked, err = l.c.lockModerationRestrictionTx(ctx, tx, target.AccountID, "BAN")
		return err
	}
	rejected := errors.New("case decision failed after restriction")
	_, err := l.c.withModerationAccountsSession(ctx, actor.SessionToken, target.AccountID, prepare, func(tx pgx.Tx, _ uuid.UUID, final AuthorizationDecision) (any, error) {
		if err := l.c.applyModerationRestrictionTx(ctx, tx, locked, "BAN", nil, final.TrustedAt); err != nil {
			return nil, err
		}
		return nil, rejected
	})
	if !errors.Is(err, rejected) {
		t.Fatal(err)
	}
	if _, err = l.c.GetCurrentSession(ctx, target.SessionToken); err != nil {
		t.Fatalf("rolled-back decision revoked target session: %v", err)
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_auth.account_restrictions WHERE account_id=$1 AND ban_state='NONE' AND version=1`, target.AccountID); n != 1 {
		t.Fatal("partial restriction survived rollback")
	}
	_, err = l.c.withModerationAccountsSession(ctx, actor.SessionToken, target.AccountID, prepare, func(tx pgx.Tx, _ uuid.UUID, final AuthorizationDecision) (any, error) {
		return nil, l.c.applyModerationRestrictionTx(ctx, tx, locked, "BAN", nil, final.TrustedAt)
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.GetCurrentSession(ctx, target.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("committed restriction failed to revoke: %v", err)
	}
}

func TestModerationAccessFinalGateGenerationPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	sessionTestAccount(t, l, "moderation_gate_user")
	passwords := sessionTestPasswordWorker(t, 1)
	limited, err := l.c.CreateModerationAccessSession(ctx, ModerationAccessRequest{"moderation_gate_user", labLoginPassword}, passwords)
	if err != nil {
		t.Fatal(err)
	}
	if err = l.gate.Freeze(ctx, "restricted access test"); err != nil {
		t.Fatal(err)
	}
	if _, err = moderationAccessRead(ctx, l.c, limited.SessionToken, true); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("restricted token crossed freeze: %v", err)
	}
	control.clock.set(control.clock.now().Add(time.Second))
	control.recover(t, AuthorizationRecoveryNormal, 3, 3)
	if _, err = moderationAccessRead(ctx, l.c, limited.SessionToken, true); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("restricted old generation survived recovery: %v", err)
	}
}

func TestModerationAccessPasswordProofCannotCrossCredentialChangePostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "moderation_proof_user")
	passwords := sessionTestPasswordWorker(t, 1)
	paused := &pausingPasswordVerifier{inner: passwords, ready: make(chan struct{}), resume: make(chan struct{})}
	answer := make(chan error, 1)
	go func() {
		_, err := l.c.CreateModerationAccessSession(ctx, ModerationAccessRequest{"moderation_proof_user", labLoginPassword}, paused)
		answer <- err
	}()
	<-paused.ready
	material, err := passwords.PreparePassword(ctx, "changed independent moderation credential", "moderation_proof_user")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, `UPDATE c_auth.accounts SET password_hash=$2,password_salt=$3,credential_version=credential_version+1 WHERE account_id=$1`, initial.AccountID, material.Hash[:], material.Salt[:])
	close(paused.resume)
	if err = <-answer; !errors.Is(err, ErrCredentialStateChanged) {
		t.Fatalf("stale credential proof issued restricted capability: %v", err)
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_moderation.access_sessions`); n != 0 {
		t.Fatal("stale proof left restricted token")
	}
}

func TestModerationAccountLockOrderConcurrentPostgres(t *testing.T) {
	l := newLab(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	a := sessionTestAccount(t, l, "moderation_lock_a")
	b := sessionTestAccount(t, l, "moderation_lock_b")
	start := make(chan struct{})
	answer := make(chan error, 2)
	for _, pair := range []struct {
		token  [32]byte
		target uuid.UUID
	}{{a.SessionToken, b.AccountID}, {b.SessionToken, a.AccountID}} {
		pair := pair
		go func() {
			<-start
			_, err := l.c.withModerationAccountsSession(ctx, pair.token, pair.target, nil, func(_ pgx.Tx, _ uuid.UUID, _ AuthorizationDecision) (any, error) { return nil, nil })
			answer <- err
		}()
	}
	close(start)
	for i := 0; i < 2; i++ {
		if err := <-answer; err != nil {
			t.Fatalf("opposite moderation targets deadlocked: %v", err)
		}
	}
}
