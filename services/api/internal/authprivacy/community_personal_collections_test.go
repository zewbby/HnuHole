package authprivacy

import (
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"testing"
)

func TestPersonalIdentityAndSharedCollectionsPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "personal_owner")
	other := sessionTestAccount(t, l, "personal_other")
	first := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "First").IdentityID
	second := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Second").IdentityID
	a := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, first))
	b := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, second))
	c := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, first))
	postTestPublish(t, l)
	own := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostOwnList, IdentityID: first.String(), Limit: 1}).(posts.OwnPostPage)
	if len(own.Items) != 1 || own.NextCursor == nil || own.Items[0].Post.PostID == b.PostID {
		t.Fatal("identity filter/pagination", own)
	}
	_, err := l.c.ReadPosts(ctx, owner.SessionToken, PostQuery{Kind: PostOwnList, IdentityID: second.String(), Cursor: *own.NextCursor, Limit: 1})
	if !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("cursor crossed identities", err)
	}
	rest := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostOwnList, IdentityID: first.String(), Cursor: *own.NextCursor, Limit: 1}).(posts.OwnPostPage)
	if len(rest.Items) != 1 || rest.Items[0].Post.PostID == b.PostID || rest.Items[0].Post.PostID == own.Items[0].Post.PostID {
		t.Fatal("wrong next identity page", rest)
	}
	_, err = l.c.ReadPosts(ctx, other.SessionToken, PostQuery{Kind: PostOwnList, IdentityID: first.String()})
	postTestError(t, err, "POST_IDENTITY_UNAVAILABLE", 409)
	for _, kind := range []posts.InteractionKind{posts.PostLike, posts.PostFavorite} {
		interactionTestSet(t, l, owner.SessionToken, a.PostID, kind, true)
		interactionTestSet(t, l, owner.SessionToken, b.PostID, kind, true)
		interactionTestSet(t, l, owner.SessionToken, c.PostID, kind, true)
	}
	for _, kind := range []PostReadKind{PostLikedList, PostFavoriteList} {
		page := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: kind, Limit: 2}).(posts.FeedPage)
		if len(page.Items) != 2 || page.NextCursor == nil {
			t.Fatal("collection pagination", page)
		}
		next := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: kind, Limit: 2, Cursor: *page.NextCursor}).(posts.FeedPage)
		if len(next.Items) != 1 || next.Items[0].PostID == page.Items[0].PostID || next.Items[0].PostID == page.Items[1].PostID {
			t.Fatal("collection next page", next)
		}
		empty := postTestRead(t, l, other.SessionToken, PostQuery{Kind: kind}).(posts.FeedPage)
		if len(empty.Items) != 0 {
			t.Fatal("collection crossed accounts")
		}
		_, err = l.c.ReadPosts(ctx, other.SessionToken, PostQuery{Kind: kind, Limit: 2, Cursor: *page.NextCursor})
		if !errors.Is(err, posts.ErrCursorInvalid) {
			t.Fatal("collection cursor crossed accounts", err)
		}
	}
	interactionTestSet(t, l, owner.SessionToken, a.PostID, posts.PostLike, false)
	interactionTestSet(t, l, owner.SessionToken, a.PostID, posts.PostFavorite, false)
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, b.PostID)
	for _, kind := range []PostReadKind{PostLikedList, PostFavoriteList} {
		page := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: kind}).(posts.FeedPage)
		if len(page.Items) != 1 || page.Items[0].PostID != c.PostID {
			t.Fatal("removed or hidden item leaked", page)
		}
	}
}
