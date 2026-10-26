package authprivacyhttp

import (
	"net/http"
	"strings"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

func TestCommentSnapshotCORSAndErrorClasses(t *testing.T) {
	f, handler := newPostHTTP(t, httpTestLimits())
	for _, path := range []string{"/api/v1/posts/" + postHTTPPost + "/comments", "/api/v1/posts/" + postHTTPPost + "/comments/" + postHTTPTask + "/replies"} {
		h := http.Header{"Origin": {"https://client.example"}, "Access-Control-Request-Method": {"GET"}, "Access-Control-Request-Headers": {"authorization,x-comment-snapshot-request"}}
		w := postHTTPRequest(handler, "OPTIONS", path, "", h)
		if w.Code != 204 || !strings.Contains(w.Header().Get("Access-Control-Allow-Headers"), "x-comment-snapshot-request") || f.calls != 0 {
			t.Fatal("snapshot preflight", w.Code, w.Body.String())
		}
	}
	for _, tc := range []struct {
		code   string
		status int
	}{{"COMMENT_SNAPSHOT_TOO_LARGE", 422}, {"COMMENT_SNAPSHOT_CAPACITY", 503}, {"COMMENT_SNAPSHOT_UNAVAILABLE", 503}, {"COMMENT_SNAPSHOT_INTEGRITY", 503}, {"SHARED_RATE_UNAVAILABLE", 503}, {"CURSOR_INVALID", 400}} {
		f.err = &authprivacy.PostError{Code: tc.code, Status: tc.status}
		w := postHTTPRequest(handler, "GET", "/api/v1/me/posts", "", postHTTPHeaders(false))
		postHTTPCheckError(t, w, tc.status, tc.code)
	}
}
