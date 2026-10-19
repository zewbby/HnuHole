package authprivacyhttp

import (
	"context"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestRealHTTPSFeedViewsPreferencesAndCompatibilityPostgres(t *testing.T) {
	s := e2eNewServices(t)
	owner, _ := e2ePrivacySignup(t, s, "feed_https_owner")
	reader, _ := e2ePrivacySignup(t, s, "feed_https_reader")
	channel := postHTTPSChannel(t, s, owner)
	id := postHTTPSIdentity(t, s, owner, "FeedAuthor", 81)
	created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 82), owner, "", posts.CreatePostInput{ChannelID: channel, IdentityID: id, Title: "Feed title", Body: "Feed body"}, 202)
	if _, err := s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal(err)
	}
	post := created["postId"].(string)
	feed := postHTTPSJSON(t, s, "GET", "/api/v1/feed", reader, "", nil, 200)
	item := feed["items"].([]any)[0].(map[string]any)
	postHTTPSFields(t, item, "postId", "channelId", "title", "body", "author", "publishedAt", "viewCount")
	if item["viewCount"] != float64(0) {
		t.Fatal("exposure counted")
	}
	for _, token := range []string{owner, reader, reader} {
		view := postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+post+"/views", token, "", nil, 200)
		postHTTPSFields(t, view, "postId", "viewCount")
		want := float64(1)
		if token == owner {
			want = 0
		}
		if view["viewCount"] != want {
			t.Fatal("view count/dedup failed")
		}
	}
	feed = postHTTPSJSON(t, s, "GET", "/api/v1/feed", reader, "", nil, 200)
	if feed["items"].([]any)[0].(map[string]any)["viewCount"] != float64(1) {
		t.Fatal("feed total stale")
	}
	postHTTPSJSON(t, s, "PUT", "/api/v1/me/feed-preferences", reader, "", posts.FeedPreferences{BlockedChannelIDs: []string{channel}}, 200)
	prefs := postHTTPSJSON(t, s, "GET", "/api/v1/me/feed-preferences", reader, "", nil, 200)
	if len(prefs["blockedChannelIds"].([]any)) != 1 {
		t.Fatal("preference lost")
	}
	feed = postHTTPSJSON(t, s, "GET", "/api/v1/feed?channelId="+channel, reader, "", nil, 200)
	if len(feed["items"].([]any)) != 0 {
		t.Fatal("blocked selection bypass")
	}
	legacy := postHTTPSJSON(t, s, "GET", "/api/v1/channels/"+channel+"/posts", reader, "", nil, 200)
	postHTTPSPublic(t, legacy["items"].([]any)[0].(map[string]any), false)
	detail := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post, reader, "", nil, 200)
	postHTTPSPublic(t, detail["post"].(map[string]any), true)
	postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+post+"/delete", owner, httpTestEncoding(16, 83), nil, 200)
	postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+post+"/views", reader, "", nil, 404)
	if err := s.gate.Freeze(context.Background(), "feed HTTPS regression"); err != nil {
		t.Fatal(err)
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/feed", reader, "", nil, 503)
	postHTTPSJSON(t, s, "PUT", "/api/v1/me/feed-preferences", reader, "", posts.FeedPreferences{BlockedChannelIDs: []string{}}, 503)
}
