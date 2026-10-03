package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type OwnIdentity struct {
	ID uuid.UUID
	Nickname, Avatar string
	IsOriginal bool
	CreatedAt time.Time
	RenameAvailableAt *time.Time
}

type IdentityDirectory struct {
	Identities []OwnIdentity
	CreatedCount int64
	NextCreateAt *time.Time
	ServerTime, ExpiresAt time.Time
}

type IdentityChangeRequest struct {
	Bearer [32]byte
	ChangeID [16]byte
	Operation string
	IdentityID uuid.UUID
	Nickname string
}

type IdentityChangeResult struct {
	State, Operation, ErrorCode string
	IdentityID uuid.UUID
	ExpiresAt time.Time
}

// The callback has persisted a terminal business rejection. Commit its receipt
// under the Gate, but do not renew a request returned as an HTTP error.
var errIdentityRejectionRecorded = errors.New("identity rejection recorded")

// withIdentitySession shares the account -> restriction -> session -> Gate
// lock order with authentication. The account lock serializes every identity
// list, mutation and result query. Business reads and writes run only after the
// final Gate/session validation; rejected commands never renew the session.
func (c *Community) withIdentitySession(ctx context.Context, bearer [32]byte, action func(pgx.Tx, uuid.UUID, AuthorizationDecision) error) (time.Time, error) {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return time.Time{}, err
	}
	token := sha256.Sum256(bearer[:])
	var account uuid.UUID
	err = c.pool.QueryRow(ctx, `SELECT account_id FROM c_auth.sessions WHERE token_digest=$1`, token[:]).Scan(&account)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, ErrAuthorizationUnavailable
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return time.Time{}, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	a := credentialAccount{account: account}
	var session credentialSession
	if account != uuid.Nil {
		err = tx.QueryRow(ctx, `SELECT state,session_generation FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&a.state, &a.generation)
		if err != nil {
			return time.Time{}, ErrAuthorizationUnavailable
		}
		a.ban, err = lockRestriction(ctx, tx, account)
		if err != nil {
			return time.Time{}, ErrAuthorizationUnavailable
		}
		session, err = lockCredentialSession(ctx, tx, a, token)
		if err != nil && !errors.Is(err, ErrSessionInvalid) {
			return time.Time{}, ErrAuthorizationUnavailable
		}
	}
	var expires time.Time
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if account == uuid.Nil {
			return ErrSessionInvalid
		}
		if e := session.validate(a, final); e != nil {
			return e
		}
		if e := action(tx, account, final); e != nil {
			if errors.Is(e, errIdentityRejectionRecorded) {
				expires = session.expires
				return nil
			}
			return e
		}
		var e error
		expires, e = session.renew(ctx, tx, final.TrustedAt)
		if e != nil {
			return ErrAuthorizationUnavailable
		}
		return nil
	})
	if err != nil {
		return time.Time{}, err
	}
	return expires.UTC(), nil
}

func readIdentityCreationState(ctx context.Context, tx pgx.Tx, account uuid.UUID) (int64, *time.Time, error) {
	var count int64
	var last *time.Time
	err := tx.QueryRow(ctx, `SELECT created_count,last_created_at FROM public.identity_account_state WHERE account_id=$1`, account).Scan(&count, &last)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil, nil
	}
	if err != nil {
		return 0, nil, ErrAuthorizationUnavailable
	}
	return count, last, nil
}

func readOwnIdentities(ctx context.Context, tx pgx.Tx, account uuid.UUID) ([]OwnIdentity, error) {
	items := make([]OwnIdentity, 0, 3)
	rows, err := tx.Query(ctx, `SELECT identity_id,nickname,avatar,is_original,created_at,last_renamed_at FROM public.community_identities WHERE account_id=$1 AND deleted_at IS NULL ORDER BY created_at,identity_id LIMIT 4`, account)
	if err != nil {
		return nil, ErrAuthorizationUnavailable
	}
	defer rows.Close()
	for rows.Next() {
		var item OwnIdentity
		var renamed *time.Time
		if err := rows.Scan(&item.ID, &item.Nickname, &item.Avatar, &item.IsOriginal, &item.CreatedAt, &renamed); err != nil {
			return nil, ErrAuthorizationUnavailable
		}
		item.CreatedAt = item.CreatedAt.UTC()
		item.RenameAvailableAt = identityRenameAvailableAt(renamed)
		items = append(items, item)
	}
	if rows.Err() != nil || len(items) > 3 {
		return nil, ErrAuthorizationUnavailable
	}
	return items, nil
}

func (c *Community) ListOwnIdentities(ctx context.Context, bearer [32]byte) (IdentityDirectory, error) {
	var result IdentityDirectory
	expires, err := c.withIdentitySession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) error {
		var e error
		var last *time.Time
		result.CreatedCount, last, e = readIdentityCreationState(ctx, tx, account)
		if e != nil {
			return e
		}
		result.Identities, e = readOwnIdentities(ctx, tx, account)
		result.NextCreateAt = identityNextCreateAt(result.CreatedCount, last)
		result.ServerTime = final.TrustedAt.UTC()
		return e
	})
	if err != nil {
		return IdentityDirectory{}, err
	}
	result.ExpiresAt = expires
	return result, nil
}

func identityChangeKey(key [16]byte) [32]byte {
	return digest("HNUHOLE/IDENTITY-CHANGE-KEY/V1", key[:])
}

func readIdentityReceipt(ctx context.Context, tx pgx.Tx, account uuid.UUID, key [32]byte) (IdentityChangeResult, []byte, bool, error) {
	var result IdentityChangeResult
	var intent []byte
	var id *uuid.UUID
	var code *string
	err := tx.QueryRow(ctx, `SELECT state,operation,identity_id,error_code,intent_fingerprint FROM public.identity_change_receipts WHERE account_id=$1 AND change_key_digest=$2`, account, key[:]).Scan(&result.State, &result.Operation, &id, &code, &intent)
	if errors.Is(err, pgx.ErrNoRows) {
		return result, nil, false, nil
	}
	if err != nil {
		return result, nil, false, ErrAuthorizationUnavailable
	}
	if id != nil {
		result.IdentityID = *id
	}
	if code != nil {
		result.ErrorCode = *code
	}
	return result, intent, true, nil
}

func writeIdentityReceipt(ctx context.Context, tx pgx.Tx, account uuid.UUID, key, fingerprint [32]byte, result IdentityChangeResult, at time.Time) error {
	var id *uuid.UUID
	var code *string
	if result.State == "COMMITTED" {
		id = &result.IdentityID
	} else {
		code = &result.ErrorCode
	}
	_, err := tx.Exec(ctx, `INSERT INTO public.identity_change_receipts(account_id,change_key_digest,intent_fingerprint,state,operation,identity_id,error_code,committed_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, account, key[:], fingerprint[:], result.State, result.Operation, id, code, at)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	return nil
}

// NOT_FOUND describes only this serialized read. An original network request
// may reach the account lock later; clients must preserve and replay the same
// key and intent instead of treating absence as permission for a new command.
func (c *Community) GetIdentityChangeResult(ctx context.Context, bearer [32]byte, key [16]byte) (IdentityChangeResult, error) {
	var result IdentityChangeResult
	expires, err := c.withIdentitySession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) error {
		if key == ([16]byte{}) {
			return ErrIdentityChangeConflict
		}
		var e error
		var found bool
		result, _, found, e = readIdentityReceipt(ctx, tx, account, identityChangeKey(key))
		if e != nil {
			return e
		}
		if !found {
			result.State = "NOT_FOUND"
		}
		return nil
	})
	if err != nil {
		return IdentityChangeResult{}, err
	}
	result.ExpiresAt = expires
	return result, nil
}

func (c *Community) ChangeOwnIdentity(ctx context.Context, request IdentityChangeRequest) (IdentityChangeResult, error) {
	var result IdentityChangeResult
	var shapeErr, nameErr error
	name := request.Nickname
	switch request.Operation {
	case "CREATE":
		if request.IdentityID != uuid.Nil {
			shapeErr = ErrIdentityChangeConflict
		}
		name, nameErr = identityValidateRequestedName(name)
	case "RENAME":
		if request.IdentityID == uuid.Nil {
			shapeErr = ErrIdentityNotFound
		}
		name, nameErr = identityValidateRequestedName(name)
	case "DELETE":
		if request.IdentityID == uuid.Nil {
			shapeErr = ErrIdentityNotFound
		} else if name != "" {
			shapeErr = ErrIdentityChangeConflict
		}
	default:
		shapeErr = ErrIdentityChangeConflict
	}
	if request.ChangeID == ([16]byte{}) {
		shapeErr = ErrIdentityChangeConflict
	}
	key := identityChangeKey(request.ChangeID)
	fingerprint := requestMAC(c.requestKey, []byte("HNUHOLE/IDENTITY-INTENT/V1"), []byte(request.Operation), request.IdentityID[:], []byte(name))
	expires, err := c.withIdentitySession(ctx, request.Bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) error {
		if shapeErr != nil {
			return shapeErr
		}
		previous, bound, found, e := readIdentityReceipt(ctx, tx, account, key)
		if e != nil {
			return e
		}
		if found {
			if !hmac.Equal(bound, fingerprint[:]) {
				return ErrIdentityChangeConflict
			}
			result = previous
			if result.State == "REJECTED" {
				return errIdentityRejectionRecorded
			}
			return nil
		}
		// A stable business rejection binds this key forever. A delayed
		// original request cannot apply after a retry was rejected, even
		// when a later rename/delete/time change would make it admissible.
		reject := func(code string) error {
			result = IdentityChangeResult{State: "REJECTED", Operation: request.Operation, ErrorCode: code}
			if e := writeIdentityReceipt(ctx, tx, account, key, fingerprint, result, final.TrustedAt); e != nil {
				return e
			}
			return errIdentityRejectionRecorded
		}
		if nameErr != nil {
			return reject("IDENTITY_INVALID_NAME")
		}
		items, e := readOwnIdentities(ctx, tx, account)
		if e != nil {
			return e
		}
		createdCount, lastCreatedAt, e := readIdentityCreationState(ctx, tx, account)
		if e != nil {
			return e
		}
		var target *OwnIdentity
		for i := range items {
			if items[i].ID == request.IdentityID {
				target = &items[i]
			}
		}
		if request.Operation != "CREATE" && target == nil {
			return reject("IDENTITY_NOT_FOUND")
		}
		if request.Operation != "DELETE" {
			for _, item := range items {
				if item.ID != request.IdentityID && item.Nickname == name {
					return reject("IDENTITY_DUPLICATE_NAME")
				}
			}
		}
		result = IdentityChangeResult{State: "COMMITTED", Operation: request.Operation, IdentityID: request.IdentityID}
		switch request.Operation {
		case "CREATE":
			if len(items) >= 3 {
				return reject("IDENTITY_LIMIT")
			}
			if next := identityNextCreateAt(createdCount, lastCreatedAt); next != nil && final.TrustedAt.Before(*next) {
				return reject("IDENTITY_CREATE_COOLDOWN")
			}
			if createdCount == math.MaxInt64 {
				return reject("IDENTITY_LIMIT")
			}
			id, e := uuid.NewRandom()
			if e != nil {
				return ErrAuthorizationUnavailable
			}
			result.IdentityID = id
			if _, e = tx.Exec(ctx, `INSERT INTO public.identity_account_state(account_id,created_count,last_created_at) VALUES($1,1,$2) ON CONFLICT(account_id) DO UPDATE SET created_count=identity_account_state.created_count+1,last_created_at=EXCLUDED.last_created_at`, account, final.TrustedAt); e != nil {
				return ErrAuthorizationUnavailable
			}
			if _, e = tx.Exec(ctx, `INSERT INTO public.community_identities(identity_id,account_id,nickname,avatar,is_original,created_at) VALUES($1,$2,$3,$4,$5,$6)`, id, account, name, IdentityDefaultAvatar, createdCount == 0, final.TrustedAt); e != nil {
				return ErrAuthorizationUnavailable
			}
		case "RENAME":
			// An unchanged canonical nickname is a successful no-op. It can
			// be retried during cooldown and does not start or extend it.
			if target.Nickname != name {
				if target.RenameAvailableAt != nil && final.TrustedAt.Before(*target.RenameAvailableAt) {
					return reject("IDENTITY_RENAME_COOLDOWN")
				}
				if _, e = tx.Exec(ctx, `UPDATE public.community_identities SET nickname=$3,last_renamed_at=$4 WHERE account_id=$1 AND identity_id=$2 AND deleted_at IS NULL`, account, target.ID, name, final.TrustedAt); e != nil {
					return ErrAuthorizationUnavailable
				}
			}
		case "DELETE":
			if len(items) <= 1 {
				return reject("IDENTITY_LAST_REQUIRED")
			}
			// Preserve identity identity/ownership for later post and chat
			// projections, while removing the private nickname immediately.
			if _, e = tx.Exec(ctx, `UPDATE public.community_identities SET nickname=NULL,avatar=NULL,last_renamed_at=NULL,deleted_at=$3 WHERE account_id=$1 AND identity_id=$2 AND deleted_at IS NULL`, account, target.ID, final.TrustedAt); e != nil {
				return ErrAuthorizationUnavailable
			}
		}
		if e = writeIdentityReceipt(ctx, tx, account, key, fingerprint, result, final.TrustedAt); e != nil {
			return e
		}
		return nil
	})
	if err != nil {
		return IdentityChangeResult{}, err
	}
	result.ExpiresAt = expires
	return result, nil
}

func identityValidateRequestedName(name string) (string, error) {
	normal, err := ValidateIdentityNickname(name)
	if err != nil {
		// Preserve the exact failed payload in the keyed fingerprint;
		// different invalid names must not collapse to an empty string.
		return name, err
	}
	return normal, nil
}
