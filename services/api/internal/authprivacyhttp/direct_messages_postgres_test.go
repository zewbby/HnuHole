package authprivacyhttp

import (
	"context"
	"encoding/base64"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

func TestDMReliableTextPostgres(t *testing.T) {
	ctx := context.Background()
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		v, e := c.WithDirectMessages(ctx)
		if e != nil {
			t.Fatal(e)
		}
		return v
	})
	a, accountA := e2ePrivacySignup(t, s, "dm_sender")
	b, _ := e2ePrivacySignup(t, s, "dm_receiver")
	stranger, _ := e2ePrivacySignup(t, s, "dm_stranger")
	ia := postHTTPSIdentity(t, s, a, "甲同学", 41)
	ib := postHTTPSIdentity(t, s, b, "乙同学", 42)
	channel := postHTTPSChannel(t, s, b)
	p := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 43), b, "", map[string]any{"channelId": channel, "identityId": ib, "title": "私信入口", "body": "联系作者"}, 202)
	if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	intent := authprivacy.DMTextIntent{IdentityID: ia, PeerID: ib, SourcePostID: p["postId"].(string), Text: "原文\n你好 👨‍👩‍👧", Attempt: 1}
	id := uuid.NewString()
	path := "/api/v1/dm/commands/" + id
	result := postHTTPSJSON(t, s, "PUT", path, a, "", intent, 200)
	if result["state"] != "SENT" {
		t.Fatal(result)
	}
	conv := result["conversationId"].(string)
	message := result["messageId"].(string)
	replay := postHTTPSJSON(t, s, "PUT", path, a, "", intent, 200)
	if replay["messageId"] != message {
		t.Fatal("idempotent replay changed message")
	}
	changed := intent
	changed.Text = "不同正文"
	postHTTPSJSON(t, s, "PUT", path, a, "", changed, 409)
	absent := postHTTPSJSON(t, s, "GET", path, stranger, "", nil, 200)
	if absent["state"] != "ABSENT" {
		t.Fatal("receipt leaked")
	}
	var binding string
	if e := s.cp.QueryRow(ctx, `SELECT identity_id::text FROM c_posts.post_identity_bindings WHERE account_id=$1 AND post_id=$2`, accountA, intent.SourcePostID).Scan(&binding); e != nil || binding != ia {
		t.Fatal("binding not atomic", e)
	}
	failedID := uuid.NewString()
	failed := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+failedID, a, "", intent, 200)
	if failed["state"] != "FAILED" || failed["errorCode"] != "WAITING_FOR_REPLY" {
		t.Fatal("first contact quota", failed)
	}
	pending := postHTTPSJSON(t, s, "GET", "/api/v1/dm/pending", b, "", nil, 200)["items"].([]any)
	if len(pending) != 1 || pending[0].(map[string]any)["text"] != intent.Text {
		t.Fatal("pending body lost")
	}
	// Repeated pulls before durable local ACK must replay exactly the same item.
	again := postHTTPSJSON(t, s, "GET", "/api/v1/dm/pending", b, "", nil, 200)["items"].([]any)
	if again[0].(map[string]any)["messageId"] != message {
		t.Fatal("pull is destructive")
	}
	ids := map[string]any{"messageIds": []string{message}}
	postHTTPSJSON(t, s, "POST", "/api/v1/dm/read", b, "", ids, 409)
	postHTTPSJSON(t, s, "POST", "/api/v1/dm/ack", stranger, "", ids, 409)
	postHTTPSJSON(t, s, "POST", "/api/v1/dm/ack", b, "", ids, 200)
	postHTTPSJSON(t, s, "POST", "/api/v1/dm/ack", b, "", ids, 200)
	if len(postHTTPSJSON(t, s, "GET", "/api/v1/dm/pending", b, "", nil, 200)["items"].([]any)) != 0 {
		t.Fatal("ACK failed")
	}
	var body *string
	if e := s.cp.QueryRow(ctx, `SELECT body FROM c_dm.messages WHERE message_id=$1`, message).Scan(&body); e != nil || body != nil {
		t.Fatal("ACK retained body", e)
	}
	dir := postHTTPSJSON(t, s, "GET", "/api/v1/dm/conversations?identityId="+ib, b, "", nil, 200)["items"].([]any)
	if dir[0].(map[string]any)["unread"] != float64(1) {
		t.Fatal("ACK marked read")
	}
	reply := authprivacy.DMTextIntent{IdentityID: ib, PeerID: ia, ConversationID: conv, Text: "回复", Attempt: 1}
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), b, "", reply, 200)
	// Retry only the original failed intent and monotonically advance attempt.
	intent.Attempt = 2
	retried := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+failedID, a, "", intent, 200)
	if retried["state"] != "SENT" {
		t.Fatal("original retry failed", retried)
	}
	postHTTPSJSON(t, s, "POST", "/api/v1/dm/read", b, "", ids, 200)
	dir = postHTTPSJSON(t, s, "GET", "/api/v1/dm/conversations?identityId="+ib, b, "", nil, 200)["items"].([]any)
	if dir[0].(map[string]any)["unread"] != float64(1) {
		t.Fatal("read swallowed later arrival")
	}
	// Lost response is reconciled from durable receipt even after body purge.
	observed := postHTTPSJSON(t, s, "GET", path, a, "", nil, 200)
	if observed["messageId"] != message {
		t.Fatal("receipt lost after ACK")
	}
	// Concurrent replays all resolve to the same durable intent.
	raw, _ := base64.RawURLEncoding.DecodeString(a)
	var bearer [32]byte
	copy(bearer[:], raw)
	var wg sync.WaitGroup
	for n := 0; n < 8; n++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r, e := s.c.SendDMText(ctx, bearer, failedID, intent)
			if e != nil || r.Value.(authprivacy.DMReceipt).MessageID != retried["messageId"] {
				t.Errorf("concurrent replay: %v", e)
			}
		}()
	}
	wg.Wait()
	// Final authorization gate protects every DM operation.
	if e := s.gate.Freeze(ctx, "DM scoped regression"); e != nil {
		t.Fatal(e)
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/pending", b, "", nil, 503)
	postHTTPSJSON(t, s, "PUT", path, a, "", intent, 503)
}
