package authprivacy

import (
	"context"
	"crypto/hmac"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// GetCredentialChangeResult reconciles a submitted change without retaining or
// replaying its new code/attestation. Absence of a transient result never proves
// failure: NOT_COMMITTED requires a known intent irreversibly terminalized in
// the same authorized transaction. The account -> intents -> session -> result
// lock order matches mutations and cleanup. A replaced session cannot inspect
// or adopt its predecessor's pending command.
func (c *Community) GetCredentialChangeResult(ctx context.Context, bearer, id, opaqueKey [32]byte) (CredentialChangeResult, error) {
	var result CredentialChangeResult
	if id == ([32]byte{}) || opaqueKey == ([32]byte{}) {
		return result, ErrCredentialIntentInvalid
	}
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return result, err
	}
	tx, a, s, err := c.credentialTransaction(ctx, bearer, id)
	if err != nil {
		return result, err
	}
	defer c.gate.Abort(ctx, tx)
	key := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", opaqueKey[:])
	var operation, state string
	var boundIntent, boundChallenge []byte
	var code *string
	var deadline *time.Time
	err = tx.QueryRow(ctx, `SELECT operation,state,credential_change_id,auth_challenge_id,result_code,expires_at FROM c_auth.request_results WHERE key_digest=$1 FOR UPDATE`, key[:]).Scan(&operation, &state, &boundIntent, &boundChallenge, &code, &deadline)
	found := err == nil
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return result, ErrAuthorizationUnavailable
	}
	var intent credentialIntent
	var challenge authChallenge
	var outcomeErr error
	if found && state == "EXPIRED" {
		outcomeErr = ErrExpired
	} else if found {
		if operation != "ROTATE_CODE" && operation != "CREATE_PASSKEY" && operation != "REMOVE_PASSKEY" {
			return result, ErrConflict
		}
		if operation == "CREATE_PASSKEY" {
			if !hmac.Equal(boundChallenge, id[:]) || len(boundIntent) != 0 {
				return result, ErrConflict
			}
			// credentialTransaction already locked this ID when it belongs
			// to the current account. Read foreign metadata without a lock:
			// taking its challenge lock after its result lock would reverse
			// another account's mutation order before ownership is rejected.
			challenge, err = readAuthChallenge(ctx, tx, id, false)
			if err != nil {
				return result, err
			}
			if challenge.account == nil || *challenge.account != a.account || !hmac.Equal(challenge.token, s.token[:]) || challenge.generation == nil || *challenge.generation != s.generation || challenge.authGeneration != s.authGeneration || challenge.state != "CONSUMED" {
				return result, ErrCredentialIntentInvalid
			}
		} else {
			if !hmac.Equal(boundIntent, id[:]) || len(boundChallenge) != 0 {
				return result, ErrConflict
			}
			intent, err = readCredentialIntent(ctx, tx, a.account, id)
			if err != nil {
				return result, err
			}
			if intent.kind != operation || !hmac.Equal(intent.token, s.token[:]) || intent.generation != s.generation || intent.authGeneration != s.authGeneration || intent.state != "CONSUMED" {
				return result, ErrCredentialIntentInvalid
			}
		}
		if state != "LIVE" || code == nil || *code != "COMMITTED" || deadline == nil {
			return result, ErrAuthorizationUnavailable
		}
	} else {
		intent, err = readCredentialIntent(ctx, tx, a.account, id)
		if err != nil {
			return result, err
		}
		if !hmac.Equal(intent.token, s.token[:]) || intent.generation != s.generation || intent.authGeneration != s.authGeneration {
			return result, ErrCredentialIntentInvalid
		}
		if intent.kind == "CREATE_PASSKEY" {
			challenge, err = readAuthChallenge(ctx, tx, id, true)
			if err != nil {
				return result, err
			}
			if challenge.account == nil || *challenge.account != a.account || !hmac.Equal(challenge.token, s.token[:]) {
				return result, ErrCredentialIntentInvalid
			}
		}
		// An already consumed intent with a different/missing opaque key does
		// not prove that this command committed or failed.
		if intent.state == "CONSUMED" {
			return result, ErrConflict
		}
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		if e := s.validate(a, f); e != nil {
			return e
		}
		if outcomeErr != nil {
			return nil
		}
		if found {
			if !f.TrustedAt.Before(*deadline) {
				if _, e := tx.Exec(ctx, `UPDATE c_auth.request_results SET state='EXPIRED',request_hmac=NULL,hmac_key_version=NULL,intent_id=NULL,reset_intent_id=NULL,credential_change_id=NULL,auth_challenge_id=NULL,result_code=NULL,expires_at=NULL WHERE key_digest=$1 AND state='LIVE'`, key[:]); e != nil {
					return e
				}
				outcomeErr = ErrExpired
				return nil
			}
			result.State = "COMMITTED"
		} else if intent.state != "ACTIVE" {
			if intent.state != "ABANDONED" && intent.state != "EXPIRED" {
				return ErrAuthorizationUnavailable
			}
			result.State = "NOT_COMMITTED"
		} else {
			invalid := intent.version != a.version || !f.TrustedAt.Before(intent.expires)
			if intent.kind == "ROTATE_CODE" {
				invalid = invalid || intent.rotation == nil || *intent.rotation != a.rotationGeneration || !hmac.Equal(a.activeRotation, id[:])
			}
			if intent.kind == "CREATE_PASSKEY" {
				policy, e := c.webAuthnPolicy()
				invalid = invalid || e != nil || challenge.state != "ACTIVE" || challenge.version == nil || *challenge.version != a.version || challenge.generation == nil || *challenge.generation != s.generation || challenge.authGeneration != int64(f.Generation) || !hmac.Equal(challenge.policy, policy[:]) || !f.TrustedAt.Before(challenge.expires)
			}
			if invalid {
				if _, e := tx.Exec(ctx, `UPDATE c_auth.credential_change_intents SET state='EXPIRED',new_recovery_digest=NULL,target_credential_id=NULL,challenge_id=NULL,terminal_at=$2 WHERE intent_id=$1 AND state='ACTIVE'`, id[:], f.TrustedAt); e != nil {
					return e
				}
				if intent.kind == "CREATE_PASSKEY" {
					if _, e := tx.Exec(ctx, `UPDATE c_auth.auth_challenges SET state='EXPIRED',nonce=NULL,terminal_at=$2 WHERE challenge_id=$1 AND state='ACTIVE'`, id[:], f.TrustedAt); e != nil {
						return e
					}
				}
				if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET active_rotation_intent_id=NULL WHERE account_id=$1 AND active_rotation_intent_id=$2`, a.account, id[:]); e != nil {
					return e
				}
				result.State = "NOT_COMMITTED"
			} else {
				result.State = "PENDING"
			}
		}
		var e error
		result.SessionExpiresAt, e = s.renew(ctx, tx, f.TrustedAt)
		return e
	})
	if err != nil {
		return CredentialChangeResult{}, err
	}
	if outcomeErr != nil {
		return CredentialChangeResult{}, outcomeErr
	}
	return result, nil
}
