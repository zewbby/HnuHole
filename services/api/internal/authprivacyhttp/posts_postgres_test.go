package authprivacyhttp

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

// 通过实际 TLS handler 和一次性 PG 走业务；失败只打印状态和路径，不打印凭据或正文。
func postHTTPSJSON(t *testing.T, s *e2eServices, method, path, token, key string, body any, status int) map[string]any {
	t.Helper()
	var input io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatal("unable to encode synthetic post input")
		}
		input = bytes.NewReader(encoded)
	}
	r, err := http.NewRequest(method, s.cPublic.URL+path, input)
	if err != nil {
		t.Fatal("unable to construct synthetic request")
	}
	r.Header.Set("Authorization", "Bearer "+token)
	if key != "" {
		r.Header.Set("Idempotency-Key", key)
	}
	if body != nil {
		r.Header.Set("Content-Type", "application/json")
	}
	response, err := s.client.Do(r)
	if err != nil {
		t.Fatal("post HTTPS transport failed")
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 262144))
	if err != nil {
		t.Fatal("post HTTPS response unreadable")
	}
	if response.StatusCode != status {
		t.Fatalf("%s %s status=%d want=%d", method, r.URL.Path, response.StatusCode, status)
	}
	if response.Header.Get("Cache-Control") != "no-store" || response.Header.Get("X-Request-ID") == "" {
		t.Fatal("post response missing private envelope")
	}
	if status == 200 || status == 202 {
		expires, e1 := time.Parse(time.RFC3339Nano, response.Header.Get("Session-Expires-At"))
		at, e2 := time.Parse(time.RFC3339Nano, response.Header.Get("Server-Time"))
		if e1 != nil || e2 != nil || !expires.After(at) {
			t.Fatal("post success lacks final authority headers")
		}
	} else if response.Header.Get("Session-Expires-At") != "" || response.Header.Get("Server-Time") != "" {
		t.Fatal("post error changed session authority")
	}
	var result map[string]any
	if json.Unmarshal(data, &result) != nil {
		t.Fatal("post response malformed JSON")
	}
	return result
}

func postHTTPSChannel(t *testing.T, s *e2eServices, token string) string {
	t.Helper()
	catalog := e2eJSON(t, s.client, "GET", s.cPublic.URL+"/api/v1/channels", nil, map[string]string{"Authorization": "Bearer " + token}, 200)
	items, ok := catalog["channels"].([]any)
	if !ok || len(items) == 0 {
		t.Fatal("missing real channel catalog")
	}
	return items[0].(map[string]any)["id"].(string)
}

func postHTTPSIdentity(t *testing.T, s *e2eServices, token, name string, key byte) string {
	t.Helper()
	result := e2eJSON(t, s.client, "POST", s.cPublic.URL+identitiesPath, map[string]string{"nickname": name}, map[string]string{"Authorization": "Bearer " + token, "Idempotency-Key": httpTestEncoding(16, key)}, 200)
	return result["identityId"].(string)
}

func postHTTPSFields(t *testing.T, value map[string]any, names ...string) {
	t.Helper()
	if len(value) != len(names) {
		t.Fatal("post DTO contains unexpected/missing fields")
	}
	for _, name := range names {
		if _, ok := value[name]; !ok {
			t.Fatalf("post DTO missing %s", name)
		}
	}
}

func postHTTPSPublic(t *testing.T, value map[string]any, detail bool) {
	t.Helper()
	if detail {
		postHTTPSFields(t, value, "postId", "channelId", "title", "body", "author", "publishedAt")
	} else {
		postHTTPSFields(t, value, "postId", "channelId", "title", "author", "publishedAt")
	}
	author := value["author"].(map[string]any)
	if author["state"] == "ACTIVE" {
		postHTTPSFields(t, author, "state", "nickname", "avatar")
	} else {
		postHTTPSFields(t, author, "state", "shortCode", "avatar")
	}
}

func TestRealHTTPSPostAcceptancePublicationReadAndDeletePostgres(t *testing.T) {
	s := e2eNewServices(t)
	token, account := e2ePrivacySignup(t, s, "post_https_owner")
	foreignToken, foreignAccount := e2ePrivacySignup(t, s, "post_https_other")
	if account == foreignAccount {
		t.Fatal("accounts not independent")
	}
	channel := postHTTPSChannel(t, s, token)
	missingChannel := uuid.NewString()
	missing := postHTTPSJSON(t, s, "GET", "/api/v1/channels/"+missingChannel+"/posts", token, "", nil, 404)
	if missing["error"].(map[string]any)["code"] != "POST_CHANNEL_UNAVAILABLE" {
		t.Fatal("missing channel read did not preserve contract error")
	}
	feed := postHTTPSJSON(t, s, "GET", "/api/v1/channels/"+channel+"/posts", token, "", nil, 200)
	if len(feed["items"].([]any)) != 0 {
		t.Fatal("fresh feed nonempty")
	}
	composer := postHTTPSJSON(t, s, "GET", "/api/v1/me/post-composer-context", token, "", nil, 200)
	if composer["selectionState"] != "INITIAL_SETUP_REQUIRED" || composer["defaultIdentityId"] != nil {
		t.Fatal("zero identity context incorrect")
	}
	id := postHTTPSIdentity(t, s, token, "发表身份", 61)
	composer = postHTTPSJSON(t, s, "GET", "/api/v1/me/post-composer-context", token, "", nil, 200)
	if composer["selectionState"] != "DEFAULT_AVAILABLE" || composer["defaultIdentityId"] != id {
		t.Fatal("initial identity default missing")
	}
	body := posts.CreatePostInput{ChannelID: channel, IdentityID: id, Title: "文字闭环", Body: "保留原文\r\n👨‍👩‍👧‍👦 e\u0301 "}
	unavailable := body
	unavailable.ChannelID = missingChannel
	missing = postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 65), token, "", unavailable, 409)
	if missing["error"].(map[string]any)["code"] != "POST_CHANNEL_UNAVAILABLE" {
		t.Fatal("missing channel create did not preserve durable rejection")
	}
	key := httpTestEncoding(16, 62)
	unknown := postHTTPSJSON(t, s, "GET", "/api/v1/post-commands/"+key, token, "", nil, 200)
	postHTTPSFields(t, unknown, "state")
	if unknown["state"] != "UNKNOWN_NOT_OBSERVED" {
		t.Fatal("absent command became terminal")
	}
	accepted := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+key, token, "", body, 202)
	postHTTPSFields(t, accepted, "state", "operation", "taskId", "postId", "attemptVersion")
	if accepted["state"] != "ACCEPTED" || accepted["operation"] != "CREATE" || accepted["attemptVersion"] != float64(1) {
		t.Fatal("create not accepted")
	}
	task, post := accepted["taskId"].(string), accepted["postId"].(string)
	replay := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+key, token, "", body, 202)
	if !reflect.DeepEqual(replay, accepted) {
		t.Fatal("same command response not original")
	}
	query := postHTTPSJSON(t, s, "GET", "/api/v1/post-commands/"+key, token, "", nil, 200)
	if !reflect.DeepEqual(query, accepted) {
		t.Fatal("query did not return original")
	}
	digest, err := posts.RequestDigest(posts.Intent{Operation: posts.Create, ChannelID: channel, IdentityID: id, Title: body.Title, Body: body.Body})
	if err != nil {
		t.Fatal(err)
	}
	sealed := postHTTPSJSON(t, s, "POST", "/api/v1/post-commands/"+key+"/seal", token, "", posts.SealInput{Operation: posts.Create, RequestDigest: hex.EncodeToString(digest[:])}, 200)
	if !reflect.DeepEqual(sealed, accepted) {
		t.Fatal("seal changed accepted fact")
	}
	changed := body
	changed.Body = "改变的原文"
	conflict := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+key, token, "", changed, 409)
	if conflict["error"].(map[string]any)["code"] != "COMMAND_CONFLICT" {
		t.Fatal("different payload replay not conflicted")
	}
	detail := postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks/"+task, token, "", nil, 200)
	if detail["task"].(map[string]any)["state"] != "ACCEPTED" || detail["content"].(map[string]any)["body"] != body.Body {
		t.Fatal("accepted private original differs")
	}
	list := postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks?limit=1", token, "", nil, 200)
	if len(list["items"].([]any)) != 1 {
		t.Fatal("pending card missing")
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post, token, "", nil, 404)
	postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks/"+task, foreignToken, "", nil, 404)
	foreign := postHTTPSJSON(t, s, "GET", "/api/v1/post-commands/"+key, foreignToken, "", nil, 200)
	if foreign["state"] != "UNKNOWN_NOT_OBSERVED" {
		t.Fatal("shared key disclosed another account")
	}
	if _, err = s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal("post worker failed")
	}
	if _, err = s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal("duplicate worker failed")
	}
	detail = postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks/"+task, token, "", nil, 200)
	if detail["task"].(map[string]any)["state"] != "PUBLISHED" || detail["task"].(map[string]any)["visible"] != false {
		t.Fatal("published private reconciliation incorrect")
	}
	list = postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks", token, "", nil, 200)
	if len(list["items"].([]any)) != 0 {
		t.Fatal("published task retained pending card")
	}
	feed = postHTTPSJSON(t, s, "GET", "/api/v1/channels/"+channel+"/posts?limit=1", foreignToken, "", nil, 200)
	if len(feed["items"].([]any)) != 1 {
		t.Fatal("publication duplicated/missing")
	}
	card := feed["items"].([]any)[0].(map[string]any)
	postHTTPSPublic(t, card, false)
	public := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post, foreignToken, "", nil, 200)
	postHTTPSFields(t, public, "post")
	postHTTPSPublic(t, public["post"].(map[string]any), true)
	if public["post"].(map[string]any)["body"] != body.Body || public["post"].(map[string]any)["author"].(map[string]any)["nickname"] != "发表身份" {
		t.Fatal("public content/binding changed")
	}
	for _, value := range []map[string]any{feed, public} {
		encoded, _ := json.Marshal(value)
		if strings.Contains(string(encoded), account) || strings.Contains(string(encoded), id) {
			t.Fatal("public DTO leaked caller linkage")
		}
	}
	me := postHTTPSJSON(t, s, "GET", "/api/v1/me/posts", token, "", nil, 200)
	if len(me["items"].([]any)) != 1 {
		t.Fatal("own published card missing")
	}
	caps := postHTTPSJSON(t, s, "GET", "/api/v1/me/posts/"+post+"/capabilities", token, "", nil, 200)
	postHTTPSFields(t, caps, "postId", "canDelete", "canEdit")
	if caps["canDelete"] != true || caps["canEdit"] != false {
		t.Fatal("minimal author capability incorrect")
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/me/posts/"+post+"/capabilities", foreignToken, "", nil, 404)
	postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+post+"/delete", foreignToken, httpTestEncoding(16, 63), nil, 404)
	deleted := postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+post+"/delete", token, httpTestEncoding(16, 64), nil, 200)
	postHTTPSFields(t, deleted, "state", "operation", "postId")
	if deleted["state"] != "COMMITTED" || deleted["operation"] != "DELETE_POST" {
		t.Fatal("author deletion not committed")
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post, token, "", nil, 404)
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post, foreignToken, "", nil, 404)
	feed = postHTTPSJSON(t, s, "GET", "/api/v1/channels/"+channel+"/posts", foreignToken, "", nil, 200)
	if len(feed["items"].([]any)) != 0 {
		t.Fatal("deleted body retained in feed")
	}
	query = postHTTPSJSON(t, s, "GET", "/api/v1/post-commands/"+key, token, "", nil, 200)
	if !reflect.DeepEqual(query, accepted) {
		t.Fatal("deletion rewrote acceptance history")
	}
}

func TestRealHTTPSPostStopsRetryHideCancelAndSealPostgres(t *testing.T) {
	s := e2eNewServices(t)
	token, account := e2ePrivacySignup(t, s, "post_https_stops")
	channel := postHTTPSChannel(t, s, token)
	id := postHTTPSIdentity(t, s, token, "停止身份", 71)
	body := posts.CreatePostInput{ChannelID: channel, IdentityID: id, Title: "待发表", Body: "必须核对停止事实"}
	first := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 72), token, "", body, 202)
	second := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 73), token, "", body, 202)
	decision, err := s.gate.Snapshot(context.Background())
	if err != nil {
		t.Fatal("gate snapshot unavailable")
	}
	ends := decision.TrustedAt.Add(time.Hour)
	if err = s.c.ApplyAccountMute(context.Background(), uuid.MustParse(account), 1, &ends); err != nil {
		t.Fatal("trusted mute failed")
	}
	task := first["taskId"].(string)
	detail := postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks/"+task, token, "", nil, 200)
	state := detail["task"].(map[string]any)
	if state["state"] != "FAILED" || state["failureCode"] != "PUBLISHING_STOPPED" || state["canRetry"] != false || state["canHide"] != true {
		t.Fatal("mute stop projection incorrect")
	}
	restricted := postHTTPSJSON(t, s, "POST", "/api/v1/me/post-tasks/"+task+"/retry", token, httpTestEncoding(16, 74), posts.RetryInput{ExpectedAttemptVersion: 1, Title: "修改标题", Body: "修改正文"}, 409)
	if restricted["error"].(map[string]any)["code"] != "POSTING_RESTRICTED" {
		t.Fatal("mute bypassed retry authorization")
	}
	if _, err = s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal("stopped worker failed")
	}
	s.advanceC(2 * time.Hour)
	retried := postHTTPSJSON(t, s, "POST", "/api/v1/me/post-tasks/"+task+"/retry", token, httpTestEncoding(16, 75), posts.RetryInput{ExpectedAttemptVersion: 1, Title: "修改标题", Body: "修改正文"}, 202)
	if retried["taskId"] != task || retried["postId"] != first["postId"] || retried["attemptVersion"] != float64(2) {
		t.Fatal("retry replaced original binding/task")
	}
	detail = postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks/"+task, token, "", nil, 200)
	if detail["task"].(map[string]any)["identityId"] != id || detail["task"].(map[string]any)["channelId"] != channel {
		t.Fatal("retry changed speaking identity/channel")
	}
	cancelled := postHTTPSJSON(t, s, "POST", "/api/v1/me/post-tasks/"+task+"/cancel", token, httpTestEncoding(16, 76), posts.AttemptVersionInput{ExpectedAttemptVersion: 2}, 200)
	postHTTPSFields(t, cancelled, "state", "operation", "taskId", "attemptVersion", "taskState")
	if cancelled["taskState"] != "CANCELLED" {
		t.Fatal("cancel did not win before publication")
	}
	if _, err = s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal("cancelled worker failed")
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+first["postId"].(string), token, "", nil, 404)
	detail = postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks/"+task, token, "", nil, 200)
	if detail["content"] != nil || detail["task"].(map[string]any)["contentAvailable"] != false {
		t.Fatal("cancelled private text retained API visibility")
	}
	hiddenTask := second["taskId"].(string)
	hidden := postHTTPSJSON(t, s, "POST", "/api/v1/me/post-tasks/"+hiddenTask+"/hide", token, httpTestEncoding(16, 77), posts.AttemptVersionInput{ExpectedAttemptVersion: 1}, 200)
	postHTTPSFields(t, hidden, "state", "operation", "taskId", "attemptVersion")
	detail = postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks/"+hiddenTask, token, "", nil, 200)
	if detail["task"].(map[string]any)["visible"] != false || detail["content"] != nil {
		t.Fatal("hidden failure reconstructed old content/card")
	}
	list := postHTTPSJSON(t, s, "GET", "/api/v1/me/post-tasks", token, "", nil, 200)
	if len(list["items"].([]any)) != 0 {
		t.Fatal("hidden/cancelled cards returned")
	}
	sealedKey := httpTestEncoding(16, 78)
	digest, err := posts.RequestDigest(posts.Intent{Operation: posts.Create, ChannelID: channel, IdentityID: id, Title: body.Title, Body: body.Body})
	if err != nil {
		t.Fatal(err)
	}
	seal := postHTTPSJSON(t, s, "POST", "/api/v1/post-commands/"+sealedKey+"/seal", token, "", posts.SealInput{Operation: posts.Create, RequestDigest: hex.EncodeToString(digest[:])}, 200)
	if seal["state"] != "NOT_ACCEPTED" || seal["reason"] != "COMMAND_SEALED" {
		t.Fatal("seal did not establish absent terminal fact")
	}
	delayed := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+sealedKey, token, "", body, 409)
	if delayed["error"].(map[string]any)["code"] != "COMMAND_SEALED" {
		t.Fatal("late create crossed seal")
	}
	observed := postHTTPSJSON(t, s, "GET", "/api/v1/post-commands/"+sealedKey, token, "", nil, 200)
	if !reflect.DeepEqual(observed, seal) {
		t.Fatal("sealed original fact lost")
	}
}
