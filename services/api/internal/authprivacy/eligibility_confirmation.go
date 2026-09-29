package authprivacy

import (
	"bytes"
	"context"
	"crypto/hmac"
	"encoding/binary"
	"errors"
	"math"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

const confirmationOperation = "OTP_CONFIRMATION"

// Address locks always precede this lock on mutations. Read-only result queries
// do not acquire an address lock after acquiring a request lock.
func lockVRequest(ctx context.Context, tx pgx.Tx, key [32]byte) error {
	d := digest("HNUHOLE/V-REQUEST-LOCK/V1", key[:])
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, int64(binary.BigEndian.Uint64(d[:8])))
	return err
}

type confirmationAnchor struct {
	Operation string
	State     string
	MAC       []byte
	Flow      []byte
	Install   []byte
	Code      *string
	ExpiresAt *time.Time
}

type confirmationRecord struct {
	Key          [32]byte
	Flow         [32]byte
	Install      [16]byte
	Email        []byte
	NewSlot      protocol.SlotID
	BootstrapKey protocol.PublicKey
	OldSlot      []byte
	OldVersion   *int64
	VerifiedAt   time.Time
	OTPExpiresAt time.Time
	Window       uint32
	Epoch        uint32
	State        string
	CommittedAt  *time.Time
	ReplayUntil  *time.Time
}

type confirmationQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func readConfirmationAnchor(ctx context.Context, q confirmationQuerier, key [32]byte, lock bool) (confirmationAnchor, error) {
	query := `SELECT operation,state,request_hmac,flow_id,installation_id,result_code,expires_at FROM v_auth.request_results WHERE key_digest=$1`
	if lock {
		query += ` FOR UPDATE`
	}
	var a confirmationAnchor
	err := q.QueryRow(ctx, query, key[:]).Scan(&a.Operation, &a.State, &a.MAC, &a.Flow, &a.Install, &a.Code, &a.ExpiresAt)
	return a, err
}

func readConfirmation(ctx context.Context, q confirmationQuerier, key [32]byte, lock bool) (confirmationRecord, error) {
	query := `SELECT flow_id,installation_id,email_exact,new_slot,new_bootstrap_public_key,old_slot,old_quota_version,verified_at,verified_otp_expires_at,admission_window,signing_key_epoch,state,qualification_committed_at,ticket_replay_until FROM v_auth.otp_confirmations WHERE confirmation_key_digest=$1`
	if lock {
		query += ` FOR UPDATE`
	}
	r := confirmationRecord{Key: key}
	var flow, install, slot, public []byte
	var window, epoch int64
	err := q.QueryRow(ctx, query, key[:]).Scan(&flow, &install, &r.Email, &slot, &public, &r.OldSlot, &r.OldVersion, &r.VerifiedAt, &r.OTPExpiresAt, &window, &epoch, &r.State, &r.CommittedAt, &r.ReplayUntil)
	if err != nil {
		return r, err
	}
	if !((len(flow) == 32 && len(install) == 16) || (len(flow) == 0 && len(install) == 0)) || len(slot) != 32 || len(public) != 32 || window < 0 || window > math.MaxUint32 || epoch < 0 || epoch > math.MaxUint32 {
		return r, ErrReconciliation
	}
	copy(r.Flow[:], flow)
	copy(r.Install[:], install)
	copy(r.NewSlot[:], slot)
	copy(r.BootstrapKey[:], public)
	r.Window, r.Epoch = uint32(window), uint32(epoch)
	return r, nil
}

func confirmationMAC(e *Eligibility, req ConfirmOTPRequest) [32]byte {
	return requestMAC(e.config.RequestHMACKey, []byte(confirmationOperation), req.FlowID[:], req.InstallationID[:], []byte(req.OTP), req.SlotID[:], req.BootstrapPublicKey[:], []byte(req.ReleaseReceipt))
}

func validOTPShape(otp string) bool {
	if len(otp) != 6 {
		return false
	}
	for i := range otp {
		if otp[i] < '0' || otp[i] > '9' {
			return false
		}
	}
	return true
}

func expectedOTPError(err error) bool {
	return errors.Is(err, ErrOTPInvalid) || errors.Is(err, ErrOTPExpired) || errors.Is(err, ErrOTPReplaced) || errors.Is(err, ErrOTPFlowInvalid) || errors.Is(err, ErrRateLimited)
}

func (e *Eligibility) insertConfirmationAnchor(ctx context.Context, tx pgx.Tx, req ConfirmOTPRequest, key, mac [32]byte, code string, at time.Time) error {
	_, err := tx.Exec(ctx, `INSERT INTO v_auth.request_results(operation,key_digest,state,request_hmac,hmac_key_version,installation_id,flow_id,result_code,expires_at) VALUES($1,$2,'LIVE',$3,$4,$5,$6,$7,$8::timestamptz+interval '10 minutes')`, confirmationOperation, key[:], mac[:], e.config.HMACKeyVersion, req.InstallationID[:], req.FlowID[:], code, at)
	return err
}

func (e *Eligibility) ConfirmOTP(ctx context.Context, req ConfirmOTPRequest) (ConfirmationResult, error) {
	if req.Key == ([32]byte{}) || req.FlowID == ([32]byte{}) || req.InstallationID == ([16]byte{}) || !validOTPShape(req.OTP) {
		return ConfirmationResult{}, ErrBadRequest
	}
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", req.Key[:])
	mac := confirmationMAC(e, req)
	// A permanent expired anchor wins even if its flow or private bindings have
	// already been erased. A live replay never consumes/counts the OTP again.
	a, err := readConfirmationAnchor(ctx, e.store.pool, key, false)
	if err == nil {
		if err = authenticateConfirmationAnchor(a, mac); err != nil {
			return ConfirmationResult{}, err
		}
		return e.advanceConfirmation(ctx, key)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return ConfirmationResult{}, err
	}
	slot, err := protocol.DeriveSlot(req.BootstrapPublicKey)
	if err != nil {
		return ConfirmationResult{}, ErrBootstrapKeyInvalid
	}
	if slot != req.SlotID {
		return ConfirmationResult{}, ErrSlotBindingInvalid
	}
	email, err := e.lookupOTPFlowEmail(ctx, req.FlowID)
	if err != nil {
		return ConfirmationResult{}, err
	}
	tx, err := begin(ctx, e.store.pool)
	if err != nil {
		return ConfirmationResult{}, err
	}
	defer tx.Rollback(ctx)
	if err = e.store.lockAddress(ctx, tx, email); err != nil {
		return ConfirmationResult{}, err
	}
	if err = lockVRequest(ctx, tx, key); err != nil {
		return ConfirmationResult{}, err
	}
	a, err = readConfirmationAnchor(ctx, tx, key, true)
	if err == nil {
		if err = authenticateConfirmationAnchor(a, mac); err != nil {
			return ConfirmationResult{}, err
		}
		if err = tx.Commit(ctx); err != nil {
			return ConfirmationResult{}, err
		}
		return e.advanceConfirmation(ctx, key)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return ConfirmationResult{}, err
	}
	var at time.Time
	if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return ConfirmationResult{}, err
	}
	verified, err := e.verifyOTPInTx(ctx, tx, req, at)
	if err != nil {
		if !expectedOTPError(err) {
			return ConfirmationResult{}, err
		}
		var rejected *EligibilityError
		if !errors.As(err, &rejected) {
			return ConfirmationResult{}, err
		}
		// Only attempts accepted for an actual OTP decision allocate permanent
		// keys. Unknown/wrong installations, exhausted budgets, and already
		// locked devices cannot mint unbounded tombstones for arbitrary keys.
		if verified.AttemptCounted {
			if err = e.insertConfirmationAnchor(ctx, tx, req, key, mac, rejected.Code, at); err != nil {
				return ConfirmationResult{}, err
			}
			if rejected.Code == "RATE_LIMITED" {
				// The helper still holds this device row's lock. Save its actual
				// original expiry in this transaction, rather than a rounded
				// duration or a new deadline calculated during replay.
				device := e.deviceEmailDigest(email)
				var until *time.Time
				if err = tx.QueryRow(ctx, `SELECT locked_until FROM v_auth.device_email_limits WHERE installation_id=$1 AND email_digest=$2`, req.InstallationID[:], device[:]).Scan(&until); err != nil {
					return ConfirmationResult{}, err
				}
				if until == nil {
					return ConfirmationResult{}, ErrReconciliation
				}
				if _, err = tx.Exec(ctx, `INSERT INTO v_auth.confirmation_rejections(confirmation_key_digest,retry_until) VALUES($1,$2)`, key[:], *until); err != nil {
					return ConfirmationResult{}, err
				}
			}
		}
		if err = tx.Commit(ctx); err != nil {
			return ConfirmationResult{}, err
		}
		return ConfirmationResult{}, rejected
	}
	if !bytes.Equal(email, verified.Email) || verified.FlowID != req.FlowID || !verified.VerifiedAt.Before(verified.ExpiresAt) || verified.VerifiedAt.Unix() < 0 || verified.VerifiedAt.Unix()/1800 > math.MaxUint32 {
		return ConfirmationResult{}, ErrOTPFlowInvalid
	}
	r := confirmationRecord{Key: key, Flow: req.FlowID, Install: req.InstallationID, Email: email, NewSlot: slot, BootstrapKey: req.BootstrapPublicKey, VerifiedAt: verified.VerifiedAt, OTPExpiresAt: verified.ExpiresAt, Window: uint32(verified.VerifiedAt.Unix() / 1800), Epoch: e.config.RegistrationEpoch}
	if _, err = tx.Exec(ctx, `SAVEPOINT qualification_decision`); err != nil {
		return ConfirmationResult{}, err
	}
	if req.ReleaseReceipt != "" {
		if err = e.processPresentedRelease(ctx, tx, email, req.ReleaseReceipt); err != nil {
			if errors.Is(err, ErrReleaseReceiptInvalid) || errors.Is(err, ErrEligibilityReserved) {
				var code = "RELEASE_RECEIPT_INVALID"
				if errors.Is(err, ErrEligibilityReserved) {
					code = "ELIGIBILITY_RESERVED"
				}
				if insertErr := e.insertConfirmationAnchor(ctx, tx, req, key, mac, code, verified.VerifiedAt); insertErr != nil {
					return ConfirmationResult{}, insertErr
				}
				if commitErr := tx.Commit(ctx); commitErr != nil {
					return ConfirmationResult{}, commitErr
				}
				return ConfirmationResult{}, err
			}
			return ConfirmationResult{}, err
		}
	}
	var current, currentKey []byte
	var quotaVersion int64
	err = tx.QueryRow(ctx, `SELECT current_slot,bootstrap_public_key,quota_version FROM v_auth.email_quota WHERE email_exact=$1 FOR UPDATE`, email).Scan(&current, &currentKey, &quotaVersion)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return ConfirmationResult{}, err
	}
	if len(current) == 0 {
		if err = e.reserveConfirmationSlot(ctx, tx, r); err != nil {
			if errors.Is(err, ErrEligibilityReserved) {
				if err = e.insertConfirmationAnchor(ctx, tx, req, key, mac, "ELIGIBILITY_RESERVED", verified.VerifiedAt); err != nil {
					return ConfirmationResult{}, err
				}
				if err = tx.Commit(ctx); err != nil {
					return ConfirmationResult{}, err
				}
				return ConfirmationResult{}, ErrEligibilityReserved
			}
			return ConfirmationResult{}, err
		}
		quotaVersion = 1
		r.State = "CONFIRMATION_PENDING"
	} else {
		var pending bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.retire_pending WHERE old_slot=$1)`, current).Scan(&pending); err != nil {
			return ConfirmationResult{}, err
		}
		if pending {
			if err = e.insertConfirmationAnchor(ctx, tx, req, key, mac, "ELIGIBILITY_RESERVED", verified.VerifiedAt); err != nil {
				return ConfirmationResult{}, err
			}
			if err = tx.Commit(ctx); err != nil {
				return ConfirmationResult{}, err
			}
			return ConfirmationResult{}, ErrEligibilityReserved
		}
		if bytes.Equal(current, slot[:]) && bytes.Equal(currentKey, req.BootstrapPublicKey[:]) {
			r.State = "CONFIRMATION_PENDING"
		} else {
			r.State, r.OldSlot, r.OldVersion = "RETIREMENT_PENDING", current, &quotaVersion
		}
	}
	if err = e.insertConfirmationAnchor(ctx, tx, req, key, mac, r.State, verified.VerifiedAt); err != nil {
		return ConfirmationResult{}, err
	}
	if err = insertConfirmation(ctx, tx, r); err != nil {
		return ConfirmationResult{}, err
	}
	if r.State == "RETIREMENT_PENDING" {
		var old protocol.SlotID
		copy(old[:], r.OldSlot)
		authorization := protocol.Authorization{Epoch: r.Epoch, Slot: old}
		message := authorization.MessageBytes()
		_, err = tx.Exec(ctx, `INSERT INTO v_auth.retire_pending(old_slot,email_exact,quota_version,new_slot,new_bootstrap_public_key,retirement_authorization,state,confirmation_key_digest,authorization_message,signing_key_epoch) VALUES($1,$2,$3,$4,$5,NULL,'PENDING',$6,$7,$8)`, r.OldSlot, r.Email, quotaVersion, r.NewSlot[:], r.BootstrapKey[:], key[:], message[:], int64(r.Epoch))
	} else {
		err = e.queueConfirmationSignature(ctx, tx, r, quotaVersion)
	}
	if err != nil {
		if errors.Is(err, ErrReverifyRequired) {
			return e.commitReverifyDecision(ctx, tx, req, key, mac, verified.VerifiedAt)
		}
		return ConfirmationResult{}, err
	}
	if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return ConfirmationResult{}, err
	}
	if !at.Before(r.OTPExpiresAt) || protocol.ValidateAdmissionWindow(r.Window, at) != nil {
		return e.commitReverifyDecision(ctx, tx, req, key, mac, verified.VerifiedAt)
	}
	if err = tx.Commit(ctx); err != nil {
		return ConfirmationResult{}, err
	}
	return e.advanceConfirmation(ctx, key)
}

func (e *Eligibility) commitReverifyDecision(ctx context.Context, tx pgx.Tx, req ConfirmOTPRequest, key, mac [32]byte, verifiedAt time.Time) (ConfirmationResult, error) {
	if _, err := tx.Exec(ctx, `ROLLBACK TO SAVEPOINT qualification_decision`); err != nil {
		return ConfirmationResult{}, err
	}
	if err := e.insertConfirmationAnchor(ctx, tx, req, key, mac, "REVERIFY_REQUIRED", verifiedAt); err != nil {
		return ConfirmationResult{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return ConfirmationResult{}, err
	}
	return ConfirmationResult{}, ErrReverifyRequired
}

func authenticateConfirmationAnchor(a confirmationAnchor, mac [32]byte) error {
	if a.State == "EXPIRED" {
		return ErrExpired
	}
	if a.Operation != confirmationOperation || !hmac.Equal(a.MAC, mac[:]) {
		return ErrConflict
	}
	return nil
}

func insertConfirmation(ctx context.Context, tx pgx.Tx, r confirmationRecord) error {
	_, err := tx.Exec(ctx, `INSERT INTO v_auth.otp_confirmations(confirmation_key_digest,flow_id,installation_id,email_exact,new_slot,new_bootstrap_public_key,old_slot,old_quota_version,verified_at,verified_otp_expires_at,admission_window,signing_key_epoch,state) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`, r.Key[:], r.Flow[:], r.Install[:], r.Email, r.NewSlot[:], r.BootstrapKey[:], r.OldSlot, r.OldVersion, r.VerifiedAt, r.OTPExpiresAt, int64(r.Window), int64(r.Epoch), r.State)
	return err
}

func (e *Eligibility) reserveConfirmationSlot(ctx context.Context, tx pgx.Tx, r confirmationRecord) error {
	var exists bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.used_slots WHERE slot_id=$1)`, r.NewSlot[:]).Scan(&exists); err != nil {
		return err
	}
	if exists {
		return ErrEligibilityReserved
	}
	tag, err := tx.Exec(ctx, `INSERT INTO v_auth.used_slots(slot_id,state,version) VALUES($1,'RESERVED',1) ON CONFLICT(slot_id) DO NOTHING`, r.NewSlot[:])
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return ErrEligibilityReserved
	}
	_, err = tx.Exec(ctx, `INSERT INTO v_auth.email_quota(email_exact,current_slot,bootstrap_public_key,quota_version,reservation_confirmation_key_digest) VALUES($1,$2,$3,1,$4)`, r.Email, r.NewSlot[:], r.BootstrapKey[:], r.Key[:])
	return err
}

func (e *Eligibility) queueConfirmationSignature(ctx context.Context, tx pgx.Tx, r confirmationRecord, quotaVersion int64) error {
	var at time.Time
	if err := tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return err
	}
	// The completed OTP decision fixes the window. Waiting on a reservation or
	// signing service never substitutes a new bucket.
	if !at.Before(r.OTPExpiresAt) || !at.Before(r.VerifiedAt.Add(10*time.Minute)) || protocol.ValidateAdmissionWindow(r.Window, at) != nil {
		return ErrReverifyRequired
	}
	message := (protocol.Ticket{Epoch: r.Epoch, Window: r.Window, Slot: r.NewSlot, BootstrapKey: r.BootstrapKey}).MessageBytes()
	_, err := tx.Exec(ctx, `INSERT INTO v_auth.confirmation_sign_jobs(confirmation_key_digest,slot_id,quota_version,signing_key_epoch,reg_message,state) VALUES($1,$2,$3,$4,$5,'PENDING_SIGN')`, r.Key[:], r.NewSlot[:], quotaVersion, int64(r.Epoch), message[:])
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `UPDATE v_auth.otp_confirmations SET state='CONFIRMATION_PENDING',qualification_committed_at=$2,ticket_replay_until=verified_at+interval '10 minutes' WHERE confirmation_key_digest=$1`, r.Key[:], at)
	return err
}

// Presented RELEASED receipts share the same durable invariants as the internal
// receipt endpoint, but the caller has already verified/consumed this flow's OTP
// and holds its exact address lock. Never look up/release a different address.
func (e *Eligibility) processPresentedRelease(ctx context.Context, tx pgx.Tx, email []byte, encoded string) error {
	r, err := e.store.verifier.VerifyReceipt(encoded, protocol.PurposeReleased)
	if err != nil {
		return ErrReleaseReceiptInvalid
	}
	var processed string
	err = tx.QueryRow(ctx, `SELECT purpose FROM v_auth.processed_receipts WHERE slot_id=$1`, r.Slot[:]).Scan(&processed)
	if err == nil {
		if processed != "RELEASED" {
			return ErrReleaseReceiptInvalid
		}
		return nil // A duplicate receipt cannot clear this address's later slot.
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	var current []byte
	var version int64
	if err = tx.QueryRow(ctx, `SELECT current_slot,quota_version FROM v_auth.email_quota WHERE email_exact=$1 FOR UPDATE`, email).Scan(&current, &version); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrReleaseReceiptInvalid
		}
		return err
	}
	if !bytes.Equal(current, r.Slot[:]) {
		return ErrReleaseReceiptInvalid
	}
	var state string
	var slotVersion int64
	if err = tx.QueryRow(ctx, `SELECT state,version FROM v_auth.used_slots WHERE slot_id=$1 FOR UPDATE`, r.Slot[:]).Scan(&state, &slotVersion); err != nil {
		return err
	}
	if state != "RESERVED" {
		return ErrReleaseReceiptInvalid
	}
	if _, err = tx.Exec(ctx, `DELETE FROM v_auth.retire_pending WHERE old_slot=$1`, r.Slot[:]); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `DELETE FROM v_auth.email_quota WHERE email_exact=$1 AND current_slot=$2 AND quota_version=$3`, email, r.Slot[:], version); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE v_auth.used_slots SET state='RELEASED',version=version+1 WHERE slot_id=$1`, r.Slot[:]); err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO v_auth.processed_receipts(slot_id,purpose,version) VALUES($1,'RELEASED',$2)`, r.Slot[:], slotVersion+1)
	return err
}

type confirmationSignJob struct {
	Message      []byte
	Signature    []byte
	State        string
	QuotaVersion int64
	Epoch        uint32
}

func readConfirmationSignJob(ctx context.Context, q confirmationQuerier, key [32]byte, lock bool) (confirmationSignJob, error) {
	query := `SELECT reg_message,signature,state,quota_version,signing_key_epoch FROM v_auth.confirmation_sign_jobs WHERE confirmation_key_digest=$1`
	if lock {
		query += ` FOR UPDATE`
	}
	var j confirmationSignJob
	var epoch int64
	err := q.QueryRow(ctx, query, key[:]).Scan(&j.Message, &j.Signature, &j.State, &j.QuotaVersion, &epoch)
	if err != nil {
		return j, err
	}
	if epoch < 0 || epoch > math.MaxUint32 || len(j.Message) != 92 || j.QuotaVersion < 0 {
		return j, ErrReconciliation
	}
	j.Epoch = uint32(epoch)
	return j, nil
}

func (e *Eligibility) lockConfirmation(ctx context.Context, original confirmationRecord) (pgx.Tx, confirmationAnchor, confirmationRecord, error) {
	tx, err := begin(ctx, e.store.pool)
	if err != nil {
		return nil, confirmationAnchor{}, confirmationRecord{}, err
	}
	fail := func(err error) (pgx.Tx, confirmationAnchor, confirmationRecord, error) {
		_ = tx.Rollback(ctx)
		return nil, confirmationAnchor{}, confirmationRecord{}, err
	}
	if err = e.store.lockAddress(ctx, tx, original.Email); err != nil {
		return fail(err)
	}
	if err = lockVRequest(ctx, tx, original.Key); err != nil {
		return fail(err)
	}
	a, err := readConfirmationAnchor(ctx, tx, original.Key, true)
	if err != nil {
		return fail(err)
	}
	r, err := readConfirmation(ctx, tx, original.Key, true)
	if errors.Is(err, pgx.ErrNoRows) {
		return fail(ErrExpired)
	}
	if err != nil {
		return fail(err)
	}
	if a.Operation != confirmationOperation || !bytes.Equal(original.Email, r.Email) {
		return fail(ErrReconciliation)
	}
	return tx, a, r, nil
}

func (e *Eligibility) cachedConfirmationError(ctx context.Context, key [32]byte, code *string) error {
	if code == nil {
		return ErrReconciliation
	}
	switch *code {
	case "OTP_INVALID", "OTP_EXPIRED", "OTP_REPLACED", "OTP_FLOW_INVALID", "RELEASE_RECEIPT_INVALID", "ELIGIBILITY_RESERVED", "REVERIFY_REQUIRED":
		return eligibilityError(*code, 0)
	case "RATE_LIMITED":
		// This is a permanently rejected operation, not permission to retry its
		// OTP. Compute only the original lock's remaining duration. Even after
		// flow erasure, replay never extends the lock or evaluates the OTP again.
		var until, at time.Time
		err := e.store.pool.QueryRow(ctx, `SELECT retry_until,clock_timestamp() FROM v_auth.confirmation_rejections WHERE confirmation_key_digest=$1`, key[:]).Scan(&until, &at)
		if errors.Is(err, pgx.ErrNoRows) {
			// Cleanup can have atomically erased the detail and expired the
			// permanent anchor since driveConfirmation's initial snapshot.
			a, readErr := readConfirmationAnchor(ctx, e.store.pool, key, false)
			if readErr != nil {
				return readErr
			}
			if a.State == "EXPIRED" {
				return ErrExpired
			}
			return ErrReconciliation
		}
		if err != nil {
			return err
		}
		return eligibilityError(*code, remainingSeconds(until, at))
	default:
		return ErrReconciliation
	}
}

func (e *Eligibility) advanceConfirmation(ctx context.Context, key [32]byte) (ConfirmationResult, error) {
	return e.driveConfirmation(ctx, key, false)
}

func (e *Eligibility) driveConfirmation(ctx context.Context, key [32]byte, worker bool) (ConfirmationResult, error) {
	a, err := readConfirmationAnchor(ctx, e.store.pool, key, false)
	if err != nil {
		return ConfirmationResult{}, err
	}
	r, err := readConfirmation(ctx, e.store.pool, key, false)
	if errors.Is(err, pgx.ErrNoRows) {
		if a.State == "EXPIRED" {
			return ConfirmationResult{}, ErrExpired
		}
		var at time.Time
		if err = e.store.pool.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
			return ConfirmationResult{}, err
		}
		if a.ExpiresAt == nil || !at.Before(*a.ExpiresAt) {
			return ConfirmationResult{}, ErrExpired
		}
		return ConfirmationResult{}, e.cachedConfirmationError(ctx, key, a.Code)
	}
	if err != nil {
		return ConfirmationResult{}, err
	}
	var at time.Time
	if err = e.store.pool.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return ConfirmationResult{}, err
	}
	if (a.State == "EXPIRED" || !at.Before(r.VerifiedAt.Add(10*time.Minute))) && !(worker && r.State == "RETIREMENT_PENDING") {
		return ConfirmationResult{}, ErrExpired
	}
	switch r.State {
	case "RETIREMENT_PENDING":
		return e.driveOriginalRetirement(ctx, r)
	case "CONFIRMATION_PENDING", "TICKET_AVAILABLE":
		return e.signConfirmation(ctx, r)
	case "REVERIFY_REQUIRED":
		return ConfirmationResult{}, ErrReverifyRequired
	case "ELIGIBILITY_RESERVED":
		return ConfirmationResult{}, ErrEligibilityReserved
	default:
		return ConfirmationResult{}, ErrReconciliation
	}
}

func (e *Eligibility) setConfirmationTerminal(ctx context.Context, tx pgx.Tx, r confirmationRecord, state string, at time.Time) error {
	if state != "REVERIFY_REQUIRED" && state != "ELIGIBILITY_RESERVED" {
		return ErrReconciliation
	}
	if _, err := tx.Exec(ctx, `UPDATE v_auth.otp_confirmations SET state=$2,terminal_at=$3 WHERE confirmation_key_digest=$1`, r.Key[:], state, at); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `UPDATE v_auth.request_results SET result_code=$2 WHERE key_digest=$1 AND state='LIVE'`, r.Key[:], state)
	return err
}

// The address lock protects the whole quota lifecycle, while the request lock
// serializes its signing job with replay, cleanup and other workers.
func (e *Eligibility) confirmationTicketPreflight(ctx context.Context, tx pgx.Tx, a confirmationAnchor, r confirmationRecord) (confirmationSignJob, time.Time, error) {
	if a.State == "EXPIRED" {
		return confirmationSignJob{}, time.Time{}, ErrExpired
	}
	if r.State == "REVERIFY_REQUIRED" {
		return confirmationSignJob{}, time.Time{}, ErrReverifyRequired
	}
	if r.State == "ELIGIBILITY_RESERVED" {
		return confirmationSignJob{}, time.Time{}, ErrEligibilityReserved
	}
	if r.State != "CONFIRMATION_PENDING" && r.State != "TICKET_AVAILABLE" {
		return confirmationSignJob{}, time.Time{}, ErrReconciliation
	}
	var current, public, owner []byte
	var version int64
	err := tx.QueryRow(ctx, `SELECT current_slot,bootstrap_public_key,quota_version,reservation_confirmation_key_digest FROM v_auth.email_quota WHERE email_exact=$1 FOR UPDATE`, r.Email).Scan(&current, &public, &version, &owner)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return confirmationSignJob{}, time.Time{}, err
	}
	var pending bool
	if len(current) != 0 {
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.retire_pending WHERE old_slot=$1)`, current).Scan(&pending); err != nil {
			return confirmationSignJob{}, time.Time{}, err
		}
	}
	j, err := readConfirmationSignJob(ctx, tx, r.Key, true)
	if err != nil {
		return j, time.Time{}, err
	}
	var at time.Time
	if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return j, at, err
	}
	message := (protocol.Ticket{Epoch: r.Epoch, Window: r.Window, Slot: r.NewSlot, BootstrapKey: r.BootstrapKey}).MessageBytes()
	if !bytes.Equal(j.Message, message[:]) || j.Epoch != r.Epoch {
		return j, at, ErrReconciliation
	}
	if !bytes.Equal(current, r.NewSlot[:]) || !bytes.Equal(public, r.BootstrapKey[:]) || version != j.QuotaVersion || pending || (len(r.OldSlot) != 0 && !bytes.Equal(owner, r.Key[:])) || r.ReplayUntil == nil || !at.Before(*r.ReplayUntil) || protocol.ValidateAdmissionWindow(r.Window, at) != nil {
		if err = e.setConfirmationTerminal(ctx, tx, r, "REVERIFY_REQUIRED", at); err != nil {
			return j, at, err
		}
		return j, at, ErrReverifyRequired
	}
	return j, at, nil
}

func confirmationWire(r confirmationRecord, signature []byte) (string, error) {
	if len(signature) != 64 {
		return "", ErrReconciliation
	}
	ticket := protocol.SignedTicket{Ticket: protocol.Ticket{Epoch: r.Epoch, Window: r.Window, Slot: r.NewSlot, BootstrapKey: r.BootstrapKey}}
	copy(ticket.Signature[:], signature)
	return ticket.Encode(), nil
}

func (e *Eligibility) signConfirmation(ctx context.Context, original confirmationRecord) (ConfirmationResult, error) {
	tx, a, r, err := e.lockConfirmation(ctx, original)
	if err != nil {
		return ConfirmationResult{}, err
	}
	defer tx.Rollback(ctx)
	j, at, err := e.confirmationTicketPreflight(ctx, tx, a, r)
	if err != nil {
		if errors.Is(err, ErrReverifyRequired) {
			if commitErr := tx.Commit(ctx); commitErr != nil {
				return ConfirmationResult{}, commitErr
			}
		}
		return ConfirmationResult{}, err
	}
	if j.State == "READY" {
		wire, wireErr := confirmationWire(r, j.Signature)
		if wireErr != nil {
			return ConfirmationResult{}, wireErr
		}
		if _, wireErr = e.store.verifier.VerifyRegistrationTicket(wire, at); wireErr != nil {
			return ConfirmationResult{}, ErrReconciliation
		}
		if err = tx.Commit(ctx); err != nil {
			return ConfirmationResult{}, err
		}
		return ConfirmationResult{State: "TICKET_AVAILABLE", RegistrationTicket: wire}, nil
	}
	if j.State != "PENDING_SIGN" {
		return ConfirmationResult{}, ErrReconciliation
	}
	if err = tx.Commit(ctx); err != nil {
		return ConfirmationResult{}, err
	}
	// This exact message was durably queued with OTP consumption and quota
	// reservation. Neither retry nor the signer can choose a new admission time.
	signature, err := e.signer(ctx, j.Epoch, append([]byte(nil), j.Message...))
	if err != nil {
		return ConfirmationResult{State: "CONFIRMATION_PENDING", RetryAfterSeconds: 1}, nil
	}
	wire, err := confirmationWire(r, signature)
	if err != nil {
		return ConfirmationResult{}, err
	}
	tx, a, r, err = e.lockConfirmation(ctx, r)
	if err != nil {
		return ConfirmationResult{}, err
	}
	defer tx.Rollback(ctx)
	j, at, err = e.confirmationTicketPreflight(ctx, tx, a, r)
	if err != nil {
		if errors.Is(err, ErrReverifyRequired) {
			if commitErr := tx.Commit(ctx); commitErr != nil {
				return ConfirmationResult{}, commitErr
			}
		}
		return ConfirmationResult{}, err
	}
	if j.State == "READY" {
		wire, err = confirmationWire(r, j.Signature)
		if err != nil {
			return ConfirmationResult{}, err
		}
	}
	if _, err = e.store.verifier.VerifyRegistrationTicket(wire, at); err != nil {
		return ConfirmationResult{}, ErrReconciliation
	}
	if j.State == "PENDING_SIGN" {
		if _, err = tx.Exec(ctx, `UPDATE v_auth.confirmation_sign_jobs SET state='READY',signature=$2 WHERE confirmation_key_digest=$1 AND state='PENDING_SIGN'`, r.Key[:], signature); err != nil {
			return ConfirmationResult{}, err
		}
		if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_confirmations SET state='TICKET_AVAILABLE' WHERE confirmation_key_digest=$1`, r.Key[:]); err != nil {
			return ConfirmationResult{}, err
		}
		if _, err = tx.Exec(ctx, `UPDATE v_auth.request_results SET result_code='TICKET_AVAILABLE' WHERE key_digest=$1 AND state='LIVE'`, r.Key[:]); err != nil {
			return ConfirmationResult{}, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return ConfirmationResult{}, err
	}
	return ConfirmationResult{State: "TICKET_AVAILABLE", RegistrationTicket: wire}, nil
}

// settleOriginalRetirement always inspects the committed old-slot ledger
// before acting on a late peer response. The original binding survives deletion
// of retire_pending, so no push/pull ordering can silently start a new operation.
func (e *Eligibility) settleOriginalRetirement(ctx context.Context, tx pgx.Tx, r confirmationRecord, reject, allowQualification bool) (confirmationRecord, bool, error) {
	if r.State != "RETIREMENT_PENDING" {
		return r, true, nil
	}
	var purpose string
	err := tx.QueryRow(ctx, `SELECT purpose FROM v_auth.processed_receipts WHERE slot_id=$1`, r.OldSlot).Scan(&purpose)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return r, false, err
	}
	if err == nil {
		if purpose != "RETIRED" && purpose != "RELEASED" {
			return r, false, ErrReconciliation
		}
		var current, public, owner []byte
		var version int64
		err = tx.QueryRow(ctx, `SELECT current_slot,bootstrap_public_key,quota_version,reservation_confirmation_key_digest FROM v_auth.email_quota WHERE email_exact=$1 FOR UPDATE`, r.Email).Scan(&current, &public, &version, &owner)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return r, false, err
		}
		var at time.Time
		if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
			return r, false, err
		}
		if !allowQualification || !at.Before(r.OTPExpiresAt) || !at.Before(r.VerifiedAt.Add(10*time.Minute)) || protocol.ValidateAdmissionWindow(r.Window, at) != nil {
			if err = e.setConfirmationTerminal(ctx, tx, r, "REVERIFY_REQUIRED", at); err != nil {
				return r, false, err
			}
			r.State = "REVERIFY_REQUIRED"
			return r, true, nil
		}
		if len(current) != 0 && (!bytes.Equal(current, r.NewSlot[:]) || !bytes.Equal(public, r.BootstrapKey[:]) || !bytes.Equal(owner, r.Key[:])) {
			if err = e.setConfirmationTerminal(ctx, tx, r, "ELIGIBILITY_RESERVED", at); err != nil {
				return r, false, err
			}
			r.State = "ELIGIBILITY_RESERVED"
			return r, true, nil
		}
		if _, err = tx.Exec(ctx, `SAVEPOINT original_continuation`); err != nil {
			return r, false, err
		}
		if len(current) == 0 {
			err = e.reserveConfirmationSlot(ctx, tx, r)
			version = 1
		}
		if err == nil {
			err = e.queueConfirmationSignature(ctx, tx, r, version)
		}
		if err != nil {
			if !errors.Is(err, ErrEligibilityReserved) && !errors.Is(err, ErrReverifyRequired) {
				return r, false, err
			}
			state := "REVERIFY_REQUIRED"
			if errors.Is(err, ErrEligibilityReserved) {
				state = "ELIGIBILITY_RESERVED"
			}
			if _, err = tx.Exec(ctx, `ROLLBACK TO SAVEPOINT original_continuation`); err != nil {
				return r, false, err
			}
			if err = e.setConfirmationTerminal(ctx, tx, r, state, at); err != nil {
				return r, false, err
			}
			r.State = state
			return r, true, nil
		}
		// Recheck after all uniqueness/FK waits. A proof that was fresh before a
		// competing slot insert must not create a reservation after its expiry.
		if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
			return r, false, err
		}
		if !at.Before(r.OTPExpiresAt) || !at.Before(r.VerifiedAt.Add(10*time.Minute)) || protocol.ValidateAdmissionWindow(r.Window, at) != nil {
			if _, err = tx.Exec(ctx, `ROLLBACK TO SAVEPOINT original_continuation`); err != nil {
				return r, false, err
			}
			if err = e.setConfirmationTerminal(ctx, tx, r, "REVERIFY_REQUIRED", at); err != nil {
				return r, false, err
			}
			r.State = "REVERIFY_REQUIRED"
			return r, true, nil
		}
		r.State = "CONFIRMATION_PENDING"
		return r, true, nil
	}
	if !reject {
		return r, false, nil
	}
	// A definitive C refusal only cancels this exact original job. It cannot
	// clear the old reservation or a pending job belonging to another request.
	tag, err := tx.Exec(ctx, `DELETE FROM v_auth.retire_pending WHERE old_slot=$1 AND confirmation_key_digest=$2 AND email_exact=$3 AND quota_version=$4`, r.OldSlot, r.Key[:], r.Email, r.OldVersion)
	if err != nil {
		return r, false, err
	}
	if tag.RowsAffected() != 1 {
		return r, false, ErrReconciliation
	}
	var at time.Time
	if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return r, false, err
	}
	if err = e.setConfirmationTerminal(ctx, tx, r, "ELIGIBILITY_RESERVED", at); err != nil {
		return r, false, err
	}
	r.State = "ELIGIBILITY_RESERVED"
	return r, true, nil
}

func (e *Eligibility) finishRetirementStep(ctx context.Context, original confirmationRecord, reject bool) (ConfirmationResult, bool, error) {
	tx, a, r, err := e.lockConfirmation(ctx, original)
	if err != nil {
		return ConfirmationResult{}, false, err
	}
	defer tx.Rollback(ctx)
	r, done, err := e.settleOriginalRetirement(ctx, tx, r, reject, a.State != "EXPIRED")
	if err != nil {
		return ConfirmationResult{}, false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return ConfirmationResult{}, false, err
	}
	if !done {
		return ConfirmationResult{State: "RETIREMENT_PENDING", RetryAfterSeconds: 1}, false, nil
	}
	switch r.State {
	case "CONFIRMATION_PENDING", "TICKET_AVAILABLE":
		result, err := e.signConfirmation(ctx, r)
		return result, true, err
	case "REVERIFY_REQUIRED":
		return ConfirmationResult{}, true, ErrReverifyRequired
	case "ELIGIBILITY_RESERVED":
		return ConfirmationResult{}, true, ErrEligibilityReserved
	default:
		return ConfirmationResult{}, true, ErrReconciliation
	}
}

func (e *Eligibility) driveOriginalRetirement(ctx context.Context, original confirmationRecord) (ConfirmationResult, error) {
	result, done, err := e.finishRetirementStep(ctx, original, false)
	if err != nil || done {
		return result, err
	}
	tx, a, r, err := e.lockConfirmation(ctx, original)
	if err != nil {
		return ConfirmationResult{}, err
	}
	defer tx.Rollback(ctx)
	r, done, err = e.settleOriginalRetirement(ctx, tx, r, false, a.State != "EXPIRED")
	if err != nil {
		return ConfirmationResult{}, err
	}
	if done {
		if err = tx.Commit(ctx); err != nil {
			return ConfirmationResult{}, err
		}
		result, _, err = e.finishRetirementStep(ctx, r, false)
		return result, err
	}
	var message, authorization, owner []byte
	var epoch int64
	err = tx.QueryRow(ctx, `SELECT authorization_message,retirement_authorization,confirmation_key_digest,signing_key_epoch FROM v_auth.retire_pending WHERE old_slot=$1 FOR UPDATE`, r.OldSlot).Scan(&message, &authorization, &owner, &epoch)
	if err != nil {
		return ConfirmationResult{}, err
	}
	var old protocol.SlotID
	copy(old[:], r.OldSlot)
	expected := (protocol.Authorization{Epoch: r.Epoch, Slot: old}).MessageBytes()
	if !bytes.Equal(owner, r.Key[:]) || !bytes.Equal(message, expected[:]) || epoch != int64(r.Epoch) {
		return ConfirmationResult{}, ErrReconciliation
	}
	if err = tx.Commit(ctx); err != nil {
		return ConfirmationResult{}, err
	}
	if len(authorization) == 0 {
		signature, signErr := e.signer(ctx, r.Epoch, append([]byte(nil), message...))
		if signErr != nil {
			result, _, err = e.finishRetirementStep(ctx, r, false)
			return result, err
		}
		if len(signature) != 64 {
			return ConfirmationResult{}, ErrReconciliation
		}
		authorization = append(append([]byte(nil), message...), signature...)
		verified, verifyErr := e.store.verifier.VerifyRetirementAuthorization(protocol.EncodeCanonicalBase64url(authorization))
		if verifyErr != nil || verified.Slot != old || verified.Epoch != r.Epoch {
			return ConfirmationResult{}, ErrReconciliation
		}
		tx, a, r, err = e.lockConfirmation(ctx, r)
		if err != nil {
			return ConfirmationResult{}, err
		}
		defer tx.Rollback(ctx)
		r, done, err = e.settleOriginalRetirement(ctx, tx, r, false, a.State != "EXPIRED")
		if err != nil {
			return ConfirmationResult{}, err
		}
		if !done {
			var stored []byte
			err = tx.QueryRow(ctx, `SELECT retirement_authorization FROM v_auth.retire_pending WHERE old_slot=$1 AND confirmation_key_digest=$2 FOR UPDATE`, r.OldSlot, r.Key[:]).Scan(&stored)
			if err != nil {
				return ConfirmationResult{}, err
			}
			if len(stored) == 0 {
				if _, err = tx.Exec(ctx, `UPDATE v_auth.retire_pending SET retirement_authorization=$3 WHERE old_slot=$1 AND confirmation_key_digest=$2 AND retirement_authorization IS NULL`, r.OldSlot, r.Key[:], authorization); err != nil {
					return ConfirmationResult{}, err
				}
			} else {
				authorization = stored
			}
		}
		if err = tx.Commit(ctx); err != nil {
			return ConfirmationResult{}, err
		}
		if done {
			result, _, err = e.finishRetirementStep(ctx, r, false)
			return result, err
		}
	}
	// Treat transport errors and PENDING as unknown outcomes. In both cases a
	// concurrent receipt push may already have committed the old-slot terminal.
	verified, verifyErr := e.store.verifier.VerifyRetirementAuthorization(protocol.EncodeCanonicalBase64url(authorization))
	if verifyErr != nil || verified.Slot != old || verified.Epoch != r.Epoch {
		return ConfirmationResult{}, ErrReconciliation
	}
	reply, peerErr := e.retirePeer.RetireUnusedSlot(ctx, protocol.EncodeCanonicalBase64url(authorization))
	if peerErr == nil && reply.Receipt != "" {
		receipt, receiptErr := e.store.verifier.VerifyReceipt(reply.Receipt, protocol.PurposeRetired)
		if receiptErr != nil || receipt.Slot != old {
			return ConfirmationResult{}, ErrReconciliation
		}
		processErr := e.store.ProcessReceipt(ctx, reply.Receipt, protocol.PurposeRetired)
		result, done, err = e.finishRetirementStep(ctx, r, false)
		if err != nil || done {
			return result, err
		}
		if processErr != nil {
			return ConfirmationResult{}, processErr
		}
		return result, nil
	}
	result, _, err = e.finishRetirementStep(ctx, r, peerErr == nil && reply.SlotNotRetirable)
	return result, err
}

// GetOTPConfirmationResult is strictly read-only: it neither calls a signer or
// C nor consumes an OTP, reserves a slot, advances a job, or expires an anchor.
// The full signed ticket is available only by replaying the original POST body.
func (e *Eligibility) GetOTPConfirmationResult(ctx context.Context, rawKey, flow [32]byte, installation [16]byte) (ConfirmationResult, error) {
	if rawKey == ([32]byte{}) || flow == ([32]byte{}) || installation == ([16]byte{}) {
		return ConfirmationResult{}, ErrBadRequest
	}
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", rawKey[:])
	tx, err := e.store.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return ConfirmationResult{}, err
	}
	defer tx.Rollback(ctx)
	a, err := readConfirmationAnchor(ctx, tx, key, false)
	if errors.Is(err, pgx.ErrNoRows) {
		return ConfirmationResult{State: "PENDING", RetryAfterSeconds: 1}, nil
	}
	if err != nil {
		return ConfirmationResult{}, err
	}
	if a.State == "EXPIRED" {
		return ConfirmationResult{}, ErrExpired
	}
	if a.Operation != confirmationOperation || !hmac.Equal(a.Flow, flow[:]) || !hmac.Equal(a.Install, installation[:]) {
		return ConfirmationResult{}, ErrResultAuthentication
	}
	var at time.Time
	if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
		return ConfirmationResult{}, err
	}
	if a.ExpiresAt == nil || !at.Before(*a.ExpiresAt) {
		return ConfirmationResult{}, ErrExpired
	}
	r, err := readConfirmation(ctx, tx, key, false)
	if errors.Is(err, pgx.ErrNoRows) {
		return ConfirmationResult{State: "NOT_COMMITTED"}, nil
	}
	if err != nil {
		return ConfirmationResult{}, err
	}
	switch r.State {
	case "RETIREMENT_PENDING":
		var processed bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.processed_receipts WHERE slot_id=$1)`, r.OldSlot).Scan(&processed); err != nil {
			return ConfirmationResult{}, err
		}
		if processed && (!at.Before(r.OTPExpiresAt) || protocol.ValidateAdmissionWindow(r.Window, at) != nil) {
			return ConfirmationResult{State: "REVERIFY_REQUIRED"}, nil
		}
		return ConfirmationResult{State: "RETIREMENT_PENDING", RetryAfterSeconds: 1}, nil
	case "REVERIFY_REQUIRED":
		return ConfirmationResult{State: "REVERIFY_REQUIRED"}, nil
	case "ELIGIBILITY_RESERVED":
		return ConfirmationResult{State: "NOT_COMMITTED"}, nil
	case "CONFIRMATION_PENDING", "TICKET_AVAILABLE":
		if r.ReplayUntil == nil || !at.Before(*r.ReplayUntil) || protocol.ValidateAdmissionWindow(r.Window, at) != nil {
			return ConfirmationResult{State: "REVERIFY_REQUIRED"}, nil
		}
		var current, public, owner []byte
		var version int64
		err = tx.QueryRow(ctx, `SELECT current_slot,bootstrap_public_key,quota_version,reservation_confirmation_key_digest FROM v_auth.email_quota WHERE email_exact=$1`, r.Email).Scan(&current, &public, &version, &owner)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return ConfirmationResult{}, err
		}
		var pending bool
		if len(current) != 0 {
			if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.retire_pending WHERE old_slot=$1)`, current).Scan(&pending); err != nil {
				return ConfirmationResult{}, err
			}
		}
		j, err := readConfirmationSignJob(ctx, tx, key, false)
		if err != nil {
			return ConfirmationResult{}, err
		}
		if !bytes.Equal(current, r.NewSlot[:]) || !bytes.Equal(public, r.BootstrapKey[:]) || version != j.QuotaVersion || pending || (len(r.OldSlot) != 0 && !bytes.Equal(owner, r.Key[:])) {
			return ConfirmationResult{State: "REVERIFY_REQUIRED"}, nil
		}
		if j.State == "READY" {
			wire, wireErr := confirmationWire(r, j.Signature)
			if wireErr != nil {
				return ConfirmationResult{}, wireErr
			}
			if _, wireErr = e.store.verifier.VerifyRegistrationTicket(wire, at); wireErr != nil {
				return ConfirmationResult{State: "REVERIFY_REQUIRED"}, nil
			}
			return ConfirmationResult{State: "TICKET_AVAILABLE"}, nil
		}
		return ConfirmationResult{State: "CONFIRMATION_PENDING", RetryAfterSeconds: 1}, nil
	default:
		return ConfirmationResult{}, ErrReconciliation
	}
}

// ResumePendingConfirmations drives a bounded snapshot of durable jobs using
// their digests. It requires no stored raw idempotency key or consumed OTP.
// Unresolved retirements continue after public result expiry; expired original
// qualifications can only release the old slot and then require a new OTP.
func (e *Eligibility) ResumePendingConfirmations(ctx context.Context, limit int) (int, error) {
	if limit < 1 || limit > 1000 {
		return 0, ErrBadRequest
	}
	rows, err := e.store.pool.Query(ctx, `SELECT confirmation_key_digest FROM v_auth.otp_confirmations WHERE state IN ('RETIREMENT_PENDING','CONFIRMATION_PENDING') ORDER BY verified_at,confirmation_key_digest LIMIT $1`, limit)
	if err != nil {
		return 0, err
	}
	var keys [][32]byte
	for rows.Next() {
		var wire []byte
		if err = rows.Scan(&wire); err != nil {
			rows.Close()
			return 0, err
		}
		if len(wire) != 32 {
			rows.Close()
			return 0, ErrReconciliation
		}
		var key [32]byte
		copy(key[:], wire)
		keys = append(keys, key)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return 0, err
	}
	processed := 0
	for _, key := range keys {
		_, err = e.driveConfirmation(ctx, key, true)
		processed++
		if err != nil && !errors.Is(err, ErrExpired) && !errors.Is(err, ErrReverifyRequired) && !errors.Is(err, ErrEligibilityReserved) {
			return processed, err
		}
	}
	return processed, nil
}

// CleanupConfirmations expires permanent result anchors and erases resolved
// identity/signature rows. Pending old-slot cleanup is never cancelled by time:
// only flow/device bindings are erased, while its minimal original retirement
// facts survive until an authenticated C decision settles it.
func (e *Eligibility) CleanupConfirmations(ctx context.Context, limit int) (int, error) {
	if limit < 1 || limit > 1000 {
		return 0, ErrBadRequest
	}
	rows, err := e.store.pool.Query(ctx, `SELECT rr.key_digest,oc.email_exact FROM v_auth.request_results rr LEFT JOIN v_auth.otp_confirmations oc ON oc.confirmation_key_digest=rr.key_digest WHERE rr.operation=$1 AND ((rr.state='LIVE' AND rr.expires_at <= clock_timestamp()) OR (rr.state='EXPIRED' AND oc.confirmation_key_digest IS NOT NULL AND (oc.flow_id IS NOT NULL OR NOT EXISTS(SELECT 1 FROM v_auth.retire_pending rp WHERE rp.confirmation_key_digest=oc.confirmation_key_digest)))) ORDER BY rr.key_digest LIMIT $2`, confirmationOperation, limit)
	if err != nil {
		return 0, err
	}
	type candidate struct {
		key   [32]byte
		email []byte
	}
	var candidates []candidate
	for rows.Next() {
		var wire, email []byte
		if err = rows.Scan(&wire, &email); err != nil {
			rows.Close()
			return 0, err
		}
		if len(wire) != 32 {
			rows.Close()
			return 0, ErrReconciliation
		}
		c := candidate{email: email}
		copy(c.key[:], wire)
		candidates = append(candidates, c)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return 0, err
	}
	processed := 0
	for _, c := range candidates {
		tx, beginErr := begin(ctx, e.store.pool)
		if beginErr != nil {
			return processed, beginErr
		}
		err = func() error {
			defer tx.Rollback(ctx)
			if len(c.email) != 0 {
				if err := e.store.lockAddress(ctx, tx, c.email); err != nil {
					return err
				}
			}
			if err := lockVRequest(ctx, tx, c.key); err != nil {
				return err
			}
			a, err := readConfirmationAnchor(ctx, tx, c.key, true)
			if err != nil {
				return err
			}
			var at time.Time
			if err = tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&at); err != nil {
				return err
			}
			if a.Operation != confirmationOperation || (a.State == "LIVE" && (a.ExpiresAt == nil || at.Before(*a.ExpiresAt))) {
				return tx.Commit(ctx)
			}
			r, rowErr := readConfirmation(ctx, tx, c.key, true)
			if rowErr != nil && !errors.Is(rowErr, pgx.ErrNoRows) {
				return rowErr
			}
			if _, err = tx.Exec(ctx, `DELETE FROM v_auth.confirmation_rejections WHERE confirmation_key_digest=$1`, c.key[:]); err != nil {
				return err
			}
			if a.State == "LIVE" {
				if _, err = tx.Exec(ctx, `UPDATE v_auth.request_results SET state='EXPIRED',request_hmac=NULL,hmac_key_version=NULL,installation_id=NULL,flow_id=NULL,result_code=NULL,expires_at=NULL WHERE key_digest=$1`, c.key[:]); err != nil {
					return err
				}
			}
			if rowErr == nil {
				var pending bool
				if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.retire_pending WHERE confirmation_key_digest=$1)`, c.key[:]).Scan(&pending); err != nil {
					return err
				}
				if pending {
					if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_confirmations SET flow_id=NULL,installation_id=NULL WHERE confirmation_key_digest=$1 AND flow_id IS NOT NULL`, c.key[:]); err != nil {
						return err
					}
				} else {
					// A completed pushed receipt may precede the worker's state
					// transition. After expiry no new reservation is permitted,
					// so deleting this already-settled original is safe.
					if r.State == "RETIREMENT_PENDING" {
						var settled bool
						if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.processed_receipts WHERE slot_id=$1)`, r.OldSlot).Scan(&settled); err != nil {
							return err
						}
						if !settled {
							return ErrReconciliation
						}
					}
					if _, err = tx.Exec(ctx, `DELETE FROM v_auth.confirmation_sign_jobs WHERE confirmation_key_digest=$1`, c.key[:]); err != nil {
						return err
					}
					if _, err = tx.Exec(ctx, `DELETE FROM v_auth.otp_confirmations WHERE confirmation_key_digest=$1`, c.key[:]); err != nil {
						return err
					}
				}
			}
			return tx.Commit(ctx)
		}()
		if err != nil {
			return processed, err
		}
		processed++
	}
	return processed, nil
}
