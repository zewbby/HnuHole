package authprivacy

import (
	"context"
	"crypto/hmac"
	"encoding/base64"
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (c *Community) CreatePasskeyResetOptions(ctx context.Context) (PasskeyOptions, error) {
	var r PasskeyOptions
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return r, err
	}
	policy, err := c.webAuthnPolicy()
	if err != nil {
		return r, err
	}
	r.ChallengeID, err = random32()
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	nonce, err := random32()
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		r.ExpiresAt = f.TrustedAt.Add(5 * time.Minute)
		_, e := tx.Exec(ctx, `INSERT INTO c_auth.auth_challenges(challenge_id,kind,authorization_generation,policy_digest,nonce,state,created_at,expires_at) VALUES($1,'RESET_PASSKEY',$2,$3,$4,'ACTIVE',$5,$6)`, r.ChallengeID[:], int64(f.Generation), policy[:], nonce[:], f.TrustedAt, r.ExpiresAt)
		return e
	})
	if err != nil {
		return PasskeyOptions{}, err
	}
	r.PublicKey = map[string]any{"rpId": c.webauthnConfig.RPID, "challenge": base64.RawURLEncoding.EncodeToString(nonce[:]), "timeout": 60000, "userVerification": "required"}
	return r, nil
}

type passkeyRecoveryRow struct {
	account            uuid.UUID
	version            int64
	key, handle        []byte
	count              int64
	eligible, backedUp bool
}

func readPasskeyRecovery(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, id []byte) (passkeyRecoveryRow, error) {
	var r passkeyRecoveryRow
	err := q.QueryRow(ctx, `SELECT p.account_id,a.credential_version,p.public_key,p.user_handle,p.sign_count,p.backup_eligible,p.backed_up
 FROM c_auth.passkeys p JOIN c_auth.accounts a USING(account_id) WHERE p.credential_id=$1`, id).Scan(&r.account, &r.version, &r.key, &r.handle, &r.count, &r.eligible, &r.backedUp)
	if errors.Is(err, pgx.ErrNoRows) {
		return r, ErrRecoveryProofInvalid
	}
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	return r, nil
}

// A valid discoverable assertion proves only a ten-minute reset capability.
// It never creates a session, cancels a closure, or lifts a restriction.
func (c *Community) CreatePasskeyResetIntent(ctx context.Context, r PasskeyResetProof) (PasswordResetIntent, error) {
	var result PasswordResetIntent
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return result, err
	}
	policy, err := c.webAuthnPolicy()
	if err != nil {
		return result, err
	}
	if r.ChallengeID == ([32]byte{}) {
		return result, ErrRecoveryProofInvalid
	}
	original, err := readAuthChallenge(ctx, c.pool, r.ChallengeID, false)
	if err != nil || original.kind != "RESET_PASSKEY" || original.state != "ACTIVE" || len(original.nonce) != 32 {
		if errors.Is(err, ErrAuthorizationUnavailable) {
			return result, err
		}
		return result, ErrRecoveryProofInvalid
	}
	id, err := webAuthnCredentialID(r.Response.ID, r.Response.RawID, r.Response.Type)
	if err != nil {
		return result, ErrRecoveryProofInvalid
	}
	preliminary, err := readPasskeyRecovery(ctx, c.pool, id)
	if err != nil {
		return result, err
	}
	if len(preliminary.handle) != 32 {
		return result, ErrAuthorizationUnavailable
	}
	var nonce, handle [32]byte
	copy(nonce[:], original.nonce)
	copy(handle[:], preliminary.handle)
	verified, err := c.webauthn.VerifyAssertion(r.Response, nonce, preliminary.key, handle)
	if err != nil {
		return result, ErrRecoveryProofInvalid
	}
	result.ID, err = random32()
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	code, codeDigest, err := generateRecoveryCode()
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	// Anonymous challenges have no account. Lock the account first, then the
	// requested challenge before any recovery credential/session row.
	var a credentialAccount
	a.account = preliminary.account
	err = tx.QueryRow(ctx, `SELECT state,COALESCE(username,''),credential_version,session_generation,reset_generation FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, a.account).Scan(&a.state, &a.username, &a.version, &a.generation, &a.resetGeneration)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	a.ban, err = lockRestriction(ctx, tx, a.account)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	a.closure, err = lockPendingClosure(ctx, tx, a.account)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	if err = lockCredentialIntents(ctx, tx, a.account); err != nil {
		return result, ErrAuthorizationUnavailable
	}
	challenge, err := readAuthChallenge(ctx, tx, r.ChallengeID, true)
	if err != nil {
		return result, ErrRecoveryProofInvalid
	}
	if err = drainLocks(ctx, tx, `SELECT code_digest FROM c_auth.recovery_codes WHERE account_id=$1 FOR UPDATE`, a.account); err != nil {
		return result, ErrAuthorizationUnavailable
	}
	if err = drainLocks(ctx, tx, `SELECT credential_id FROM c_auth.passkeys WHERE account_id=$1 ORDER BY credential_id FOR UPDATE`, a.account); err != nil {
		return result, ErrAuthorizationUnavailable
	}
	locked, err := readPasskeyRecovery(ctx, tx, id)
	if err != nil {
		return result, err
	}
	if a.version != preliminary.version || locked.account != a.account || locked.version != preliminary.version || !hmac.Equal(locked.key, preliminary.key) || !hmac.Equal(locked.handle, preliminary.handle) || verified.BackupEligible != locked.eligible {
		return result, ErrRecoveryProofInvalid
	}
	if a.resetGeneration == math.MaxInt64 {
		return result, ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		if !recoveryAccountAllowed(a.state, a.closure, f.TrustedAt) {
			return ErrRecoveryProofInvalid
		}
		if e := challenge.valid(f, policy, "RESET_PASSKEY"); e != nil {
			return ErrRecoveryProofInvalid
		}
		if !hmac.Equal(challenge.nonce, original.nonce) {
			return ErrRecoveryProofInvalid
		}
		result.ExpiresAt = f.TrustedAt.Add(10 * time.Minute)
		// Synced credentials may legitimately keep zero/non-increasing counters.
		// Record bounded risk metadata, retain the high-water count, and allow a
		// cryptographically verified assertion without inventing an MFA guarantee.
		if locked.count > 0 && int64(verified.SignCount) <= locked.count {
			if e := recordCredentialEvent(ctx, tx, a, "PASSKEY_COUNTER_RISK", a.version, f.TrustedAt); e != nil {
				return e
			}
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.passkeys SET sign_count=GREATEST(sign_count,$2),backed_up=$3 WHERE credential_id=$1 AND account_id=$4`, id, int64(verified.SignCount), verified.BackupState, a.account); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.auth_challenges SET state='CONSUMED',nonce=NULL,terminal_at=$2 WHERE challenge_id=$1`, r.ChallengeID[:], f.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.reset_intents SET state='ABANDONED',new_recovery_digest=NULL,terminal_at=$2 WHERE account_id=$1 AND state='ACTIVE'`, a.account, f.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `INSERT INTO c_auth.reset_intents(intent_id,account_id,credential_version,reset_generation,authorization_generation,state,new_recovery_digest,created_at,expires_at) VALUES($1,$2,$3,$4,$5,'ACTIVE',$6,$7,$8)`, result.ID[:], a.account, preliminary.version, a.resetGeneration+1, int64(f.Generation), codeDigest[:], f.TrustedAt, result.ExpiresAt); e != nil {
			return e
		}
		_, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET reset_generation=$2,active_reset_intent_id=$3 WHERE account_id=$1`, a.account, a.resetGeneration+1, result.ID[:])
		return e
	})
	if err != nil {
		return PasswordResetIntent{}, err
	}
	result.Username = a.username
	result.NewRecoveryCode = code
	return result, nil
}
