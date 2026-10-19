package authprivacy

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestFeedSchemaRequiresUniqueKeysPostgres(t *testing.T) {
	for _, table := range []string{"post_daily_views", "post_view_totals", "feed_preferences"} {
		t.Run(table, func(t *testing.T) {
			l := newPostLab(t)
			ctx := context.Background()
			mustExec(t, l.cp, `ALTER TABLE c_posts.`+table+` DROP CONSTRAINT `+table+`_pkey`)
			if err := l.c.CheckPostSchema(ctx); err == nil {
				t.Fatal("post startup accepted a missing feed uniqueness constraint")
			}
			if err := CheckModerationLifecycleSchema(ctx, l.cp); err == nil {
				t.Fatal("common C startup accepted a missing feed uniqueness constraint")
			}
		})
	}
	for _, shape := range []struct{ name, sql string }{
		{"wrong_columns", `PRIMARY KEY(account_id,post_id)`},
		{"deferred", `PRIMARY KEY(account_id,post_id,view_day) DEFERRABLE INITIALLY DEFERRED`},
	} {
		t.Run(shape.name, func(t *testing.T) {
			l := newPostLab(t)
			mustExec(t, l.cp, `ALTER TABLE c_posts.post_daily_views DROP CONSTRAINT post_daily_views_pkey; ALTER TABLE c_posts.post_daily_views ADD `+shape.sql)
			if err := l.c.CheckPostSchema(context.Background()); err == nil {
				t.Fatal("startup accepted a dedup key incompatible with registration")
			}
		})
	}
}

func TestFeedViewDedupKeyLossFailsClosedPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "feed_key_owner")
	reader := sessionTestAccount(t, l, "feed_key_reader")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "KeyAuthor").IdentityID
	created := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id))
	postTestPublish(t, l)
	query := PostQuery{Kind: PostViewRecord, ID: created.PostID}
	if view := postTestRead(t, l, reader.SessionToken, query).(posts.PostView); view.ViewCount != 1 {
		t.Fatal("first view missing")
	}
	mustExec(t, l.cp, `ALTER TABLE c_posts.post_daily_views DROP CONSTRAINT post_daily_views_pkey`)
	if _, err := l.c.ReadPosts(ctx, reader.SessionToken, query); err == nil {
		t.Fatal("missing dedup key allowed a repeated view to commit")
	}
	if count(t, l.cp, `SELECT view_count FROM c_posts.post_view_totals WHERE post_id=$1`, created.PostID) != 1 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_daily_views WHERE post_id=$1`, created.PostID) != 1 {
		t.Fatal("failed registration changed view facts")
	}
	// A rejected pre-checkpoint write must not freeze otherwise valid business.
	postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostDetail, ID: created.PostID})
}

func TestFeedViewFailureRollsBackAndConcurrentAccountsPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "feed_rollback_owner")
	reader := sessionTestAccount(t, l, "feed_rollback_reader")
	other := sessionTestAccount(t, l, "feed_rollback_other")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "RollAuthor").IdentityID
	intent := postTestIntent(t, l, id)
	created := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	postTestPublish(t, l)
	for _, query := range []PostQuery{{Kind: PostDetail, ID: created.PostID}, {Kind: PostFeed}, {Kind: PostChannelFeed, ID: intent.ChannelID}} {
		postTestRead(t, l, reader.SessionToken, query)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_daily_views`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_view_totals`) != 0 {
		t.Fatal("a non-author read counted a view")
	}
	// Force failure after inserting the daily key but before committing its total.
	mustExec(t, l.cp, `CREATE FUNCTION c_posts.reject_review_view_total() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic total write failure'; END $$;
 CREATE TRIGGER reject_review_view_total BEFORE INSERT OR UPDATE ON c_posts.post_view_totals FOR EACH ROW EXECUTE FUNCTION c_posts.reject_review_view_total()`)
	query := PostQuery{Kind: PostViewRecord, ID: created.PostID}
	if _, err := l.c.ReadPosts(ctx, reader.SessionToken, query); err == nil {
		t.Fatal("synthetic aggregate failure was accepted")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_daily_views`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_view_totals`) != 0 {
		t.Fatal("failed aggregate retained partial facts")
	}
	mustExec(t, l.cp, `DROP TRIGGER reject_review_view_total ON c_posts.post_view_totals; DROP FUNCTION c_posts.reject_review_view_total()`)
	const concurrent = 12
	done := make(chan error, concurrent)
	for i := 0; i < concurrent; i++ {
		bearer := reader.SessionToken
		if i%2 == 0 {
			bearer = other.SessionToken
		}
		go func(token [32]byte) {
			_, err := l.c.ReadPosts(ctx, token, query)
			done <- err
		}(bearer)
	}
	for i := 0; i < concurrent; i++ {
		if err := <-done; err != nil {
			t.Fatal(err)
		}
	}
	if count(t, l.cp, `SELECT view_count FROM c_posts.post_view_totals WHERE post_id=$1`, created.PostID) != 2 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_daily_views WHERE post_id=$1`, created.PostID) != 2 {
		t.Fatal("distinct account contributions were lost or duplicated")
	}
}

func TestFeedVisibilityChangesAndPreferenceABAPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "feed_visibility_owner")
	reader := sessionTestAccount(t, l, "feed_visibility_reader")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "ViewAuthor").IdentityID
	channels := feedTestChannels(t, l)
	intent := postTestIntent(t, l, id)
	intent.ChannelID = channels[0]
	for i := 0; i < 8; i++ {
		postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	}
	postTestPublish(t, l)
	all := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeed}).(posts.CrossChannelFeedPage)
	first := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeed, Limit: 2}).(posts.CrossChannelFeedPage)
	if len(all.Items) != 8 || first.NextCursor == nil {
		t.Fatal("missing pagination fixture")
	}
	for _, post := range all.Items[2:4] {
		mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, post.PostID)
	}
	postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: all.Items[4].PostID})
	later := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	postTestPublish(t, l)
	second := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeed, Limit: 2, Cursor: *first.NextCursor}).(posts.CrossChannelFeedPage)
	if len(second.Items) != 2 || second.NextCursor == nil || second.Items[0].PostID != all.Items[5].PostID || second.Items[1].PostID != all.Items[6].PostID {
		t.Fatal("visibility changes consumed page slots or changed continuation order")
	}
	for _, post := range second.Items {
		if post.PostID == later.PostID {
			t.Fatal("new publication entered the snapshot")
		}
	}
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, all.Items[7].PostID)
	last := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeed, Limit: 2, Cursor: *second.NextCursor}).(posts.CrossChannelFeedPage)
	if len(last.Items) != 0 || last.NextCursor != nil {
		t.Fatal("removing the final unread item did not terminate pagination")
	}
	set := func(ids []string) {
		if _, err := l.c.ReplaceFeedPreferences(ctx, reader.SessionToken, posts.FeedPreferences{BlockedChannelIDs: ids}); err != nil {
			t.Fatal(err)
		}
	}
	set([]string{channels[2], channels[1]})
	page := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeed, Limit: 1}).(posts.CrossChannelFeedPage)
	if page.NextCursor == nil {
		t.Fatal("missing preference-bound cursor")
	}
	query := PostQuery{Kind: PostFeed, Limit: 1, Cursor: *page.NextCursor}
	set([]string{channels[1], channels[2]})
	postTestRead(t, l, reader.SessionToken, query)
	set([]string{})
	set([]string{channels[2], channels[1]})
	if _, err := l.c.ReadPosts(ctx, reader.SessionToken, query); !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("restoring an old preference set revived its old cursor", err)
	}
}
