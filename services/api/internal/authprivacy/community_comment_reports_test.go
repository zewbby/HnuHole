package authprivacy

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func commentReportLab(t *testing.T) *lab {
	t.Helper()
	l := commentTextLab(t)
	var e error
	l.c, e = l.c.WithModeration(context.Background())
	if e != nil {
		t.Fatal(e)
	}
	return l
}
func commentReportCreate(t *testing.T, l *lab, owner SessionCreateResult, identity uuid.UUID, post, root, body string) string {
	t.Helper()
	in := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: identity.String(), RootCommentID: root, TargetCommentID: root, Body: body}
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), in)
	commentTextPublish(t, l)
	return *commentTextOwn(t, l, owner.SessionToken, in.TaskID).PublishedCommentID
}
func commentReportSubmit(t *testing.T, l *lab, reporter SessionCreateResult, post, comment string, identity *string) (string, moderation.Report) {
	t.Helper()
	key := uuid.NewString()
	v, e := l.c.SubmitReport(context.Background(), reporter.SessionToken, key, moderation.ReportInput{PostID: post, CommentID: &comment, IdentityID: identity, Reason: "OTHER", Images: []moderation.Image{}})
	if e != nil {
		t.Fatal(e)
	}
	return key, *v.Value.(moderation.ReportResult).Report
}
func commentReportRevoke(t *testing.T, l *lab, actor SessionCreateResult, id string) {
	t.Helper()
	if _, e := l.c.ExecuteModeration(context.Background(), actor.SessionToken, "revoke", id, moderation.Decision{CommandID: uuid.NewString(), Reason: "独立纠正"}); e != nil {
		t.Fatal(e)
	}
}

func TestCommentReportTargetPrivacyReceiptsAndConcurrentDecisionPostgres(t *testing.T) {
	l := commentReportLab(t)
	ctx := context.Background()
	p := moderationPost(t, l, "cr_parent")
	owner := moderationActor(t, l, "cr_comment_owner", "")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "评论身份").IdentityID
	otherMask := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "私有其他面具").IdentityID
	reporter := moderationActor(t, l, "cr_reporter", "")
	reportMask := identityChange(t, l.c, reporter.SessionToken, "CREATE", uuid.Nil, "举报面具").IdentityID.String()
	anotherMask := identityChange(t, l.c, reporter.SessionToken, "CREATE", uuid.Nil, "另一举报面具").IdentityID.String()
	reviewer := moderationActor(t, l, "cr_reviewer", "REVIEWER")
	second := moderationActor(t, l, "cr_second", "REVIEWER")
	root := commentReportCreate(t, l, owner, identity, p.post.String(), "", "相同原文")
	reply := commentReportCreate(t, l, owner, identity, p.post.String(), root, "相同原文")
	key, r := commentReportSubmit(t, l, reporter, p.post.String(), root, &reportMask)
	_, r2 := commentReportSubmit(t, l, reporter, p.post.String(), reply, nil)
	if r.CaseID == r2.CaseID || r.CommentID == nil || *r.CommentID != root {
		t.Fatal("distinct comment facts collapsed")
	}
	in := moderation.ReportInput{PostID: p.post.String(), CommentID: &root, IdentityID: &reportMask, Reason: "PRIVACY", Images: []moderation.Image{}}
	dup, e := l.c.SubmitReport(ctx, reporter.SessionToken, uuid.NewString(), in)
	if e != nil || dup.Value.(moderation.ReportResult).Report.CaseID != r.CaseID {
		t.Fatal("same snapshot split by allegation", e)
	}
	in.Reason = "OTHER"
	if _, e = l.c.SubmitReport(ctx, reporter.SessionToken, key, in); e != nil {
		t.Fatal("exact replay", e)
	}
	in.CommentID = &reply
	_, e = l.c.SubmitReport(ctx, reporter.SessionToken, key, in)
	postTestError(t, e, "REQUEST_CONFLICT", 409)
	otherPost := moderationPost(t, l, "cr_other_parent")
	in.PostID = otherPost.post.String()
	_, e = l.c.SubmitReport(ctx, reporter.SessionToken, uuid.NewString(), in)
	postTestError(t, e, "COMMENT_NOT_FOUND", 404)
	v, e := l.c.GetReport(ctx, owner.SessionToken, key)
	if e != nil || v.Value.(moderation.ReportResult).State != "NOT_SUBMITTED" {
		t.Fatal("foreign report receipt exposed", e)
	}
	_, e = l.c.ReadModeration(ctx, reporter.SessionToken, "case", r.CaseID, "", "", 50)
	postTestError(t, e, "MODERATION_FORBIDDEN", 403)
	v, e = l.c.ReadModeration(ctx, reviewer.SessionToken, "case", r.CaseID, "", "", 50)
	if e != nil {
		t.Fatal(e)
	}
	b, _ := json.Marshal(v.Value)
	for _, secret := range []string{owner.AccountID.String(), p.account.String(), reporter.AccountID.String(), identity.String(), otherMask.String(), reportMask, anotherMask, "email", "reporterAccountId", "username"} {
		if strings.Contains(string(b), secret) {
			t.Fatal("management privacy leak", secret)
		}
	}
	// The actor is a reviewer, never an administrator. No role mutation through a comment case.
	_, e = l.c.ExecuteModeration(ctx, reviewer.SessionToken, "role", "000001", moderation.Decision{CommandID: uuid.NewString(), Role: "ADMIN", Reason: "不得提权"})
	postTestError(t, e, "MODERATION_FORBIDDEN", 403)
	var wg sync.WaitGroup
	outcomes := make(chan error, 2)
	for _, actor := range []SessionCreateResult{reviewer, second} {
		wg.Add(1)
		go func(a SessionCreateResult) {
			defer wg.Done()
			_, e := l.c.ExecuteModeration(ctx, a.SessionToken, "decision", r.CaseID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Action: "TAKEDOWN", Reason: "并发处理"})
			outcomes <- e
		}(actor)
	}
	wg.Wait()
	close(outcomes)
	wins := 0
	for e := range outcomes {
		if e == nil {
			wins++
		} else {
			postTestError(t, e, "CASE_ALREADY_HANDLED", 409)
		}
	}
	if wins != 1 || count(t, l.cp, `SELECT count(*) FROM c_moderation.sanctions WHERE case_id=$1 AND account_id=$2`, r.CaseID, owner.AccountID) != 1 {
		t.Fatal("wrong target or concurrent duplicate sanction")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE post_id=$1 AND NOT moderation_hidden`, p.post) != 1 {
		t.Fatal("comment action hid parent")
	}
	if _, e = l.c.ReadPosts(ctx, reporter.SessionToken, PostQuery{Kind: PostDetail, ID: p.post.String()}); e != nil {
		t.Fatal("parent became unreadable", e)
	}
	// Identity-scoped notices stay out of account and other-mask inboxes; details and reads enforce that same scope.
	var notice string
	if e = l.cp.QueryRow(ctx, `SELECT notification_id FROM c_moderation.notifications WHERE resource_id=$1 AND state='ENDED'`, key).Scan(&notice); e != nil {
		t.Fatal(e)
	}
	for _, mask := range []string{"", anotherMask} {
		_, e = l.c.ReadSystemNotifications(ctx, reporter.SessionToken, notice, mask, "", 50, true)
		postTestError(t, e, "NOTIFICATION_NOT_FOUND", 404)
	}
	_, e = l.c.ReadSystemNotifications(ctx, owner.SessionToken, notice, reportMask, "", 50, true)
	if e == nil {
		t.Fatal("foreign reporter notice readable")
	}
	if _, e = l.c.ReadSystemNotifications(ctx, reporter.SessionToken, notice, reportMask, "", 50, true); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.notifications WHERE notification_id=$1 AND read_at IS NOT NULL`, notice) != 1 {
		t.Fatal("read receipt missing")
	}
}

func TestCommentReportOldCursorAndIndependentRestorationPostgres(t *testing.T) {
	l := commentReportLab(t)
	ctx := context.Background()
	p := moderationPost(t, l, "cr_cursor_parent")
	owner := moderationActor(t, l, "cr_cursor_owner", "")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "评论者").IdentityID
	reporter := moderationActor(t, l, "cr_cursor_reporter", "")
	reviewer := moderationActor(t, l, "cr_cursor_reviewer", "REVIEWER")
	other := moderationActor(t, l, "cr_cursor_other", "REVIEWER")
	commentReportCreate(t, l, owner, id, p.post.String(), "", "第一条")
	commentReportCreate(t, l, owner, id, p.post.String(), "", "第二条")
	first, e := l.c.ReadComments(ctx, reporter.SessionToken, CommentQuery{ID: p.post.String(), Limit: 1})
	if e != nil {
		t.Fatal(e)
	}
	page := first.Value.(TextCommentPage)
	if page.NextCursor == nil {
		t.Fatal("real cursor absent")
	}
	next, e := l.c.ReadComments(ctx, reporter.SessionToken, CommentQuery{ID: p.post.String(), Cursor: *page.NextCursor, Limit: 1})
	if e != nil {
		t.Fatal(e)
	}
	target := next.Value.(TextCommentPage).Comments[0].ID
	foreignMask := id.String()
	_, e = l.c.SubmitReport(ctx, reporter.SessionToken, uuid.NewString(), moderation.ReportInput{PostID: p.post.String(), CommentID: &target, IdentityID: &foreignMask, Reason: "OTHER", Images: []moderation.Image{}})
	postTestError(t, e, "IDENTITY_UNAVAILABLE", 404)
	_, cr := commentReportSubmit(t, l, reporter, p.post.String(), target, nil)
	cs := moderationDecision(t, l, reviewer, cr.CaseID, "TAKEDOWN", 0).Sanctions[0]
	old, e := l.c.ReadComments(ctx, reporter.SessionToken, CommentQuery{ID: p.post.String(), Cursor: *page.NextCursor, Limit: 1})
	if e != nil || len(old.Value.(TextCommentPage).Comments) != 0 || *old.Value.(TextCommentPage).TotalCount != 1 {
		t.Fatal("old cursor leaked downed content", e)
	}
	own, e := l.c.ReadOwnComments(ctx, owner.SessionToken, id.String(), "")
	if e != nil {
		t.Fatal(e)
	}
	encoded, _ := json.Marshal(own.Value)
	if strings.Contains(string(encoded), target) {
		t.Fatal("own history bypassed moderation")
	}
	_, pr := moderationReport(t, l, reporter, nil, p.post, "OTHER")
	ps := moderationDecision(t, l, reviewer, pr.CaseID, "TAKEDOWN", 0).Sanctions[0]
	commentReportRevoke(t, l, other, cs.ID)
	if _, e = l.c.ReadOneComment(ctx, reporter.SessionToken, p.post.String(), target); e == nil {
		t.Fatal("comment appeal bypassed parent action")
	}
	commentReportRevoke(t, l, other, ps.ID)
	if _, e = l.c.ReadOneComment(ctx, reporter.SessionToken, p.post.String(), target); e != nil {
		t.Fatal("independent restrictions did not restore", e)
	}
}

func TestCommentReportSingleImageAppealVisibilityAndDeletionPostgres(t *testing.T) {
	l := commentReportLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	p := moderationPost(t, l, "cr_image_parent")
	owner := moderationActor(t, l, "cr_image_owner", "")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "图片评论").IdentityID
	reporter := moderationActor(t, l, "cr_image_reporter", "")
	reviewer := moderationActor(t, l, "cr_image_reviewer", "REVIEWER")
	other := moderationActor(t, l, "cr_image_other", "REVIEWER")
	root := commentReportCreate(t, l, owner, id, p.post.String(), "", "楼层原文")
	sel, data := imageFixture(t, "gif")
	in := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: p.post.String(), IdentityID: id.String(), RootCommentID: root, TargetCommentID: root, Body: "单图回复原文", Image: &sel}
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), in)
	if _, e := l.c.UploadCommentImage(ctx, owner.SessionToken, in.TaskID, 1, data, sel.MIME); e != nil {
		t.Fatal(e)
	}
	commentTextPublish(t, l)
	reply := *commentTextOwn(t, l, owner.SessionToken, in.TaskID).PublishedCommentID
	sibling := commentReportCreate(t, l, owner, id, p.post.String(), root, "同层另一个回复")
	_, r := commentReportSubmit(t, l, reporter, p.post.String(), reply, nil)
	v, e := l.c.ReadModeration(ctx, reviewer.SessionToken, "case", r.CaseID, "", "", 50)
	if e != nil {
		t.Fatal(e)
	}
	evidence := v.Value.(moderation.Case).Evidence
	if evidence.Title != "回复" || evidence.Body != in.Body || len(evidence.Images) != 1 || evidence.Images[0].Base64 != base64.StdEncoding.EncodeToString(data) {
		t.Fatal("real image snapshot lost")
	}
	row, e := l.c.ReadOneComment(ctx, reporter.SessionToken, p.post.String(), reply)
	if e != nil {
		t.Fatal(e)
	}
	image := row.Value.(TextComment).Image.(PublishedCommentImage)
	sanction := moderationDecision(t, l, reviewer, r.CaseID, "MUTE", 3).Sanctions[0]
	if sanction.CommentID == nil || *sanction.CommentID != reply {
		t.Fatal("sanction lost target")
	}
	for _, call := range []func() error{
		func() error { _, e := l.c.ReadOneComment(ctx, reporter.SessionToken, p.post.String(), reply); return e },
		func() error {
			_, e := l.c.ReadCommentImage(ctx, reporter.SessionToken, p.post.String(), reply, image.ContentVersionID)
			return e
		},
		func() error { _, e := l.c.LocateComment(ctx, reporter.SessionToken, p.post.String(), reply); return e },
	} {
		if call() == nil {
			t.Fatal("downed reply remained public")
		}
	}
	page, e := l.c.ReadComments(ctx, reporter.SessionToken, CommentQuery{ID: root, Replies: true})
	if e != nil || len(page.Value.(TextCommentPage).Comments) != 1 || page.Value.(TextCommentPage).Comments[0].ID != sibling {
		t.Fatal("reply action damaged sibling", e)
	}
	yes := true
	like := commentTextSend(t, l, reporter.SessionToken, postTestKey(t), comments.Intent{Operation: comments.SetLike, CommentID: reply, Liked: &yes})
	if like.State != "REJECTED" {
		t.Fatal("hidden reply liked")
	}
	pending := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: p.post.String(), IdentityID: p.identity.String(), RootCommentID: root, TargetCommentID: reply, Body: "不得回复下架目标"}
	rejected := commentTextSend(t, l, p.bearer, postTestKey(t), pending)
	if rejected.State != "REJECTED" {
		t.Fatal("hidden target accepted new reply")
	}
	appeal, e := l.c.SubmitAppeal(ctx, owner.SessionToken, sanction.ID, uuid.NewString(), moderation.Material{Description: "合成申诉", Images: []moderation.Image{}}, false)
	if e != nil {
		t.Fatal(e)
	}
	a := appeal.Value.(moderation.Appeal)
	_, e = l.c.ExecuteModeration(ctx, reviewer.SessionToken, "appeal-decision", a.ID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Accept: true, Reason: "原审核员不得复核"})
	postTestError(t, e, "REVIEWER_RECUSED", 403)
	if _, e = l.c.ExecuteModeration(ctx, other.SessionToken, "appeal-decision", a.ID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Accept: true, Reason: "独立申诉复核"}); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.ReadCommentImage(ctx, reporter.SessionToken, p.post.String(), reply, image.ContentVersionID); e != nil {
		t.Fatal("eligible image not restored", e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.notifications WHERE account_id=$1 AND kind='APPEAL_RESULT'`, owner.AccountID) != 1 {
		t.Fatal("appeal result notice missing")
	}
	// Root hides its whole floor. Reversing one restriction cannot override another root/post fact.
	_, rr := commentReportSubmit(t, l, reporter, p.post.String(), root, nil)
	_, pendingReport := commentReportSubmit(t, l, reporter, p.post.String(), sibling, nil)
	rootSanction := moderationDecision(t, l, reviewer, rr.CaseID, "TAKEDOWN", 0).Sanctions[0]
	if _, e = l.c.ReadOneComment(ctx, reporter.SessionToken, p.post.String(), sibling); e == nil {
		t.Fatal("root did not hide floor")
	}
	if _, e = l.c.ReadCommentImage(ctx, reporter.SessionToken, p.post.String(), reply, image.ContentVersionID); e == nil {
		t.Fatal("root hidden image leak")
	}
	// Own deletion remains allowed for moderated content and ends any unfinished cases.
	removed := commentTextSend(t, l, owner.SessionToken, postTestKey(t), comments.Intent{Operation: comments.DeleteComment, CommentID: root})
	if removed.State != "APPLIED" || *removed.DeletedCount != 3 {
		t.Fatal("owner could not erase hidden floor", removed)
	}
	commentReportRevoke(t, l, other, rootSanction.ID)
	if _, e = l.c.ReadOneComment(ctx, reporter.SessionToken, p.post.String(), reply); e == nil {
		t.Fatal("appeal revived author deletion")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.cases WHERE case_id=$1 AND state='ENDED' AND outcome='TARGET_DELETED'`, pendingReport.CaseID) != 1 {
		t.Fatal("delete hook left pending case")
	}
	v, e = l.c.ReadModeration(ctx, reviewer.SessionToken, "case", r.CaseID, "", "", 50)
	if e != nil || v.Value.(moderation.Case).Evidence.Images[0].Base64 != evidence.Images[0].Base64 {
		t.Fatal("immutable governance evidence erased", e)
	}
}

func TestCommentReportRootFailureProviderAndParentLifecyclePostgres(t *testing.T) {
	l := commentReportLab(t)
	ctx := context.Background()
	p := moderationPost(t, l, "cr_failure_parent")
	owner := moderationActor(t, l, "cr_failure_owner", "")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "参与身份").IdentityID
	reporter := moderationActor(t, l, "cr_failure_reporter", "")
	reviewer := moderationActor(t, l, "cr_failure_reviewer", "REVIEWER")
	other := moderationActor(t, l, "cr_failure_other", "REVIEWER")
	root := commentReportCreate(t, l, owner, id, p.post.String(), "", "楼层")
	reply := commentReportCreate(t, l, owner, id, p.post.String(), root, "回复")
	_, rr := commentReportSubmit(t, l, reporter, p.post.String(), root, nil)
	_, rp := commentReportSubmit(t, l, reporter, p.post.String(), reply, nil)
	pending := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: p.post.String(), IdentityID: p.identity.String(), RootCommentID: root, TargetCommentID: root, Body: "审核前已受理的真实任务"}
	commentTextSend(t, l, p.bearer, postTestKey(t), pending)
	rootSanction := moderationDecision(t, l, reviewer, rr.CaseID, "TAKEDOWN", 0).Sanctions[0]
	commentTextPublish(t, l)
	own := commentTextOwn(t, l, p.bearer, pending.TaskID)
	if own.State != comments.Failed || own.FailureCode == nil || *own.FailureCode != "COMMENT_TARGET_DELETED" {
		t.Fatal("existing task failure pipeline not reused", own)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.notifications WHERE resource_id=$1 AND kind='COMMENT_FAILURE' AND identity_id=$2`, pending.TaskID, p.identity) != 1 {
		t.Fatal("real failure notification missing")
	}
	retry := pending
	retry.Operation = comments.Retry
	retry.ExpectedAttemptVersion = 1
	retry.PostID = ""
	retry.IdentityID = ""
	retry.RootCommentID = ""
	retry.TargetCommentID = ""
	if got := commentTextSend(t, l, p.bearer, postTestKey(t), retry); got.State != "REJECTED" {
		t.Fatal("terminal original task retry accepted")
	}
	commentTextSend(t, l, p.bearer, postTestKey(t), comments.Intent{Operation: comments.Abandon, TaskID: pending.TaskID, ExpectedAttemptVersion: 1})
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.notifications WHERE resource_id=$1`, pending.TaskID) != 0 {
		t.Fatal("existing abandon did not remove notification")
	}
	commentReportRevoke(t, l, other, rootSanction.ID)
	// A parent takedown blocks every public comment surface, its reversal restores eligible comments only.
	_, pr := moderationReport(t, l, reporter, nil, p.post, "OTHER")
	ps := moderationDecision(t, l, reviewer, pr.CaseID, "TAKEDOWN", 0).Sanctions[0]
	if _, e := l.c.ReadOneComment(ctx, reporter.SessionToken, p.post.String(), reply); e == nil {
		t.Fatal("parent state bypass")
	}
	commentReportRevoke(t, l, other, ps.ID)
	if _, e := l.c.ReadOneComment(ctx, reporter.SessionToken, p.post.String(), reply); e != nil {
		t.Fatal(e)
	}
	if _, e := l.c.ExecutePostCommand(ctx, p.bearer, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: p.post.String()}); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.cases WHERE case_id=$1 AND state='ENDED' AND outcome='TARGET_DELETED'`, rp.CaseID) != 1 {
		t.Fatal("parent deletion stranded comment case")
	}
}

func TestCommentReportRuntimeSchemaAndLeastPrivilegePostgres(t *testing.T) {
	l := commentReportLab(t)
	ctx := context.Background()
	// Both enabled moderation and common C startup must fail closed without the new hooks.
	for _, spec := range [][2]string{{"c_comments.tasks", "moderation_comment_deleted"}, {"c_comments.attempts", "moderation_comment_publication"}} {
		mustExec(t, l.cp, `ALTER TABLE `+spec[0]+` DISABLE TRIGGER `+spec[1])
		_, moderationErr := l.c.WithModeration(ctx)
		if CheckModerationLifecycleSchema(ctx, l.cp) == nil || moderationErr == nil {
			t.Fatal("missing lifecycle hook accepted")
		}
		mustExec(t, l.cp, `ALTER TABLE `+spec[0]+` ENABLE TRIGGER `+spec[1])
	}
	p := moderationPost(t, l, "cr_runtime_parent")
	owner := moderationActor(t, l, "cr_runtime_owner", "")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "runtime").IdentityID
	reporter := moderationActor(t, l, "cr_runtime_reporter", "")
	reviewer := moderationActor(t, l, "cr_runtime_reviewer", "REVIEWER")
	root := commentReportCreate(t, l, owner, id, p.post.String(), "", "真实最小授权评论")
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	for _, path := range []string{"grant-community.sql", "grant-comments.sql", "grant-moderation.sql"} {
		b, e := os.ReadFile("../../../../infra/postgres/" + path)
		if e != nil {
			t.Fatal(e)
		}
		mustExec(t, l.cp, string(b))
	}
	pool, e := pgxpool.New(ctx, os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
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
	if _, e = l.c.WithModeration(ctx); e != nil {
		t.Fatal(e)
	}
	_, r := commentReportSubmit(t, l, reporter, p.post.String(), root, nil)
	moderationDecision(t, l, reviewer, r.CaseID, "TAKEDOWN", 0)
	if _, e = l.c.ReadOneComment(ctx, reporter.SessionToken, p.post.String(), root); e == nil {
		t.Fatal("runtime public filter bypass")
	}
	mustExec(t, l.cp, `REVOKE UPDATE(moderation_hidden) ON c_comments.tasks FROM hnuhole_c_runtime`)
	if _, e = l.c.WithModeration(ctx); e == nil {
		t.Fatal("missing target grant accepted")
	}
}

func TestCommentReportGooseUpgradePostgres(t *testing.T) {
	tool := os.Getenv("MODERATION_GOOSE")
	dsn := os.Getenv("COMMENT_REPORT_UPGRADE_DSN")
	if tool == "" || dsn == "" {
		t.Skip("owned Goose upgrade fixture absent")
	}
	ctx := context.Background()
	cfg, e := pgxpool.ParseConfig(dsn)
	if e != nil || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(os.Getenv("AUTHLAB_RUNTIME_TAG"), "hnuhole_authlab_") || cfg.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
		t.Fatal("owned fixture marker required")
	}
	pool, e := pgxpool.NewWithConfig(ctx, cfg)
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	var safe bool
	if e = pool.QueryRow(ctx, `SELECT current_database()='hnuhole_comment_report_upgrade' AND current_user='hnuhole_c' AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AND inet_server_addr() IS NULL AND to_regnamespace('c_auth') IS NULL`).Scan(&safe); e != nil || !safe {
		t.Fatal("dedicated empty upgrade database required", e)
	}
	dir, e := filepath.Abs("../../migrations")
	if e != nil {
		t.Fatal(e)
	}
	run := func(command string, args ...string) error {
		return exec.Command(tool, append([]string{"-dir", dir, "postgres", dsn, command}, args...)...).Run()
	}
	if e = run("up-to", "17"); e != nil {
		t.Fatal("main schema install", e)
	}
	mustExec(t, pool, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('d2c920f5-5563-452d-901c-be133844b0fa','001829','comment_report_upgrade',decode(repeat('11',32),'hex'),decode(repeat('22',16),'hex'),1)`)
	if e = run("up"); e != nil {
		t.Fatal("0018 upgrade", e)
	}
	if count(t, pool, `SELECT count(*) FROM public.goose_db_version WHERE is_applied`) != 19 || count(t, pool, `SELECT count(*) FROM c_auth.accounts WHERE username='comment_report_upgrade'`) != 1 {
		t.Fatal("migration order or preserved account")
	}
	if e = checkCommentModerationSchema(ctx, pool, false); e != nil {
		t.Fatal(e)
	}
	if e = run("down"); e == nil {
		t.Fatal("evidence migration rolled back")
	}
	if count(t, pool, `SELECT count(*) FROM public.goose_db_version WHERE is_applied AND version_id=18`) != 1 {
		t.Fatal("failed down changed ledger")
	}
}
