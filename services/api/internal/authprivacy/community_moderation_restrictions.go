package authprivacy

import (
	"context"
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// A moderation caller must prepare these locks before acquiring the final Gate.
// Applying the punishment then shares the case decision's transaction, so neither
// an audit result nor an account restriction can commit on its own.
type moderationRestrictionState struct {
	account                                uuid.UUID
	state                                  string
	version, generation, closureGeneration int64
	closure                                pendingClosure
}

func (c *Community) lockModerationRestrictionTx(ctx context.Context, tx pgx.Tx, account uuid.UUID, action string) (moderationRestrictionState, error) {
	s := moderationRestrictionState{account: account}
	if account == uuid.Nil || (action != "BAN" && action != "MUTE" && action != "UNBAN" && action != "UNMUTE") {
		return s, ErrIntentInvalid
	}
	err := tx.QueryRow(ctx, `SELECT state,session_generation,closure_generation FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).
		Scan(&s.state, &s.generation, &s.closureGeneration)
	if errors.Is(err, pgx.ErrNoRows) {
		return s, ErrAccountUnavailable
	}
	if err != nil {
		return s, ErrAuthorizationUnavailable
	}
	if _, err = lockRestriction(ctx, tx, account); err != nil {
		return s, ErrAuthorizationUnavailable
	}
	if err = tx.QueryRow(ctx, `SELECT version FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&s.version); err != nil {
		return s, ErrAuthorizationUnavailable
	}
	s.closure, err = lockPendingClosure(ctx, tx, account)
	if err != nil {
		return s, ErrAuthorizationUnavailable
	}
	if action == "BAN" {
		if err = drainLocks(ctx, tx, `SELECT token_digest FROM c_auth.sessions WHERE account_id=$1 ORDER BY token_digest FOR UPDATE`, account); err != nil {
			return s, ErrAuthorizationUnavailable
		}
	}
	return s, nil
}

// Only invoke inside CommitAuthorized after lockModerationRestrictionTx. The
// caller enforces role, allowed duration and concurrent sanction aggregation.
func (c *Community) applyModerationRestrictionTx(ctx context.Context, tx pgx.Tx, s moderationRestrictionState, action string, endsAt *time.Time, at time.Time) error {
	if s.account == uuid.Nil || (action != "BAN" && action != "MUTE" && action != "UNBAN" && action != "UNMUTE") {
		return ErrIntentInvalid
	}
	if s.state == "CLOSED" {
		return ErrAccountUnavailable
	}
	if s.version == math.MaxInt64 || (action == "BAN" && s.generation == math.MaxInt64) {
		return ErrAuthorizationUnavailable
	}
	if (action == "BAN" || action == "MUTE") && endsAt != nil && !endsAt.After(at) {
		return ErrIntentInvalid
	}
	if action == "BAN" && s.state == "PENDING_CLOSE" && (!s.closure.found || s.closure.generation != s.closureGeneration) {
		return ErrAccountUnavailable
	}
	switch action {
	case "MUTE", "BAN":
		if err := c.stopPostPublication(ctx, tx, s.account, action, at); err != nil {
			return err
		}
	}
	var err error
	switch action {
	case "MUTE":
		_, err = tx.Exec(ctx, `UPDATE c_auth.account_restrictions SET mute_state='MUTED',mute_ends_at=$2,version=version+1 WHERE account_id=$1`, s.account, endsAt)
	case "BAN":
		_, err = tx.Exec(ctx, `UPDATE c_auth.account_restrictions SET ban_state='BANNED',ban_ends_at=$2,version=version+1 WHERE account_id=$1`, s.account, endsAt)
		if err == nil {
			_, err = tx.Exec(ctx, `UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason='BAN' WHERE account_id=$1 AND revoked_at IS NULL`, s.account, at)
		}
		if err == nil {
			_, err = tx.Exec(ctx, `UPDATE c_auth.accounts SET session_generation=session_generation+1 WHERE account_id=$1`, s.account)
		}
		if err == nil && s.state == "PENDING_CLOSE" && at.Before(s.closure.dueAt) {
			err = cancelPendingClosure(ctx, tx, s.account, s.closure, at)
		}
	case "UNMUTE":
		_, err = tx.Exec(ctx, `UPDATE c_auth.account_restrictions SET mute_state='NONE',mute_ends_at=NULL,version=version+1 WHERE account_id=$1`, s.account)
	case "UNBAN":
		_, err = tx.Exec(ctx, `UPDATE c_auth.account_restrictions SET ban_state='NONE',ban_ends_at=NULL,version=version+1 WHERE account_id=$1`, s.account)
	}
	return err
}
