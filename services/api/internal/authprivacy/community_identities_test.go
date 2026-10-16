package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
)

type identitySnapshotBarrier struct {
	AuthorizationGate
	mu sync.Mutex
	paused bool
	captured, release chan struct{}
}

func (g *identitySnapshotBarrier) Snapshot(ctx context.Context) (AuthorizationDecision, error) {
	d, err := g.AuthorizationGate.Snapshot(ctx)
	if err != nil { return d,err }
	g.mu.Lock()
	pause := !g.paused
	g.paused = true
	g.mu.Unlock()
	if pause {
		close(g.captured)
		select {
		case <-g.release:
		case <-ctx.Done(): return AuthorizationDecision{},ErrAuthorizationUnavailable
		}
	}
	return d,nil
}

func identityRequestKey(t *testing.T) [16]byte {
	t.Helper()
	raw, err := random32()
	if err != nil { t.Fatal(err) }
	var key [16]byte
	copy(key[:], raw[:16])
	return key
}

func identityChange(t *testing.T, c *Community, bearer [32]byte, operation string, id uuid.UUID, nickname string) IdentityChangeResult {
	t.Helper()
	result, err := c.ChangeOwnIdentity(context.Background(), IdentityChangeRequest{Bearer: bearer, ChangeID: identityRequestKey(t), Operation: operation, IdentityID: id, Nickname: nickname})
	if err != nil || result.State != "COMMITTED" || result.Operation != operation || result.IdentityID == uuid.Nil || result.ExpiresAt.IsZero() {
		t.Fatalf("%s identity: %v", operation, err)
	}
	return result
}

func identityDirectory(t *testing.T, c *Community, bearer [32]byte) IdentityDirectory {
	t.Helper()
	result, err := c.ListOwnIdentities(context.Background(), bearer)
	if err != nil || result.Identities == nil || result.ServerTime.IsZero() || result.ExpiresAt.IsZero() {
		t.Fatalf("identity directory: %v", err)
	}
	return result
}

func identityRejected(result IdentityChangeResult, err error, code string) bool {
	return err == nil && result.State == "REJECTED" && result.ErrorCode == code &&
		result.IdentityID == uuid.Nil && !result.ExpiresAt.IsZero()
}

func TestIdentityInitialManagementAndAccountLocalNamesPostgres(t *testing.T) {
	l, ctx := newLab(t), context.Background()
	owner := sessionTestAccount(t,l,"identity_profile_user")
	foreign := sessionTestAccount(t,l,"identity_other_user")
	empty := identityDirectory(t,l.c,owner.SessionToken)
	if len(empty.Identities) != 0 || empty.CreatedCount != 0 || empty.NextCreateAt != nil {
		t.Fatal("signup automatically created an identity")
	}
	if directory, err := l.c.ListAuthorizedChannels(ctx,owner.SessionToken); err != nil || len(directory.Channels) != 7 {
		t.Fatalf("zero-identity account could not browse: %v",err)
	}
	first := identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"e\u0301风")
	view := identityDirectory(t,l.c,owner.SessionToken)
	if view.CreatedCount != 1 || len(view.Identities) != 1 || view.NextCreateAt != nil ||
		view.Identities[0].ID != first.IdentityID || view.Identities[0].Nickname != "é风" ||
		view.Identities[0].Avatar != IdentityDefaultAvatar || !view.Identities[0].IsOriginal || view.Identities[0].RenameAvailableAt != nil {
		t.Fatal("initial identity/default avatar/canonical name contract")
	}
	identityChange(t,l.c,foreign.SessionToken,"CREATE",uuid.Nil,"é风")
	duplicate := IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: "CREATE", Nickname: "é风"}
	if result,err := l.c.ChangeOwnIdentity(ctx,duplicate); !identityRejected(result,err,"IDENTITY_DUPLICATE_NAME") { t.Fatalf("same-account canonical duplicate: %v",err) }
	if result,err := l.c.GetIdentityChangeResult(ctx,owner.SessionToken,duplicate.ChangeID); !identityRejected(result,err,"IDENTITY_DUPLICATE_NAME") { t.Fatalf("failed create lacked terminal receipt: %v",err) }
	second := identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"Ab")
	identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"ab")
	if result,err := l.c.ChangeOwnIdentity(ctx,IdentityChangeRequest{Bearer: owner.SessionToken,ChangeID: identityRequestKey(t),Operation:"CREATE",Nickname:"海风"}); !identityRejected(result,err,"IDENTITY_LIMIT") { t.Fatalf("fourth active identity: %v",err) }
	if result,err := l.c.ChangeOwnIdentity(ctx,IdentityChangeRequest{Bearer: owner.SessionToken,ChangeID: identityRequestKey(t),Operation:"RENAME",IdentityID:second.IdentityID,Nickname:"ab"}); !identityRejected(result,err,"IDENTITY_DUPLICATE_NAME") { t.Fatalf("rename formed duplicate: %v",err) }
	identityChange(t,l.c,owner.SessionToken,"DELETE",first.IdentityID,"")
	view=identityDirectory(t,l.c,owner.SessionToken)
	if len(view.Identities)!=2 || view.CreatedCount!=3 || view.NextCreateAt==nil { t.Fatal("deletion reset count or cooldown") }
	if count(t,l.cp,`SELECT count(*) FROM public.community_identities WHERE identity_id=$1 AND deleted_at IS NOT NULL AND nickname IS NULL AND avatar IS NULL`,first.IdentityID)!=1 { t.Fatal("deletion retained original profile or removed tombstone") }
	identityChange(t,l.c,owner.SessionToken,"DELETE",second.IdentityID,"")
	view=identityDirectory(t,l.c,owner.SessionToken)
	if result,err := l.c.ChangeOwnIdentity(ctx,IdentityChangeRequest{Bearer:owner.SessionToken,ChangeID:identityRequestKey(t),Operation:"DELETE",IdentityID:view.Identities[0].ID}); !identityRejected(result,err,"IDENTITY_LAST_REQUIRED") { t.Fatalf("last identity deleted: %v",err) }
	if count(t,l.cp,`SELECT count(*) FROM public.identity_change_receipts WHERE account_id=$1 AND state='COMMITTED'`,owner.AccountID)!=5 || count(t,l.cp,`SELECT count(*) FROM public.identity_change_receipts WHERE account_id=$1 AND state='REJECTED'`,owner.AccountID)!=4 { t.Fatal("successful/rejected receipts did not match final outcomes") }
}

func TestIdentityCumulativeCreationAndCalendarCooldownPostgres(t *testing.T) {
	control:=newGateControl(t)
	l,ctx:=control.lab,context.Background()
	owner:=sessionTestAccount(t,l,"identity_calendar_user")
	first:=identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"海风")
	identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"山林")
	identityChange(t,l.c,owner.SessionToken,"DELETE",first.IdentityID,"")
	third:=identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"星河")
	view:=identityDirectory(t,l.c,owner.SessionToken)
	if view.CreatedCount!=3 || len(view.Identities)!=2 || view.NextCreateAt==nil {t.Fatal("deleted slot bypassed cumulative third-create threshold")}
	for _,item:=range view.Identities {if item.IsOriginal {t.Fatal("recreation inherited deleted original marker")}}
	blocked:=IdentityChangeRequest{Bearer:owner.SessionToken,ChangeID:identityRequestKey(t),Operation:"CREATE",Nickname:"秋雨"}
	if result,err:=l.c.ChangeOwnIdentity(ctx,blocked);!identityRejected(result,err,"IDENTITY_CREATE_COOLDOWN"){t.Fatalf("before six months: %v",err)}
	advanceClosureClock(t,control,view.NextCreateAt.Add(-time.Microsecond))
	login,err:=l.c.CreateSession(ctx,sessionTestRequest(t,"identity_calendar_user"),sessionTestPasswordWorker(t,1));if err!=nil{t.Fatal(err)}
	blocked.Bearer=login.SessionToken
	if result,e:=l.c.ChangeOwnIdentity(ctx,blocked);!identityRejected(result,e,"IDENTITY_CREATE_COOLDOWN"){t.Fatalf("rejected intent replay: %v",e)}
	blocked.ChangeID=identityRequestKey(t)
	if result,e:=l.c.ChangeOwnIdentity(ctx,blocked);!identityRejected(result,e,"IDENTITY_CREATE_COOLDOWN"){t.Fatalf("one microsecond before boundary: %v",e)}
	advanceClosureClock(t,control,*view.NextCreateAt)
	if result,e:=l.c.ChangeOwnIdentity(ctx,blocked);!identityRejected(result,e,"IDENTITY_CREATE_COOLDOWN"){t.Fatalf("delayed rejected original applied at cooldown boundary: %v",e)}
	blocked.ChangeID=identityRequestKey(t)
	created,err:=l.c.ChangeOwnIdentity(ctx,blocked);if err!=nil || created.State!="COMMITTED" {t.Fatalf("exact six-month boundary: %v",err)}
	view=identityDirectory(t,l.c,login.SessionToken)
	if view.CreatedCount!=4 || len(view.Identities)!=3 || view.NextCreateAt==nil || !view.NextCreateAt.Equal(*identityNextCreateAt(4,&view.ServerTime)) {t.Fatal("successful create did not start next six-month interval")}
	identityChange(t,l.c,login.SessionToken,"DELETE",third.IdentityID,"")
	if result,e:=l.c.ChangeOwnIdentity(ctx,IdentityChangeRequest{Bearer:login.SessionToken,ChangeID:identityRequestKey(t),Operation:"CREATE",Nickname:"晚霞"});!identityRejected(result,e,"IDENTITY_CREATE_COOLDOWN"){t.Fatalf("delete reset new interval: %v",e)}
}

func TestIdentityRenameIntervalAndNoopPostgres(t *testing.T) {
	control:=newGateControl(t)
	l,ctx:=control.lab,context.Background()
	owner:=sessionTestAccount(t,l,"identity_rename_user")
	created:=identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"海风")
	identityChange(t,l.c,owner.SessionToken,"RENAME",created.IdentityID,"海风")
	view:=identityDirectory(t,l.c,owner.SessionToken)
	if view.Identities[0].RenameAvailableAt!=nil {t.Fatal("unchanged name consumed initial rename")}
	identityChange(t,l.c,owner.SessionToken,"RENAME",created.IdentityID,"山林")
	view=identityDirectory(t,l.c,owner.SessionToken)
	deadline:=*view.Identities[0].RenameAvailableAt
	identityChange(t,l.c,owner.SessionToken,"RENAME",created.IdentityID,"山林")
	if after:=identityDirectory(t,l.c,owner.SessionToken);!after.Identities[0].RenameAvailableAt.Equal(deadline){t.Fatal("same-name retry extended rename cooldown")}
	request:=IdentityChangeRequest{Bearer:owner.SessionToken,ChangeID:identityRequestKey(t),Operation:"RENAME",IdentityID:created.IdentityID,Nickname:"星河"}
	if result,err:=l.c.ChangeOwnIdentity(ctx,request);!identityRejected(result,err,"IDENTITY_RENAME_COOLDOWN"){t.Fatalf("immediate second rename: %v",err)}
	advanceClosureClock(t,control,deadline.Add(-time.Microsecond))
	login,err:=l.c.CreateSession(ctx,sessionTestRequest(t,"identity_rename_user"),sessionTestPasswordWorker(t,1));if err!=nil{t.Fatal(err)}
	request.Bearer=login.SessionToken
	request.ChangeID=identityRequestKey(t)
	if result,e:=l.c.ChangeOwnIdentity(ctx,request);!identityRejected(result,e,"IDENTITY_RENAME_COOLDOWN"){t.Fatalf("before 30 days: %v",e)}
	advanceClosureClock(t,control,deadline)
	if result,e:=l.c.ChangeOwnIdentity(ctx,request);!identityRejected(result,e,"IDENTITY_RENAME_COOLDOWN"){t.Fatalf("delayed rejected rename applied at boundary: %v",e)}
	request.ChangeID=identityRequestKey(t)
	if result,e:=l.c.ChangeOwnIdentity(ctx,request);e!=nil || result.State!="COMMITTED"{t.Fatalf("exact 30-day boundary: %v",e)}
	view=identityDirectory(t,l.c,login.SessionToken)
	if view.CreatedCount!=1 || !view.Identities[0].RenameAvailableAt.Equal(deadline.Add(30*24*time.Hour)) {t.Fatal("rename created identity or did not restart interval")}
}

func TestIdentityReceiptReplayOwnershipAndTombstonesPostgres(t *testing.T) {
	l,ctx:=newLab(t),context.Background()
	owner:=sessionTestAccount(t,l,"identity_replay_user")
	foreign:=sessionTestAccount(t,l,"identity_foreign_user")
	request:=IdentityChangeRequest{Bearer:owner.SessionToken,ChangeID:identityRequestKey(t),Operation:"CREATE",Nickname:"海风"}
	if result,err:=l.c.GetIdentityChangeResult(ctx,owner.SessionToken,request.ChangeID);err!=nil || result.State!="NOT_FOUND" || result.IdentityID!=uuid.Nil || result.Operation!="" {t.Fatalf("unsubmitted query: %v",err)}
	created,err:=l.c.ChangeOwnIdentity(ctx,request);if err!=nil{t.Fatal(err)}
	replayed,err:=l.c.ChangeOwnIdentity(ctx,request);if err!=nil || replayed.IdentityID!=created.IdentityID{t.Fatalf("unknown result replay created twice: %v",err)}
	changed:=request;changed.Nickname="星河"
	if _,err=l.c.ChangeOwnIdentity(ctx,changed);!errors.Is(err,ErrIdentityChangeConflict){t.Fatalf("changed payload reused key: %v",err)}
	changed.Operation="DELETE";changed.IdentityID=created.IdentityID;changed.Nickname=""
	if _,err=l.c.ChangeOwnIdentity(ctx,changed);!errors.Is(err,ErrIdentityChangeConflict){t.Fatalf("changed operation reused key: %v",err)}
	if result,err:=l.c.GetIdentityChangeResult(ctx,foreign.SessionToken,request.ChangeID);err!=nil || result.State!="NOT_FOUND" {t.Fatalf("foreign result leaked: %v",err)}
	for _,op:=range []string{"RENAME","DELETE"} {
		name:="";if op=="RENAME"{name="山林"}
		if result,e:=l.c.ChangeOwnIdentity(ctx,IdentityChangeRequest{Bearer:foreign.SessionToken,ChangeID:identityRequestKey(t),Operation:op,IdentityID:created.IdentityID,Nickname:name});!identityRejected(result,e,"IDENTITY_NOT_FOUND"){t.Fatalf("foreign %s: %v",op,e)}
	}
	// Account-scoped keys permit a different account to use the same opaque
	// key for its own command, with no cross-account receipt lock.
	foreignRequest:=request;foreignRequest.Bearer=foreign.SessionToken
	if result,err:=l.c.ChangeOwnIdentity(ctx,foreignRequest);err!=nil || result.IdentityID==created.IdentityID {t.Fatalf("foreign account key collision: %v",err)}
	identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"秋雨")
	identityChange(t,l.c,owner.SessionToken,"DELETE",created.IdentityID,"")
	if result,err:=l.c.ChangeOwnIdentity(ctx,request);err!=nil || result.IdentityID!=created.IdentityID {t.Fatalf("replay resurrected/delegitimized deleted create: %v",err)}
	login,err:=l.c.CreateSession(ctx,sessionTestRequest(t,"identity_replay_user"),sessionTestPasswordWorker(t,1));if err!=nil{t.Fatal(err)}
	if result,err:=l.c.GetIdentityChangeResult(ctx,login.SessionToken,request.ChangeID);err!=nil || result.IdentityID!=created.IdentityID || result.State!="COMMITTED"{t.Fatalf("same account successor lost receipt: %v",err)}
	if _,err=l.c.GetIdentityChangeResult(ctx,owner.SessionToken,request.ChangeID);!errors.Is(err,ErrSessionReplaced){t.Fatalf("replaced session read receipt: %v",err)}
	if count(t,l.cp,`SELECT created_count FROM public.identity_account_state WHERE account_id=$1`,owner.AccountID)!=2 {t.Fatal("replay incremented cumulative counter")}
}

func TestIdentityConcurrentCreateDeleteAndDuplicatePostgres(t *testing.T) {
	for _,scenario:=range []string{"slots","duplicate","last-delete","same-key"} {
		t.Run(scenario,func(t *testing.T){
			l,ctx:=newLab(t),context.Background()
			owner:=sessionTestAccount(t,l,"identity_concurrent_user")
			requests:=make([]IdentityChangeRequest,4)
			for i,name:=range []string{"海风","山林","星河","秋雨"} {requests[i]=IdentityChangeRequest{Bearer:owner.SessionToken,ChangeID:identityRequestKey(t),Operation:"CREATE",Nickname:name}}
			successWant,errorWant:=3,1
			expected:="IDENTITY_LIMIT"
			switch scenario {
			case "duplicate":
				for i:=range requests {requests[i].Nickname="海风"};successWant,errorWant,expected=1,3,"IDENTITY_DUPLICATE_NAME"
			case "last-delete":
				first:=identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"海风")
				second:=identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"山林")
				requests=requests[:2]
				requests[0].Operation,requests[0].IdentityID,requests[0].Nickname="DELETE",first.IdentityID,""
				requests[1].Operation,requests[1].IdentityID,requests[1].Nickname="DELETE",second.IdentityID,""
				successWant,errorWant,expected=1,1,"IDENTITY_LAST_REQUIRED"
			case "same-key":
				for i:=range requests {requests[i]=requests[0]};successWant,errorWant=4,0
			}
			var wg sync.WaitGroup
			type outcome struct {result IdentityChangeResult;err error}
			outcomes:=make(chan outcome,len(requests));ids:=make(chan uuid.UUID,len(requests))
			for _,request:=range requests {request:=request;wg.Add(1);go func(){defer wg.Done();result,err:=l.c.ChangeOwnIdentity(ctx,request);outcomes<-outcome{result,err};if err==nil && result.State=="COMMITTED"{ids<-result.IdentityID}}()}
			wg.Wait();close(outcomes);close(ids)
			succeeded,rejected:=0,0
			for answer:=range outcomes {if answer.err==nil && answer.result.State=="COMMITTED"{succeeded++}else if identityRejected(answer.result,answer.err,expected){rejected++}else{t.Fatalf("unexpected concurrent outcome %+v: %v",answer.result,answer.err)}}
			if succeeded!=successWant || rejected!=errorWant {t.Fatalf("concurrent %s success=%d rejection=%d",scenario,succeeded,rejected)}
			view:=identityDirectory(t,l.c,owner.SessionToken)
			if scenario=="same-key" {var one uuid.UUID;for id:=range ids{if one!=uuid.Nil && id!=one{t.Fatal("same key produced distinct identity IDs")};one=id};if view.CreatedCount!=1 || len(view.Identities)!=1{t.Fatal("same-key concurrent replay consumed slots")}}
			if scenario=="last-delete" && len(view.Identities)!=1 {t.Fatal("concurrent deletion left zero identities")}
		})
	}
}

func TestIdentityFinalGateAndSessionOutrankDomainErrorsPostgres(t *testing.T) {
	for _,scenario:=range []string{"freeze","expiry","revocation","pending-close","ban","replacement"} {
		t.Run(scenario,func(t *testing.T){
			control:=newGateControl(t)
			l,ctx:=control.lab,context.Background()
			owner:=sessionTestAccount(t,l,"identity_gate_wait_user")
			hash:=sha256.Sum256(owner.SessionToken[:])
			before:=control.clock.now().Add(time.Minute)
			mustExec(t,l.cp,`UPDATE c_auth.sessions SET expires_at=$2 WHERE token_digest=$1`,hash[:],before)
			hold,err:=l.cp.Begin(ctx);if err!=nil{t.Fatal(err)};defer hold.Rollback(ctx)
			var state string
			if err=hold.QueryRow(ctx,`SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`,owner.AccountID).Scan(&state);err!=nil{t.Fatal(err)}
			answer:=make(chan error,1)
			// Invalid nickname must not outrank final session invalidation.
			go func(){result,err:=l.c.ChangeOwnIdentity(ctx,IdentityChangeRequest{Bearer:owner.SessionToken,ChangeID:identityRequestKey(t),Operation:"CREATE",Nickname:"bad name"});if err==nil || result.State!=""{answer<-errors.New("unauthorized identity mutation published result");return};answer<-err}()
			waitLock(t,l.cp,"transactionid",1)
			expected:=ErrSessionInvalid
			switch scenario {
			case "freeze":
				expected=ErrAuthorizationUnavailable;if err=l.gate.Freeze(ctx,"identity wait across freeze");err!=nil{t.Fatal(err)}
			case "expiry":control.clock.set(before.Add(time.Second))
			case "revocation":_,err=hold.Exec(ctx,`UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason='LOGOUT' WHERE token_digest=$1`,hash[:],control.clock.now())
			case "pending-close":_,err=hold.Exec(ctx,`UPDATE c_auth.accounts SET state='PENDING_CLOSE' WHERE account_id=$1`,owner.AccountID)
			case "ban":_,err=hold.Exec(ctx,`UPDATE c_auth.account_restrictions SET ban_state='BANNED',ban_ends_at=NULL,version=version+1 WHERE account_id=$1`,owner.AccountID)
			case "replacement":
				expected=ErrSessionReplaced
				if _,err=hold.Exec(ctx,`UPDATE c_auth.accounts SET session_generation=session_generation+1 WHERE account_id=$1`,owner.AccountID);err==nil{_,err=hold.Exec(ctx,`UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason='REPLACED' WHERE token_digest=$1`,hash[:],control.clock.now())}
			}
			if err!=nil{t.Fatal(err)};if err=hold.Commit(ctx);err!=nil{t.Fatal(err)}
			if err=<-answer;!errors.Is(err,expected){t.Fatalf("%s final authority: %v",scenario,err)}
			if count(t,l.cp,`SELECT count(*) FROM public.community_identities WHERE account_id=$1`,owner.AccountID)!=0 || count(t,l.cp,`SELECT count(*) FROM public.identity_change_receipts WHERE account_id=$1`,owner.AccountID)!=0 {t.Fatal("rejected mutation committed data")}
			var expiry time.Time
			if err=l.cp.QueryRow(ctx,`SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`,hash[:]).Scan(&expiry);err!=nil || !expiry.Equal(before){t.Fatalf("rejected mutation renewed session: %v",err)}
		})
	}
}

func TestIdentityFrozenGateCoversListResultAndMutationPostgres(t *testing.T) {
	l,ctx:=newLab(t),context.Background()
	owner:=sessionTestAccount(t,l,"identity_frozen_user")
	if err:=l.gate.Freeze(ctx,"identity frozen access");err!=nil{t.Fatal(err)}
	for _,bearer:=range [][32]byte{owner.SessionToken,{99}} {
		if result,err:=l.c.ListOwnIdentities(ctx,bearer);!errors.Is(err,ErrAuthorizationUnavailable) || result.Identities!=nil{t.Fatalf("frozen list: %v",err)}
		if result,err:=l.c.GetIdentityChangeResult(ctx,bearer,identityRequestKey(t));!errors.Is(err,ErrAuthorizationUnavailable) || result.State!=""{t.Fatalf("frozen result: %v",err)}
		if result,err:=l.c.ChangeOwnIdentity(ctx,IdentityChangeRequest{Bearer:bearer,ChangeID:identityRequestKey(t),Operation:"CREATE",Nickname:"海风"});!errors.Is(err,ErrAuthorizationUnavailable) || result.State!=""{t.Fatalf("frozen mutation: %v",err)}
	}
}

func TestIdentityRejectedRetryPreventsDelayedOriginalAfterStateChangesPostgres(t *testing.T) {
	l:=newLab(t)
	ctx,cancel:=context.WithTimeout(context.Background(),20*time.Second)
	defer cancel()
	owner:=sessionTestAccount(t,l,"identity_delay_user")
	existing:=identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"海风")
	request:=IdentityChangeRequest{Bearer:owner.SessionToken,ChangeID:identityRequestKey(t),Operation:"CREATE",Nickname:"海风"}
	barrier:=&identitySnapshotBarrier{AuthorizationGate:l.gate,captured:make(chan struct{}),release:make(chan struct{})}
	l.c.gate=barrier
	defer func(){l.c.gate=l.gate}()
	var once sync.Once
	unblock:=func(){once.Do(func(){close(barrier.release)})}
	defer unblock()
	type outcome struct{result IdentityChangeResult;err error}
	answer:=make(chan outcome,1)
	go func(){result,err:=l.c.ChangeOwnIdentity(ctx,request);answer<-outcome{result,err}}()
	select{case <-barrier.captured:case <-ctx.Done():t.Fatal("original did not reach pre-account-lock barrier")}
	if result,err:=l.c.GetIdentityChangeResult(ctx,owner.SessionToken,request.ChangeID);err!=nil || result.State!="NOT_FOUND"{t.Fatalf("query before delayed original: %v",err)}
	if result,err:=l.c.ChangeOwnIdentity(ctx,request);!identityRejected(result,err,"IDENTITY_DUPLICATE_NAME"){t.Fatalf("retry did not bind rejected key: %v",err)}
	if result,err:=l.c.GetIdentityChangeResult(ctx,owner.SessionToken,request.ChangeID);!identityRejected(result,err,"IDENTITY_DUPLICATE_NAME"){t.Fatalf("rejected retry lookup: %v",err)}
	// The original CREATE would now be allowed without the rejected receipt.
	identityChange(t,l.c,owner.SessionToken,"RENAME",existing.IdentityID,"山林")
	unblock()
	select{
	case result:=<-answer:
		if !identityRejected(result.result,result.err,"IDENTITY_DUPLICATE_NAME"){t.Fatalf("delayed original applied after definitive rejection: %+v %v",result.result,result.err)}
	case <-ctx.Done():t.Fatal("delayed original did not complete")
	}
	view:=identityDirectory(t,l.c,owner.SessionToken)
	if view.CreatedCount!=1 || len(view.Identities)!=1 || view.Identities[0].Nickname!="山林"{t.Fatal("rejected replay created a second identity")}
	request.ChangeID=identityRequestKey(t)
	if result,err:=l.c.ChangeOwnIdentity(ctx,request);err!=nil || result.State!="COMMITTED"{t.Fatalf("new explicit intent cannot use released nickname: %v",err)}
}

func TestIdentityInvalidNameRejectionBindingAndNoSessionRenewalPostgres(t *testing.T) {
	control:=newGateControl(t)
	l,ctx:=control.lab,context.Background()
	owner:=sessionTestAccount(t,l,"identity_invalid_user")
	hash:=sha256.Sum256(owner.SessionToken[:])
	before:=control.clock.now().Add(6*24*time.Hour)
	mustExec(t,l.cp,`UPDATE c_auth.sessions SET expires_at=$2 WHERE token_digest=$1`,hash[:],before)
	request:=IdentityChangeRequest{Bearer:owner.SessionToken,ChangeID:identityRequestKey(t),Operation:"CREATE",Nickname:"invalid name"}
	result,err:=l.c.ChangeOwnIdentity(ctx,request)
	if !identityRejected(result,err,"IDENTITY_INVALID_NAME") || !result.ExpiresAt.Equal(before){t.Fatalf("invalid name terminal result/expiry: %+v %v",result,err)}
	var expiry time.Time
	if err=l.cp.QueryRow(ctx,`SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`,hash[:]).Scan(&expiry);err!=nil || !expiry.Equal(before){t.Fatalf("rejected mutation renewed session without HTTP expiry: %v",err)}
	for _,name:=range []string{"other invalid","海风"}{changed:=request;changed.Nickname=name;if _,err=l.c.ChangeOwnIdentity(ctx,changed);!errors.Is(err,ErrIdentityChangeConflict){t.Fatalf("different invalid/legal payload adopted rejected key: %v",err)}}
	if result,err=l.c.GetIdentityChangeResult(ctx,owner.SessionToken,request.ChangeID);!identityRejected(result,err,"IDENTITY_INVALID_NAME") || !result.ExpiresAt.Equal(control.clock.now().Add(sessionLifetime)){t.Fatalf("query200 did not safely reconcile and renew: %+v %v",result,err)}
	if count(t,l.cp,`SELECT count(*) FROM public.identity_account_state WHERE account_id=$1`,owner.AccountID)!=0 || count(t,l.cp,`SELECT count(*) FROM public.community_identities WHERE account_id=$1`,owner.AccountID)!=0{t.Fatal("invalid nickname consumed creation count")}
}

func TestIdentityDatabaseFailureDoesNotTerminalizeOrRenewPostgres(t *testing.T) {
	control:=newGateControl(t)
	l,ctx:=control.lab,context.Background()
	owner:=sessionTestAccount(t,l,"identity_database_user")
	hash:=sha256.Sum256(owner.SessionToken[:])
	before:=control.clock.now().Add(6*24*time.Hour)
	mustExec(t,l.cp,`UPDATE c_auth.sessions SET expires_at=$2 WHERE token_digest=$1`,hash[:],before)
	request:=IdentityChangeRequest{Bearer:owner.SessionToken,ChangeID:identityRequestKey(t),Operation:"CREATE",Nickname:"海风"}
	mustExec(t,l.cp,`ALTER TABLE public.community_identities RENAME COLUMN nickname TO unavailable_nickname`)
	if result,err:=l.c.ChangeOwnIdentity(ctx,request);!errors.Is(err,ErrAuthorizationUnavailable) || result.State!=""{t.Fatalf("database failure became terminal business outcome: %+v %v",result,err)}
	mustExec(t,l.cp,`ALTER TABLE public.community_identities RENAME COLUMN unavailable_nickname TO nickname`)
	var expiry time.Time
	if err:=l.cp.QueryRow(ctx,`SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`,hash[:]).Scan(&expiry);err!=nil || !expiry.Equal(before){t.Fatalf("database failure renewed: %v",err)}
	if count(t,l.cp,`SELECT count(*) FROM public.identity_change_receipts WHERE account_id=$1`,owner.AccountID)!=0{t.Fatal("SQL failure persisted rejected receipt")}
	if result,err:=l.c.ChangeOwnIdentity(ctx,request);err!=nil || result.State!="COMMITTED"{t.Fatalf("same intent could not retry transient SQL failure: %v",err)}
}

func TestIdentitySchemaRejectsCounterTombstoneAndReceiptTamperingPostgres(t *testing.T) {
	l,ctx:=newLab(t),context.Background()
	owner:=sessionTestAccount(t,l,"identity_shape_user")
	first:=identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"海风")
	second:=identityChange(t,l.c,owner.SessionToken,"CREATE",uuid.Nil,"山林")
	identityChange(t,l.c,owner.SessionToken,"DELETE",first.IdentityID,"")
	for _,sql:=range []string{
		`DELETE FROM public.community_identities WHERE account_id=$1`,
		`DELETE FROM public.identity_account_state WHERE account_id=$1`,
		`UPDATE public.identity_account_state SET created_count=1 WHERE account_id=$1`,
		`UPDATE public.identity_change_receipts SET operation='DELETE' WHERE account_id=$1`,
		`DELETE FROM public.identity_change_receipts WHERE account_id=$1`,
		`UPDATE public.community_identities SET deleted_at=NULL,nickname='星河',avatar='default-v1' WHERE account_id=$1 AND deleted_at IS NOT NULL`,
		`UPDATE public.community_identities SET nickname=NULL,avatar=NULL,last_renamed_at=NULL,deleted_at=clock_timestamp() WHERE account_id=$1 AND deleted_at IS NULL`,
	} {
		if _,err:=l.cp.Exec(ctx,sql,owner.AccountID);err==nil{t.Fatalf("identity invariant accepted %s",sql)}
	}
	view:=identityDirectory(t,l.c,owner.SessionToken)
	if len(view.Identities)!=1 || view.Identities[0].ID!=second.IdentityID || view.CreatedCount!=2{t.Fatal("failed invariant transaction changed identity state")}
}
