package authprivacyhttp

import (
	"context"
	"encoding/json"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestRealHTTPSFeedRepostsPostgres(t *testing.T) {
	s := e2eNewServices(t)
	owner, _ := e2ePrivacySignup(t, s, "repost_tls")
	channel := postHTTPSChannel(t, s, owner)
	identity := postHTTPSIdentity(t, s, owner, "Original", 121)
	created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 122), owner, "", posts.CreatePostInput{ChannelID: channel, IdentityID: identity, Title: "Repost source", Body: "Original body"}, 202)
	if _, e := s.c.PublishAcceptedPosts(context.Background(), 100); e != nil {
		t.Fatal(e)
	}
	base := "/api/v1/posts/" + created["postId"].(string) + "/repost"
	call := func(method, path, body, version string, status int) (string, map[string]any) {
		req, e := http.NewRequest(method, s.cPublic.URL+path, strings.NewReader(body))
		if e != nil {
			t.Fatal(e)
		}
		req.Header.Set("Authorization", "Bearer "+owner)
		if body != "" {
			req.Header.Set("Content-Type", "application/json")
		}
		if version != "" {
			req.Header.Set("If-Interaction-Version", version)
		}
		r, e := s.client.Do(req)
		if e != nil {
			t.Fatal(e)
		}
		defer r.Body.Close()
		raw, e := io.ReadAll(r.Body)
		if e != nil {
			t.Fatal(e)
		}
		if r.StatusCode != status {
			t.Fatalf("%s %s status=%d want=%d", method, path, r.StatusCode, status)
		}
		var out map[string]any
		if json.Unmarshal(raw, &out) != nil {
			t.Fatal("invalid JSON")
		}
		if r.Header.Get("Cache-Control") != "no-store" {
			t.Fatal("private cache")
		}
		if status != 200 && r.Header.Get("Session-Expires-At") != "" {
			t.Fatal("failure renewed")
		}
		return r.Header.Get("Interaction-Version"), out
	}
	initial, _ := call("GET", base, "", "", 200)
	committed, _ := call("PUT", base, `{"identityId":"`+identity+`","reposted":true}`, initial, 200)
	_, page := call("GET", "/api/v1/me/reposts?limit=1", "", "", 200)
	item := page["items"].([]any)[0].(map[string]any)
	if item["identityId"] != identity || item["post"].(map[string]any)["body"] != "Original body" {
		t.Fatal("lost original projection")
	}
	cancelled, _ := call("PUT", base, `{"identityId":"`+identity+`","reposted":false}`, committed, 200)
	call("PUT", base, `{"identityId":"`+identity+`","reposted":true}`, initial, 412)
	actual, state := call("GET", base, "", "", 200)
	if actual != cancelled || len(state["items"].([]any)) != 0 {
		t.Fatal("late create revived")
	}
}
