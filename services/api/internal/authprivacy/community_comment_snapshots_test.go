package authprivacy

import (
	"context"
	"encoding/base64"
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/commentsnapshot"
)

func snapshotSQLStore(t *testing.T, l *lab, quota ...int) (*commentsnapshot.Store, commentsnapshot.Config) {
	t.Helper()
	binary := os.Getenv("COMMENT_SNAPSHOT_REDIS_SERVER")
	if binary == "" {
		t.Fatal("real snapshot SQL acceptance requires owned Redis binary")
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	port := listener.Addr().(*net.TCPAddr).Port
	_ = listener.Close()
	dir := t.TempDir()
	cmd := exec.Command(binary, "--bind", "127.0.0.1", "--port", strconv.Itoa(port), "--save", "", "--appendonly", "no", "--maxmemory", "64mb", "--maxmemory-policy", "noeviction", "--dir", dir, "--logfile", filepath.Join(dir, "redis.log"))
	if err = cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	client := redis.NewClient(&redis.Options{Addr: address, MaxRetries: -1})
	defer client.Close()
	ctx := context.Background()
	ready := false
	for i := 0; i < 100; i++ {
		info, e := client.Info(ctx, "server").Result()
		if e == nil {
			if !strings.Contains(info, "process_id:"+strconv.Itoa(cmd.Process.Pid)+"\r\n") {
				t.Fatal("Redis owner mismatch")
			}
			ready = true
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !ready {
		t.Fatal("owned Redis unavailable")
	}
	cfg := commentsnapshot.DefaultConfig()
	cfg.PostgresCursorVersion = 2
	if len(quota) > 0 {
		cfg.MaxPerAccount = quota[0]
	}
	cfg.CreateBackend = "redis"
	cfg.ReadRedis = true
	cfg.Redis.Address = address
	cfg.Redis.Namespace = "hnuhole:comment-snapshot:v2:sqltest:"
	cfg.Redis.Epoch = uuid.NewString()
	store, e := commentsnapshot.New(cfg, "", l.c.comments.codec.IntentFingerprint)
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { _ = store.Close() })
	if e = store.InitializeNew(ctx); e != nil {
		t.Fatal(e)
	}
	l.c.comments.snapshotConfig = &cfg
	l.c.comments.snapshotStore = store
	return store, cfg
}

func TestCommentSnapshotRepliesAndCombinedQuotaPostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "snapshot_reply_owner")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "楼层").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, identity)
	rootTask := uuid.NewString()
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), comments.Intent{Operation: comments.Create, TaskID: rootTask, PostID: post, IdentityID: identity.String(), Body: "root"})
	commentTextPublish(t, l)
	root := *commentTextOwn(t, l, owner.SessionToken, rootTask).PublishedCommentID
	for i := 0; i < 7; i++ {
		commentTextSend(t, l, owner.SessionToken, postTestKey(t), comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: identity.String(), RootCommentID: root, TargetCommentID: root, Body: "reply"})
	}
	commentTextPublish(t, l)
	_ = snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post}) // one live old PG snapshot
	store, cfg := snapshotSQLStore(t, l, 2)
	nonce := postTestKey(t)
	preview := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: root, PostID: post, Replies: true, SnapshotRequest: nonce})
	if len(preview.Comments) != 5 || preview.NextCursor == nil || *preview.RemainingCount != 2 {
		t.Fatal("reply preview protocol")
	}
	repeat := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: root, PostID: post, Replies: true, SnapshotRequest: nonce})
	if preview.SnapshotID != repeat.SnapshotID {
		t.Fatal("nonce reuse charged quota twice")
	}
	rest := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: root, PostID: post, Replies: true, Expanded: true, Cursor: *preview.NextCursor})
	if len(rest.Comments) != 2 || rest.NextCursor != nil || *rest.RemainingCount != 0 {
		t.Fatal("expanded remainder protocol")
	}
	_, e := l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post})
	postTestError(t, e, "RATE_LIMITED", 429)
	var failure *PostError
	if !errors.As(e, &failure) || failure.RetryAfter < 2 {
		t.Fatal("combined PG/Redis wait", e)
	}
	_, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post, Cursor: *preview.NextCursor})
	postTestError(t, e, "CURSOR_INVALID", 400)
	mustExec(t, l.cp, `DELETE FROM c_comments.snapshots`)
	_ = snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post}) // second Redis reservation
	pgcfg := cfg
	pgcfg.CreateBackend = "postgres"
	l.c.comments.snapshotConfig = &pgcfg
	_, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post})
	postTestError(t, e, "RATE_LIMITED", 429)
	if !errors.As(e, &failure) || failure.RetryAfter < 2 {
		t.Fatal("empty PG domain shortened Redis quota wait", e)
	}
	l.c.comments.snapshotConfig = &cfg
	ownerToken := commentsnapshot.OwnerToken(l.c.comments.codec.IntentFingerprint, owner.AccountID, cfg.Redis.Namespace)
	usage, e := store.Usage(ctx, ownerToken)
	if e != nil || usage.AccountCount != 2 {
		t.Fatal("quota reservations", usage, e)
	}
	mustExec(t, l.cp, `UPDATE c_comments.tasks SET moderation_hidden=true WHERE comment_id=$1`, root)
	_, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: root, PostID: post, Replies: true, Expanded: true, Cursor: *preview.NextCursor})
	postTestError(t, e, "COMMENT_NOT_FOUND", 404)
}

func snapshotRead(t *testing.T, l *lab, b [32]byte, q CommentQuery) TextCommentPage {
	t.Helper()
	r, e := l.c.ReadComments(context.Background(), b, q)
	if e != nil {
		t.Fatal(e)
	}
	return r.Value.(TextCommentPage)
}

func TestCommentSnapshotRedisSQLPublicationCompatibilityAndRecovery(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "snapshot_owner")
	other := sessionTestAccount(t, l, "snapshot_other")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "快照测试").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, identity)
	for i := 0; i < 6; i++ {
		commentTextSend(t, l, owner.SessionToken, postTestKey(t), comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: identity.String(), Body: "frozen membership"})
	}
	commentTextPublish(t, l)
	old := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Limit: 1})
	if old.NextCursor == nil {
		t.Fatal("V1 fixture cursor absent")
	}
	store, cfg := snapshotSQLStore(t, l)
	page := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Cursor: *old.NextCursor, Limit: 50})
	if len(page.Comments) != 5 {
		t.Fatal("legacy PostgreSQL cursor compatibility")
	}
	nonce := postTestKey(t)
	first := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Sort: comments.Recent, Limit: 1, SnapshotRequest: nonce})
	ref, offset, e := commentsnapshot.DecodeCursor(l.c.comments.codec.IntentFingerprint, *first.NextCursor)
	if e != nil || offset != 1 || ref.Backend != commentsnapshot.Redis || ref.Sort != comments.Recent || ref.Expires.Sub(first.Comments[0].PublishedAt) > 31*time.Minute {
		t.Fatal("V2 cursor", e)
	}
	again := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Sort: comments.Recent, Limit: 1, SnapshotRequest: nonce})
	if again.SnapshotID != first.SnapshotID || *again.NextCursor != *first.NextCursor {
		t.Fatal("retry changed snapshot or expiry")
	}
	_, e = l.c.ReadComments(ctx, other.SessionToken, CommentQuery{ID: post, Cursor: *first.NextCursor})
	postTestError(t, e, "CURSOR_INVALID", 400)
	otherPost := commentTextPost(t, l, owner.SessionToken, identity)
	_, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: otherPost, Cursor: *first.NextCursor})
	postTestError(t, e, "CURSOR_INVALID", 400)
	_, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post, Sort: comments.MostLiked, SnapshotRequest: nonce})
	postTestError(t, e, "MALFORMED_REQUEST", 400)
	_, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post, SnapshotRequest: base64.RawURLEncoding.EncodeToString(make([]byte, 16))})
	postTestError(t, e, "MALFORMED_REQUEST", 400)
	// A separately constructed store/service instance continues the same frozen list.
	second, e := commentsnapshot.New(cfg, "", l.c.comments.codec.IntentFingerprint)
	if e != nil {
		t.Fatal(e)
	}
	defer second.Close()
	l.c.comments.snapshotStore = second
	rest := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Cursor: *first.NextCursor, Limit: 50})
	if len(rest.Comments) != 5 {
		t.Fatal("cross-instance read")
	}
	for _, item := range rest.Comments[:3] {
		mustExec(t, l.cp, `UPDATE c_comments.tasks SET moderation_hidden=true WHERE comment_id=$1`, item.ID)
	}
	empty := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Cursor: *first.NextCursor, Limit: 1})
	if len(empty.Comments) != 0 || empty.NextCursor == nil {
		t.Fatal("three empty segments must remain resumable")
	}
	_, scanned, e := commentsnapshot.DecodeCursor(l.c.comments.codec.IntentFingerprint, *empty.NextCursor)
	if e != nil || scanned != 4 {
		t.Fatal("cursor must advance by original scanned positions")
	}
	remaining := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Cursor: *empty.NextCursor, Limit: 50})
	if len(remaining.Comments) != 2 || remaining.NextCursor != nil {
		t.Fatal("remaining frozen membership")
	}
	location, e := l.c.LocateComment(ctx, owner.SessionToken, post, remaining.Comments[0].ID)
	if e != nil || location.Value.(CommentLocation).Cursor == nil {
		t.Fatal("Redis locate", e)
	}
	// Explicit PostgreSQL creation continues both V1 and V2 compatibility reads.
	pgcfg := cfg
	pgcfg.CreateBackend = "postgres"
	// The dual reader emits V1 by default during a mixed old/new fleet.
	pgcfg.PostgresCursorVersion = 0
	l.c.comments.snapshotConfig = &pgcfg
	bridge := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Limit: 1})
	if bridge.NextCursor == nil {
		t.Fatal("bridge cursor absent")
	}
	encoded, decodeErr := base64.RawURLEncoding.Strict().DecodeString(*bridge.NextCursor)
	if decodeErr != nil || len(encoded) != 52 {
		t.Fatal("bridge did not emit legacy wire format", decodeErr)
	}
	// Use the original V1-only service route, then continue through the new route.
	l.c.comments.snapshotConfig = nil
	bridgeOld := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Cursor: *bridge.NextCursor, Limit: 1})
	if bridgeOld.NextCursor == nil || bridgeOld.SnapshotID != bridge.SnapshotID {
		t.Fatal("old route cannot continue bridge")
	}
	l.c.comments.snapshotConfig = &pgcfg
	_ = snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Cursor: *bridgeOld.NextCursor, Limit: 1})
	bridgeNew := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Cursor: *bridge.NextCursor, Limit: 1})
	if bridgeNew.NextCursor == nil {
		t.Fatal("bridge continuation absent")
	}
	encoded, decodeErr = base64.RawURLEncoding.Strict().DecodeString(*bridgeNew.NextCursor)
	if decodeErr != nil || len(encoded) != 52 {
		t.Fatal("V1 continuation upgraded unexpectedly", decodeErr)
	}
	pgcfg.PostgresCursorVersion = 2
	l.c.comments.snapshotConfig = &pgcfg
	pg := snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Limit: 1})
	pgr, _, e := commentsnapshot.DecodeCursor(l.c.comments.codec.IntentFingerprint, *pg.NextCursor)
	if e != nil || pgr.Backend != commentsnapshot.Postgres {
		t.Fatal("PG V2 route", e)
	}
	_ = snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Cursor: *pg.NextCursor})
	_ = snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Cursor: *first.NextCursor})
	// With PostgreSQL reads disabled, renamed old table cannot affect list/locate.
	cfg.ReadPostgres = false
	l.c.comments.snapshotConfig = &cfg
	mustExec(t, l.cp, `ALTER TABLE c_comments.snapshots RENAME TO snapshots_offline`)
	_ = snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Limit: 1})
	_, e = l.c.LocateComment(ctx, owner.SessionToken, post, remaining.Comments[0].ID)
	if e != nil {
		t.Fatal("old table accessed by locate", e)
	}
	_, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post, Cursor: *pg.NextCursor})
	postTestError(t, e, "CURSOR_INVALID", 400)
	mustExec(t, l.cp, `ALTER TABLE c_comments.snapshots_offline RENAME TO snapshots`)
	// Exercise the new path using actual least-privileged runtime SQL grants.
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	for _, path := range []string{"../../../../infra/postgres/grant-community.sql", "../../../../infra/postgres/grant-comments.sql"} {
		data, e := os.ReadFile(path)
		if e != nil {
			t.Fatal(e)
		}
		mustExec(t, l.cp, string(data))
	}
	pool, e := pgxpool.New(ctx, os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	originalPool := l.c.pool
	l.c.pool = pool
	_ = snapshotRead(t, l, owner.SessionToken, CommentQuery{ID: post, Limit: 1})
	l.c.pool = originalPool
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, post)
	_, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post, Cursor: *first.NextCursor})
	postTestError(t, e, "POST_NOT_FOUND", 404)
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=false WHERE post_id=$1`, post)
	// A deferred COMMIT failure occurs after Redis preparation. Existing Gate
	// intentionally freezes after this ambiguous SQL failure, so run it last.
	before, e := store.Usage(ctx, [32]byte{})
	if e != nil {
		t.Fatal(e)
	}
	mustExec(t, l.cp, `CREATE FUNCTION public.snapshot_fail_commit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected snapshot commit failure'; END $$; CREATE CONSTRAINT TRIGGER snapshot_fail_commit AFTER UPDATE ON c_auth.sessions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.snapshot_fail_commit()`)
	failed, e := l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post})
	mustExec(t, l.cp, `DROP TRIGGER snapshot_fail_commit ON c_auth.sessions; DROP FUNCTION public.snapshot_fail_commit()`)
	if e == nil || failed.Value != nil {
		t.Fatal("failed SQL transaction exposed snapshot")
	}
	after, e := store.Usage(ctx, [32]byte{})
	if e != nil || before.ReservedBytes != after.ReservedBytes {
		t.Fatal("SQL failure leaked reservation", before, after, e)
	}
	_, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post})
	if e == nil {
		t.Fatal("SQL failure bypassed existing Gate freeze")
	}
}
