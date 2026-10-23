package authprivacy

import (
	"context"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"strings"
	"testing"
)

func TestFeedRepostsLifecyclePostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "repost_owner")
	reader := sessionTestAccount(t, l, "repost_reader")
	other := sessionTestAccount(t, l, "repost_other")
	author := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "作者").IdentityID
	identity := identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "转帖身份").IdentityID
	secondIdentity := identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "另一个身份").IdentityID
	foreign := identityChange(t, l.c, other.SessionToken, "CREATE", uuid.Nil, "其他账号").IdentityID
	p := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, author))
	p2 := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, author))
	postTestPublish(t, l)
	read := func(token [32]byte, id string) PostResponse {
		t.Helper()
		r, e := l.c.ReadPostReposts(ctx, token, id)
		if e != nil {
			t.Fatal(e)
		}
		return r
	}
	set := func(id string, identity uuid.UUID, on bool, version string) PostResponse {
		t.Helper()
		r, e := l.c.SetPostRepost(ctx, reader.SessionToken, id, identity.String(), on, version)
		if e != nil {
			t.Fatal(e)
		}
		return r
	}
	list := func(token [32]byte, cursor string, limit int) posts.RepostPage {
		t.Helper()
		r, e := l.c.ListPostReposts(ctx, token, PostQuery{Cursor: cursor, Limit: limit})
		if e != nil {
			t.Fatal(e)
		}
		return r.Value.(posts.RepostPage)
	}
	initial := read(reader.SessionToken, p.PostID)
	if _, e := l.c.SetPostRepost(ctx, reader.SessionToken, p.PostID, foreign.String(), true, initial.InteractionVersion); e == nil {
		t.Fatal("foreign identity")
	}
	first := set(p.PostID, identity, true, initial.InteractionVersion)
	if _, e := l.c.SetPostRepost(ctx, reader.SessionToken, p.PostID, identity.String(), true, initial.InteractionVersion); e == nil {
		t.Fatal("duplicate old fence accepted")
	}
	same := set(p.PostID, identity, true, first.InteractionVersion)
	if !same.Value.(posts.RepostState).Items[0].RepostedAt.Equal(first.Value.(posts.RepostState).Items[0].RepostedAt) {
		t.Fatal("retry changed sort time")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_reposts`) != 1 {
		t.Fatal("duplicate")
	}
	// Own second identity may retain an independent private reference.
	multi := set(p.PostID, secondIdentity, true, same.InteractionVersion)
	if len(multi.Value.(posts.RepostState).Items) != 2 {
		t.Fatal("identity ownership lost")
	}
	set(p2.PostID, identity, true, read(reader.SessionToken, p2.PostID).InteractionVersion)
	page := list(reader.SessionToken, "", 1)
	if len(page.Items) != 1 || page.Items[0].PostID != p2.PostID || page.NextCursor == nil || page.Items[0].Post == nil || page.Items[0].Post.Author.Nickname != "作者" {
		t.Fatal("order/original projection", page)
	}
	fence := read(reader.SessionToken, p.PostID)
	removed := set(p.PostID, identity, false, fence.InteractionVersion)
	set(p.PostID, identity, true, removed.InteractionVersion)
	next := list(reader.SessionToken, *page.NextCursor, 1)
	if next.Items[0].IdentityID != secondIdentity.String() {
		t.Fatal("equal-time ordinal ordering")
	}
	if next.NextCursor != nil {
		t.Fatal("re-added item entered old pagination snapshot")
	}
	if _, e := l.c.ListPostReposts(ctx, reader.SessionToken, PostQuery{Cursor: *page.NextCursor, Limit: 2}); e == nil {
		t.Fatal("changed limit accepted old cursor")
	}
	if _, e := l.c.ListPostReposts(ctx, other.SessionToken, PostQuery{Cursor: *page.NextCursor, Limit: 1}); e == nil {
		t.Fatal("foreign cursor")
	}
	if len(list(other.SessionToken, "", 20).Items) != 0 || len(read(other.SessionToken, p.PostID).Value.(posts.RepostState).Items) != 0 {
		t.Fatal("private archive leak")
	}
	// Hold original create; retry commits, cancellation commits, delayed create must fail.
	before := read(reader.SessionToken, p2.PostID)
	cancelled := set(p2.PostID, identity, false, before.InteractionVersion)
	barrier := &identitySnapshotBarrier{AuthorizationGate: l.c.gate, captured: make(chan struct{}), release: make(chan struct{})}
	delayed := *l.c
	delayed.gate = barrier
	done := make(chan error, 1)
	go func() {
		_, e := delayed.SetPostRepost(ctx, reader.SessionToken, p2.PostID, identity.String(), true, cancelled.InteractionVersion)
		done <- e
	}()
	<-barrier.captured
	committed := set(p2.PostID, identity, true, cancelled.InteractionVersion)
	set(p2.PostID, identity, false, committed.InteractionVersion)
	close(barrier.release)
	postTestError(t, <-done, "INTERACTION_VERSION_CONFLICT", 412)
	if len(read(reader.SessionToken, p2.PostID).Value.(posts.RepostState).Items) != 0 {
		t.Fatal("late create revived cancellation")
	}
	// Concurrent cancellation: only one CAS consumes the condition.
	condition := read(reader.SessionToken, p.PostID).InteractionVersion
	results := make(chan error, 8)
	for n := 0; n < 8; n++ {
		go func() {
			_, e := l.c.SetPostRepost(ctx, reader.SessionToken, p.PostID, identity.String(), false, condition)
			results <- e
		}()
	}
	successes := 0
	for n := 0; n < 8; n++ {
		if <-results == nil {
			successes++
		}
	}
	if successes != 1 {
		t.Fatal("CAS not atomic", successes)
	}
	if len(read(reader.SessionToken, p.PostID).Value.(posts.RepostState).Items) != 1 {
		t.Fatal("cancel removed other identity")
	}
	// No new publication, favorite, like, view or speaking binding.
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts`) != 2 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_favorites`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_likes`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_identity_bindings WHERE account_id=$1`, reader.AccountID) != 0 {
		t.Fatal("repost mutated other interaction")
	}
	raw, _ := json.Marshal(list(reader.SessionToken, "", 20))
	if strings.Contains(string(raw), reader.AccountID.String()) || strings.Contains(string(raw), "accountId") {
		t.Fatal("account identifier serialized")
	}
	// Hidden/deleted source carries no payload, still removable by owner.
	if _, e := l.cp.Exec(ctx, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, p.PostID); e != nil {
		t.Fatal(e)
	}
	hidden := list(reader.SessionToken, "", 20)
	if len(hidden.Items) != 1 || hidden.Items[0].Post != nil {
		t.Fatal("hidden original leaked")
	}
	set(p.PostID, secondIdentity, false, read(reader.SessionToken, p.PostID).InteractionVersion)
	if _, e := l.c.SetPostRepost(ctx, reader.SessionToken, p.PostID, secondIdentity.String(), true, read(reader.SessionToken, p.PostID).InteractionVersion); e == nil {
		t.Fatal("hidden source reposted")
	}
	if len(list(reader.SessionToken, "", 20).Items) != 0 {
		t.Fatal("unavailable cancellation failed")
	}
	if _, e := l.c.ReadPostReposts(ctx, [32]byte{1}, p.PostID); e == nil {
		t.Fatal("invalid session accepted")
	}
	// Identity lifecycle deletes only its archive and rotates the fence.
	set(p2.PostID, identity, true, read(reader.SessionToken, p2.PostID).InteractionVersion)
	identityChange(t, l.c, reader.SessionToken, "DELETE", identity, "")
	if len(list(reader.SessionToken, "", 20).Items) != 0 {
		t.Fatal("deleted identity archive")
	}
	if err := checkPostRepostSchema(ctx, l.cp, true); err != nil {
		t.Fatal("schema", err)
	}
}
