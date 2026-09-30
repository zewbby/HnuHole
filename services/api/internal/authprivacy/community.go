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
	pool          *pgxpool.Pool
	verifier      *protocol.Verifier
	gate          AuthorizationGate
	signingEpoch  uint32
	requestKey    [32]byte
	receiptSigner Signer
}

func NewCommunity(pool *pgxpool.Pool, verifier *protocol.Verifier, signingEpoch uint32, requestKey [32]byte, gate AuthorizationGate) (*Community, error) {
	if pool == nil || verifier == nil || requestKey == ([32]byte{}) || gate == nil {
		return nil, errors.New("invalid community configuration")
	}
	return &Community{pool: pool, verifier: verifier, gate: gate, signingEpoch: signingEpoch, requestKey: requestKey}, nil
}

// NewCommunityWithReceiptSigner additionally enables post-commit receipt work
// and read-only re-signing after acknowledged delivery material is cleaned.
func NewCommunityWithReceiptSigner(pool *pgxpool.Pool, verifier *protocol.Verifier, signingEpoch uint32, requestKey [32]byte, signer Signer, gate AuthorizationGate) (*Community, error) {
	if signer == nil {
		return nil, errors.New("receipt signer is required")
	}
	c, err := NewCommunity(pool, verifier, signingEpoch, requestKey, gate)
	if err != nil {
		return nil, err
	}
	c.receiptSigner = signer
	return c, nil
}

// PasswordMaterial is prepared by the trusted authentication boundary before
// taking SQL locks. The session slice verifies this material through the same
// bounded Argon2id worker and never stores the submitted password.
type PasswordMaterial struct {
	Hash              [32]byte
	Salt              [16]byte
	ParametersVersion int64
}

type SignupIntent struct {
	ID           protocol.IntentID
	Challenge    protocol.Challenge
	ExpiresAt    time.Time
	RecoveryCode string // returned once; never saved as a result or SQL column
}

var usernamePattern = regexp.MustCompile(`^[a-z][a-z0-9_]{5,23}$`)

// ValidateSignupTicket obtains the generation before scheduling expensive
// password work. The trusted boundary carries that generation into the intent;
// it is never accepted from a public request or replaced after password work.
func (c *Community) ValidateSignupTicket(ctx context.Context, encoded string) (AuthorizationDecision, error) {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return AuthorizationDecision{}, err
	}
	_, err = c.verifier.VerifyRegistrationTicket(encoded, decision.TrustedAt)
	return decision, err
}

func (c *Community) CreateSignupIntent(ctx context.Context, encodedTicket, username string, password PasswordMaterial, installation [16]byte, expectedGeneration uint64) (SignupIntent, error) {
	var result SignupIntent
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return result, err
	}
	if expectedGeneration == 0 || decision.Generation != expectedGeneration {
		return result, ErrAuthorizationUnavailable
	}
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
	defer c.gate.Abort(ctx, tx)
	at := decision.TrustedAt
	ticket, err := c.verifier.VerifyRegistrationTicket(encodedTicket, at)
	if err != nil {
		return result, err
	}
	wire, err := protocol.DecodeCanonicalBase64url(encodedTicket, 156)
	if err != nil {
		return result, err
	}
	_, err = tx.Exec(ctx, `INSERT INTO c_auth.signup_intents
	(intent_id,challenge,ticket,slot_id,bootstrap_public_key,admission_window,username,password_hash,password_salt,password_params_version,recovery_digest,installation_id,created_at,expires_at,state,attempts,authorization_generation)
	VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13::timestamptz+interval '10 minutes','OPEN',0,$14)`, id[:], challenge[:], wire, ticket.Slot[:], ticket.BootstrapKey[:], int64(ticket.Window), username, password.Hash[:], password.Salt[:], password.ParametersVersion, codeHash[:], installation[:], at, int64(expectedGeneration))
	if err != nil {
		return result, err
	}
	if _, err = c.gate.CommitAuthorized(ctx, tx, expectedGeneration, func(final AuthorizationDecision) error {
		_, e := c.verifier.VerifyRegistrationTicket(encodedTicket, final.TrustedAt)
		return e
	}); err != nil {
		return result, err
	}
	return SignupIntent{ID: protocol.IntentID(id), Challenge: protocol.Challenge(challenge), ExpiresAt: at.Add(10 * time.Minute), RecoveryCode: code}, nil
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
	AccountID    uuid.UUID
	ExpiresAt    time.Time
	SessionToken [32]byte // only first successful commit returns secrets
	RevokeSecret [32]byte
}

func (c *Community) CommitSignup(ctx context.Context, request SignupRequest) (SignupResult, error) {
	var result SignupResult
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return result, err
	}
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
	defer c.gate.Abort(ctx, tx)
	// A prior committed request returns only a non-secret outcome. No new
	// authentication authority is granted by this idempotency replay. It still
	// checks the current gate at its final response point, including after waits.
	finishReplay := func(replay SignupResult, replayErr error) (SignupResult, error) {
		if _, e := c.gate.CommitAuthorized(ctx, tx, decision.Generation); e != nil {
			return SignupResult{}, e
		}
		return replay, replayErr
	}
	if replay, found, e := signupReplay(ctx, tx, keyDigest, mac); found || e != nil {
		if found {
			return finishReplay(replay, e)
		}
		return replay, e
	}
	var located []byte
	if err = tx.QueryRow(ctx, `SELECT slot_id FROM c_auth.signup_intents WHERE intent_id=$1 AND state='OPEN'`, request.IntentID[:]).Scan(&located); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			if replay, found, e := signupReplay(ctx, tx, keyDigest, mac); found || e != nil {
				if found {
					return finishReplay(replay, e)
				}
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
		if found {
			return finishReplay(replay, e)
		}
		return replay, e
	}
	var ticketBytes, challengeBytes, salt, hash, recovery, installation []byte
	var username string
	var params, generation int64
	var expires time.Time
	err = tx.QueryRow(ctx, `SELECT ticket,challenge,username,password_hash,password_salt,password_params_version,recovery_digest,installation_id,expires_at,authorization_generation FROM c_auth.signup_intents WHERE intent_id=$1 AND state='OPEN' FOR UPDATE`, request.IntentID[:]).Scan(&ticketBytes, &challengeBytes, &username, &hash, &salt, &params, &recovery, &installation, &expires, &generation)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			if replay, found, e := signupReplay(ctx, tx, keyDigest, mac); found || e != nil {
				if found {
					return finishReplay(replay, e)
				}
				return replay, e
			}
			return result, ErrIntentInvalid
		}
		return result, err
	}
	if generation <= 0 || uint64(generation) != decision.Generation {
		return result, ErrAuthorizationUnavailable
	}
	expectedGeneration := uint64(generation)
	at := decision.TrustedAt
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
		if err = clearSignupIntent(ctx, tx, request.IntentID, "ABANDONED"); err != nil {
			return result, err
		}
		if _, err = c.gate.CommitAuthorized(ctx, tx, expectedGeneration, func(final AuthorizationDecision) error {
			return c.validateSignupDeadline(ticketBytes, expires, final.TrustedAt)
		}); err != nil {
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
			if found {
				return finishReplay(replay, e)
			}
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
				if err = clearSignupIntent(ctx, tx, request.IntentID, "ABANDONED"); err != nil {
					return result, err
				}
				if _, err = tx.Exec(ctx, `UPDATE c_auth.request_results SET result_code='USERNAME_UNAVAILABLE' WHERE key_digest=$1`, keyDigest[:]); err != nil {
					return result, err
				}
				if _, err = c.gate.CommitAuthorized(ctx, tx, expectedGeneration, func(final AuthorizationDecision) error {
					return c.validateSignupDeadline(ticketBytes, expires, final.TrustedAt)
				}); err != nil {
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
	if _, err = tx.Exec(ctx, `INSERT INTO c_auth.sessions(token_digest,revoke_digest,account_id,installation_id,session_generation,created_at,last_activity_at,expires_at,authorization_generation) VALUES($1,$2,$3,$4,1,$5,$5,$5::timestamptz+interval '30 days',$6)`, tokenHash[:], revokeHash[:], account, installation, at, generation); err != nil {
		return result, err
	}
	if err = clearSignupIntent(ctx, tx, request.IntentID, "CONSUMED"); err != nil {
		return result, err
	}
	// All provisional writes and uniqueness/FK waits precede this final gate
	// decision. A freeze or recovery during those waits rolls back every grant.
	decision, err = c.gate.CommitAuthorized(ctx, tx, expectedGeneration, func(final AuthorizationDecision) error {
		if e := c.validateSignupDeadline(ticketBytes, expires, final.TrustedAt); e != nil {
			return e
		}
		_, e := tx.Exec(ctx, `UPDATE c_auth.sessions SET created_at=$2,last_activity_at=$2,expires_at=$2::timestamptz+interval '30 days' WHERE token_digest=$1`, tokenHash[:], final.TrustedAt)
		return e
	})
	if err != nil {
		return result, err
	}
	at = decision.TrustedAt
	return SignupResult{Created: true, AccountID: account, ExpiresAt: at.Add(30 * 24 * time.Hour), SessionToken: token, RevokeSecret: revoke}, nil
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

func (c *Community) validateSignupDeadline(ticket []byte, expires, at time.Time) error {
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
