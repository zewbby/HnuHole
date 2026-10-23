package authprivacy

import (
	"context"
	"encoding/base64"
	"os"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestDMChatMediaLifecyclePostgres(t *testing.T) {
	l := commentTextLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	a := sessionTestAccount(t, l, "dm_chat_a")
	b := sessionTestAccount(t, l, "dm_chat_b")
	stranger := sessionTestAccount(t, l, "dm_chat_stranger")
	ia := identityChange(t, l.c, a.SessionToken, "CREATE", uuid.Nil, "甲同学").IdentityID.String()
	ib := identityChange(t, l.c, b.SessionToken, "CREATE", uuid.Nil, "乙同学").IdentityID.String()
	post := commentTextPost(t, l, b.SessionToken, uuid.MustParse(ib))
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
	text := func(token [32]byte, in DMTextIntent) DMReceipt {
		t.Helper()
		r, e := c.SendDMText(ctx, token, uuid.NewString(), in)
		if e != nil {
			t.Fatal(e)
		}
		return r.Value.(DMReceipt)
	}
	first := text(a.SessionToken, DMTextIntent{IdentityID: ia, PeerID: ib, SourcePostID: post, Text: "first", Attempt: 1})
	conv := first.ConversationID
	selection, data := imageFixture(t, "png")
	imageIntent := DMImageIntent{IdentityID: ia, PeerID: ib, ConversationID: conv, GroupID: uuid.NewString(), GroupSize: 9, Selection: selection, Data: base64.StdEncoding.EncodeToString(data), Attempt: 1}
	sendImage := func(id string, in DMImageIntent) DMReceipt {
		t.Helper()
		r, e := c.SendDMImage(ctx, a.SessionToken, id, in)
		if e != nil {
			t.Fatal(e)
		}
		return r.Value.(DMReceipt)
	}
	if r := sendImage(uuid.NewString(), imageIntent); r.ErrorCode != "WAITING_FOR_REPLY" {
		t.Fatal("image before reply", r)
	}
	op := func(token [32]byte, id string, in DMChatOperation) DMChatResult {
		t.Helper()
		r, e := c.ExecuteDMChatOperation(ctx, token, id, in)
		if e != nil {
			t.Fatal(e)
		}
		return r.Value.(DMChatResult)
	}
	// Retracting/deleting first text never restores the first-contact quota.
	retractFirst := DMChatOperation{IdentityID: ia, ConversationID: conv, Operation: "RETRACT", MessageID: first.MessageID}
	if r := op(a.SessionToken, uuid.NewString(), retractFirst); r.State != "APPLIED" {
		t.Fatal(r)
	}
	if r := text(a.SessionToken, DMTextIntent{IdentityID: ia, PeerID: ib, ConversationID: conv, Text: "again", Attempt: 1}); r.ErrorCode != "WAITING_FOR_REPLY" {
		t.Fatal("retraction restored quota", r)
	}
	text(b.SessionToken, DMTextIntent{IdentityID: ib, PeerID: ia, ConversationID: conv, Text: "reply", Attempt: 1})
	ids := make([]string, 9)
	intents := make([]DMImageIntent, 9)
	messages := make([]string, 9)
	for i := 0; i < 9; i++ {
		in := imageIntent
		in.Position = i
		in.MediaID = uuid.NewString()
		ids[i] = uuid.NewString()
		intents[i] = in
		if i >= 7 {
			broken := append([]byte(nil), data...)
			broken[0] ^= 255
			in.Data = base64.StdEncoding.EncodeToString(broken)
		}
		r := sendImage(ids[i], in)
		if i < 7 {
			if r.State != "SENT" {
				t.Fatal(r)
			}
			messages[i] = r.MessageID
		} else if r.ErrorCode != "INVALID_IMAGE" {
			t.Fatal(r)
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_dm.media`) != 7 {
		t.Fatal("expected seven durable successes")
	}
	for i := 7; i < 9; i++ {
		intents[i].Attempt = 2
		r := sendImage(ids[i], intents[i])
		if r.State != "SENT" {
			t.Fatal(r)
		}
		messages[i] = r.MessageID
	}
	if count(t, l.cp, `SELECT count(*) FROM c_dm.media`) != 9 {
		t.Fatal("per-item retry duplicated group")
	}
	for i := 0; i < 9; i++ {
		if r := sendImage(ids[i], intents[i]); r.MessageID != messages[i] {
			t.Fatal("lost response replay changed identity")
		}
	}
	if _, e = c.ReadDMPrivateMedia(ctx, a.SessionToken, messages[0]); e == nil {
		t.Fatal("sender may not recover cloud media")
	}
	if _, e = c.ReadDMPrivateMedia(ctx, stranger.SessionToken, messages[0]); e == nil {
		t.Fatal("stranger read media")
	}
	r, e := c.ReadDMPrivateMedia(ctx, b.SessionToken, messages[0])
	if e != nil || r.Value.(DMPrivateMedia).Data != imageIntent.Data {
		t.Fatal("recipient byte integrity", e)
	}
	if _, e = c.AcknowledgeDM(ctx, b.SessionToken, []string{messages[0]}, false); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_dm.media WHERE bytes IS NOT NULL`) != 8 {
		t.Fatal("ACK did not clear just one image")
	}
	if _, e = c.ReadDMPrivateMedia(ctx, b.SessionToken, messages[0]); e == nil {
		t.Fatal("ACKed bytes downloadable")
	}
	directory := func(token [32]byte, identity string) DMChatConversation {
		t.Helper()
		r, e := c.ReadDMChatDirectory(ctx, token, identity, "")
		if e != nil {
			t.Fatal(e)
		}
		return r.Value.(DMChatDirectory).Items[0]
	}
	own := directory(b.SessionToken, ib)
	if own.Unread != 9 || own.UnavailableUnread != 1 {
		t.Fatal("ACK changed unread or missing history", own)
	}
	note := DMChatOperation{IdentityID: ib, ConversationID: conv, Operation: "SETTINGS", ExpectedVersion: own.SettingsVersion, Pinned: true, Muted: true, Note: "仅本人备注"}
	noteID := uuid.NewString()
	nr := op(b.SessionToken, noteID, note)
	if nr.State != "APPLIED" {
		t.Fatal(nr)
	}
	if r := op(b.SessionToken, noteID, note); r != nr {
		t.Fatal("unstable operation receipt")
	}
	if r := op(b.SessionToken, uuid.NewString(), note); r.ErrorCode != "VERSION_CONFLICT" {
		t.Fatal("stale setting overwrote new state")
	}
	if directory(a.SessionToken, ia).Note != "" {
		t.Fatal("private note exposed")
	}
	hidden := op(b.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: ib, ConversationID: conv, Operation: "HIDE", ExpectedVersion: nr.SettingsVersion})
	if hidden.State != "APPLIED" || !directory(b.SessionToken, ib).Hidden {
		t.Fatal("hide")
	}
	newest := text(a.SessionToken, DMTextIntent{IdentityID: ia, PeerID: ib, ConversationID: conv, Text: "new unhides", Attempt: 1})
	if d := directory(b.SessionToken, ib); d.Hidden || d.Unread != 10 {
		t.Fatal("new did not restore full unread", d)
	}
	// ACK and sender retraction contend on different caller accounts but the same
	// conversation lock. Exactly one tombstone per side survives both orders.
	var wg sync.WaitGroup
	errs := make(chan error, 2)
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, e := c.AcknowledgeDM(ctx, b.SessionToken, []string{messages[1]}, false)
		errs <- e
	}()
	go func() {
		defer wg.Done()
		_, e := c.ExecuteDMChatOperation(ctx, a.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: ia, ConversationID: conv, Operation: "RETRACT", MessageID: messages[1]})
		errs <- e
	}()
	wg.Wait()
	close(errs)
	for e := range errs {
		if e != nil {
			t.Fatal("ACK/retraction race", e)
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_dm.controls`) != 4 {
		t.Fatal("missing or duplicate controls")
	}
	controls, e := c.PullDMControls(ctx, b.SessionToken, 0)
	if e != nil || len(controls.Value.(DMControls).Items) != 2 {
		t.Fatal("offline controls", e)
	}
	cursor := controls.Value.(DMControls).Next
	controls, e = c.PullDMControls(ctx, b.SessionToken, cursor)
	if e != nil || len(controls.Value.(DMControls).Items) != 0 {
		t.Fatal("control cursor", e)
	}
	// Reading after another device's processing can replay minimal tombstones.
	controls, e = c.PullDMControls(ctx, b.SessionToken, 0)
	if e != nil || len(controls.Value.(DMControls).Items) != 2 {
		t.Fatal("new device lost controls", e)
	}
	// Delete the displayed boundary; a newer incoming message must remain even
	// when it commits before the deletion transaction obtains its lock.
	before := newest.Sequence
	later := text(a.SessionToken, DMTextIntent{IdentityID: ia, PeerID: ib, ConversationID: conv, Text: "survives deletion", Attempt: 1})
	dr := op(b.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: ib, ConversationID: conv, Operation: "DELETE", ThroughSequence: before})
	after := directory(b.SessionToken, ib)
	if dr.DeletedThrough != before || after.Deleted || after.Unread != 1 || after.Note != note.Note || after.Version <= own.Version {
		t.Fatal("delete boundary/note/revision", after)
	}
	pending, e := c.PullDMChat(ctx, b.SessionToken)
	if e != nil {
		t.Fatal(e)
	}
	p := pending.Value.(DMChatPending).Items
	if len(p) != 1 || p[0].MessageID != later.MessageID {
		t.Fatal("deleted payload resurrected", p)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_dm.media WHERE bytes IS NOT NULL`) != 0 {
		t.Fatal("delete retained recipient bytes")
	}
	// Delete and retract operate on metadata after ACK; time limit is authoritative.
	mustExec(t, l.cp, `UPDATE c_dm.messages SET accepted_at=accepted_at-interval '3 minutes' WHERE message_id='`+later.MessageID+`'`)
	expired := op(a.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: ia, ConversationID: conv, Operation: "RETRACT", MessageID: later.MessageID})
	if expired.ErrorCode != "RETRACT_EXPIRED" {
		t.Fatal("retraction deadline", expired)
	}
	if _, e = c.ExecuteDMChatOperation(ctx, stranger.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: ib, ConversationID: conv, Operation: "DELETE", ThroughSequence: later.Sequence}); e == nil {
		t.Fatal("stranger deletion")
	}
	// Restricted runtime cannot replace media or edit permanent operation receipts.
	for _, sql := range []string{`UPDATE c_dm.media SET selection='{}'`, `DELETE FROM c_dm.operations`, `UPDATE c_dm.controls SET message_sequence=1`, `DELETE FROM c_dm.settings`} {
		if _, e = pool.Exec(ctx, sql); e == nil {
			t.Fatal("excess runtime authority", sql)
		}
	}
	// Posting restrictions apply to each retry; no old failed image bypass.
	if e = l.c.ApplyAccountMute(ctx, a.AccountID, 1, nil); e != nil {
		t.Fatal(e)
	}
	in := imageIntent
	in.GroupID = uuid.NewString()
	in.MediaID = uuid.NewString()
	if r := sendImage(uuid.NewString(), in); r.ErrorCode != "POSTING_RESTRICTED" {
		t.Fatal(r)
	}
}
