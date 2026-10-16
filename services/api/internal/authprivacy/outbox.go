package authprivacy

import (
	"bytes"
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
	Generation uint64
	ClaimToken [32]byte
	Signature []byte
}

// ReceiptJob reads only committed terminal state. HSM calls belong outside SQL
// transactions; neither a successful SQL write nor a signature is a V ACK.
func (c *Community) ReceiptJob(ctx context.Context, slot protocol.SlotID) (ReceiptJob, error) {
 return c.receiptJob(ctx, slot, nil)
}

func (c *Community) receiptJob(ctx context.Context, slot protocol.SlotID, claim *ReceiptJob) (ReceiptJob, error) {
 var job ReceiptJob
 decision, err := c.gate.Snapshot(ctx)
 if err != nil { return job, err }
 tx, err := begin(ctx, c.pool)
 if err != nil { return job, err }
 defer c.gate.Abort(ctx, tx)
 if err = lockSlot(ctx, tx, slot[:]); err != nil { return job, err }
 var state string
 var acknowledged bool
 if err = tx.QueryRow(ctx, `SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`, slot[:]).Scan(&state,&acknowledged); err != nil {
  if errors.Is(err,pgx.ErrNoRows) { return job,ErrReceiptPending }; return job,err
 }
 var purpose string
 var epoch int64
 var token []byte
 var claimUntil *time.Time
 var generation *int64
 err = tx.QueryRow(ctx, `SELECT purpose,signing_key_epoch,receipt_message,signature,claim_token,claim_until,claim_generation FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state IN ('PENDING_SIGN','READY') FOR UPDATE`,slot[:]).Scan(&purpose,&epoch,&job.Message,&job.Signature,&token,&claimUntil,&generation)
 if errors.Is(err,pgx.ErrNoRows) { return job,ErrReceiptPending }
 if err != nil { return job,err }
 if acknowledged || (state != "RETIRED" && state != "CLOSED") || (state=="RETIRED" && purpose!="RETIRED") || (state=="CLOSED" && purpose!="RELEASED") { return job,ErrReconciliation }
 job.Slot,job.Purpose,job.Epoch,job.Generation = slot,wirePurpose(purpose),uint32(epoch),decision.Generation
 _,err = c.gate.CommitAuthorized(ctx,tx,decision.Generation,func(final AuthorizationDecision) error {
  if claim != nil {
   if claim.Generation != final.Generation || generation == nil || uint64(*generation) != final.Generation || claimUntil == nil || !final.TrustedAt.Before(*claimUntil) || !bytes.Equal(token,claim.ClaimToken[:]) { return ErrReceiptPending }
   job.ClaimToken=claim.ClaimToken
  } else if claimUntil != nil && generation != nil && uint64(*generation)==final.Generation && final.TrustedAt.Before(*claimUntil) { return ErrReceiptPending }
  return nil
 })
 return job,err
}

// StoreSignature compares the original message and epoch. A late HSM result
// cannot replace a rotated job or recreate a cleaned/acknowledged outbox.
func (c *Community) StoreSignature(ctx context.Context, job ReceiptJob, signature []byte) (bool, error) {
 if len(signature) != 64 { return false,ErrIntentInvalid }
 wire := append(append([]byte{},job.Message...),signature...)
 receipt,err := c.verifier.VerifyReceipt(protocol.EncodeCanonicalBase64url(wire),job.Purpose)
 if err != nil { return false,err }
 if receipt.Slot != job.Slot || receipt.Epoch != job.Epoch { return false,ErrIntentInvalid }
 decision,err := c.gate.Snapshot(ctx)
 if err != nil { return false,err }
 if job.Generation == 0 || job.Generation != decision.Generation { return false,ErrAuthorizationUnavailable }
 tx,err := begin(ctx,c.pool)
 if err != nil { return false,err }
 defer c.gate.Abort(ctx,tx)
 if err = lockSlot(ctx,tx,job.Slot[:]); err != nil { return false,err }
 var acknowledged bool
 var state string
 err=tx.QueryRow(ctx,`SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`,job.Slot[:]).Scan(&state,&acknowledged)
 if errors.Is(err,pgx.ErrNoRows) { return false,ErrSlotUnavailable }
 if err != nil { return false,err }
 if (state != "RETIRED" && state != "CLOSED") || (state=="RETIRED" && job.Purpose!=protocol.PurposeRetired) || (state=="CLOSED" && job.Purpose!=protocol.PurposeReleased) { return false,ErrReconciliation }
 var stored bool
 _,err=c.gate.CommitAuthorized(ctx,tx,decision.Generation,func(final AuthorizationDecision) error {
  if acknowledged { return nil }
  var token any
  if job.ClaimToken != ([32]byte{}) { token=job.ClaimToken[:] }
  command,e:=tx.Exec(ctx,`UPDATE c_auth.receipt_outbox SET signature=$1,state='READY' WHERE slot_id=$2 AND purpose=$3 AND signing_key_epoch=$4 AND receipt_message=$5 AND state IN ('PENDING_SIGN','READY') AND (($6::bytea IS NULL AND (claim_until IS NULL OR claim_until<=$7 OR claim_generation<>$8)) OR (claim_token=$6 AND claim_until>$7 AND claim_generation=$8))`,signature,job.Slot[:],sqlPurpose(job.Purpose),int64(job.Epoch),job.Message,token,final.TrustedAt,int64(final.Generation))
  if e==nil { stored=command.RowsAffected()==1 }; return e
 })
 return stored,err
}

type Signer func(context.Context, uint32, []byte) ([]byte, error)

func (c *Community) SignReceipt(ctx context.Context, slot protocol.SlotID, sign Signer) (bool, error) {
	if sign == nil { return false, ErrIntentInvalid }
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
 return c.deliverReceipt(ctx,slot,nil,receive)
}

func (c *Community) deliverReceipt(ctx context.Context, slot protocol.SlotID, claim *ReceiptJob, receive ReceiptReceiver) error {
 if receive==nil { return ErrIntentInvalid }
 job,err := c.receiptJob(ctx,slot,claim)
 if err != nil { return err }
 if len(job.Signature)!=64 { return ErrReceiptPending }
 wire:=append(append([]byte{},job.Message...),job.Signature...)
 encoded:=protocol.EncodeCanonicalBase64url(wire)
 if _,err=c.verifier.VerifyReceipt(encoded,job.Purpose); err != nil { return err }
 // Authorization commits before the network effect. A later freeze cannot
 // retract an in-flight delivery; the ACK still needs its own final Gate.
 if err=receive(ctx,encoded,job.Purpose); err != nil { return err }
 if _,err=c.verifier.VerifyReceipt(encoded,job.Purpose); err != nil { return err }
 return c.recordACKForJob(ctx,slot,job.Purpose,&job)
}

func (c *Community) recordACK(ctx context.Context, slot protocol.SlotID, purpose protocol.Purpose) error {
 return c.recordACKForJob(ctx,slot,purpose,nil)
}

func (c *Community) recordACKForJob(ctx context.Context, slot protocol.SlotID, purpose protocol.Purpose, job *ReceiptJob) error {
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
	if job == nil { return ErrReceiptPending }
	if purpose == protocol.PurposeReleased {
		if _, err = tx.Exec(ctx, `SELECT closure_id FROM c_auth.closure_requests
			WHERE slot_id=$1 ORDER BY closure_id FOR UPDATE`, slot[:]); err != nil {
			return err
		}
	}
 var token,message []byte
 var epoch int64
 var until *time.Time
 var generation *int64
 if err=tx.QueryRow(ctx,`SELECT claim_token,claim_until,claim_generation,receipt_message,signing_key_epoch FROM c_auth.receipt_outbox WHERE slot_id=$1 AND purpose=$2 AND state IN ('PENDING_SIGN','READY') FOR UPDATE`,slot[:],sqlPurpose(purpose)).Scan(&token,&until,&generation,&message,&epoch); err!=nil {
  if errors.Is(err,pgx.ErrNoRows) { return ErrReceiptPending }; return err
 }
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
  if job != nil {
   if job.Generation!=final.Generation { return ErrAuthorizationUnavailable }
   if int64(job.Epoch)!=epoch || !bytes.Equal(job.Message,message) { return ErrReceiptPending }
   if job.ClaimToken!=([32]byte{}) {
    if until==nil || !final.TrustedAt.Before(*until) || generation==nil || uint64(*generation)!=final.Generation || !bytes.Equal(token,job.ClaimToken[:]) { return ErrReceiptPending }
   } else if until!=nil && generation!=nil && uint64(*generation)==final.Generation && final.TrustedAt.Before(*until) { return ErrReceiptPending }
  }
		command, e := tx.Exec(ctx, `UPDATE c_auth.receipt_outbox SET state='ACKED',ack_at=$3,claim_token=NULL,claim_until=NULL,claim_generation=NULL
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
 decision,err:=c.gate.Snapshot(ctx)
 if err != nil { return err }
 tx,err:=begin(ctx,c.pool)
 if err != nil { return err }
 defer c.gate.Abort(ctx,tx)
 if err=lockSlot(ctx,tx,slot[:]); err != nil { return err }
 var acknowledged bool
 var state string
 if err=tx.QueryRow(ctx,`SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`,slot[:]).Scan(&state,&acknowledged); err != nil { return err }
 purpose:=protocol.PurposeRetired
 if state=="CLOSED" { purpose=protocol.PurposeReleased } else if state!="RETIRED" { return ErrSlotUnavailable }
 message,err:=(protocol.Receipt{Purpose:purpose,Slot:slot,Epoch:epoch}).MessageBytes()
 if err != nil { return err }
 _,err=c.gate.CommitAuthorized(ctx,tx,decision.Generation,func(AuthorizationDecision) error {
  if acknowledged { return nil }
  _,e:=tx.Exec(ctx,`UPDATE c_auth.receipt_outbox SET signing_key_epoch=$1,receipt_message=$2,signature=NULL,state='PENDING_SIGN',claim_token=NULL,claim_until=NULL,claim_generation=NULL WHERE slot_id=$3 AND purpose=$4 AND signing_key_epoch<=$1 AND state IN ('PENDING_SIGN','READY')`,int64(epoch),message,slot[:],sqlPurpose(purpose))
  return e
 })
 return err
}

// CleanupAcknowledged keeps the historical explicit cutoff API bounded. The
// final trusted time always caps its cutoff, and only durable ACKs qualify.
func (c *Community) CleanupAcknowledged(ctx context.Context,before time.Time) (int64,error) {
 if before.IsZero() { return 0, ErrIntentInvalid }
 return c.cleanupAcknowledged(ctx,before,0,100)
}

// CleanupAcknowledgedBatch derives the retention cutoff inside the final Gate;
// restarting or duplicate ACKs cannot restart the durable ACK lifetime.
func (c *Community) CleanupAcknowledgedBatch(ctx context.Context,retention time.Duration,limit int) (int64,error) {
 if retention<0 { return 0,ErrIntentInvalid }
 return c.cleanupAcknowledged(ctx,time.Time{},retention,limit)
}

func (c *Community) cleanupAcknowledged(ctx context.Context,before time.Time,retention time.Duration,limit int) (int64,error) {
 if limit<1 || limit>500 { return 0,ErrIntentInvalid }
 decision,err:=c.gate.Snapshot(ctx)
 if err != nil { return 0,err }
 cutoff:=decision.TrustedAt.Add(-retention)
 if !before.IsZero() && before.Before(cutoff) { cutoff=before }
 slots,err:=c.receiptSlots(ctx,decision,limit,true,cutoff)
 if err != nil { return 0,err }
 var removed int64
 for _,slot:=range slots {
  tx,e:=begin(ctx,c.pool)
  if e!=nil { return removed,e }
  if e=lockSlot(ctx,tx,slot[:]); e!=nil { c.gate.Abort(ctx,tx); return removed,e }
  var ack bool
  if e=tx.QueryRow(ctx,`SELECT receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`,slot[:]).Scan(&ack); e!=nil { c.gate.Abort(ctx,tx); return removed,e }
  // Lock delivery material after the ledger, before the final Gate.
  var ackAt *time.Time
  e=tx.QueryRow(ctx,`SELECT ack_at FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='ACKED' FOR UPDATE`,slot[:]).Scan(&ackAt)
  if errors.Is(e,pgx.ErrNoRows) { c.gate.Abort(ctx,tx); continue }
  if e!=nil { c.gate.Abort(ctx,tx); return removed,e }
  var deleted int64
  _,e=c.gate.CommitAuthorized(ctx,tx,decision.Generation,func(final AuthorizationDecision) error {
   cutoff:=final.TrustedAt.Add(-retention)
   if !before.IsZero() && before.Before(cutoff) { cutoff=before }
   if !ack || ackAt==nil || !ackAt.Before(cutoff) { return nil }
   tag,e:=tx.Exec(ctx,`DELETE FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='ACKED' AND ack_at<$2`,slot[:],cutoff)
   if e==nil { deleted=tag.RowsAffected() }; return e
  })
  c.gate.Abort(ctx,tx)
  if e!=nil { return removed,e }; removed+=deleted
 }
 return removed,nil
}

// receiptSlots is a bounded authorized enumeration, followed by per-slot
// rechecks using the ordinary slot -> ledger -> outbox -> Gate lock order.
func (c *Community) receiptSlots(ctx context.Context,d AuthorizationDecision,limit int,acked bool,cutoff time.Time) ([]protocol.SlotID,error) {
 tx,err:=begin(ctx,c.pool)
 if err!=nil { return nil,err }
 defer c.gate.Abort(ctx,tx)
 sql:=`SELECT o.slot_id FROM c_auth.receipt_outbox o JOIN c_auth.slot_ledger l USING(slot_id) WHERE NOT l.receipt_acknowledged AND o.state IN ('PENDING_SIGN','READY') AND (o.claim_until IS NULL OR o.claim_until<=$2 OR o.claim_generation<>$3) ORDER BY o.slot_id LIMIT $1`
 if acked { sql=`SELECT o.slot_id FROM c_auth.receipt_outbox o JOIN c_auth.slot_ledger l USING(slot_id) WHERE l.receipt_acknowledged AND o.state='ACKED' AND o.ack_at<$2 AND $3::bigint>0 ORDER BY o.ack_at,o.slot_id LIMIT $1` }
 rows,err:=tx.Query(ctx,sql,limit,cutoff,int64(d.Generation))
 if err!=nil { return nil,err }
 var slots []protocol.SlotID
 for rows.Next() {
  var raw []byte
  if err=rows.Scan(&raw); err!=nil || len(raw)!=32 { rows.Close(); return nil,ErrReconciliation }
  var slot protocol.SlotID; copy(slot[:],raw); slots=append(slots,slot)
 }
 err=rows.Err(); rows.Close()
 if err!=nil { return nil,err }
 if _,err=c.gate.CommitAuthorized(ctx,tx,d.Generation); err!=nil { return nil,err }
 return slots,nil
}

// ClaimReceiptJobs leases at most limit committed terminal jobs. Lease tokens
// identify attempts, never business events; a crashed claim is retried only
// after its trusted expiry or an explicit Gate generation change.
func (c *Community) ClaimReceiptJobs(ctx context.Context,limit int,lease time.Duration) ([]ReceiptJob,error) {
 if limit<1 || limit>500 || lease<time.Second || lease>5*time.Minute { return nil,ErrIntentInvalid }
 decision,err:=c.gate.Snapshot(ctx)
 if err!=nil { return nil,err }
 slots,err:=c.receiptSlots(ctx,decision,limit,false,decision.TrustedAt)
 if err!=nil { return nil,err }
 var jobs []ReceiptJob
 for _,slot:=range slots {
  job,claimed,e:=c.claimReceipt(ctx,decision,slot,lease)
  if e!=nil { return jobs,e }
  if claimed { jobs=append(jobs,job) }
 }
 return jobs,nil
}

func (c *Community) claimReceipt(ctx context.Context,decision AuthorizationDecision,slot protocol.SlotID,lease time.Duration) (ReceiptJob,bool,error) {
 var job ReceiptJob
 token,err:=random32()
 if err!=nil { return job,false,err }
 tx,err:=begin(ctx,c.pool)
 if err!=nil { return job,false,err }
 defer c.gate.Abort(ctx,tx)
 if err=lockSlot(ctx,tx,slot[:]); err!=nil { return job,false,err }
 var ack bool
 var terminal string
 if err=tx.QueryRow(ctx,`SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`,slot[:]).Scan(&terminal,&ack); err!=nil { return job,false,err }
 var purpose string
 var epoch int64
 var until *time.Time
 var generation *int64
 err=tx.QueryRow(ctx,`SELECT purpose,signing_key_epoch,receipt_message,signature,claim_until,claim_generation FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state IN ('PENDING_SIGN','READY') FOR UPDATE`,slot[:]).Scan(&purpose,&epoch,&job.Message,&job.Signature,&until,&generation)
 if errors.Is(err,pgx.ErrNoRows) { return job,false,nil }; if err!=nil { return job,false,err }
 if ack || (terminal!="RETIRED" && terminal!="CLOSED") || (terminal=="RETIRED" && purpose!="RETIRED") || (terminal=="CLOSED" && purpose!="RELEASED") { return job,false,ErrReconciliation }
 var claimed bool
 _,err=c.gate.CommitAuthorized(ctx,tx,decision.Generation,func(final AuthorizationDecision) error {
  if until!=nil && generation!=nil && uint64(*generation)==final.Generation && final.TrustedAt.Before(*until) { return nil }
  tag,e:=tx.Exec(ctx,`UPDATE c_auth.receipt_outbox SET claim_token=$2,claim_until=$3,claim_generation=$4 WHERE slot_id=$1 AND state IN ('PENDING_SIGN','READY')`,slot[:],token[:],final.TrustedAt.Add(lease),int64(final.Generation))
  if e==nil { claimed=tag.RowsAffected()==1 }; return e
 })
 job.Slot,job.Purpose,job.Epoch,job.Generation,job.ClaimToken=slot,wirePurpose(purpose),uint32(epoch),decision.Generation,token
 return job,claimed,err
}

func (c *Community) ProcessReceiptJob(ctx context.Context,job ReceiptJob,sign Signer,receive ReceiptReceiver) error {
 if job.ClaimToken==([32]byte{}) || sign==nil || receive==nil { return ErrIntentInvalid }
 // A batch may wait before its next item starts. Reauthorize its original
 // claim before scheduling expensive work, so a freeze or expired/superseded
 // lease stops tasks which have not started their external operation.
 current,err:=c.receiptJob(ctx,job.Slot,&job)
 if err!=nil { return err }
 if current.Epoch!=job.Epoch || current.Purpose!=job.Purpose || !bytes.Equal(current.Message,job.Message) { return ErrReceiptPending }
 job=current
 if len(job.Signature)==0 {
  signature,err:=sign(ctx,job.Epoch,append([]byte{},job.Message...))
  if err!=nil { return err }
  stored,err:=c.StoreSignature(ctx,job,signature)
  if err!=nil { return err }; if !stored { return ErrReceiptPending }
 }
 return c.deliverReceipt(ctx,job.Slot,&job,receive)
}
