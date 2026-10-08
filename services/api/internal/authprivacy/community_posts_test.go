package authprivacy

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func enablePostLab(t *testing.T, l *lab) PostConfig {
	t.Helper()
	config := PostConfig{Environment: "text-post-lab"}
	for _, key := range []*[32]byte{&config.KeyKey, &config.FingerprintKey, &config.CursorKey} {
		value, err := random32()
		if err != nil {
			t.Fatal(err)
		}
		*key = value
	}
	var err error
	l.c, err = l.c.WithPosts(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	return config
}
func newPostLab(t *testing.T) *lab {
	t.Helper()
	l := newLab(t)
	enablePostLab(t, l)
	return l
}
func postTestKey(t *testing.T) string {
	t.Helper()
	key := identityRequestKey(t)
	return protocol.EncodeCanonicalBase64url(key[:])
}
func postTestIntent(t *testing.T, l *lab, identity uuid.UUID) posts.Intent {
	t.Helper()
	var channel string
	if err := l.cp.QueryRow(context.Background(), `SELECT id FROM public.channels ORDER BY id LIMIT 1`).Scan(&channel); err != nil {
		t.Fatal(err)
	}
	return posts.Intent{Operation: posts.Create, ChannelID: channel, IdentityID: identity.String(), Title: "文字标题", Body: "正文 👨‍👩‍👧‍👦\r\n保留原文 e\u0301"}
}
func postTestCommand(t *testing.T, l *lab, bearer [32]byte, key string, intent posts.Intent) posts.CommandResult {
	t.Helper()
	r, err := l.c.ExecutePostCommand(context.Background(), bearer, key, intent)
	if err != nil {
		t.Fatal(err)
	}
	result, ok := r.Value.(posts.CommandResult)
	if !ok || r.ServerTime.IsZero() || !r.ExpiresAt.After(r.ServerTime) {
		t.Fatal("missing authoritative command result")
	}
	if _, err = json.Marshal(result); err != nil {
		t.Fatal("invalid strict command DTO", err)
	}
	return result
}
func postTestRead(t *testing.T, l *lab, bearer [32]byte, query PostQuery) any {
	t.Helper()
	r, err := l.c.ReadPosts(context.Background(), bearer, query)
	if err != nil {
		t.Fatal(err)
	}
	if r.ServerTime.IsZero() || !r.ExpiresAt.After(r.ServerTime) {
		t.Fatal("missing read authority headers")
	}
	return r.Value
}
func postTestPublish(t *testing.T, l *lab) {
	t.Helper()
	if _, err := l.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal(err)
	}
}
func postTestError(t *testing.T, err error, code string, status int) {
	t.Helper()
	var rejected *PostError
	if !errors.As(err, &rejected) || rejected.Code != code || rejected.Status != status {
		t.Fatalf("expected %s/%d: %v", code, status, err)
	}
}

func TestPostAtomicAcceptanceOriginalReceiptAndWorkerPostgres(t *testing.T) {
	l := newPostLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "post_atomic_owner")
	first := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "最初身份")
	second := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "第二身份")
	intent, key := postTestIntent(t, l, second.IdentityID), postTestKey(t)
	accepted := postTestCommand(t, l, owner.SessionToken, key, intent)
	if accepted.State != "ACCEPTED" || accepted.AttemptVersion != 1 {
		t.Fatal("not accepted")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_identity_bindings WHERE account_id=$1 AND post_id=$2 AND identity_id=$3`, owner.AccountID, accepted.PostID, second.IdentityID) != 1 {
		t.Fatal("missing immutable identity binding")
	}
	task := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostTaskDetail, ID: accepted.TaskID}).(posts.OwnTaskDetail)
	if task.Task.State != posts.Accepted || task.Content == nil || task.Content.Body != intent.Body || !task.Task.CanCancel {
		t.Fatal("accepted content differs from original")
	}
	feed := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostChannelFeed, ID: intent.ChannelID}).(posts.FeedPage)
	if len(feed.Items) != 0 {
		t.Fatal("acceptance prematurely exposed content")
	}
	composer := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostComposerContext}).(posts.ComposerContext)
	if composer.DefaultIdentityID == nil || *composer.DefaultIdentityID != first.IdentityID.String() {
		t.Fatal("acceptance changed default identity")
	}
	if replay := postTestCommand(t, l, owner.SessionToken, key, intent); replay != accepted {
		t.Fatal("original receipt changed")
	}
	changed := intent
	changed.IdentityID = first.IdentityID.String()
	_, err := l.c.ExecutePostCommand(ctx, owner.SessionToken, key, changed)
	postTestError(t, err, "COMMAND_CONFLICT", 409)
	postTestPublish(t, l)
	postTestPublish(t, l)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE visibility='PUBLISHED'`) != 1 || count(t, l.cp, `SELECT count(*) FROM c_posts.publication_attempts WHERE state='PUBLISHED'`) != 1 {
		t.Fatal("duplicate public effect")
	}
	if replay := postTestCommand(t, l, owner.SessionToken, key, intent); replay != accepted {
		t.Fatal("publication rewrote accepted receipt")
	}
	view, err := l.c.GetPostCommand(ctx, owner.SessionToken, key)
	if err != nil || view.Value.(posts.CommandResult) != accepted {
		t.Fatal("lookup did not return original acceptance", err)
	}
	public := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostDetail, ID: accepted.PostID}).(posts.PublicPostResponse).Post
	if public.Body != intent.Body || public.Author.Nickname != "第二身份" {
		t.Fatal("wrong public content/identity")
	}
	composer = postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostComposerContext}).(posts.ComposerContext)
	if composer.DefaultIdentityID == nil || *composer.DefaultIdentityID != second.IdentityID.String() {
		t.Fatal("successful publication did not update default")
	}
	encoded, _ := json.Marshal(public)
	for _, forbidden := range []string{owner.AccountID.String(), second.IdentityID.String(), "taskId", "canDelete", "acceptanceOrdinal", "requestDigest"} {
		if strings.Contains(string(encoded), forbidden) {
			t.Fatal("public DTO disclosed private field")
		}
	}
}

func TestPostUnknownSealAndDelayedCommandPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "post_seal_owner")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "封印身份").IdentityID
	intent, key := postTestIntent(t, l, id), postTestKey(t)
	digest, err := posts.RequestDigest(intent)
	if err != nil {
		t.Fatal(err)
	}
	unknown, err := l.c.GetPostCommand(ctx, owner.SessionToken, key)
	if err != nil || unknown.Value.(posts.CommandResult).State != "UNKNOWN_NOT_OBSERVED" {
		t.Fatal("missing unknown state", err)
	}
	input := posts.SealInput{Operation: posts.Create, RequestDigest: hex.EncodeToString(digest[:])}
	sealed, err := l.c.SealPostCommand(ctx, owner.SessionToken, key, input)
	if err != nil || sealed.Value.(posts.CommandResult).State != "NOT_ACCEPTED" {
		t.Fatal("not sealed", err)
	}
	_, err = l.c.ExecutePostCommand(ctx, owner.SessionToken, key, intent)
	postTestError(t, err, "COMMAND_SEALED", 409)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts`) != 0 {
		t.Fatal("delayed create passed seal")
	}
	again, err := l.c.SealPostCommand(ctx, owner.SessionToken, key, input)
	if err != nil || again.Value.(posts.CommandResult) != sealed.Value.(posts.CommandResult) {
		t.Fatal("seal not stable")
	}
	input.Operation = posts.Cancel
	_, err = l.c.SealPostCommand(ctx, owner.SessionToken, key, input)
	postTestError(t, err, "COMMAND_CONFLICT", 409)
	key = postTestKey(t)
	accepted := postTestCommand(t, l, owner.SessionToken, key, intent)
	input.Operation = posts.Create
	observed, err := l.c.SealPostCommand(ctx, owner.SessionToken, key, input)
	if err != nil || observed.Value.(posts.CommandResult) != accepted {
		t.Fatal("seal undid accepted task")
	}
}

func TestPostConcurrentReplayAndSealPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "post_concurrent_owner")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "并发身份").IdentityID
	intent, key := postTestIntent(t, l, id), postTestKey(t)
	const clients = 12
	results := make(chan PostResponse, clients)
	failures := make(chan error, clients)
	var wg sync.WaitGroup
	for n := 0; n < clients; n++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r, e := l.c.ExecutePostCommand(ctx, owner.SessionToken, key, intent)
			results <- r
			failures <- e
		}()
	}
	wg.Wait()
	close(results)
	close(failures)
	for e := range failures {
		if e != nil {
			t.Fatal(e)
		}
	}
	var original posts.CommandResult
	for r := range results {
		current := r.Value.(posts.CommandResult)
		if original.State == "" {
			original = current
		}
		if current != original {
			t.Fatal("concurrent duplicate outcomes")
		}
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts`) != 1 || count(t, l.cp, `SELECT count(*) FROM c_posts.post_identity_bindings`) != 1 {
		t.Fatal("duplicate atomic acceptance")
	}
	for n := 0; n < 8; n++ {
		key = postTestKey(t)
		digest, _ := posts.RequestDigest(intent)
		wg.Add(2)
		var create PostResponse
		var createErr, sealErr error
		var seal PostResponse
		go func() {
			defer wg.Done()
			create, createErr = l.c.ExecutePostCommand(ctx, owner.SessionToken, key, intent)
		}()
		go func() {
			defer wg.Done()
			seal, sealErr = l.c.SealPostCommand(ctx, owner.SessionToken, key, posts.SealInput{Operation: posts.Create, RequestDigest: hex.EncodeToString(digest[:])})
		}()
		wg.Wait()
		if sealErr != nil {
			t.Fatal(sealErr)
		}
		if seal.Value.(posts.CommandResult).State == "NOT_ACCEPTED" {
			postTestError(t, createErr, "COMMAND_SEALED", 409)
		} else if createErr != nil || create.Value.(posts.CommandResult) != seal.Value.(posts.CommandResult) {
			t.Fatal("create/seal race yielded conflicting facts")
		}
	}
	postTestPublish(t, l)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE visibility='PUBLISHED'`) != count(t, l.cp, `SELECT count(*) FROM c_posts.publication_attempts WHERE state='PUBLISHED'`) {
		t.Fatal("publication uniqueness mismatch")
	}
}

func TestPostRejectedFactOwnershipAndSessionReplacementPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "post_isolation_owner")
	foreign := sessionTestAccount(t, l, "post_isolation_foreign")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "归属身份").IdentityID
	intent := postTestIntent(t, l, id)
	invalid, key := intent, postTestKey(t)
	invalid.Body = " \u200d\n"
	rejected := postTestCommand(t, l, owner.SessionToken, key, invalid)
	if rejected.State != "REJECTED" || rejected.ErrorCode != "POST_CONTENT_INVALID" || count(t, l.cp, `SELECT count(*) FROM c_posts.post_identity_bindings`) != 0 {
		t.Fatal("rejection created a binding")
	}
	if replay := postTestCommand(t, l, owner.SessionToken, key, invalid); replay != rejected {
		t.Fatal("rejected receipt changed")
	}
	_, err := l.c.ExecutePostCommand(ctx, owner.SessionToken, key, intent)
	postTestError(t, err, "COMMAND_CONFLICT", 409)
	if wrong := postTestCommand(t, l, foreign.SessionToken, postTestKey(t), intent); wrong.ErrorCode != "POST_IDENTITY_UNAVAILABLE" {
		t.Fatal("foreign identity accepted")
	}
	key = postTestKey(t)
	accepted := postTestCommand(t, l, owner.SessionToken, key, intent)
	unknown, err := l.c.GetPostCommand(ctx, foreign.SessionToken, key)
	if err != nil || unknown.Value.(posts.CommandResult).State != "UNKNOWN_NOT_OBSERVED" {
		t.Fatal("foreign account saw command")
	}
	for _, query := range []PostQuery{{Kind: PostTaskDetail, ID: accepted.TaskID}, {Kind: PostCapabilities, ID: accepted.PostID}} {
		_, err = l.c.ReadPosts(ctx, foreign.SessionToken, query)
		if err == nil {
			t.Fatal("foreign ownership bypass")
		}
	}
	login, err := l.c.CreateSession(ctx, sessionTestRequest(t, "post_isolation_owner"), sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	_, err = l.c.GetPostCommand(ctx, owner.SessionToken, key)
	if !errors.Is(err, ErrSessionReplaced) {
		t.Fatal("replaced session queried task", err)
	}
	postTestPublish(t, l)
	public := postTestRead(t, l, foreign.SessionToken, PostQuery{Kind: PostDetail, ID: accepted.PostID}).(posts.PublicPostResponse)
	if public.Post.PostID != accepted.PostID {
		t.Fatal("worker required obsolete bearer")
	}
	if _, err = l.c.GetPostCommand(ctx, login.SessionToken, key); err != nil {
		t.Fatal("new session lost original fact")
	}
}

func TestPostCancelPublicationRaceAndCleanupPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "post_cancel_owner")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "取消身份").IdentityID
	intent := postTestIntent(t, l, id)
	for n := 0; n < 12; n++ {
		accepted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
		cancel := posts.Intent{Operation: posts.Cancel, TaskID: accepted.TaskID, ExpectedAttemptVersion: 1}
		var wg sync.WaitGroup
		wg.Add(2)
		var result PostResponse
		var cancelErr, publishErr error
		go func() {
			defer wg.Done()
			result, cancelErr = l.c.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), cancel)
		}()
		go func() { defer wg.Done(); _, publishErr = l.c.PublishAcceptedPosts(ctx, 100) }()
		wg.Wait()
		if cancelErr != nil || publishErr != nil {
			t.Fatal("race error", cancelErr, publishErr)
		}
		fact := result.Value.(posts.CommandResult)
		task := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostTaskDetail, ID: accepted.TaskID}).(posts.OwnTaskDetail)
		if fact.TaskState != task.Task.State || (fact.TaskState != posts.Cancelled && fact.TaskState != posts.Published) {
			t.Fatal("race yielded contradictory terminal states")
		}
		published := count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE post_id=$1 AND visibility='PUBLISHED'`, accepted.PostID)
		if (fact.TaskState == posts.Published) != (published == 1) {
			t.Fatal("cancel/public visibility mismatch")
		}
		if fact.TaskState == posts.Cancelled && (task.Content != nil || task.Task.Visible) {
			t.Fatal("cancel retained visible failed task")
		}
	}
	if _, err := l.c.CleanupPostPayloads(ctx, 100); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.attempt_contents x JOIN c_posts.publication_attempts a USING(task_id,version) WHERE a.state='CANCELLED' AND (x.title IS NOT NULL OR x.body IS NOT NULL OR x.erased_at IS NULL)`) != 0 {
		t.Fatal("cancel payload survived cleanup")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.command_receipts WHERE outcome='COMMITTED'`) != 12 {
		t.Fatal("cleanup erased immutable command facts")
	}
}

func TestPostMuteExpiryAndExplicitRetryPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "post_mute_owner")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "重试身份").IdentityID
	intent := postTestIntent(t, l, id)
	accepted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	stopAt := control.clock.now().Add(time.Second)
	advanceClosureClock(t, control, stopAt)
	endsAt := stopAt.Add(time.Minute)
	if err := l.c.ApplyAccountMute(ctx, owner.AccountID, 1, &endsAt); err != nil {
		t.Fatal(err)
	}
	postTestPublish(t, l)
	failed := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostTaskDetail, ID: accepted.TaskID}).(posts.OwnTaskDetail)
	if failed.Task.State != posts.Failed || failed.Task.CanRetry || failed.Task.TerminalAt == nil || !failed.Task.TerminalAt.Equal(stopAt) || failed.Task.FailureCode == nil || *failed.Task.FailureCode != "PUBLISHING_STOPPED" {
		t.Fatal("mute did not logically stop original attempt")
	}
	advanceClosureClock(t, control, endsAt)
	postTestPublish(t, l)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE visibility='PUBLISHED'`) != 0 {
		t.Fatal("expiry revived stopped attempt")
	}
	retry := posts.Intent{Operation: posts.Retry, TaskID: accepted.TaskID, ExpectedAttemptVersion: 1, Title: "修改文字", Body: "明确重试"}
	second := postTestCommand(t, l, owner.SessionToken, postTestKey(t), retry)
	if second.State != "ACCEPTED" || second.PostID != accepted.PostID || second.AttemptVersion != 2 {
		t.Fatal("retry changed bound task/post")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_identity_bindings WHERE identity_id=$1`, id) != 1 {
		t.Fatal("retry rebound identity")
	}
	postTestPublish(t, l)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.publication_attempts WHERE task_id=$1 AND version=1 AND state='FAILED'`, accepted.TaskID) != 1 {
		t.Fatal("retry rewrote original failure")
	}
	public := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostDetail, ID: accepted.PostID}).(posts.PublicPostResponse).Post
	if public.Title != retry.Title || public.ChannelID != intent.ChannelID || public.Author.Nickname != "重试身份" {
		t.Fatal("retry did not preserve channel/identity")
	}
	if _, err := l.c.CleanupPostPayloads(ctx, 100); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.attempt_contents WHERE task_id=$1 AND version=1 AND erased_at IS NOT NULL AND title IS NULL AND body IS NULL`, accepted.TaskID) != 1 {
		t.Fatal("old retry content retained")
	}
}

func TestPostClosureCancellationNeverRevivesAttemptPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "post_close_cancel")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "注销缓冲").IdentityID
	accepted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id))
	request, _ := closureTestRequest(t, owner.SessionToken)
	if _, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1)); err != nil {
		t.Fatal(err)
	}
	postTestPublish(t, l)
	login, err := l.c.CreateSession(ctx, sessionTestRequest(t, "post_close_cancel"), sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	postTestPublish(t, l)
	failed := postTestRead(t, l, login.SessionToken, PostQuery{Kind: PostTaskDetail, ID: accepted.TaskID}).(posts.OwnTaskDetail)
	if failed.Task.State != posts.Failed || !failed.Task.CanRetry || count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE visibility='PUBLISHED'`) != 0 {
		t.Fatal("closure cancellation revived original attempt")
	}
	retry := posts.Intent{Operation: posts.Retry, TaskID: accepted.TaskID, ExpectedAttemptVersion: 1, Title: "撤销后重试", Body: "必须显式"}
	if r := postTestCommand(t, l, login.SessionToken, postTestKey(t), retry); r.State != "ACCEPTED" {
		t.Fatal("explicit retry blocked")
	}
	postTestPublish(t, l)
}

func TestPostIdentityDeleteProjectionOwnershipAndHiddenTaskPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "post_delete_identity")
	reader := sessionTestAccount(t, l, "post_delete_reader")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "旧身份").IdentityID
	identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "保留身份")
	intent := postTestIntent(t, l, id)
	first := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	postTestPublish(t, l)
	identityChange(t, l.c, owner.SessionToken, "RENAME", id, "新昵称")
	public := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostDetail, ID: first.PostID}).(posts.PublicPostResponse).Post
	if public.Author.Nickname != "新昵称" {
		t.Fatal("post cached old nickname")
	}
	pending := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	identityChange(t, l.c, owner.SessionToken, "DELETE", id, "")
	postTestPublish(t, l)
	public = postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostDetail, ID: first.PostID}).(posts.PublicPostResponse).Post
	if public.Author.State != "DELETED" || !posts.ValidShortCode(public.Author.ShortCode) || public.Author.Avatar != "inactive-v1" || public.Author.Nickname != "" {
		t.Fatal("bad inactive projection")
	}
	stable := public.Author.ShortCode
	if postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostDetail, ID: first.PostID}).(posts.PublicPostResponse).Post.Author.ShortCode != stable {
		t.Fatal("inactive code unstable")
	}
	if len(postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostOwnList}).(posts.OwnPostPage).Items) != 0 || len(postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostTaskList}).(posts.OwnTaskList).Items) != 0 {
		t.Fatal("deleted identity retained my items")
	}
	failed := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostTaskDetail, ID: pending.TaskID}).(posts.OwnTaskDetail)
	if failed.Task.State != posts.Failed || failed.Task.Visible || failed.Task.CanRetry || failed.Content != nil {
		t.Fatal("deleted identity pending task remained actionable")
	}
	capability := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostCapabilities, ID: first.PostID}).(posts.OwnPostCapabilities)
	if !capability.CanDelete || capability.CanEdit {
		t.Fatal("minimal deletion authority lost")
	}
	deleted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: first.PostID})
	if deleted.State != "COMMITTED" {
		t.Fatal("original author unable to delete old identity post")
	}
	_, err := l.c.ReadPosts(ctx, reader.SessionToken, PostQuery{Kind: PostDetail, ID: first.PostID})
	postTestError(t, err, "POST_NOT_FOUND", 404)
	if _, err = l.c.CleanupPostPayloads(ctx, 100); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.attempt_contents WHERE title IS NOT NULL OR body IS NOT NULL`) != 0 {
		t.Fatal("deleted task/post plaintext survived cleanup")
	}
}

func TestPostFormalClosureIndependentCodesAndExpiredFactsPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "post_formal_close")
	reader := sessionTestAccount(t, l, "post_close_reader")
	var accepted []posts.CommandResult
	for n := 0; n < 2; n++ {
		id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, fmt.Sprintf("关闭身份%d", n)).IdentityID
		accepted = append(accepted, postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id)))
	}
	postTestPublish(t, l)
	request, _ := closureTestRequest(t, owner.SessionToken)
	closure, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, closure.DueAt)
	if n, err := l.c.FinalizeDueClosures(ctx, 10); err != nil || n != 1 {
		t.Fatal("formal close failed", n, err)
	}
	codes := map[string]bool{}
	for _, fact := range accepted {
		p := postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostDetail, ID: fact.PostID}).(posts.PublicPostResponse).Post
		if p.Author.State != "ACCOUNT_CLOSED" || !posts.ValidShortCode(p.Author.ShortCode) || codes[p.Author.ShortCode] {
			t.Fatal("closure projection leaked shared account code")
		}
		codes[p.Author.ShortCode] = true
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.command_receipts WHERE outcome='RESULT_EXPIRED' AND owner_account_id IS NULL AND task_id IS NULL AND post_id IS NULL`) != 2 {
		t.Fatal("closed command facts not compacted")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.attempt_contents WHERE body IS NOT NULL`) != 2 {
		t.Fatal("formal close erased surviving public posts")
	}
	_, err = l.c.ReadPosts(ctx, owner.SessionToken, PostQuery{Kind: PostTaskList})
	if !errors.Is(err, ErrSessionInvalid) {
		t.Fatal("closed bearer had access", err)
	}
	if len(postTestRead(t, l, reader.SessionToken, PostQuery{Kind: PostOwnList}).(posts.OwnPostPage).Items) != 0 {
		t.Fatal("new account inherited old posts")
	}
}

func TestPostCeilingPaginationAndCursorIsolationPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "post_page_owner")
	foreign := sessionTestAccount(t, l, "post_page_foreign")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "分页身份").IdentityID
	intent := postTestIntent(t, l, id)
	var original []posts.CommandResult
	for n := 0; n < 4; n++ {
		original = append(original, postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent))
	}
	postTestPublish(t, l)
	first := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostChannelFeed, ID: intent.ChannelID, Limit: 2}).(posts.FeedPage)
	if len(first.Items) != 2 || first.NextCursor == nil {
		t.Fatal("missing initial page cursor")
	}
	later := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	postTestPublish(t, l)
	second := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostChannelFeed, ID: intent.ChannelID, Limit: 2, Cursor: *first.NextCursor}).(posts.FeedPage)
	seen := map[string]bool{}
	for _, p := range append(first.Items, second.Items...) {
		if p.PostID == later.PostID || seen[p.PostID] {
			t.Fatal("page inserted new publication or duplicate")
		}
		seen[p.PostID] = true
	}
	if len(seen) != 4 || second.NextCursor != nil {
		t.Fatal("page lost snapshot items")
	}
	for _, query := range []PostQuery{{Kind: PostOwnList, Limit: 2, Cursor: *first.NextCursor}, {Kind: PostChannelFeed, ID: intent.ChannelID, Limit: 1, Cursor: *first.NextCursor}} {
		_, err := l.c.ReadPosts(ctx, owner.SessionToken, query)
		if !errors.Is(err, posts.ErrCursorInvalid) {
			t.Fatal("cursor scope or limit changed", err)
		}
	}
	_, err := l.c.ReadPosts(ctx, foreign.SessionToken, PostQuery{Kind: PostChannelFeed, ID: intent.ChannelID, Limit: 2, Cursor: *first.NextCursor})
	if !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("cursor crossed accounts", err)
	}
	advanceClosureClock(t, control, control.clock.now().Add(30*time.Minute))
	_, err = l.c.ReadPosts(ctx, owner.SessionToken, PostQuery{Kind: PostChannelFeed, ID: intent.ChannelID, Limit: 2, Cursor: *first.NextCursor})
	if !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("expired cursor accepted", err)
	}
}

func TestPostGateFreezeAndStaleSessionFinalAuthorizationPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "post_gate_owner")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "冻结身份").IdentityID
	intent := postTestIntent(t, l, id)
	accepted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	barrier := &identitySnapshotBarrier{AuthorizationGate: l.c.gate, captured: make(chan struct{}), release: make(chan struct{})}
	stale := *l.c
	stale.gate = barrier
	done := make(chan error, 1)
	go func() {
		_, err := stale.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), intent)
		done <- err
	}()
	<-barrier.captured
	if _, err := l.c.CreateSession(ctx, sessionTestRequest(t, "post_gate_owner"), sessionTestPasswordWorker(t, 1)); err != nil {
		t.Fatal(err)
	}
	close(barrier.release)
	if err := <-done; !errors.Is(err, ErrSessionReplaced) {
		t.Fatal("stale final session authorized", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts`) != 1 {
		t.Fatal("stale request had business effect")
	}
	if err := l.gate.Freeze(ctx, "post test freeze"); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.PublishAcceptedPosts(ctx, 100); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("worker bypassed frozen gate", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.publication_attempts WHERE task_id=$1 AND state='ACCEPTED'`, accepted.TaskID) != 1 {
		t.Fatal("freeze destroyed queued attempt")
	}
}

func TestPostBanExpiryAndHideNeverRestoreTaskPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "post_ban_owner")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "封禁身份").IdentityID
	accepted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id))
	ends := control.clock.now().Add(time.Minute)
	if err := l.c.ApplyAccountBan(ctx, owner.AccountID, 1, &ends); err != nil {
		t.Fatal(err)
	}
	postTestPublish(t, l)
	advanceClosureClock(t, control, ends)
	login, err := l.c.CreateSession(ctx, sessionTestRequest(t, "post_ban_owner"), sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	postTestPublish(t, l)
	failed := postTestRead(t, l, login.SessionToken, PostQuery{Kind: PostTaskDetail, ID: accepted.TaskID}).(posts.OwnTaskDetail)
	if failed.Task.State != posts.Failed || !failed.Task.CanRetry || count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE visibility='PUBLISHED'`) != 0 {
		t.Fatal("ban expiry revived original attempt")
	}
	hide := posts.Intent{Operation: posts.HideTask, TaskID: accepted.TaskID, ExpectedAttemptVersion: 1}
	key := postTestKey(t)
	if r := postTestCommand(t, l, login.SessionToken, key, hide); r.State != "COMMITTED" {
		t.Fatal("hide not committed")
	}
	if len(postTestRead(t, l, login.SessionToken, PostQuery{Kind: PostTaskList}).(posts.OwnTaskList).Items) != 0 {
		t.Fatal("hidden task still listed")
	}
	detail := postTestRead(t, l, login.SessionToken, PostQuery{Kind: PostTaskDetail, ID: accepted.TaskID}).(posts.OwnTaskDetail)
	if detail.Task.Visible || detail.Task.ContentAvailable || detail.Content != nil || detail.Task.CanRetry {
		t.Fatal("hidden task retained payload/capability")
	}
	retry := posts.Intent{Operation: posts.Retry, TaskID: accepted.TaskID, ExpectedAttemptVersion: 1, Title: "隐藏后", Body: "禁止恢复"}
	if r := postTestCommand(t, l, login.SessionToken, postTestKey(t), retry); r.ErrorCode != "TASK_NOT_RETRYABLE" {
		t.Fatal("hidden task revived")
	}
	if _, err = l.c.CleanupPostPayloads(ctx, 100); err != nil {
		t.Fatal(err)
	}
	if r, err := l.c.GetPostCommand(ctx, login.SessionToken, key); err != nil || r.Value.(posts.CommandResult).State != "COMMITTED" {
		t.Fatal("hide cleanup lost command fact")
	}
}

func TestPostTaskCursorRetryCeilingPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "post_task_cursor")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "任务分页").IdentityID
	intent := postTestIntent(t, l, id)
	for n := 0; n < 4; n++ {
		postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	}
	first := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostTaskList, Limit: 2}).(posts.OwnTaskList)
	if len(first.Items) != 2 || first.NextCursor == nil {
		t.Fatal("missing task cursor")
	}
	ends := control.clock.now().Add(time.Minute)
	if err := l.c.ApplyAccountMute(ctx, owner.AccountID, 1, &ends); err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, ends)
	all := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostTaskList}).(posts.OwnTaskList)
	last := all.Items[3].Task
	retry := posts.Intent{Operation: posts.Retry, TaskID: last.TaskID, ExpectedAttemptVersion: 1, Title: "翻页后重试", Body: "刷新才能出现"}
	if r := postTestCommand(t, l, owner.SessionToken, postTestKey(t), retry); r.State != "ACCEPTED" {
		t.Fatal("retry failed")
	}
	second := postTestRead(t, l, owner.SessionToken, PostQuery{Kind: PostTaskList, Limit: 2, Cursor: *first.NextCursor}).(posts.OwnTaskList)
	if len(second.Items) != 1 {
		t.Fatal("task page reintroduced retry above ceiling")
	}
	for _, item := range second.Items {
		if item.Task.TaskID == last.TaskID {
			t.Fatal("later retry appeared in existing cursor")
		}
	}
	_, err := l.c.ReadPosts(ctx, owner.SessionToken, PostQuery{Kind: PostChannelFeed, ID: intent.ChannelID, Limit: 2, Cursor: *first.NextCursor})
	if !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("task cursor crossed public feed")
	}
}

func TestPostProtocolKeysCannotLoseHistoricalDomainPostgres(t *testing.T) {
	for _, purpose := range []string{"command", "fingerprint", "missing"} {
		t.Run(purpose, func(t *testing.T) {
			control := newGateControl(t)
			l, ctx := control.lab, context.Background()
			config := enablePostLab(t, l)
			owner := sessionTestAccount(t, l, "post_key_integrity")
			id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "密钥历史").IdentityID
			key := postTestKey(t)
			intent := postTestIntent(t, l, id)
			accepted := postTestCommand(t, l, owner.SessionToken, key, intent)
			if _, err := l.c.WithPosts(ctx, config); err != nil {
				t.Fatal("same keys could not restart", err)
			}
			wrong := config
			switch purpose {
			case "command":
				wrong.KeyKey[0] ^= 1
			case "fingerprint":
				wrong.FingerprintKey[0] ^= 1
			case "missing":
				// 模拟恢复材料丢失；只在归属已验证的一次性owner库中绕过guard。
				mustExec(t, l.cp, `ALTER TABLE c_posts.protocol_keys DISABLE TRIGGER post_protocol_keys_immutable`)
				mustExec(t, l.cp, `DELETE FROM c_posts.protocol_keys`)
				mustExec(t, l.cp, `ALTER TABLE c_posts.protocol_keys ENABLE TRIGGER post_protocol_keys_immutable`)
			}
			if _, err := l.c.WithPosts(ctx, wrong); !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatal("changed/lost protocol key accepted", err)
			}
			assertFrozen(t, control)
			if count(t, l.cp, `SELECT count(*) FROM c_posts.posts`) != 1 || count(t, l.cp, `SELECT count(*) FROM c_posts.command_receipts`) != 1 {
				t.Fatal("integrity rejection changed command facts")
			}
			if purpose != "missing" {
				if _, err := l.c.WithPosts(ctx, config); err != nil {
					t.Fatal("matching key check blocked frozen startup", err)
				}
				control.recover(t, AuthorizationRecoveryNormal, 3, 3)
				postTestPublish(t, l)
				login, err := l.c.CreateSession(ctx, sessionTestRequest(t, "post_key_integrity"), sessionTestPasswordWorker(t, 1))
				if err != nil {
					t.Fatal(err)
				}
				if r := postTestCommand(t, l, login.SessionToken, key, intent); r != accepted {
					t.Fatal("restored keys duplicated original task")
				}
				postTestPublish(t, l)
				if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE visibility='PUBLISHED'`) != 1 {
					t.Fatal("restored keys lost worker task")
				}
			}
		})
	}
}

func TestPostBudgetAndLiveTaskLimitPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "post_capacity_owner")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "预算身份").IdentityID
	intent := postTestIntent(t, l, id)
	for n := 0; n < 120; n++ {
		if r := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent); r.State != "ACCEPTED" {
			t.Fatal("budget rejected valid acceptance")
		}
	}
	_, err := l.c.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), intent)
	postTestError(t, err, "RATE_LIMITED", 429)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.command_receipts`) != 120 {
		t.Fatal("rate rejection persisted command")
	}
	advanceClosureClock(t, control, control.clock.now().Add(time.Minute))
	for n := 0; n < 8; n++ {
		postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	}
	_, err = l.c.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), intent)
	postTestError(t, err, "RATE_LIMITED", 429)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.publication_tasks`) != 128 {
		t.Fatal("live capacity exceeded")
	}
	postTestPublish(t, l)
	postTestPublish(t, l)
	if r := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent); r.State != "ACCEPTED" {
		t.Fatal("publication did not free live budget")
	}
}
