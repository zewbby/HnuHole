package authprivacyhttp

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
)

func TestCommentTextHTTPSPostgres(t *testing.T) {
	ctx := context.Background()
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		result, e := c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: e2eKey(t), FingerprintKey: e2eKey(t)})
		if e != nil {
			t.Fatal(e)
		}
		return result
	})
	token, account := e2ePrivacySignup(t, s, "ct_http")
	id := postHTTPSIdentity(t, s, token, "HTTP身份", 0x62)
	channel := postHTTPSChannel(t, s, token)
	post := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 0x63), token, "", map[string]any{"channelId": channel, "identityId": id, "title": "文字后端", "body": "帖子"}, 202)
	if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	postID := post["postId"].(string)
	taskID := uuid.NewString()
	intent := map[string]any{"operation": "CREATE", "taskId": taskID, "identityId": id, "postId": postID, "rootCommentId": nil, "targetCommentId": nil, "body": "HTTP原文\r\n e\u0301", "image": nil}
	key := httpTestEncoding(16, 0x64)
	path := "/api/v1/comment-commands/" + key
	accepted := postHTTPSJSON(t, s, "PUT", path, token, "", intent, 202)
	postHTTPSFields(t, accepted, "state", "operation", "taskId", "attemptVersion")
	if accepted["state"] != "ACCEPTED" {
		t.Fatal("not accepted")
	}
	replay := postHTTPSJSON(t, s, "PUT", path, token, "", intent, 202)
	if replay["taskId"] != taskID {
		t.Fatal("duplicate task")
	}
	own := postHTTPSJSON(t, s, "GET", "/api/v1/me/comment-tasks/"+taskID, token, "", nil, 200)
	if own["state"] != "ACCEPTED" {
		t.Fatal("task observation")
	}
	if _, e := s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	own = postHTTPSJSON(t, s, "GET", "/api/v1/me/comment-tasks/"+taskID, token, "", nil, 200)
	commentID := own["publishedCommentId"].(string)
	page := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID+"/comments?limit=1", token, "", nil, 200)
	first := page["comments"].([]any)[0].(map[string]any)
	postHTTPSFields(t, first, "id", "postId", "rootCommentId", "targetCommentId", "body", "image", "author", "replyTo", "isPostAuthor", "publishedAt", "likeCount", "likedByMe", "replyCount")
	if first["body"] != intent["body"] || first["isPostAuthor"] != true {
		t.Fatal("public projection")
	}
	data, _ := json.Marshal(page)
	encoded := strings.ToLower(string(data))
	if strings.Contains(encoded, "identityid") || strings.Contains(encoded, "accountid") || strings.Contains(encoded, "taskid") {
		t.Fatal("private identifiers leaked")
	}
	replyID := uuid.NewString()
	reply := map[string]any{"operation": "CREATE", "taskId": replyID, "identityId": id, "postId": postID, "rootCommentId": commentID, "targetCommentId": commentID, "body": "回复具体内容", "image": nil}
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 0x65), token, "", reply, 202)
	if _, e := s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	replies := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID+"/comments/"+commentID+"/replies", token, "", nil, 200)
	if len(replies["comments"].([]any)) != 1 {
		t.Fatal("reply missing")
	}
	// Immutable receipt, mismatched intent, unknown observation and seal.
	receipt := postHTTPSJSON(t, s, "GET", path, token, "", nil, 200)
	if receipt["state"] != "ACCEPTED" {
		t.Fatal("receipt not original")
	}
	intent["body"] = "更改"
	postHTTPSJSON(t, s, "PUT", path, token, "", intent, 409)
	unknownKey := httpTestEncoding(16, 0x66)
	unknownPath := "/api/v1/comment-commands/" + unknownKey
	unknown := postHTTPSJSON(t, s, "GET", unknownPath, token, "", nil, 200)
	if unknown["state"] != "UNKNOWN_NOT_OBSERVED" {
		t.Fatal(unknown)
	}
	pendingID := uuid.NewString()
	pending := comments.Intent{Operation: comments.Create, TaskID: pendingID, IdentityID: id, PostID: postID, Body: "迟到文字"}
	digest, _ := comments.RequestDigest(pending)
	sealed := postHTTPSJSON(t, s, "POST", unknownPath+"/seal", token, "", map[string]any{"operation": "CREATE", "requestDigest": hex.EncodeToString(digest[:])}, 200)
	if sealed["state"] != "NOT_ACCEPTED" {
		t.Fatal(sealed)
	}
	delayed := map[string]any{"operation": "CREATE", "taskId": pendingID, "identityId": id, "postId": postID, "rootCommentId": nil, "targetCommentId": nil, "body": "迟到文字", "image": nil}
	postHTTPSJSON(t, s, "PUT", unknownPath, token, "", delayed, 200)
	// Strict text-only boundary; a media object is never silently dropped.
	delayed["image"] = map[string]any{}
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 0x67), token, "", delayed, 400)
	postHTTPSJSON(t, s, "GET", "/api/v1/me/comment-tasks/"+taskID, "", "", nil, 401)
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID+"/comments?limit=1&limit=2", token, "", nil, 400)
	// Drive actual task transitions through HTTP. The test-only control uses
	// the existing final-Gate mute API; it adds no administrative public route.
	failureID := uuid.NewString()
	delayed["image"] = nil
	delayed["taskId"] = failureID
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 0x68), token, "", delayed, 202)
	ends := time.Now().Add(time.Second)
	if e := s.c.ApplyAccountMute(ctx, uuid.MustParse(account), 1, &ends); e != nil {
		t.Fatal(e)
	}
	failed := postHTTPSJSON(t, s, "GET", "/api/v1/me/comment-tasks/"+failureID, token, "", nil, 200)
	if failed["state"] != "FAILED" || failed["failureCode"] != "PUBLISHING_STOPPED" {
		t.Fatal("failure not observed")
	}
	s.advanceC(10 * time.Second)
	retry := map[string]any{"operation": "RETRY", "taskId": failureID, "expectedAttemptVersion": 1, "body": "HTTP重试", "image": nil}
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 0x69), token, "", retry, 202)
	if _, e := s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	final := postHTTPSJSON(t, s, "GET", "/api/v1/me/comment-tasks/"+failureID, token, "", nil, 200)
	if final["state"] != "PUBLISHED" || final["attemptVersion"] != float64(2) {
		t.Fatal("HTTP retry did not publish")
	}
	abandonID := uuid.NewString()
	delayed["taskId"] = abandonID
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 0x6a), token, "", delayed, 202)
	if e := s.c.ApplyAccountMute(ctx, uuid.MustParse(account), 2, nil); e != nil {
		t.Fatal(e)
	}
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 0x6b), token, "", map[string]any{"operation": "ABANDON", "taskId": abandonID, "expectedAttemptVersion": 1}, 200)
	abandoned := postHTTPSJSON(t, s, "GET", "/api/v1/me/comment-tasks/"+abandonID, token, "", nil, 200)
	if abandoned["state"] != "ABANDONED" || abandoned["content"] != nil || abandoned["failureCode"] != nil {
		t.Fatal("HTTP abandonment")
	}
}
