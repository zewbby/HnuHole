package authprivacy

import (
 "context"
 "crypto/ed25519"
 "errors"
 "testing"
 "time"

 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func retiredWorkerSlot(t *testing.T,l *lab) protocol.SlotID {
 t.Helper()
 ticket,_:=l.ticket(t)
 if err:=l.c.RetireSlot(context.Background(),l.authorization(ticket.Slot)); err!=nil { t.Fatal(err) }
 return ticket.Slot
}

func TestReceiptClaimsAreExclusiveAndExpiredAttemptCannotWritePostgres(t *testing.T) {
 control:=newGateControl(t)
 l:=control.lab
 ctx,cancel:=context.WithTimeout(context.Background(),30*time.Second)
 defer cancel()
 slot:=retiredWorkerSlot(t,l)
 hold,err:=l.cp.Begin(ctx)
 if err!=nil { t.Fatal(err) }
 defer hold.Rollback(context.Background())
 if err=lockSlot(ctx,hold,slot[:]); err!=nil { t.Fatal(err) }
 type reply struct { jobs []ReceiptJob; err error }
 replies:=make(chan reply,2)
 for i:=0;i<2;i++ { go func(){ jobs,err:=l.c.ClaimReceiptJobs(ctx,1,30*time.Second); replies<-reply{jobs,err} }() }
 waitLock(t,l.cp,"advisory",2)
 if err=hold.Rollback(ctx); err!=nil { t.Fatal(err) }
 var claimed []ReceiptJob
 for i:=0;i<2;i++ { result:=<-replies; if result.err!=nil { t.Fatal(result.err) }; claimed=append(claimed,result.jobs...) }
 if len(claimed)!=1 || claimed[0].Slot!=slot { t.Fatalf("competing instances claimed %d jobs",len(claimed)) }
 old:=claimed[0]
 signerFailure:=errors.New("signer unavailable after durable claim")
 if err=l.c.ProcessReceiptJob(ctx,old,func(context.Context,uint32,[]byte)([]byte,error){return nil,signerFailure},func(context.Context,string,protocol.Purpose)error{return nil}); !errors.Is(err,signerFailure) { t.Fatalf("signer failure lost: %v",err) }
 if count(t,l.cp,`SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='PENDING_SIGN' AND signature IS NULL AND claim_token=$2`,slot[:],old.ClaimToken[:])!=1 { t.Fatal("signer failure changed the durable terminal event") }
 if jobs,err:=l.c.ClaimReceiptJobs(ctx,1,30*time.Second); err!=nil || len(jobs)!=0 { t.Fatalf("live lease was reclaimed: %d %v",len(jobs),err) }
 // A persisted lease represents the crashed worker. Advancing independent
 // evidence recovers exactly that event, with a fresh attempt token.
 advanceClosureClock(t,control,control.clock.now().Add(31*time.Second))
 recovered,err:=l.c.ClaimReceiptJobs(ctx,1,30*time.Second)
 if err!=nil || len(recovered)!=1 || recovered[0].ClaimToken==old.ClaimToken || recovered[0].Slot!=old.Slot { t.Fatalf("crashed lease did not resume the same event: %d %v",len(recovered),err) }
 signature:=ed25519.Sign(l.cPrivate,old.Message)
 if stored,err:=l.c.StoreSignature(ctx,old,signature); err!=nil || stored { t.Fatalf("late signer wrote through superseding claim: %v %v",stored,err) }
 if stored,err:=l.c.StoreSignature(ctx,recovered[0],signature); err!=nil || !stored { t.Fatalf("current claim failed: %v %v",stored,err) }
 if count(t,l.cp,`SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='READY' AND claim_token=$2`,slot[:],recovered[0].ClaimToken[:])!=1 { t.Fatal("signature changed the durable claim identity") }
}

func TestReceiptSignerInFlightCannotCommitAcrossFreezePostgres(t *testing.T) {
 control:=newGateControl(t)
 l:=control.lab
 ctx,cancel:=context.WithTimeout(context.Background(),30*time.Second)
 defer cancel()
 slot:=retiredWorkerSlot(t,l)
 jobs,err:=l.c.ClaimReceiptJobs(ctx,1,30*time.Second)
 if err!=nil || len(jobs)!=1 { t.Fatalf("claim failed: %v",err) }
 signing:=make(chan struct{})
 release:=make(chan struct{})
 done:=make(chan error,1)
 go func(){ done<-l.c.ProcessReceiptJob(ctx,jobs[0],func(context.Context,uint32,[]byte)([]byte,error){ close(signing); <-release; return ed25519.Sign(l.cPrivate,jobs[0].Message),nil },func(context.Context,string,protocol.Purpose)error{ return errors.New("receipt crossed freeze before delivery") }) }()
 select { case <-signing: case <-ctx.Done(): t.Fatal("signer did not start") }
 if err=control.gate.Freeze(ctx,"signer in flight"); err!=nil { t.Fatal(err) }
 close(release)
 if err=<-done; !errors.Is(err,ErrAuthorizationUnavailable) { t.Fatalf("in-flight signature crossed freeze: %v",err) }
 if count(t,l.cp,`SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='PENDING_SIGN' AND signature IS NULL`,slot[:])!=1 { t.Fatal("frozen signer partially committed") }
 if _,err=l.c.ClaimReceiptJobs(ctx,1,30*time.Second); !errors.Is(err,ErrAuthorizationUnavailable) { t.Fatalf("frozen scheduler claimed new work: %v",err) }
 control.clock.set(control.clock.now().Add(time.Second))
 control.recover(t,AuthorizationRecoveryNormal,3,4)
 resumed,err:=l.c.ClaimReceiptJobs(ctx,1,30*time.Second)
 if err!=nil || len(resumed)!=1 { t.Fatalf("new generation could not reclaim original event: %v",err) }
 if err=l.c.ProcessReceiptJob(ctx,resumed[0],func(_ context.Context,_ uint32,message []byte)([]byte,error){ return ed25519.Sign(l.cPrivate,message),nil },func(context.Context,string,protocol.Purpose)error{return nil}); err!=nil { t.Fatal(err) }
 if count(t,l.cp,`SELECT count(*) FROM c_auth.slot_ledger l JOIN c_auth.receipt_outbox o USING(slot_id) WHERE l.slot_id=$1 AND l.receipt_acknowledged AND o.state='ACKED' AND o.claim_token IS NULL`,slot[:])!=1 { t.Fatal("recovery did not persist a terminal ACK") }
}

func TestReceiptCleanupFinalGatePreservesAckAndRetentionPostgres(t *testing.T) {
 control:=newGateControl(t)
 l:=control.lab
 ctx,cancel:=context.WithTimeout(context.Background(),30*time.Second)
 defer cancel()
 slot:=retiredWorkerSlot(t,l)
 sign:=func(_ context.Context,_ uint32,message []byte)([]byte,error){ return ed25519.Sign(l.cPrivate,message),nil }
 if _,err:=l.c.SignReceipt(ctx,slot,sign); err!=nil { t.Fatal(err) }
 if err:=l.c.DeliverReceipt(ctx,slot,func(context.Context,string,protocol.Purpose)error{return nil}); err!=nil { t.Fatal(err) }
 if n,err:=l.c.CleanupAcknowledgedBatch(ctx,24*time.Hour,1); err!=nil || n!=0 { t.Fatalf("ACK retention was shortened: %d %v",n,err) }
 advanceClosureClock(t,control,control.clock.now().Add(24*time.Hour+time.Second))
 hold,err:=l.cp.Begin(ctx)
 if err!=nil { t.Fatal(err) }
 defer hold.Rollback(context.Background())
 if err=lockSlot(ctx,hold,slot[:]); err!=nil { t.Fatal(err) }
 done:=make(chan error,1)
 go func(){ _,err:=l.c.CleanupAcknowledgedBatch(ctx,24*time.Hour,1); done<-err }()
 waitLock(t,l.cp,"advisory",1)
 if err=control.gate.Freeze(ctx,"cleanup awaiting slot lock"); err!=nil { t.Fatal(err) }
 if err=hold.Rollback(ctx); err!=nil { t.Fatal(err) }
 if err=<-done; !errors.Is(err,ErrAuthorizationUnavailable) { t.Fatalf("cleanup crossed freeze: %v",err) }
 if count(t,l.cp,`SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='ACKED'`,slot[:])!=1 { t.Fatal("freeze erased acknowledged delivery evidence") }
 control.clock.set(control.clock.now().Add(time.Second))
 control.recover(t,AuthorizationRecoveryNormal,3,4)
 if n,err:=l.c.CleanupAcknowledgedBatch(ctx,24*time.Hour,1); err!=nil || n!=1 { t.Fatalf("trusted retained ACK was not cleaned: %d %v",n,err) }
 if count(t,l.cp,`SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1 AND receipt_acknowledged`,slot[:])!=1 { t.Fatal("cleanup lost permanent ACK authority") }
 if _,err=l.c.ReceiptJob(ctx,slot); !errors.Is(err,ErrReceiptPending) { t.Fatalf("cleaned event was resurrected: %v",err) }
}

func TestReceiptLateACKCannotUseRecoveredGenerationOrNewClaimPostgres(t *testing.T) {
 control:=newGateControl(t)
 l:=control.lab
 ctx,cancel:=context.WithTimeout(context.Background(),30*time.Second)
 defer cancel()
 slot:=retiredWorkerSlot(t,l)
 jobs,err:=l.c.ClaimReceiptJobs(ctx,1,30*time.Second)
 if err!=nil || len(jobs)!=1 { t.Fatalf("claim failed: %v",err) }
 delivered:=make(chan struct{})
 releaseACK:=make(chan struct{})
 done:=make(chan error,1)
 sign:=func(_ context.Context,_ uint32,message []byte)([]byte,error){return ed25519.Sign(l.cPrivate,message),nil}
 go func(){ done<-l.c.ProcessReceiptJob(ctx,jobs[0],sign,func(context.Context,string,protocol.Purpose)error{ close(delivered); <-releaseACK; return nil }) }()
 select { case <-delivered: case <-ctx.Done(): t.Fatal("delivery did not reach remote ACK barrier") }
 if err=control.gate.Freeze(ctx,"remote ACK in flight"); err!=nil { t.Fatal(err) }
 control.clock.set(control.clock.now().Add(time.Second))
 control.recover(t,AuthorizationRecoveryNormal,3,4)
 current,err:=l.c.ClaimReceiptJobs(ctx,1,30*time.Second)
 if err!=nil || len(current)!=1 || current[0].ClaimToken==jobs[0].ClaimToken { t.Fatalf("recovered generation did not supersede claim: %v",err) }
 close(releaseACK)
 if err=<-done; !errors.Is(err,ErrAuthorizationUnavailable) { t.Fatalf("old ACK used recovered authorization generation: %v",err) }
 if count(t,l.cp,`SELECT count(*) FROM c_auth.slot_ledger l JOIN c_auth.receipt_outbox o USING(slot_id) WHERE l.slot_id=$1 AND NOT l.receipt_acknowledged AND o.state='READY' AND o.ack_at IS NULL AND o.claim_token=$2`,slot[:],current[0].ClaimToken[:])!=1 { t.Fatal("old network callback acknowledged the new attempt") }
 if err=l.c.ProcessReceiptJob(ctx,current[0],sign,func(context.Context,string,protocol.Purpose)error{return nil}); err!=nil { t.Fatal(err) }
 if count(t,l.cp,`SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1 AND receipt_acknowledged`,slot[:])!=1 { t.Fatal("current claim did not persist remote terminal ACK") }
}

func TestReceiptClaimWaitingToStartDoesNotScheduleSignerAfterFreezePostgres(t *testing.T) {
 control:=newGateControl(t)
 l:=control.lab
 slot:=retiredWorkerSlot(t,l)
 jobs,err:=l.c.ClaimReceiptJobs(context.Background(),1,30*time.Second)
 if err!=nil || len(jobs)!=1 { t.Fatalf("claim failed: %v",err) }
 if err=control.gate.Freeze(context.Background(),"claimed work has not started"); err!=nil { t.Fatal(err) }
 calls:=0
 err=l.c.ProcessReceiptJob(context.Background(),jobs[0],func(context.Context,uint32,[]byte)([]byte,error){calls++; return nil,errors.New("frozen signer was scheduled")},func(context.Context,string,protocol.Purpose)error{calls++;return nil})
 if !errors.Is(err,ErrAuthorizationUnavailable) || calls!=0 { t.Fatalf("frozen claimed work scheduled an external effect: calls=%d err=%v",calls,err) }
 if count(t,l.cp,`SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='PENDING_SIGN' AND signature IS NULL AND ack_at IS NULL`,slot[:])!=1 { t.Fatal("waiting claimed work changed across freeze") }
}
