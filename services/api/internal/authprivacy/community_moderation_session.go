package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"sort"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const moderationAccessLifetime = 24 * time.Hour

type ModerationAccessRequest struct{ Username, Password string }
type ModerationAccessResult struct {
	SessionToken [32]byte
	Subject      [32]byte
	ExpiresAt    time.Time
}

// The opaque local subject binds pending self-service material to this account
// incarnation. It is neither an account identifier nor an authorization token.
func (c *Community) moderationLocalSubject(account uuid.UUID) [32]byte {
	return requestMAC(c.requestKey, []byte("HNUHOLE/MODERATION-LOCAL-SUBJECT/V1"), account[:])
}

// CreateModerationAccessSession proves the existing private credential. It
// grants only access to one's handling notices and appeals, never a community
// session, and neither cancels pending closure nor replaces a mobile session.
func (c *Community) CreateModerationAccessSession(ctx context.Context, request ModerationAccessRequest, verifier PasswordVerifier) (ModerationAccessResult, error) {
	var result ModerationAccessResult
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return result, err
	}
	if verifier == nil || !usernamePattern.MatchString(request.Username) || request.Password == "" || !utf8.ValidString(request.Password) || len(request.Password) > 2048 || utf8.RuneCountInString(request.Password) > 512 {
		return result, ErrAuthenticationFailed
	}
	proof, err := c.proveUsernamePassword(ctx, request.Username, request.Password, verifier)
	if err != nil {
		return result, err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	a := credentialAccount{account: proof.account}
	err = tx.QueryRow(ctx, `SELECT state,COALESCE(username,''),credential_version,session_generation,COALESCE(password_params_version,0),password_hash,password_salt FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, proof.account).
		Scan(&a.state, &a.username, &a.version, &a.generation, &a.params, &a.hash, &a.salt)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	if a.username != request.Username || a.version != proof.version || a.params != proof.params || !hmac.Equal(a.hash, proof.hash) || !hmac.Equal(a.salt, proof.salt) {
		return result, ErrCredentialStateChanged
	}
	if _, err = lockRestriction(ctx, tx, proof.account); err != nil {
		return result, ErrAuthorizationUnavailable
	}
	if _, err = lockPendingClosure(ctx, tx, proof.account); err != nil {
		return result, ErrAuthorizationUnavailable
	}
	if err = drainLocks(ctx, tx, `SELECT token_digest FROM c_moderation.access_sessions WHERE account_id=$1 ORDER BY token_digest FOR UPDATE`, proof.account); err != nil {
		return result, ErrAuthorizationUnavailable
	}
	token, err := random32()
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	tokenHash := sha256.Sum256(token[:])
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(final AuthorizationDecision) error {
		if a.state != "ACTIVE" {
			return ErrAccountUnavailable
		}
		result.ExpiresAt = final.TrustedAt.Add(moderationAccessLifetime).UTC()
		if _, e := tx.Exec(ctx, `UPDATE c_moderation.access_sessions SET revoked_at=$2 WHERE account_id=$1 AND revoked_at IS NULL`, proof.account, final.TrustedAt); e != nil {
			return e
		}
		_, e := tx.Exec(ctx, `INSERT INTO c_moderation.access_sessions(token_digest,account_id,credential_version,session_generation,authorization_generation,expires_at) VALUES($1,$2,$3,$4,$5,$6)`, tokenHash[:], proof.account, a.version, a.generation, int64(final.Generation), result.ExpiresAt)
		return e
	})
	if err != nil {
		return ModerationAccessResult{}, err
	}
	result.SessionToken = token
	result.Subject = c.moderationLocalSubject(proof.account)
	return result, nil
}

// withModerationSession allows restricted credentials only on explicitly
// selected self-service handlers. Reports and every management handler pass
// false; the ordinary credentialSession validator remains unchanged.
func (c *Community) withModerationSession(ctx context.Context, bearer [32]byte, allowRestricted bool, action func(pgx.Tx, uuid.UUID, AuthorizationDecision) (any, error)) (PostResponse, error) {
	return c.withModerationSessionPrepared(ctx, bearer, allowRestricted, uuid.Nil, nil, action)
}

// Management locks both accounts in stable order before the restriction,
// session, role and resource locks. prepare must run before the final Gate;
// action performs all externally visible effects inside that final transaction.
func (c *Community) withModerationAccountsSession(ctx context.Context, bearer [32]byte, target uuid.UUID, prepare func(pgx.Tx, uuid.UUID) error, action func(pgx.Tx, uuid.UUID, AuthorizationDecision) (any, error)) (PostResponse, error) {
	return c.withModerationSessionPrepared(ctx, bearer, false, target, prepare, action)
}

func (c *Community) withModerationSessionPrepared(ctx context.Context, bearer [32]byte, allowRestricted bool, target uuid.UUID, prepare func(pgx.Tx, uuid.UUID) error, action func(pgx.Tx, uuid.UUID, AuthorizationDecision) (any, error)) (PostResponse, error) {
	var result PostResponse
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return result, err
	}
	token := sha256.Sum256(bearer[:])
	var account uuid.UUID
	err = c.pool.QueryRow(ctx, `SELECT account_id FROM c_auth.sessions WHERE token_digest=$1`, token[:]).Scan(&account)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return result, ErrAuthorizationUnavailable
	}
	restricted := false
	if account == uuid.Nil && allowRestricted {
		err = c.pool.QueryRow(ctx, `SELECT account_id FROM c_moderation.access_sessions WHERE token_digest=$1`, token[:]).Scan(&account)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return result, ErrAuthorizationUnavailable
		}
		restricted = account != uuid.Nil
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	accounts := make(map[uuid.UUID]credentialAccount)
	if account != uuid.Nil {
		ids := []uuid.UUID{account}
		if target != uuid.Nil && target != account {
			ids = append(ids, target)
		}
		sort.Slice(ids, func(i, j int) bool { return ids[i].String() < ids[j].String() })
		for _, id := range ids {
			a := credentialAccount{account: id}
			if err = tx.QueryRow(ctx, `SELECT state,credential_version,session_generation FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, id).Scan(&a.state, &a.version, &a.generation); err != nil {
				return result, ErrAuthorizationUnavailable
			}
			accounts[id] = a
		}
		for _, id := range ids {
			a := accounts[id]
			if a.ban, err = lockRestriction(ctx, tx, id); err != nil {
				return result, ErrAuthorizationUnavailable
			}
			accounts[id] = a
		}
	}
	a := accounts[account]
	s := credentialSession{token: token}
	var accessVersion int64
	if account != uuid.Nil {
		if restricted {
			err = tx.QueryRow(ctx, `SELECT credential_version,session_generation,authorization_generation,expires_at,revoked_at FROM c_moderation.access_sessions WHERE token_digest=$1 AND account_id=$2 FOR UPDATE`, token[:], account).
				Scan(&accessVersion, &s.generation, &s.authGeneration, &s.expires, &s.revoked)
		} else {
			s, err = lockCredentialSession(ctx, tx, a, token)
		}
		if err != nil && !errors.Is(err, pgx.ErrNoRows) && !errors.Is(err, ErrSessionInvalid) {
			return result, ErrAuthorizationUnavailable
		}
	}
	validate := func(final AuthorizationDecision) error {
		if account == uuid.Nil {
			return ErrSessionInvalid
		}
		if !restricted {
			return s.validate(a, final)
		}
		if !allowRestricted || a.state != "ACTIVE" || accessVersion != a.version || s.generation != a.generation || s.authGeneration != int64(final.Generation) || s.revoked != nil || !final.TrustedAt.Before(s.expires) {
			return ErrSessionInvalid
		}
		return nil
	}
	// Another request may renew this session between Snapshot and our account
	// lock. Preliminary checks validate its authority, without treating that
	// normal queue wait as clock rollback. The original lastActivity remains in
	// s and is checked strictly against final trusted time before any action.
	// Mandatory role/resource preparation must never be skipped.
	if restricted {
		err = validate(d)
	} else {
		preliminary := s
		preliminary.lastActivity = time.Time{}
		err = preliminary.validate(a, d)
	}
	if err != nil {
		return result, err
	}
	if prepare != nil {
		if err = prepare(tx, account); err != nil {
			return result, err
		}
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(final AuthorizationDecision) error {
		if e := validate(final); e != nil {
			return e
		}
		result.ServerTime = final.TrustedAt.UTC()
		if action != nil {
			value, e := action(tx, account, final)
			if e != nil {
				return e
			}
			result.Value = value
		}
		result.ExpiresAt = s.expires.UTC()
		if !restricted {
			var e error
			result.ExpiresAt, e = s.renew(ctx, tx, final.TrustedAt)
			return e
		}
		return nil
	})
	if err != nil {
		return PostResponse{}, err
	}
	result.ExpiresAt = result.ExpiresAt.UTC()
	return result, nil
}

func (c *Community) RevokeModerationAccessSession(ctx context.Context, bearer [32]byte) error {
	_, err := c.withModerationSession(ctx, bearer, true, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) (any, error) {
		token := sha256.Sum256(bearer[:])
		command, e := tx.Exec(ctx, `UPDATE c_moderation.access_sessions SET revoked_at=$3 WHERE token_digest=$1 AND account_id=$2 AND revoked_at IS NULL`, token[:], account, final.TrustedAt)
		if e == nil && command.RowsAffected() != 1 {
			return nil, ErrSessionInvalid
		}
		return nil, e
	})
	return err
}

// Call only inside an action already authorized by withModerationSession. This
// scope check lets self-service lists omit identity/community notifications for
// a restricted capability without treating query failures as ordinary access.
func moderationAccessOnly(ctx context.Context, tx pgx.Tx, bearer [32]byte) (bool, error) {
	token := sha256.Sum256(bearer[:])
	var restricted bool
	err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_moderation.access_sessions WHERE token_digest=$1 AND revoked_at IS NULL)`, token[:]).Scan(&restricted)
	return restricted, err
}
