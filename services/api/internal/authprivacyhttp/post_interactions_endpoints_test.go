package authprivacyhttp

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func (f *postHTTPBackend) ReadPostInteractions(_ context.Context, bearer [32]byte, ids []string) (authprivacy.PostResponse, error) {
	f.calls++
	f.bearer = bearer
	page := posts.PostInteractionPage{Items: []posts.PostInteractions{}}
	for _, id := range ids {
		page.Items = append(page.Items, posts.PostInteractions{PostID: id})
	}
	return f.response(page)
}

func (f *postHTTPBackend) SetPostInteractionConditional(ctx context.Context, bearer [32]byte, id string, kind posts.InteractionKind, enabled bool, expected string) (authprivacy.PostResponse, error) {
	f.command = expected
	r, e := f.SetPostInteraction(ctx, bearer, id, kind, enabled)
	r.InteractionVersion = `"` + strings.Repeat("b", 64) + `"`
	return r, e
}

func TestFeedInteractionConditionalHTTPHeaders(t *testing.T) {
	backend, handler := newPostHTTP(t, httpTestLimits())
	path := "/api/v1/posts/" + postHTTPPost + "/like"
	tag := `"` + strings.Repeat("a", 64) + `"`
	for _, values := range [][]string{{""}, {"*"}, {"W/" + tag}, {tag + ", " + tag}, {tag, tag}, {`"` + strings.Repeat("A", 64) + `"`}} {
		headers := postHTTPHeaders(false)
		headers["If-Interaction-Version"] = values
		before := backend.calls
		w := postHTTPRequest(handler, "PUT", path, `{"liked":true}`, headers)
		if w.Code != 400 || backend.calls != before {
			t.Fatal("invalid conditional header accepted", values, w.Code)
		}
	}
	headers := postHTTPHeaders(false)
	headers.Set("If-Interaction-Version", tag)
	w := postHTTPRequest(handler, "PUT", path, `{"liked":true}`, headers)
	if w.Code != 200 || backend.command != tag || !posts.ValidInteractionVersion(w.Header().Get("Interaction-Version")) || w.Header().Get("ETag") != "" {
		t.Fatal("conditional response envelope", w.Code)
	}
	backend.err = &authprivacy.PostError{Code: "INTERACTION_VERSION_CONFLICT", Status: 412}
	w = postHTTPRequest(handler, "PUT", path, `{"liked":true}`, headers)
	if w.Code != 412 || w.Header().Get("Interaction-Version") != "" || w.Header().Get("Session-Expires-At") != "" {
		t.Fatal("conflict altered authority", w.Code)
	}
	backend.err = nil
	for _, path := range []string{"/api/v1/posts/" + postHTTPPost + "/interactions", "/api/v1/feed/interactions"} {
		method, body := "GET", ""
		if path == "/api/v1/feed/interactions" {
			method = "POST"
			body = `{"postIds":["` + postHTTPPost + `"]}`
		}
		if postHTTPRequest(handler, method, path, body, headers).Code != 400 {
			t.Fatal("write condition accepted on read")
		}
	}
	cors := http.Header{"Origin": {"https://client.example"}, "Access-Control-Request-Method": {"PUT"}, "Access-Control-Request-Headers": {"content-type,authorization,if-interaction-version"}}
	if postHTTPRequest(handler, "OPTIONS", path, "", cors).Code != 204 {
		t.Fatal("conditional preflight blocked")
	}
	if postHTTPRequest(handler, "OPTIONS", "/api/v1/post-commands/"+httpTestEncoding(16, 8), "", cors).Code != 400 {
		t.Fatal("conditional header allowed outside interaction PUT")
	}
	headers.Set("Origin", "https://client.example")
	if !strings.Contains(postHTTPRequest(handler, "PUT", path, `{"liked":true}`, headers).Header().Get("Access-Control-Expose-Headers"), "Interaction-Version") {
		t.Fatal("write version hidden from browser")
	}
}
func (f *postHTTPBackend) SetPostInteraction(_ context.Context, bearer [32]byte, id string, kind posts.InteractionKind, enabled bool) (authprivacy.PostResponse, error) {
	f.calls++
	f.bearer = bearer
	item := posts.PostInteractions{PostID: id}
	if kind == posts.PostLike && enabled {
		item.LikedByMe, item.LikeCount = true, 1
	} else if kind == posts.PostFavorite && enabled {
		item.FavoritedByMe, item.FavoriteCount = true, 1
	}
	return f.response(item)
}

func TestFeedInteractionsHTTPStrictInputsAndDTOs(t *testing.T) {
	backend, handler := newPostHTTP(t, httpTestLimits())
	base := "/api/v1/posts/" + postHTTPPost
	for _, tc := range []struct {
		method, path, body string
		status             int
	}{
		{"GET", base + "/interactions", "", 200},
		{"POST", "/api/v1/feed/interactions", `{"postIds":["` + postHTTPPost + `"]}`, 200},
		{"PUT", base + "/like", `{"liked":true}`, 200},
		{"PUT", base + "/like", `{"liked":false}`, 200},
		{"PUT", base + "/favorite", `{"favorited":true}`, 200},
		{"PUT", base + "/favorite", `{"favorited":false}`, 200},
		{"POST", "/api/v1/feed/interactions", `{"postIds":[]}`, 400},
		{"POST", "/api/v1/feed/interactions", `{"postIds":null}`, 400},
		{"POST", "/api/v1/feed/interactions", `{"postIds":[1]}`, 400},
		{"POST", "/api/v1/feed/interactions", `{"postIds":["bad"]}`, 400},
		{"POST", "/api/v1/feed/interactions", `{"postIds":["` + postHTTPPost + `","` + postHTTPPost + `"]}`, 400},
		{"POST", "/api/v1/feed/interactions", `{"postIds":["` + postHTTPPost + `"],"accountId":"x"}`, 400},
		{"PUT", base + "/like", `{"liked":true,"liked":false}`, 400},
		{"PUT", base + "/like", `{"liked":null}`, 400},
		{"PUT", base + "/favorite", `{"favorited":"yes"}`, 400},
		{"PUT", base + "/favorite", `{"favorited":true,"identityId":"x"}`, 400},
		{"GET", base + "/interactions?accountId=x", "", 400},
		{"GET", base + "/interactions", `{}`, 400},
		{"POST", base + "/like", `{"liked":true}`, 405},
		{"PUT", "/api/v1/posts/bad/like", `{"liked":true}`, 400},
	} {
		t.Run(tc.method+tc.path+tc.body, func(t *testing.T) {
			before := backend.calls
			w := postHTTPRequest(handler, tc.method, tc.path, tc.body, postHTTPHeaders(false))
			if w.Code != tc.status || tc.status >= 400 && before != backend.calls {
				t.Fatalf("status %d want %d; calls %d->%d; %s", w.Code, tc.status, before, backend.calls, w.Body.String())
			}
		})
	}
	for _, n := range []int{50, 51} {
		ids := make([]string, n)
		for i := range ids {
			ids[i] = uuid.NewString()
		}
		body, _ := json.Marshal(map[string]any{"postIds": ids})
		w := postHTTPRequest(handler, "POST", "/api/v1/feed/interactions", string(body), postHTTPHeaders(false))
		if n == 50 && w.Code != 200 || n == 51 && w.Code != 400 {
			t.Fatal("batch bound", n, w.Code)
		}
	}
	if w := postHTTPRequest(handler, "GET", base+"/interactions", "", http.Header{}); w.Code != 401 {
		t.Fatal("anonymous access")
	}
	if w := postHTTPRequest(handler, "PUT", base+"/like", `{"liked":true}`, postHTTPHeaders(true)); w.Code != 400 {
		t.Fatal("unrelated idempotency key accepted")
	}
	for _, value := range []any{
		map[string]any{"accountId": "private"},
		posts.PostInteractions{PostID: postHTTPPost, LikeCount: -1},
		posts.PostInteractions{PostID: postHTTPPost, LikedByMe: true},
		posts.PostInteractions{PostID: postHTTPChannel},
		posts.PostInteractions{PostID: postHTTPPost}, // Contradicts requested liked:true.
	} {
		backend.value = value
		if w := postHTTPRequest(handler, "PUT", base+"/like", `{"liked":true}`, postHTTPHeaders(false)); w.Code != 503 || w.Header().Get("Session-Expires-At") != "" {
			t.Fatal("unsafe DTO accepted", w.Code)
		}
	}
	backend.value = posts.PostInteractionPage{Items: []posts.PostInteractions{{PostID: postHTTPChannel}}}
	if w := postHTTPRequest(handler, "POST", "/api/v1/feed/interactions", `{"postIds":["`+postHTTPPost+`"]}`, postHTTPHeaders(false)); w.Code != 503 {
		t.Fatal("batch echoed foreign IDs")
	}
}
