package authprivacyhttp

import (
	"net/http"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestFeedHTTPRoutesAndStrictInputs(t *testing.T) {
	backend, handler := newPostHTTP(t, httpTestLimits())
	for _, tc := range []struct {
		method, path, body string
		status             int
	}{
		{"GET", "/api/v1/feed", "", 200},
		{"GET", "/api/v1/feed?channelId=" + postHTTPChannel + "&limit=1", "", 200},
		{"GET", "/api/v1/me/feed-preferences", "", 200},
		{"PUT", "/api/v1/me/feed-preferences", `{"blockedChannelIds":["` + postHTTPChannel + `"]}`, 200},
		{"PUT", "/api/v1/me/feed-preferences", `{"blockedChannelIds":[]}`, 200},
		{"POST", "/api/v1/posts/" + postHTTPPost + "/views", "", 200},
		{"GET", "/api/v1/feed?channelId=bad", "", 400},
		{"GET", "/api/v1/feed?sort=heat", "", 400},
		{"GET", "/api/v1/feed?channelId=" + postHTTPChannel + "&channelId=" + postHTTPChannel, "", 400},
		{"GET", "/api/v1/me/feed-preferences?limit=1", "", 400},
		{"PUT", "/api/v1/me/feed-preferences", `{"blockedChannelIds":null}`, 400},
		{"PUT", "/api/v1/me/feed-preferences", `{"blockedChannelIds":[1]}`, 400},
		{"PUT", "/api/v1/me/feed-preferences", `{"blockedChannelIds":["` + postHTTPChannel + `","` + postHTTPChannel + `"]}`, 400},
		{"PUT", "/api/v1/me/feed-preferences", `{"blockedChannelIds":[],"accountId":"x"}`, 400},
		{"PUT", "/api/v1/me/feed-preferences", `{"blockedChannelIds":[],"blockedChannelIds":[]}`, 400},
		{"POST", "/api/v1/posts/" + postHTTPPost + "/views", "{}", 400},
		{"POST", "/api/v1/posts/" + postHTTPPost + "/views?identityId=" + postHTTPIdentity, "", 400},
		{"GET", "/api/v1/posts/" + postHTTPPost + "/views", "", 405},
	} {
		t.Run(tc.method+tc.path+tc.body, func(t *testing.T) {
			before := backend.calls
			w := postHTTPRequest(handler, tc.method, tc.path, tc.body, postHTTPHeaders(false))
			if w.Code != tc.status {
				t.Fatalf("status=%d want=%d body=%s", w.Code, tc.status, w.Body.String())
			}
			if tc.status >= 400 && backend.calls != before {
				t.Fatal("invalid input reached backend")
			}
		})
	}
	for _, path := range []string{"/api/v1/feed", "/api/v1/me/feed-preferences"} {
		if w := postHTTPRequest(handler, "GET", path, "", http.Header{}); w.Code != 401 {
			t.Fatal("anonymous feed access", w.Code)
		}
	}
	if w := postHTTPRequest(handler, "POST", "/api/v1/posts/"+postHTTPPost+"/views", "", postHTTPHeaders(true)); w.Code != 400 {
		t.Fatal("accepted unrelated idempotency key", w.Code)
	}
}

func TestFeedHTTPRejectsInvalidDTOs(t *testing.T) {
	backend, handler := newPostHTTP(t, httpTestLimits())
	for _, tc := range []struct {
		method, path, body string
		value              any
	}{
		{"POST", "/api/v1/posts/" + postHTTPPost + "/views", "", posts.PostView{PostID: postHTTPPost, ViewCount: -1}},
		{"GET", "/api/v1/me/feed-preferences", "", posts.FeedPreferences{}},
		{"GET", "/api/v1/feed", "", posts.CrossChannelFeedPage{}},
		{"GET", "/api/v1/feed", "", map[string]any{"accountId": "private"}},
	} {
		backend.value = tc.value
		w := postHTTPRequest(handler, tc.method, tc.path, tc.body, postHTTPHeaders(false))
		if w.Code != 503 {
			t.Fatal("invalid/private DTO exposed", w.Code)
		}
	}
	backend.value = nil
	backend.err = authprivacy.ErrAuthorizationUnavailable
	if w := postHTTPRequest(handler, "GET", "/api/v1/feed", "", postHTTPHeaders(false)); w.Code != 503 || w.Header().Get("Session-Expires-At") != "" {
		t.Fatal("failed authority exposed success headers")
	}
}
