package authprivacy

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type ReceiptJob struct {
	Slot    protocol.SlotID
	Purpose protocol.Purpose
	Epoch   uint32
	Message []byte
}

// ReceiptJob reads only committed terminal state. HSM calls belong outside SQL
// transactions; neither a successful SQL write nor a signature is a V ACK.
func (c *Community) ReceiptJob(ctx context.Context, slot protocol.SlotID) (ReceiptJob, error) {
	var job ReceiptJob
	var epoch int64
	var purpose string
	err := c.pool.QueryRow(ctx, `SELECT o.purpose,o.signing_key_epoch,o.receipt_message FROM c_auth.receipt_outbox o JOIN c_auth.slot_ledger l USING(slot_id) WHERE o.slot_id=$1 AND NOT l.receipt_acknowledged AND o.state IN ('PENDING_SIGN','READY')`, slot[:]).Scan(&purpose, &epoch, &job.Message)
	if errors.Is(err, pgx.ErrNoRows) {
		return job, ErrReceiptPending
	}
	if err != nil {
		return job, err
	}
	job.Slot = slot
	job.Purpose = wirePurpose(purpose)
	job.Epoch = uint32(epoch)
	return job, nil
}

// StoreSignature compares the original message and epoch. A late HSM result
// cannot replace a rotated job or recreate a cleaned/acknowledged outbox.
func (c *Community) StoreSignature(ctx context.Context, job ReceiptJob, signature []byte) (bool, error) {
	if len(signature) != 64 {
		return false, ErrIntentInvalid
	}
	wire := append(append([]byte{}, job.Message...), signature...)
	receipt, err := c.verifier.VerifyReceipt(protocol.EncodeCanonicalBase64url(wire), job.Purpose)
	if err != nil {
		return false, err
	}
	if receipt.Slot != job.Slot || receipt.Epoch != job.Epoch {
		return false, ErrIntentInvalid
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx)
	if err = lockSlot(ctx, tx, job.Slot[:]); err != nil {
		return false, err
	}
	var acknowledged bool
	var state string
	err = tx.QueryRow(ctx, `SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`, job.Slot[:]).Scan(&state, &acknowledged)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, ErrSlotUnavailable
	}
	if err != nil {
		return false, err
	}
	if acknowledged {
		return false, nil
	}
	command, err := tx.Exec(ctx, `UPDATE c_auth.receipt_outbox SET signature=$1,state='READY' WHERE slot_id=$2 AND purpose=$3 AND signing_key_epoch=$4 AND receipt_message=$5 AND state IN ('PENDING_SIGN','READY')`, signature, job.Slot[:], sqlPurpose(job.Purpose), int64(job.Epoch), job.Message)
	if err != nil {
		return false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return false, err
	}
	return command.RowsAffected() == 1, nil
}

type Signer func(context.Context, uint32, []byte) ([]byte, error)

func (c *Community) SignReceipt(ctx context.Context, slot protocol.SlotID, sign Signer) (bool, error) {
	job, err := c.ReceiptJob(ctx, slot)
	if err != nil {
		return false, err
	}
	signature, err := sign(ctx, job.Epoch, append([]byte{}, job.Message...))
	if err != nil {
		return false, err
	}
	return c.StoreSignature(ctx, job, signature)
}

// ReceiptReceiver is a trusted transport boundary. The isolated lab invokes the
// verifier DB command directly in storage tests; authprivacyhttp.PeerClient
// authenticates the environment-bound peer and requires the exact request's
// 200 ACKNOWLEDGED for the network boundary.
type ReceiptReceiver func(context.Context, string, protocol.Purpose) error

func (c *Community) DeliverReceipt(ctx context.Context, slot protocol.SlotID, receive ReceiptReceiver) error {
	var message, signature []byte
	var purpose string
	err := c.pool.QueryRow(ctx, `SELECT receipt_message,signature,purpose FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='READY'`, slot[:]).Scan(&message, &signature, &purpose)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrReceiptPending
	}
	if err != nil {
		return err
	}
	wire := append(append([]byte{}, message...), signature...)
	if _, err = c.verifier.VerifyReceipt(protocol.EncodeCanonicalBase64url(wire), wirePurpose(purpose)); err != nil {
		return err
	}
	if err = receive(ctx, protocol.EncodeCanonicalBase64url(wire), wirePurpose(purpose)); err != nil {
		return err
	}
	if _, err = c.verifier.VerifyReceipt(protocol.EncodeCanonicalBase64url(wire), wirePurpose(purpose)); err != nil {
		return err
	}
	return c.recordACK(ctx, slot, wirePurpose(purpose))
}

func (c *Community) recordACK(ctx context.Context, slot protocol.SlotID, purpose protocol.Purpose) error {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return err
	}
	defer c.gate.Abort(ctx, tx)
	if err = lockSlot(ctx, tx, slot[:]); err != nil {
		return err
	}
	var acknowledged bool
	var state string
	if err = tx.QueryRow(ctx, `SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`, slot[:]).Scan(&state, &acknowledged); err != nil {
		return err
	}
	if (state == "RETIRED" && purpose != protocol.PurposeRetired) || (state == "CLOSED" && purpose != protocol.PurposeReleased) || state == "ACTIVE" {
		return ErrReconciliation
	}
	if acknowledged {
		_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation)
		return err
	}
	if purpose == protocol.PurposeReleased {
		if _, err = tx.Exec(ctx, `SELECT closure_id FROM c_auth.closure_requests
			WHERE slot_id=$1 ORDER BY closure_id FOR UPDATE`, slot[:]); err != nil {
			return err
		}
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		command, e := tx.Exec(ctx, `UPDATE c_auth.receipt_outbox SET state='ACKED',ack_at=$3
			WHERE slot_id=$1 AND purpose=$2 AND state IN ('PENDING_SIGN','READY')`, slot[:], sqlPurpose(purpose), final.TrustedAt)
		if e != nil {
			return e
		}
		if command.RowsAffected() != 1 {
			return ErrReconciliation
		}
		if _, e = tx.Exec(ctx, `UPDATE c_auth.slot_ledger SET receipt_acknowledged=true WHERE slot_id=$1`, slot[:]); e != nil {
			return e
		}
		// Preserve the first trusted ACK time after delivery material is cleaned.
		// Repeated ACKs and key rotation never restart the status lifetime.
		if purpose == protocol.PurposeReleased {
			_, e = tx.Exec(ctx, `UPDATE c_auth.closure_requests SET released_at=COALESCE(released_at,$2)
				WHERE slot_id=$1 AND state='CLOSED_RELEASE_PENDING'`, slot[:], final.TrustedAt)
		}
		return e
	})
	return err
}

func (c *Community) RotateReceiptEpoch(ctx context.Context, slot protocol.SlotID, epoch uint32) error {
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err = lockSlot(ctx, tx, slot[:]); err != nil {
		return err
	}
	var acknowledged bool
	var state string
	if err = tx.QueryRow(ctx, `SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`, slot[:]).Scan(&state, &acknowledged); err != nil {
		return err
	}
	if acknowledged {
		return tx.Commit(ctx)
	}
	purpose := protocol.PurposeRetired
	if state == "CLOSED" {
		purpose = protocol.PurposeReleased
	} else if state != "RETIRED" {
		return ErrSlotUnavailable
	}
	message, err := (protocol.Receipt{Purpose: purpose, Slot: slot, Epoch: epoch}).MessageBytes()
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `UPDATE c_auth.receipt_outbox SET signing_key_epoch=$1,receipt_message=$2,signature=NULL,state='PENDING_SIGN' WHERE slot_id=$3 AND purpose=$4 AND state IN ('PENDING_SIGN','READY')`, int64(epoch), message, slot[:], sqlPurpose(purpose))
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (c *Community) CleanupAcknowledged(ctx context.Context, before time.Time) (int64, error) {
	// Only delivery material is removed; the permanent ledger/ACK bit remains.
	command, err := c.pool.Exec(ctx, `DELETE FROM c_auth.receipt_outbox o USING c_auth.slot_ledger l WHERE o.slot_id=l.slot_id AND l.receipt_acknowledged AND o.state='ACKED' AND o.ack_at < $1`, before)
	if err != nil {
		return 0, err
	}
	return command.RowsAffected(), nil
}
