package authprivacyhttp

import (
	"context"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestRealHTTPSFeedInteractionsAccountPrivacyPostgres(t *testing.T) {
	s := e2eNewServices(t)
	owner, _ := e2ePrivacySignup(t, s, "interaction_https_owner")
	reader, _ := e2ePrivacySignup(t, s, "interaction_https_reader")
	channel := postHTTPSChannel(t, s, owner)
	id := postHTTPSIdentity(t, s, owner, "Author", 91)
	created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 92), owner, "", posts.CreatePostInput{ChannelID: channel, IdentityID: id, Title: "Interaction", Body: "Body"}, 202)
	if _, err := s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal(err)
	}
	post := created["postId"].(string)
	base := "/api/v1/posts/" + post
	for _, kind := range []string{"like", "favorite"} {
		field := "liked"
		if kind == "favorite" {
			field = "favorited"
		}
		for i := 0; i < 2; i++ {
			r := postHTTPSJSON(t, s, "PUT", base+"/"+kind, reader, "", map[string]any{field: true}, 200)
			postHTTPSFields(t, r, "postId", "likeCount", "favoriteCount", "commentCount", "likedByMe", "favoritedByMe")
		}
	}
	r := postHTTPSJSON(t, s, "GET", base+"/interactions", owner, "", nil, 200)
	if r["likedByMe"] != false || r["favoritedByMe"] != false || r["likeCount"] != float64(1) || r["favoriteCount"] != float64(1) {
		t.Fatal("private flags crossed accounts", r)
	}
	batch := postHTTPSJSON(t, s, "POST", "/api/v1/feed/interactions", reader, "", map[string]any{"postIds": []string{post}}, 200)
	postHTTPSFields(t, batch, "items")
	if batch["items"].([]any)[0].(map[string]any)["likedByMe"] != true {
		t.Fatal("reader state lost")
	}
	feed := postHTTPSJSON(t, s, "GET", "/api/v1/feed", reader, "", nil, 200)
	postHTTPSFields(t, feed["items"].([]any)[0].(map[string]any), "postId", "channelId", "title", "body", "author", "publishedAt", "viewCount")
	postHTTPSJSON(t, s, "POST", base+"/delete", owner, httpTestEncoding(16, 93), nil, 200)
	postHTTPSJSON(t, s, "GET", base+"/interactions", reader, "", nil, 404)
	postHTTPSJSON(t, s, "PUT", base+"/like", reader, "", map[string]any{"liked": false}, 404)
	if err := s.gate.Freeze(context.Background(), "interaction HTTPS fixture"); err != nil {
		t.Fatal(err)
	}
	postHTTPSJSON(t, s, "POST", "/api/v1/feed/interactions", reader, "", map[string]any{"postIds": []string{post}}, 503)
}
