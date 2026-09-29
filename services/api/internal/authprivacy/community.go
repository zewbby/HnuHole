package authprivacy

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"errors"
	"fmt"
	"math/big"
	"regexp"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type Community struct {
	pool         *pgxpool.Pool
	verifier     *protocol.Verifier
	signingEpoch uint32
	requestKey   [32]byte
}

func NewCommunity(pool *pgxpool.Pool, verifier *protocol.Verifier, signingEpoch uint32, requestKey [32]byte) (*Community, error) {
	if pool == nil || verifier == nil || requestKey == ([32]byte{}) {
		return nil, errors.New("invalid community configuration")
	}
	return &Community{pool: pool, verifier: verifier, signingEpoch: signingEpoch, requestKey: requestKey}, nil
}

// PasswordMaterial is prepared by the trusted authentication boundary before
// taking SQL locks. This lab stores Argon2id output, not passwords; it does not
// expose a public password policy or login endpoint.
type PasswordMaterial struct {
	Hash              [32]byte
	Salt              [16]byte
	ParametersVersion int64
}

type SignupIntent struct {
	ID           protocol.IntentID
	Challenge    protocol.Challenge
	RecoveryCode string // returned once; never saved as a result or SQL column
}

var usernamePattern = regexp.MustCompile(`^[a-z][a-z0-9_]{5,23}$`)

func (c *Community) CreateSignupIntent(ctx context.Context, encodedTicket, username string, password PasswordMaterial, installation [16]byte) (SignupIntent, error) {
	var result SignupIntent
	if !usernamePattern.MatchString(username) || password.ParametersVersion < 1 || password.Salt == ([16]byte{}) || password.Hash == ([32]byte{}) {
		return result, ErrIntentInvalid
	}
	id, err := random32()
	if err != nil {
		return result, err
	}
	challenge, err := random32()
	if err != nil {
		return result, err
	}
	var secret [16]byte
	if _, err = rand.Read(secret[:]); err != nil {
		return result, err
	}
	code := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(secret[:])
	codeHash := digest("HNUHOLE/RECOVERY/V1", secret[:])
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return result, err
	}
	defer tx.Rollback(ctx)
	var at time.Time
	if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return result, err
	}
	ticket, err := c.verifier.VerifyRegistrationTicket(encodedTicket, at)
	if err != nil {
		return result, err
	}
	wire, err := protocol.DecodeCanonicalBase64url(encodedTicket, 156)
	if err != nil {
		return result, err
	}
	_, err = tx.Exec(ctx, `INSERT INTO c_auth.signup_intents
	(intent_id,challenge,ticket,slot_id,bootstrap_public_key,admission_window,username,password_hash,password_salt,password_params_version,recovery_digest,installation_id,created_at,expires_at,state,attempts)
	VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13::timestamptz+interval '10 minutes','OPEN',0)`, id[:], challenge[:], wire, ticket.Slot[:], ticket.BootstrapKey[:], int64(ticket.Window), username, password.Hash[:], password.Salt[:], password.ParametersVersion, codeHash[:], installation[:], at)
	if err != nil {
		return result, err
	}
	if err = tx.Commit(ctx); err != nil {
		return result, err
	}
	return SignupIntent{ID: protocol.IntentID(id), Challenge: protocol.Challenge(challenge), RecoveryCode: code}, nil
}

type SignupRequest struct {
	IntentID       protocol.IntentID
	Proof          string
	RecoveryCode   string
	IdempotencyKey [32]byte
}

type SignupResult struct {
	Created      bool
	Replay       bool
	SessionToken [32]byte // only first successful commit returns secrets
	RevokeSecret [32]byte
}

func (c *Community) CommitSignup(ctx context.Context, request SignupRequest) (SignupResult, error) {
	var result SignupResult
	confirmed, err := recoveryDigest(request.RecoveryCode)
	if err != nil {
		return result, err
	}
	if request.IdempotencyKey == ([32]byte{}) {
		return result, ErrIntentInvalid
	}
	proof, err := protocol.DecodeCanonicalBase64url(request.Proof, 64)
	if err != nil {
		return result, err
	}
	keyDigest := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", request.IdempotencyKey[:])
	mac := requestMAC(c.requestKey, []byte("SIGNUP"), request.IntentID[:], proof, confirmed[:])
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return result, err
	}
	defer tx.Rollback(ctx)
	// A prior committed request returns only a non-secret outcome. No new
	// authentication authority is granted by this idempotency replay.
	if replay, found, e := signupReplay(ctx, tx, keyDigest, mac); found || e != nil {
		return replay, e
	}
	var located []byte
	if err = tx.QueryRow(ctx, `SELECT slot_id FROM c_auth.signup_intents WHERE intent_id=$1 AND state='OPEN'`, request.IntentID[:]).Scan(&located); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			if replay, found, e := signupReplay(ctx, tx, keyDigest, mac); found || e != nil {
				return replay, e
			}
			return result, ErrIntentInvalid
		}
		return result, err
	}
	if err = lockSlot(ctx, tx, located); err != nil {
		return result, err
	}
	if replay, found, e := signupReplay(ctx, tx, keyDigest, mac); found || e != nil {
		return replay, e
	}
	var ticketBytes, challengeBytes, salt, hash, recovery, installation []byte
	var username string
	var params int64
	var expires time.Time
	err = tx.QueryRow(ctx, `SELECT ticket,challenge,username,password_hash,password_salt,password_params_version,recovery_digest,installation_id,expires_at FROM c_auth.signup_intents WHERE intent_id=$1 AND state='OPEN' FOR UPDATE`, request.IntentID[:]).Scan(&ticketBytes, &challengeBytes, &username, &hash, &salt, &params, &recovery, &installation, &expires)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			if replay, found, e := signupReplay(ctx, tx, keyDigest, mac); found || e != nil {
				return replay, e
			}
			return result, ErrIntentInvalid
		}
		return result, err
	}
	var at time.Time
	if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return result, err
	}
	if !at.Before(expires) || !hmac.Equal(confirmed[:], recovery) || len(challengeBytes) != 32 {
		return result, ErrIntentInvalid
	}
	ticket, err := c.verifier.VerifyRegistrationTicket(protocol.EncodeCanonicalBase64url(ticketBytes), at)
	if err != nil {
		return result, err
	}
	var challenge protocol.Challenge
	copy(challenge[:], challengeBytes)
	if !bytes.Equal(ticket.Slot[:], located) {
		return result, ErrIntentInvalid
	}
	if err = protocol.VerifyBootstrapProof(ticket, request.IntentID, challenge, request.Proof); err != nil {
		return result, err
	}
	var ledgerState string
	err = tx.QueryRow(ctx, `SELECT state FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`, located).Scan(&ledgerState)
	if err == nil {
		_, err = tx.Exec(ctx, `INSERT INTO c_auth.request_results(operation,key_digest,state,request_hmac,hmac_key_version,intent_id,result_code,expires_at) VALUES('SIGNUP',$1,'LIVE',$2,1,$3,'SLOT_UNAVAILABLE',$4::timestamptz+interval '7 days') ON CONFLICT(key_digest) DO NOTHING`, keyDigest[:], mac[:], request.IntentID[:], at)
		if err != nil {
			return result, err
		}
		if replay, found, e := signupReplay(ctx, tx, keyDigest, mac); e != nil && (!found || !errors.Is(e, ErrSlotUnavailable)) {
			return replay, e
		}
		if err = c.checkSignupDeadline(ctx, tx, ticketBytes, expires); err != nil {
			return result, err
		}
		if err = clearSignupIntent(ctx, tx, request.IntentID, "ABANDONED"); err != nil {
			return result, err
		}
		if err = tx.Commit(ctx); err != nil {
			return result, err
		}
		return result, ErrSlotUnavailable
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return result, err
	}
	// Claim the unique result anchor before creating an account. A concurrent
	// same-key request can only yield one committed command, across all slots.
	command, err := tx.Exec(ctx, `INSERT INTO c_auth.request_results(operation,key_digest,state,request_hmac,hmac_key_version,intent_id,result_code,expires_at) VALUES('SIGNUP',$1,'LIVE',$2,1,$3,'ACCOUNT_CREATED',$4::timestamptz+interval '7 days') ON CONFLICT (key_digest) DO NOTHING`, keyDigest[:], mac[:], request.IntentID[:], at)
	if err != nil {
		return result, err
	}
	if command.RowsAffected() != 1 {
		if replay, found, e := signupReplay(ctx, tx, keyDigest, mac); found || e != nil {
			return replay, e
		}
		return result, ErrConflict
	}
	if _, err = tx.Exec(ctx, `SAVEPOINT signup_account`); err != nil {
		return result, err
	}
	account, err := uuid.NewRandom()
	if err != nil {
		return result, err
	}
	inserted := false
	for attempt := 0; attempt < 32; attempt++ {
		platform, e := rand.Int(rand.Reader, big.NewInt(1000000))
		if e != nil {
			return result, e
		}
		command, e = tx.Exec(ctx, `INSERT INTO c_auth.accounts(account_id,platform_number,state,username,password_hash,password_salt,password_params_version,credential_version,session_generation) VALUES($1,$2,'ACTIVE',$3,$4,$5,$6,1,1) ON CONFLICT (platform_number) DO NOTHING`, account, fmt.Sprintf("%06d", platform.Int64()), username, hash, salt, params)
		if e != nil {
			var pgerr *pgconn.PgError
			if errors.As(e, &pgerr) && pgerr.Code == "23505" && pgerr.ConstraintName == "accounts_active_username_unique" {
				if _, err = tx.Exec(ctx, `ROLLBACK TO SAVEPOINT signup_account`); err != nil {
					return result, err
				}
				if err = c.checkSignupDeadline(ctx, tx, ticketBytes, expires); err != nil {
					return result, err
				}
				if err = clearSignupIntent(ctx, tx, request.IntentID, "ABANDONED"); err != nil {
					return result, err
				}
				if _, err = tx.Exec(ctx, `UPDATE c_auth.request_results SET result_code='USERNAME_UNAVAILABLE' WHERE key_digest=$1`, keyDigest[:]); err != nil {
					return result, err
				}
				if err = tx.Commit(ctx); err != nil {
					return result, err
				}
				return result, ErrUsernameTaken
			}
			return result, e
		}
		if command.RowsAffected() == 1 {
			inserted = true
			break
		}
	}
	if !inserted {
		return result, errors.New("platform number allocation exhausted")
	}
	if _, err = tx.Exec(ctx, `INSERT INTO c_auth.slot_ledger(slot_id,state,account_id) VALUES($1,'ACTIVE',$2)`, located, account); err != nil {
		return result, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO c_auth.recovery_codes(account_id,code_digest,activation_version) VALUES($1,$2,1)`, account, recovery); err != nil {
		return result, err
	}
	token, err := random32()
	if err != nil {
		return result, err
	}
	revoke := digest("HNUHOLE/SESSION-REVOKE/V1", token[:])
	// Tokens in this lab use the same capability digest boundary as the spec.
	tokenHash := sha256.Sum256(token[:])
	revokeHash := digest("HNUHOLE/REVOKE-STORAGE/V1", revoke[:])
	if _, err = tx.Exec(ctx, `INSERT INTO c_auth.sessions(token_digest,revoke_digest,account_id,installation_id,session_generation,created_at,last_activity_at,expires_at) VALUES($1,$2,$3,$4,1,$5,$5,$5::timestamptz+interval '30 days')`, tokenHash[:], revokeHash[:], account, installation, at); err != nil {
		return result, err
	}
	if err = clearSignupIntent(ctx, tx, request.IntentID, "CONSUMED"); err != nil {
		return result, err
	}
	// Uniqueness/FK waits above can cross an expiry boundary. Re-sample the
	// database clock after those waits and roll back the entire command if stale.
	if err = c.checkSignupDeadline(ctx, tx, ticketBytes, expires); err != nil {
		return result, err
	}
	if err = tx.Commit(ctx); err != nil {
		return result, err
	}
	return SignupResult{Created: true, SessionToken: token, RevokeSecret: revoke}, nil
}

func signupReplay(ctx context.Context, tx pgx.Tx, key, mac [32]byte) (SignupResult, bool, error) {
	var state, operation string
	var code *string
	var storedMAC []byte
	err := tx.QueryRow(ctx, `SELECT state,operation,request_hmac,result_code FROM c_auth.request_results WHERE key_digest=$1`, key[:]).Scan(&state, &operation, &storedMAC, &code)
	if errors.Is(err, pgx.ErrNoRows) {
		return SignupResult{}, false, nil
	}
	if err != nil {
		return SignupResult{}, false, err
	}
	if operation != "SIGNUP" {
		return SignupResult{}, true, ErrConflict
	}
	if state == "EXPIRED" {
		return SignupResult{}, true, ErrExpired
	}
	if !hmac.Equal(mac[:], storedMAC) {
		return SignupResult{}, true, ErrConflict
	}
	if code != nil && *code == "USERNAME_UNAVAILABLE" {
		return SignupResult{Replay: true}, true, ErrUsernameTaken
	}
	if code != nil && *code == "SLOT_UNAVAILABLE" {
		return SignupResult{Replay: true}, true, ErrSlotUnavailable
	}
	if code == nil || *code != "ACCOUNT_CREATED" {
		return SignupResult{}, true, ErrConflict
	}
	return SignupResult{Created: true, Replay: true}, true, nil
}

func clearSignupIntent(ctx context.Context, tx pgx.Tx, id protocol.IntentID, state string) error {
	_, err := tx.Exec(ctx, `UPDATE c_auth.signup_intents SET state=$2,challenge=NULL,ticket=NULL,slot_id=NULL,bootstrap_public_key=NULL,admission_window=NULL,username=NULL,password_hash=NULL,password_salt=NULL,password_params_version=NULL,recovery_digest=NULL,installation_id=NULL WHERE intent_id=$1`, id[:], state)
	return err
}

func (c *Community) checkSignupDeadline(ctx context.Context, tx pgx.Tx, ticket []byte, expires time.Time) error {
	var at time.Time
	if err := tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return err
	}
	if !at.Before(expires) {
		return ErrIntentInvalid
	}
	_, err := c.verifier.VerifyRegistrationTicket(protocol.EncodeCanonicalBase64url(ticket), at)
	return err
}

// RetireSlot commits a permanent terminal and pending outbox without invoking
// any signer. The authorization never grants control of an existing account.
func (c *Community) RetireSlot(ctx context.Context, encodedAuthorization string) error {
	auth, err := c.verifier.VerifyRetirementAuthorization(encodedAuthorization)
	if err != nil {
		return err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err = lockSlot(ctx, tx, auth.Slot[:]); err != nil {
		return err
	}
	var state string
	err = tx.QueryRow(ctx, `SELECT state FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`, auth.Slot[:]).Scan(&state)
	if err == nil {
		if state == "RETIRED" {
			return tx.Commit(ctx)
		}
		return ErrSlotUnavailable
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	receipt := protocol.Receipt{Purpose: protocol.PurposeRetired, Epoch: c.signingEpoch, Slot: auth.Slot}
	message, err := receipt.MessageBytes()
	if err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO c_auth.slot_ledger(slot_id,state) VALUES($1,'RETIRED')`, auth.Slot[:]); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO c_auth.receipt_outbox(slot_id,purpose,receipt_message,signing_key_epoch,state) VALUES($1,'RETIRED',$2,$3,'PENDING_SIGN')`, auth.Slot[:], message, int64(c.signingEpoch)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
