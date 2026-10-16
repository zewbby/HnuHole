package authprivacy

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// CleanupCredentialState bounds scans, locks candidates before the final Gate,
// clears expired authority, and keeps permanent global result tombstones.
func (c *Community) CleanupCredentialState(ctx context.Context, limit int) (int64, error) {
	if limit < 1 || limit > 1000 {
		return 0, ErrIntentInvalid
	}
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return 0, err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	keys, err := lockCleanupDigests(ctx, tx, `SELECT key_digest FROM c_auth.request_results WHERE operation IN ('ROTATE_CODE','CREATE_PASSKEY','REMOVE_PASSKEY') AND state='LIVE' AND expires_at<=$1 ORDER BY key_digest LIMIT $2 FOR UPDATE SKIP LOCKED`, d.TrustedAt, limit)
	if err != nil {
		c.gate.Abort(ctx, tx)
		return 0, ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		_, e := tx.Exec(ctx, `UPDATE c_auth.request_results SET state='EXPIRED',request_hmac=NULL,hmac_key_version=NULL,intent_id=NULL,reset_intent_id=NULL,credential_change_id=NULL,auth_challenge_id=NULL,result_code=NULL,expires_at=NULL WHERE key_digest=ANY($1::bytea[]) AND state='LIVE' AND expires_at<=$2`, keys, f.TrustedAt)
		return e
	})
	c.gate.Abort(ctx, tx)
	if err != nil {
		return 0, err
	}
	rows, err := c.pool.Query(ctx, `SELECT source,id,account_id FROM (
 SELECT 'INTENT'::text source,intent_id id,account_id FROM c_auth.credential_change_intents WHERE (state='ACTIVE' AND (expires_at<=$1 OR authorization_generation<>$3)) OR (state<>'ACTIVE' AND terminal_at<=$1::timestamptz-interval '7 days')
 UNION ALL SELECT 'CHALLENGE',challenge_id,account_id FROM c_auth.auth_challenges WHERE (state='ACTIVE' AND (expires_at<=$1 OR authorization_generation<>$3)) OR (state<>'ACTIVE' AND terminal_at<=$1::timestamptz-interval '7 days')
 ) candidates ORDER BY account_id NULLS LAST,source,id LIMIT $2`, d.TrustedAt, limit, int64(d.Generation))
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	type candidate struct {
		source  string
		id      []byte
		account *uuid.UUID
	}
	items := make([]candidate, 0)
	for rows.Next() {
		var item candidate
		if err = rows.Scan(&item.source, &item.id, &item.account); err != nil {
			break
		}
		items = append(items, item)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var count int64
	for _, item := range items {
		changed, e := c.cleanupCredentialCandidate(ctx, d, item.source, item.id, item.account)
		if e != nil {
			return count, e
		}
		count += changed
	}
	if err = c.cleanupRecoveryEvents(ctx, d, limit); err != nil {
		return count, err
	}
	return count, nil
}
func (c *Community) cleanupCredentialCandidate(ctx context.Context, d AuthorizationDecision, source string, id []byte, account *uuid.UUID) (int64, error) {
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	if account != nil {
		var locked uuid.UUID
		err = tx.QueryRow(ctx, `SELECT account_id FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE SKIP LOCKED`, *account).Scan(&locked)
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, nil
		}
		if err != nil {
			return 0, ErrAuthorizationUnavailable
		}
		if _, err = lockRestriction(ctx, tx, locked); err != nil {
			return 0, ErrAuthorizationUnavailable
		}
	}
	table, column, resultColumn := "c_auth.credential_change_intents", "intent_id", "credential_change_id"
	if source == "CHALLENGE" {
		table, column, resultColumn = "c_auth.auth_challenges", "challenge_id", "auth_challenge_id"
	}
	var state string
	err = tx.QueryRow(ctx, `SELECT state FROM `+table+` WHERE `+column+`=$1 FOR UPDATE SKIP LOCKED`, id).Scan(&state)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	if err = drainLocks(ctx, tx, `SELECT key_digest FROM c_auth.request_results WHERE `+resultColumn+`=$1 ORDER BY key_digest FOR UPDATE`, id); err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var count int64
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		if state == "ACTIVE" {
			clearFields := "new_recovery_digest=NULL,target_credential_id=NULL,challenge_id=NULL"
			if source == "CHALLENGE" {
				clearFields = "nonce=NULL"
			}
			tag, e := tx.Exec(ctx, `UPDATE `+table+` SET state='EXPIRED',`+clearFields+`,terminal_at=$2 WHERE `+column+`=$1 AND state='ACTIVE' AND (expires_at<=$2 OR authorization_generation<>$3)`, id, f.TrustedAt, int64(f.Generation))
			if e != nil {
				return e
			}
			count += tag.RowsAffected()
			if source == "INTENT" && account != nil {
				if _, e = tx.Exec(ctx, `UPDATE c_auth.accounts SET active_rotation_intent_id=NULL WHERE account_id=$1 AND active_rotation_intent_id=$2`, *account, id); e != nil {
					return e
				}
			}
		} else {
			extra := ""
			if source == "CHALLENGE" {
				extra = ` AND NOT EXISTS(SELECT 1 FROM c_auth.credential_change_intents WHERE challenge_id=$1)`
			}
			tag, e := tx.Exec(ctx, `DELETE FROM `+table+` WHERE `+column+`=$1 AND state<>'ACTIVE' AND terminal_at<=$2::timestamptz-interval '7 days' AND NOT EXISTS(SELECT 1 FROM c_auth.request_results WHERE `+resultColumn+`=$1)`+extra, id, f.TrustedAt)
			if e != nil {
				return e
			}
			count += tag.RowsAffected()
		}
		return nil
	})
	return count, err
}
