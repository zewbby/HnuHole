package authprivacyhttp

import (
	"context"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"net/http"
	"strings"
	"testing"
	"time"
)

func (f *postHTTPBackend) ReadPostReposts(_ context.Context, bearer [32]byte, id string) (authprivacy.PostResponse, error) {
	f.calls++
	f.bearer = bearer
	r, e := f.response(posts.RepostState{PostID: id, Items: []posts.RepostMark{}})
	r.InteractionVersion = `"` + strings.Repeat("b", 64) + `"`
	return r, e
}
func (f *postHTTPBackend) SetPostRepost(_ context.Context, bearer [32]byte, id, identity string, on bool, version string) (authprivacy.PostResponse, error) {
	f.calls++
	f.bearer = bearer
	f.command = version
	state := posts.RepostState{PostID: id, Items: []posts.RepostMark{}}
	if on {
		state.Items = append(state.Items, posts.RepostMark{IdentityID: identity, RepostedAt: time.Now().UTC()})
	}
	r, e := f.response(state)
	r.InteractionVersion = `"` + strings.Repeat("b", 64) + `"`
	return r, e
}
func (f *postHTTPBackend) ListPostReposts(_ context.Context, bearer [32]byte, q authprivacy.PostQuery) (authprivacy.PostResponse, error) {
	f.calls++
	f.bearer = bearer
	return f.response(posts.RepostPage{Items: []posts.RepostItem{}})
}
func TestFeedRepostsStrictHTTP(t *testing.T) {
	backend, handler := newPostHTTP(t, httpTestLimits())
	path := "/api/v1/posts/" + postHTTPPost + "/repost"
	body := `{"identityId":"` + postHTTPPost + `","reposted":true}`
	headers := postHTTPHeaders(false)
	if w := postHTTPRequest(handler, "PUT", path, body, headers); w.Code != 400 {
		t.Fatal("missing mandatory version", w.Code)
	}
	headers.Set("If-Interaction-Version", `"`+strings.Repeat("a", 64)+`"`)
	for _, bad := range []string{`{"identityId":"bad","reposted":true}`, `{"identityId":"` + postHTTPPost + `","reposted":true,"accountId":"x"}`, `{"identityId":"` + postHTTPPost + `","reposted":true,"reposted":false}`} {
		before := backend.calls
		if w := postHTTPRequest(handler, "PUT", path, bad, headers); w.Code != 400 || backend.calls != before {
			t.Fatal("invalid request reached backend", w.Code)
		}
	}
	if w := postHTTPRequest(handler, "PUT", path, body, headers); w.Code != 200 || !posts.ValidInteractionVersion(w.Header().Get("Interaction-Version")) {
		t.Fatal("write", w.Code, w.Body.String())
	}
	if w := postHTTPRequest(handler, "GET", path, "", postHTTPHeaders(false)); w.Code != 200 {
		t.Fatal("state", w.Code)
	}
	if w := postHTTPRequest(handler, "GET", "/api/v1/me/reposts?limit=1", "", postHTTPHeaders(false)); w.Code != 200 {
		t.Fatal("list", w.Code, w.Body.String())
	}
	if w := postHTTPRequest(handler, "GET", "/api/v1/me/reposts?accountId="+postHTTPPost, "", postHTTPHeaders(false)); w.Code != 400 {
		t.Fatal("foreign filter", w.Code)
	}
	if w := postHTTPRequest(handler, "GET", "/api/v1/me/reposts", "", http.Header{}); w.Code != 401 {
		t.Fatal("unauthenticated", w.Code)
	}
	backend.err = &authprivacy.PostError{Code: "INTERACTION_VERSION_CONFLICT", Status: 412}
	if w := postHTTPRequest(handler, "PUT", path, body, headers); w.Code != 412 || w.Header().Get("Session-Expires-At") != "" {
		t.Fatal("conflict metadata", w.Code)
	}
}
