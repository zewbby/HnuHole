package authprivacy

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

// RetireUnusedSlot is the C application boundary behind the mTLS adapter. An
// authorization cannot alter ACTIVE/CLOSED slots or return any account data.
func (c *Community) RetireUnusedSlot(ctx context.Context, encoded string) (RetirementReply, error) {
	authorization, err := c.verifier.VerifyRetirementAuthorization(encoded)
	if err != nil {
		return RetirementReply{}, err
	}
	if err = c.RetireSlot(ctx, encoded); err != nil {
		return RetirementReply{}, err
	}
	var acknowledged bool
	var state, purpose string
	var message, signature []byte
	var epoch *int64
	err = c.pool.QueryRow(ctx, `SELECT l.state,l.receipt_acknowledged,COALESCE(o.purpose,''),o.receipt_message,o.signature,o.signing_key_epoch FROM c_auth.slot_ledger l LEFT JOIN c_auth.receipt_outbox o USING(slot_id) WHERE l.slot_id=$1`, authorization.Slot[:]).Scan(&state, &acknowledged, &purpose, &message, &signature, &epoch)
	if err != nil || state != "RETIRED" {
		if err == nil {
			err = ErrReconciliation
		}
		return RetirementReply{}, err
	}
	if len(signature) == 64 && purpose == "RETIRED" {
		return c.validRetirementReply(authorization.Slot, message, signature)
	}
	if acknowledged {
		// Permanent terminal evidence grants read-only re-signing. Never recreate
		// the cleaned outbox, change the ACK bit or restart the retention clock.
		if c.receiptSigner == nil {
			return RetirementReply{}, errors.New("receipt signer unavailable")
		}
		receipt := protocol.Receipt{Purpose: protocol.PurposeRetired, Epoch: c.signingEpoch, Slot: authorization.Slot}
		message, err = receipt.MessageBytes()
		if err != nil {
			return RetirementReply{}, err
		}
		signature, err = c.receiptSigner(ctx, receipt.Epoch, append([]byte{}, message...))
		if err != nil {
			return RetirementReply{}, errors.New("receipt signing unavailable")
		}
		var stillAcknowledged bool
		var stillState string
		if err = c.pool.QueryRow(ctx, `SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1`, authorization.Slot[:]).Scan(&stillState, &stillAcknowledged); err != nil || stillState != "RETIRED" || !stillAcknowledged {
			return RetirementReply{}, ErrReconciliation
		}
		return c.validRetirementReply(authorization.Slot, message, signature)
	}
	if epoch == nil || purpose != "RETIRED" {
		return RetirementReply{}, ErrReconciliation
	}
	if c.receiptSigner != nil {
		job, err := c.ReceiptJob(ctx, authorization.Slot)
		if err != nil {
			if errors.Is(err, ErrReceiptPending) {
				return RetirementReply{Pending: true, RetryAfterSeconds: 2}, nil
			}
			return RetirementReply{}, err
		}
		signed, err := c.receiptSigner(ctx, job.Epoch, append([]byte{}, job.Message...))
		if err != nil {
			return RetirementReply{Pending: true, RetryAfterSeconds: 2}, nil
		}
		ready, err := c.StoreSignature(ctx, job, signed)
		if err != nil {
			return RetirementReply{}, errors.New("receipt signature commit unavailable")
		}
		if ready {
			// Re-read the committed signature, also allowing a concurrently ACKed
			// READY job. The job may have been cleaned after ACK; retry is safe.
			if err = c.pool.QueryRow(ctx, `SELECT receipt_message,signature FROM c_auth.receipt_outbox WHERE slot_id=$1 AND purpose='RETIRED' AND signature IS NOT NULL`, authorization.Slot[:]).Scan(&message, &signature); err == nil {
				return c.validRetirementReply(authorization.Slot, message, signature)
			} else if !errors.Is(err, pgx.ErrNoRows) {
				return RetirementReply{}, err
			}
		}
	}
	return RetirementReply{Pending: true, RetryAfterSeconds: 2}, nil
}

func (c *Community) validRetirementReply(slot protocol.SlotID, message, signature []byte) (RetirementReply, error) {
	wire := append(append([]byte{}, message...), signature...)
	encoded := protocol.EncodeCanonicalBase64url(wire)
	receipt, err := c.verifier.VerifyReceipt(encoded, protocol.PurposeRetired)
	if err != nil || receipt.Slot != slot {
		// Output/trust failures are not reported as bad input authorization.
		return RetirementReply{}, errors.New("stored retirement receipt unavailable")
	}
	return RetirementReply{Receipt: encoded}, nil
}
