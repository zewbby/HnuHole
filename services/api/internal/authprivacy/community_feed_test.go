package authprivacy

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func feedTestChannels(t *testing.T, l *lab) []string {
	t.Helper()
	rows, err := l.cp.Query(context.Background(), `SELECT id FROM public.channels ORDER BY id`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	ids := []string{}
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			t.Fatal(err)
		}
		ids = append(ids, id)
	}
	if rows.Err() != nil || len(ids) != 7 {
		t.Fatal("missing channel catalog")
	}
	return ids
}

func TestFeedViewsAccountDailyConcurrencyPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "feed_view_owner")
	reader := sessionTestAccount(t, l, "feed_view_reader")
	other := sessionTestAccount(t, l, "feed_view_other")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Author").IdentityID
	identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Second")
	intent := postTestIntent(t, l, id)
	p := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	_, err := l.c.ReadPosts(ctx, reader.SessionToken, PostQuery{Kind: PostViewRecord, ID: p.PostID})
	postTestError(t, err, "POST_NOT_FOUND", 404)
	postTestPublish(t, l)
	for _, kind := range []PostReadKind{PostFeed, PostChannelFeed, PostDetail, PostOwnList} {
		q := PostQuery{Kind: kind}
		if kind == PostChannelFeed {
			q.ID = intent.ChannelID
		}
		if kind == PostDetail {
			q.ID = p.PostID
		}
		postTestRead(t, l, owner.SessionToken, q)
	}
	view := func(token [32]byte) posts.PostView {
		return postTestRead(t, l, token, PostQuery{Kind: PostViewRecord, ID: p.PostID}).(posts.PostView)
	}
	if view(owner.SessionToken).ViewCount != 0 {
		t.Fatal("author counted")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_daily_views`) != 0 {
		t.Fatal("read/exposure counted")
	}
	identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "ReaderOne")
	identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "ReaderTwo")
	const parallel = 10
	errorsSeen := make(chan error, parallel)
	for i := 0; i < parallel; i++ {
		go func() {
			_, e := l.c.ReadPosts(ctx, reader.SessionToken, PostQuery{Kind: PostViewRecord, ID: p.PostID})
			errorsSeen <- e
		}()
	}
	for i := 0; i < parallel; i++ {
		if e := <-errorsSeen; e != nil {
			t.Fatal(e)
		}
	}
	if view(reader.SessionToken).ViewCount != 1 || view(other.SessionToken).ViewCount != 2 {
		t.Fatal("account dedup or independent reader failed")
	}
	// Advance the final Gate's trusted clock across Shanghai midnight, not UTC.
	local := control.clock.now().In(feedDayZone)
	midnight := time.Date(local.Year(), local.Month(), local.Day()+1, 0, 0, 0, 0, feedDayZone).UTC()
	advanceClosureClock(t, control, midnight.Add(-time.Microsecond))
	if view(reader.SessionToken).ViewCount != 2 {
		t.Fatal("same local day recounted")
	}
	advanceClosureClock(t, control, midnight)
	if view(reader.SessionToken).ViewCount != 3 || view(owner.SessionToken).ViewCount != 3 {
		t.Fatal("midnight or author exclusion failed")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_daily_views WHERE account_id=$1`, reader.AccountID) != 1 {
		t.Fatal("old reader keys not pruned")
	}
	public := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostDetail, ID: p.PostID}).(posts.PublicPostResponse)
	encoded, _ := json.Marshal(public)
	for _, secret := range []string{reader.AccountID.String(), owner.AccountID.String(), id.String(), "view_day", "accountId", "counted"} {
		if strings.Contains(string(encoded), secret) {
			t.Fatal("private visitor data escaped")
		}
	}
	page := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeed}).(posts.CrossChannelFeedPage)
	if len(page.Items) != 1 || page.Items[0].ViewCount != 3 {
		t.Fatal("feed total missing")
	}
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, p.PostID)
	_, err = l.c.ReadPosts(ctx, reader.SessionToken, PostQuery{Kind: PostViewRecord, ID: p.PostID})
	postTestError(t, err, "POST_NOT_FOUND", 404)
	if count(t, l.cp, `SELECT view_count FROM c_posts.post_view_totals WHERE post_id=$1`, p.PostID) != 3 {
		t.Fatal("hidden post counted")
	}
}

func TestFeedFilteringSnapshotAndPreferenceBindingPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "feed_page_owner")
	reader := sessionTestAccount(t, l, "feed_page_reader")
	other := sessionTestAccount(t, l, "feed_page_other")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Author").IdentityID
	channels := feedTestChannels(t, l)
	intent := postTestIntent(t, l, id)
	// One worker batch gives identical timestamps; ordinal must break ties.
	for i := 0; i < 8; i++ {
		intent.ChannelID = channels[i%2]
		postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	}
	postTestPublish(t, l)
	intent.ChannelID = channels[0]
	hidden := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	deleted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	postTestPublish(t, l)
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, hidden.PostID)
	postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: deleted.PostID})
	set := func(ids []string) {
		if _, e := l.c.ReplaceFeedPreferences(ctx, reader.SessionToken, posts.FeedPreferences{BlockedChannelIDs: ids}); e != nil {
			t.Fatal(e)
		}
	}
	set([]string{channels[1]})
	q := PostQuery{Kind: PostFeed, Limit: 2}
	first := postTestRead(t, l, reader.SessionToken, q).(posts.CrossChannelFeedPage)
	if len(first.Items) != 2 || first.NextCursor == nil {
		t.Fatal("blocked posts consumed page slots")
	}
	q.Cursor = *first.NextCursor
	// Reopen the business connection to verify database-backed preferences.
	set([]string{channels[1]})
	newPool, e := pgxpool.New(ctx, os.Getenv("AUTHLAB_C_DSN"))
	if e != nil {
		t.Fatal(e)
	}
	defer newPool.Close()
	reopened := *l.c
	reopened.pool = newPool
	l.c = &reopened
	prefs := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeedPreferences}).(posts.FeedPreferences)
	if len(prefs.BlockedChannelIDs) != 1 {
		t.Fatal("preference not persisted")
	}
	if len(postTestRead(t, l, other.SessionToken, PostQuery{Kind: PostFeedPreferences}).(posts.FeedPreferences).BlockedChannelIDs) != 0 {
		t.Fatal("preference crossed accounts")
	}
	intent.ChannelID = channels[0]
	later := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	postTestPublish(t, l)
	second := postTestRead(t, l, reader.SessionToken, q).(posts.CrossChannelFeedPage)
	seen := map[string]bool{}
	items := append(first.Items, second.Items...)
	for _, item := range items {
		if item.ChannelID != channels[0] || seen[item.PostID] || item.PostID == later.PostID {
			t.Fatal("scope/snapshot/order violation")
		}
		seen[item.PostID] = true
	}
	if len(seen) != 4 || second.NextCursor != nil {
		t.Fatal("filtered traversal lost rows")
	}
	for i := 1; i < len(items); i++ {
		previous := count(t, l.cp, `SELECT publication_ordinal FROM c_posts.posts WHERE post_id=$1`, items[i-1].PostID)
		current := count(t, l.cp, `SELECT publication_ordinal FROM c_posts.posts WHERE post_id=$1`, items[i].PostID)
		if !items[i-1].PublishedAt.Equal(items[i].PublishedAt) || previous <= current {
			t.Fatal("same-time unique order was not stable")
		}
	}
	for _, wrong := range []PostQuery{{Kind: PostChannelFeed, ID: channels[0], Limit: 2, Cursor: q.Cursor}, {Kind: PostFeed, ID: channels[0], Limit: 2, Cursor: q.Cursor}, {Kind: PostFeed, Limit: 1, Cursor: q.Cursor}} {
		if _, e := l.c.ReadPosts(ctx, reader.SessionToken, wrong); !errors.Is(e, posts.ErrCursorInvalid) {
			t.Fatal("foreign scope cursor accepted", e)
		}
	}
	if _, e := l.c.ReadPosts(ctx, other.SessionToken, q); !errors.Is(e, posts.ErrCursorInvalid) {
		t.Fatal("cursor crossed accounts", e)
	}
	set(channels)
	if _, e := l.c.ReadPosts(ctx, reader.SessionToken, q); !errors.Is(e, posts.ErrCursorInvalid) {
		t.Fatal("changed preference reused cursor", e)
	}
	for _, selected := range []string{"", channels[0]} {
		page := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeed, ID: selected}).(posts.CrossChannelFeedPage)
		if len(page.Items) != 0 || page.NextCursor != nil {
			t.Fatal("all blocked must be empty")
		}
	}
	legacy := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostChannelFeed, ID: channels[1]}).(posts.FeedPage)
	if len(legacy.Items) != 4 {
		t.Fatal("legacy channel endpoint changed preference semantics")
	}
	set([]string{})
	page := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeed}).(posts.CrossChannelFeedPage)
	if len(page.Items) != 9 || page.Items[0].PostID != later.PostID {
		t.Fatal("reset lost feed rows")
	}
	for _, ids := range [][]string{nil, {channels[0], channels[0]}, {uuid.NewString()}} {
		if _, e := l.c.ReplaceFeedPreferences(ctx, reader.SessionToken, posts.FeedPreferences{BlockedChannelIDs: ids}); e == nil {
			t.Fatal("invalid preference accepted")
		}
	}
}

func TestFeedRuntimePrivilegesClosureAndStartupPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "feed_runtime_owner")
	reader := sessionTestAccount(t, l, "feed_runtime_reader")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Author").IdentityID
	p := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id))
	postTestPublish(t, l)
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	grant, e := os.ReadFile("../../../../infra/postgres/grant-community.sql")
	if e != nil {
		t.Fatal(e)
	}
	mustExec(t, l.cp, string(grant))
	pool, e := pgxpool.New(ctx, os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	clone := *l.c
	clone.pool = pool
	l.c = &clone
	if e = l.c.CheckPostSchema(ctx); e != nil {
		t.Fatal(e)
	}
	postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostViewRecord, ID: p.PostID})
	if _, e = l.c.ReplaceFeedPreferences(ctx, reader.SessionToken, posts.FeedPreferences{BlockedChannelIDs: feedTestChannels(t, l)[:1]}); e != nil {
		t.Fatal(e)
	}
	postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostFeed})
	interactionTestSet(t, l, reader.SessionToken, p.PostID, posts.PostLike, true)
	interactionTestSet(t, l, reader.SessionToken, p.PostID, posts.PostFavorite, true)
	interactionTestSet(t, l, owner.SessionToken, p.PostID, posts.PostLike, true)
	interactionTestSet(t, l, owner.SessionToken, p.PostID, posts.PostFavorite, true)
	for _, sql := range []string{`REVOKE DELETE ON c_posts.feed_preferences FROM hnuhole_c_runtime`, `ALTER TABLE c_auth.accounts DISABLE TRIGGER feed_account_closed`} {
		tx, err := l.cp.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = tx.Exec(ctx, sql); err != nil {
			t.Fatal(err)
		}
		if err = tx.Commit(ctx); err != nil {
			t.Fatal(err)
		}
		if CheckModerationLifecycleSchema(ctx, pool) == nil {
			t.Fatal("common startup ignored missing feed cleanup")
		}
		mustExec(t, l.cp, `GRANT DELETE ON c_posts.feed_preferences TO hnuhole_c_runtime; ALTER TABLE c_auth.accounts ENABLE TRIGGER feed_account_closed`)
	}
	// A reader without public identities can close through the original path.
	request, _ := closureTestRequest(t, reader.SessionToken)
	closure, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	_, err = l.c.SetPostInteraction(ctx, reader.SessionToken, p.PostID, posts.PostLike, false)
	if !errors.Is(err, ErrSessionInvalid) {
		t.Fatal("pending closure session retained write access", err)
	}
	if _, err = l.c.ReadPostInteractions(ctx, reader.SessionToken, []string{p.PostID}); !errors.Is(err, ErrSessionInvalid) {
		t.Fatal("pending closure session retained read access", err)
	}
	advanceClosureClock(t, control, closure.DueAt)
	if n, e := l.c.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
		t.Fatal("original closure path failed", n, e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_daily_views WHERE account_id=$1`, reader.AccountID) != 0 || count(t, l.cp, `SELECT count(*) FROM c_posts.feed_preferences WHERE account_id=$1`, reader.AccountID) != 0 {
		t.Fatal("closure retained private feed data")
	}
	if count(t, l.cp, `SELECT view_count FROM c_posts.post_view_totals WHERE post_id=$1`, p.PostID) != 1 {
		t.Fatal("closure changed cumulative total")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_likes WHERE account_id=$1`, reader.AccountID) != 0 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_favorites WHERE account_id=$1`, reader.AccountID) != 0 {
		t.Fatal("closure retained private interactions")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_interaction_versions WHERE account_id=$1`, reader.AccountID) != 0 {
		t.Fatal("closure retained private write fence")
	}
	remaining := interactionTestRead(t, l, owner.SessionToken, p.PostID)[0]
	if remaining.LikeCount != 1 || remaining.FavoriteCount != 1 || !remaining.LikedByMe || !remaining.FavoritedByMe {
		t.Fatal("closure touched another account", remaining)
	}
}

func TestFeedFinalGateAndSessionPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	reader := sessionTestAccount(t, l, "feed_gate_reader")
	channels := feedTestChannels(t, l)
	barrier := &identitySnapshotBarrier{AuthorizationGate: l.c.gate, captured: make(chan struct{}), release: make(chan struct{})}
	stale := *l.c
	stale.gate = barrier
	done := make(chan error, 1)
	go func() {
		_, e := stale.ReplaceFeedPreferences(ctx, reader.SessionToken, posts.FeedPreferences{BlockedChannelIDs: channels[:1]})
		done <- e
	}()
	<-barrier.captured
	if _, e := l.c.CreateSession(ctx, sessionTestRequest(t, "feed_gate_reader"), sessionTestPasswordWorker(t, 1)); e != nil {
		t.Fatal(e)
	}
	close(barrier.release)
	if e := <-done; !errors.Is(e, ErrSessionReplaced) {
		t.Fatal("stale session wrote preference", e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.feed_preferences`) != 0 {
		t.Fatal("stale write committed")
	}
	if e := l.gate.Freeze(ctx, "feed regression"); e != nil {
		t.Fatal(e)
	}
	for _, kind := range []PostReadKind{PostFeed, PostFeedPreferences, PostViewRecord} {
		q := PostQuery{Kind: kind}
		if kind == PostViewRecord {
			q.ID = uuid.NewString()
		}
		if _, e := l.c.ReadPosts(ctx, reader.SessionToken, q); !errors.Is(e, ErrAuthorizationUnavailable) {
			t.Fatal("frozen Gate served feed", e)
		}
	}
}
