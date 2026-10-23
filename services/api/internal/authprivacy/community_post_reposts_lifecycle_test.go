package authprivacy

import (
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"testing"
)

func TestFeedRepostsRollbackSessionGateAndClosurePostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "repost_closure")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "身份").IdentityID
	post := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, identity)).PostID
	postTestPublish(t, l)
	initial, e := l.c.ReadPostReposts(ctx, owner.SessionToken, post)
	if e != nil {
		t.Fatal(e)
	}
	mustExec(t, l.cp, `CREATE FUNCTION c_posts.reject_repost() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic'; END $$; CREATE TRIGGER reject_repost AFTER INSERT ON c_posts.post_reposts FOR EACH ROW EXECUTE FUNCTION c_posts.reject_repost()`)
	if _, e = l.c.SetPostRepost(ctx, owner.SessionToken, post, identity.String(), true, initial.InteractionVersion); e == nil {
		t.Fatal("failed save accepted")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_reposts`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_repost_versions`) != 0 {
		t.Fatal("partial transaction")
	}
	mustExec(t, l.cp, `DROP TRIGGER reject_repost ON c_posts.post_reposts`)
	if _, e = l.c.SetPostRepost(ctx, owner.SessionToken, post, identity.String(), true, initial.InteractionVersion); e != nil {
		t.Fatal("same condition retry", e)
	}
	// Deletion retains only an unavailable private reference.
	postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: post})
	page, e := l.c.ListPostReposts(ctx, owner.SessionToken, PostQuery{Limit: 20})
	if e != nil || page.Value.(posts.RepostPage).Items[0].Post != nil {
		t.Fatal("deleted content leak", e)
	}
	state, e := l.c.ReadPostReposts(ctx, owner.SessionToken, post)
	if e != nil {
		t.Fatal(e)
	}
	barrier := &identitySnapshotBarrier{AuthorizationGate: l.c.gate, captured: make(chan struct{}), release: make(chan struct{})}
	stale := *l.c
	stale.gate = barrier
	done := make(chan error, 1)
	go func() {
		_, e := stale.SetPostRepost(ctx, owner.SessionToken, post, identity.String(), false, state.InteractionVersion)
		done <- e
	}()
	<-barrier.captured
	renewed, e := l.c.CreateSession(ctx, sessionTestRequest(t, "repost_closure"), sessionTestPasswordWorker(t, 1))
	if e != nil {
		t.Fatal(e)
	}
	close(barrier.release)
	if e = <-done; !errors.Is(e, ErrSessionReplaced) {
		t.Fatal("stale session", e)
	}
	request, _ := closureTestRequest(t, renewed.SessionToken)
	closure, e := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if e != nil {
		t.Fatal(e)
	}
	advanceClosureClock(t, control, closure.DueAt)
	if n, e := l.c.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
		t.Fatal("closure", n, e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_reposts`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_repost_versions`) != 0 {
		t.Fatal("private closure data retained")
	}
	if _, e = l.c.ListPostReposts(ctx, renewed.SessionToken, PostQuery{Limit: 20}); e == nil {
		t.Fatal("closed archive readable")
	}
	if e = l.gate.Freeze(ctx, "repost fixture"); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.ReadPostReposts(ctx, owner.SessionToken, post); !errors.Is(e, ErrAuthorizationUnavailable) {
		t.Fatal("frozen read", e)
	}
}
