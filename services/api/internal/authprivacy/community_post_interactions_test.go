package authprivacy

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func interactionTestRead(t *testing.T, l *lab, token [32]byte, ids ...string) []posts.PostInteractions {
	t.Helper()
	r, err := l.c.ReadPostInteractions(context.Background(), token, ids)
	if err != nil || !r.ExpiresAt.After(r.ServerTime) {
		t.Fatal("interaction authority/read failed", err)
	}
	return r.Value.(posts.PostInteractionPage).Items
}

func interactionTestSet(t *testing.T, l *lab, token [32]byte, id string, kind posts.InteractionKind, enabled bool) posts.PostInteractions {
	t.Helper()
	r, err := l.c.SetPostInteraction(context.Background(), token, id, kind, enabled)
	if err != nil || !r.ExpiresAt.After(r.ServerTime) {
		t.Fatal("interaction mutation failed", err)
	}
	return r.Value.(posts.PostInteractions)
}

func TestFeedInteractionsAccountIsolationAndConcurrencyPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "interaction_owner")
	reader := sessionTestAccount(t, l, "interaction_reader")
	other := sessionTestAccount(t, l, "interaction_other")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Author").IdentityID
	intent := postTestIntent(t, l, id)
	first := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	second := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	if _, err := l.c.SetPostInteraction(ctx, reader.SessionToken, first.PostID, posts.PostLike, true); err == nil {
		t.Fatal("unpublished post accepted a like")
	}
	postTestPublish(t, l)
	for _, kind := range []posts.InteractionKind{posts.PostLike, posts.PostFavorite} {
		interactionTestSet(t, l, reader.SessionToken, first.PostID, kind, true)
		interactionTestSet(t, l, owner.SessionToken, first.PostID, kind, true)
	}
	const parallel = 12
	done := make(chan error, parallel)
	for i := 0; i < parallel; i++ {
		token := reader.SessionToken
		if i%2 == 0 {
			token = owner.SessionToken
		}
		go func(token [32]byte) {
			_, err := l.c.SetPostInteraction(ctx, token, first.PostID, posts.PostLike, true)
			done <- err
		}(token)
	}
	for i := 0; i < parallel; i++ {
		if err := <-done; err != nil {
			t.Fatal(err)
		}
	}
	// A reader without a speaking identity can interact, without making a binding.
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_identity_bindings WHERE account_id=$1`, reader.AccountID) != 0 {
		t.Fatal("interaction bound a speaking identity")
	}
	readerIdentity := identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "Reader").IdentityID
	identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "Another")
	identityChange(t, l.c, reader.SessionToken, "DELETE", readerIdentity, "")
	items := interactionTestRead(t, l, reader.SessionToken, second.PostID, first.PostID)
	if items[0].PostID != second.PostID || items[0].LikeCount != 0 || items[1].LikeCount != 2 || items[1].FavoriteCount != 2 || !items[1].LikedByMe || !items[1].FavoritedByMe {
		t.Fatal("order, self-like, identity-independent or dedup violation", items)
	}
	foreign := interactionTestRead(t, l, other.SessionToken, first.PostID)[0]
	if foreign.LikedByMe || foreign.FavoritedByMe || foreign.LikeCount != 2 {
		t.Fatal("private state crossed accounts", foreign)
	}
	var saved string
	if err := l.cp.QueryRow(ctx, `SELECT saved_at::text FROM c_posts.post_favorites WHERE account_id=$1 AND post_id=$2`, reader.AccountID, first.PostID).Scan(&saved); err != nil {
		t.Fatal(err)
	}
	interactionTestSet(t, l, reader.SessionToken, first.PostID, posts.PostFavorite, true)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_favorites WHERE account_id=$1 AND post_id=$2 AND saved_at::text=$3`, reader.AccountID, first.PostID, saved) != 1 {
		t.Fatal("retry reordered favorite")
	}
	for i := 0; i < 2; i++ {
		v := interactionTestSet(t, l, reader.SessionToken, first.PostID, posts.PostLike, false)
		if v.LikedByMe || v.LikeCount != 1 || !v.FavoritedByMe {
			t.Fatal("unlike was not independent/idempotent", v)
		}
		v = interactionTestSet(t, l, reader.SessionToken, first.PostID, posts.PostFavorite, false)
		if v.FavoritedByMe || v.FavoriteCount != 1 {
			t.Fatal("unfavorite was not independent/idempotent", v)
		}
		if i == 0 {
			interactionTestSet(t, l, reader.SessionToken, first.PostID, posts.PostFavorite, true)
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_daily_views`) != 0 {
		t.Fatal("interaction counted a view")
	}
	for _, ids := range [][]string{nil, {}, {first.PostID, first.PostID}, {"bad"}, {uuid.NewString()}} {
		if _, err := l.c.ReadPostInteractions(ctx, reader.SessionToken, ids); err == nil {
			t.Fatal("invalid/missing batch accepted")
		}
	}
	if _, err := l.c.ReadPostInteractions(ctx, [32]byte{1}, []string{first.PostID}); !errors.Is(err, ErrSessionInvalid) {
		t.Fatal("anonymous interaction read", err)
	}
}

func TestFeedInteractionsReuseVisibleCommentCountPostgres(t *testing.T) {
	l, ctx := commentTextLab(t), context.Background()
	owner := sessionTestAccount(t, l, "interaction_comments")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Author").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, id)
	rootIntent := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: id.String(), Body: "root"}
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), rootIntent)
	commentTextPublish(t, l)
	root := *commentTextOwn(t, l, owner.SessionToken, rootIntent.TaskID).PublishedCommentID
	reply := rootIntent
	reply.TaskID, reply.RootCommentID, reply.TargetCommentID = uuid.NewString(), root, root
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), reply)
	commentTextPublish(t, l)
	pending := rootIntent
	pending.TaskID = uuid.NewString()
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), pending)
	assertCount := func(want int) {
		t.Helper()
		item := interactionTestRead(t, l, owner.SessionToken, post)[0]
		context, err := l.c.ReadCommentContext(ctx, owner.SessionToken, post)
		if err != nil || context.Value.(CommentContext).TotalCount != want || item.CommentCount != want {
			t.Fatal("comment context and feed count diverged", want, item.CommentCount, err)
		}
		page, err := l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post})
		if err != nil || *page.Value.(TextCommentPage).TotalCount != want {
			t.Fatal("comment page count diverged", err)
		}
	}
	assertCount(2)
	mustExec(t, l.cp, `UPDATE c_comments.tasks SET moderation_hidden=true WHERE comment_id=$1`, root)
	assertCount(0)
	mustExec(t, l.cp, `UPDATE c_comments.tasks SET moderation_hidden=false WHERE comment_id=$1`, root)
	assertCount(2)
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), comments.Intent{Operation: comments.DeleteComment, CommentID: root})
	assertCount(0)
}

func TestFeedInteractionsVisibilityRollbackAndSchemaPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "interaction_visibility")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Author").IdentityID
	post := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id)).PostID
	postTestPublish(t, l)
	mustExec(t, l.cp, `CREATE FUNCTION c_posts.reject_interaction() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic interaction failure'; END $$; CREATE TRIGGER reject_interaction AFTER INSERT ON c_posts.post_likes FOR EACH ROW EXECUTE FUNCTION c_posts.reject_interaction()`)
	if _, err := l.c.SetPostInteraction(ctx, owner.SessionToken, post, posts.PostLike, true); err == nil {
		t.Fatal("synthetic failure accepted")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_likes`) != 0 {
		t.Fatal("failed transaction retained like")
	}
	mustExec(t, l.cp, `DROP TRIGGER reject_interaction ON c_posts.post_likes`)
	interactionTestSet(t, l, owner.SessionToken, post, posts.PostLike, true)
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, post)
	if _, err := l.c.ReadPostInteractions(ctx, owner.SessionToken, []string{post}); err == nil {
		t.Fatal("hidden post summary leaked")
	}
	if _, err := l.c.SetPostInteraction(ctx, owner.SessionToken, post, posts.PostFavorite, true); err == nil {
		t.Fatal("hidden post accepted favorite")
	}
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=false WHERE post_id=$1`, post)
	interactionTestSet(t, l, owner.SessionToken, post, posts.PostFavorite, true)
	postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: post})
	if _, err := l.c.ReadPostInteractions(ctx, owner.SessionToken, []string{post}); err == nil {
		t.Fatal("deleted post summary leaked")
	}
	for _, table := range []string{"post_likes", "post_favorites"} {
		mustExec(t, l.cp, `ALTER TABLE c_posts.`+table+` DROP CONSTRAINT `+table+`_pkey`)
		if l.c.CheckPostSchema(ctx) == nil || CheckModerationLifecycleSchema(ctx, l.cp) == nil {
			t.Fatal("missing interaction key accepted")
		}
		mustExec(t, l.cp, `ALTER TABLE c_posts.`+table+` ADD PRIMARY KEY(account_id,post_id)`)
	}
}

func TestFeedInteractionsFinalSessionAndGatePostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "interaction_gate")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Author").IdentityID
	post := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id)).PostID
	postTestPublish(t, l)
	barrier := &identitySnapshotBarrier{AuthorizationGate: l.c.gate, captured: make(chan struct{}), release: make(chan struct{})}
	stale := *l.c
	stale.gate = barrier
	done := make(chan error, 1)
	go func() {
		_, err := stale.SetPostInteraction(ctx, owner.SessionToken, post, posts.PostLike, true)
		done <- err
	}()
	<-barrier.captured
	if _, err := l.c.CreateSession(ctx, sessionTestRequest(t, "interaction_gate"), sessionTestPasswordWorker(t, 1)); err != nil {
		t.Fatal(err)
	}
	close(barrier.release)
	if err := <-done; !errors.Is(err, ErrSessionReplaced) {
		t.Fatal("replaced session committed", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_likes`) != 0 {
		t.Fatal("stale write survived")
	}
	if err := l.gate.Freeze(ctx, "interaction fixture"); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.ReadPostInteractions(ctx, owner.SessionToken, []string{post}); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("frozen read", err)
	}
	if _, err := l.c.SetPostInteraction(ctx, owner.SessionToken, post, posts.PostLike, true); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("frozen write", err)
	}
}
