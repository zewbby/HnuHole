package authprivacy

import (
    "context"
    "crypto/sha256"
    "errors"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v5"
    "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/channels"
)

// ChannelDirectory contains only the catalog and the same session's committed
// server expiry. Account identifiers and authentication generations stay private.
type ChannelDirectory struct {
    Channels []channels.Channel
    ExpiresAt time.Time
}

var ErrChannelDirectoryUnavailable = errors.New("channel directory unavailable")

// ListAuthorizedChannels reads the complete business catalog inside the same
// authorization transaction as session validation and threshold renewal.
func (c *Community) ListAuthorizedChannels(ctx context.Context, bearer [32]byte) (ChannelDirectory, error) {
    var items []channels.Channel
    view, err := c.withAuthorizedSession(ctx, bearer, false, func(query channels.Queryer) error {
        var err error
        items, err = channels.NewService(channels.NewPostgresRepository(query)).List(ctx)
        if errors.Is(err, channels.ErrInvalidCatalog) { return ErrChannelDirectoryUnavailable }
        if err != nil { return ErrAuthorizationUnavailable }
        return nil
    })
    if err != nil { return ChannelDirectory{}, err }
    return ChannelDirectory{Channels: items, ExpiresAt: view.ExpiresAt}, nil
}

func (c *Community) withAuthorizedSession(ctx context.Context, bearer [32]byte, withDevices bool, read func(channels.Queryer) error) (SessionView, error) {
	var result SessionView
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return result, err
	}
	tokenHash := sha256.Sum256(bearer[:])
	var account uuid.UUID
	err = c.pool.QueryRow(ctx, `SELECT account_id FROM c_auth.sessions WHERE token_digest=$1`, tokenHash[:]).Scan(&account)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return result, ErrAuthorizationUnavailable
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	if account == uuid.Nil {
		if _, e := c.gate.CommitAuthorized(ctx, tx, decision.Generation); e != nil {
			return result, e
		}
		return result, ErrSessionInvalid
	}
	var state string
	var username *string
	var currentGeneration int64
	err = tx.QueryRow(ctx, `SELECT state,username,session_generation FROM c_auth.accounts
		WHERE account_id=$1 FOR UPDATE`, account).Scan(&state, &username, &currentGeneration)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	ban, err := lockRestriction(ctx, tx, account)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	var generation, authGeneration int64
	var created, lastActivity, expires time.Time
	var revoked *time.Time
	var reason *string
	err = tx.QueryRow(ctx, `SELECT session_generation,authorization_generation,created_at,last_activity_at,
		expires_at,revoked_at,revocation_reason FROM c_auth.sessions
		WHERE token_digest=$1 AND account_id=$2 FOR UPDATE`, tokenHash[:], account).
		Scan(&generation, &authGeneration, &created, &lastActivity, &expires, &revoked, &reason)
	if errors.Is(err, pgx.ErrNoRows) {
		if _, e := c.gate.CommitAuthorized(ctx, tx, decision.Generation); e != nil {
			return result, e
		}
		return SessionView{}, ErrSessionInvalid
	}
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	if withDevices {
		var recent ReplacedDevice
		err = tx.QueryRow(ctx, `SELECT signed_in_at,replaced_at FROM c_auth.recent_device_replacement
			WHERE account_id=$1`, account).Scan(&recent.SignedInAt, &recent.ReplacedAt)
		if err == nil {
			result.LastReplaced = &recent
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return SessionView{}, ErrAuthorizationUnavailable
		}
	}
	result.AccountID, result.SignedInAt = account, created
	if username != nil {
		result.Username = *username
	}
	// The callback receives query access to this transaction. It builds only an
	// in-memory result; final authority and renewal remain owned by this method.
	// Definitively revoked generations do not need a catalog read. The final
	// check below still adjudicates their error after locking the Gate.
	if read != nil && state == "ACTIVE" && revoked == nil && generation == currentGeneration && authGeneration == int64(decision.Generation) {
		if err := read(tx); err != nil {
			return SessionView{}, err
		}
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if authGeneration != int64(final.Generation) || state != "ACTIVE" ||
			bannedAt(ban, final.TrustedAt) || !final.TrustedAt.Before(expires) ||
			generation != currentGeneration || revoked != nil {
			if authGeneration == int64(final.Generation) && reason != nil && *reason == "REPLACED" &&
				generation < currentGeneration && state == "ACTIVE" {
				return ErrSessionReplaced
			}
			return ErrSessionInvalid
		}
		result.ExpiresAt = expires
		if expires.Sub(final.TrustedAt) <= renewalWindow {
			result.ExpiresAt = final.TrustedAt.Add(sessionLifetime)
		}
		if final.TrustedAt.Before(lastActivity) {
			return ErrAuthorizationUnavailable
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.sessions SET last_activity_at=$2,expires_at=$3
			WHERE token_digest=$1`, tokenHash[:], final.TrustedAt, result.ExpiresAt); e != nil {
			return e
		}
		if result.LastReplaced != nil && !final.TrustedAt.Before(result.LastReplaced.ReplacedAt.Add(30*24*time.Hour)) {
			result.LastReplaced = nil
		}
		return nil
	})
	if err != nil {
		return SessionView{}, err
	}
	return result, nil
}
