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

func TestRealHTTPSFeedInteractionsConditionalPostgres(t *testing.T) {
	s := e2eNewServices(t)
	owner, _ := e2ePrivacySignup(t, s, "conditional_tls")
	channel := postHTTPSChannel(t, s, owner)
	identity := postHTTPSIdentity(t, s, owner, "Author", 111)
	created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 112), owner, "", posts.CreatePostInput{ChannelID: channel, IdentityID: identity, Title: "Fence", Body: "Body"}, 202)
	if _, e := s.c.PublishAcceptedPosts(context.Background(), 100); e != nil {
		t.Fatal(e)
	}
	base := "/api/v1/posts/" + created["postId"].(string)
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
			t.Fatalf("conditional TLS status %d want%d", r.StatusCode, status)
		}
		var out map[string]any
		if json.Unmarshal(raw, &out) != nil {
			t.Fatal("JSON")
		}
		tag := r.Header.Get("Interaction-Version")
		if status == 200 {
			if !posts.ValidInteractionVersion(tag) || r.Header.Get("Session-Expires-At") == "" {
				t.Fatal("missing write authority")
			}
			postHTTPSFields(t, out, "postId", "likeCount", "favoriteCount", "commentCount", "likedByMe", "favoritedByMe")
		} else if tag != "" || r.Header.Get("Session-Expires-At") != "" {
			t.Fatal("conflict renewed authority")
		}
		return tag, out
	}
	initial, _ := call("GET", base+"/interactions", "", "", 200)
	committed, _ := call("PUT", base+"/like", `{"liked":true}`, initial, 200)
	if committed == initial {
		t.Fatal("version not rotated")
	}
	current, _ := call("PUT", base+"/like", `{"liked":false}`, committed, 200)
	call("PUT", base+"/like", `{"liked":true}`, initial, 412)
	stable, item := call("GET", base+"/interactions", "", "", 200)
	if stable != current || item["likedByMe"] != false {
		t.Fatal("late retry overwrote reverse")
	}
	// A like's version and favorite's version belong to the same private queue.
	call("PUT", base+"/favorite", `{"favorited":true}`, committed, 412)
}
