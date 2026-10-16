package authprivacy

import (
 "context"
 "errors"
 "testing"
 "time"
)

func TestQueuedMailDigestWorkersNeverRepeatClaimedOrUnknownPostgres(t *testing.T) {
 l,e,capture:=newOTPTestEligibility(t,MailUnknown)
 ctx,cancel:=context.WithTimeout(context.Background(),30*time.Second)
 defer cancel()
 request:=otpFixtureRequest(t,"mail.worker-competition@hainanu.edu.cn")
 if _,err:=e.queueOTP(ctx,request); err!=nil { t.Fatal(err) }
 hold,err:=l.vp.Begin(ctx)
 if err!=nil { t.Fatal(err) }
 defer hold.Rollback(context.Background())
 if err=e.store.lockAddress(ctx,hold,[]byte(request.Email)); err!=nil { t.Fatal(err) }
 done:=make(chan error,2)
 for i:=0;i<2;i++ { go func(){ _,err:=e.ResumeQueuedMail(ctx,1); done<-err }() }
 waitLock(t,l.vp,"advisory",2)
 if err=hold.Rollback(ctx); err!=nil { t.Fatal(err) }
 for i:=0;i<2;i++ { if err=<-done; err!=nil { t.Fatal(err) } }
 if calls,_:=capture.captured(); calls!=1 { t.Fatalf("competing digest workers sent %d times",calls) }
 if n,err:=e.ResumeQueuedMail(ctx,1); err!=nil || n!=0 { t.Fatalf("UNKNOWN was rescheduled: %d %v",n,err) }
 if result,err:=e.GetOTPRequestResult(ctx,request.Key,request.InstallationID); err!=nil || result.State!="PENDING" { t.Fatalf("unknown SMTP result became known: %+v %v",result,err) }
 // Simulate a process crash after the dispatch transaction committed and
 // before it touched SMTP. Neither startup nor the original raw-key retry
 // is allowed to repeat an attempt with unknown acceptance.
 crashed:=otpFixtureRequest(t,"mail.worker-crashed@hainanu.edu.cn")
 if _,err=e.queueOTP(ctx,crashed); err!=nil { t.Fatal(err) }
 key:=digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1",crashed.Key[:])
 mustExec(t,l.vp,`UPDATE v_auth.mail_outbox SET state='DISPATCHING' WHERE key_digest=$1`,key[:])
 if n,err:=e.ResumeQueuedMail(ctx,10); err!=nil || n!=0 { t.Fatalf("crashed DISPATCHING was rescheduled: %d %v",n,err) }
 if outcome,err:=e.DispatchMail(ctx,crashed.Key); err!=nil || outcome!=MailUnknown { t.Fatalf("raw-key retry changed crashed outcome: %s %v",outcome,err) }
 if calls,_:=capture.captured(); calls!=1 { t.Fatal("crashed dispatch produced a duplicate SMTP send") }
}

func TestExpiredUnknownMailErasesAssociationWithoutSendingPostgres(t *testing.T) {
 for _,state:=range []string{"DISPATCHING","UNKNOWN"} {
  t.Run(state,func(t *testing.T) {
   l,e,capture:=newOTPTestEligibility(t,MailSent)
   ctx:=context.Background()
   request:=otpFixtureRequest(t,"expired.worker@hainanu.edu.cn")
   flow,_:=random32(); operation,_:=random32()
   key:=digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1",request.Key[:])
   mac:=requestMAC(e.config.RequestHMACKey,[]byte("HNUHOLE/V-OTP-REQUEST/V1"),[]byte(request.Email),request.InstallationID[:])
   tx,err:=l.vp.Begin(ctx)
   if err!=nil { t.Fatal(err) }
   defer tx.Rollback(context.Background())
   var old time.Time
   if err=tx.QueryRow(ctx,`SELECT clock_timestamp()-interval '11 minutes'`).Scan(&old); err!=nil { t.Fatal(err) }
   for _,step:=range []struct{ sql string; args []any }{
    {`INSERT INTO v_auth.otp_email_state(email_exact,code_generation,latest_flow_id,send_wait_until) VALUES($1,1,$2,$3)`,[]any{[]byte(request.Email),flow[:],old.Add(time.Minute)}},
    {`INSERT INTO v_auth.otp_flows(flow_id,email_exact,installation_id,code_generation,state,created_at,expires_at) VALUES($1,$2,$3,1,'ACTIVE',$4,$4::timestamptz+interval '5 minutes')`,[]any{flow[:],[]byte(request.Email),request.InstallationID[:],old}},
    {`INSERT INTO v_auth.request_results(operation,key_digest,state,request_hmac,hmac_key_version,installation_id,flow_id,result_code,expires_at) VALUES('OTP_REQUEST',$1,'LIVE',$2,1,$3,$4,'PENDING',$5::timestamptz+interval '10 minutes')`,[]any{key[:],mac[:],request.InstallationID[:],flow[:],old}},
   } { if _,err=tx.Exec(ctx,step.sql,step.args...); err!=nil { t.Fatal(err) } }
   var email,ciphertext,nonce []byte
   var version any
   if state=="DISPATCHING" { email=[]byte(request.Email); ciphertext=make([]byte,22); nonce=make([]byte,12); version=int64(1) }
   if _,err=tx.Exec(ctx,`INSERT INTO v_auth.mail_outbox(operation_id,key_digest,flow_id,state,email_exact,ciphertext,nonce,encryption_key_version,expires_at,send_wait_until,previous_send_wait_until) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::timestamptz+interval '5 minutes',$9::timestamptz+interval '1 minute',$9)`,operation[:],key[:],flow[:],state,email,ciphertext,nonce,version,old); err!=nil { t.Fatal(err) }
   if err=tx.Commit(ctx); err!=nil { t.Fatal(err) }
   if err=e.CleanupOTP(ctx,1); err!=nil { t.Fatal(err) }
   if calls,_:=capture.captured(); calls!=0 { t.Fatal("expired unknown cleanup touched SMTP") }
   if count(t,l.vp,`SELECT count(*) FROM v_auth.mail_outbox`)!=0 || count(t,l.vp,`SELECT count(*) FROM v_auth.otp_flows` )!=0 { t.Fatal("expired unknown result retained email/flow linkage") }
   if count(t,l.vp,`SELECT count(*) FROM v_auth.request_results WHERE key_digest=$1 AND state='EXPIRED' AND request_hmac IS NULL AND installation_id IS NULL AND flow_id IS NULL`,key[:])!=1 { t.Fatal("unknown cleanup lost permanent request tombstone") }
   if _,err=e.RequestOTP(ctx,request); !errors.Is(err,ErrExpired) { t.Fatalf("old unknown request became sendable after cleanup: %v",err) }
  })
 }
}

type inspectedMailProvider func(context.Context,[32]byte,string,string)(MailOutcome,error)

func (send inspectedMailProvider) SendOTP(ctx context.Context,id [32]byte,email,code string)(MailOutcome,error) {
 return send(ctx,id,email,code)
}

func TestMailWorkerPersistsDispatchAndReleasesLocksBeforeSMTPPostgres(t *testing.T) {
 l,e,_:=newOTPTestEligibility(t,MailSent)
 ctx,cancel:=context.WithTimeout(context.Background(),10*time.Second)
 defer cancel()
 request:=otpFixtureRequest(t,"mail.worker-before-data@hainanu.edu.cn")
 if _,err:=e.queueOTP(ctx,request); err!=nil { t.Fatal(err) }
 key:=digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1",request.Key[:])
 explicitFailure:=errors.New("SMTP rejected before DATA")
 inspected:=false
 e.mail=inspectedMailProvider(func(sendCtx context.Context,_ [32]byte,email,code string)(MailOutcome,error) {
  var state string
  if err:=l.vp.QueryRow(sendCtx,`SELECT state FROM v_auth.mail_outbox WHERE key_digest=$1`,key[:]).Scan(&state); err!=nil { return MailUnknown,err }
  if state!="DISPATCHING" || email!=request.Email || !validOTPShape(code) { return MailUnknown,errors.New("SMTP ran without committed original dispatch") }
  // A separate connection must obtain the same locks during SMTP. A send
  // moved inside the claim transaction fails this deterministic lock probe.
  probeCtx,probeCancel:=context.WithTimeout(sendCtx,2*time.Second)
  defer probeCancel()
  tx,err:=l.vp.Begin(probeCtx)
  if err!=nil { return MailUnknown,err }
  defer tx.Rollback(context.Background())
  if err=e.store.lockAddress(probeCtx,tx,[]byte(email)); err!=nil { return MailUnknown,err }
  if err=lockVRequest(probeCtx,tx,key); err!=nil { return MailUnknown,err }
  if _,err=readOTPMail(probeCtx,tx,key,true); err!=nil { return MailUnknown,err }
  if err=tx.Commit(probeCtx); err!=nil { return MailUnknown,err }
  inspected=true
  return MailNotSent,explicitFailure
 })
 if n,err:=e.ResumeQueuedMail(ctx,1); n!=1 || !errors.Is(err,explicitFailure) || !inspected { t.Fatalf("dispatch/lock probe failed: n=%d inspected=%v err=%v",n,inspected,err) }
 if count(t,l.vp,`SELECT count(*) FROM v_auth.mail_outbox WHERE key_digest=$1 AND state='NOT_SENT' AND ciphertext IS NULL AND nonce IS NULL AND email_exact IS NULL`,key[:])!=1 { t.Fatal("explicit pre-DATA failure retained uncertain mail or plaintext binding") }
 if count(t,l.vp,`SELECT count(*) FROM v_auth.otp_flows WHERE flow_id=(SELECT flow_id FROM v_auth.mail_outbox WHERE key_digest=$1) AND state='EXPIRED'`,key[:])!=1 { t.Fatal("definitely unsent OTP stayed valid") }
 if n,err:=e.ResumeQueuedMail(ctx,1); err!=nil || n!=0 { t.Fatalf("known NOT_SENT attempt was sent again: %d %v",n,err) }
}
