package authprivacy

import (
    "context"
    "crypto/sha256"
    "errors"
    "sync"
    "testing"
    "time"

    "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/channels"
    "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func TestDirectoryRenewalAndInvalidCatalogRollbackPostgres(t *testing.T) {
    control := newGateControl(t)
    l, ctx := control.lab, context.Background()
    session := sessionTestAccount(t, l, "catalog_renewal_user")
    hash := sha256.Sum256(session.SessionToken[:])
    first, err := l.c.ListAuthorizedChannels(ctx, session.SessionToken)
    if err != nil || len(first.Channels) != 7 || !first.ExpiresAt.Equal(session.ExpiresAt) {
        t.Fatalf("complete catalog changed a >7-day session: %v", err)
    }
    before := control.clock.now().Add(6*24*time.Hour)
    mustExec(t, l.cp, `UPDATE c_auth.sessions SET expires_at=$2 WHERE token_digest=$1`, hash[:], before)
    mustExec(t, l.cp, `UPDATE public.channels SET name='broken' WHERE code='vent'`)
    if result, err := l.c.ListAuthorizedChannels(ctx, session.SessionToken); !errors.Is(err, ErrChannelDirectoryUnavailable) || len(result.Channels) != 0 {
        t.Fatalf("invalid catalog returned data: %v", err)
    }
    var expiry time.Time
    if err := l.cp.QueryRow(ctx, `SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`, hash[:]).Scan(&expiry); err != nil || !expiry.Equal(before) {
        t.Fatalf("failed catalog renewed session: %v", err)
    }
    mustExec(t, l.cp, `UPDATE public.channels SET name='吐槽' WHERE code='vent'`)
    var wg sync.WaitGroup
    errorsOut := make(chan error, 4)
    for i:=0; i<4; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            result, err := l.c.ListAuthorizedChannels(ctx, session.SessionToken)
            if err == nil && (!result.ExpiresAt.Equal(control.clock.now().Add(sessionLifetime)) || len(result.Channels)!=7) {
                err = errors.New("concurrent renewal accumulated lifetime or returned partial catalog")
            }
            errorsOut <- err
        }()
    }
    wg.Wait()
    close(errorsOut)
    for err := range errorsOut { if err != nil { t.Fatal(err) } }
    if err := l.gate.Freeze(ctx, "catalog frozen capability test"); err != nil { t.Fatal(err) }
    if result, err := l.c.ListAuthorizedChannels(ctx, [32]byte{99}); !errors.Is(err, ErrAuthorizationUnavailable) || len(result.Channels)!=0 {
        t.Fatalf("frozen Gate distinguished a valid random capability: %v",err)
    }
}

func TestDirectoryDatabaseFailureDoesNotRenewPostgres(t *testing.T) {
    control := newGateControl(t)
    l, ctx := control.lab, context.Background()
    session := sessionTestAccount(t, l, "catalog_database_user")
    hash := sha256.Sum256(session.SessionToken[:])
    before := control.clock.now().Add(6*24*time.Hour)
    mustExec(t, l.cp, `UPDATE c_auth.sessions SET expires_at=$2 WHERE token_digest=$1`, hash[:], before)
    mustExec(t, l.cp, `ALTER TABLE public.channels RENAME COLUMN name TO unavailable_name`)
    defer mustExec(t, l.cp, `ALTER TABLE public.channels RENAME COLUMN unavailable_name TO name`)
    result, err := l.c.ListAuthorizedChannels(ctx, session.SessionToken)
    if !errors.Is(err, ErrAuthorizationUnavailable) || errors.Is(err, ErrChannelDirectoryUnavailable) || len(result.Channels) != 0 {
        t.Fatalf("database failure returned the wrong boundary: %v", err)
    }
    var expiry time.Time
    if err := l.cp.QueryRow(ctx, `SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`, hash[:]).Scan(&expiry); err != nil || !expiry.Equal(before) {
        t.Fatalf("database failure renewed session: %v", err)
    }
}

func TestDirectoryAccountLockWaitUsesFinalGateAndExpiryPostgres(t *testing.T) {
    for _, scenario := range []string{"freeze", "expiry", "revocation", "pending-close", "ban"} {
        t.Run(scenario, func(t *testing.T) {
            control := newGateControl(t)
            l, ctx := control.lab, context.Background()
            session := sessionTestAccount(t, l, "catalog_wait_user")
            hash := sha256.Sum256(session.SessionToken[:])
            before := control.clock.now().Add(time.Minute)
            mustExec(t, l.cp, `UPDATE c_auth.sessions SET expires_at=$2 WHERE token_digest=$1`,hash[:],before)
            hold, err := l.cp.Begin(ctx)
            if err != nil { t.Fatal(err) }
            defer hold.Rollback(ctx)
            var state string
            if err := hold.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`,session.AccountID).Scan(&state); err != nil { t.Fatal(err) }
            answer := make(chan error,1)
            go func(){ result, err := l.c.ListAuthorizedChannels(ctx, session.SessionToken); if err==nil || len(result.Channels)>0 { answer<-errors.New("blocked unauthorized catalog returned data"); return }; answer<-err }()
            waitLock(t,l.cp,"transactionid",1)
            expected := ErrSessionInvalid
            switch scenario {
            case "freeze":
                expected = ErrAuthorizationUnavailable
                if err := l.gate.Freeze(ctx,"directory waiting across freeze"); err != nil { t.Fatal(err) }
            case "expiry":
                control.clock.set(before.Add(time.Second))
            case "revocation":
                if _,err:=hold.Exec(ctx,`UPDATE c_auth.sessions SET revoked_at=$2,revocation_reason='LOGOUT' WHERE token_digest=$1`,hash[:],control.clock.now()); err!=nil {t.Fatal(err)}
            case "pending-close":
                if _,err:=hold.Exec(ctx,`UPDATE c_auth.accounts SET state='PENDING_CLOSE' WHERE account_id=$1`,session.AccountID); err!=nil {t.Fatal(err)}
            case "ban":
                if _,err:=hold.Exec(ctx,`UPDATE c_auth.account_restrictions SET ban_state='BANNED',ban_ends_at=NULL,version=version+1 WHERE account_id=$1`,session.AccountID); err!=nil {t.Fatal(err)}
            }
            if err:=hold.Commit(ctx); err!=nil {t.Fatal(err)}
            if err:=<-answer; !errors.Is(err,expected) {t.Fatalf("%s final authorization: %v",scenario,err)}
            var expiry time.Time
            if err:=l.cp.QueryRow(ctx,`SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`,hash[:]).Scan(&expiry); err!=nil || !expiry.Equal(before) {t.Fatalf("rejected directory renewed: %v",err)}
        })
    }
}

func TestDirectoryCommitPrecedesWaitingRevocationPostgres(t *testing.T) {
    l := newLab(t)
    ctx,cancel:=context.WithTimeout(context.Background(),10*time.Second)
    defer cancel()
    session := sessionTestAccount(t,l,"catalog_commit_user")
    read, release := make(chan struct{}), make(chan struct{})
    var once sync.Once
    unblock:=func(){once.Do(func(){close(release)})}
    defer unblock()
    directory := make(chan error,1)
    go func(){
        _,err:=l.c.withAuthorizedSession(ctx,session.SessionToken,false,func(query channels.Queryer)error{
            items,err:=channels.NewService(channels.NewPostgresRepository(query)).List(ctx)
            if err!=nil || len(items)!=7 {return ErrChannelDirectoryUnavailable}
            close(read)
            <-release
            return nil
        })
        directory<-err
    }()
    select {case <-read:case err:=<-directory:t.Fatalf("catalog failed before serialization barrier: %v",err);case <-ctx.Done():t.Fatal("catalog did not reach serialization barrier")}
    revoked:=make(chan error,1)
    go func(){revoked<-l.c.RevokeSession(ctx,session.RevokeSecret)}()
    waitLock(t,l.cp,"transactionid",1)
    unblock()
    if err:=<-directory; err!=nil {t.Fatalf("directory lost already-serialized authorization: %v",err)}
    if err:=<-revoked; err!=nil {t.Fatal(err)}
    if _,err:=l.c.ListAuthorizedChannels(ctx,session.SessionToken); !errors.Is(err,ErrSessionInvalid) {t.Fatalf("revoked session read directory again: %v",err)}
}

func TestDirectoryRejectsLegacyTokenForSameAccountPostgres(t *testing.T) {
    l,ctx:=newLab(t),context.Background()
    session:=sessionTestAccount(t,l,"catalog_legacy_user")
    legacy,err:=random32();if err!=nil{t.Fatal(err)}
    encoded:=protocol.EncodeCanonicalBase64url(legacy[:])
    legacyHash:=sha256.Sum256([]byte(encoded))
    mustExec(t,l.cp,`INSERT INTO public.sessions(token_hash,account_id,expires_at)
        VALUES($1,$2,clock_timestamp()+interval '30 days')`,legacyHash[:],session.AccountID)
    if result,err:=l.c.ListAuthorizedChannels(ctx,legacy);!errors.Is(err,ErrSessionInvalid) || len(result.Channels)!=0 {
        t.Fatalf("valid legacy string-digest token granted new business access: %v",err)
    }
    replacement,err:=l.c.CreateSession(ctx,sessionTestRequest(t,"catalog_legacy_user"),sessionTestPasswordWorker(t,1))
    if err!=nil{t.Fatal(err)}
    if result,err:=l.c.ListAuthorizedChannels(ctx,session.SessionToken);!errors.Is(err,ErrSessionReplaced) || len(result.Channels)!=0 {
        t.Fatalf("replaced session retained catalog access: %v",err)
    }
    if _,err:=l.c.ListAuthorizedChannels(ctx,replacement.SessionToken);err!=nil {t.Fatal(err)}
}
