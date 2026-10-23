package authprivacyhttp

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

func TestDMChatHTTPSPostgres(t *testing.T) {
	python, script := os.Getenv("POST_MEDIA_PYTHON"), os.Getenv("POST_MEDIA_VALIDATOR")
	if python == "" || script == "" {
		t.Skip("real pinned validator absent")
	}
	raw, e := os.ReadFile(script)
	if e != nil {
		t.Fatal(e)
	}
	hash := sha256.Sum256(raw)
	validator, e := postmedia.NewProcessValidator(python, script, hex.EncodeToString(hash[:]))
	if e != nil {
		t.Fatal(e)
	}
	ctx := context.Background()
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		v, e := c.WithPostImages(ctx, validator)
		if e != nil {
			t.Fatal(e)
		}
		v, e = v.WithDirectMessages(ctx)
		if e != nil {
			t.Fatal(e)
		}
		return v
	})
	a, _ := e2ePrivacySignup(t, s, "dm_p2_https_a")
	b, _ := e2ePrivacySignup(t, s, "dm_p2_https_b")
	ia := postHTTPSIdentity(t, s, a, "甲同学", 61)
	ib := postHTTPSIdentity(t, s, b, "乙同学", 62)
	channel := postHTTPSChannel(t, s, b)
	p := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 63), b, "", map[string]any{"channelId": channel, "identityId": ib, "title": "最初来源", "body": "来源内容"}, 202)
	if _, e = s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	first := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), a, "", authprivacy.DMTextIntent{IdentityID: ia, PeerID: ib, SourcePostID: p["postId"].(string), Text: "hello", Attempt: 1}, 200)
	conv := first["conversationId"].(string)
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), b, "", authprivacy.DMTextIntent{IdentityID: ib, PeerID: ia, ConversationID: conv, Text: "reply", Attempt: 1}, 200)
	data, e := os.ReadFile(filepath.Join(os.Getenv("POST_MEDIA_FIXTURES"), "png.bin"))
	if e != nil {
		t.Fatal(e)
	}
	raw, e = os.ReadFile(filepath.Join(os.Getenv("POST_MEDIA_FIXTURES"), "png.json"))
	if e != nil {
		t.Fatal(e)
	}
	var metadata postmedia.Metadata
	if e = json.Unmarshal(raw, &metadata); e != nil {
		t.Fatal(e)
	}
	in := authprivacy.DMImageIntent{IdentityID: ia, PeerID: ib, ConversationID: conv, GroupID: uuid.NewString(), GroupSize: 1, Selection: postmedia.Selection{MediaID: uuid.NewString(), SHA256: metadata.SHA256, ByteLength: metadata.ByteLength, MIME: metadata.MIME, Width: metadata.Width, Height: metadata.Height}, Data: base64.StdEncoding.EncodeToString(data), Attempt: 1}
	id := uuid.NewString()
	sent := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/chat/images/"+id, a, "", in, 200)
	if sent["state"] != "SENT" {
		t.Fatal(sent)
	}
	message := sent["messageId"].(string)
	checked := postHTTPSJSON(t, s, "GET", "/api/v1/dm/commands/"+id, a, "", nil, 200)
	if checked["messageId"] != message {
		t.Fatal("image receipt route")
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/media/"+message, a, "", nil, 409)
	media := postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/media/"+message, b, "", nil, 200)
	if media["data"] != in.Data || media["mediaId"] != in.MediaID {
		t.Fatal("private bytes")
	}
	pending := postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/pending", b, "", nil, 200)["items"].([]any)
	if len(pending) != 2 || pending[1].(map[string]any)["kind"] != "IMAGE" {
		t.Fatal("typed pending")
	}
	postHTTPSJSON(t, s, "POST", "/api/v1/dm/ack", b, "", map[string]any{"messageIds": []string{message}}, 200)
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/media/"+message, b, "", nil, 409)
	dir := postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/conversations?identityId="+ib, b, "", nil, 200)["items"].([]any)[0].(map[string]any)
	if dir["sourceTitle"] != "最初来源" || dir["unavailableUnread"] != float64(1) {
		t.Fatal("directory boundary", dir)
	}
	oid := uuid.NewString()
	operation := authprivacy.DMChatOperation{IdentityID: ia, ConversationID: conv, Operation: "RETRACT", MessageID: message}
	applied := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/chat/operations/"+oid, a, "", operation, 200)
	if applied["state"] != "APPLIED" {
		t.Fatal(applied)
	}
	checked = postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/operations/"+oid, a, "", nil, 200)
	if checked["state"] != "APPLIED" {
		t.Fatal(checked)
	}
	other := postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/operations/"+oid, b, "", nil, 200)
	if other["state"] != "ABSENT" {
		t.Fatal("operation privacy")
	}
	controls := postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/controls?after=0", b, "", nil, 200)
	if len(controls["items"].([]any)) != 1 {
		t.Fatal("durable controls")
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/controls?after=-1", b, "", nil, 400)
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/conversations?identityId="+ib+"&accountId=x", b, "", nil, 400)
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/chat/operations/"+uuid.NewString(), b, "", map[string]any{"identityId": ib, "conversationId": conv, "operation": "SETTINGS", "expectedVersion": 0, "note": "missing booleans"}, 400)
	// Frozen C gate blocks private reads and operations through the final boundary.
	if e = s.gate.Freeze(ctx, "DM P2 isolated final gate check"); e != nil {
		t.Fatal(e)
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/pending", b, "", nil, 503)
}
