package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"sync"
	"testing"
	"time"
)

const labLoginPassword = "isolated test credential independent of email"

func sessionTestPasswordWorker(t *testing.T, workers int) *PasswordPreparer {
	t.Helper()
	p, err := NewPasswordPreparer(workers, []string{"commonly blocked password"})
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func sessionTestAccount(t *testing.T, l *lab, username string) SignupResult {
	t.Helper()
	ticket, private := l.ticket(t)
	_, request := l.intent(t, ticket, private, username)
	created, err := l.c.CommitSignup(context.Background(), request)
	if err != nil {
		t.Fatal(err)
	}
	return created
}

func sessionTestRequest(t *testing.T, username string) SessionCreateRequest {
	t.Helper()
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	installation, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	request := SessionCreateRequest{Username: username, Password: labLoginPassword, IdempotencyKey: key}
	copy(request.InstallationID[:], installation[:16])
	return request
}

func TestSessionLoginReplacementAndRevocationPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "session_lifecycle_user")
	passwords := sessionTestPasswordWorker(t, 2)
	request := sessionTestRequest(t, "session_lifecycle_user")
	wrong := request
	wrong.Password = "a definitely wrong long password"
	if _, err := l.c.CreateSession(ctx, wrong, passwords); !errors.Is(err, ErrAuthenticationFailed) {
		t.Fatalf("wrong password granted login: %v", err)
	}
	missing := request
	missing.Username = "missing_session_user"
	if _, err := l.c.CreateSession(ctx, missing, passwords); !errors.Is(err, ErrAuthenticationFailed) {
		t.Fatalf("unknown username had a distinct result: %v", err)
	}
	created, err := l.c.CreateSession(ctx, request, passwords)
	if err != nil || created.AccountID != initial.AccountID || created.SessionToken == ([32]byte{}) {
		t.Fatalf("login failed: %+v %v", created, err)
	}
	if _, err = l.c.AuthorizeExistingSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionReplaced) {
		t.Fatalf("old device retained authority: %v", err)
	}
	view, err := l.c.GetDevices(ctx, created.SessionToken)
	if err != nil || view.Username != request.Username || view.LastReplaced == nil || view.AccountID != initial.AccountID {
		t.Fatalf("device view is not limited to current and last replacement: %+v %v", view, err)
	}
	if _, err = l.c.CreateSession(ctx, request, passwords); !errors.Is(err, ErrSessionCreatedReplay) {
		t.Fatalf("same-key retry issued a token: %v", err)
	}
	changed := request
	changed.InstallationID[0] ^= 1
	if _, err = l.c.CreateSession(ctx, changed, passwords); !errors.Is(err, ErrConflict) {
		t.Fatalf("same key accepted different intent: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 1 {
		t.Fatal("more than one unrevoked session")
	}
	if err = l.c.RevokeSession(ctx, initial.RevokeSecret); err != nil {
		t.Fatalf("old revoke capability failed: %v", err)
	}
	if _, err = l.c.GetCurrentSession(ctx, created.SessionToken); err != nil {
		t.Fatalf("old revoke capability reached replacement: %v", err)
	}
	revoke := digest("HNUHOLE/SESSION-REVOKE/V1", created.SessionToken[:])
	if err = l.c.RevokeSession(ctx, revoke); err != nil {
		t.Fatal(err)
	}
	if err = l.c.RevokeSession(ctx, revoke); err != nil {
		t.Fatalf("same revoke capability was not idempotent: %v", err)
	}
	if _, err = l.c.GetCurrentSession(ctx, created.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("logout bearer still authorized: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 0 {
		t.Fatal("logout left an active row")
	}
}

func TestSessionRenewalThresholdAndExpiredBearerPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "renewal_session_user")
	hash := sha256.Sum256(initial.SessionToken[:])
	var original time.Time
	if err := l.cp.QueryRow(ctx, `SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`, hash[:]).Scan(&original); err != nil {
		t.Fatal(err)
	}
	first, err := l.c.RenewCurrentSession(ctx, initial.SessionToken)
	if err != nil || !first.Equal(original) {
		t.Fatalf("renewed before seven-day window: %v %v", first, err)
	}
	mustExec(t, l.cp, `UPDATE c_auth.sessions SET expires_at=clock_timestamp()+interval '6 days' WHERE token_digest=$1`, hash[:])
	renewed, err := l.c.RenewCurrentSession(ctx, initial.SessionToken)
	if err != nil || renewed.Before(time.Now().Add(29*24*time.Hour)) {
		t.Fatalf("active bearer was not extended thirty days: %v %v", renewed, err)
	}
	again, err := l.c.GetCurrentSession(ctx, initial.SessionToken)
	if err != nil || !again.ExpiresAt.Equal(renewed) {
		t.Fatalf("retry stacked another renewal: %+v %v", again, err)
	}
	mustExec(t, l.cp, `UPDATE c_auth.sessions SET created_at=created_at-interval '30 days',
		last_activity_at=created_at-interval '30 days',expires_at=clock_timestamp()-interval '1 second'
		WHERE token_digest=$1`, hash[:])
	if _, err := l.c.RenewCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("expired bearer renewed: %v", err)
	}
}

func TestConcurrentLoginsKeepOneMobileSession(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "concurrent_login_user")
	passwords := sessionTestPasswordWorker(t, 3)
	requests := []SessionCreateRequest{sessionTestRequest(t, "concurrent_login_user"), sessionTestRequest(t, "concurrent_login_user")}
	results := make([]SessionCreateResult, len(requests))
	errorsFound := make([]error, len(requests))
	var group sync.WaitGroup
	for i := range requests {
		group.Add(1)
		go func(i int) {
			defer group.Done()
			results[i], errorsFound[i] = l.c.CreateSession(ctx, requests[i], passwords)
		}(i)
	}
	group.Wait()
	for i, err := range errorsFound {
		if err != nil {
			t.Fatalf("concurrent login %d failed: %v", i, err)
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 1 {
		t.Fatal("concurrent logins left multiple current devices")
	}
	active := 0
	for _, result := range results {
		if _, err := l.c.GetCurrentSession(ctx, result.SessionToken); err == nil {
			active++
		} else if !errors.Is(err, ErrSessionReplaced) {
			t.Fatalf("concurrent replaced bearer had wrong result: %v", err)
		}
	}
	if active != 1 {
		t.Fatalf("expected one authorized token after concurrent login, got %d", active)
	}
}

type pausingPasswordVerifier struct {
	inner  *PasswordPreparer
	ready  chan struct{}
	resume chan struct{}
	once   sync.Once
}

func (p *pausingPasswordVerifier) VerifyPassword(ctx context.Context, password string, material PasswordMaterial) (bool, error) {
	valid, err := p.inner.VerifyPassword(ctx, password, material)
	p.once.Do(func() { close(p.ready) })
	select {
	case <-p.resume:
	case <-ctx.Done():
		return false, ctx.Err()
	}
	return valid, err
}

func TestSessionProofVersionAndGateFreezeDuringPasswordWork(t *testing.T) {
	for _, mode := range []string{"credential_change", "freeze"} {
		t.Run(mode, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			initial := sessionTestAccount(t, l, "paused_session_user")
			passwords := sessionTestPasswordWorker(t, 2)
			paused := &pausingPasswordVerifier{inner: passwords, ready: make(chan struct{}), resume: make(chan struct{})}
			request := sessionTestRequest(t, "paused_session_user")
			result := make(chan error, 1)
			go func() {
				_, err := l.c.CreateSession(context.Background(), request, paused)
				result <- err
			}()
			<-paused.ready
			if mode == "freeze" {
				if err := control.gate.Freeze(context.Background(), "password worker pause"); err != nil {
					t.Fatal(err)
				}
			} else {
				newMaterial, err := passwords.PreparePassword(context.Background(), "another independent credential phrase", request.Username)
				if err != nil {
					t.Fatal(err)
				}
				mustExec(t, l.cp, `UPDATE c_auth.accounts SET password_hash=$2,password_salt=$3,
					credential_version=credential_version+1 WHERE account_id=$1`, initial.AccountID,
					newMaterial.Hash[:], newMaterial.Salt[:])
			}
			close(paused.resume)
			err := <-result
			want := ErrCredentialStateChanged
			if mode == "freeze" {
				want = ErrAuthorizationUnavailable
			}
			if !errors.Is(err, want) {
				t.Fatalf("stale password proof committed: %v", err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1`, initial.AccountID) != 1 {
				t.Fatal("stale proof replaced initial session")
			}
		})
	}
}

func TestSessionGateRecoveryInvalidatesBearerAndAllowsFreshLogin(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "recovery_login_user")
	passwords := sessionTestPasswordWorker(t, 2)
	if err := control.gate.Freeze(ctx, "session recovery test"); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.GetCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen bearer was accepted: %v", err)
	}
	if err := l.c.RevokeSession(ctx, initial.RevokeSecret); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen revoke produced an untrusted result: %v", err)
	}
	if _, err := l.c.CreateSession(ctx, sessionTestRequest(t, "recovery_login_user"), passwords); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen login was accepted: %v", err)
	}
	control.clock.set(control.clock.now().Add(time.Second))
	control.recover(t, AuthorizationRecoveryNormal, 3, 3)
	if _, err := l.c.GetCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("old generation bearer revived: %v", err)
	}
	fresh, err := l.c.CreateSession(ctx, sessionTestRequest(t, "recovery_login_user"), passwords)
	if err != nil {
		t.Fatalf("fresh login after recovery failed: %v", err)
	}
	if _, err := l.c.GetCurrentSession(ctx, fresh.SessionToken); err != nil {
		t.Fatalf("fresh bearer after recovery denied: %v", err)
	}
	if err := l.c.RevokeSession(ctx, initial.RevokeSecret); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.GetCurrentSession(ctx, fresh.SessionToken); err != nil {
		t.Fatalf("old-generation revoke reached new session: %v", err)
	}
}

func TestSessionResultCleanupPreservesPermanentTombstone(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	digestKey := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", key[:])
	mac, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, `INSERT INTO c_auth.request_results
		(operation,key_digest,state,request_hmac,hmac_key_version,result_code,expires_at)
		VALUES('SESSION_CREATE',$1,'LIVE',$2,1,'SESSION_CREATED',clock_timestamp()-interval '1 day')`, digestKey[:], mac[:])
	cleaned, err := l.c.CleanupSessionResults(ctx, 10)
	if err != nil || cleaned != 1 {
		t.Fatalf("bounded cleanup did not expire one result: %d %v", cleaned, err)
	}
	if found, err := sessionReplay(ctx, l.cp, digestKey, mac); !found || !errors.Is(err, ErrExpired) {
		t.Fatalf("expired key was reusable: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE key_digest=$1
		AND operation='SESSION_CREATE' AND state='EXPIRED' AND request_hmac IS NULL
		AND result_code IS NULL AND expires_at IS NULL`, digestKey[:]) != 1 {
		t.Fatal("cleanup retained sensitive binding or removed tombstone")
	}
}

func TestRealLoginAndRenewalWaitsCannotCrossGateFreeze(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "gate_wait_login_user")
	passwords := sessionTestPasswordWorker(t, 2)
	hold, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(ctx)
	var locked string
	if err := hold.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, initial.AccountID).Scan(&locked); err != nil {
		t.Fatal(err)
	}
	answer := make(chan error, 1)
	blockedRequest := sessionTestRequest(t, "gate_wait_login_user")
	go func() {
		_, e := l.c.CreateSession(ctx, blockedRequest, passwords)
		answer <- e
	}()
	waitLock(t, l.cp, "transactionid", 1)
	if err := control.gate.Freeze(ctx, "login waited across freeze"); err != nil {
		t.Fatal(err)
	}
	if err := hold.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-answer; !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("blocked login crossed freeze: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1`, initial.AccountID) != 1 {
		t.Fatal("frozen login replaced the prior session")
	}
	control.clock.set(control.clock.now().Add(time.Second))
	control.recover(t, AuthorizationRecoveryNormal, 3, 3)
	fresh, err := l.c.CreateSession(ctx, sessionTestRequest(t, "gate_wait_login_user"), passwords)
	if err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(fresh.SessionToken[:])
	mustExec(t, l.cp, `UPDATE c_auth.sessions SET expires_at=clock_timestamp()+interval '6 days' WHERE token_digest=$1`, hash[:])
	var before time.Time
	if err := l.cp.QueryRow(ctx, `SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`, hash[:]).Scan(&before); err != nil {
		t.Fatal(err)
	}
	hold, err = l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(ctx)
	if err := hold.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, initial.AccountID).Scan(&locked); err != nil {
		t.Fatal(err)
	}
	go func() {
		_, e := l.c.RenewCurrentSession(ctx, fresh.SessionToken)
		answer <- e
	}()
	waitLock(t, l.cp, "transactionid", 1)
	if err := control.gate.Freeze(ctx, "renewal waited across freeze"); err != nil {
		t.Fatal(err)
	}
	if err := hold.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-answer; !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("blocked renewal crossed freeze: %v", err)
	}
	var after time.Time
	if err := l.cp.QueryRow(ctx, `SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`, hash[:]).Scan(&after); err != nil || !after.Equal(before) {
		t.Fatalf("frozen renewal changed expiry: %v before=%v after=%v", err, before, after)
	}
}

func TestSessionAndDeviceRetentionUsesFinalServerExpiry(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "session_retention_user")
	hash := sha256.Sum256(initial.SessionToken[:])
	mustExec(t, l.cp, `UPDATE c_auth.sessions SET created_at=created_at-interval '40 days',
		last_activity_at=created_at-interval '40 days',expires_at=clock_timestamp()-interval '6 days'
		WHERE token_digest=$1`, hash[:])
	if removed, err := l.c.CleanupOldSessions(ctx, 10); err != nil || removed != 0 {
		t.Fatalf("session digest removed before expiry plus seven days: %d %v", removed, err)
	}
	mustExec(t, l.cp, `UPDATE c_auth.sessions SET expires_at=clock_timestamp()-interval '8 days'
		WHERE token_digest=$1`, hash[:])
	if removed, err := l.c.CleanupOldSessions(ctx, 10); err != nil || removed != 1 {
		t.Fatalf("old digest was not cleaned after retention: %d %v", removed, err)
	}
	if err := l.c.RevokeSession(ctx, initial.RevokeSecret); err != nil {
		t.Fatalf("cleaned revocation capability was not idempotent: %v", err)
	}
	if _, err := l.c.GetCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("cleaned bearer regained access: %v", err)
	}
	mustExec(t, l.cp, `INSERT INTO c_auth.recent_device_replacement
		(account_id,installation_id,signed_in_at,replaced_at)
		VALUES($1,$2,clock_timestamp()-interval '31 days',clock_timestamp()-interval '31 days')`, initial.AccountID, []byte("1234567890abcdef"))
	if removed, err := l.c.CleanupRecentDevices(ctx, 10); err != nil || removed != 1 {
		t.Fatalf("old replacement record was not deleted: %d %v", removed, err)
	}
}

func TestSessionAuthorityRejectsBannedAndPendingCloseStates(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "restricted_session_user")
	passwords := sessionTestPasswordWorker(t, 2)
	mustExec(t, l.cp, `UPDATE c_auth.account_restrictions SET ban_state='BANNED',
		version=version+1 WHERE account_id=$1`, initial.AccountID)
	if _, err := l.c.GetCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("banned account read through bearer: %v", err)
	}
	if _, err := l.c.CreateSession(ctx, sessionTestRequest(t, "restricted_session_user"), passwords); !errors.Is(err, ErrAccountUnavailable) {
		t.Fatalf("banned account obtained new session: %v", err)
	}
	mustExec(t, l.cp, `UPDATE c_auth.account_restrictions SET ban_state='NONE',
		version=version+1 WHERE account_id=$1`, initial.AccountID)
	mustExec(t, l.cp, `UPDATE c_auth.accounts SET state='PENDING_CLOSE' WHERE account_id=$1`, initial.AccountID)
	if _, err := l.c.GetCurrentSession(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("pending-close account read through bearer: %v", err)
	}
	if _, err := l.c.CreateSession(ctx, sessionTestRequest(t, "restricted_session_user"), passwords); !errors.Is(err, ErrAccountUnavailable) {
		t.Fatalf("pending-close account obtained new session without due-time authority: %v", err)
	}
}

func TestConcurrentRenewalReplacementAndOldRevocation(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial := sessionTestAccount(t, l, "mixed_session_race_user")
	passwords := sessionTestPasswordWorker(t, 2)
	hash := sha256.Sum256(initial.SessionToken[:])
	mustExec(t, l.cp, `UPDATE c_auth.sessions SET expires_at=clock_timestamp()+interval '6 days' WHERE token_digest=$1`, hash[:])
	request := sessionTestRequest(t, "mixed_session_race_user")
	start := make(chan struct{})
	var group sync.WaitGroup
	var created SessionCreateResult
	var loginErr, renewalErr, revokeErr error
	group.Add(3)
	go func() {
		defer group.Done()
		<-start
		created, loginErr = l.c.CreateSession(ctx, request, passwords)
	}()
	go func() {
		defer group.Done()
		<-start
		_, renewalErr = l.c.RenewCurrentSession(ctx, initial.SessionToken)
	}()
	go func() {
		defer group.Done()
		<-start
		revokeErr = l.c.RevokeSession(ctx, initial.RevokeSecret)
	}()
	close(start)
	group.Wait()
	if loginErr != nil || revokeErr != nil {
		t.Fatalf("concurrent login or old revocation failed: login=%v revoke=%v", loginErr, revokeErr)
	}
	if renewalErr != nil && !errors.Is(renewalErr, ErrSessionInvalid) && !errors.Is(renewalErr, ErrSessionReplaced) {
		t.Fatalf("old renewal had an unexpected race outcome: %v", renewalErr)
	}
	if _, err := l.c.GetCurrentSession(ctx, created.SessionToken); err != nil {
		t.Fatalf("old revocation or renewal affected replacement: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 1 {
		t.Fatal("mixed race left more than one current session")
	}
}
