package authprivacy

import (
	"context"
	"crypto/hmac"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type authChallenge struct {
	kind, state          string
	account              *uuid.UUID
	token, nonce, policy []byte
	version, generation  *int64
	authGeneration       int64
	expires              time.Time
}

func readAuthChallenge(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, id [32]byte, lock bool) (authChallenge, error) {
	var r authChallenge
	sql := `SELECT kind,state,account_id,session_digest,nonce,policy_digest,credential_version,session_generation,authorization_generation,expires_at FROM c_auth.auth_challenges WHERE challenge_id=$1`
	if lock {
		sql += " FOR UPDATE"
	}
	err := q.QueryRow(ctx, sql, id[:]).Scan(&r.kind, &r.state, &r.account, &r.token, &r.nonce, &r.policy, &r.version, &r.generation, &r.authGeneration, &r.expires)
	if errors.Is(err, pgx.ErrNoRows) {
		return r, ErrCredentialIntentInvalid
	}
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	return r, nil
}
func (r authChallenge) valid(f AuthorizationDecision, policy [32]byte, kind string) error {
	if r.kind != kind || r.state != "ACTIVE" || len(r.nonce) != 32 || r.authGeneration != int64(f.Generation) || !hmac.Equal(r.policy, policy[:]) {
		return ErrCredentialIntentInvalid
	}
	if !f.TrustedAt.Before(r.expires) {
		return ErrCredentialIntentExpired
	}
	return nil
}
func creationOptions(rp string, nonce [32]byte, handle []byte, exclude []map[string]string) map[string]any {
	encoded := base64.RawURLEncoding.EncodeToString(handle)
	return map[string]any{"rp": map[string]string{"id": rp, "name": "Hnuhole"}, "user": map[string]string{"id": encoded, "name": encoded, "displayName": "Hnuhole account"}, "challenge": base64.RawURLEncoding.EncodeToString(nonce[:]), "pubKeyCredParams": []map[string]any{{"type": "public-key", "alg": -7}}, "timeout": 60000, "excludeCredentials": exclude, "authenticatorSelection": map[string]any{"residentKey": "required", "requireResidentKey": true, "userVerification": "required"}, "attestation": "none"}
}
func (c *Community) CreatePasskeyOptions(ctx context.Context, bearer [32]byte, password string, verifier PasswordVerifier) (PasskeyOptions, error) {
	var r PasskeyOptions
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return r, err
	}
	policy, err := c.webAuthnPolicy()
	if err != nil {
		return r, err
	}
	p, err := c.proveCredentialPassword(ctx, bearer, password, verifier)
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
	handle, err := random32()
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	tx, a, s, err := c.credentialTransaction(ctx, bearer)
	if err != nil {
		return r, err
	}
	defer c.gate.Abort(ctx, tx)
	if err = checkCredentialProof(p, a, s); err != nil {
		return r, err
	}
	exclude := make([]map[string]string, 0)
	rows, err := tx.Query(ctx, `SELECT credential_id FROM c_auth.passkeys WHERE account_id=$1 ORDER BY credential_id LIMIT 11`, a.account)
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	for rows.Next() {
		var raw []byte
		if err = rows.Scan(&raw); err != nil {
			break
		}
		exclude = append(exclude, map[string]string{"type": "public-key", "id": base64.RawURLEncoding.EncodeToString(raw)})
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	if len(exclude) >= 10 {
		return r, ErrPasskeyLimit
	}
	if a.handle == nil {
		a.handle = handle[:]
	} else if len(a.handle) != 32 {
		return r, ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		if e := s.validate(a, f); e != nil {
			return e
		}
		r.ExpiresAt = f.TrustedAt.Add(5 * time.Minute)
		if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET user_handle=$2 WHERE account_id=$1 AND user_handle IS NULL`, a.account, a.handle); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `INSERT INTO c_auth.auth_challenges(challenge_id,kind,account_id,session_digest,session_generation,credential_version,authorization_generation,policy_digest,nonce,state,created_at,expires_at) VALUES($1,'CREATE_PASSKEY',$2,$3,$4,$5,$6,$7,$8,'ACTIVE',$9,$10)`, r.ChallengeID[:], a.account, s.token[:], s.generation, a.version, int64(f.Generation), policy[:], nonce[:], f.TrustedAt, r.ExpiresAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `INSERT INTO c_auth.credential_change_intents(intent_id,account_id,kind,session_digest,session_generation,credential_version,authorization_generation,challenge_id,state,created_at,expires_at) VALUES($1,$2,'CREATE_PASSKEY',$3,$4,$5,$6,$1,'ACTIVE',$7,$8)`, r.ChallengeID[:], a.account, s.token[:], s.generation, a.version, int64(f.Generation), f.TrustedAt, r.ExpiresAt); e != nil {
			return e
		}
		var e error
		r.SessionExpiresAt, e = s.renew(ctx, tx, f.TrustedAt)
		return e
	})
	if err != nil {
		return PasskeyOptions{}, err
	}
	r.PublicKey = creationOptions(c.webauthnConfig.RPID, nonce, a.handle, exclude)
	return r, nil
}
func (c *Community) RegisterPasskey(ctx context.Context, bearer [32]byte, r PasskeyRegistration) (time.Time, error) {
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return time.Time{}, err
	}
	policy, err := c.webAuthnPolicy()
	if err != nil {
		return time.Time{}, err
	}
	if r.ChallengeID == ([32]byte{}) || r.IdempotencyKey == ([32]byte{}) {
		return time.Time{}, ErrCredentialIntentInvalid
	}
	// Parse crypto before SQL locks. Only a challenge bound to this account can
	// grant management authority after its original version is rechecked below.
	original, originalErr := readAuthChallenge(ctx, c.pool, r.ChallengeID, false)
	var proof VerifiedRegistration
	if originalErr == nil && original.state == "ACTIVE" && len(original.nonce) == 32 {
		var nonce [32]byte
		copy(nonce[:], original.nonce)
		proof, err = c.webauthn.VerifyRegistration(r.Response, nonce)
		if err != nil {
			return time.Time{}, err
		}
	}
	encoded, _ := json.Marshal(r.Response)
	tx, a, s, err := c.credentialTransaction(ctx, bearer, r.ChallengeID)
	if err != nil {
		return time.Time{}, err
	}
	defer c.gate.Abort(ctx, tx)
	key := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", r.IdempotencyKey[:])
	mac := requestMAC(c.requestKey, []byte("CREATE_PASSKEY"), s.token[:], r.ChallengeID[:], encoded)
	found, replayErr := readCredentialReplay(ctx, tx, key, mac, "CREATE_PASSKEY")
	if replayErr != nil && !found {
		return time.Time{}, replayErr
	}
	var intent credentialIntent
	var challenge authChallenge
	if !found {
		if originalErr != nil {
			return time.Time{}, originalErr
		}
		if original.account == nil || *original.account != a.account || original.version == nil || *original.version != a.version || len(proof.CredentialID) == 0 {
			return time.Time{}, ErrCredentialIntentInvalid
		}
		intent, err = readCredentialIntent(ctx, tx, a.account, r.ChallengeID)
		if err != nil {
			return time.Time{}, err
		}
		challenge, err = readAuthChallenge(ctx, tx, r.ChallengeID, true)
		if err != nil {
			return time.Time{}, err
		}
		if a.version == math.MaxInt64 || len(a.handle) != 32 {
			return time.Time{}, ErrAuthorizationUnavailable
		}
		var count int
		err = tx.QueryRow(ctx, `SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1`, a.account).Scan(&count)
		if err != nil {
			return time.Time{}, ErrAuthorizationUnavailable
		}
		if count >= 10 {
			return time.Time{}, ErrPasskeyLimit
		}
		claimed, e := claimCredentialResult(ctx, tx, key, mac, r.ChallengeID, "CREATE_PASSKEY", d.TrustedAt)
		if e != nil {
			return time.Time{}, e
		}
		if !claimed {
			found, replayErr = readCredentialReplay(ctx, tx, key, mac, "CREATE_PASSKEY")
			if !found {
				return time.Time{}, ErrAuthorizationUnavailable
			}
		}
	}
	var expires time.Time
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		if e := s.validate(a, f); e != nil {
			return e
		}
		if found {
			if replayErr != nil {
				return replayErr
			}
			var e error
			expires, e = s.renew(ctx, tx, f.TrustedAt)
			return e
		}
		if e := intent.valid(a, s, f, "CREATE_PASSKEY"); e != nil {
			return e
		}
		if e := challenge.valid(f, policy, "CREATE_PASSKEY"); e != nil {
			return e
		}
		if challenge.account == nil || *challenge.account != a.account || challenge.version == nil || *challenge.version != a.version || challenge.generation == nil || *challenge.generation != s.generation || !hmac.Equal(challenge.token, s.token[:]) || !hmac.Equal(challenge.nonce, original.nonce) {
			return ErrCredentialIntentInvalid
		}
		if _, e := tx.Exec(ctx, `INSERT INTO c_auth.passkeys(credential_id,account_id,public_key,created_at,user_handle,cose_algorithm,sign_count,backup_eligible,backed_up,created_credential_version) VALUES($1,$2,$3,$4,$5,-7,$6,$7,$8,$9)`, proof.CredentialID, a.account, proof.PublicKey, f.TrustedAt, a.handle, int64(proof.SignCount), proof.BackupEligible, proof.BackupState, a.version+1); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.auth_challenges SET state='CONSUMED',nonce=NULL,terminal_at=$2 WHERE challenge_id=$1`, r.ChallengeID[:], f.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.credential_change_intents SET state='CONSUMED',new_recovery_digest=NULL,target_credential_id=NULL,challenge_id=NULL,terminal_at=$2 WHERE intent_id=$1`, r.ChallengeID[:], f.TrustedAt); e != nil {
			return e
		}
		if e := invalidateCredentialAuthority(ctx, tx, a.account, f.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET credential_version=$2 WHERE account_id=$1`, a.account, a.version+1); e != nil {
			return e
		}
		if e := recordCredentialEvent(ctx, tx, a, "CREATE_PASSKEY", a.version+1, f.TrustedAt); e != nil {
			return e
		}
		var e error
		expires, e = s.renew(ctx, tx, f.TrustedAt)
		return e
	})
	return expires, credentialConflict(err)
}
func (c *Community) CreatePasskeyRemovalIntent(ctx context.Context, bearer [32]byte, password, id string, verifier PasswordVerifier) (PasskeyRemovalIntent, error) {
	var r PasskeyRemovalIntent
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return r, err
	}
	target, err := webAuthnBytes(id, 1, 1023)
	if err != nil {
		return r, ErrCredentialNotFound
	}
	p, err := c.proveCredentialPassword(ctx, bearer, password, verifier)
	if err != nil {
		return r, err
	}
	r.ID, err = random32()
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	tx, a, s, err := c.credentialTransaction(ctx, bearer)
	if err != nil {
		return r, err
	}
	defer c.gate.Abort(ctx, tx)
	if err = checkCredentialProof(p, a, s); err != nil {
		return r, err
	}
	var exists bool
	err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_auth.passkeys WHERE account_id=$1 AND credential_id=$2)`, a.account, target).Scan(&exists)
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		if e := s.validate(a, f); e != nil {
			return e
		}
		if !exists {
			return ErrCredentialNotFound
		}
		r.ExpiresAt = f.TrustedAt.Add(5 * time.Minute)
		if _, e := tx.Exec(ctx, `INSERT INTO c_auth.credential_change_intents(intent_id,account_id,kind,session_digest,session_generation,credential_version,authorization_generation,target_credential_id,state,created_at,expires_at) VALUES($1,$2,'REMOVE_PASSKEY',$3,$4,$5,$6,$7,'ACTIVE',$8,$9)`, r.ID[:], a.account, s.token[:], s.generation, a.version, int64(f.Generation), target, f.TrustedAt, r.ExpiresAt); e != nil {
			return e
		}
		var e error
		r.SessionExpiresAt, e = s.renew(ctx, tx, f.TrustedAt)
		return e
	})
	if err != nil {
		return PasskeyRemovalIntent{}, err
	}
	return r, nil
}
func (c *Community) RemovePasskey(ctx context.Context, bearer [32]byte, r PasskeyRemoval) (time.Time, error) {
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return time.Time{}, err
	}
	target, err := webAuthnBytes(r.CredentialID, 1, 1023)
	if err != nil {
		return time.Time{}, ErrCredentialNotFound
	}
	if r.IntentID == ([32]byte{}) || r.IdempotencyKey == ([32]byte{}) {
		return time.Time{}, ErrCredentialIntentInvalid
	}
	tx, a, s, err := c.credentialTransaction(ctx, bearer, r.IntentID)
	if err != nil {
		return time.Time{}, err
	}
	defer c.gate.Abort(ctx, tx)
	key := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", r.IdempotencyKey[:])
	mac := requestMAC(c.requestKey, []byte("REMOVE_PASSKEY"), s.token[:], r.IntentID[:], target)
	found, replayErr := readCredentialReplay(ctx, tx, key, mac, "REMOVE_PASSKEY")
	if replayErr != nil && !found {
		return time.Time{}, replayErr
	}
	var intent credentialIntent
	var exists, hasCode bool
	var count int
	if !found {
		intent, err = readCredentialIntent(ctx, tx, a.account, r.IntentID)
		if err != nil {
			return time.Time{}, err
		}
		if a.version == math.MaxInt64 {
			return time.Time{}, ErrAuthorizationUnavailable
		}
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_auth.passkeys WHERE account_id=$1 AND credential_id=$2),EXISTS(SELECT 1 FROM c_auth.recovery_codes WHERE account_id=$1),(SELECT count(*) FROM c_auth.passkeys WHERE account_id=$1)`, a.account, target).Scan(&exists, &hasCode, &count); err != nil {
			return time.Time{}, ErrAuthorizationUnavailable
		}
		if !exists {
			return time.Time{}, ErrCredentialNotFound
		}
		claimed, e := claimCredentialResult(ctx, tx, key, mac, r.IntentID, "REMOVE_PASSKEY", d.TrustedAt)
		if e != nil {
			return time.Time{}, e
		}
		if !claimed {
			found, replayErr = readCredentialReplay(ctx, tx, key, mac, "REMOVE_PASSKEY")
			if !found {
				return time.Time{}, ErrAuthorizationUnavailable
			}
		}
	}
	var expires time.Time
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		if e := s.validate(a, f); e != nil {
			return e
		}
		if found {
			if replayErr != nil {
				return replayErr
			}
			var e error
			expires, e = s.renew(ctx, tx, f.TrustedAt)
			return e
		}
		if e := intent.valid(a, s, f, "REMOVE_PASSKEY"); e != nil {
			return e
		}
		if !hmac.Equal(intent.target, target) {
			return ErrCredentialNotFound
		}
		if !hasCode && count <= 1 {
			return ErrConflict
		}
		if _, e := tx.Exec(ctx, `DELETE FROM c_auth.passkeys WHERE account_id=$1 AND credential_id=$2`, a.account, target); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.credential_change_intents SET state='CONSUMED',new_recovery_digest=NULL,target_credential_id=NULL,challenge_id=NULL,terminal_at=$2 WHERE intent_id=$1`, r.IntentID[:], f.TrustedAt); e != nil {
			return e
		}
		if e := invalidateCredentialAuthority(ctx, tx, a.account, f.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET credential_version=$2 WHERE account_id=$1`, a.account, a.version+1); e != nil {
			return e
		}
		if e := recordCredentialEvent(ctx, tx, a, "REMOVE_PASSKEY", a.version+1, f.TrustedAt); e != nil {
			return e
		}
		var e error
		expires, e = s.renew(ctx, tx, f.TrustedAt)
		return e
	})
	return expires, credentialConflict(err)
}
