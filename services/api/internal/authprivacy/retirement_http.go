package authprivacy

import (
 "context"
 "errors"

 "github.com/jackc/pgx/v5"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type retirementRead struct {
 acknowledged bool
 purpose string
 message,signature []byte
}

// authorizedRetirementRead follows the worker's slot -> ledger -> outbox ->
// Gate order. It grants a response only for this request's original generation;
// the earlier terminal write alone does not authorize a later receipt response.
func (c *Community) authorizedRetirementRead(ctx context.Context,slot protocol.SlotID,generation uint64) (retirementRead,error) {
 var result retirementRead
 tx,err:=begin(ctx,c.pool)
 if err!=nil { return result,ErrAuthorizationUnavailable }
 defer c.gate.Abort(ctx,tx)
 if err=lockSlot(ctx,tx,slot[:]); err!=nil { return result,ErrAuthorizationUnavailable }
 var state string
 if err=tx.QueryRow(ctx,`SELECT state,receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`,slot[:]).Scan(&state,&result.acknowledged); err!=nil { return result,ErrAuthorizationUnavailable }
 var outboxState string
 err=tx.QueryRow(ctx,`SELECT purpose,receipt_message,signature,state FROM c_auth.receipt_outbox WHERE slot_id=$1 FOR UPDATE`,slot[:]).Scan(&result.purpose,&result.message,&result.signature,&outboxState)
 missing:=errors.Is(err,pgx.ErrNoRows)
 if err!=nil && !missing { return result,ErrAuthorizationUnavailable }
 _,err=c.gate.CommitAuthorized(ctx,tx,generation,func(AuthorizationDecision) error {
  if state!="RETIRED" { return ErrReconciliation }
  if result.acknowledged {
   if !missing && (result.purpose!="RETIRED" || outboxState!="ACKED") { return ErrReconciliation }
  } else if missing || result.purpose!="RETIRED" || (outboxState!="PENDING_SIGN" && outboxState!="READY") { return ErrReconciliation }
  return nil
 })
 if err!=nil { return retirementRead{},err }
 return result,nil
}

// RetireUnusedSlot is the C application boundary behind the mTLS adapter. An
// authorization cannot alter ACTIVE/CLOSED slots or return any account data.
func (c *Community) RetireUnusedSlot(ctx context.Context,encoded string) (RetirementReply,error) {
 authorization,err:=c.verifier.VerifyRetirementAuthorization(encoded)
 if err!=nil { return RetirementReply{},err }
 decision,err:=c.gate.Snapshot(ctx)
 if err!=nil { return RetirementReply{},err }
 if err=c.retireAuthorizedSlot(ctx,authorization.Slot,decision); err!=nil { return RetirementReply{},err }
 current,err:=c.authorizedRetirementRead(ctx,authorization.Slot,decision.Generation)
 if err!=nil { return RetirementReply{},err }
 if len(current.signature)==64 && current.purpose=="RETIRED" {
  return c.validRetirementReply(authorization.Slot,current.message,current.signature)
 }
 if current.acknowledged {
  // Permanent terminal evidence grants read-only re-signing. Never recreate
  // the cleaned outbox, change the ACK bit or restart the retention clock.
  if c.receiptSigner==nil { return RetirementReply{},errors.New("receipt signer unavailable") }
  receipt:=protocol.Receipt{Purpose:protocol.PurposeRetired,Epoch:c.signingEpoch,Slot:authorization.Slot}
  message,err:=receipt.MessageBytes()
  if err!=nil { return RetirementReply{},err }
  signature,err:=c.receiptSigner(ctx,receipt.Epoch,append([]byte{},message...))
  if err!=nil { return RetirementReply{},ErrAuthorizationUnavailable }
  // Signing stays outside SQL locks. A freeze or recovery while it is in
  // flight must reject the old response, even though RETIRED is immutable.
  final,err:=c.authorizedRetirementRead(ctx,authorization.Slot,decision.Generation)
  if err!=nil { return RetirementReply{},err }
  if !final.acknowledged { return RetirementReply{},ErrReconciliation }
  return c.validRetirementReply(authorization.Slot,message,signature)
 }
 if c.receiptSigner!=nil {
  job,jobErr:=c.ReceiptJob(ctx,authorization.Slot)
  if jobErr!=nil && !errors.Is(jobErr,ErrReceiptPending) { return RetirementReply{},jobErr }
  if jobErr==nil {
   if job.Generation!=decision.Generation { return RetirementReply{},ErrAuthorizationUnavailable }
   signed,signErr:=c.receiptSigner(ctx,job.Epoch,append([]byte{},job.Message...))
   if signErr==nil {
    if _,err=c.StoreSignature(ctx,job,signed); err!=nil { return RetirementReply{},ErrAuthorizationUnavailable }
   }
  }
 }
 // A worker lease can make an unsigned job temporarily unavailable. The final
 // read may observe that worker's committed READY/ACKED result; it otherwise
 // returns a bounded PENDING response under the same original Gate fence.
 final,err:=c.authorizedRetirementRead(ctx,authorization.Slot,decision.Generation)
 if err!=nil { return RetirementReply{},err }
 if len(final.signature)==64 && final.purpose=="RETIRED" {
  return c.validRetirementReply(authorization.Slot,final.message,final.signature)
 }
 return RetirementReply{Pending:true,RetryAfterSeconds:2},nil
}

func (c *Community) validRetirementReply(slot protocol.SlotID,message,signature []byte) (RetirementReply,error) {
 wire:=append(append([]byte{},message...),signature...)
 encoded:=protocol.EncodeCanonicalBase64url(wire)
 receipt,err:=c.verifier.VerifyReceipt(encoded,protocol.PurposeRetired)
 if err!=nil || receipt.Slot!=slot {
  // Output/trust failures are not reported as bad input authorization.
  return RetirementReply{},errors.New("stored retirement receipt unavailable")
 }
 return RetirementReply{Receipt:encoded},nil
}
