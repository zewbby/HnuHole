package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"encoding/base32"
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

var (
	ErrRecoveryProofInvalid = errors.New("recovery proof invalid")
	ErrResetIntentInvalid   = errors.New("reset intent invalid")
	ErrResetIntentExpired   = errors.New("reset intent expired")
	ErrResetResultNotFound  = errors.New("reset result not found")
)

type PasswordProcessor interface {
	PreparePassword(context.Context, string, string) (PasswordMaterial, error)
}

type PasswordResetIntent struct {
	ID              [32]byte
	ExpiresAt       time.Time
	Username        string
	NewRecoveryCode string
}

type PasswordResetRequest struct {
	IntentID                    [32]byte
	IdempotencyKey              [32]byte
	NewPassword                 string
	NewRecoveryCodeConfirmation string
}

// Recovery proofs can reset a banned account but never lift its restriction.
// Only an explicit successful login may cancel a still-pending closure.
func recoveryAccountAllowed(state string, closure pendingClosure, at time.Time) bool {
	return state == "ACTIVE" || state == "PENDING_CLOSE" && closure.found && at.Before(closure.dueAt)
}

func generateRecoveryCode() (string, [32]byte, error) {
	var secret [16]byte
	if _, err := rand.Read(secret[:]); err != nil {
		return "", [32]byte{}, err
	}
	defer clear(secret[:])
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(secret[:]), digest("HNUHOLE/RECOVERY/V1", secret[:]), nil
}

// CreateRecoveryCodeResetIntent keeps the old code usable until the final
// reset. A replacement intent invalidates the previous intent atomically;
// neither this response nor a lost response creates a normal session.
func (c *Community) CreateRecoveryCodeResetIntent(ctx context.Context, code string) (PasswordResetIntent, error) {
	var zero PasswordResetIntent
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return zero, err
	}
	proof, err := recoveryDigest(code)
	if err != nil {
		return zero, ErrRecoveryProofInvalid
	}
	var account uuid.UUID
	var version int64
	err = c.pool.QueryRow(ctx, `SELECT a.account_id,a.credential_version FROM c_auth.accounts a
		JOIN c_auth.recovery_codes r USING(account_id) WHERE r.code_digest=$1`, proof[:]).Scan(&account, &version)
	if errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrRecoveryProofInvalid
	}
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	id, err := random32()
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	newCode, newDigest, err := generateRecoveryCode()
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state, username string
	var lockedVersion, generation int64
	err = tx.QueryRow(ctx, `SELECT state,COALESCE(username,''),credential_version,reset_generation
		FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&state, &username, &lockedVersion, &generation)
	if errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrRecoveryProofInvalid
	}
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	if _, err = lockRestriction(ctx, tx, account); err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	var closure pendingClosure
	if state == "PENDING_CLOSE" {
		closure, err = lockPendingClosure(ctx, tx, account)
		if err != nil {
			return zero, ErrAuthorizationUnavailable
		}
	}
	if err = lockRecoveryRows(ctx, tx, account, false); err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	var current []byte
	err = tx.QueryRow(ctx, `SELECT code_digest FROM c_auth.recovery_codes WHERE account_id=$1 FOR UPDATE`, account).Scan(&current)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrAuthorizationUnavailable
	}
	if lockedVersion != version || !hmac.Equal(current, proof[:]) {
		return zero, ErrRecoveryProofInvalid
	}
	if generation == math.MaxInt64 {
		return zero, ErrAuthorizationUnavailable
	}
	var expires time.Time
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if !recoveryAccountAllowed(state, closure, final.TrustedAt) {
			return ErrRecoveryProofInvalid
		}
		expires = final.TrustedAt.Add(10 * time.Minute)
		if _, e := tx.Exec(ctx, `UPDATE c_auth.reset_intents SET state='ABANDONED',new_recovery_digest=NULL,terminal_at=$2
			WHERE account_id=$1 AND state='ACTIVE'`, account, final.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `INSERT INTO c_auth.reset_intents
			(intent_id,account_id,credential_version,reset_generation,authorization_generation,state,new_recovery_digest,created_at,expires_at)
			VALUES($1,$2,$3,$4,$5,'ACTIVE',$6,$7,$8)`, id[:], account, version, generation+1, int64(final.Generation), newDigest[:], final.TrustedAt, expires); e != nil {
			return e
		}
		_, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET reset_generation=$2,active_reset_intent_id=$3 WHERE account_id=$1`, account, generation+1, id[:])
		return e
	})
	if err != nil {
		return zero, err
	}
	return PasswordResetIntent{ID: id, ExpiresAt: expires, Username: username, NewRecoveryCode: newCode}, nil
}

// Existing-account lock order is account, restriction, pending closure,
// reset intents, recovery code/Passkeys, sessions, then request result.
func lockRecoveryRows(ctx context.Context, tx pgx.Tx, account uuid.UUID, all bool) error {
	queries := []string{`SELECT intent_id FROM c_auth.reset_intents WHERE account_id=$1 AND state='ACTIVE' ORDER BY intent_id FOR UPDATE`}
	if all {
		queries = append(queries, `SELECT code_digest FROM c_auth.recovery_codes WHERE account_id=$1 FOR UPDATE`,
			`SELECT credential_id FROM c_auth.passkeys WHERE account_id=$1 ORDER BY credential_id FOR UPDATE`,
			`SELECT token_digest FROM c_auth.sessions WHERE account_id=$1 AND revoked_at IS NULL ORDER BY token_digest FOR UPDATE`)
	}
	for _, query := range queries {
		rows, err := tx.Query(ctx, query, account)
		if err != nil {
			return err
		}
		for rows.Next() {
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return err
		}
	}
	return nil
}

type resetIntentRow struct {
	account                                      uuid.UUID
	state                                        string
	version, generation, authorizationGeneration int64
	digest                                       []byte
	expires                                      time.Time
}

func readResetIntent(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, id [32]byte, lock bool) (resetIntentRow, error) {
	var row resetIntentRow
	query := `SELECT account_id,state,credential_version,reset_generation,authorization_generation,new_recovery_digest,expires_at
		FROM c_auth.reset_intents WHERE intent_id=$1`
	if lock {
		query += " FOR UPDATE"
	}
	err := q.QueryRow(ctx, query, id[:]).Scan(&row.account, &row.state, &row.version, &row.generation, &row.authorizationGeneration, &row.digest, &row.expires)
	return row, err
}

func readResetReplay(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, key, mac, id [32]byte, lock bool) (bool, error) {
	query := `SELECT operation,state,request_hmac,reset_intent_id,result_code FROM c_auth.request_results WHERE key_digest=$1`
	if lock {
		query += " FOR UPDATE"
	}
	var operation, state string
	var storedMAC, storedID []byte
	var result *string
	err := q.QueryRow(ctx, query, key[:]).Scan(&operation, &state, &storedMAC, &storedID, &result)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, ErrAuthorizationUnavailable
	}
	if state == "EXPIRED" {
		return true, ErrExpired
	}
	if operation != "PASSWORD_RESET" || !hmac.Equal(storedMAC, mac[:]) || !hmac.Equal(storedID, id[:]) {
		return true, ErrConflict
	}
	if result == nil || *result != "COMMITTED" {
		return true, ErrResetIntentInvalid
	}
	return true, nil
}

// CommitPasswordReset never runs the password KDF under account locks and
// carries both the original intent proof version and Gate generation across
// that work. Idempotent replays do not rerun KDF or return recovery material.
func (c *Community) CommitPasswordReset(ctx context.Context, request PasswordResetRequest, processor PasswordProcessor) error {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return err
	}
	if processor == nil || request.IntentID == ([32]byte{}) || request.IdempotencyKey == ([32]byte{}) {
		return ErrResetIntentInvalid
	}
	confirmation, err := recoveryDigest(request.NewRecoveryCodeConfirmation)
	if err != nil {
		return ErrResetIntentInvalid
	}
	key := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", request.IdempotencyKey[:])
	mac := requestMAC(c.requestKey, []byte("PASSWORD_RESET"), request.IntentID[:], []byte(request.NewPassword), confirmation[:])
	if found, e := readResetReplay(ctx, c.pool, key, mac, request.IntentID, false); found || e != nil {
		if !found {
			return e
		}
		tx, txErr := begin(ctx, c.pool)
		if txErr != nil {
			return ErrAuthorizationUnavailable
		}
		defer c.gate.Abort(ctx, tx)
		found, e = readResetReplay(ctx, tx, key, mac, request.IntentID, true)
		if !found {
			return ErrAuthorizationUnavailable
		}
		if _, gateErr := c.gate.CommitAuthorized(ctx, tx, decision.Generation); gateErr != nil {
			return gateErr
		}
		return e
	}
	original, err := readResetIntent(ctx, c.pool, request.IntentID, false)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrResetIntentInvalid
	}
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	if original.authorizationGeneration != int64(decision.Generation) {
		return ErrResetIntentInvalid
	}
	var username string
	err = c.pool.QueryRow(ctx, `SELECT COALESCE(username,'') FROM c_auth.accounts WHERE account_id=$1`, original.account).Scan(&username)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	material, err := processor.PreparePassword(ctx, request.NewPassword, username)
	if err != nil {
		return err
	}
	if material.ParametersVersion != 1 || material.Hash == ([32]byte{}) || material.Salt == ([16]byte{}) {
		return ErrPasswordPolicy
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state string
	var version, generation, sessionGeneration int64
	var active []byte
	err = tx.QueryRow(ctx, `SELECT state,credential_version,reset_generation,session_generation,active_reset_intent_id
		FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, original.account).Scan(&state, &version, &generation, &sessionGeneration, &active)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	if _, err = lockRestriction(ctx, tx, original.account); err != nil {
		return ErrAuthorizationUnavailable
	}
	var closure pendingClosure
	if state == "PENDING_CLOSE" {
		closure, err = lockPendingClosure(ctx, tx, original.account)
		if err != nil {
			return ErrAuthorizationUnavailable
		}
	}
	// Lock the requested and any newer active intent together in byte order.
	// The account lock prevents their set changing underneath this query.
	intentLocks, err := tx.Query(ctx, `SELECT intent_id FROM c_auth.reset_intents
		WHERE account_id=$1 AND (intent_id=$2 OR state='ACTIVE') ORDER BY intent_id FOR UPDATE`, original.account, request.IntentID[:])
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	for intentLocks.Next() {
	}
	err = intentLocks.Err()
	intentLocks.Close()
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	locked, err := readResetIntent(ctx, tx, request.IntentID, true)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrResetIntentInvalid
	}
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	if err = lockRecoveryRows(ctx, tx, original.account, true); err != nil {
		return ErrAuthorizationUnavailable
	}
	var currentRecovery []byte
	if err = tx.QueryRow(ctx, `SELECT code_digest FROM c_auth.recovery_codes WHERE account_id=$1`, original.account).Scan(&currentRecovery); err != nil || len(currentRecovery) != 32 {
		return ErrAuthorizationUnavailable
	}
	if found, e := readResetReplay(ctx, tx, key, mac, request.IntentID, true); found || e != nil {
		if !found {
			return e
		}
		if _, gateErr := c.gate.CommitAuthorized(ctx, tx, decision.Generation); gateErr != nil {
			return gateErr
		}
		return e
	}
	if locked.account != original.account || locked.version != original.version || version != original.version ||
		locked.generation != original.generation || generation != original.generation || !hmac.Equal(active, request.IntentID[:]) || locked.state != "ACTIVE" ||
		locked.authorizationGeneration != original.authorizationGeneration || !hmac.Equal(locked.digest, confirmation[:]) {
		return ErrResetIntentInvalid
	}
	if version == math.MaxInt64 || sessionGeneration == math.MaxInt64 {
		return ErrAuthorizationUnavailable
	}
	// Claim before any irreversible mutation; global key uniqueness serializes
	// different-account races as well as retries on this account.
	claim, err := tx.Exec(ctx, `INSERT INTO c_auth.request_results
		(operation,key_digest,state,request_hmac,hmac_key_version,reset_intent_id,result_code,expires_at)
		VALUES('PASSWORD_RESET',$1,'LIVE',$2,1,$3,'COMMITTED',$4) ON CONFLICT(key_digest) DO NOTHING`,
		key[:], mac[:], request.IntentID[:], decision.TrustedAt.Add(8*24*time.Hour))
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	if claim.RowsAffected() == 0 {
		found, e := readResetReplay(ctx, tx, key, mac, request.IntentID, true)
		if !found {
			return ErrAuthorizationUnavailable
		}
		if _, gateErr := c.gate.CommitAuthorized(ctx, tx, decision.Generation); gateErr != nil {
			return gateErr
		}
		return e
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if !recoveryAccountAllowed(state, closure, final.TrustedAt) {
			return ErrRecoveryProofInvalid
		}
		if !final.TrustedAt.Before(locked.expires) {
			return ErrResetIntentExpired
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET password_hash=$2,password_salt=$3,password_params_version=$4,
			credential_version=$5,session_generation=$6,active_reset_intent_id=NULL WHERE account_id=$1`,
			original.account, material.Hash[:], material.Salt[:], material.ParametersVersion, version+1, sessionGeneration+1); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.recovery_codes SET code_digest=$2,activation_version=$3 WHERE account_id=$1`, original.account, confirmation[:], version+1); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `DELETE FROM c_auth.passkeys WHERE account_id=$1`, original.account); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason='RECOVERY' WHERE account_id=$1 AND revoked_at IS NULL`, original.account, final.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.reset_intents SET state='CONSUMED',new_recovery_digest=NULL,terminal_at=$2 WHERE intent_id=$1`, request.IntentID[:], final.TrustedAt); e != nil {
			return e
		}
		_, e := tx.Exec(ctx, `INSERT INTO c_auth.security_events(event_id,account_id,action,credential_version,session_generation,recorded_at)
			VALUES($1,$2,'PASSWORD_RESET',$3,$4,$5)`, uuid.New(), original.account, version+1, sessionGeneration+1, final.TrustedAt)
		return e
	})
	var pgerr *pgconn.PgError
	if errors.As(err, &pgerr) && pgerr.Code == "23505" && pgerr.ConstraintName == "recovery_codes_code_digest_key" {
		return ErrConflict
	}
	return err
}

func (c *Community) GetPasswordResetResult(ctx context.Context, key, id [32]byte) (string, error) {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return "", err
	}
	if key == ([32]byte{}) || id == ([32]byte{}) {
		return "", ErrResetResultNotFound
	}
	keyDigest := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", key[:])
	// First locate without locks. A missing intent may simply mean a client is
	// querying before an in-flight operation becomes visible.
	intent, intentErr := readResetIntent(ctx, c.pool, id, false)
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return "", ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var locked resetIntentRow
	if intentErr == nil {
		var account uuid.UUID
		if err = tx.QueryRow(ctx, `SELECT account_id FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, intent.account).Scan(&account); err != nil {
			return "", ErrAuthorizationUnavailable
		}
		if _, err = lockRestriction(ctx, tx, account); err != nil {
			return "", ErrAuthorizationUnavailable
		}
		locked, err = readResetIntent(ctx, tx, id, true)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return "", ErrAuthorizationUnavailable
		}
		if errors.Is(err, pgx.ErrNoRows) {
			intentErr = pgx.ErrNoRows
		}
	} else if !errors.Is(intentErr, pgx.ErrNoRows) {
		return "", ErrAuthorizationUnavailable
	}
	var operation, state string
	var result *string
	var storedID []byte
	err = tx.QueryRow(ctx, `SELECT operation,state,reset_intent_id,result_code FROM c_auth.request_results WHERE key_digest=$1 FOR UPDATE`, keyDigest[:]).Scan(&operation, &state, &storedID, &result)
	found := err == nil
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return "", ErrAuthorizationUnavailable
	}
	answer := "PENDING"
	var responseErr error
	if found {
		if state == "EXPIRED" {
			responseErr = ErrExpired
		} else if operation != "PASSWORD_RESET" || !hmac.Equal(storedID, id[:]) {
			responseErr = ErrResetResultNotFound
		} else if result != nil && (*result == "COMMITTED" || *result == "NOT_COMMITTED") {
			answer = *result
		} else {
			responseErr = ErrAuthorizationUnavailable
		}
	} else if errors.Is(intentErr, pgx.ErrNoRows) {
		responseErr = ErrResetResultNotFound
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if !found && intentErr == nil && locked.account == intent.account && locked.state != "CONSUMED" &&
			(locked.state == "ABANDONED" || locked.state == "EXPIRED" || !final.TrustedAt.Before(locked.expires)) {
			answer = "NOT_COMMITTED"
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	if responseErr != nil {
		return "", responseErr
	}
	return answer, nil
}

// CleanupRecoveryState clears expired secrets immediately and keeps terminal
// intent metadata for at least seven days. Results are narrowed in place to
// permanent tombstones before their FK-bound intent may be removed.
func (c *Community) CleanupRecoveryState(ctx context.Context, limit int) (int64, error) {
	if limit < 1 || limit > 1000 {
		return 0, ErrResetIntentInvalid
	}
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return 0, err
	}
	if err = c.cleanupRecoveryEvents(ctx, decision, limit); err != nil {
		return 0, err
	}
	rows, err := c.pool.Query(ctx, `SELECT intent_id,account_id FROM c_auth.reset_intents
		WHERE (state='ACTIVE' AND expires_at<=$1) OR (state<>'ACTIVE' AND terminal_at<=$1::timestamptz-interval '7 days')
		ORDER BY account_id,intent_id LIMIT $2`, decision.TrustedAt, limit)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	type candidate struct {
		id      [32]byte
		account uuid.UUID
	}
	var candidates []candidate
	for rows.Next() {
		var raw []byte
		var item candidate
		if err = rows.Scan(&raw, &item.account); err != nil {
			rows.Close()
			return 0, err
		}
		copy(item.id[:], raw)
		candidates = append(candidates, item)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return 0, err
	}
	var count int64
	for _, item := range candidates {
		tx, e := begin(ctx, c.pool)
		if e != nil {
			return count, ErrAuthorizationUnavailable
		}
		e = func() error {
			defer c.gate.Abort(ctx, tx)
			var account uuid.UUID
			if e = tx.QueryRow(ctx, `SELECT account_id FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, item.account).Scan(&account); e != nil {
				return e
			}
			if _, e = lockRestriction(ctx, tx, account); e != nil {
				return e
			}
			intent, e := readResetIntent(ctx, tx, item.id, true)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil
			}
			if e != nil {
				return e
			}
			resultLocks, e := tx.Query(ctx, `SELECT key_digest FROM c_auth.request_results WHERE reset_intent_id=$1 ORDER BY key_digest FOR UPDATE`, item.id[:])
			if e != nil {
				return e
			}
			for resultLocks.Next() {
			}
			e = resultLocks.Err()
			resultLocks.Close()
			if e != nil {
				return e
			}
			var changed int64
			_, e = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
				if intent.state == "ACTIVE" && !final.TrustedAt.Before(intent.expires) {
					if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET active_reset_intent_id=NULL WHERE account_id=$1 AND active_reset_intent_id=$2`, account, item.id[:]); e != nil {
						return e
					}
					if _, e := tx.Exec(ctx, `UPDATE c_auth.reset_intents SET state='EXPIRED',new_recovery_digest=NULL,terminal_at=$2 WHERE intent_id=$1`, item.id[:], final.TrustedAt); e != nil {
						return e
					}
					changed++
				} else if intent.state != "ACTIVE" {
					// Live results of any key keep the metadata referenced. Their
					// own cleanup path first strips this association permanently.
					if _, e := tx.Exec(ctx, `UPDATE c_auth.request_results SET state='EXPIRED',request_hmac=NULL,hmac_key_version=NULL,
						intent_id=NULL,reset_intent_id=NULL,result_code=NULL,expires_at=NULL
						WHERE reset_intent_id=$1 AND state='LIVE' AND expires_at<=$2`, item.id[:], final.TrustedAt); e != nil {
						return e
					}
					deleted, e := tx.Exec(ctx, `DELETE FROM c_auth.reset_intents WHERE intent_id=$1 AND terminal_at<=$2::timestamptz-interval '7 days'
						AND NOT EXISTS(SELECT 1 FROM c_auth.request_results WHERE reset_intent_id=$1)`, item.id[:], final.TrustedAt)
					if e != nil {
						return e
					}
					changed += deleted.RowsAffected()
				}
				return nil
			})
			if e == nil {
				count += changed
			}
			return e
		}()
		if e != nil {
			return count, e
		}
	}
	return count, nil
}

// Restricted incident metadata is also bounded. Events contain no slot or
// credential material; delivery of device notifications is a later slice.
func (c *Community) cleanupRecoveryEvents(ctx context.Context, decision AuthorizationDecision, limit int) error {
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	rows, err := tx.Query(ctx, `SELECT event_id FROM c_auth.security_events
		WHERE recorded_at+interval '7 days'<=$1 ORDER BY event_id LIMIT $2 FOR UPDATE SKIP LOCKED`, decision.TrustedAt, limit)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	ids := make([]uuid.UUID, 0)
	for rows.Next() {
		var id uuid.UUID
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			return ErrAuthorizationUnavailable
		}
		ids = append(ids, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		_, e := tx.Exec(ctx, `DELETE FROM c_auth.security_events WHERE event_id=ANY($1::uuid[])
			AND recorded_at+interval '7 days'<=$2`, ids, final.TrustedAt)
		return e
	})
	return err
}
