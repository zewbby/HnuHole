package authprivacy

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type VerifierStore struct {
	pool           *pgxpool.Pool
	verifier       *protocol.Verifier
	addressLockKey [32]byte
	gate           AuthorizationGate
}

func NewVerifierStore(pool *pgxpool.Pool, verifier *protocol.Verifier, lockKey [32]byte, gate AuthorizationGate) (*VerifierStore, error) {
	if pool == nil || verifier == nil || lockKey == ([32]byte{}) || gate == nil || (reflect.ValueOf(gate).Kind() == reflect.Pointer && reflect.ValueOf(gate).IsNil()) {
		return nil, errors.New("invalid verifier configuration")
	}
	if postgresGate, ok := gate.(*PostgresAuthorizationGate); ok && postgresGate.schema != "v_auth" {
		return nil, errors.New("verifier requires an independent v_auth gate")
	}
	if postgresGate, ok := gate.(*PostgresAuthorizationGate); ok && postgresGate.pool == pool {
		return nil, errors.New("verifier gate refresh requires a separate bounded pool")
	}
	return &VerifierStore{pool: pool, verifier: verifier, addressLockKey: lockKey, gate: gate}, nil
}

// Every V transaction takes its generation before acquiring any business lock.
// Commit always rechecks the gate in that same transaction. Abort also persists
// a freeze discovered during a failed operation, rather than rolling it away.
type verifierAuthorizationTx struct {
	pgx.Tx
	gate     AuthorizationGate
	decision AuthorizationDecision
	checks   []func(AuthorizationDecision) error
}

func (v *VerifierStore) beginAuthorized(ctx context.Context) (pgx.Tx, error) {
	decision, err := v.gate.Snapshot(ctx)
	if err != nil {
		return nil, err
	}
	tx, err := begin(ctx, v.pool)
	if err != nil {
		return nil, err
	}
	return &verifierAuthorizationTx{Tx: tx, gate: v.gate, decision: decision}, nil
}

func (t *verifierAuthorizationTx) Commit(ctx context.Context) error {
	_, err := t.gate.CommitAuthorized(ctx, t.Tx, t.decision.Generation, t.checks...)
	return err
}

func (t *verifierAuthorizationTx) Rollback(ctx context.Context) error {
	return t.gate.Abort(ctx, t.Tx)
}

func verifierGeneration(tx pgx.Tx) uint64 {
	if t, ok := tx.(*verifierAuthorizationTx); ok {
		return t.decision.Generation
	}
	return 0
}

func verifierTrustedAt(ctx context.Context, tx pgx.Tx, at *time.Time) error {
	t, ok := tx.(*verifierAuthorizationTx)
	if !ok {
		return ErrAuthorizationUnavailable
	}
	// V takes the gate row only at final Commit. This independent refresh
	// therefore cannot self-lock or hold the gate across later business waits.
	// Final validators still receive the final authority time under that lock.
	decision, err := t.gate.Snapshot(ctx)
	if err == nil && decision.Generation != t.decision.Generation {
		err = ErrAuthorizationUnavailable
	}
	if err == nil {
		*at = decision.TrustedAt
	}
	return err
}

// trustedSQLTime is a bound parameter supplied by the V gate, never a SQL clock
// function. This small template keeps worker predicates and updates on the same
// authority time while retaining their existing numbered argument lists.
const trustedSQLTime = "{trusted_at}"

func bindVerifierTime(sql string, args []any, at time.Time) (string, []any) {
	if !strings.Contains(sql, trustedSQLTime) {
		return sql, args
	}
	return strings.ReplaceAll(sql, trustedSQLTime, fmt.Sprintf("$%d::timestamptz", len(args)+1)), append(args, at)
}

func (t *verifierAuthorizationTx) timedSQL(ctx context.Context, sql string, args []any) (string, []any, error) {
	if !strings.Contains(sql, trustedSQLTime) {
		return sql, args, nil
	}
	var at time.Time
	if err := verifierTrustedAt(ctx, t, &at); err != nil {
		return "", nil, err
	}
	sql, args = bindVerifierTime(sql, args, at)
	return sql, args, nil
}

func (t *verifierAuthorizationTx) Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
	sql, args, err := t.timedSQL(ctx, sql, args)
	if err != nil {
		return pgconn.CommandTag{}, err
	}
	return t.Tx.Exec(ctx, sql, args...)
}

func (t *verifierAuthorizationTx) Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error) {
	sql, args, err := t.timedSQL(ctx, sql, args)
	if err != nil {
		return nil, err
	}
	return t.Tx.Query(ctx, sql, args...)
}

type verifierErrorRow struct{ err error }

func (r verifierErrorRow) Scan(...any) error { return r.err }

func (t *verifierAuthorizationTx) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	sql, args, err := t.timedSQL(ctx, sql, args)
	if err != nil {
		return verifierErrorRow{err}
	}
	return t.Tx.QueryRow(ctx, sql, args...)
}

// Candidate enumeration is only a hint. Each candidate is rechecked and
// committed by beginAuthorized under its own business locks.
func (v *VerifierStore) queryCandidates(ctx context.Context, sql string, args ...any) (pgx.Rows, error) {
	decision, err := v.gate.Snapshot(ctx)
	if err != nil {
		return nil, err
	}
	sql, args = bindVerifierTime(sql, args, decision.TrustedAt)
	return v.pool.Query(ctx, sql, args...)
}

func (v *VerifierStore) execAuthorized(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
	tx, err := v.beginAuthorized(ctx)
	if err != nil {
		return pgconn.CommandTag{}, err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, sql, args...)
	if err != nil {
		return tag, err
	}
	return tag, tx.Commit(ctx)
}

func (v *VerifierStore) lockAddress(ctx context.Context, tx pgx.Tx, email []byte) error {
	h := hmac.New(sha256.New, v.addressLockKey[:])
	h.Write([]byte("HNUHOLE/V-EMAIL-LOCK/V1\x00"))
	h.Write(email)
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, int64(binary.BigEndian.Uint64(h.Sum(nil)[:8])))
	return err
}

// ReserveAfterQualification is an internal lab storage command using synthetic
// preverified eligibility. A production adapter must compose OTP consumption
// and quota reservation in one transaction, not call this after a separate OTP
// commit. The real eligibility boundary uses ConfirmOTP's combined transaction;
// this synthetic helper must never be used as a public qualification endpoint.
func (v *VerifierStore) ReserveAfterQualification(ctx context.Context, email []byte, key protocol.PublicKey) (protocol.SlotID, error) {
	slot, err := protocol.DeriveSlot(key)
	if err != nil {
		return slot, err
	}
	s := string(email)
	if !utf8.Valid(email) || strings.Count(s, "@") != 1 || !strings.HasSuffix(s, "@hainanu.edu.cn") || len(s) == len("@hainanu.edu.cn") || strings.IndexFunc(s, unicode.IsSpace) >= 0 {
		return slot, ErrIntentInvalid
	}
	tx, err := v.beginAuthorized(ctx)
	if err != nil {
		return slot, err
	}
	defer tx.Rollback(ctx)
	if err = v.lockAddress(ctx, tx, email); err != nil {
		return slot, err
	}
	var current []byte
	err = tx.QueryRow(ctx, `SELECT current_slot FROM v_auth.email_quota WHERE email_exact=$1 FOR UPDATE`, email).Scan(&current)
	if err == nil {
		if !bytes.Equal(current, slot[:]) {
			return slot, ErrSlotUnavailable
		}
		var pending bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.retire_pending WHERE old_slot=$1)`, current).Scan(&pending); err != nil {
			return slot, err
		}
		if pending {
			return slot, ErrSlotUnavailable
		}
		return slot, tx.Commit(ctx)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return slot, err
	}
	var state string
	err = tx.QueryRow(ctx, `SELECT state FROM v_auth.used_slots WHERE slot_id=$1 FOR UPDATE`, slot[:]).Scan(&state)
	if err == nil {
		return slot, ErrSlotUnavailable
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return slot, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.used_slots(slot_id,state,version) VALUES($1,'RESERVED',1)`, slot[:]); err != nil {
		return slot, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.email_quota(email_exact,current_slot,bootstrap_public_key,quota_version) VALUES($1,$2,$3,1)`, email, slot[:], key[:]); err != nil {
		return slot, err
	}
	return slot, tx.Commit(ctx)
}

// PrepareRetirement is a synthetic lab command with a pre-signed authorization.
// ConfirmOTP instead persists the original confirmation and fixed signing job
// before calling the signer or C, so that its admission window survives retries.
func (v *VerifierStore) PrepareRetirement(ctx context.Context, email []byte, newKey protocol.PublicKey, encodedAuthorization string) error {
	auth, err := v.verifier.VerifyRetirementAuthorization(encodedAuthorization)
	if err != nil {
		return err
	}
	newSlot, err := protocol.DeriveSlot(newKey)
	if err != nil {
		return err
	}
	if newSlot == auth.Slot {
		return ErrConflict
	}
	wire, err := protocol.DecodeCanonicalBase64url(encodedAuthorization, 123)
	if err != nil {
		return err
	}
	tx, err := v.beginAuthorized(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err = v.lockAddress(ctx, tx, email); err != nil {
		return err
	}
	var current []byte
	var version int64
	if err = tx.QueryRow(ctx, `SELECT current_slot,quota_version FROM v_auth.email_quota WHERE email_exact=$1 FOR UPDATE`, email).Scan(&current, &version); err != nil {
		return err
	}
	if !bytes.Equal(current, auth.Slot[:]) {
		return ErrReconciliation
	}
	var state string
	if err = tx.QueryRow(ctx, `SELECT state FROM v_auth.used_slots WHERE slot_id=$1 FOR UPDATE`, current).Scan(&state); err != nil {
		return err
	}
	if state != "RESERVED" {
		return ErrReconciliation
	}
	var boundNew, boundKey []byte
	var pendingGeneration uint64
	err = tx.QueryRow(ctx, `SELECT new_slot,new_bootstrap_public_key,authorization_generation FROM v_auth.retire_pending WHERE old_slot=$1 FOR UPDATE`, current).Scan(&boundNew, &boundKey, &pendingGeneration)
	if err == nil {
		if pendingGeneration == 0 || pendingGeneration != verifierGeneration(tx) {
			return ErrAuthorizationUnavailable
		}
		if !bytes.Equal(boundNew, newSlot[:]) || !bytes.Equal(boundKey, newKey[:]) {
			return ErrConflict
		}
		return tx.Commit(ctx)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO v_auth.retire_pending(old_slot,email_exact,quota_version,new_slot,new_bootstrap_public_key,retirement_authorization,state,authorization_generation) VALUES($1,$2,$3,$4,$5,$6,'PENDING',$7)`, current, email, version, newSlot[:], newKey[:], wire, int64(verifierGeneration(tx)))
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// ProcessReceipt returns success only after the V transaction is durably
// committed. All duplicates verify current trust first; no duplicate can clear
// a later reservation. Purpose, not a signature's bytes or epoch, is the key.
func (v *VerifierStore) ProcessReceipt(ctx context.Context, encoded string, purpose protocol.Purpose) error {
	receipt, err := v.verifier.VerifyReceipt(encoded, purpose)
	if err != nil {
		return err
	}
	var email []byte
	err = v.pool.QueryRow(ctx, `SELECT email_exact FROM v_auth.email_quota WHERE current_slot=$1`, receipt.Slot[:]).Scan(&email)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	tx, err := v.beginAuthorized(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var current []byte
	var quotaVersion int64
	if len(email) > 0 {
		if err = v.lockAddress(ctx, tx, email); err != nil {
			return err
		}
		err = tx.QueryRow(ctx, `SELECT current_slot,quota_version FROM v_auth.email_quota WHERE email_exact=$1 FOR UPDATE`, email).Scan(&current, &quotaVersion)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
	}
	var state string
	var slotVersion int64
	err = tx.QueryRow(ctx, `SELECT state,version FROM v_auth.used_slots WHERE slot_id=$1 FOR UPDATE`, receipt.Slot[:]).Scan(&state, &slotVersion)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrReconciliation
	}
	if err != nil {
		return err
	}
	var processed string
	err = tx.QueryRow(ctx, `SELECT purpose FROM v_auth.processed_receipts WHERE slot_id=$1`, receipt.Slot[:]).Scan(&processed)
	if err == nil {
		if processed != sqlPurpose(purpose) {
			return ErrReconciliation
		}
		return tx.Commit(ctx)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if state != "RESERVED" || !bytes.Equal(current, receipt.Slot[:]) {
		return ErrReconciliation
	}
	if purpose == protocol.PurposeRetired {
		var pendingEmail []byte
		var pendingVersion int64
		if err = tx.QueryRow(ctx, `SELECT email_exact,quota_version FROM v_auth.retire_pending WHERE old_slot=$1 FOR UPDATE`, receipt.Slot[:]).Scan(&pendingEmail, &pendingVersion); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrReconciliation
			}
			return err
		}
		if !bytes.Equal(email, pendingEmail) || pendingVersion != quotaVersion {
			return ErrReconciliation
		}
	}
	if _, err = tx.Exec(ctx, `DELETE FROM v_auth.retire_pending WHERE old_slot=$1`, receipt.Slot[:]); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `DELETE FROM v_auth.email_quota WHERE email_exact=$1 AND current_slot=$2 AND quota_version=$3`, email, receipt.Slot[:], quotaVersion); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE v_auth.used_slots SET state=$1,version=version+1 WHERE slot_id=$2`, sqlPurpose(purpose), receipt.Slot[:]); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.processed_receipts(slot_id,purpose,version) VALUES($1,$2,$3)`, receipt.Slot[:], sqlPurpose(purpose), slotVersion+1); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// External work is outside database locks. Its fixed durable generation is
// checked immediately before and after external effects, then again by the
// transaction that records their result. Recovery never rebinds an old job.
func (v *VerifierStore) checkExternalGeneration(ctx context.Context, expected uint64) error {
	decision, err := v.gate.Snapshot(ctx)
	if err != nil {
		return err
	}
	if expected == 0 || decision.Generation != expected {
		return ErrAuthorizationUnavailable
	}
	return nil
}

func verifierFinalCheck(tx pgx.Tx, check func(AuthorizationDecision) error) error {
	t, ok := tx.(*verifierAuthorizationTx)
	if !ok || check == nil {
		return ErrAuthorizationUnavailable
	}
	t.checks = append(t.checks, check)
	return nil
}
