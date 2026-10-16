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
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

var (
	ErrClosureNotFound         = errors.New("closure status not found")
	ErrRestrictionStateChanged = errors.New("restriction state changed")
)

const closureWaitingPeriod = 7 * 24 * time.Hour
const closureStatusRetention = 30 * 24 * time.Hour

type ClosureRequest struct {
	Bearer       [32]byte
	ID           [32]byte
	StatusDigest [32]byte
	Password     string
}

type ClosureAccepted struct {
	ID    [32]byte
	DueAt time.Time
}

type ClosureStatus struct {
	State          string
	DueAt          *time.Time
	ReleaseReceipt string
}

type pendingClosure struct {
	id         [32]byte
	dueAt      time.Time
	generation int64
	found      bool
}

// lockPendingClosure follows the account and restriction locks. It precedes
// recovery intents, credentials, sessions and command-result locks.
func lockPendingClosure(ctx context.Context, tx pgx.Tx, account uuid.UUID) (pendingClosure, error) {
	var p pendingClosure
	var id []byte
	err := tx.QueryRow(ctx, `SELECT closure_id,due_at,request_generation FROM c_auth.closure_requests
		WHERE account_id=$1 AND state='PENDING' FOR UPDATE`, account).Scan(&id, &p.dueAt, &p.generation)
	if errors.Is(err, pgx.ErrNoRows) {
		return p, nil
	}
	if err != nil || len(id) != 32 || p.generation <= 0 {
		if err == nil {
			err = ErrAuthorizationUnavailable
		}
		return p, err
	}
	copy(p.id[:], id)
	p.found = true
	return p, nil
}

func cancelPendingClosure(ctx context.Context, tx pgx.Tx, account uuid.UUID, p pendingClosure, at time.Time) error {
	if !p.found || !at.Before(p.dueAt) || p.generation == math.MaxInt64 {
		return ErrAccountUnavailable
	}
	command, err := tx.Exec(ctx, `UPDATE c_auth.closure_requests SET state='CANCELLED',account_id=NULL,
		request_generation=NULL,due_at=NULL,terminal_at=$2 WHERE closure_id=$1 AND state='PENDING'`, p.id[:], at)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrAccountUnavailable
	}
	command, err = tx.Exec(ctx, `UPDATE c_auth.accounts SET state='ACTIVE',closure_generation=closure_generation+1
		WHERE account_id=$1 AND state='PENDING_CLOSE' AND closure_generation=$2`, account, p.generation)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrAccountUnavailable
	}
	return nil
}

func closureKey(id [32]byte) [32]byte { return digest("HNUHOLE/C-CLOSURE-TOMBSTONE/V1", id[:]) }

// RequestAccountClosure requires the current bearer even on a live retry. An
// already-revoked historical token never becomes a closure-management bypass.
func (c *Community) RequestAccountClosure(ctx context.Context, request ClosureRequest, verifier PasswordVerifier) (ClosureAccepted, error) {
	var zero ClosureAccepted
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return zero, err
	}
	if verifier == nil || request.ID == ([32]byte{}) || request.StatusDigest == ([32]byte{}) || request.Password == "" ||
		!utf8.ValidString(request.Password) || len(request.Password) > 2048 || utf8.RuneCountInString(request.Password) > 512 {
		return zero, ErrIntentInvalid
	}
	key := closureKey(request.ID)
	var anchorState string
	err = c.pool.QueryRow(ctx, `SELECT state FROM c_auth.request_results WHERE key_digest=$1`, key[:]).Scan(&anchorState)
	if err == nil && anchorState == "EXPIRED" {
		return zero, ErrExpired
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrAuthorizationUnavailable
	}
	tokenHash := sha256.Sum256(request.Bearer[:])
	var account uuid.UUID
	var hash, salt []byte
	var params, version int64
	err = c.pool.QueryRow(ctx, `SELECT a.account_id,a.password_hash,a.password_salt,a.password_params_version,a.credential_version
		FROM c_auth.accounts a JOIN c_auth.sessions s USING(account_id) WHERE s.token_digest=$1`, tokenHash[:]).Scan(&account, &hash, &salt, &params, &version)
	if errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrSessionInvalid
	}
	if err != nil || len(hash) != 32 || len(salt) != 16 || params != 1 {
		return zero, ErrSessionInvalid
	}
	var material PasswordMaterial
	copy(material.Hash[:], hash)
	copy(material.Salt[:], salt)
	material.ParametersVersion = params
	valid, err := verifier.VerifyPassword(ctx, request.Password, material)
	if err != nil {
		return zero, err
	}
	if !valid {
		return zero, ErrAuthenticationFailed
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state string
	var lockedHash, lockedSalt []byte
	var lockedParams *int64
	var lockedVersion, sessionGeneration, closureGeneration int64
	err = tx.QueryRow(ctx, `SELECT state,password_hash,password_salt,password_params_version,credential_version,
		session_generation,closure_generation FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).
		Scan(&state, &lockedHash, &lockedSalt, &lockedParams, &lockedVersion, &sessionGeneration, &closureGeneration)
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	if lockedParams == nil || *lockedParams != params || lockedVersion != version || !hmac.Equal(lockedHash, hash) || !hmac.Equal(lockedSalt, salt) {
		return zero, ErrCredentialStateChanged
	}
	ban, err := lockRestriction(ctx, tx, account)
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	if _, err = lockPendingClosure(ctx, tx, account); err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	var existingState string
	var existingAccount *uuid.UUID
	var existingDigest []byte
	// A caller may submit another account's ID. Never lock that status row
	// after locking this account's pending closure; the unique result anchor
	// serializes ID claims without a cross-account closure-lock cycle.
	err = tx.QueryRow(ctx, `SELECT state,account_id,status_digest FROM c_auth.closure_requests WHERE closure_id=$1`, request.ID[:]).Scan(&existingState, &existingAccount, &existingDigest)
	exists := err == nil
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrAuthorizationUnavailable
	}
	var rowGeneration, rowAuthorization int64
	var expires time.Time
	var revoked *time.Time
	err = tx.QueryRow(ctx, `SELECT session_generation,authorization_generation,expires_at,revoked_at FROM c_auth.sessions
		WHERE token_digest=$1 AND account_id=$2 FOR UPDATE`, tokenHash[:], account).Scan(&rowGeneration, &rowAuthorization, &expires, &revoked)
	if errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrSessionInvalid
	}
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	// Including the original bearer prevents the retained MAC from becoming an
	// enumerable account-to-slot link when terminal status retains only a slot.
	mac := requestMAC(c.requestKey, []byte("CLOSURE"), account[:], request.StatusDigest[:], request.Bearer[:])
	var operation, resultState string
	var storedMAC []byte
	err = tx.QueryRow(ctx, `SELECT operation,state,request_hmac FROM c_auth.request_results WHERE key_digest=$1 FOR UPDATE`, key[:]).Scan(&operation, &resultState, &storedMAC)
	hasResult := err == nil
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrAuthorizationUnavailable
	}
	if !hasResult {
		claim, e := tx.Exec(ctx, `INSERT INTO c_auth.request_results
			(operation,key_digest,state,request_hmac,hmac_key_version,result_code,expires_at)
			VALUES('CLOSURE',$1,'LIVE',$2,1,'CLOSURE_ACCEPTED',$3) ON CONFLICT(key_digest) DO NOTHING`,
			key[:], mac[:], decision.TrustedAt.Add(8*24*time.Hour))
		if e != nil {
			return zero, ErrAuthorizationUnavailable
		}
		if claim.RowsAffected() != 1 {
			hasResult = true
			if e = tx.QueryRow(ctx, `SELECT operation,state,request_hmac FROM c_auth.request_results
				WHERE key_digest=$1 FOR UPDATE`, key[:]).Scan(&operation, &resultState, &storedMAC); e != nil {
				return zero, ErrAuthorizationUnavailable
			}
		}
	}
	var result ClosureAccepted
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if hasResult && resultState == "EXPIRED" {
			return ErrExpired
		}
		if state != "ACTIVE" || revoked != nil || rowGeneration != sessionGeneration || rowAuthorization != int64(final.Generation) ||
			!final.TrustedAt.Before(expires) {
			return ErrSessionInvalid
		}
		if bannedAt(ban, final.TrustedAt) {
			return ErrAccountUnavailable
		}
		if sessionGeneration == math.MaxInt64 || closureGeneration == math.MaxInt64 {
			return ErrAuthorizationUnavailable
		}
		if hasResult || exists {
			if operation != "CLOSURE" || !hmac.Equal(storedMAC, mac[:]) || !hmac.Equal(existingDigest, request.StatusDigest[:]) {
				return ErrConflict
			}
			// Cancellation does not make an old ID available for another request.
			return ErrConflict
		}
		result = ClosureAccepted{ID: request.ID, DueAt: final.TrustedAt.Add(closureWaitingPeriod)}
		if e := c.stopPostPublication(ctx, tx, account, "REQUEST_CLOSURE", final.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET state='PENDING_CLOSE',closure_generation=$2,
			session_generation=$3 WHERE account_id=$1`, account, closureGeneration+1, sessionGeneration+1); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason='CLOSURE'
			WHERE account_id=$1 AND revoked_at IS NULL`, account, final.TrustedAt); e != nil {
			return e
		}
		_, e := tx.Exec(ctx, `INSERT INTO c_auth.closure_requests(closure_id,account_id,status_digest,request_generation,due_at,state)
			VALUES($1,$2,$3,$4,$5,'PENDING')`, request.ID[:], account, request.StatusDigest[:], closureGeneration+1, result.DueAt)
		return e
	})
	if err != nil {
		return zero, err
	}
	return result, nil
}

// GetAccountClosureStatus grants only the bounded status capability. Signing
// for an acknowledged, cleaned outbox is performed before the final locks;
// neither receipt signing nor this read can cancel closure or create a session.
func (c *Community) GetAccountClosureStatus(ctx context.Context, id, secret [32]byte) (ClosureStatus, error) {
	var result ClosureStatus
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return result, err
	}
	statusDigest := digest("HNUHOLE/CLOSE-STATUS/V1", secret[:])
	for attempts := 0; attempts < 3; attempts++ {
		var locatedAccount *uuid.UUID
		var locatedSlot []byte
		var locatedState string
		var storedDigest, message, signature []byte
		var acknowledged *bool
		err = c.pool.QueryRow(ctx, `SELECT r.account_id,r.slot_id,r.state,r.status_digest,l.receipt_acknowledged,o.receipt_message,o.signature
			FROM c_auth.closure_requests r LEFT JOIN c_auth.slot_ledger l ON l.slot_id=r.slot_id
			LEFT JOIN c_auth.receipt_outbox o ON o.slot_id=r.slot_id WHERE r.closure_id=$1`, id[:]).
			Scan(&locatedAccount, &locatedSlot, &locatedState, &storedDigest, &acknowledged, &message, &signature)
		if errors.Is(err, pgx.ErrNoRows) || (err == nil && !hmac.Equal(storedDigest, statusDigest[:])) {
			return result, ErrClosureNotFound
		}
		if err != nil {
			return result, ErrAuthorizationUnavailable
		}
		encodedReceipt := ""
		if locatedState == "CLOSED_RELEASE_PENDING" {
			if len(locatedSlot) != 32 || acknowledged == nil {
				return result, ErrAuthorizationUnavailable
			}
			if len(signature) != 64 && *acknowledged {
				if c.receiptSigner == nil {
					return result, ErrAuthorizationUnavailable
				}
				var slot protocol.SlotID
				copy(slot[:], locatedSlot)
				message, err = (protocol.Receipt{Purpose: protocol.PurposeReleased, Epoch: c.signingEpoch, Slot: slot}).MessageBytes()
				if err != nil {
					return result, ErrAuthorizationUnavailable
				}
				signature, err = c.receiptSigner(ctx, c.signingEpoch, append([]byte{}, message...))
				if err != nil {
					return result, ErrAuthorizationUnavailable
				}
			}
			if len(signature) == 64 {
				encodedReceipt = protocol.EncodeCanonicalBase64url(append(append([]byte{}, message...), signature...))
				receipt, e := c.verifier.VerifyReceipt(encodedReceipt, protocol.PurposeReleased)
				if e != nil || !hmac.Equal(receipt.Slot[:], locatedSlot) {
					return result, ErrAuthorizationUnavailable
				}
			}
		}
		tx, e := begin(ctx, c.pool)
		if e != nil {
			return result, ErrAuthorizationUnavailable
		}
		if locatedAccount != nil {
			var ignored string
			if e = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, *locatedAccount).Scan(&ignored); e == nil {
				_, e = lockRestriction(ctx, tx, *locatedAccount)
			}
		}
		var slotState string
		var slotACK bool
		if e == nil && len(locatedSlot) == 32 {
			if e = lockSlot(ctx, tx, locatedSlot); e == nil {
				e = tx.QueryRow(ctx, `SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`, locatedSlot).Scan(&slotState, &slotACK)
			}
		}
		var currentAccount *uuid.UUID
		var currentSlot, currentDigest []byte
		var currentState string
		var dueAt *time.Time
		if e == nil {
			e = tx.QueryRow(ctx, `SELECT account_id,slot_id,state,status_digest,due_at FROM c_auth.closure_requests
				WHERE closure_id=$1 FOR UPDATE`, id[:]).Scan(&currentAccount, &currentSlot, &currentState, &currentDigest, &dueAt)
		}
		if errors.Is(e, pgx.ErrNoRows) {
			_ = c.gate.Abort(ctx, tx)
			return result, ErrClosureNotFound
		}
		if e != nil {
			_ = c.gate.Abort(ctx, tx)
			return result, ErrAuthorizationUnavailable
		}
		if currentState != locatedState || !sameAccount(currentAccount, locatedAccount) || !hmac.Equal(currentSlot, locatedSlot) {
			_ = c.gate.Abort(ctx, tx)
			continue
		}
		_, e = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
			if !hmac.Equal(currentDigest, statusDigest[:]) {
				return ErrClosureNotFound
			}
			switch currentState {
			case "PENDING":
				if dueAt == nil {
					return ErrAuthorizationUnavailable
				}
				result = ClosureStatus{State: "PENDING", DueAt: dueAt}
				if !final.TrustedAt.Before(*dueAt) {
					result.State = "FINALIZING"
				}
			case "CANCELLED":
				result = ClosureStatus{State: "CANCELLED"}
			case "CLOSED_RELEASE_PENDING":
				if slotState != "CLOSED" {
					return ErrAuthorizationUnavailable
				}
				result = ClosureStatus{State: "CLOSED_RELEASE_PENDING", ReleaseReceipt: encodedReceipt}
				if slotACK {
					if encodedReceipt == "" {
						return ErrAuthorizationUnavailable
					}
					result.State = "RELEASED"
				}
			default:
				return ErrAuthorizationUnavailable
			}
			return nil
		})
		_ = c.gate.Abort(ctx, tx)
		if e != nil {
			return ClosureStatus{}, e
		}
		return result, nil
	}
	return result, ErrAuthorizationUnavailable
}

func sameAccount(a, b *uuid.UUID) bool {
	return (a == nil && b == nil) || (a != nil && b != nil && *a == *b)
}

// FinalizeDueClosures locates candidates without locks, then serializes each
// complete close against login, recovery and moderation under its account lock.
func (c *Community) FinalizeDueClosures(ctx context.Context, limit int) (int64, error) {
	if limit < 1 || limit > 1000 {
		return 0, ErrIntentInvalid
	}
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return 0, err
	}
	rows, err := c.pool.Query(ctx, `SELECT account_id FROM c_auth.closure_requests WHERE state='PENDING' AND due_at<=$1
		ORDER BY due_at,closure_id LIMIT $2`, decision.TrustedAt, limit)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var accounts []uuid.UUID
	for rows.Next() {
		var a uuid.UUID
		if err = rows.Scan(&a); err != nil {
			rows.Close()
			return 0, ErrAuthorizationUnavailable
		}
		accounts = append(accounts, a)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var closed int64
	for _, account := range accounts {
		ok, e := c.finalizeAccountClosure(ctx, account)
		if e != nil {
			return closed, e
		}
		if ok {
			closed++
		}
	}
	return closed, nil
}

func lockClosureDependents(ctx context.Context, tx pgx.Tx, account uuid.UUID) error {
	if err := lockCredentialIntents(ctx, tx, account); err != nil {
		return err
	}
	for _, sql := range []string{
		`SELECT code_digest FROM c_auth.recovery_codes WHERE account_id=$1 FOR UPDATE`,
		`SELECT credential_id FROM c_auth.passkeys WHERE account_id=$1 ORDER BY credential_id FOR UPDATE`,
		`SELECT token_digest FROM c_auth.sessions WHERE account_id=$1 ORDER BY token_digest FOR UPDATE`,
		`SELECT account_id FROM c_auth.recent_device_replacement WHERE account_id=$1 FOR UPDATE`,
		`SELECT account_id FROM public.identity_account_state WHERE account_id=$1 FOR UPDATE`,
		`SELECT identity_id FROM public.community_identities WHERE account_id=$1 ORDER BY identity_id FOR UPDATE`,
	} {
		rows, err := tx.Query(ctx, sql, account)
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

func (c *Community) finalizeAccountClosure(ctx context.Context, account uuid.UUID) (bool, error) {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return false, err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return false, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state string
	var credentialVersion, sessionGeneration, closureGeneration, resetGeneration int64
	err = tx.QueryRow(ctx, `SELECT state,credential_version,session_generation,closure_generation,reset_generation
		FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&state, &credentialVersion, &sessionGeneration, &closureGeneration, &resetGeneration)
	if err != nil {
		return false, ErrAuthorizationUnavailable
	}
	if _, err = lockRestriction(ctx, tx, account); err != nil {
		return false, ErrAuthorizationUnavailable
	}
	if state != "PENDING_CLOSE" {
		_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation)
		return false, err
	}
	var slot []byte
	err = tx.QueryRow(ctx, `SELECT slot_id FROM c_auth.slot_ledger WHERE account_id=$1 AND state='ACTIVE'`, account).Scan(&slot)
	if err != nil || len(slot) != 32 {
		return false, ErrAuthorizationUnavailable
	}
	if err = lockSlot(ctx, tx, slot); err != nil {
		return false, ErrAuthorizationUnavailable
	}
	var slotAccount uuid.UUID
	err = tx.QueryRow(ctx, `SELECT account_id FROM c_auth.slot_ledger WHERE slot_id=$1 AND state='ACTIVE' FOR UPDATE`, slot).Scan(&slotAccount)
	if err != nil || slotAccount != account {
		return false, ErrAuthorizationUnavailable
	}
	p, err := lockPendingClosure(ctx, tx, account)
	if err != nil {
		return false, ErrAuthorizationUnavailable
	}
	if err = lockClosureDependents(ctx, tx, account); err != nil {
		return false, ErrAuthorizationUnavailable
	}
	var restrictionVersion int64
	if err = tx.QueryRow(ctx, `SELECT version FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&restrictionVersion); err != nil {
		return false, ErrAuthorizationUnavailable
	}
	var finalClosed bool
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if !p.found || p.generation != closureGeneration {
			return ErrAccountUnavailable
		}
		if final.TrustedAt.Before(p.dueAt) {
			return nil
		}
		if credentialVersion == math.MaxInt64 || sessionGeneration == math.MaxInt64 || closureGeneration == math.MaxInt64 ||
			resetGeneration == math.MaxInt64 || restrictionVersion == math.MaxInt64 {
			return ErrAuthorizationUnavailable
		}
		at := final.TrustedAt
		if e := invalidateCredentialAuthority(ctx, tx, account, at); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `DELETE FROM c_auth.recovery_codes WHERE account_id=$1`, account); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `DELETE FROM c_auth.passkeys WHERE account_id=$1`, account); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason='CLOSURE'
			WHERE account_id=$1 AND revoked_at IS NULL`, account, at); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET state='CLOSED',username=NULL,password_hash=NULL,password_salt=NULL,
			password_params_version=NULL,user_handle=NULL,active_rotation_intent_id=NULL,active_reset_intent_id=NULL,credential_version=credential_version+1,
			reset_generation=reset_generation+1,session_generation=session_generation+1,closure_generation=closure_generation+1
			WHERE account_id=$1`, account); e != nil {
			return e
		}
		// Formal closure erases every remaining identity profile at the same
		// authority point as CLOSED and its release outbox. Existing tombstones,
		// cumulative creation counters and permanent change receipts survive.
		if e := c.closePostAccount(ctx, tx, account, at); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE public.community_identities SET nickname=NULL,avatar=NULL,
			last_renamed_at=NULL,deleted_at=$2 WHERE account_id=$1 AND deleted_at IS NULL`, account, at); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.account_restrictions SET ban_state='NONE',ban_ends_at=NULL,
			mute_state='NONE',mute_ends_at=NULL,version=version+1 WHERE account_id=$1`, account); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `DELETE FROM c_auth.recent_device_replacement WHERE account_id=$1`, account); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.slot_ledger SET state='CLOSED',account_id=NULL WHERE slot_id=$1`, slot); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.closure_requests SET state='CLOSED_RELEASE_PENDING',account_id=NULL,
			request_generation=NULL,due_at=NULL,slot_id=$2,terminal_at=$3 WHERE closure_id=$1`, p.id[:], slot, at); e != nil {
			return e
		}
		var protocolSlot protocol.SlotID
		copy(protocolSlot[:], slot)
		message, e := (protocol.Receipt{Purpose: protocol.PurposeReleased, Epoch: c.signingEpoch, Slot: protocolSlot}).MessageBytes()
		if e != nil {
			return e
		}
		if _, e = tx.Exec(ctx, `INSERT INTO c_auth.receipt_outbox(slot_id,purpose,signing_key_epoch,receipt_message,state)
			VALUES($1,'RELEASED',$2,$3,'PENDING_SIGN')`, slot, int64(c.signingEpoch), message); e != nil {
			return e
		}
		finalClosed = true
		return nil
	})
	if err != nil {
		return false, err
	}
	return finalClosed, nil
}

// ApplyAccountBan is a trusted moderation command, not a public HTTP route.
// The version fence and account lock atomically revoke sessions. Once due_at
// has passed even a new ban cannot cancel the pending terminal transition.
func (c *Community) ApplyAccountBan(ctx context.Context, account uuid.UUID, expectedVersion int64, endsAt *time.Time) error {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return err
	}
	if account == uuid.Nil || expectedVersion < 1 {
		return ErrIntentInvalid
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state string
	var generation, closureGeneration int64
	err = tx.QueryRow(ctx, `SELECT state,session_generation,closure_generation FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).
		Scan(&state, &generation, &closureGeneration)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrAccountUnavailable
	}
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	if _, err = lockRestriction(ctx, tx, account); err != nil {
		return ErrAuthorizationUnavailable
	}
	var version int64
	if err = tx.QueryRow(ctx, `SELECT version FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&version); err != nil {
		return ErrAuthorizationUnavailable
	}
	p, err := lockPendingClosure(ctx, tx, account)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	rows, err := tx.Query(ctx, `SELECT token_digest FROM c_auth.sessions WHERE account_id=$1 ORDER BY token_digest FOR UPDATE`, account)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	for rows.Next() {
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if state == "CLOSED" {
			return ErrAccountUnavailable
		}
		if version != expectedVersion {
			return ErrRestrictionStateChanged
		}
		if version == math.MaxInt64 || generation == math.MaxInt64 {
			return ErrAuthorizationUnavailable
		}
		if endsAt != nil && !endsAt.After(final.TrustedAt) {
			return ErrIntentInvalid
		}
		if state == "PENDING_CLOSE" && (!p.found || p.generation != closureGeneration) {
			return ErrAccountUnavailable
		}
		if e := c.stopPostPublication(ctx, tx, account, "BAN", final.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.account_restrictions SET ban_state='BANNED',ban_ends_at=$2,version=version+1
			WHERE account_id=$1`, account, endsAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason='BAN'
			WHERE account_id=$1 AND revoked_at IS NULL`, account, final.TrustedAt); e != nil {
			return e
		}
		if _, e := tx.Exec(ctx, `UPDATE c_auth.accounts SET session_generation=session_generation+1 WHERE account_id=$1`, account); e != nil {
			return e
		}
		if state == "PENDING_CLOSE" && final.TrustedAt.Before(p.dueAt) {
			return cancelPendingClosure(ctx, tx, account, p, final.TrustedAt)
		}
		return nil
	})
	return err
}

// CleanupClosureStatuses removes only CANCELLED or durably ACKed status
// capabilities after thirty days. Request bindings have their own shorter
// retry lifetime, even when release delivery remains pending indefinitely.
// The independent closure-ID anchor remains.
func (c *Community) CleanupClosureStatuses(ctx context.Context, limit int) (int64, error) {
	if limit < 1 || limit > 1000 {
		return 0, ErrIntentInvalid
	}
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return 0, err
	}
	if err = c.expireClosureResults(ctx, decision, limit); err != nil {
		return 0, err
	}
	rows, err := c.pool.Query(ctx, `SELECT closure_id,slot_id FROM c_auth.closure_requests
		WHERE (state='CANCELLED' AND terminal_at<=$1) OR (state='CLOSED_RELEASE_PENDING' AND released_at<=$1)
		ORDER BY closure_id LIMIT $2`, decision.TrustedAt.Add(-closureStatusRetention), limit)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	type candidate struct {
		id   [32]byte
		slot []byte
	}
	var candidates []candidate
	for rows.Next() {
		var value candidate
		var id []byte
		if err = rows.Scan(&id, &value.slot); err != nil || len(id) != 32 {
			rows.Close()
			return 0, ErrAuthorizationUnavailable
		}
		copy(value.id[:], id)
		candidates = append(candidates, value)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var removed int64
	for _, candidate := range candidates {
		tx, e := begin(ctx, c.pool)
		if e != nil {
			return removed, ErrAuthorizationUnavailable
		}
		var ack bool
		if len(candidate.slot) > 0 {
			if e = lockSlot(ctx, tx, candidate.slot); e == nil {
				e = tx.QueryRow(ctx, `SELECT receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`, candidate.slot).Scan(&ack)
			}
		}
		var state string
		var terminal, released *time.Time
		if e == nil {
			e = tx.QueryRow(ctx, `SELECT state,terminal_at,released_at FROM c_auth.closure_requests WHERE closure_id=$1 FOR UPDATE`, candidate.id[:]).Scan(&state, &terminal, &released)
		}
		if errors.Is(e, pgx.ErrNoRows) {
			_ = c.gate.Abort(ctx, tx)
			continue
		}
		if e != nil {
			_ = c.gate.Abort(ctx, tx)
			return removed, ErrAuthorizationUnavailable
		}
		key := closureKey(candidate.id)
		var anchorState string
		if e = tx.QueryRow(ctx, `SELECT state FROM c_auth.request_results WHERE key_digest=$1 AND operation='CLOSURE'
			FOR UPDATE`, key[:]).Scan(&anchorState); e != nil {
			_ = c.gate.Abort(ctx, tx)
			return removed, ErrAuthorizationUnavailable
		}
		var deleted bool
		_, e = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
			eligible := state == "CANCELLED" && terminal != nil && !final.TrustedAt.Before(terminal.Add(closureStatusRetention))
			eligible = eligible || (state == "CLOSED_RELEASE_PENDING" && ack && released != nil && !final.TrustedAt.Before(released.Add(closureStatusRetention)))
			if !eligible {
				return nil
			}
			if _, err := tx.Exec(ctx, `UPDATE c_auth.request_results SET state='EXPIRED',request_hmac=NULL,hmac_key_version=NULL,
				intent_id=NULL,reset_intent_id=NULL,result_code=NULL,expires_at=NULL WHERE key_digest=$1 AND operation='CLOSURE' AND state='LIVE'`, key[:]); err != nil {
				return err
			}
			command, err := tx.Exec(ctx, `DELETE FROM c_auth.closure_requests WHERE closure_id=$1`, candidate.id[:])
			if err != nil {
				return err
			}
			deleted = command.RowsAffected() == 1
			return nil
		})
		_ = c.gate.Abort(ctx, tx)
		if e != nil {
			return removed, e
		}
		if deleted {
			removed++
		}
	}
	return removed, nil
}

func (c *Community) expireClosureResults(ctx context.Context, decision AuthorizationDecision, limit int) error {
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	keys, err := lockCleanupDigests(ctx, tx, `SELECT key_digest FROM c_auth.request_results
		WHERE operation='CLOSURE' AND state='LIVE' AND expires_at<=$1
		ORDER BY key_digest LIMIT $2 FOR UPDATE SKIP LOCKED`, decision.TrustedAt, limit)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		_, e := tx.Exec(ctx, `UPDATE c_auth.request_results SET state='EXPIRED',request_hmac=NULL,hmac_key_version=NULL,
			intent_id=NULL,reset_intent_id=NULL,result_code=NULL,expires_at=NULL
			WHERE key_digest=ANY($1::bytea[]) AND operation='CLOSURE' AND state='LIVE' AND expires_at<=$2`, keys, final.TrustedAt)
		return e
	})
	return err
}
