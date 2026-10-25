package authprivacy

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (c *Community) resolveExpiredAdmission(ctx context.Context, tx pgx.Tx, account uuid.UUID, kind string, key [32]byte, at time.Time) error {
	if c.sharedRate == nil {
		return nil
	}
	var s rateSpec
	s.Account = account
	s.Kind = kind
	s.Key = key
	var fingerprint []byte
	var deadline time.Time
	var generation int64
	err := tx.QueryRow(ctx, `SELECT fingerprint,operation,COALESCE(dm_command_id::text,''),attempt,deadline,generation FROM c_rate_limit.admissions WHERE account_id=$1 AND business_kind=$2 AND key_digest=$3`, account, kind, key[:]).Scan(&fingerprint, &s.Operation, &s.DMID, &s.Attempt, &deadline, &generation)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	var currentGeneration int64
	if e := tx.QueryRow(ctx, `SELECT generation FROM c_rate_limit.namespace WHERE singleton_id=1`).Scan(&currentGeneration); e != nil {
		return ErrAuthorizationUnavailable
	}
	if at.Before(deadline) && generation == currentGeneration {
		return nil
	}
	copy(s.Fingerprint[:], fingerprint)
	return sealRateAdmission(ctx, tx, s, at)
}

func (c *Community) CleanupSharedAdmissions(ctx context.Context, limit int) (int, error) {
	if c.sharedRate == nil {
		return 0, nil
	}
	if limit < 1 || limit > 100 {
		return 0, ErrIntentInvalid
	}
	rows, err := c.pool.Query(ctx, `SELECT account_id,business_kind,key_digest FROM c_rate_limit.admissions WHERE deadline<=clock_timestamp() ORDER BY deadline,account_id LIMIT $1`, limit)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	type item struct {
		account uuid.UUID
		kind    string
		key     []byte
	}
	items := []item{}
	for rows.Next() {
		var i item
		if err = rows.Scan(&i.account, &i.kind, &i.key); err != nil {
			break
		}
		items = append(items, i)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	for index, i := range items {
		d, err := c.gate.Snapshot(ctx)
		if err != nil {
			return index, err
		}
		tx, err := begin(ctx, c.pool)
		if err != nil {
			return index, ErrAuthorizationUnavailable
		}
		var state string
		err = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, i.account).Scan(&state)
		if err == nil {
			var key [32]byte
			copy(key[:], i.key)
			_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(final AuthorizationDecision) error {
				return c.resolveExpiredAdmission(ctx, tx, i.account, i.kind, key, final.TrustedAt)
			})
		}
		_ = c.gate.Abort(ctx, tx)
		if err != nil {
			return index, err
		}
	}
	return len(items), nil
}
