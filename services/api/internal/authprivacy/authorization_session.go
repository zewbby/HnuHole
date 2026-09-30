package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

var ErrSessionInvalid = errors.New("session invalid")

// AuthorizeExistingSession is the isolated auth-read boundary for already
// issued lab bearers. Protected handlers must finish this gate check before
// returning private data; the production router has not been wired to it.
func (c *Community) AuthorizeExistingSession(ctx context.Context, bearer [32]byte) (uuid.UUID, error) {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return uuid.Nil, err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return uuid.Nil, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	digest := sha256.Sum256(bearer[:])
	var account uuid.UUID
	var expires time.Time
	err = tx.QueryRow(ctx, `SELECT s.account_id,s.expires_at FROM c_auth.sessions s
		JOIN c_auth.accounts a USING(account_id)
		WHERE s.token_digest=$1 AND s.revoked_at IS NULL AND a.state='ACTIVE'
		AND s.authorization_generation=$2 AND s.session_generation=a.session_generation
		FOR SHARE OF s,a`, digest[:], int64(decision.Generation)).Scan(&account, &expires)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, ErrSessionInvalid
	}
	if err != nil {
		return uuid.Nil, ErrAuthorizationUnavailable
	}
	if _, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if !final.TrustedAt.Before(expires) {
			return ErrSessionInvalid
		}
		return nil
	}); err != nil {
		return uuid.Nil, err
	}
	return account, nil
}
