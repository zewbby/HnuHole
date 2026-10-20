package authprivacyhttp

import (
	"context"
	"encoding/json"
	"net/http"
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
