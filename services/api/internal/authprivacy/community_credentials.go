package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math"
	"sort"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type credentialProof struct {
	account                                     uuid.UUID
	token                                       [32]byte
	version, generation, authGeneration, params int64
	hash, salt                                  []byte
}

// Password work happens before locks. None of this preliminary evidence can
// authorize a newer credential version or a replacement session.
func (c *Community) proveCredentialPassword(ctx context.Context, bearer [32]byte, password string, verifier PasswordVerifier) (credentialProof, error) {
	var p credentialProof
	p.token = sha256.Sum256(bearer[:])
	if verifier == nil || password == "" || !utf8.ValidString(password) || len(password) > 2048 || utf8.RuneCountInString(password) > 512 {
		return p, ErrAuthenticationFailed
	}
	err := c.pool.QueryRow(ctx, `SELECT a.account_id,a.credential_version,a.password_hash,a.password_salt,
 COALESCE(a.password_params_version,0),s.session_generation,s.authorization_generation
 FROM c_auth.sessions s JOIN c_auth.accounts a USING(account_id) WHERE s.token_digest=$1`, p.token[:]).Scan(&p.account, &p.version, &p.hash, &p.salt, &p.params, &p.generation, &p.authGeneration)
	if errors.Is(err, pgx.ErrNoRows) {
		return p, ErrSessionInvalid
	}
	if err != nil {
		return p, ErrAuthorizationUnavailable
	}
	if len(p.hash) != 32 || len(p.salt) != 16 || p.params != 1 {
		return p, ErrSessionInvalid
	}
	material := PasswordMaterial{ParametersVersion: p.params}
	copy(material.Hash[:], p.hash)
	copy(material.Salt[:], p.salt)
	valid, err := verifier.VerifyPassword(ctx, password, material)
	if err != nil {
		return p, err
	}
	if !valid {
		return p, ErrAuthenticationFailed
	}
	return p, nil
}

type credentialAccount struct {
	account                                                  uuid.UUID
	state, username                                          string
	version, generation, rotationGeneration, resetGeneration int64
	params                                                   int64
	hash, salt, handle, activeRotation                       []byte
	ban                                                      restriction
	closure                                                  pendingClosure
}

func drainLocks(ctx context.Context, tx pgx.Tx, sql string, args ...any) error {
	rows, err := tx.Query(ctx, sql, args...)
	if err != nil {
		return err
	}
	for rows.Next() {
	}
	err = rows.Err()
	rows.Close()
	return err
}

// Every account command uses this order before credential/session/result rows.
func lockCredentialIntents(ctx context.Context, tx pgx.Tx, account uuid.UUID, ids ...[32]byte) error {
	rawIDs := make([][]byte, 0, len(ids))
	for _, id := range ids {
		rawIDs = append(rawIDs, id[:])
	}
	for _, query := range []string{
		`SELECT intent_id FROM c_auth.reset_intents WHERE account_id=$1 AND (state='ACTIVE' OR intent_id=ANY($2::bytea[])) ORDER BY intent_id FOR UPDATE`,
		`SELECT intent_id FROM c_auth.credential_change_intents WHERE account_id=$1 AND (state='ACTIVE' OR intent_id=ANY($2::bytea[])) ORDER BY intent_id FOR UPDATE`,
		`SELECT challenge_id FROM c_auth.auth_challenges WHERE account_id=$1 AND (state='ACTIVE' OR challenge_id=ANY($2::bytea[])) ORDER BY challenge_id FOR UPDATE`,
	} {
		if err := drainLocks(ctx, tx, query, account, rawIDs); err != nil {
			return err
		}
	}
	return nil
}
func lockCredentialAccount(ctx context.Context, tx pgx.Tx, account uuid.UUID, ids ...[32]byte) (credentialAccount, error) {
	a := credentialAccount{account: account}
	err := tx.QueryRow(ctx, `SELECT state,COALESCE(username,''),credential_version,session_generation,rotation_generation,
 reset_generation,COALESCE(password_params_version,0),password_hash,password_salt,user_handle,active_rotation_intent_id
 FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&a.state, &a.username, &a.version, &a.generation, &a.rotationGeneration, &a.resetGeneration, &a.params, &a.hash, &a.salt, &a.handle, &a.activeRotation)
	if err != nil {
		return a, ErrAuthorizationUnavailable
	}
	a.ban, err = lockRestriction(ctx, tx, account)
	if err != nil {
		return a, ErrAuthorizationUnavailable
	}
	a.closure, err = lockPendingClosure(ctx, tx, account)
	if err != nil {
		return a, ErrAuthorizationUnavailable
	}
	if err = lockCredentialIntents(ctx, tx, account, ids...); err != nil {
		return a, ErrAuthorizationUnavailable
	}
	for _, q := range []string{`SELECT code_digest FROM c_auth.recovery_codes WHERE account_id=$1 FOR UPDATE`, `SELECT credential_id FROM c_auth.passkeys WHERE account_id=$1 ORDER BY credential_id FOR UPDATE`} {
		if err = drainLocks(ctx, tx, q, account); err != nil {
			return a, ErrAuthorizationUnavailable
		}
	}
	return a, nil
}

type credentialSession struct {
	token                      [32]byte
	generation, authGeneration int64
	expires, lastActivity      time.Time
	revoked                    *time.Time
	reason                     *string
}

func lockCredentialSession(ctx context.Context, tx pgx.Tx, a credentialAccount, token [32]byte) (credentialSession, error) {
	s := credentialSession{token: token}
	err := tx.QueryRow(ctx, `SELECT session_generation,authorization_generation,expires_at,last_activity_at,revoked_at,revocation_reason
 FROM c_auth.sessions WHERE account_id=$1 AND token_digest=$2 FOR UPDATE`, a.account, token[:]).Scan(&s.generation, &s.authGeneration, &s.expires, &s.lastActivity, &s.revoked, &s.reason)
	if errors.Is(err, pgx.ErrNoRows) {
		return s, ErrSessionInvalid
	}
	if err != nil {
		return s, ErrAuthorizationUnavailable
	}
	return s, nil
}
func (s credentialSession) validate(a credentialAccount, final AuthorizationDecision) error {
	if a.state != "ACTIVE" || bannedAt(a.ban, final.TrustedAt) || s.authGeneration != int64(final.Generation) || s.generation != a.generation || s.revoked != nil || !final.TrustedAt.Before(s.expires) {
		if a.state == "ACTIVE" && s.authGeneration == int64(final.Generation) && s.reason != nil && *s.reason == "REPLACED" && s.generation < a.generation {
			return ErrSessionReplaced
		}
		return ErrSessionInvalid
	}
	if final.TrustedAt.Before(s.lastActivity) {
		return ErrAuthorizationUnavailable
	}
	return nil
}
func (s credentialSession) renew(ctx context.Context, tx pgx.Tx, at time.Time) (time.Time, error) {
	expires := s.expires
	if expires.Sub(at) <= renewalWindow {
		expires = at.Add(sessionLifetime)
	}
	_, err := tx.Exec(ctx, `UPDATE c_auth.sessions SET last_activity_at=$2,expires_at=$3 WHERE token_digest=$1`, s.token[:], at, expires)
	return expires, err
}
func checkCredentialProof(p credentialProof, a credentialAccount, s credentialSession) error {
	if p.account != a.account || p.version != a.version || p.params != a.params || !hmac.Equal(p.hash, a.hash) || !hmac.Equal(p.salt, a.salt) {
		return ErrCredentialStateChanged
	}
	if p.generation != s.generation || p.authGeneration != s.authGeneration || p.generation != a.generation {
		return ErrSessionInvalid
	}
	return nil
}
func (c *Community) credentialTransaction(ctx context.Context, bearer [32]byte, ids ...[32]byte) (pgx.Tx, credentialAccount, credentialSession, error) {
	token := sha256.Sum256(bearer[:])
	var account uuid.UUID
	err := c.pool.QueryRow(ctx, `SELECT account_id FROM c_auth.sessions WHERE token_digest=$1`, token[:]).Scan(&account)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, credentialAccount{}, credentialSession{}, ErrSessionInvalid
	}
	if err != nil {
		return nil, credentialAccount{}, credentialSession{}, ErrAuthorizationUnavailable
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return nil, credentialAccount{}, credentialSession{}, ErrAuthorizationUnavailable
	}
	a, err := lockCredentialAccount(ctx, tx, account, ids...)
	if err != nil {
		c.gate.Abort(ctx, tx)
		return nil, a, credentialSession{}, err
	}
	s, err := lockCredentialSession(ctx, tx, a, token)
	if err != nil {
		c.gate.Abort(ctx, tx)
		return nil, a, s, err
	}
	return tx, a, s, nil
}
func (c *Community) GetRecoveryCredentials(ctx context.Context, bearer [32]byte) (RecoveryCredentials, error) {
	var r RecoveryCredentials
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return r, err
	}
	tx, a, s, err := c.credentialTransaction(ctx, bearer)
	if err != nil {
		return r, err
	}
	defer c.gate.Abort(ctx, tx)
	r.Passkeys = make([]PasskeySummary, 0)
	err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_auth.recovery_codes WHERE account_id=$1)`, a.account).Scan(&r.RecoveryCodeAvailable)
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	rows, err := tx.Query(ctx, `SELECT credential_id,created_at,backup_eligible,backed_up FROM c_auth.passkeys WHERE account_id=$1 ORDER BY created_at,credential_id LIMIT 11`, a.account)
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	for rows.Next() {
		var id []byte
		var item PasskeySummary
		if err = rows.Scan(&id, &item.CreatedAt, &item.BackupEligible, &item.BackedUp); err != nil {
			break
		}
		item.CredentialID = base64.RawURLEncoding.EncodeToString(id)
		r.Passkeys = append(r.Passkeys, item)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil || len(r.Passkeys) > 10 {
		return RecoveryCredentials{}, ErrAuthorizationUnavailable
	}
	sort.Slice(r.Passkeys, func(i, j int) bool {
		if r.Passkeys[i].CreatedAt.Equal(r.Passkeys[j].CreatedAt) {
			return r.Passkeys[i].CredentialID < r.Passkeys[j].CredentialID
		}
		return r.Passkeys[i].CreatedAt.Before(r.Passkeys[j].CreatedAt)
	})
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		if e := s.validate(a, f); e != nil {
			return e
		}
		var e error
		r.SessionExpiresAt, e = s.renew(ctx, tx, f.TrustedAt)
		return e
	})
	if err != nil {
		return RecoveryCredentials{}, err
	}
	return r, nil
}
func (c *Community) CreateRecoveryCodeRotation(ctx context.Context, bearer [32]byte, password string, verifier PasswordVerifier) (CodeRotationIntent, error) {
	var r CodeRotationIntent
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return r, err
	}
	p, err := c.proveCredentialPassword(ctx, bearer, password, verifier)
	if err != nil {
		return r, err
	}
	r.ID, err = random32()
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	code, codeDigest, err := generateRecoveryCode()
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
	if a.rotationGeneration == math.MaxInt64 {
		return r, ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(f AuthorizationDecision) error {
		if e := s.validate(a, f); e != nil {
			return e
		}
		r.ExpiresAt = f.TrustedAt.Add(10 * time.Minute)
		if _, e := tx.Exec(ctx, `UPDATE c_auth.credential_change_intents SET state='ABANDONED',new_recovery_digest=NULL,target_credential_id=NULL,challenge_id=NULL,terminal_at=$2 WHERE account_id=$1 AND kind='ROTATE_CODE' AND state='ACTIVE'`, a.account, f.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `INSERT INTO c_auth.credential_change_intents(intent_id,account_id,kind,session_digest,session_generation,credential_version,authorization_generation,rotation_generation,new_recovery_digest,state,created_at,expires_at)
 VALUES($1,$2,'ROTATE_CODE',$3,$4,$5,$6,$7,$8,'ACTIVE',$9,$10)`, r.ID[:], a.account, s.token[:], s.generation, a.version, int64(f.Generation), a.rotationGeneration+1, codeDigest[:], f.TrustedAt, r.ExpiresAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET rotation_generation=$2,active_rotation_intent_id=$3 WHERE account_id=$1`, a.account, a.rotationGeneration+1, r.ID[:]); e != nil {
			return e
		}
		var e error
		r.SessionExpiresAt, e = s.renew(ctx, tx, f.TrustedAt)
		return e
	})
	if err != nil {
		return CodeRotationIntent{}, err
	}
	r.NewRecoveryCode = code
	return r, nil
}

type credentialIntent struct {
	kind, state                         string
	token, target, digest               []byte
	version, generation, authGeneration int64
	rotation                            *int64
	expires                             time.Time
}

func readCredentialIntent(ctx context.Context, tx pgx.Tx, account uuid.UUID, id [32]byte) (credentialIntent, error) {
	var r credentialIntent
	err := tx.QueryRow(ctx, `SELECT kind,state,session_digest,target_credential_id,new_recovery_digest,credential_version,session_generation,authorization_generation,rotation_generation,expires_at FROM c_auth.credential_change_intents WHERE account_id=$1 AND intent_id=$2 FOR UPDATE`, account, id[:]).Scan(&r.kind, &r.state, &r.token, &r.target, &r.digest, &r.version, &r.generation, &r.authGeneration, &r.rotation, &r.expires)
	if errors.Is(err, pgx.ErrNoRows) {
		return r, ErrCredentialIntentInvalid
	}
	if err != nil {
		return r, ErrAuthorizationUnavailable
	}
	return r, nil
}
func (r credentialIntent) valid(a credentialAccount, s credentialSession, f AuthorizationDecision, kind string) error {
	if r.kind != kind || r.state != "ACTIVE" || r.version != a.version || r.generation != s.generation || r.authGeneration != int64(f.Generation) || !hmac.Equal(r.token, s.token[:]) {
		return ErrCredentialIntentInvalid
	}
	if !f.TrustedAt.Before(r.expires) {
		return ErrCredentialIntentExpired
	}
	return nil
}
func readCredentialReplay(ctx context.Context, tx pgx.Tx, key, mac [32]byte, operation string) (bool, error) {
	var op, state string
	var stored []byte
	var result *string
	err := tx.QueryRow(ctx, `SELECT operation,state,request_hmac,result_code FROM c_auth.request_results WHERE key_digest=$1 FOR UPDATE`, key[:]).Scan(&op, &state, &stored, &result)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, ErrAuthorizationUnavailable
	}
	if state == "EXPIRED" {
		return true, ErrExpired
	}
	if op != operation || result == nil || *result != "COMMITTED" || !hmac.Equal(stored, mac[:]) {
		return true, ErrConflict
	}
	return true, nil
}
func claimCredentialResult(ctx context.Context, tx pgx.Tx, key, mac, id [32]byte, op string, at time.Time) (bool, error) {
	column := "credential_change_id"
	if op == "CREATE_PASSKEY" {
		column = "auth_challenge_id"
	}
	tag, err := tx.Exec(ctx, `INSERT INTO c_auth.request_results(operation,key_digest,state,request_hmac,hmac_key_version,`+column+`,result_code,expires_at) VALUES($1,$2,'LIVE',$3,1,$4,'COMMITTED',$5) ON CONFLICT(key_digest) DO NOTHING`, op, key[:], mac[:], id[:], at.Add(8*24*time.Hour))
	if err != nil {
		return false, ErrAuthorizationUnavailable
	}
	return tag.RowsAffected() == 1, nil
}

// Invalidation clears all pending secrets in the same transaction as a control
// credential change. Retained recovery/Passkey rows remain valid across versions.
func invalidateCredentialAuthority(ctx context.Context, tx pgx.Tx, account uuid.UUID, at time.Time) error {
	for _, q := range []string{
		`UPDATE c_auth.reset_intents SET state='ABANDONED',new_recovery_digest=NULL,terminal_at=$2 WHERE account_id=$1 AND state='ACTIVE'`,
		`UPDATE c_auth.credential_change_intents SET state='ABANDONED',new_recovery_digest=NULL,target_credential_id=NULL,challenge_id=NULL,terminal_at=$2 WHERE account_id=$1 AND state='ACTIVE'`,
		`UPDATE c_auth.auth_challenges SET state='ABANDONED',nonce=NULL,terminal_at=$2 WHERE account_id=$1 AND state='ACTIVE'`,
	} {
		if _, err := tx.Exec(ctx, q, account, at); err != nil {
			return err
		}
	}
	_, err := tx.Exec(ctx, `UPDATE c_auth.accounts SET active_reset_intent_id=NULL,active_rotation_intent_id=NULL WHERE account_id=$1`, account)
	return err
}
func recordCredentialEvent(ctx context.Context, tx pgx.Tx, a credentialAccount, action string, version int64, at time.Time) error {
	_, err := tx.Exec(ctx, `INSERT INTO c_auth.security_events(event_id,account_id,action,credential_version,session_generation,recorded_at) VALUES($1,$2,$3,$4,$5,$6)`, uuid.New(), a.account, action, version, a.generation, at)
	return err
}
func credentialConflict(err error) error {
	var e *pgconn.PgError
	if errors.As(err, &e) && e.Code == "23505" {
		return ErrConflict
	}
	return err
}
func (c *Community) ConfirmRecoveryCodeRotation(ctx context.Context, bearer [32]byte, r CodeRotationConfirmation) (time.Time, error) {
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return time.Time{}, err
	}
	if r.IntentID == ([32]byte{}) || r.IdempotencyKey == ([32]byte{}) {
		return time.Time{}, ErrCredentialIntentInvalid
	}
	confirmation, err := recoveryDigest(r.NewRecoveryCodeConfirmation)
	if err != nil {
		return time.Time{}, ErrCredentialIntentInvalid
	}
	tx, a, s, err := c.credentialTransaction(ctx, bearer, r.IntentID)
	if err != nil {
		return time.Time{}, err
	}
	defer c.gate.Abort(ctx, tx)
	key := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", r.IdempotencyKey[:])
	mac := requestMAC(c.requestKey, []byte("ROTATE_CODE"), s.token[:], r.IntentID[:], confirmation[:])
	found, replayErr := readCredentialReplay(ctx, tx, key, mac, "ROTATE_CODE")
	if replayErr != nil && !found {
		return time.Time{}, replayErr
	}
	var intent credentialIntent
	if !found {
		intent, err = readCredentialIntent(ctx, tx, a.account, r.IntentID)
		if err != nil {
			return time.Time{}, err
		}
		if a.version == math.MaxInt64 {
			return time.Time{}, ErrAuthorizationUnavailable
		}
		claimed, e := claimCredentialResult(ctx, tx, key, mac, r.IntentID, "ROTATE_CODE", d.TrustedAt)
		if e != nil {
			return time.Time{}, e
		}
		if !claimed {
			found, replayErr = readCredentialReplay(ctx, tx, key, mac, "ROTATE_CODE")
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
		if e := intent.valid(a, s, f, "ROTATE_CODE"); e != nil {
			return e
		}
		if intent.rotation == nil || *intent.rotation != a.rotationGeneration || !hmac.Equal(a.activeRotation, r.IntentID[:]) || !hmac.Equal(intent.digest, confirmation[:]) {
			return ErrCredentialIntentInvalid
		}
		if tag, e := tx.Exec(ctx, `UPDATE c_auth.recovery_codes SET code_digest=$2,activation_version=$3 WHERE account_id=$1`, a.account, confirmation[:], a.version+1); e != nil {
			return e
		} else if tag.RowsAffected() != 1 {
			return ErrAuthorizationUnavailable
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
		if e := recordCredentialEvent(ctx, tx, a, "ROTATE_CODE", a.version+1, f.TrustedAt); e != nil {
			return e
		}
		var e error
		expires, e = s.renew(ctx, tx, f.TrustedAt)
		return e
	})
	return expires, credentialConflict(err)
}
func (c *Community) webAuthnPolicy() ([32]byte, error) {
	if c.webauthn == nil {
		return [32]byte{}, ErrAuthorizationUnavailable
	}
	b, err := json.Marshal(c.webauthnConfig)
	if err != nil {
		return [32]byte{}, ErrAuthorizationUnavailable
	}
	return digest("HNUHOLE/WEBAUTHN-POLICY/V1", b), nil
}
