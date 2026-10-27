package authprivacyhttp

import (
	"context"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"testing"
)

func TestNotificationInboxHTTPSPostgres(t *testing.T) {
	ctx := context.Background()
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		result, e := c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: e2eKey(t), FingerprintKey: e2eKey(t)})
		if e != nil {
			t.Fatal(e)
		}
		return result
	})
	owner, _ := e2ePrivacySignup(t, s, "notice_http_owner")
	sender, _ := e2ePrivacySignup(t, s, "notice_http_sender")
	id := postHTTPSIdentity(t, s, owner, "接收身份", 0x31)
	other := postHTTPSIdentity(t, s, sender, "发言身份", 0x32)
	channel := postHTTPSChannel(t, s, owner)
	post := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 0x33), owner, "", map[string]any{"channelId": channel, "identityId": id, "title": "通知测试", "body": "正文"}, 202)
	if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	postID := post["postId"].(string)
	task := uuid.NewString()
	intent := map[string]any{"operation": "CREATE", "taskId": task, "postId": postID, "identityId": other, "rootCommentId": nil, "targetCommentId": nil, "body": "来看看", "image": nil}
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 0x34), sender, "", intent, 202)
	listPath := "/api/v1/notifications?identityId=" + id
	page := postHTTPSJSON(t, s, "GET", listPath, owner, "", nil, 200)
	if len(page["items"].([]any)) != 0 {
		t.Fatal("accepted notification escaped transaction")
	}
	if _, e := s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	page = postHTTPSJSON(t, s, "GET", listPath+"&category=reply&unreadOnly=true&limit=1", owner, "", nil, 200)
	items := page["items"].([]any)
	if len(items) != 1 {
		t.Fatal(page)
	}
	n := items[0].(map[string]any)
	if n["isReply"] != true || n["postId"] != postID {
		t.Fatal(n)
	}
	counts := postHTTPSJSON(t, s, "GET", "/api/v1/notifications/unread-counts?identityId="+id, owner, "", nil, 200)
	if counts["all"] != float64(1) || counts["reply"] != float64(1) {
		t.Fatal(counts)
	}
	read := "/api/v1/notifications/" + n["id"].(string) + "/read?identityId=" + id
	postHTTPSJSON(t, s, "POST", read, owner, "", map[string]any{"seenVersion": n["version"]}, 200)
	page = postHTTPSJSON(t, s, "GET", listPath+"&unreadOnly=true", owner, "", nil, 200)
	if len(page["items"].([]any)) != 0 {
		t.Fatal("read did not clear exact event")
	}
	postHTTPSJSON(t, s, "GET", listPath, sender, "", nil, 404)
	postHTTPSJSON(t, s, "GET", listPath, "", "", nil, 401)
	for _, suffix := range []string{"&limit=1&limit=2", "&category=invalid", "&unreadOnly=1", "&cursor=invalid", "&unknown=true"} {
		postHTTPSJSON(t, s, "GET", listPath+suffix, owner, "", nil, 400)
	}
	postHTTPSJSON(t, s, "POST", read, owner, "", map[string]any{"seenVersion": 0}, 400)
	postHTTPSJSON(t, s, "POST", read, owner, "", map[string]any{"seenVersion": 1, "accountId": id}, 400)
}
