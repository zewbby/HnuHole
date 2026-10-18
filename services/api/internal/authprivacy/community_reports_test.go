package authprivacy

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestModerationImageSnapshotAndHiddenOriginalPostgres(t *testing.T) {
	l := moderationLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	owner := moderationActor(t, l, "mod_image_owner", "")
	reporter := moderationActor(t, l, "mod_image_reporter", "")
	reviewer := moderationActor(t, l, "mod_image_reviewer", "REVIEWER")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "图片证据身份").IdentityID
	selection, data := imageFixture(t, "png")
	selection.MediaID = uuid.NewString()
	intent := postTestIntent(t, l, identity)
	intent.Images = []postmedia.Selection{selection}
	accepted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	grant := imageGrant(t, l, owner.SessionToken, accepted, selection.MediaID)
	imageUpload(t, l, accepted, selection, grant, data)
	postTestPublish(t, l)
	// Existing public images remain snapshot evidence if image uploads are disabled.
	withoutImages := *l.c
	withoutImages.postImages = nil
	key := uuid.NewString()
	v, e := withoutImages.SubmitReport(ctx, reporter.SessionToken, key, moderation.ReportInput{PostID: accepted.PostID, Reason: "PRIVACY", Images: []moderation.Image{}})
	if e != nil {
		t.Fatal(e)
	}
	caseID := v.Value.(moderation.ReportResult).Report.CaseID
	detail, e := l.c.ReadModeration(ctx, reviewer.SessionToken, "case", caseID, "", "", 50)
	if e != nil {
		t.Fatal(e)
	}
	images := detail.Value.(moderation.Case).Evidence.Images
	if len(images) != 1 || images[0].Base64 != base64.StdEncoding.EncodeToString(data) {
		t.Fatal("original public evidence dropped when uploads disabled")
	}
	for _, image := range []moderation.Image{{MIME: "image/png", Base64: base64.StdEncoding.EncodeToString([]byte("not an image"))}, {MIME: "image/jpeg", Base64: base64.StdEncoding.EncodeToString(data)}} {
		_, e = l.c.SubmitReport(ctx, reporter.SessionToken, uuid.NewString(), moderation.ReportInput{PostID: accepted.PostID, Reason: "OTHER", Images: []moderation.Image{image}})
		if !errors.Is(e, moderation.ErrInvalid) {
			t.Fatal("invalid supplement accepted", e)
		}
	}
	moderationDecision(t, l, reviewer, caseID, "TAKEDOWN", 0)
	for _, content := range []string{"", selection.MediaID} {
		_, e = l.c.ReadPostImages(ctx, owner.SessionToken, accepted.PostID, content)
		postTestError(t, e, "MEDIA_NOT_FOUND", 404)
	}
	if _, e = l.c.ReadPosts(ctx, reporter.SessionToken, PostQuery{Kind: PostDetail, ID: accepted.PostID}); e == nil {
		t.Fatal("downed image post remained public")
	}
}

func TestModerationAppealRoundsAndAdvanceReversalPostgres(t *testing.T) {
	l := moderationLab(t)
	ctx := context.Background()
	f := moderationPost(t, l, "mod_round_owner")
	r := moderationActor(t, l, "mod_round_reporter", "")
	a := moderationActor(t, l, "mod_round_actor", "REVIEWER")
	b := moderationActor(t, l, "mod_round_other", "REVIEWER")
	_, report := moderationReport(t, l, r, nil, f.post, "OTHER")
	s := moderationDecision(t, l, a, report.CaseID, "TAKEDOWN", 0).Sanctions[0]
	var last moderation.Appeal
	for i, description := range []string{"首次证据", "第二轮新增证据", "第三轮新增证据"} {
		v, e := l.c.SubmitAppeal(ctx, f.bearer, s.ID, uuid.NewString(), moderation.Material{Description: description, Images: []moderation.Image{}}, false)
		if e != nil {
			t.Fatal(e)
		}
		last = v.Value.(moderation.Appeal)
		if last.Ordinal != i+1 {
			t.Fatal("appeal round drift")
		}
		_, e = l.c.SubmitAppeal(ctx, f.bearer, s.ID, uuid.NewString(), moderation.Material{Description: "并行新申诉", Images: []moderation.Image{}}, false)
		postTestError(t, e, "APPEAL_PENDING", 409)
		if _, e = l.c.ExecuteModeration(ctx, b.SessionToken, "appeal-decision", last.ID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Accept: false, Reason: "独立复核"}); e != nil {
			t.Fatal(e)
		}
		if i < 2 {
			_, e = l.c.SubmitAppeal(ctx, f.bearer, s.ID, uuid.NewString(), moderation.Material{Description: description, Images: []moderation.Image{}}, false)
			postTestError(t, e, "NEW_MATERIAL_REQUIRED", 409)
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.appeals WHERE sanction_id=$1`, s.ID) != 3 {
		t.Fatal("appeal quota drift")
	}
	_, e := l.c.SubmitAppeal(ctx, f.bearer, s.ID, uuid.NewString(), moderation.Material{Description: "第四轮", Images: []moderation.Image{}}, false)
	postTestError(t, e, "APPEAL_LIMIT", 409)
	// A separate new public fact has its own quota; advance reversal must not
	// strand an appeal that was already pending.
	accepted := postTestCommand(t, l, f.bearer, postTestKey(t), postTestIntent(t, l, f.identity))
	postTestPublish(t, l)
	_, next := moderationReport(t, l, r, nil, uuid.MustParse(accepted.PostID), "OTHER")
	s2 := moderationDecision(t, l, a, next.CaseID, "TAKEDOWN", 0).Sanctions[0]
	v, e := l.c.SubmitAppeal(ctx, f.bearer, s2.ID, uuid.NewString(), moderation.Material{Description: "待复核证据", Images: []moderation.Image{}}, false)
	if e != nil {
		t.Fatal(e)
	}
	pending := v.Value.(moderation.Appeal)
	if _, e = l.c.ExecuteModeration(ctx, b.SessionToken, "revoke", s2.ID, moderation.Decision{CommandID: uuid.NewString(), Reason: "先行纠正"}); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.ExecuteModeration(ctx, b.SessionToken, "appeal-decision", pending.ID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Accept: true, Reason: "独立复核"}); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.appeals WHERE appeal_id=$1 AND state='ACCEPTED'`, pending.ID) != 1 {
		t.Fatal("advance reversal stranded pending appeal")
	}
}

// A concurrent renewal can commit after B's Snapshot and before B obtains the
// session lock. Never skip mandatory preparation when that snapshot is stale.
func TestModerationStaleSessionCannotSkipManagementAuthorizationPostgres(t *testing.T) {
	l := moderationLab(t)
	ctx := context.Background()
	f := moderationPost(t, l, "mod_stale_owner")
	actor := moderationActor(t, l, "mod_stale_ordinary", "")
	_, report := moderationReport(t, l, actor, nil, f.post, "PRIVACY")
	var number string
	if e := l.cp.QueryRow(ctx, `SELECT platform_number FROM c_auth.accounts WHERE account_id=$1`, actor.AccountID).Scan(&number); e != nil {
		t.Fatal(e)
	}
	operations := []func(*Community) error{
		func(c *Community) error {
			_, e := c.ReadModeration(ctx, actor.SessionToken, "case", report.CaseID, "", "", 50)
			return e
		},
		func(c *Community) error {
			_, e := c.ReadModerationMaterials(ctx, actor.SessionToken, "REPORT", report.CaseID, "", true)
			return e
		},
		func(c *Community) error {
			_, e := c.ExecuteModeration(ctx, actor.SessionToken, "role", number, moderation.Decision{CommandID: uuid.NewString(), Role: "ADMIN", Reason: "不得绕过权限"})
			return e
		},
	}
	for i, operation := range operations {
		barrier := &identitySnapshotBarrier{AuthorizationGate: l.gate, captured: make(chan struct{}), release: make(chan struct{})}
		c := *l.c
		c.gate = barrier
		done := make(chan error, 1)
		go func() { done <- operation(&c) }()
		<-barrier.captured
		hash := sha256.Sum256(actor.SessionToken[:])
		mustExec(t, l.cp, `UPDATE c_auth.sessions SET last_activity_at=clock_timestamp() WHERE token_digest=$1`, hash[:])
		close(barrier.release)
		if e := <-done; !errors.Is(e, ErrAuthorizationUnavailable) {
			t.Fatalf("operation %d bypassed failed snapshot: %v", i, e)
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.roles WHERE account_id=$1`, actor.AccountID) != 0 {
		t.Fatal("ordinary account elevated itself")
	}
}

func TestModerationMergedReportMaterialRetainsEachReasonPostgres(t *testing.T) {
	l := moderationLab(t)
	f := moderationPost(t, l, "mod_reason_owner")
	r := moderationActor(t, l, "mod_reason_reporter", "")
	reviewer := moderationActor(t, l, "mod_reason_reviewer", "REVIEWER")
	ctx := context.Background()
	caseID := ""
	for _, reason := range []string{"ADVERTISING", "PRIVACY"} {
		v, e := l.c.SubmitReport(ctx, r.SessionToken, uuid.NewString(), moderation.ReportInput{PostID: f.post.String(), Reason: reason, Images: []moderation.Image{}})
		if e != nil {
			t.Fatal(e)
		}
		id := v.Value.(moderation.ReportResult).Report.CaseID
		if caseID != "" && caseID != id {
			t.Fatal("same fact split by reason")
		}
		caseID = id
	}
	cursor := ""
	seen := map[string]bool{}
	for {
		v, e := l.c.ReadModerationMaterials(ctx, reviewer.SessionToken, "REPORT", caseID, cursor, true)
		if e != nil {
			t.Fatal(e)
		}
		p := v.Value.(moderation.MaterialPage)
		if len(p.Items) != 1 || p.Items[0].Description != "" {
			t.Fatal("material batch corrupted")
		}
		seen[p.Items[0].Reason] = true
		if p.NextCursor == nil {
			break
		}
		cursor = *p.NextCursor
	}
	if len(seen) != 2 || !seen["ADVERTISING"] || !seen["PRIVACY"] {
		t.Fatal("merged allegation reason lost", seen)
	}
}

func moderationLab(t *testing.T) *lab {
	t.Helper()
	l := newPostLab(t)
	var e error
	l.c, e = l.c.WithModeration(context.Background())
	if e != nil {
		t.Fatal(e)
	}
	return l
}
func moderationActor(t *testing.T, l *lab, name, role string) SessionCreateResult {
	t.Helper()
	s := sessionTestAccount(t, l, name)
	if role != "" {
		mustExec(t, l.cp, `INSERT INTO c_moderation.roles VALUES($1,$2)`, s.AccountID, role)
	}
	return SessionCreateResult{AccountID: s.AccountID, SessionToken: s.SessionToken}
}
func moderationPost(t *testing.T, l *lab, name string) postSchemaFixture {
	t.Helper()
	s := sessionTestAccount(t, l, name)
	i := identityChange(t, l.c, s.SessionToken, "CREATE", uuid.Nil, "帖子身份").IdentityID
	intent := postTestIntent(t, l, i)
	intent.Title = "标题"
	intent.Body = "正文"
	result := postTestCommand(t, l, s.SessionToken, postTestKey(t), intent)
	f := postSchemaFixture{account: s.AccountID, identity: i, post: uuid.MustParse(result.PostID), task: uuid.MustParse(result.TaskID), bearer: s.SessionToken}
	postTestPublish(t, l)
	return f
}
func moderationReport(t *testing.T, l *lab, s SessionCreateResult, identity *string, post uuid.UUID, reason string) (string, moderation.Report) {
	t.Helper()
	key := uuid.NewString()
	r, e := l.c.SubmitReport(context.Background(), s.SessionToken, key, moderation.ReportInput{PostID: post.String(), IdentityID: identity, Reason: reason, Description: "合成举报说明", Images: []moderation.Image{}})
	if e != nil {
		t.Fatal(e)
	}
	return key, *r.Value.(moderation.ReportResult).Report
}
func moderationDecision(t *testing.T, l *lab, s SessionCreateResult, caseID, action string, days int) moderation.Case {
	t.Helper()
	v, e := l.c.ReadModeration(context.Background(), s.SessionToken, "case", caseID, "", "", 50)
	if e != nil {
		t.Fatal(e)
	}
	c := v.Value.(moderation.Case)
	r, e := l.c.ExecuteModeration(context.Background(), s.SessionToken, "decision", caseID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: c.Version, Action: action, Days: days, Reason: "合成处理原因"})
	if e != nil {
		t.Fatal(e)
	}
	return r.Value.(moderation.Case)
}
func TestModerationReportsOriginalResultAndPrivacyPostgres(t *testing.T) {
	l := moderationLab(t)
	ctx := context.Background()
	f := moderationPost(t, l, "mod_post_owner")
	r := moderationActor(t, l, "mod_reporter_a", "")
	other := moderationActor(t, l, "mod_reporter_b", "")
	mask := identityChange(t, l.c, r.SessionToken, "CREATE", uuid.Nil, "举报身份").IdentityID.String()
	key, report := moderationReport(t, l, r, &mask, f.post, "PRIVACY")
	key2, report2 := moderationReport(t, l, other, nil, f.post, "PRIVACY")
	if report.CaseID != report2.CaseID {
		t.Fatal("same fact was not merged")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.cases`) != 1 {
		t.Fatal("duplicate case")
	}
	input := moderation.ReportInput{PostID: f.post.String(), IdentityID: &mask, Reason: "PRIVACY", Description: "合成举报说明", Images: []moderation.Image{}}
	if _, e := l.c.SubmitReport(ctx, r.SessionToken, key, input); e != nil {
		t.Fatal(e)
	}
	input.Description = "变更材料"
	_, e := l.c.SubmitReport(ctx, r.SessionToken, key, input)
	postTestError(t, e, "REQUEST_CONFLICT", 409)
	unknown, e := l.c.GetReport(ctx, r.SessionToken, key2)
	if e != nil || unknown.Value.(moderation.ReportResult).State != "NOT_SUBMITTED" {
		t.Fatal("report ownership leaked", e)
	}
	reviewer := moderationActor(t, l, "mod_review_a", "REVIEWER")
	detail, e := l.c.ReadModeration(ctx, reviewer.SessionToken, "case", report.CaseID, "", "", 50)
	if e != nil {
		t.Fatal(e)
	}
	b, _ := json.Marshal(detail.Value)
	for _, secret := range []string{r.AccountID.String(), other.AccountID.String(), f.account.String(), f.identity.String(), mask, "reporterAccount", "username", "slot", "email"} {
		if strings.Contains(string(b), secret) {
			t.Fatalf("management DTO leaked %s", secret)
		}
	}
	if detail.Value.(moderation.Case).Evidence.Title != "标题" {
		t.Fatal("snapshot missing")
	}
	if _, e = l.c.ReadModeration(ctx, r.SessionToken, "case", report.CaseID, "", "", 50); e == nil {
		t.Fatal("ordinary user entered management")
	}
	_, e = l.c.ExecuteModeration(ctx, reviewer.SessionToken, "decision", report.CaseID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Action: "BAN", Days: 0, Reason: "越权"})
	postTestError(t, e, "MODERATION_FORBIDDEN", 403)
}
func TestModerationConcurrentDecisionAndIdentityReadPostgres(t *testing.T) {
	l := moderationLab(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	f := moderationPost(t, l, "mod_concurrent_owner")
	r := moderationActor(t, l, "mod_concurrent_report", "")
	mask := identityChange(t, l.c, r.SessionToken, "CREATE", uuid.Nil, "通知身份甲").IdentityID.String()
	maskB := identityChange(t, l.c, r.SessionToken, "CREATE", uuid.Nil, "通知身份乙").IdentityID.String()
	_, report := moderationReport(t, l, r, &mask, f.post, "HARASSMENT")
	other := moderationActor(t, l, "mod_concurrent_other", "")
	moderationReport(t, l, other, nil, f.post, "HARASSMENT")
	reviewers := []SessionCreateResult{moderationActor(t, l, "mod_concurrent_rev_a", "REVIEWER"), moderationActor(t, l, "mod_concurrent_rev_b", "REVIEWER")}
	var wg sync.WaitGroup
	out := make(chan error, 2)
	for _, s := range reviewers {
		wg.Add(1)
		go func(s SessionCreateResult) {
			defer wg.Done()
			_, e := l.c.ExecuteModeration(ctx, s.SessionToken, "decision", report.CaseID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Action: "TAKEDOWN", Reason: "并发合成处理"})
			out <- e
		}(s)
	}
	wg.Wait()
	close(out)
	success := 0
	for e := range out {
		if e == nil {
			success++
		} else {
			postTestError(t, e, "CASE_ALREADY_HANDLED", 409)
		}
	}
	if success != 1 || count(t, l.cp, `SELECT count(*) FROM c_moderation.sanctions`) != 1 {
		t.Fatal("duplicate penalty")
	}
	page, e := l.c.ReadSystemNotifications(ctx, r.SessionToken, "", mask, "", 50, false)
	if e != nil {
		t.Fatal(e)
	}
	items := page.Value.(moderation.NotificationPage).Items
	if len(items) != 2 {
		t.Fatal("progress/result notification missing", len(items))
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.notifications WHERE read_at IS NOT NULL`) != 0 {
		t.Fatal("list marked read")
	}
	_, e = l.c.ReadSystemNotifications(ctx, r.SessionToken, items[0].ID, maskB, "", 50, true)
	postTestError(t, e, "NOTIFICATION_NOT_FOUND", 404)
	_, e = l.c.ReadSystemNotifications(ctx, other.SessionToken, items[0].ID, "", "", 50, true)
	postTestError(t, e, "NOTIFICATION_NOT_FOUND", 404)
	if _, e = l.c.ReadSystemNotifications(ctx, r.SessionToken, items[0].ID, mask, "", 50, true); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.notifications WHERE read_at IS NOT NULL`) != 1 {
		t.Fatal("read affected other item")
	}
	_, e = l.c.ReadPosts(ctx, r.SessionToken, PostQuery{Kind: PostDetail, ID: f.post.String()})
	postTestError(t, e, "POST_NOT_FOUND", 404)
	task, e := l.c.ReadPosts(ctx, f.bearer, PostQuery{Kind: PostTaskDetail, ID: f.task.String()})
	if e != nil {
		t.Fatal(e)
	}
	if task.Value.(posts.OwnTaskDetail).Content != nil {
		t.Fatal("hidden post exposed by task endpoint")
	}
	// A notification cursor includes the UUID tie-breaker; no equal-time event is lost.
	var cursor string
	seen := map[string]bool{}
	for i := 0; i < 3; i++ {
		v, e := l.c.ReadSystemNotifications(ctx, r.SessionToken, "", mask, cursor, 1, false)
		if e != nil {
			t.Fatal(e)
		}
		p := v.Value.(moderation.NotificationPage)
		for _, n := range p.Items {
			if seen[n.ID] {
				t.Fatal("duplicate page item")
			}
			seen[n.ID] = true
		}
		if p.NextBefore == nil {
			break
		}
		cursor = *p.NextBefore
	}
	if len(seen) != 2 {
		t.Fatal("notification pagination lost an event")
	}
}
func TestModerationAppealIndependentReversalAndAuthorDeletionPostgres(t *testing.T) {
	l := moderationLab(t)
	ctx := context.Background()
	f := moderationPost(t, l, "mod_appeal_owner")
	reporter := moderationActor(t, l, "mod_appeal_reporter", "")
	_, first := moderationReport(t, l, reporter, nil, f.post, "PRIVACY")
	_, second := moderationReport(t, l, reporter, nil, f.post, "HARASSMENT")
	second.CaseID = moderationIndependentCase(t, l, first.CaseID, "second-fact")
	_, pending := moderationReport(t, l, reporter, nil, f.post, "OTHER")
	pending.CaseID = moderationIndependentCase(t, l, first.CaseID, "pending-fact")
	a := moderationActor(t, l, "mod_appeal_rev_a", "REVIEWER")
	b := moderationActor(t, l, "mod_appeal_rev_b", "REVIEWER")
	c1 := moderationDecision(t, l, a, first.CaseID, "TAKEDOWN", 0)
	c2 := moderationDecision(t, l, a, second.CaseID, "TAKEDOWN", 0)
	s1 := c1.Sanctions[0]
	s2 := c2.Sanctions[0]
	key := uuid.NewString()
	v, e := l.c.SubmitAppeal(ctx, f.bearer, s1.ID, key, moderation.Material{Description: "首次申诉证据", Images: []moderation.Image{}}, false)
	if e != nil {
		t.Fatal(e)
	}
	appeal := v.Value.(moderation.Appeal)
	_, e = l.c.ExecuteModeration(ctx, a.SessionToken, "appeal-decision", appeal.ID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Accept: true, Reason: "不能自己复核"})
	postTestError(t, e, "REVIEWER_RECUSED", 403)
	if _, e = l.c.SubmitAppeal(ctx, f.bearer, appeal.ID, uuid.NewString(), moderation.Material{Description: "追加材料不计次数", Images: []moderation.Image{}}, true); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.appeals WHERE sanction_id=$1`, s1.ID) != 1 {
		t.Fatal("append consumed appeal round")
	}
	if _, e = l.c.ExecuteModeration(ctx, b.SessionToken, "appeal-decision", appeal.ID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Accept: true, Reason: "独立复核通过"}); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE post_id=$1 AND moderation_hidden`, f.post) != 1 {
		t.Fatal("reversal ignored another takedown")
	}
	postTestCommand(t, l, f.bearer, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: f.post.String()})
	var outcome string
	if e = l.cp.QueryRow(ctx, `SELECT outcome FROM c_moderation.cases WHERE case_id=$1`, pending.CaseID).Scan(&outcome); e != nil || outcome != "TARGET_DELETED" {
		t.Fatal("deletion did not end pending case", e, outcome)
	}
	if _, e = l.c.ExecuteModeration(ctx, b.SessionToken, "revoke", s2.ID, moderation.Decision{CommandID: uuid.NewString(), Reason: "撤销第二项"}); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE post_id=$1 AND visibility='DELETED'`, f.post) != 1 {
		t.Fatal("appeal revived author-deleted post")
	}
	_, e = l.c.SubmitAppeal(ctx, f.bearer, appeal.ID, uuid.NewString(), moderation.Material{Description: "结案追加", Images: []moderation.Image{}}, true)
	postTestError(t, e, "APPEAL_CLOSED", 409)
}
func TestModerationMuteOverlapAndRestrictedNoticesPostgres(t *testing.T) {
	l := moderationLab(t)
	ctx := context.Background()
	f := moderationPost(t, l, "mod_overlap_owner")
	reporter := moderationActor(t, l, "mod_overlap_reporter", "")
	_, r1 := moderationReport(t, l, reporter, nil, f.post, "PRIVACY")
	_, r2 := moderationReport(t, l, reporter, nil, f.post, "HARASSMENT")
	r2.CaseID = moderationIndependentCase(t, l, r1.CaseID, "overlap-fact")
	_, r3 := moderationReport(t, l, reporter, nil, f.post, "OTHER")
	r3.CaseID = moderationIndependentCase(t, l, r1.CaseID, "ban-fact")
	a := moderationActor(t, l, "mod_overlap_rev_a", "ADMIN")
	b := moderationActor(t, l, "mod_overlap_rev_b", "ADMIN")
	c1 := moderationDecision(t, l, a, r1.CaseID, "MUTE", 3)
	c2 := moderationDecision(t, l, a, r2.CaseID, "MUTE", 7)
	if !c2.Sanctions[0].EndsAt.After(*c1.Sanctions[0].EndsAt) {
		t.Fatal("independent windows missing")
	}
	if _, e := l.c.ExecuteModeration(ctx, b.SessionToken, "revoke", c1.Sanctions[0].ID, moderation.Decision{CommandID: uuid.NewString(), Reason: "只撤第一项"}); e != nil {
		t.Fatal(e)
	}
	var end time.Time
	if e := l.cp.QueryRow(ctx, `SELECT mute_ends_at FROM c_auth.account_restrictions WHERE account_id=$1`, f.account).Scan(&end); e != nil || !end.Equal(*c2.Sanctions[0].EndsAt) {
		t.Fatal("reversal cleared overlapping mute", e)
	}
	c3 := moderationDecision(t, l, a, r3.CaseID, "BAN", 1)
	if _, e := l.c.GetCurrentSession(ctx, f.bearer); e == nil {
		t.Fatal("ban retained ordinary session")
	}
	limited, e := l.c.CreateModerationAccessSession(ctx, ModerationAccessRequest{"mod_overlap_owner", labLoginPassword}, sessionTestPasswordWorker(t, 1))
	if e != nil {
		t.Fatal(e)
	}
	notices, e := l.c.ReadSystemNotifications(ctx, limited.SessionToken, "", "", "", 50, false)
	if e != nil {
		t.Fatal(e)
	}
	for _, n := range notices.Value.(moderation.NotificationPage).Items {
		if n.Scope != "ACCOUNT" || n.Kind != "SANCTION" && n.Kind != "APPEAL_RESULT" {
			t.Fatal("limited capability saw community notifications")
		}
	}
	if _, e = l.c.ReadSanction(ctx, limited.SessionToken, c3.Sanctions[0].ID); e != nil {
		t.Fatal("banned user cannot inspect sanction", e)
	}
	if _, e = l.c.SubmitAppeal(ctx, limited.SessionToken, c3.Sanctions[0].ID, uuid.NewString(), moderation.Material{Description: "封禁申诉", Images: []moderation.Image{}}, false); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.ReadModeration(ctx, limited.SessionToken, "me", "", "", "", 50); e == nil {
		t.Fatal("limited capability entered admin")
	}
}
func TestModerationRuntimePrivilegesAndAuditPostgres(t *testing.T) {
	l := moderationLab(t)
	dsn := os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN")
	if dsn == "" {
		t.Skip("isolated runtime DSN absent")
	}
	ctx := context.Background()
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(id integer PRIMARY KEY,version_id bigint,is_applied boolean,tstamp timestamp)`)
	for _, name := range []string{"../../../../infra/postgres/grant-community.sql", "../../../../infra/postgres/grant-post-images.sql", "../../../../infra/postgres/grant-moderation.sql"} {
		b, e := os.ReadFile(name)
		if e != nil {
			t.Fatal(e)
		}
		mustExec(t, l.cp, string(b))
	}
	pool, e := pgxpool.New(ctx, dsn)
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	clone := *l.c
	clone.pool = pool
	runtimeCommunity, e := clone.WithModeration(ctx)
	if e != nil {
		t.Fatal("restricted runtime did not enable", e)
	}
	for _, sql := range []string{`DELETE FROM c_moderation.audit`, `UPDATE c_moderation.audit SET reason='changed'`, `SELECT * FROM v_auth.slots`} {
		if _, e = pool.Exec(ctx, sql); e == nil {
			t.Fatal("restricted runtime allowed forbidden SQL", sql)
		}
	}
	actor := moderationActor(t, l, "mod_priv_actor", "ADMIN")
	number := ""
	if e = l.cp.QueryRow(ctx, `SELECT platform_number FROM c_auth.accounts WHERE account_id=$1`, actor.AccountID).Scan(&number); e != nil {
		t.Fatal(e)
	}
	_, e = l.c.ExecuteModeration(ctx, actor.SessionToken, "role", number, moderation.Decision{CommandID: uuid.NewString(), Role: "NONE", Reason: "最后管理员"})
	postTestError(t, e, "LAST_ADMIN", 409)
	f := moderationPost(t, l, "mod_priv_post_owner")
	reporter := moderationActor(t, l, "mod_priv_reporter", "")
	other := moderationActor(t, l, "mod_priv_other_admin", "ADMIN")
	// Business DML must actually run through the restricted runtime connection;
	// owner fixture creation alone is not evidence that the grant is sufficient.
	l.c = runtimeCommunity
	_, report := moderationReport(t, l, reporter, nil, f.post, "PRIVACY")
	s := moderationDecision(t, l, actor, report.CaseID, "MUTE", 3).Sanctions[0]
	v, e := l.c.SubmitAppeal(ctx, f.bearer, s.ID, uuid.NewString(), moderation.Material{Description: "受限数据库角色申诉", Images: []moderation.Image{}}, false)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.ExecuteModeration(ctx, other.SessionToken, "appeal-decision", v.Value.(moderation.Appeal).ID, moderation.Decision{CommandID: uuid.NewString(), ExpectedVersion: 1, Accept: true, Reason: "受限数据库角色复核"}); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.ReadSystemNotifications(ctx, f.bearer, "", "", "", 50, false); e != nil {
		t.Fatal(e)
	}
}

// Seed historical independently established facts only to exercise conservative reversal.
// Production report creation merges every identical public snapshot across categories.
func moderationIndependentCase(t *testing.T, l *lab, original, label string) string {
	t.Helper()
	id := uuid.NewString()
	mustExec(t, l.cp, `INSERT INTO c_moderation.cases(case_id,post_id,target_account_id,target_identity_id,reason,snapshot_digest,evidence,created_at) SELECT $2,post_id,target_account_id,target_identity_id,reason,$3,evidence,created_at FROM c_moderation.cases WHERE case_id=$1`, original, id, label)
	return id
}
