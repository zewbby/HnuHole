package authprivacy

import (
	"context"
	"encoding/base64"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestDMChatIndependentPendingLimitsPostgres(t *testing.T) {
	l := commentTextLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	a := sessionTestAccount(t, l, "dm_quota_a")
	b := sessionTestAccount(t, l, "dm_quota_b")
	other := sessionTestAccount(t, l, "dm_quota_other")
	ia := identityChange(t, l.c, a.SessionToken, "CREATE", uuid.Nil, "额度甲").IdentityID.String()
	ib := identityChange(t, l.c, b.SessionToken, "CREATE", uuid.Nil, "额度乙").IdentityID.String()
	io := identityChange(t, l.c, other.SessionToken, "CREATE", uuid.Nil, "额度丙").IdentityID.String()
	postB := commentTextPost(t, l, b.SessionToken, uuid.MustParse(ib))
	postOther := commentTextPost(t, l, other.SessionToken, uuid.MustParse(io))
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	for _, name := range []string{"grant-community.sql", "grant-comments.sql", "grant-direct-messages.sql"} {
		raw, e := os.ReadFile("../../../../infra/postgres/" + name)
		if e != nil {
			t.Fatal(e)
		}
		mustExec(t, l.cp, string(raw))
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
	openConversation := func(peer string, token [32]byte, post string) string {
		t.Helper()
		first, e := c.SendDMText(ctx, a.SessionToken, uuid.NewString(), DMTextIntent{IdentityID: ia, PeerID: peer, SourcePostID: post, Text: "open contact", Attempt: 1})
		if e != nil {
			t.Fatal(e)
		}
		receipt := first.Value.(DMReceipt)
		if receipt.State != "SENT" {
			t.Fatal(receipt)
		}
		reply, e := c.SendDMText(ctx, token, uuid.NewString(), DMTextIntent{IdentityID: peer, PeerID: ia, ConversationID: receipt.ConversationID, Text: "open reply", Attempt: 1})
		if e != nil {
			t.Fatal(e)
		}
		replyReceipt := reply.Value.(DMReceipt)
		if replyReceipt.State != "SENT" {
			t.Fatal(replyReceipt)
		}
		if _, e = c.AcknowledgeDM(ctx, token, []string{receipt.MessageID}, false); e != nil {
			t.Fatal(e)
		}
		if _, e = c.AcknowledgeDM(ctx, a.SessionToken, []string{replyReceipt.MessageID}, false); e != nil {
			t.Fatal(e)
		}
		return receipt.ConversationID
	}
	current := openConversation(ib, b.SessionToken, postB)
	elsewhere := openConversation(io, other.SessionToken, postOther)
	// Bulk insertion is fixture setup only. Keep the real 4096 limit, actual SQL
	// rows, real sequence constraints and pending-body checks, without 4096 HTTPs.
	seed := func(conv, sender, recipient string, n int) {
		t.Helper()
		tx, e := l.cp.Begin(ctx)
		if e != nil {
			t.Fatal(e)
		}
		defer tx.Rollback(ctx)
		var last int64
		if e = tx.QueryRow(ctx, `UPDATE c_dm.conversations SET sequence=sequence+$2 WHERE conversation_id=$1 RETURNING sequence`, conv, n).Scan(&last); e != nil {
			t.Fatal(e)
		}
		if _, e = tx.Exec(ctx, `INSERT INTO c_dm.messages(message_id,conversation_id,sequence,sender,recipient,body,accepted_at) SELECT gen_random_uuid(),$1,s,$2,$3,'quota fixture',now() FROM generate_series($4::bigint,$5::bigint) s`, conv, sender, recipient, last-int64(n)+1, last); e != nil {
			t.Fatal(e)
		}
		if e = tx.Commit(ctx); e != nil {
			t.Fatal(e)
		}
	}
	assertCounts := func(wantSender, wantConversation int) {
		t.Helper()
		var sender, conversation int
		if e = l.cp.QueryRow(ctx, `SELECT count(*) FILTER(WHERE i.account_id=$1),count(*) FILTER(WHERE m.conversation_id=$2) FROM c_dm.messages m JOIN public.community_identities i ON i.identity_id=m.sender WHERE NOT m.acknowledged`, a.AccountID, current).Scan(&sender, &conversation); e != nil {
			t.Fatal(e)
		}
		if sender != wantSender || conversation != wantConversation {
			t.Fatalf("pending sender=%d conversation=%d, want %d/%d", sender, conversation, wantSender, wantConversation)
		}
	}
	selection, data := imageFixture(t, "png")
	send := func() DMReceipt {
		t.Helper()
		item := selection
		item.MediaID = uuid.NewString()
		result, e := c.SendDMImage(ctx, a.SessionToken, uuid.NewString(), DMImageIntent{IdentityID: ia, PeerID: ib, ConversationID: current, GroupID: uuid.NewString(), GroupSize: 1, Selection: item, Data: base64.StdEncoding.EncodeToString(data), Attempt: 1})
		if e != nil {
			t.Fatal(e)
		}
		return result.Value.(DMReceipt)
	}
	seed(elsewhere, ia, io, 3000)
	seed(current, ib, ia, 1096)
	assertCounts(3000, 1096)
	// Their disjoint union is 4096, but neither individual budget is full.
	if r := send(); r.State != "SENT" {
		t.Fatalf("independent budgets incorrectly combined: %+v", r)
	}
	assertCounts(3001, 1097)
	seed(elsewhere, ia, io, 1094)
	assertCounts(4095, 1097)
	if r := send(); r.State != "SENT" {
		t.Fatalf("last sender slot rejected: %+v", r)
	}
	assertCounts(4096, 1098)
	if r := send(); r.State != "FAILED" || r.ErrorCode != "PENDING_LIMIT" {
		t.Fatalf("full sender budget accepted: %+v", r)
	}
	assertCounts(4096, 1098)
	// Release only the sender's other-conversation rows, then fill this
	// conversation with incoming messages so the conversation budget alone binds.
	if _, e = l.cp.Exec(ctx, `UPDATE c_dm.messages SET acknowledged=true,body=NULL WHERE conversation_id=$1 AND NOT acknowledged`, elsewhere); e != nil {
		t.Fatal(e)
	}
	seed(current, ib, ia, 2998)
	assertCounts(2, 4096)
	if r := send(); r.State != "FAILED" || r.ErrorCode != "PENDING_LIMIT" {
		t.Fatalf("full conversation budget accepted: %+v", r)
	}
	assertCounts(2, 4096)
	if count(t, l.cp, `SELECT count(*) FROM c_dm.media`) != 2 {
		t.Fatal("quota rejection created media or erased accepted images")
	}
}
