package authprivacy

import (
	"context"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"os"
	"sync"
	"testing"
)

func TestDMFirstContactConcurrencyAndRuntimePostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	a := sessionTestAccount(t, l, "dm_concurrent_a")
	b := sessionTestAccount(t, l, "dm_concurrent_b")
	ia := identityChange(t, l.c, a.SessionToken, "CREATE", uuid.Nil, "甲面具").IdentityID
	ib := identityChange(t, l.c, b.SessionToken, "CREATE", uuid.Nil, "乙面具").IdentityID
	post := commentTextPost(t, l, b.SessionToken, ib)
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	for _, name := range []string{"grant-community.sql", "grant-comments.sql", "grant-direct-messages.sql"} {
		sql, e := os.ReadFile("../../../../infra/postgres/" + name)
		if e != nil {
			t.Fatal(e)
		}
		mustExec(t, l.cp, string(sql))
	}
	cfg, e := pgxpool.ParseConfig(os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
	if e != nil || cfg.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
		t.Fatal("owned runtime DSN required")
	}
	pool, e := pgxpool.NewWithConfig(ctx, cfg)
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	clone := *l.c
	clone.pool = pool
	c, e := clone.WithDirectMessages(ctx)
	if e != nil {
		t.Fatal(e)
	}
	in := DMTextIntent{IdentityID: ia.String(), PeerID: ib.String(), SourcePostID: post, Text: "并发首发", Attempt: 1}
	outcomes := make(chan DMReceipt, 12)
	errs := make(chan error, 12)
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r, e := c.SendDMText(ctx, a.SessionToken, uuid.NewString(), in)
			if e != nil {
				errs <- e
				return
			}
			outcomes <- r.Value.(DMReceipt)
		}()
	}
	wg.Wait()
	close(errs)
	close(outcomes)
	for e := range errs {
		t.Fatal(e)
	}
	accepted := 0
	var conv string
	for r := range outcomes {
		if r.State == "SENT" {
			accepted++
			conv = r.ConversationID
		} else if r.ErrorCode != "WAITING_FOR_REPLY" {
			t.Fatal(r)
		}
	}
	if accepted != 1 || count(t, l.cp, `SELECT count(*) FROM c_dm.messages`) != 1 || count(t, l.cp, `SELECT count(*) FROM c_dm.conversations`) != 1 {
		t.Fatal("first quota/unique pair violated")
	}
	// Exact pending bodies are available only to the recipient, not the sender.
	pending, e := c.PullDM(ctx, a.SessionToken)
	if e != nil || len(pending.Value.(DMPending).Items) != 0 {
		t.Fatal("outgoing content exposed by pull", e)
	}
	reply := DMTextIntent{IdentityID: ib.String(), PeerID: ia.String(), ConversationID: conv, Text: "回复打开联系", Attempt: 1}
	if _, e = c.SendDMText(ctx, b.SessionToken, uuid.NewString(), reply); e != nil {
		t.Fatal(e)
	}
	// Fresh masks can simultaneously contact one another from their real posts.
	ia2 := identityChange(t, l.c, a.SessionToken, "CREATE", uuid.Nil, "甲新面具").IdentityID
	ib2 := identityChange(t, l.c, b.SessionToken, "CREATE", uuid.Nil, "乙新面具").IdentityID
	pa := commentTextPost(t, l, a.SessionToken, ia2)
	pb := commentTextPost(t, l, b.SessionToken, ib2)
	mutual := make(chan DMReceipt, 2)
	for _, v := range []struct {
		bearer [32]byte
		in     DMTextIntent
	}{
		{a.SessionToken, DMTextIntent{IdentityID: ia2.String(), PeerID: ib2.String(), SourcePostID: pb, Text: "同时首发甲", Attempt: 1}},
		{b.SessionToken, DMTextIntent{IdentityID: ib2.String(), PeerID: ia2.String(), SourcePostID: pa, Text: "同时首发乙", Attempt: 1}},
	} {
		wg.Add(1)
		go func(v struct {
			bearer [32]byte
			in     DMTextIntent
		}) {
			defer wg.Done()
			r, err := c.SendDMText(ctx, v.bearer, uuid.NewString(), v.in)
			if err != nil {
				t.Error(err)
				return
			}
			mutual <- r.Value.(DMReceipt)
		}(v)
	}
	wg.Wait()
	close(mutual)
	same := ""
	n := 0
	for r := range mutual {
		n++
		if r.State != "SENT" || (same != "" && same != r.ConversationID) {
			t.Fatal("simultaneous first contact diverged", r)
		}
		same = r.ConversationID
	}
	if n != 2 {
		t.Fatal("mutual first contact incomplete")
	}
	if e = l.c.ApplyAccountMute(ctx, a.AccountID, 1, nil); e != nil {
		t.Fatal(e)
	}
	denied, e := c.SendDMText(ctx, a.SessionToken, uuid.NewString(), in)
	if e != nil || denied.Value.(DMReceipt).ErrorCode != "POSTING_RESTRICTED" {
		t.Fatal("mute bypass", e)
	}
	// Revoked schema invariant fails startup rather than permitting duplicate pairs.
	mustExec(t, l.cp, `ALTER TABLE c_dm.conversations DROP CONSTRAINT conversations_low_identity_high_identity_key`)
	if _, e = clone.WithDirectMessages(ctx); e == nil {
		t.Fatal("missing unique pair admitted")
	}
	// Restricted role cannot restore an ACKed body by changing identity or erase receipts.
	for _, sql := range []string{`DELETE FROM c_dm.commands`, `UPDATE c_dm.messages SET sender=gen_random_uuid()`, `UPDATE c_dm.commands SET fingerprint=decode(repeat('00',32),'hex')`, `TRUNCATE c_dm.messages`} {
		if _, e = pool.Exec(ctx, sql); e == nil {
			t.Fatal("runtime privilege exceeded")
		}
	}
}
