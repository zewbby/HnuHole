package authprivacyhttp

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

const (
	postHTTPTask     = "11111111-1111-4111-8111-111111111111"
	postHTTPPost     = "22222222-2222-4222-8222-222222222222"
	postHTTPChannel  = "33333333-3333-4333-8333-333333333333"
	postHTTPIdentity = "44444444-4444-4444-8444-444444444444"
)

var postHTTPTime = time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)

// 替身只证明 HTTP 解析和 DTO 边界；SQL/Gate/归属由独立真实数据库测试证明。
type postHTTPBackend struct {
	calls                 int
	method, command       string
	intent                posts.Intent
	query                 authprivacy.PostQuery
	seal                  posts.SealInput
	bearer                [32]byte
	value                 any
	err                   error
	expiresAt, serverTime time.Time
}

func (f *postHTTPBackend) response(value any) (authprivacy.PostResponse, error) {
	if f.value != nil {
		value = f.value
	}
	expiresAt, serverTime := f.expiresAt, f.serverTime
	if expiresAt.IsZero() {
		expiresAt = postHTTPTime.Add(24 * time.Hour)
	}
	if serverTime.IsZero() {
		serverTime = postHTTPTime
	}
	return authprivacy.PostResponse{Value: value, ExpiresAt: expiresAt, ServerTime: serverTime}, f.err
}

func (f *postHTTPBackend) ExecutePostCommand(_ context.Context, bearer [32]byte, command string, intent posts.Intent) (authprivacy.PostResponse, error) {
	f.calls++
	f.method, f.command, f.bearer, f.intent = "execute", command, bearer, intent
	result := posts.CommandResult{Operation: intent.Operation, TaskID: postHTTPTask, PostID: postHTTPPost, AttemptVersion: 1}
	switch intent.Operation {
	case posts.Create:
		result.State = "ACCEPTED"
	case posts.Retry:
		result.State, result.TaskID, result.AttemptVersion = "ACCEPTED", intent.TaskID, intent.ExpectedAttemptVersion+1
	case posts.Cancel:
		result.State, result.TaskID, result.AttemptVersion, result.TaskState = "COMMITTED", intent.TaskID, intent.ExpectedAttemptVersion, posts.Cancelled
	case posts.HideTask:
		result.State, result.TaskID, result.AttemptVersion = "COMMITTED", intent.TaskID, intent.ExpectedAttemptVersion
	case posts.DeletePost:
		result.State, result.PostID = "COMMITTED", intent.PostID
	}
	return f.response(result)
}

func (f *postHTTPBackend) GetPostCommand(_ context.Context, bearer [32]byte, command string) (authprivacy.PostResponse, error) {
	f.calls++
	f.method, f.command, f.bearer = "get", command, bearer
	return f.response(posts.CommandResult{State: "UNKNOWN_NOT_OBSERVED"})
}

func (f *postHTTPBackend) SealPostCommand(_ context.Context, bearer [32]byte, command string, input posts.SealInput) (authprivacy.PostResponse, error) {
	f.calls++
	f.method, f.command, f.bearer, f.seal = "seal", command, bearer, input
	return f.response(posts.CommandResult{State: "NOT_ACCEPTED", Operation: input.Operation, Reason: "COMMAND_SEALED"})
}

func postHTTPCard() posts.PublicPostCard {
	return posts.PublicPostCard{PostID: postHTTPPost, ChannelID: postHTTPChannel, Title: "原始标题", Author: posts.PublicAuthor{State: "ACTIVE", Nickname: "当前身份", Avatar: "default-v1"}, PublishedAt: postHTTPTime}
}

func postHTTPTaskDetail() posts.OwnTaskDetail {
	return posts.OwnTaskDetail{Task: posts.OwnTaskSummary{TaskID: postHTTPTask, PostID: postHTTPPost, ChannelID: postHTTPChannel, IdentityID: postHTTPIdentity, AttemptVersion: 1, State: posts.Accepted, AcceptedAt: postHTTPTime, ServerSortAt: postHTTPTime, Visible: true, ContentAvailable: true, CanCancel: true}, Content: &posts.OwnTaskContent{Title: "原始标题", Body: " 原文\r\n👨‍👩‍👦 e\u0301 "}}
}

func (f *postHTTPBackend) ReadPosts(_ context.Context, bearer [32]byte, query authprivacy.PostQuery) (authprivacy.PostResponse, error) {
	f.calls++
	f.method, f.bearer, f.query = "read", bearer, query
	var value any
	switch query.Kind {
	case authprivacy.PostComposerContext:
		id := postHTTPIdentity
		value = posts.ComposerContext{SelectionState: "DEFAULT_AVAILABLE", DefaultIdentityID: &id}
	case authprivacy.PostTaskDetail:
		value = postHTTPTaskDetail()
	case authprivacy.PostTaskList:
		value = posts.OwnTaskList{Items: []posts.OwnTaskDetail{postHTTPTaskDetail()}}
	case authprivacy.PostChannelFeed:
		value = posts.FeedPage{Items: []posts.PublicPostCard{postHTTPCard()}}
	case authprivacy.PostDetail:
		card := postHTTPCard()
		value = posts.PublicPostResponse{Post: posts.PublicPost{PostID: card.PostID, ChannelID: card.ChannelID, Title: card.Title, Body: " 原文\r\n👨‍👩‍👦 e\u0301 ", Author: card.Author, PublishedAt: card.PublishedAt}}
	case authprivacy.PostOwnList:
		value = posts.OwnPostPage{Items: []posts.OwnPostCard{{Post: postHTTPCard(), ServerSortAt: postHTTPTime}}}
	case authprivacy.PostCapabilities:
		value = posts.OwnPostCapabilities{PostID: query.ID, CanDelete: true}
	}
	return f.response(value)
}

func newPostHTTP(t *testing.T, limits NetworkLimits) (*postHTTPBackend, http.Handler) {
	t.Helper()
	pki := newHTTPTestPKI(t)
	community := &httpTestCommunity{}
	f := &postHTTPBackend{}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{Posts: f, Backend: community, Passwords: httpTestPasswords{backend: community}, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: limits, AllowedOrigins: []string{"https://client.example"}})
	if err != nil {
		t.Fatal(err)
	}
	return f, endpoints.Public
}

func postHTTPRequest(handler http.Handler, method, path, body string, headers http.Header) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "https://c.example"+path, strings.NewReader(body))
	r.TLS = &tls.ConnectionState{Version: tls.VersionTLS13, HandshakeComplete: true}
	r.RemoteAddr = "127.0.0.1:12345"
	r.Header = headers
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)
	return w
}

func postHTTPHeaders(mutation bool) http.Header {
	h := http.Header{"Authorization": {"Bearer " + httpTestEncoding(32, 7)}, "Content-Type": {"application/json"}}
	if mutation {
		h.Set("Idempotency-Key", httpTestEncoding(16, 8))
	}
	return h
}

func postHTTPCreateBody() string {
	return `{"channelId":"` + postHTTPChannel + `","identityId":"` + postHTTPIdentity + `","title":" 原题 ","body":" 原文\r\n👨‍👩‍👦 e\u0301 "}`
}

func postHTTPCheckError(t *testing.T, w *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	if w.Code != status {
		t.Fatalf("status=%d want=%d body=%s", w.Code, status, w.Body.String())
	}
	var value map[string]json.RawMessage
	if err := json.Unmarshal(w.Body.Bytes(), &value); err != nil {
		t.Fatal(err)
	}
	if len(value) != 2 || value["requestId"] == nil || value["error"] == nil {
		t.Fatalf("not closed error DTO: %s", w.Body.String())
	}
	var failure map[string]any
	if err := json.Unmarshal(value["error"], &failure); err != nil {
		t.Fatal(err)
	}
	if len(failure) != 2 || failure["code"] != code || failure["message"] == "" {
		t.Fatalf("not closed public error: %s", w.Body.String())
	}
	if w.Header().Get("Session-Expires-At") != "" || w.Header().Get("Server-Time") != "" {
		t.Fatal("failure renewed session or sent trusted deadline")
	}
	if w.Header().Get("Cache-Control") != "no-store" || w.Header().Get("X-Request-ID") == "" {
		t.Fatal("missing independent no-store envelope")
	}
}

func TestPostHTTPAllFourteenOperations(t *testing.T) {
	key := httpTestEncoding(16, 8)
	cases := []struct {
		name, method, path, body, backend string
		operation                         posts.Operation
		kind                              authprivacy.PostReadKind
		status                            int
		headerKey                         bool
	}{
		{"create", "PUT", "/api/v1/post-commands/" + key, postHTTPCreateBody(), "execute", posts.Create, "", 202, false},
		{"reconcile", "GET", "/api/v1/post-commands/" + key, "", "get", "", "", 200, false},
		{"seal", "POST", "/api/v1/post-commands/" + key + "/seal", `{"operation":"CREATE","requestDigest":"` + strings.Repeat("a", 64) + `"}`, "seal", "", "", 200, false},
		{"composer", "GET", "/api/v1/me/post-composer-context", "", "read", "", authprivacy.PostComposerContext, 200, false},
		{"tasks", "GET", "/api/v1/me/post-tasks?limit=1", "", "read", "", authprivacy.PostTaskList, 200, false},
		{"task", "GET", "/api/v1/me/post-tasks/" + postHTTPTask, "", "read", "", authprivacy.PostTaskDetail, 200, false},
		{"cancel", "POST", "/api/v1/me/post-tasks/" + postHTTPTask + "/cancel", `{"expectedAttemptVersion":1}`, "execute", posts.Cancel, "", 200, true},
		{"retry", "POST", "/api/v1/me/post-tasks/" + postHTTPTask + "/retry", `{"expectedAttemptVersion":1,"title":"新题","body":"新文"}`, "execute", posts.Retry, "", 202, true},
		{"hide", "POST", "/api/v1/me/post-tasks/" + postHTTPTask + "/hide", `{"expectedAttemptVersion":1}`, "execute", posts.HideTask, "", 200, true},
		{"channel", "GET", "/api/v1/channels/" + postHTTPChannel + "/posts?cursor=AQ&limit=1", "", "read", "", authprivacy.PostChannelFeed, 200, false},
		{"detail", "GET", "/api/v1/posts/" + postHTTPPost, "", "read", "", authprivacy.PostDetail, 200, false},
		{"own", "GET", "/api/v1/me/posts?limit=1", "", "read", "", authprivacy.PostOwnList, 200, false},
		{"capabilities", "GET", "/api/v1/me/posts/" + postHTTPPost + "/capabilities", "", "read", "", authprivacy.PostCapabilities, 200, false},
		{"delete", "POST", "/api/v1/posts/" + postHTTPPost + "/delete", "", "execute", posts.DeletePost, "", 200, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f, handler := newPostHTTP(t, httpTestLimits())
			w := postHTTPRequest(handler, c.method, c.path, c.body, postHTTPHeaders(c.headerKey))
			if w.Code != c.status || f.calls != 1 || f.method != c.backend || c.operation != "" && f.intent.Operation != c.operation || c.kind != "" && f.query.Kind != c.kind {
				t.Fatalf("status=%d calls=%d method=%s body=%s", w.Code, f.calls, f.method, w.Body.String())
			}
			if f.bearer != [32]byte{7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7} {
				t.Fatal("bearer changed")
			}
			if w.Header().Get("Session-Expires-At") != utc(postHTTPTime.Add(24*time.Hour)) || w.Header().Get("Server-Time") != utc(postHTTPTime) || w.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("missing successful committed headers")
			}
			if c.name == "create" && (f.command != key || f.intent.Title != " 原题 " || f.intent.Body != " 原文\r\n👨‍👩‍👦 e\u0301 ") {
				t.Fatal("input original bytes changed")
			}
			if c.name == "channel" && (f.query.Cursor != "AQ" || f.query.Limit != 1 || f.query.ID != postHTTPChannel) {
				t.Fatal("query changed")
			}
			if c.name == "detail" || c.name == "channel" {
				for _, secret := range []string{"accountId", "identityId", "owner", "canDelete", "canEdit", "slot", "isOriginal"} {
					if strings.Contains(w.Body.String(), `"`+secret+`"`) {
						t.Fatalf("public DTO leaked %s", secret)
					}
				}
			}
		})
	}
}

func TestPostHTTPRejectsMalformedCreateBeforeBackend(t *testing.T) {
	cases := []struct {
		name, body string
		status     int
	}{
		{"duplicate", `{"channelId":"` + postHTTPChannel + `","channelId":"` + postHTTPChannel + `","identityId":"` + postHTTPIdentity + `","title":"题","body":"文"}`, 400},
		{"escaped-duplicate", `{"channelId":"` + postHTTPChannel + `","\u0063hannelId":"` + postHTTPChannel + `","identityId":"` + postHTTPIdentity + `","title":"题","body":"文"}`, 400},
		{"unknown", strings.TrimSuffix(postHTTPCreateBody(), "}") + `,"accountId":"private"}`, 400},
		{"wrong-case", strings.Replace(postHTTPCreateBody(), `"title"`, `"Title"`, 1), 400},
		{"null", strings.Replace(postHTTPCreateBody(), `" 原题 "`, "null", 1), 400},
		{"unpaired-surrogate", strings.Replace(postHTTPCreateBody(), `" 原题 "`, `"\ud800"`, 1), 400},
		{"invalid-utf8", strings.Replace(postHTTPCreateBody(), "原题", "\xff", 1), 400},
		{"noncanonical-id", strings.Replace(postHTTPCreateBody(), postHTTPIdentity, "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", 1), 400},
		{"zero-id", strings.Replace(postHTTPCreateBody(), postHTTPIdentity, "00000000-0000-0000-0000-000000000000", 1), 400},
		{"trailing-object", postHTTPCreateBody() + " {}", 400},
		{"array", "[]", 400},
		{"oversize", strings.Repeat(" ", posts.MaxRequestBytes+1) + postHTTPCreateBody(), 413},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f, handler := newPostHTTP(t, httpTestLimits())
			w := postHTTPRequest(handler, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 8), c.body, postHTTPHeaders(false))
			code := "MALFORMED_REQUEST"
			if c.status == 413 {
				code = "PAYLOAD_TOO_LARGE"
			}
			postHTTPCheckError(t, w, c.status, code)
			if f.calls != 0 {
				t.Fatal("backend invoked on malformed input")
			}
		})
	}
}

func TestPostHTTPMaintenanceBodiesAreSmallAndClosed(t *testing.T) {
	cases := []struct {
		name, path, body string
		headerKey        bool
		status           int
	}{
		{"seal-cap", "/api/v1/post-commands/" + httpTestEncoding(16, 8) + "/seal", strings.Repeat(" ", 1024) + `{"operation":"CREATE","requestDigest":"` + strings.Repeat("a", 64) + `"}`, false, 413},
		{"cancel-cap", "/api/v1/me/post-tasks/" + postHTTPTask + "/cancel", strings.Repeat(" ", 1024) + `{"expectedAttemptVersion":1}`, true, 413},
		{"hide-cap", "/api/v1/me/post-tasks/" + postHTTPTask + "/hide", strings.Repeat(" ", 1024) + `{"expectedAttemptVersion":1}`, true, 413},
		{"version-zero", "/api/v1/me/post-tasks/" + postHTTPTask + "/cancel", `{"expectedAttemptVersion":0}`, true, 400},
		{"version-overflow", "/api/v1/me/post-tasks/" + postHTTPTask + "/cancel", `{"expectedAttemptVersion":2147483648}`, true, 400},
		{"version-float", "/api/v1/me/post-tasks/" + postHTTPTask + "/cancel", `{"expectedAttemptVersion":1.0}`, true, 400},
		{"version-string", "/api/v1/me/post-tasks/" + postHTTPTask + "/cancel", `{"expectedAttemptVersion":"1"}`, true, 400},
		{"retry-rebind", "/api/v1/me/post-tasks/" + postHTTPTask + "/retry", `{"expectedAttemptVersion":1,"title":"新题","body":"新文","identityId":"` + postHTTPIdentity + `"}`, true, 400},
		{"hide-extra", "/api/v1/me/post-tasks/" + postHTTPTask + "/hide", `{"expectedAttemptVersion":1,"body":"private"}`, true, 400},
		{"seal-op", "/api/v1/post-commands/" + httpTestEncoding(16, 8) + "/seal", `{"operation":"OTHER","requestDigest":"` + strings.Repeat("a", 64) + `"}`, false, 400},
		{"seal-digest", "/api/v1/post-commands/" + httpTestEncoding(16, 8) + "/seal", `{"operation":"CREATE","requestDigest":"` + strings.Repeat("A", 64) + `"}`, false, 400},
		{"delete-body", "/api/v1/posts/" + postHTTPPost + "/delete", `{}`, true, 400},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f, handler := newPostHTTP(t, httpTestLimits())
			w := postHTTPRequest(handler, "POST", c.path, c.body, postHTTPHeaders(c.headerKey))
			code := "MALFORMED_REQUEST"
			if c.status == 413 {
				code = "PAYLOAD_TOO_LARGE"
			}
			postHTTPCheckError(t, w, c.status, code)
			if f.calls != 0 {
				t.Fatal("backend invoked on malformed maintenance")
			}
		})
	}
}

func TestPostHTTPListQueriesAreCanonicalAndBounded(t *testing.T) {
	cases := []struct{ query, code string }{
		{"?", "MALFORMED_REQUEST"}, {"?limit=0", "MALFORMED_REQUEST"}, {"?limit=51", "MALFORMED_REQUEST"}, {"?limit=01", "MALFORMED_REQUEST"}, {"?limit=%2B1", "MALFORMED_REQUEST"}, {"?limit=1&limit=2", "MALFORMED_REQUEST"}, {"?cursor=AQ&cursor=Ag", "MALFORMED_REQUEST"}, {"?ownerId=private", "MALFORMED_REQUEST"}, {"?limit=", "MALFORMED_REQUEST"}, {"?limit", "MALFORMED_REQUEST"}, {"?limit=1&", "MALFORMED_REQUEST"}, {"?limit=%zz", "MALFORMED_REQUEST"}, {"?cursor=AQ==", "CURSOR_INVALID"}, {"?cursor=AB", "CURSOR_INVALID"}, {"?cursor=" + strings.Repeat("A", 1025), "CURSOR_INVALID"},
	}
	for _, c := range cases {
		t.Run(c.query, func(t *testing.T) {
			f, handler := newPostHTTP(t, httpTestLimits())
			w := postHTTPRequest(handler, "GET", "/api/v1/me/posts"+c.query, "", postHTTPHeaders(false))
			postHTTPCheckError(t, w, 400, c.code)
			if f.calls != 0 {
				t.Fatal("invalid query entered backend")
			}
		})
	}
	for _, path := range []string{"/api/v1/posts/" + postHTTPPost + "?limit=1", "/api/v1/post-commands/" + httpTestEncoding(16, 8) + "?limit=1", "/api/v1/me/post-composer-context?cursor=AQ"} {
		f, handler := newPostHTTP(t, httpTestLimits())
		w := postHTTPRequest(handler, "GET", path, "", postHTTPHeaders(false))
		postHTTPCheckError(t, w, 400, "MALFORMED_REQUEST")
		if f.calls != 0 {
			t.Fatal("query accepted on non-list")
		}
	}
}

func TestPostHTTPHeadersAndMethodsRejectAmbiguity(t *testing.T) {
	create := "/api/v1/post-commands/" + httpTestEncoding(16, 8)
	cases := []struct {
		name, method, path, body string
		change                   func(http.Header)
		status                   int
		code                     string
	}{
		{"duplicate-auth", "PUT", create, postHTTPCreateBody(), func(h http.Header) { h.Add("Authorization", h.Get("Authorization")) }, 400, "MALFORMED_REQUEST"},
		{"wrong-auth", "PUT", create, postHTTPCreateBody(), func(h http.Header) { h.Set("Authorization", "Capability "+httpTestEncoding(32, 7)) }, 401, "AUTHENTICATION_FAILED"},
		{"no-auth", "PUT", create, postHTTPCreateBody(), func(h http.Header) { h.Del("Authorization") }, 401, "AUTHENTICATION_FAILED"},
		{"extra-key", "PUT", create, postHTTPCreateBody(), func(h http.Header) { h.Set("Idempotency-Key", httpTestEncoding(16, 8)) }, 400, "MALFORMED_REQUEST"},
		{"duplicate-type", "PUT", create, postHTTPCreateBody(), func(h http.Header) { h.Add("Content-Type", "application/json") }, 415, "UNSUPPORTED_MEDIA_TYPE"},
		{"encoded", "PUT", create, postHTTPCreateBody(), func(h http.Header) { h.Set("Content-Encoding", "gzip") }, 400, "MALFORMED_REQUEST"},
		{"foreign-proof", "PUT", create, postHTTPCreateBody(), func(h http.Header) { h.Set("OTP-Flow-ID", "proof") }, 400, "MALFORMED_REQUEST"},
		{"get-body", "GET", create, `{}`, func(http.Header) {}, 400, "MALFORMED_REQUEST"},
		{"wrong-method", "POST", create, postHTTPCreateBody(), func(http.Header) {}, 405, "MALFORMED_REQUEST"},
		{"trailing-slash", "PUT", create + "/", postHTTPCreateBody(), func(http.Header) {}, 400, "MALFORMED_REQUEST"},
		{"encoded-path", "PUT", strings.Replace(create, "post-commands", "post%2Dcommands", 1), postHTTPCreateBody(), func(http.Header) {}, 400, "MALFORMED_REQUEST"},
		{"noncanonical-key", "PUT", create + "=", postHTTPCreateBody(), func(http.Header) {}, 400, "MALFORMED_REQUEST"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f, handler := newPostHTTP(t, httpTestLimits())
			h := postHTTPHeaders(false)
			c.change(h)
			w := postHTTPRequest(handler, c.method, c.path, c.body, h)
			postHTTPCheckError(t, w, c.status, c.code)
			if f.calls != 0 {
				t.Fatal("ambiguous request entered backend")
			}
			if c.status == 405 && w.Header().Get("Allow") != "GET, PUT" {
				t.Fatal("missing allow header")
			}
		})
	}
	for _, values := range [][]string{nil, {httpTestEncoding(32, 8)}, {httpTestEncoding(16, 8), httpTestEncoding(16, 9)}} {
		f, handler := newPostHTTP(t, httpTestLimits())
		h := postHTTPHeaders(true)
		h["Idempotency-Key"] = values
		w := postHTTPRequest(handler, "POST", "/api/v1/posts/"+postHTTPPost+"/delete", "", h)
		postHTTPCheckError(t, w, 400, "MALFORMED_REQUEST")
		if f.calls != 0 {
			t.Fatal("bad maintenance key entered backend")
		}
	}
}

func TestPostHTTPRejectedMutationAndQueryAreDifferentFacts(t *testing.T) {
	f, handler := newPostHTTP(t, httpTestLimits())
	f.value = posts.CommandResult{State: "REJECTED", Operation: posts.Create, ErrorCode: "POST_CONTENT_INVALID"}
	w := postHTTPRequest(handler, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 8), postHTTPCreateBody(), postHTTPHeaders(false))
	postHTTPCheckError(t, w, 400, "POST_CONTENT_INVALID")
	w = postHTTPRequest(handler, "GET", "/api/v1/post-commands/"+httpTestEncoding(16, 8), "", postHTTPHeaders(false))
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"state":"REJECTED"`) || w.Header().Get("Session-Expires-At") == "" {
		t.Fatalf("historical query must succeed: %s", w.Body.String())
	}
}

func TestPostHTTPBackendErrorsHaveFixedPublicBodies(t *testing.T) {
	cases := []struct {
		err    error
		status int
		code   string
		retry  string
	}{
		{authprivacy.ErrSessionInvalid, 401, "SESSION_INVALID", ""}, {authprivacy.ErrSessionReplaced, 401, "session_replaced", ""}, {authprivacy.ErrAuthenticationFailed, 401, "AUTHENTICATION_FAILED", ""}, {authprivacy.ErrAccountUnavailable, 403, "AUTHENTICATION_FAILED", ""}, {authprivacy.ErrAuthorizationUnavailable, 503, "AUTHORIZATION_UNAVAILABLE", ""}, {posts.ErrCursorInvalid, 400, "CURSOR_INVALID", ""}, {&authprivacy.PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: 999}, 429, "RATE_LIMITED", "300"}, {&authprivacy.PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: 0}, 429, "RATE_LIMITED", "1"}, {&authprivacy.PostError{Code: "COMMAND_CONFLICT", Status: 409}, 409, "COMMAND_CONFLICT", ""}, {&authprivacy.PostError{Code: "COMMAND_SEALED", Status: 409}, 409, "COMMAND_SEALED", ""}, {&authprivacy.PostError{Code: "RESULT_EXPIRED", Status: 409}, 409, "RESULT_EXPIRED", ""}, {&authprivacy.PostError{Code: "TASK_NOT_FOUND", Status: 404}, 404, "TASK_NOT_FOUND", ""}, {&authprivacy.PostError{Code: "TASK_NOT_FOUND", Status: 400}, 503, "SERVICE_UNAVAILABLE", ""}, {&authprivacy.PostError{Code: "private-database-title-secret", Status: 409}, 503, "SERVICE_UNAVAILABLE", ""}, {errors.New("private-database-title-secret"), 503, "SERVICE_UNAVAILABLE", ""},
	}
	for _, c := range cases {
		t.Run(c.code+"/"+c.retry, func(t *testing.T) {
			f, handler := newPostHTTP(t, httpTestLimits())
			f.err = c.err
			w := postHTTPRequest(handler, "GET", "/api/v1/me/posts", "", postHTTPHeaders(false))
			postHTTPCheckError(t, w, c.status, c.code)
			if w.Header().Get("Retry-After") != c.retry || strings.Contains(w.Body.String(), "private-database-title-secret") {
				t.Fatal("unbounded retry or raw error leak")
			}
		})
	}
}

func TestPostHTTPNeverSerializesArbitraryBackendRows(t *testing.T) {
	f, handler := newPostHTTP(t, httpTestLimits())
	f.value = map[string]any{"post": postHTTPCard(), "accountId": "private", "identityId": "private", "body": "secret"}
	w := postHTTPRequest(handler, "GET", "/api/v1/posts/"+postHTTPPost, "", postHTTPHeaders(false))
	postHTTPCheckError(t, w, 503, "SERVICE_UNAVAILABLE")
	if strings.Contains(w.Body.String(), "private") || strings.Contains(w.Body.String(), "secret") {
		t.Fatal("backend row leaked")
	}
}

func TestPostHTTPResponseInvariantsAreEnforced(t *testing.T) {
	key := httpTestEncoding(16, 8)
	create := "/api/v1/post-commands/" + key
	accepted := posts.CommandResult{State: "ACCEPTED", Operation: posts.Create, TaskID: postHTTPTask, PostID: postHTTPPost, AttemptVersion: 1}
	badCreate := accepted
	badCreate.AttemptVersion = 2
	wrongOp := accepted
	wrongOp.Operation = posts.Retry
	badCancel := posts.CommandResult{State: "COMMITTED", Operation: posts.Cancel, TaskID: postHTTPTask, AttemptVersion: 2, TaskState: posts.Cancelled}
	wrongDelete := posts.CommandResult{State: "COMMITTED", Operation: posts.DeletePost, PostID: postHTTPTask}
	badTask := postHTTPTaskDetail()
	badTask.Task.ServerSortAt = postHTTPTime.Add(time.Second)
	badTerminal := postHTTPTaskDetail()
	badTerminal.Task.State = posts.Failed
	badTerminal.Task.CanCancel = false
	earlier := postHTTPTime.Add(-time.Second)
	code := "PUBLISHING_STOPPED"
	badTerminal.Task.TerminalAt = &earlier
	badTerminal.Task.FailureCode = &code
	badHidden := postHTTPTaskDetail()
	badHidden.Task.Visible = false
	badHidden.Task.CanCancel = false
	badCard := postHTTPCard()
	badCard.Author = posts.PublicAuthor{State: "ACCOUNT_CLOSED", ShortCode: "BAD", Avatar: "inactive-v1"}
	badDate := postHTTPCard()
	badDate.PublishedAt = postHTTPTime.In(time.FixedZone("local", 0))
	cases := []struct {
		name, method, path, body string
		value                    any
		key                      bool
	}{
		{"create-version", "PUT", create, postHTTPCreateBody(), badCreate, false}, {"operation", "PUT", create, postHTTPCreateBody(), wrongOp, false}, {"seal-unknown", "POST", create + "/seal", `{"operation":"CREATE","requestDigest":"` + strings.Repeat("a", 64) + `"}`, posts.CommandResult{State: "UNKNOWN_NOT_OBSERVED"}, false}, {"seal-wrong-operation", "POST", create + "/seal", `{"operation":"CREATE","requestDigest":"` + strings.Repeat("a", 64) + `"}`, posts.CommandResult{State: "NOT_ACCEPTED", Operation: posts.Cancel, Reason: "COMMAND_SEALED"}, false}, {"cancel-version", "POST", "/api/v1/me/post-tasks/" + postHTTPTask + "/cancel", `{"expectedAttemptVersion":1}`, badCancel, true}, {"delete-target", "POST", "/api/v1/posts/" + postHTTPPost + "/delete", "", wrongDelete, true}, {"private-sort", "GET", "/api/v1/me/post-tasks/" + postHTTPTask, "", badTask, false}, {"terminal-before-acceptance", "GET", "/api/v1/me/post-tasks/" + postHTTPTask, "", badTerminal, false}, {"hidden-content", "GET", "/api/v1/me/post-tasks/" + postHTTPTask, "", badHidden, false}, {"invalid-author", "GET", "/api/v1/me/posts", "", posts.OwnPostPage{Items: []posts.OwnPostCard{{Post: badCard, ServerSortAt: postHTTPTime}}}, false}, {"non-utc", "GET", "/api/v1/channels/" + postHTTPChannel + "/posts", "", posts.FeedPage{Items: []posts.PublicPostCard{badDate}}, false}, {"nil-items", "GET", "/api/v1/me/posts", "", posts.OwnPostPage{}, false}, {"exceeds-limit", "GET", "/api/v1/channels/" + postHTTPChannel + "/posts?limit=1", "", posts.FeedPage{Items: []posts.PublicPostCard{postHTTPCard(), postHTTPCard()}}, false}, {"capabilities-edit", "GET", "/api/v1/me/posts/" + postHTTPPost + "/capabilities", "", posts.OwnPostCapabilities{PostID: postHTTPPost, CanDelete: true, CanEdit: true}, false}, {"typed-nil", "GET", "/api/v1/me/post-composer-context", "", (*posts.ComposerContext)(nil), false}, {"wrong-type", "GET", "/api/v1/posts/" + postHTTPPost, "", postHTTPTaskDetail(), false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f, handler := newPostHTTP(t, httpTestLimits())
			f.value = c.value
			w := postHTTPRequest(handler, c.method, c.path, c.body, postHTTPHeaders(c.key))
			postHTTPCheckError(t, w, 503, "SERVICE_UNAVAILABLE")
		})
	}
	for _, at := range []time.Time{postHTTPTime, postHTTPTime.Add(-time.Second), postHTTPTime.Add(24 * time.Hour).In(time.FixedZone("local", 0))} {
		f, handler := newPostHTTP(t, httpTestLimits())
		f.expiresAt = at
		w := postHTTPRequest(handler, "GET", create, "", postHTTPHeaders(false))
		postHTTPCheckError(t, w, 503, "SERVICE_UNAVAILABLE")
	}
}

func TestPostHTTPPublishedTaskCanReconcilePublicContent(t *testing.T) {
	f, handler := newPostHTTP(t, httpTestLimits())
	task := postHTTPTaskDetail()
	task.Task.State = posts.Published
	task.Task.Visible = false
	task.Task.CanCancel = false
	at := postHTTPTime
	task.Task.TerminalAt = &at
	f.value = task
	w := postHTTPRequest(handler, "GET", "/api/v1/me/post-tasks/"+postHTTPTask, "", postHTTPHeaders(false))
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"state":"PUBLISHED"`) {
		t.Fatalf("published reconciliation failed: %s", w.Body.String())
	}
}

func TestPostHTTPMissingChannelReadAndCreateHaveDistinctStatuses(t *testing.T) {
	f, handler := newPostHTTP(t, httpTestLimits())
	f.err = &authprivacy.PostError{Code: "POST_CHANNEL_UNAVAILABLE", Status: 404}
	w := postHTTPRequest(handler, "GET", "/api/v1/channels/"+postHTTPChannel+"/posts", "", postHTTPHeaders(false))
	postHTTPCheckError(t, w, 404, "POST_CHANNEL_UNAVAILABLE")
	if f.calls != 1 || f.query.Kind != authprivacy.PostChannelFeed || f.query.ID != postHTTPChannel {
		t.Fatal("canonical missing channel did not reach final read")
	}
	f.err = nil
	f.value = posts.CommandResult{State: "REJECTED", Operation: posts.Create, ErrorCode: "POST_CHANNEL_UNAVAILABLE"}
	w = postHTTPRequest(handler, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 8), postHTTPCreateBody(), postHTTPHeaders(false))
	postHTTPCheckError(t, w, 409, "POST_CHANNEL_UNAVAILABLE")
}

func TestPostHTTPNetworkOverloadAndCORS(t *testing.T) {
	limits := httpTestLimits()
	limits.QueryCapacity = 1
	f, handler := newPostHTTP(t, limits)
	w := postHTTPRequest(handler, "GET", "/api/v1/me/posts", "", postHTTPHeaders(false))
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	w = postHTTPRequest(handler, "GET", "/api/v1/me/posts", "", postHTTPHeaders(false))
	postHTTPCheckError(t, w, 429, "RATE_LIMITED")
	if f.calls != 1 || w.Header().Get("Retry-After") == "" {
		t.Fatal("network limiter did not bound before backend")
	}
	f, handler = newPostHTTP(t, httpTestLimits())
	h := postHTTPHeaders(false)
	h.Set("Origin", "https://client.example")
	w = postHTTPRequest(handler, "GET", "/api/v1/me/posts?limit=1", "", h)
	if w.Code != 200 || w.Header().Get("Access-Control-Expose-Headers") != "Session-Expires-At, Server-Time, X-Request-ID, Retry-After" {
		t.Fatal("CORS omitted authority headers")
	}
	h = http.Header{"Origin": {"https://client.example"}, "Access-Control-Request-Method": {"PUT"}, "Access-Control-Request-Headers": {"content-type, authorization"}}
	w = postHTTPRequest(handler, "OPTIONS", "/api/v1/post-commands/"+httpTestEncoding(16, 8), "", h)
	if w.Code != 204 || f.calls != 1 {
		t.Fatalf("preflight entered backend: %d %s", w.Code, w.Body.String())
	}
}
