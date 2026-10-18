package authprivacy

import (
	"context"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
)

func commentTextLab(t *testing.T) *lab {
	t.Helper()
	l := newPostLab(t)
	var e error
	cfg := CommentConfig{}
	cfg.KeyKey, _ = random32()
	cfg.FingerprintKey, _ = random32()
	l.c, e = l.c.WithComments(context.Background(), cfg)
	if e != nil {
		t.Fatal(e)
	}
	return l
}
func commentTextSend(t *testing.T, l *lab, b [32]byte, key string, in comments.Intent) CommentReceipt {
	t.Helper()
	r, e := l.c.ExecuteCommentCommand(context.Background(), b, key, in)
	if e != nil {
		t.Fatal(e)
	}
	return r.Value.(CommentReceipt)
}
func commentTextOwn(t *testing.T, l *lab, b [32]byte, id string) OwnCommentTask {
	t.Helper()
	r, e := l.c.GetOwnCommentTask(context.Background(), b, id)
	if e != nil {
		t.Fatal(e)
	}
	return r.Value.(OwnCommentTask)
}
func commentTextPublish(t *testing.T, l *lab) {
	t.Helper()
	if _, e := l.c.PublishAcceptedComments(context.Background(), 100); e != nil {
		t.Fatal(e)
	}
}
func commentTextPost(t *testing.T, l *lab, b [32]byte, i uuid.UUID) string {
	t.Helper()
	r := postTestCommand(t, l, b, postTestKey(t), postTestIntent(t, l, i))
	postTestPublish(t, l)
	return r.PostID
}

func TestCommentTextTransactionsPostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	author := sessionTestAccount(t, l, "ct_author")
	authorID := identityChange(t, l.c, author.SessionToken, "CREATE", uuid.Nil, "楼主").IdentityID
	reader := sessionTestAccount(t, l, "ct_reader")
	readerID := identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "参与者").IdentityID
	otherID := identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "另一个身份").IdentityID
	post := commentTextPost(t, l, author.SessionToken, authorID)
	in := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: readerID.String(), Body: "原文\r\n e\u0301"}
	key := postTestKey(t)
	var wg sync.WaitGroup
	errs := make(chan error, 8)
	for n := 0; n < 8; n++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r, e := l.c.ExecuteCommentCommand(ctx, reader.SessionToken, key, in)
			if e == nil && r.Value.(CommentReceipt).TaskID != in.TaskID {
				e = errors.New("changed receipt")
			}
			errs <- e
		}()
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		if e != nil {
			t.Fatal(e)
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_comments.attempts WHERE task_id=$1`, in.TaskID) != 1 {
		t.Fatal("duplicate acceptance")
	}
	changed := in
	changed.Body = "不同内容"
	_, e := l.c.ExecuteCommentCommand(ctx, reader.SessionToken, key, changed)
	postTestError(t, e, "COMMAND_CONFLICT", 409)
	// Other accounts cannot observe receipts or private tasks, or borrow identities.
	r, e := l.c.GetCommentCommand(ctx, author.SessionToken, key)
	if e != nil || r.Value.(CommentReceipt).State != "UNKNOWN_NOT_OBSERVED" {
		t.Fatal("cross-account receipt")
	}
	_, e = l.c.GetOwnCommentTask(ctx, author.SessionToken, in.TaskID)
	postTestError(t, e, "TASK_NOT_FOUND", 404)
	foreign := in
	foreign.TaskID = uuid.NewString()
	foreign.IdentityID = authorID.String()
	if r := commentTextSend(t, l, reader.SessionToken, postTestKey(t), foreign); r.ErrorCode != "IDENTITY_UNAVAILABLE" {
		t.Fatal(r)
	}
	rebound := in
	rebound.TaskID = uuid.NewString()
	rebound.IdentityID = otherID.String()
	if r := commentTextSend(t, l, reader.SessionToken, postTestKey(t), rebound); r.ErrorCode != "IDENTITY_UNAVAILABLE" {
		t.Fatal(r)
	}
	commentTextPublish(t, l)
	main := commentTextOwn(t, l, reader.SessionToken, in.TaskID)
	if main.State != comments.Published || main.Content != nil || main.PublishedCommentID == nil {
		t.Fatal(main)
	}
	original, e := l.c.GetCommentCommand(ctx, reader.SessionToken, key)
	if e != nil || original.Value.(CommentReceipt).State != "ACCEPTED" {
		t.Fatal("receipt changed after publication")
	}
	reply := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: authorID.String(), RootCommentID: *main.PublishedCommentID, TargetCommentID: *main.PublishedCommentID, Body: "明确回复"}
	commentTextSend(t, l, author.SessionToken, postTestKey(t), reply)
	commentTextPublish(t, l)
	child := commentTextOwn(t, l, author.SessionToken, reply.TaskID)
	reply.TaskID = uuid.NewString()
	reply.TargetCommentID = *child.PublishedCommentID
	commentTextSend(t, l, author.SessionToken, postTestKey(t), reply)
	commentTextPublish(t, l)
	page, e := l.c.ReadComments(ctx, reader.SessionToken, CommentQuery{ID: post})
	if e != nil {
		t.Fatal(e)
	}
	m := page.Value.(TextCommentPage)
	if len(m.Comments) != 1 || *m.TotalCount != 3 || m.Comments[0].Body != in.Body || m.Comments[0].ReplyCount != 2 || m.Comments[0].IsPostAuthor {
		t.Fatal("main projection")
	}
	replies, e := l.c.ReadComments(ctx, reader.SessionToken, CommentQuery{ID: *main.PublishedCommentID, Replies: true})
	if e != nil {
		t.Fatal(e)
	}
	rp := replies.Value.(TextCommentPage)
	if len(rp.Comments) != 2 || !rp.Comments[0].IsPostAuthor || rp.Comments[1].ReplyTo.CommentID != *child.PublishedCommentID {
		t.Fatal("reply projection")
	}
	otherPost := commentTextPost(t, l, author.SessionToken, authorID)
	reply.TaskID = uuid.NewString()
	reply.PostID = otherPost
	if r := commentTextSend(t, l, author.SessionToken, postTestKey(t), reply); r.ErrorCode != "TARGET_UNAVAILABLE" {
		t.Fatal(r)
	}
	// Unknown -> serialized seal -> delayed original has no task/binding/effect.
	sealed := in
	sealed.TaskID = uuid.NewString()
	sealKey := postTestKey(t)
	digest, _ := comments.RequestDigest(sealed)
	result, e := l.c.SealCommentCommand(ctx, reader.SessionToken, sealKey, comments.Create, digest)
	if e != nil || result.Value.(CommentReceipt).State != "NOT_ACCEPTED" {
		t.Fatal(e)
	}
	if r := commentTextSend(t, l, reader.SessionToken, sealKey, sealed); r.State != "NOT_ACCEPTED" {
		t.Fatal(r)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_comments.tasks WHERE task_id=$1`, sealed.TaskID) != 0 {
		t.Fatal("sealed task exists")
	}
	// Pagination freezes membership and is scoped to reader + post. Newly
	// published content appears only on a fresh read snapshot.
	extra := in
	extra.TaskID = uuid.NewString()
	commentTextSend(t, l, reader.SessionToken, postTestKey(t), extra)
	commentTextPublish(t, l)
	initial, e := l.c.ReadComments(ctx, reader.SessionToken, CommentQuery{ID: post, Limit: 1})
	if e != nil {
		t.Fatal(e)
	}
	snapshot := initial.Value.(TextCommentPage)
	if snapshot.NextCursor == nil {
		t.Fatal("missing next cursor")
	}
	extra.TaskID = uuid.NewString()
	commentTextSend(t, l, reader.SessionToken, postTestKey(t), extra)
	commentTextPublish(t, l)
	next, e := l.c.ReadComments(ctx, reader.SessionToken, CommentQuery{ID: post, Limit: 50, Cursor: *snapshot.NextCursor})
	if e != nil || len(next.Value.(TextCommentPage).Comments) != 1 || next.Value.(TextCommentPage).NextCursor != nil {
		t.Fatal("snapshot changed membership", e)
	}
	_, e = l.c.ReadComments(ctx, author.SessionToken, CommentQuery{ID: post, Cursor: *snapshot.NextCursor})
	postTestError(t, e, "CURSOR_INVALID", 400)
	_, e = l.c.ReadComments(ctx, reader.SessionToken, CommentQuery{ID: otherPost, Cursor: *snapshot.NextCursor})
	postTestError(t, e, "CURSOR_INVALID", 400)
}

func TestCommentTextFailureRetryAbandonPostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "ct_failure")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "发言身份").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, identity)
	in := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: identity.String(), Body: "待发送"}
	key := postTestKey(t)
	commentTextSend(t, l, owner.SessionToken, key, in)
	end := time.Now().Add(250 * time.Millisecond)
	if e := l.c.ApplyAccountMute(ctx, owner.AccountID, 1, &end); e != nil {
		t.Fatal(e)
	}
	failed := commentTextOwn(t, l, owner.SessionToken, in.TaskID)
	if failed.State != comments.Failed || *failed.FailureCode != "PUBLISHING_STOPPED" {
		t.Fatal(failed)
	}
	// Expiry permits a new explicit attempt; it never revives the stopped one.
	time.Sleep(time.Until(end) + 100*time.Millisecond)
	retry := comments.Intent{Operation: comments.Retry, TaskID: in.TaskID, ExpectedAttemptVersion: 1, Body: "重试原身份"}
	retryKey := postTestKey(t)
	if r := commentTextSend(t, l, owner.SessionToken, retryKey, retry); r.AttemptVersion != 2 {
		t.Fatal(r)
	}
	if r := commentTextSend(t, l, owner.SessionToken, retryKey, retry); r.AttemptVersion != 2 {
		t.Fatal("retry duplicate")
	}
	if r := commentTextSend(t, l, owner.SessionToken, postTestKey(t), retry); r.ErrorCode != "STALE_ATTEMPT" {
		t.Fatal(r)
	}
	commentTextPublish(t, l)
	if task := commentTextOwn(t, l, owner.SessionToken, in.TaskID); task.State != comments.Published || task.OwnerIdentityID != identity.String() {
		t.Fatal(task)
	}
	in.TaskID = uuid.NewString()
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), in)
	// A real SQL stop event produces a confirmed failure before abandonment.
	if e := l.c.ApplyAccountMute(ctx, owner.AccountID, 2, nil); e != nil {
		t.Fatal(e)
	}
	abandon := comments.Intent{Operation: comments.Abandon, TaskID: in.TaskID, ExpectedAttemptVersion: 1}
	if r := commentTextSend(t, l, owner.SessionToken, postTestKey(t), abandon); r.State != "APPLIED" {
		t.Fatal(r)
	}
	if task := commentTextOwn(t, l, owner.SessionToken, in.TaskID); task.State != comments.Abandoned || task.Content != nil || len(task.AllowedActions) != 0 {
		t.Fatal(task)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_comments.attempts WHERE task_id=$1 AND body IS NOT NULL`, in.TaskID) != 0 {
		t.Fatal("abandoned payload retained")
	}
}

func TestCommentTextFrozenGatePostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "ct_gate")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Gate身份").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, id)
	in := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: id.String(), Body: "等待核对"}
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), in)
	if e := l.gate.Freeze(ctx, "synthetic component outage"); e != nil {
		t.Fatal(e)
	}
	if _, e := l.c.PublishAcceptedComments(ctx, 100); !errors.Is(e, ErrAuthorizationUnavailable) {
		t.Fatal("frozen publication")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_comments.attempts WHERE task_id=$1 AND state='ACCEPTED'`, in.TaskID) != 1 {
		t.Fatal("freeze changed state")
	}
}

func TestCommentTextRuntimeAndSQLGuardsPostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "ct_runtime")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "运行身份").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, id)
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	for _, path := range []string{"../../../../infra/postgres/grant-community.sql", "../../../../infra/postgres/grant-comments.sql"} {
		sql, e := os.ReadFile(path)
		if e != nil {
			t.Fatal(e)
		}
		mustExec(t, l.cp, string(sql))
	}
	cfg, e := pgxpool.ParseConfig(os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
	if e != nil || cfg.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
		t.Fatal("isolated runtime DSN required")
	}
	pool, e := pgxpool.NewWithConfig(ctx, cfg)
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	clone := *l.c
	clone.pool = pool
	l.c = &clone
	if e = l.c.CheckCommentSchema(ctx); e != nil {
		t.Fatal(e)
	}
	in := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: id.String(), Body: "真实受限连接"}
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), in)
	commentTextPublish(t, l)
	if _, e = l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post}); e != nil {
		t.Fatal(e)
	}
	for _, sql := range []string{`DELETE FROM c_comments.receipts`, `UPDATE c_comments.tasks SET identity_id=gen_random_uuid()`, `UPDATE c_comments.attempts SET accepted_stop_generation=999`, `TRUNCATE c_comments.attempts`, `CREATE TABLE c_comments.forbidden(id int)`} {
		_, e = pool.Exec(ctx, sql)
		var pg *pgconn.PgError
		if !errors.As(e, &pg) || pg.Code != "42501" {
			t.Fatalf("runtime privilege: %v", e)
		}
	}
	for _, sql := range []string{`UPDATE c_comments.receipts SET outcome='REJECTED'`, `UPDATE c_comments.attempts SET state='ACCEPTED',terminal_at=NULL WHERE task_id=$1`, `UPDATE c_comments.tasks SET post_id=gen_random_uuid() WHERE task_id=$1`} {
		tx, e := l.cp.Begin(ctx)
		if e != nil {
			t.Fatal(e)
		}
		if sql == `UPDATE c_comments.receipts SET outcome='REJECTED'` {
			_, e = tx.Exec(ctx, sql)
		} else {
			_, e = tx.Exec(ctx, sql, in.TaskID)
		}
		_ = tx.Rollback(ctx)
		var pg *pgconn.PgError
		if !errors.As(e, &pg) || pg.Code != "23514" {
			t.Fatalf("SQL invariant: %v", e)
		}
	}
	// Identity lifecycle still works with restricted invoker triggers, hides owner
	// recovery and preserves already published public content with a safe author.
	identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "保留身份")
	pending := in
	pending.TaskID = uuid.NewString()
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), pending)
	identityChange(t, l.c, owner.SessionToken, "DELETE", id, "")
	_, e = l.c.GetOwnCommentTask(ctx, owner.SessionToken, in.TaskID)
	postTestError(t, e, "TASK_NOT_FOUND", 404)
	if count(t, l.cp, `SELECT count(*) FROM c_comments.attempts WHERE task_id=$1 AND state='FAILED' AND failure_code='IDENTITY_INACTIVE' AND body IS NULL`, pending.TaskID) != 1 {
		t.Fatal("deleted identity retained live recovery")
	}
	page, e := l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post})
	if e != nil || page.Value.(TextCommentPage).Comments[0].Author.State != "IDENTITY_DELETED" {
		t.Fatal(e)
	}
}

func TestCommentTextUnavailablePostPostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "ct_hidden")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "原身份").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, id)
	in := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: id.String(), Body: "下架前已受理"}
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), in)
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, post)
	commentTextPublish(t, l)
	task := commentTextOwn(t, l, owner.SessionToken, in.TaskID)
	if task.State != comments.Failed || *task.FailureCode != "POST_UNAVAILABLE" {
		t.Fatal(task)
	}
	_, e := l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post})
	postTestError(t, e, "POST_NOT_FOUND", 404)
	retry := comments.Intent{Operation: comments.Retry, TaskID: in.TaskID, ExpectedAttemptVersion: 1, Body: "不能自动改目标"}
	if r := commentTextSend(t, l, owner.SessionToken, postTestKey(t), retry); r.ErrorCode != "TASK_NOT_FAILED" {
		t.Fatal(r)
	}
	in.TaskID = uuid.NewString()
	if r := commentTextSend(t, l, owner.SessionToken, postTestKey(t), in); r.ErrorCode != "TARGET_UNAVAILABLE" {
		t.Fatal(r)
	}
}

func TestCommentTextClosureCleanupWithFeatureDisabledPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	postConfig := enablePostLab(t, l)
	cfg := CommentConfig{}
	cfg.KeyKey, _ = random32()
	cfg.FingerprintKey, _ = random32()
	var e error
	l.c, e = l.c.WithComments(ctx, cfg)
	if e != nil {
		t.Fatal(e)
	}
	owner := sessionTestAccount(t, l, "ct_close")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "关闭账号").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, id)
	in := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: id.String(), Body: "待处理文字"}
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), in)
	runtime := moderationLifecycleRuntime(t, l)
	clone := *l.c
	clone.pool = runtime
	clone.comments = nil
	off, e := clone.WithPosts(ctx, postConfig)
	if e != nil {
		t.Fatal(e)
	}
	// Legacy post acceptance must not need private comment receipt privileges.
	if _, e = off.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id)); e != nil {
		t.Fatal("legacy post acceptance required comment feature grants", e)
	}
	request, _ := closureTestRequest(t, owner.SessionToken)
	accepted, e := off.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_comments.attempts WHERE task_id=$1 AND state='FAILED' AND failure_code='PUBLISHING_STOPPED'`, in.TaskID) != 1 {
		t.Fatal("closure request did not stop pending comment")
	}
	advanceClosureClock(t, control, accepted.DueAt)
	if n, e := off.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
		t.Fatal("restricted legacy close failed", e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_comments.tasks t JOIN c_comments.attempts a USING(task_id) WHERE t.owner_account_id=$1 AND (t.owner_visible OR a.body IS NOT NULL)`, owner.AccountID) != 0 {
		t.Fatal("closed account retained private comment material")
	}
}
