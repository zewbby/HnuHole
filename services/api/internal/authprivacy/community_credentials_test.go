package authprivacy

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

func credentialWebAuthnLab(t *testing.T, l *lab) {
	t.Helper()
	configured, err := l.c.WithWebAuthn(WebAuthnConfig{RPID: "example.test", Origins: []string{"https://auth.example.test"}})
	if err != nil {
		t.Fatal(err)
	}
	l.c = configured
}

func credentialRequestKey(t *testing.T) [32]byte {
	t.Helper()
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	return key
}

func rotationConfirmation(t *testing.T, intent CodeRotationIntent) CodeRotationConfirmation {
	t.Helper()
	return CodeRotationConfirmation{IntentID: intent.ID, IdempotencyKey: credentialRequestKey(t), NewRecoveryCodeConfirmation: intent.NewRecoveryCode}
}

func credentialChallenge(t *testing.T, options PasskeyOptions) [32]byte {
	t.Helper()
	encoded, ok := options.PublicKey["challenge"].(string)
	if !ok {
		t.Fatal("WebAuthn options missing challenge")
	}
	decoded := passkeyDecode(t, encoded)
	if len(decoded) != 32 {
		t.Fatal("WebAuthn challenge is not 32 bytes")
	}
	var challenge [32]byte
	copy(challenge[:], decoded)
	return challenge
}

func credentialRegistration(t *testing.T, options PasskeyOptions, discriminator byte) (passkeyTestFixture, PasskeyRegistration) {
	t.Helper()
	fixture := newPasskeyTestFixture(t)
	fixture.credentialID = bytes.Repeat([]byte{discriminator}, 32)
	user, ok := options.PublicKey["user"].(map[string]any)
	if !ok {
		fields, ok := options.PublicKey["user"].(map[string]string)
		if !ok {
			t.Fatal("registration options missing user")
		}
		user = make(map[string]any, len(fields))
		for key, value := range fields {
			user[key] = value
		}
	}
	encoded, ok := user["id"].(string)
	if !ok {
		t.Fatal("registration options missing random user handle")
	}
	decoded := passkeyDecode(t, encoded)
	if len(decoded) != 32 {
		t.Fatal("random user handle is not 32 bytes")
	}
	copy(fixture.userHandle[:], decoded)
	if user["name"] != encoded || user["displayName"] != "Hnuhole account" {
		t.Fatalf("private account identity leaked to platform options: %+v", user)
	}
	request := PasskeyRegistration{ChallengeID: options.ChallengeID, IdempotencyKey: credentialRequestKey(t),
		Response: fixture.makeRegistration(t, credentialChallenge(t, options), 0, 0x5d)}
	return fixture, request
}

func credentialAddPasskey(t *testing.T, l *lab, bearer [32]byte, discriminator byte) passkeyTestFixture {
	t.Helper()
	options, err := l.c.CreatePasskeyOptions(context.Background(), bearer, labLoginPassword, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	fixture, request := credentialRegistration(t, options, discriminator)
	if _, err = l.c.RegisterPasskey(context.Background(), bearer, request); err != nil {
		t.Fatal(err)
	}
	return fixture
}

func credentialPasskeyProof(t *testing.T, l *lab, fixture passkeyTestFixture, signCount uint32) PasskeyResetProof {
	t.Helper()
	options, err := l.c.CreatePasskeyResetOptions(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if _, exists := options.PublicKey["allowCredentials"]; exists || options.PublicKey["userVerification"] != "required" {
		t.Fatal("recovery options are not anonymous discoverable UV-required options")
	}
	return PasskeyResetProof{ChallengeID: options.ChallengeID,
		Response: fixture.makeAssertion(t, credentialChallenge(t, options), signCount, 0x1d)}
}

func TestRecoveryCodeRotationPreservesPasswordPasskeysAndSessionPostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, oldCode := recoveryTestAccount(t, l, "cred_rotation_user")
	fixture := credentialAddPasskey(t, l, initial.SessionToken, 0x41)
	worker := sessionTestPasswordWorker(t, 2)
	if _, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, "an incorrect independent password", worker); !errors.Is(err, ErrAuthenticationFailed) {
		t.Fatalf("wrong fresh password granted rotation: %v", err)
	}
	reset, err := l.c.CreateRecoveryCodeResetIntent(ctx, oldCode)
	if err != nil {
		t.Fatal(err)
	}
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	oldDigest, _ := recoveryDigest(oldCode)
	if len(rotation.NewRecoveryCode) != 26 || rotation.NewRecoveryCode == oldCode || count(t, l.cp, `SELECT count(*) FROM c_auth.recovery_codes WHERE account_id=$1 AND code_digest=$2`, initial.AccountID, oldDigest[:]) != 1 {
		t.Fatal("rotation creation replaced old code or did not create a new one-time secret")
	}
	request := rotationConfirmation(t, rotation)
	bad := request
	bad.NewRecoveryCodeConfirmation = oldCode
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, bad); err == nil {
		t.Fatal("unconfirmed new recovery code was activated")
	}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, request); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, request); err != nil {
		t.Fatalf("same-key confirmation did not resolve a lost response: %v", err)
	}
	changed := request
	changed.NewRecoveryCodeConfirmation = oldCode
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, changed); !errors.Is(err, ErrConflict) {
		t.Fatalf("same key accepted changed recovery-code confirmation: %v", err)
	}
	if _, err = l.c.CreateRecoveryCodeResetIntent(ctx, oldCode); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("old code survived confirmed rotation: %v", err)
	}
	if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, reset), &fixedRecoveryProcessor{}); !errors.Is(err, ErrResetIntentInvalid) {
		t.Fatalf("rotation left old reset authority valid: %v", err)
	}
	if _, err = l.c.GetCurrentSession(ctx, initial.SessionToken); err != nil {
		t.Fatalf("normal credential management revoked current session: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND credential_version=3 AND session_generation=1`, initial.AccountID) != 1 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.security_events WHERE account_id=$1 AND action='ROTATE_CODE'`, initial.AccountID) != 1 {
		t.Fatal("rotation did not advance credential version exactly once while preserving session generation")
	}
	if _, err = l.c.CreatePasskeyResetIntent(ctx, credentialPasskeyProof(t, l, fixture, 0)); err != nil {
		t.Fatalf("retained Passkey became invalid after ordinary credential version advance: %v", err)
	}
	if _, err = l.c.CreateRecoveryCodeResetIntent(ctx, rotation.NewRecoveryCode); err != nil {
		t.Fatalf("new recovery code not active: %v", err)
	}
	if _, err = l.c.CreateSession(ctx, sessionTestRequest(t, "cred_rotation_user"), worker); err != nil {
		t.Fatalf("rotation changed normal password: %v", err)
	}
}

func TestRotationReplacementAndConcurrentConfirmationOnlyOneCommitPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_rotation_race_user")
	worker := sessionTestPasswordWorker(t, 1)
	first, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	second, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, rotationConfirmation(t, first)); !errors.Is(err, ErrCredentialIntentInvalid) {
		t.Fatalf("replaced rotation remained active: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.credential_change_intents WHERE intent_id=$1 AND state='ABANDONED' AND new_recovery_digest IS NULL`, first.ID[:]) != 1 {
		t.Fatal("replaced rotation kept authority or secret digest")
	}
	requests := []CodeRotationConfirmation{rotationConfirmation(t, second), rotationConfirmation(t, second)}
	answers := make([]error, 2)
	var group sync.WaitGroup
	for i := range requests {
		group.Add(1)
		go func(i int) {
			defer group.Done()
			_, answers[i] = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, requests[i])
		}(i)
	}
	group.Wait()
	success := 0
	for _, answer := range answers {
		if answer == nil {
			success++
		} else if !errors.Is(answer, ErrCredentialIntentInvalid) {
			t.Fatalf("unexpected concurrent confirmation error: %v", answer)
		}
	}
	if success != 1 || count(t, l.cp, `SELECT count(*) FROM c_auth.security_events WHERE action='ROTATE_CODE'`) != 1 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.recovery_codes WHERE account_id=$1`, initial.AccountID) != 1 {
		t.Fatalf("concurrent rotation committed %d times", success)
	}
}

func TestFreshCredentialManagementProofCannotCrossResetSessionOrGateChangesPostgres(t *testing.T) {
	for _, mode := range []string{"reset", "session_replacement", "freeze", "gate_recovery"} {
		t.Run(mode, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			ctx := context.Background()
			initial, code := recoveryTestAccount(t, l, "cred_paused_user")
			worker := sessionTestPasswordWorker(t, 2)
			paused := &pausingPasswordVerifier{inner: worker, ready: make(chan struct{}), resume: make(chan struct{})}
			answer := make(chan error, 1)
			go func() {
				_, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, paused)
				answer <- err
			}()
			<-paused.ready
			want := ErrCredentialStateChanged
			switch mode {
			case "reset":
				intent, err := l.c.CreateRecoveryCodeResetIntent(ctx, code)
				if err != nil {
					close(paused.resume)
					t.Fatal(err)
				}
				if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, intent), &fixedRecoveryProcessor{}); err != nil {
					close(paused.resume)
					t.Fatal(err)
				}
			case "session_replacement":
				if _, err := l.c.CreateSession(ctx, sessionTestRequest(t, "cred_paused_user"), worker); err != nil {
					close(paused.resume)
					t.Fatal(err)
				}
				want = ErrSessionInvalid
			default:
				if err := control.gate.Freeze(ctx, "credential password proof paused"); err != nil {
					close(paused.resume)
					t.Fatal(err)
				}
				want = ErrAuthorizationUnavailable
				if mode == "gate_recovery" {
					control.clock.set(control.clock.now().Add(time.Second))
					control.recover(t, AuthorizationRecoveryNormal, 3, 3)
				}
			}
			close(paused.resume)
			if err := <-answer; !errors.Is(err, want) && !(mode == "session_replacement" && errors.Is(err, ErrSessionReplaced)) {
				t.Fatalf("stale management password proof crossed %s: %v", mode, err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.credential_change_intents WHERE kind='ROTATE_CODE'`) != 0 {
				t.Fatal("stale fresh-password proof created rotation authority")
			}
		})
	}
}

func TestPasskeyEnrollmentRemovalAndResetLifecyclePostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, oldCode := recoveryTestAccount(t, l, "cred_passkey_user")
	worker := sessionTestPasswordWorker(t, 1)
	options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	selection, ok := options.PublicKey["authenticatorSelection"].(map[string]any)
	if !ok || selection["residentKey"] != "required" || selection["userVerification"] != "required" || options.PublicKey["attestation"] != "none" {
		t.Fatal("enrollment options weakened the approved resident/UV/none policy")
	}
	first, registration := credentialRegistration(t, options, 0x51)
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, registration); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, registration); err != nil {
		t.Fatalf("same-key register failed to resolve lost response: %v", err)
	}
	changed := registration
	changed.Response.ClientDataJSON += "A"
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, changed); !errors.Is(err, ErrConflict) {
		t.Fatalf("same enrollment key accepted changed ceremony: %v", err)
	}
	second := credentialAddPasskey(t, l, initial.SessionToken, 0x52)
	view, err := l.c.GetRecoveryCredentials(ctx, initial.SessionToken)
	if err != nil || !view.RecoveryCodeAvailable || len(view.Passkeys) != 2 || view.SessionExpiresAt.IsZero() {
		t.Fatalf("recovery credentials view: %+v %v", view, err)
	}
	for _, item := range view.Passkeys {
		if !item.BackupEligible || !item.BackedUp {
			t.Fatal("registered backup flags not represented in limited view")
		}
	}
	removal, err := l.c.CreatePasskeyRemovalIntent(ctx, initial.SessionToken, labLoginPassword, passkeyEncode(second.credentialID), worker)
	if err != nil {
		t.Fatal(err)
	}
	request := PasskeyRemoval{IntentID: removal.ID, IdempotencyKey: credentialRequestKey(t), CredentialID: passkeyEncode(second.credentialID)}
	if _, err = l.c.RemovePasskey(ctx, initial.SessionToken, request); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.RemovePasskey(ctx, initial.SessionToken, request); err != nil {
		t.Fatalf("same-key remove of already deleted target was not idempotent: %v", err)
	}
	changedRemoval := request
	changedRemoval.CredentialID = passkeyEncode(first.credentialID)
	if _, err = l.c.RemovePasskey(ctx, initial.SessionToken, changedRemoval); !errors.Is(err, ErrConflict) {
		t.Fatalf("same removal key changed its fixed target: %v", err)
	}
	if _, err = l.c.CreatePasskeyRemovalIntent(ctx, initial.SessionToken, labLoginPassword, passkeyEncode(second.credentialID), worker); !errors.Is(err, ErrCredentialNotFound) {
		t.Fatalf("deleted target did not get uniform not-found: %v", err)
	}
	if _, err = l.c.CreatePasskeyResetIntent(ctx, credentialPasskeyProof(t, l, second, 0)); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("removed Passkey proved recovery: %v", err)
	}
	proof := credentialPasskeyProof(t, l, first, 0)
	reset, err := l.c.CreatePasskeyResetIntent(ctx, proof)
	if err != nil || reset.Username != "cred_passkey_user" || len(reset.NewRecoveryCode) != 26 {
		t.Fatalf("valid discoverable proof rejected: %+v %v", reset, err)
	}
	if _, err = l.c.CreatePasskeyResetIntent(ctx, proof); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("successful assertion replayed into second reset intent: %v", err)
	}
	if _, err = l.c.GetCurrentSession(ctx, initial.SessionToken); err != nil {
		t.Fatalf("proof intent itself revoked session: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1`, initial.AccountID) != 1 {
		t.Fatal("Passkey proof created a normal community session")
	}
	if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, reset), &fixedRecoveryProcessor{}); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 0 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 0 {
		t.Fatal("Passkey reset left old Passkeys or ordinary sessions authorized")
	}
	if _, err = l.c.CreateRecoveryCodeResetIntent(ctx, oldCode); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("Passkey reset retained old code: %v", err)
	}
	if _, err = l.c.CreateRecoveryCodeResetIntent(ctx, reset.NewRecoveryCode); err != nil {
		t.Fatalf("Passkey reset did not activate replacement recovery code: %v", err)
	}
}

func TestPasskeyAccountBindingAndCredentialIDOwnershipPostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	owner, _ := recoveryTestAccount(t, l, "cred_owner_user")
	other, _ := recoveryTestAccount(t, l, "cred_other_user")
	fixture := credentialAddPasskey(t, l, owner.SessionToken, 0x61)
	worker := sessionTestPasswordWorker(t, 1)
	if _, err := l.c.CreatePasskeyRemovalIntent(ctx, other.SessionToken, labLoginPassword, passkeyEncode(fixture.credentialID), worker); !errors.Is(err, ErrCredentialNotFound) {
		t.Fatalf("other-account credential revealed ownership or permitted removal: %v", err)
	}
	proof := credentialPasskeyProof(t, l, fixture, 0)
	proof.Response.UserHandle = passkeyEncode(bytes.Repeat([]byte{0}, 32))
	if _, err := l.c.CreatePasskeyResetIntent(ctx, proof); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("signature with wrong random account handle exposed username: %v", err)
	}
	options, err := l.c.CreatePasskeyOptions(ctx, other.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	_, registration := credentialRegistration(t, options, 0x61)
	if _, err = l.c.RegisterPasskey(ctx, other.SessionToken, registration); !errors.Is(err, ErrConflict) {
		t.Fatalf("globally-owned credential ID rebound to another account: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, owner.AccountID) != 1 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, other.AccountID) != 0 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND credential_version=1`, other.AccountID) != 1 {
		t.Fatal("ownership collision modified either account's credentials")
	}
}

func TestCredentialVersionInvalidatesPendingCeremoniesPostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, oldCode := recoveryTestAccount(t, l, "cred_stale_user")
	fixture := credentialAddPasskey(t, l, initial.SessionToken, 0x71)
	worker := sessionTestPasswordWorker(t, 1)
	options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	_, registration := credentialRegistration(t, options, 0x72)
	removal, err := l.c.CreatePasskeyRemovalIntent(ctx, initial.SessionToken, labLoginPassword, passkeyEncode(fixture.credentialID), worker)
	if err != nil {
		t.Fatal(err)
	}
	reset, err := l.c.CreateRecoveryCodeResetIntent(ctx, oldCode)
	if err != nil {
		t.Fatal(err)
	}
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, rotationConfirmation(t, rotation)); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, registration); !errors.Is(err, ErrCredentialIntentInvalid) {
		t.Fatalf("registration challenge carried old credential authority into new version: %v", err)
	}
	if _, err = l.c.RemovePasskey(ctx, initial.SessionToken, PasskeyRemoval{IntentID: removal.ID, IdempotencyKey: credentialRequestKey(t), CredentialID: passkeyEncode(fixture.credentialID)}); !errors.Is(err, ErrCredentialIntentInvalid) {
		t.Fatalf("removal intent carried old credential authority into new version: %v", err)
	}
	if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, reset), &fixedRecoveryProcessor{}); !errors.Is(err, ErrResetIntentInvalid) {
		t.Fatalf("reset intent carried old credential authority into new version: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 1 {
		t.Fatal("stale ceremony changed retained credential set")
	}
}

func TestCredentialIntentExpiryUsesTrustedTimePostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_expiry_user")
	fixture := credentialAddPasskey(t, l, initial.SessionToken, 0x81)
	worker := sessionTestPasswordWorker(t, 1)
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	_, registration := credentialRegistration(t, options, 0x82)
	removal, err := l.c.CreatePasskeyRemovalIntent(ctx, initial.SessionToken, labLoginPassword, passkeyEncode(fixture.credentialID), worker)
	if err != nil {
		t.Fatal(err)
	}
	proof := credentialPasskeyProof(t, l, fixture, 0)
	advanceClosureClock(t, control, rotation.ExpiresAt.Add(time.Second))
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, rotationConfirmation(t, rotation)); !errors.Is(err, ErrCredentialIntentExpired) {
		t.Fatalf("trusted ten-minute expiry did not reject rotation: %v", err)
	}
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, registration); !errors.Is(err, ErrCredentialIntentExpired) {
		t.Fatalf("trusted five-minute expiry did not reject enrollment: %v", err)
	}
	if _, err = l.c.RemovePasskey(ctx, initial.SessionToken, PasskeyRemoval{IntentID: removal.ID, IdempotencyKey: credentialRequestKey(t), CredentialID: passkeyEncode(fixture.credentialID)}); !errors.Is(err, ErrCredentialIntentExpired) {
		t.Fatalf("trusted five-minute expiry did not reject removal: %v", err)
	}
	if _, err = l.c.CreatePasskeyResetIntent(ctx, proof); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("trusted five-minute expiry did not reject anonymous recovery proof: %v", err)
	}
}

func TestCredentialMutationsRollBackOnSecurityEventFailurePostgres(t *testing.T) {
	for _, operation := range []string{"rotate", "register", "remove", "passkey_reset"} {
		t.Run(operation, func(t *testing.T) {
			l := newLab(t)
			credentialWebAuthnLab(t, l)
			ctx := context.Background()
			initial, oldCode := recoveryTestAccount(t, l, "cred_rollback_user")
			fixture := credentialAddPasskey(t, l, initial.SessionToken, 0x91)
			worker := sessionTestPasswordWorker(t, 1)
			var perform func() error
			switch operation {
			case "rotate":
				intent, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
				if err != nil {
					t.Fatal(err)
				}
				request := rotationConfirmation(t, intent)
				perform = func() error {
					_, err := l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, request)
					return err
				}
			case "register":
				options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
				if err != nil {
					t.Fatal(err)
				}
				_, request := credentialRegistration(t, options, 0x92)
				perform = func() error { _, err := l.c.RegisterPasskey(ctx, initial.SessionToken, request); return err }
			case "remove":
				intent, err := l.c.CreatePasskeyRemovalIntent(ctx, initial.SessionToken, labLoginPassword, passkeyEncode(fixture.credentialID), worker)
				if err != nil {
					t.Fatal(err)
				}
				request := PasskeyRemoval{IntentID: intent.ID, IdempotencyKey: credentialRequestKey(t), CredentialID: passkeyEncode(fixture.credentialID)}
				perform = func() error { _, err := l.c.RemovePasskey(ctx, initial.SessionToken, request); return err }
			case "passkey_reset":
				reset, err := l.c.CreatePasskeyResetIntent(ctx, credentialPasskeyProof(t, l, fixture, 0))
				if err != nil {
					t.Fatal(err)
				}
				request := recoveryTestRequest(t, reset)
				perform = func() error { return l.c.CommitPasswordReset(ctx, request, &fixedRecoveryProcessor{}) }
			}
			mustExec(t, l.cp, `CREATE FUNCTION c_auth.fail_credential_event_fixture() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic credential security-event failure'; END $$;
				CREATE TRIGGER fail_credential_event_fixture BEFORE INSERT ON c_auth.security_events FOR EACH ROW EXECUTE FUNCTION c_auth.fail_credential_event_fixture()`)
			if err := perform(); err == nil {
				t.Fatal("credential transaction ignored injected security-event failure")
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND credential_version=2 AND session_generation=1`, initial.AccountID) != 1 ||
				count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 1 ||
				count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 1 {
				t.Fatal("failed transaction partially changed credentials or sessions")
			}
			oldDigest, _ := recoveryDigest(oldCode)
			if count(t, l.cp, `SELECT count(*) FROM c_auth.recovery_codes WHERE account_id=$1 AND code_digest=$2`, initial.AccountID, oldDigest[:]) != 1 {
				t.Fatal("failed transaction consumed original recovery code")
			}
			mustExec(t, l.cp, `DROP TRIGGER fail_credential_event_fixture ON c_auth.security_events`)
			if err := perform(); err != nil {
				t.Fatalf("rolled-back ceremony could not retry after fault removed: %v", err)
			}
		})
	}
}

func TestCredentialAccountLockWaitCannotCrossFreezePostgres(t *testing.T) {
	for _, operation := range []string{"read", "rotate", "register", "remove", "passkey_reset"} {
		t.Run(operation, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			credentialWebAuthnLab(t, l)
			ctx := context.Background()
			initial, _ := recoveryTestAccount(t, l, "cred_frozen_wait_user")
			fixture := credentialAddPasskey(t, l, initial.SessionToken, 0xa1)
			worker := sessionTestPasswordWorker(t, 1)
			var perform func() error
			switch operation {
			case "read":
				perform = func() error { _, err := l.c.GetRecoveryCredentials(ctx, initial.SessionToken); return err }
			case "rotate":
				intent, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
				if err != nil {
					t.Fatal(err)
				}
				request := rotationConfirmation(t, intent)
				perform = func() error {
					_, err := l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, request)
					return err
				}
			case "register":
				options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
				if err != nil {
					t.Fatal(err)
				}
				_, request := credentialRegistration(t, options, 0xa2)
				perform = func() error { _, err := l.c.RegisterPasskey(ctx, initial.SessionToken, request); return err }
			case "remove":
				intent, err := l.c.CreatePasskeyRemovalIntent(ctx, initial.SessionToken, labLoginPassword, passkeyEncode(fixture.credentialID), worker)
				if err != nil {
					t.Fatal(err)
				}
				request := PasskeyRemoval{IntentID: intent.ID, IdempotencyKey: credentialRequestKey(t), CredentialID: passkeyEncode(fixture.credentialID)}
				perform = func() error { _, err := l.c.RemovePasskey(ctx, initial.SessionToken, request); return err }
			case "passkey_reset":
				proof := credentialPasskeyProof(t, l, fixture, 0)
				perform = func() error { _, err := l.c.CreatePasskeyResetIntent(ctx, proof); return err }
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
			answer := make(chan error, 1)
			go func() { answer <- perform() }()
			waitLock(t, l.cp, "transactionid", 1)
			if err = control.gate.Freeze(ctx, "credential operation waiting for account lock"); err != nil {
				t.Fatal(err)
			}
			if err = hold.Commit(ctx); err != nil {
				t.Fatal(err)
			}
			if err = <-answer; !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatalf("%s crossed freeze after account lock wait: %v", operation, err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND credential_version=2`, initial.AccountID) != 1 ||
				count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 1 {
				t.Fatal("frozen operation committed a credential change")
			}
		})
	}
}

func TestAuthorizationRecoveryInvalidatesCredentialAuthorityPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_gate_recovery_user")
	fixture := credentialAddPasskey(t, l, initial.SessionToken, 0xb1)
	worker := sessionTestPasswordWorker(t, 1)
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	proof := credentialPasskeyProof(t, l, fixture, 0)
	if err = control.gate.Freeze(ctx, "credential restore boundary"); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.GetRecoveryCredentials(ctx, initial.SessionToken); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen read disclosed credential state: %v", err)
	}
	if _, err = l.c.CreatePasskeyResetOptions(ctx); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen gate issued recovery challenge: %v", err)
	}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, rotationConfirmation(t, rotation)); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen confirmation committed: %v", err)
	}
	control.clock.set(control.clock.now().Add(time.Second))
	control.recover(t, AuthorizationRecoveryNormal, 3, 3)
	if _, err = l.c.CreatePasskeyResetIntent(ctx, proof); !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("old-generation anonymous challenge revived after recovery: %v", err)
	}
	if _, err = l.c.GetRecoveryCredentials(ctx, initial.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("old-generation session accessed recovery credential list: %v", err)
	}
	login, err := l.c.CreateSession(ctx, sessionTestRequest(t, "cred_gate_recovery_user"), worker)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, login.SessionToken, rotationConfirmation(t, rotation)); !errors.Is(err, ErrCredentialIntentInvalid) {
		t.Fatalf("fresh session revived old rotation intent: %v", err)
	}
	if _, err = l.c.CreatePasskeyResetIntent(ctx, credentialPasskeyProof(t, l, fixture, 0)); err != nil {
		t.Fatalf("persisted Passkey cannot prove under fresh gate challenge: %v", err)
	}
}

func TestPasskeySyncedCounterZeroAndRiskSignalRemainRecoverablePostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_counter_user")
	fixture := credentialAddPasskey(t, l, initial.SessionToken, 0xc1)
	for _, value := range []uint32{0, 0, 10, 9} {
		if _, err := l.c.CreatePasskeyResetIntent(ctx, credentialPasskeyProof(t, l, fixture, value)); err != nil {
			t.Fatalf("synced Passkey counter %d was blanket classified compromised: %v", value, err)
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.reset_intents WHERE account_id=$1 AND state='ACTIVE'`, initial.AccountID) != 1 {
		t.Fatal("successive valid assertions did not replace prior reset intent atomically")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.security_events WHERE account_id=$1 AND action='PASSKEY_COUNTER_RISK'`, initial.AccountID) < 1 {
		t.Fatal("non-incrementing nonzero counter lacked bounded internal risk signal")
	}
}

func TestPasskeyLastRecoveryRouteAndEnrollmentLimitPostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_recovery_limit_user")
	fixture := credentialAddPasskey(t, l, initial.SessionToken, 0xd1)
	worker := sessionTestPasswordWorker(t, 1)
	removal, err := l.c.CreatePasskeyRemovalIntent(ctx, initial.SessionToken, labLoginPassword, passkeyEncode(fixture.credentialID), worker)
	if err != nil {
		t.Fatal(err)
	}
	// Simulate a damaged recovery-code row. Management must not worsen it by
	// deleting the account's sole remaining usable recovery route.
	mustExec(t, l.cp, `DELETE FROM c_auth.recovery_codes WHERE account_id=$1`, initial.AccountID)
	if _, err = l.c.RemovePasskey(ctx, initial.SessionToken, PasskeyRemoval{IntentID: removal.ID, IdempotencyKey: credentialRequestKey(t), CredentialID: passkeyEncode(fixture.credentialID)}); !errors.Is(err, ErrConflict) {
		t.Fatalf("removed the last effective recovery route: %v", err)
	}
	for i := byte(2); i <= 10; i++ {
		credentialAddPasskey(t, l, initial.SessionToken, 0xd0+i)
	}
	if _, err = l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker); !errors.Is(err, ErrPasskeyLimit) {
		t.Fatalf("eleventh Passkey option bypassed capacity limit: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 10 {
		t.Fatal("Passkey count exceeded ten")
	}
}

func TestCredentialManagementRejectsRevokedAndForeignSessionsPostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_session_bound_user")
	worker := sessionTestPasswordWorker(t, 1)
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	_, registration := credentialRegistration(t, options, 0xe1)
	login, err := l.c.CreateSession(ctx, sessionTestRequest(t, "cred_session_bound_user"), worker)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, login.SessionToken, rotationConfirmation(t, rotation)); !errors.Is(err, ErrCredentialIntentInvalid) {
		t.Fatalf("replacement session inherited prior fresh-password rotation: %v", err)
	}
	if _, err = l.c.RegisterPasskey(ctx, login.SessionToken, registration); !errors.Is(err, ErrCredentialIntentInvalid) {
		t.Fatalf("replacement session inherited prior enrollment challenge: %v", err)
	}
	if _, err = l.c.GetRecoveryCredentials(ctx, initial.SessionToken); !errors.Is(err, ErrSessionReplaced) && !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("replaced session read credential inventory: %v", err)
	}
	if err = l.c.RevokeSession(ctx, digest("HNUHOLE/SESSION-REVOKE/V1", login.SessionToken[:])); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.CreateRecoveryCodeRotation(ctx, login.SessionToken, labLoginPassword, worker); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("logout bearer with password still obtained management authority: %v", err)
	}
	hash := sha256.Sum256(login.SessionToken[:])
	if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE token_digest=$1 AND revoked_at IS NOT NULL`, hash[:]) != 1 {
		t.Fatal("revocation fixture failed")
	}
}

func TestConcurrentPasskeyRegistrationsConsumeOneCredentialVersionPostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_enroll_race_user")
	worker := sessionTestPasswordWorker(t, 1)
	requests := make([]PasskeyRegistration, 2)
	for i := range requests {
		options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
		if err != nil {
			t.Fatal(err)
		}
		_, requests[i] = credentialRegistration(t, options, byte(0xf1+i))
	}
	answers := make([]error, len(requests))
	var group sync.WaitGroup
	for i := range requests {
		group.Add(1)
		go func(i int) {
			defer group.Done()
			_, answers[i] = l.c.RegisterPasskey(ctx, initial.SessionToken, requests[i])
		}(i)
	}
	group.Wait()
	success := 0
	for _, err := range answers {
		if err == nil {
			success++
		} else if !errors.Is(err, ErrCredentialIntentInvalid) {
			t.Fatalf("unexpected concurrent registration error: %v", err)
		}
	}
	if success != 1 || count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 1 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND credential_version=2`, initial.AccountID) != 1 {
		t.Fatalf("simultaneous credential changes committed %d times from one original proof version", success)
	}
}

func TestPasskeyAssertionRechecksOriginalVersionAfterAccountLockWaitPostgres(t *testing.T) {
	l := newLab(t)
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_assert_stale_user")
	fixture := credentialAddPasskey(t, l, initial.SessionToken, 0x31)
	proof := credentialPasskeyProof(t, l, fixture, 0)
	hold, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(ctx)
	var version int64
	if err = hold.QueryRow(ctx, `SELECT credential_version FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, initial.AccountID).Scan(&version); err != nil {
		t.Fatal(err)
	}
	answer := make(chan error, 1)
	go func() { _, err := l.c.CreatePasskeyResetIntent(ctx, proof); answer <- err }()
	waitLock(t, l.cp, "transactionid", 1)
	if _, err = hold.Exec(ctx, `UPDATE c_auth.accounts SET credential_version=credential_version+1 WHERE account_id=$1`, initial.AccountID); err != nil {
		t.Fatal(err)
	}
	if err = hold.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err = <-answer; !errors.Is(err, ErrRecoveryProofInvalid) {
		t.Fatalf("old signed assertion authorized a newer credential version: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.reset_intents WHERE account_id=$1`, initial.AccountID) != 0 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.auth_challenges WHERE challenge_id=$1 AND state='ACTIVE'`, proof.ChallengeID[:]) != 1 {
		t.Fatal("failed stale assertion consumed challenge or created reset authority")
	}
	if _, err = l.c.CreatePasskeyResetIntent(ctx, credentialPasskeyProof(t, l, fixture, 0)); err != nil {
		t.Fatalf("retained credential could not provide a new proof after unrelated version advance: %v", err)
	}
}

func TestCredentialIntentDatabaseRejectsNullAuthorizationShapesPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_sql_shape_user")
	now := time.Now().UTC()
	token := sha256.Sum256(initial.SessionToken[:])
	one := int64(1)
	type intentShape struct {
		name, kind, state         string
		rotation                  *int64
		target, challenge, digest []byte
		terminal                  *time.Time
	}
	for _, test := range []intentShape{
		{name: "rotation_without_digest", kind: "ROTATE_CODE", state: "ACTIVE", rotation: &one},
		{name: "rotation_without_generation", kind: "ROTATE_CODE", state: "ACTIVE", digest: token[:]},
		{name: "removal_without_target", kind: "REMOVE_PASSKEY", state: "ACTIVE"},
		{name: "creation_without_challenge", kind: "CREATE_PASSKEY", state: "ACTIVE"},
		{name: "terminal_without_time", kind: "REMOVE_PASSKEY", state: "CONSUMED"},
	} {
		t.Run(test.name, func(t *testing.T) {
			id := credentialRequestKey(t)
			duration := 5 * time.Minute
			if test.kind == "ROTATE_CODE" {
				duration = 10 * time.Minute
			}
			_, err := l.cp.Exec(ctx, `INSERT INTO c_auth.credential_change_intents(intent_id,account_id,kind,session_digest,session_generation,credential_version,authorization_generation,rotation_generation,target_credential_id,challenge_id,new_recovery_digest,state,created_at,expires_at,terminal_at)
				VALUES($1,$2,$3,$4,1,1,1,$5,$6,$7,$8,$9,$10,$11,$12)`, id[:], initial.AccountID, test.kind, token[:], test.rotation, test.target, test.challenge, test.digest, test.state, now, now.Add(duration), test.terminal)
			var sqlError *pgconn.PgError
			if !errors.As(err, &sqlError) || sqlError.Code != "23514" {
				t.Fatalf("nullable intent shape escaped CHECK rejection: %v", err)
			}
		})
	}
	type challengeShape struct {
		name, kind, state                 string
		account                           any
		session                           []byte
		sessionVersion, credentialVersion *int64
		nonce                             []byte
		terminal                          *time.Time
	}
	for _, test := range []challengeShape{
		{name: "active_reset_without_nonce", kind: "RESET_PASSKEY", state: "ACTIVE"},
		{name: "active_creation_without_session", kind: "CREATE_PASSKEY", state: "ACTIVE", account: initial.AccountID, sessionVersion: &one, credentialVersion: &one, nonce: token[:]},
		{name: "active_creation_without_generation", kind: "CREATE_PASSKEY", state: "ACTIVE", account: initial.AccountID, session: token[:], credentialVersion: &one, nonce: token[:]},
		{name: "active_creation_without_version", kind: "CREATE_PASSKEY", state: "ACTIVE", account: initial.AccountID, session: token[:], sessionVersion: &one, nonce: token[:]},
		{name: "terminal_reset_without_time", kind: "RESET_PASSKEY", state: "CONSUMED"},
	} {
		t.Run(test.name, func(t *testing.T) {
			id := credentialRequestKey(t)
			_, err := l.cp.Exec(ctx, `INSERT INTO c_auth.auth_challenges(challenge_id,kind,account_id,session_digest,session_generation,credential_version,authorization_generation,policy_digest,nonce,state,created_at,expires_at,terminal_at)
				VALUES($1,$2,$3,$4,$5,$6,1,$7,$8,$9,$10,$11,$12)`, id[:], test.kind, test.account, test.session, test.sessionVersion, test.credentialVersion, token[:], test.nonce, test.state, now, now.Add(5*time.Minute), test.terminal)
			var sqlError *pgconn.PgError
			if !errors.As(err, &sqlError) || sqlError.Code != "23514" {
				t.Fatalf("nullable challenge shape escaped CHECK rejection: %v", err)
			}
		})
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.credential_change_intents`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_auth.auth_challenges`) != 0 {
		t.Fatal("database persisted a challenge or management intent missing mandatory authority")
	}
}

func TestPasskeyResetPreservesPendingClosureAndRejectsDeadlinePostgres(t *testing.T) {
	for _, mode := range []string{"before_due", "at_due"} {
		t.Run(mode, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			credentialWebAuthnLab(t, l)
			ctx := context.Background()
			initial, _ := recoveryTestAccount(t, l, "cred_close_reset_user")
			fixture := credentialAddPasskey(t, l, initial.SessionToken, 0x21)
			worker := sessionTestPasswordWorker(t, 1)
			closureRequest, _ := closureTestRequest(t, initial.SessionToken)
			closure, err := l.c.RequestAccountClosure(ctx, closureRequest, worker)
			if err != nil {
				t.Fatal(err)
			}
			reset, err := l.c.CreatePasskeyResetIntent(ctx, credentialPasskeyProof(t, l, fixture, 0))
			if err != nil {
				t.Fatalf("timely Passkey recovery was blocked by pending closure: %v", err)
			}
			if mode == "at_due" {
				proof := credentialPasskeyProof(t, l, fixture, 0)
				advanceClosureClock(t, control, closure.DueAt)
				if _, err = l.c.CreatePasskeyResetIntent(ctx, proof); !errors.Is(err, ErrRecoveryProofInvalid) {
					t.Fatalf("Passkey proof crossed closure due time: %v", err)
				}
				if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, reset), &fixedRecoveryProcessor{}); !errors.Is(err, ErrRecoveryProofInvalid) {
					t.Fatalf("Passkey reset intent committed at closure due time: %v", err)
				}
				if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='PENDING_CLOSE' AND credential_version=2`, initial.AccountID) != 1 {
					t.Fatal("deadline rejection altered account credentials or closure")
				}
				return
			}
			if err = l.c.CommitPasswordReset(ctx, recoveryTestRequest(t, reset), &fixedRecoveryProcessor{}); err != nil {
				t.Fatal(err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='PENDING_CLOSE'`, initial.AccountID) != 1 ||
				count(t, l.cp, `SELECT count(*) FROM c_auth.closure_requests WHERE closure_id=$1 AND state='PENDING'`, closureRequest.ID[:]) != 1 {
				t.Fatal("Passkey recovery silently cancelled account closure")
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL`, initial.AccountID) != 0 ||
				count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 0 {
				t.Fatal("reset under pending closure kept old authority")
			}
		})
	}
}

func TestCredentialCleanupClearsExpiredSecretsWithBoundedFrozenWritesPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_cleanup_expiry_user")
	worker := sessionTestPasswordWorker(t, 1)
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.CreatePasskeyResetOptions(ctx); err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, rotation.ExpiresAt.Add(time.Second))
	if err = control.gate.Freeze(ctx, "credential expiry cleanup must use trusted authorization"); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.CleanupCredentialState(ctx, 10); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatalf("frozen cleanup accepted credential state changes: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.credential_change_intents WHERE state='ACTIVE'`) != 2 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.auth_challenges WHERE state='ACTIVE' AND nonce IS NOT NULL`) != 2 {
		t.Fatal("frozen cleanup erased pending authority or nonce")
	}
	control.recover(t, AuthorizationRecoveryNormal, 3, 3)
	first, err := l.c.CleanupCredentialState(ctx, 1)
	if err != nil || first != 1 {
		t.Fatalf("bounded cleanup changed %d candidates: %v", first, err)
	}
	if _, err = l.c.CleanupCredentialState(ctx, 10); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.credential_change_intents WHERE state='EXPIRED' AND new_recovery_digest IS NULL AND target_credential_id IS NULL AND challenge_id IS NULL`) != 2 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.auth_challenges WHERE state='EXPIRED' AND nonce IS NULL`) != 2 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND active_rotation_intent_id IS NULL AND credential_version=1`, initial.AccountID) != 1 {
		t.Fatal("expiry cleanup retained authority, secret digest, nonce or dangling active pointer")
	}
	advanceClosureClock(t, control, control.clock.now().Add(7*24*time.Hour))
	if _, err = l.c.CleanupCredentialState(ctx, 10); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.credential_change_intents`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_auth.auth_challenges`) != 0 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.recovery_codes WHERE account_id=$1`, initial.AccountID) != 1 {
		t.Fatal("terminal cleanup retained stale metadata or erased active recovery route")
	}
}

func TestCredentialResultsKeepPermanentTombstonesAfterMetadataExpiryPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	credentialWebAuthnLab(t, l)
	ctx := context.Background()
	initial, _ := recoveryTestAccount(t, l, "cred_result_ttl_user")
	worker := sessionTestPasswordWorker(t, 1)
	rotation, err := l.c.CreateRecoveryCodeRotation(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	request := rotationConfirmation(t, rotation)
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, request); err != nil {
		t.Fatal(err)
	}
	options, err := l.c.CreatePasskeyOptions(ctx, initial.SessionToken, labLoginPassword, worker)
	if err != nil {
		t.Fatal(err)
	}
	_, registration := credentialRegistration(t, options, 0x12)
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, registration); err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, control.clock.now().Add(7*24*time.Hour))
	if _, err = l.c.CleanupCredentialState(ctx, 10); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE operation IN ('ROTATE_CODE','CREATE_PASSKEY') AND state='LIVE'`) != 2 {
		t.Fatal("cleanup removed recovery evidence before its eight-day result window")
	}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, request); err != nil {
		t.Fatalf("retained result could not resolve retry after seven days: %v", err)
	}
	advanceClosureClock(t, control, control.clock.now().Add(24*time.Hour+time.Second))
	if _, err = l.c.CleanupCredentialState(ctx, 10); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE operation IN ('ROTATE_CODE','CREATE_PASSKEY') AND state='EXPIRED' AND request_hmac IS NULL AND credential_change_id IS NULL AND auth_challenge_id IS NULL`) != 2 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.credential_change_intents`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_auth.auth_challenges`) != 0 {
		t.Fatal("result expiry retained account-linked metadata or deleted permanent request anchors")
	}
	if _, err = l.c.ConfirmRecoveryCodeRotation(ctx, initial.SessionToken, request); !errors.Is(err, ErrExpired) {
		t.Fatalf("old key recreated rotation after metadata expiry: %v", err)
	}
	if _, err = l.c.RegisterPasskey(ctx, initial.SessionToken, registration); !errors.Is(err, ErrExpired) {
		t.Fatalf("old key recreated credential after metadata expiry: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, initial.AccountID) != 1 ||
		count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND credential_version=3`, initial.AccountID) != 1 {
		t.Fatal("late expired retries mutated current credentials")
	}
}
