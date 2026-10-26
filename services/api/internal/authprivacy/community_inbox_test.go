package authprivacy

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"os"
	"strings"
	"testing"
)

func TestNotificationInboxPostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "notice_owner")
	sender := sessionTestAccount(t, l, "notice_sender")
	third := sessionTestAccount(t, l, "notice_third")
	first := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "本人甲").IdentityID
	second := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "本人乙").IdentityID
	author := identityChange(t, l.c, sender.SessionToken, "CREATE", uuid.Nil, "发言者").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, first)
	runtime := moderationLifecycleRuntime(t, l)
	grant, e := os.ReadFile("../../../../infra/postgres/grant-comments.sql")
	if e != nil {
		t.Fatal(e)
	}
	mustExec(t, l.cp, string(grant))
	clone := *l.c
	clone.pool = runtime
	l.c = &clone
	if e = l.c.CheckCommentSchema(ctx); e != nil {
		t.Fatal(e)
	}
	for _, sql := range []string{`DELETE FROM c_inbox.records`, `UPDATE c_inbox.records SET version=99`, `DELETE FROM c_inbox.like_events`, `SELECT c_inbox.comment_published()`, `SELECT c_inbox.like_changed()`} {
		_, e = runtime.Exec(ctx, sql)
		var pg *pgconn.PgError
		if !errors.As(e, &pg) || pg.Code != "42501" {
			t.Fatalf("runtime forged notification: %v", e)
		}
	}
	task := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: author.String(), Body: "新回复"}
	key := postTestKey(t)
	commentTextSend(t, l, sender.SessionToken, key, task)
	if count(t, l.cp, `SELECT count(*) FROM c_inbox.records`) != 0 {
		t.Fatal("accepted is not published")
	}
	commentTextSend(t, l, sender.SessionToken, key, task)
	commentTextPublish(t, l)
	q := InboxQuery{IdentityID: first.String(), Category: "all"}
	response, e := l.c.ReadInbox(ctx, owner.SessionToken, q)
	if e != nil {
		t.Fatal(e)
	}
	page := response.Value.(InboxPage)
	if len(page.Items) != 1 || !page.Items[0].IsReply || !page.Items[0].Unread {
		t.Fatal("a published reply is delivered once", page)
	}
	notice := page.Items[0]
	response, e = l.c.ReadInboxCounts(ctx, owner.SessionToken, first.String())
	if e != nil {
		t.Fatal(e)
	}
	counts := response.Value.(InboxCounts)
	if counts.All != 1 || counts.Reply != 1 || counts.IdentityUnread[first.String()] != 1 {
		t.Fatal(counts)
	}
	response, e = l.c.ReadInbox(ctx, owner.SessionToken, InboxQuery{IdentityID: second.String()})
	if e != nil || len(response.Value.(InboxPage).Items) != 0 {
		t.Fatal("cross identity inbox", e)
	}
	_, e = l.c.ReadInbox(ctx, third.SessionToken, q)
	postTestError(t, e, "IDENTITY_UNAVAILABLE", 404)
	if _, e = l.c.MarkInboxRead(ctx, owner.SessionToken, notice.ID, second.String(), notice.Version); e == nil {
		t.Fatal("cross identity read")
	}
	if _, e = l.c.MarkInboxRead(ctx, owner.SessionToken, notice.ID, first.String(), notice.Version); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.MarkInboxRead(ctx, owner.SessionToken, notice.ID, first.String(), notice.Version); e != nil {
		t.Fatal("read replay", e)
	}
	// Likes aggregate by content, never disclose a liker identity, and only the
	// observed revision is acknowledged even when a newer like has arrived.
	interactionTestSet(t, l, sender.SessionToken, post, posts.PostLike, true)
	response, e = l.c.ReadInbox(ctx, owner.SessionToken, InboxQuery{IdentityID: first.String(), Category: "like"})
	if e != nil {
		t.Fatal(e)
	}
	like := response.Value.(InboxPage).Items[0]
	if like.NewLikeCount != 1 || like.Actor != nil {
		t.Fatal(like)
	}
	interactionTestSet(t, l, third.SessionToken, post, posts.PostLike, true)
	if _, e = l.c.MarkInboxRead(ctx, owner.SessionToken, like.ID, first.String(), like.Version); e != nil {
		t.Fatal(e)
	}
	response, e = l.c.ReadInbox(ctx, owner.SessionToken, InboxQuery{IdentityID: first.String(), Category: "like", UnreadOnly: true})
	if e != nil {
		t.Fatal(e)
	}
	newer := response.Value.(InboxPage).Items[0]
	if newer.NewLikeCount != 1 || !newer.Unread {
		t.Fatal("read swallowed newly arriving like", newer)
	}
	interactionTestSet(t, l, third.SessionToken, post, posts.PostLike, false)
	response, e = l.c.ReadInbox(ctx, owner.SessionToken, InboxQuery{IdentityID: first.String(), Category: "like", UnreadOnly: true})
	if e != nil || len(response.Value.(InboxPage).Items) != 0 {
		t.Fatal("cancelled unread like", e)
	}
	interactionTestSet(t, l, sender.SessionToken, post, posts.PostLike, false)
	response, e = l.c.ReadInbox(ctx, owner.SessionToken, InboxQuery{IdentityID: first.String(), Category: "like"})
	if e != nil {
		t.Fatal(e)
	}
	if len(response.Value.(InboxPage).Items) != 1 || response.Value.(InboxPage).Items[0].Unread {
		t.Fatal("read history must survive cancellation")
	}
	raw, _ := json.Marshal(response.Value)
	if strings.Contains(string(raw), sender.AccountID.String()) || strings.Contains(string(raw), third.AccountID.String()) {
		t.Fatal("voter account leak")
	}
	// Legacy system records are account-private and shared across this account's
	// selections, including their read state; interactions remain identity-scoped.
	id := uuid.NewString()
	mustExec(t, l.cp, `INSERT INTO c_moderation.notifications(notification_id,event_id,account_id,identity_id,kind,state,title,body,route_name,resource_id,created_at) VALUES($1,$4,$2,$3,'REPORT_PROGRESS','PENDING','已提交','等待处理','REPORT',$1,clock_timestamp())`, id, owner.AccountID, first, "test-notice:"+id)
	for _, identity := range []string{first.String(), second.String()} {
		r, e := l.c.ReadInbox(ctx, owner.SessionToken, InboxQuery{IdentityID: identity, Category: "system"})
		if e != nil || len(r.Value.(InboxPage).Items) != 1 {
			t.Fatal("system not shared", e)
		}
	}
	if _, e = l.c.MarkInboxRead(ctx, owner.SessionToken, "s_"+id, second.String(), 1); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.MarkInboxRead(ctx, third.SessionToken, "s_"+id, "", 1); e == nil {
		t.Fatal("foreign system read")
	}
	response, e = l.c.ReadInboxCounts(ctx, owner.SessionToken, first.String())
	if e != nil || response.Value.(InboxCounts).System != 0 {
		t.Fatal("system read not shared", e)
	}
	// Removed content is never quoted by stale notifications.
	commentTextSend(t, l, sender.SessionToken, postTestKey(t), comments.Intent{Operation: comments.DeleteComment, CommentID: *notice.CommentID})
	response, e = l.c.ReadInbox(ctx, owner.SessionToken, q)
	if e != nil {
		t.Fatal(e)
	}
	for _, item := range response.Value.(InboxPage).Items {
		if item.ID == notice.ID && (item.TargetAvailable || strings.Contains(item.Body, "新回复")) {
			t.Fatal("deleted text leaked")
		}
	}
	if e = l.gate.Freeze(ctx, "notification final gate fixture"); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.ReadInbox(ctx, owner.SessionToken, q); !errors.Is(e, ErrAuthorizationUnavailable) {
		t.Fatal("frozen list", e)
	}
	if _, e = l.c.ReadInboxCounts(ctx, owner.SessionToken, first.String()); !errors.Is(e, ErrAuthorizationUnavailable) {
		t.Fatal("frozen counts", e)
	}
	if _, e = l.c.MarkInboxRead(ctx, owner.SessionToken, notice.ID, first.String(), notice.Version); !errors.Is(e, ErrAuthorizationUnavailable) {
		t.Fatal("frozen read", e)
	}
}

func TestNotificationInboxIdentityPaginationPostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "notice_two_owner")
	sender := sessionTestAccount(t, l, "notice_two_sender")
	first := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "面具甲").IdentityID
	second := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "面具乙").IdentityID
	author := identityChange(t, l.c, sender.SessionToken, "CREATE", uuid.Nil, "参与者").IdentityID
	for _, id := range []uuid.UUID{first, second} {
		// One account has one fixed speaking identity per post; use distinct posts.
		post := commentTextPost(t, l, owner.SessionToken, id)
		for i := 0; i < 2; i++ {
			receipt := commentTextSend(t, l, sender.SessionToken, postTestKey(t), comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: author.String(), Body: "来看看"})
			if receipt.State != "ACCEPTED" {
				t.Fatal(receipt)
			}
			commentTextPublish(t, l)
		}
		q := InboxQuery{IdentityID: id.String(), Category: "reply", Limit: 1}
		r, e := l.c.ReadInbox(ctx, owner.SessionToken, q)
		if e != nil {
			t.Fatal(e)
		}
		page := r.Value.(InboxPage)
		if len(page.Items) != 1 || page.NextCursor == nil {
			t.Fatal("recipient identity lost", page)
		}
		q.Cursor = *page.NextCursor
		r, e = l.c.ReadInbox(ctx, owner.SessionToken, q)
		if e != nil {
			t.Fatal(e)
		}
		next := r.Value.(InboxPage)
		if len(next.Items) != 1 || next.Items[0].ID == page.Items[0].ID || next.NextCursor != nil {
			t.Fatal("keyset pagination", next)
		}
		q.Category = "like"
		if _, e = l.c.ReadInbox(ctx, owner.SessionToken, q); e == nil {
			t.Fatal("cross-category cursor")
		}
		q.Category = "reply"
		q.IdentityID = author.String()
		if _, e = l.c.ReadInbox(ctx, sender.SessionToken, q); e == nil {
			t.Fatal("cross-identity cursor")
		}
	}
	identityChange(t, l.c, owner.SessionToken, "DELETE", second, "")
	if _, e := l.c.ReadInbox(ctx, owner.SessionToken, InboxQuery{IdentityID: second.String()}); e == nil {
		t.Fatal("deleted recipient identity")
	}
	r, e := l.c.ReadInboxCounts(ctx, owner.SessionToken, first.String())
	if e != nil || len(r.Value.(InboxCounts).IdentityUnread) != 1 {
		t.Fatal("deleted identity unread", e)
	}
}
