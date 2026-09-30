package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"math"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

var (
	ErrAuthenticationFailed   = errors.New("authentication failed")
	ErrSessionInvalid         = errors.New("session invalid")
	ErrAccountUnavailable     = errors.New("account unavailable")
	ErrCredentialStateChanged = errors.New("credential state changed")
	ErrSessionReplaced        = errors.New("session replaced")
	ErrSessionCreatedReplay   = errors.New("session already created; login again")
)

const sessionLifetime = 30 * 24 * time.Hour
const renewalWindow = 7 * 24 * time.Hour

// PasswordVerifier owns the bounded Argon2id worker pool. The same worker is
// used with dummy material when the username does not exist.
type PasswordVerifier interface {
	VerifyPassword(context.Context, string, PasswordMaterial) (bool, error)
}

type SessionCreateRequest struct {
	Username       string
	Password       string
	InstallationID [16]byte
	IdempotencyKey [32]byte
}

type SessionCreateResult struct {
	AccountID    uuid.UUID
	SessionToken [32]byte
	ExpiresAt    time.Time
}

type SessionView struct {
	AccountID    uuid.UUID
	Username     string
	ExpiresAt    time.Time
	SignedInAt   time.Time
	LastReplaced *ReplacedDevice
}

type ReplacedDevice struct {
	SignedInAt time.Time
	ReplacedAt time.Time
}

var dummyPasswordMaterial = PasswordMaterial{
	Hash: [32]byte{1}, Salt: [16]byte{1}, ParametersVersion: 1,
}

// SessionRevocationSecret derives the logout-only capability from a bearer.
// It does not confer read access and may be retained after deleting the bearer.
func SessionRevocationSecret(token [32]byte) [32]byte {
	return digest("HNUHOLE/SESSION-REVOKE/V1", token[:])
}

func sessionReplay(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, key, mac [32]byte) (bool, error) {
	var operation, state string
	var result *string
	var storedMAC []byte
	err := q.QueryRow(ctx, `SELECT operation,state,request_hmac,result_code
		FROM c_auth.request_results WHERE key_digest=$1`, key[:]).Scan(&operation, &state, &storedMAC, &result)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if operation != "SESSION_CREATE" {
		return true, ErrConflict
	}
	if state == "EXPIRED" {
		return true, ErrExpired
	}
	if !hmac.Equal(storedMAC, mac[:]) {
		return true, ErrConflict
	}
	if result == nil || *result != "SESSION_CREATED" {
		return true, ErrConflict
	}
	return true, ErrSessionCreatedReplay
}

// CreateSession verifies a password outside SQL locks, then rechecks the exact
// verifier and credential version under the account lock. Its final Gate
// callback atomically replaces the one mobile session and persists a result
// that deliberately contains no token or revocation secret.
func (c *Community) CreateSession(ctx context.Context, request SessionCreateRequest, verifier PasswordVerifier) (SessionCreateResult, error) {
	var zero SessionCreateResult
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return zero, err
	}
	if verifier == nil || !usernamePattern.MatchString(request.Username) || request.Password == "" ||
		!utf8.ValidString(request.Password) || len(request.Password) > 2048 || utf8.RuneCountInString(request.Password) > 512 ||
		request.InstallationID == ([16]byte{}) || request.IdempotencyKey == ([32]byte{}) {
		return zero, ErrAuthenticationFailed
	}
	key := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", request.IdempotencyKey[:])
	mac := requestMAC(c.requestKey, []byte("SESSION_CREATE"), []byte(request.Username),
		[]byte(request.Password), request.InstallationID[:])
	if found, e := sessionReplay(ctx, c.pool, key, mac); found || e != nil {
		return zero, e
	}

	var account uuid.UUID
	var hash, salt []byte
	var version, params int64
	err = c.pool.QueryRow(ctx, `SELECT account_id,password_hash,password_salt,password_params_version,
		credential_version FROM c_auth.accounts WHERE username=$1`, request.Username).
		Scan(&account, &hash, &salt, &params, &version)
	material := dummyPasswordMaterial
	found := err == nil
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrAuthorizationUnavailable
	}
	if found {
		if len(hash) != 32 || len(salt) != 16 || params != 1 || version < 1 {
			return zero, ErrAuthorizationUnavailable
		}
		copy(material.Hash[:], hash)
		copy(material.Salt[:], salt)
		material.ParametersVersion = params
	}
	valid, err := verifier.VerifyPassword(ctx, request.Password, material)
	if err != nil {
		return zero, err
	}
	if !found || !valid {
		return zero, ErrAuthenticationFailed
	}

	tx, err := begin(ctx, c.pool)
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state, username string
	var lockedHash, lockedSalt []byte
	var lockedParams, lockedVersion, sessionGeneration, closureGeneration int64
	err = tx.QueryRow(ctx, `SELECT state,COALESCE(username,''),password_hash,password_salt,COALESCE(password_params_version,0),
		credential_version,session_generation,closure_generation FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).
		Scan(&state, &username, &lockedHash, &lockedSalt, &lockedParams, &lockedVersion, &sessionGeneration, &closureGeneration)
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	if username != request.Username || lockedParams != params || lockedVersion != version ||
		!hmac.Equal(lockedHash, hash) || !hmac.Equal(lockedSalt, salt) {
		return zero, ErrCredentialStateChanged
	}
	ban, err := lockRestriction(ctx, tx, account)
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	closure, err := lockPendingClosure(ctx, tx, account)
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	if (state != "ACTIVE" && state != "PENDING_CLOSE") || sessionGeneration == math.MaxInt64 ||
		(state == "PENDING_CLOSE" && (!closure.found || closure.generation != closureGeneration)) {
		return zero, ErrAccountUnavailable
	}
	var oldDigest, oldInstallation []byte
	var oldCreated, oldExpires time.Time
	var oldGeneration, oldAuthorizationGeneration int64
	err = tx.QueryRow(ctx, `SELECT token_digest,installation_id,created_at,expires_at,
		session_generation,authorization_generation FROM c_auth.sessions
		WHERE account_id=$1 AND revoked_at IS NULL FOR UPDATE`, account).
		Scan(&oldDigest, &oldInstallation, &oldCreated, &oldExpires, &oldGeneration, &oldAuthorizationGeneration)
	hadOld := err == nil
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrAuthorizationUnavailable
	}
	var recentAccount uuid.UUID
	err = tx.QueryRow(ctx, `SELECT account_id FROM c_auth.recent_device_replacement WHERE account_id=$1 FOR UPDATE`, account).Scan(&recentAccount)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrAuthorizationUnavailable
	}
	if replay, e := sessionReplay(ctx, tx, key, mac); e != nil && !replay {
		return zero, ErrAuthorizationUnavailable
	} else if replay {
		if _, gateErr := c.gate.CommitAuthorized(ctx, tx, decision.Generation); gateErr != nil {
			return zero, gateErr
		}
		return zero, e
	}
	claim, err := tx.Exec(ctx, `INSERT INTO c_auth.request_results
		(operation,key_digest,state,request_hmac,hmac_key_version,result_code,expires_at)
		VALUES('SESSION_CREATE',$1,'LIVE',$2,1,'SESSION_CREATED',$3)
		ON CONFLICT (key_digest) DO NOTHING`, key[:], mac[:], decision.TrustedAt.Add(8*24*time.Hour))
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	if claim.RowsAffected() == 0 {
		// A different account may have raced for the global key. The unique
		// index wait has completed; re-read its committed non-secret result.
		found, replayErr := sessionReplay(ctx, tx, key, mac)
		if !found || replayErr == nil {
			return zero, ErrAuthorizationUnavailable
		}
		if _, gateErr := c.gate.CommitAuthorized(ctx, tx, decision.Generation); gateErr != nil {
			return zero, gateErr
		}
		return zero, replayErr
	}
	token, err := random32()
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	tokenHash := sha256.Sum256(token[:])
	revoke := SessionRevocationSecret(token)
	revokeHash := digest("HNUHOLE/REVOKE-STORAGE/V1", revoke[:])
	var expires time.Time
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if bannedAt(ban, final.TrustedAt) {
			return ErrAccountUnavailable
		}
		if state == "PENDING_CLOSE" {
			if err := cancelPendingClosure(ctx, tx, account, closure, final.TrustedAt); err != nil {
				return err
			}
		}
		at := final.TrustedAt
		expires = at.Add(sessionLifetime)
		if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET session_generation=$2 WHERE account_id=$1`, account, sessionGeneration+1); e != nil {
			return e
		}
		if hadOld {
			reason := "EXPIRED"
			if oldAuthorizationGeneration != int64(final.Generation) || oldGeneration != sessionGeneration {
				reason = "RECOVERY"
			} else if at.Before(oldExpires) {
				reason = "REPLACED"
			}
			if _, e := tx.Exec(ctx, `UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason=$3
				WHERE token_digest=$1 AND revoked_at IS NULL`, oldDigest, at, reason); e != nil {
				return e
			}
			if reason == "REPLACED" {
				if _, e := tx.Exec(ctx, `INSERT INTO c_auth.recent_device_replacement
					(account_id,installation_id,signed_in_at,replaced_at) VALUES($1,$2,$3,$4)
					ON CONFLICT(account_id) DO UPDATE SET installation_id=$2,signed_in_at=$3,replaced_at=$4`,
					account, oldInstallation, oldCreated, at); e != nil {
					return e
				}
			}
		}
		if _, e := tx.Exec(ctx, `INSERT INTO c_auth.sessions
			(token_digest,revoke_digest,account_id,installation_id,session_generation,
			created_at,last_activity_at,expires_at,authorization_generation)
			VALUES($1,$2,$3,$4,$5,$6,$6,$7,$8)`, tokenHash[:], revokeHash[:], account,
			request.InstallationID[:], sessionGeneration+1, at, expires, int64(final.Generation)); e != nil {
			return e
		}
		return nil
	})
	if err != nil {
		return zero, err
	}
	return SessionCreateResult{AccountID: account, SessionToken: token, ExpiresAt: expires}, nil
}

type restriction struct {
	state string
	ends  *time.Time
}

func lockRestriction(ctx context.Context, tx pgx.Tx, account uuid.UUID) (restriction, error) {
	var result restriction
	err := tx.QueryRow(ctx, `SELECT ban_state,ban_ends_at FROM c_auth.account_restrictions
		WHERE account_id=$1 FOR UPDATE`, account).Scan(&result.state, &result.ends)
	return result, err
}

func bannedAt(r restriction, at time.Time) bool {
	return r.state == "BANNED" && (r.ends == nil || at.Before(*r.ends))
}

func (c *Community) sessionView(ctx context.Context, bearer [32]byte, withDevices bool) (SessionView, error) {
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

func (c *Community) GetCurrentSession(ctx context.Context, bearer [32]byte) (SessionView, error) {
	return c.sessionView(ctx, bearer, false)
}

func (c *Community) RenewCurrentSession(ctx context.Context, bearer [32]byte) (time.Time, error) {
	view, err := c.sessionView(ctx, bearer, false)
	return view.ExpiresAt, err
}

func (c *Community) GetDevices(ctx context.Context, bearer [32]byte) (SessionView, error) {
	return c.sessionView(ctx, bearer, true)
}

// RevokeSession accepts only the one-way revocation capability. It does not
// return account data and never revokes a later replacement session.
func (c *Community) RevokeSession(ctx context.Context, secret [32]byte) error {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return err
	}
	hash := digest("HNUHOLE/REVOKE-STORAGE/V1", secret[:])
	var account uuid.UUID
	err = c.pool.QueryRow(ctx, `SELECT account_id FROM c_auth.sessions WHERE revoke_digest=$1`, hash[:]).Scan(&account)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return ErrAuthorizationUnavailable
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	if account == uuid.Nil {
		_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation)
		return err
	}
	var currentGeneration int64
	if err = tx.QueryRow(ctx, `SELECT session_generation FROM c_auth.accounts
		WHERE account_id=$1 FOR UPDATE`, account).Scan(&currentGeneration); err != nil {
		return ErrAuthorizationUnavailable
	}
	if _, err = lockRestriction(ctx, tx, account); err != nil {
		return ErrAuthorizationUnavailable
	}
	var revoked *time.Time
	var generation, authGeneration int64
	err = tx.QueryRow(ctx, `SELECT revoked_at,session_generation,authorization_generation
		FROM c_auth.sessions WHERE revoke_digest=$1 AND account_id=$2 FOR UPDATE`, hash[:], account).
		Scan(&revoked, &generation, &authGeneration)
	if errors.Is(err, pgx.ErrNoRows) {
		_, gateErr := c.gate.CommitAuthorized(ctx, tx, decision.Generation)
		return gateErr
	}
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if revoked != nil {
			return nil
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason='LOGOUT'
			WHERE revoke_digest=$1 AND revoked_at IS NULL`, hash[:], final.TrustedAt); e != nil {
			return e
		}
		if generation == currentGeneration && authGeneration == int64(final.Generation) {
			if currentGeneration == math.MaxInt64 {
				return ErrAuthorizationUnavailable
			}
			_, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET session_generation=$2 WHERE account_id=$1`, account, currentGeneration+1)
			return e
		}
		return nil
	})
	return err
}

// CleanupSessionResults removes the request HMAC and all other LIVE metadata
// after the retry window, retaining the permanent operation/key tombstone.
// It is a bounded worker operation and cannot issue or renew a session.
func (c *Community) CleanupSessionResults(ctx context.Context, limit int) (int64, error) {
	if limit < 1 || limit > 1000 {
		return 0, ErrIntentInvalid
	}
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return 0, err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	keys, err := lockCleanupDigests(ctx, tx, `SELECT key_digest FROM c_auth.request_results
		WHERE operation='SESSION_CREATE' AND state='LIVE' AND expires_at<=$1
		ORDER BY key_digest LIMIT $2 FOR UPDATE SKIP LOCKED`, decision.TrustedAt, limit)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var cleaned int64
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		command, e := tx.Exec(ctx, `UPDATE c_auth.request_results SET state='EXPIRED',request_hmac=NULL,
			hmac_key_version=NULL,intent_id=NULL,reset_intent_id=NULL,result_code=NULL,expires_at=NULL
			WHERE key_digest=ANY($1::bytea[]) AND operation='SESSION_CREATE' AND state='LIVE'
			AND expires_at<=$2`, keys, final.TrustedAt)
		if e == nil {
			cleaned = command.RowsAffected()
		}
		return e
	})
	return cleaned, err
}

// CleanupOldSessions forgets bearer and revoke digests only after the final
// persisted server expiry plus seven days. Renewals move that expiry, so a
// stale client-side expiresAt cannot shorten this retention boundary.
func (c *Community) CleanupOldSessions(ctx context.Context, limit int) (int64, error) {
	if limit < 1 || limit > 1000 {
		return 0, ErrIntentInvalid
	}
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return 0, err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	tokens, err := lockCleanupDigests(ctx, tx, `SELECT token_digest FROM c_auth.sessions
		WHERE expires_at+interval '7 days'<=$1 ORDER BY token_digest LIMIT $2 FOR UPDATE SKIP LOCKED`, decision.TrustedAt, limit)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var cleaned int64
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		command, e := tx.Exec(ctx, `DELETE FROM c_auth.sessions WHERE token_digest=ANY($1::bytea[])
			AND expires_at+interval '7 days'<=$2`, tokens, final.TrustedAt)
		if e == nil {
			cleaned = command.RowsAffected()
		}
		return e
	})
	return cleaned, err
}

func (c *Community) CleanupRecentDevices(ctx context.Context, limit int) (int64, error) {
	if limit < 1 || limit > 1000 {
		return 0, ErrIntentInvalid
	}
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return 0, err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	rows, err := tx.Query(ctx, `SELECT account_id FROM c_auth.recent_device_replacement
		WHERE replaced_at+interval '30 days'<=$1 ORDER BY account_id LIMIT $2 FOR UPDATE SKIP LOCKED`, decision.TrustedAt, limit)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	accounts := make([]uuid.UUID, 0)
	for rows.Next() {
		var account uuid.UUID
		if err = rows.Scan(&account); err != nil {
			rows.Close()
			return 0, ErrAuthorizationUnavailable
		}
		accounts = append(accounts, account)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var cleaned int64
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		command, e := tx.Exec(ctx, `DELETE FROM c_auth.recent_device_replacement
			WHERE account_id=ANY($1::uuid[]) AND replaced_at+interval '30 days'<=$2`, accounts, final.TrustedAt)
		if e == nil {
			cleaned = command.RowsAffected()
		}
		return e
	})
	return cleaned, err
}

// Worker row locks precede the final Gate lock, matching request paths. The
// callback only mutates these already-locked candidates and rechecks time.
func lockCleanupDigests(ctx context.Context, tx pgx.Tx, sql string, args ...any) ([][]byte, error) {
	rows, err := tx.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	values := make([][]byte, 0)
	for rows.Next() {
		var value []byte
		if err = rows.Scan(&value); err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, rows.Err()
}

// Returning an account ID alone is not a substitute for final transaction
// authorization in a future protected business write.
func (c *Community) AuthorizeExistingSession(ctx context.Context, bearer [32]byte) (uuid.UUID, error) {
	view, err := c.GetCurrentSession(ctx, bearer)
	return view.AccountID, err
}
