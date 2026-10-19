package authprivacyhttp

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCommentBusinessHTTPSPostgres(t *testing.T) {
	ctx := context.Background()
	python := os.Getenv("POST_MEDIA_PYTHON")
	if python == "" {
		t.Skip("real image validator required")
	}
	script, _ := filepath.Abs("../../media/validate_image.py")
	if configured := os.Getenv("POST_MEDIA_VALIDATOR"); configured != "" {
		script = configured
	}
	source, e := os.ReadFile(script)
	if e != nil {
		t.Fatal(e)
	}
	hash := sha256.Sum256(source)
	v, e := postmedia.NewProcessValidator(python, script, hex.EncodeToString(hash[:]))
	if e != nil {
		t.Fatal(e)
	}
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		var e error
		c, e = c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: e2eKey(t), FingerprintKey: e2eKey(t)})
		if e != nil {
			t.Fatal(e)
		}
		c, e = c.WithPostImages(ctx, v)
		if e != nil {
			t.Fatal(e)
		}
		c, e = c.WithModeration(ctx)
		if e != nil {
			t.Fatal(e)
		}
		return c
	})
	token, account := e2ePrivacySignup(t, s, "cb_http")
	reader, _ := e2ePrivacySignup(t, s, "cb_http_other")
	identity := postHTTPSIdentity(t, s, token, "真实评论", 0x81)
	channel := postHTTPSChannel(t, s, token)
	post := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 0x82), token, "", map[string]any{"channelId": channel, "identityId": identity, "title": "完整评论链路", "body": "合成帖子"}, 202)
	if _, e = s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	postID := post["postId"].(string)
	data, e := os.ReadFile(filepath.Join(os.Getenv("POST_MEDIA_FIXTURES"), "gif.bin"))
	if e != nil {
		t.Fatal(e)
	}
	meta, e := v.Inspect(ctx, data)
	if e != nil {
		t.Fatal(e)
	}
	selection := postmedia.Selection{MediaID: uuid.NewString(), SHA256: meta.SHA256, ByteLength: meta.ByteLength, MIME: meta.MIME, Width: meta.Width, Height: meta.Height}
	task := uuid.NewString()
	input := map[string]any{"operation": "CREATE", "taskId": task, "identityId": identity, "postId": postID, "rootCommentId": nil, "targetCommentId": nil, "body": "", "image": selection}
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 0x83), token, "", input, 202)
	uploadPath := "/api/v1/me/comment-tasks/" + task + "/attempts/1/image"
	for _, who := range []string{reader, token, token} {
		req, _ := http.NewRequest("PUT", s.cPublic.URL+uploadPath, bytes.NewReader(data))
		req.Header.Set("Authorization", "Bearer "+who)
		req.Header.Set("Content-Type", meta.MIME)
		res, e := s.client.Do(req)
		if e != nil {
			t.Fatal(e)
		}
		io.Copy(io.Discard, res.Body)
		res.Body.Close()
		expected := 200
		if who == reader {
			expected = 404
		}
		if res.StatusCode != expected {
			t.Fatalf("upload %d", res.StatusCode)
		}
	}
	if _, e = s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	own := postHTTPSJSON(t, s, "GET", "/api/v1/me/comment-tasks/"+task, token, "", nil, 200)
	cid := own["publishedCommentId"].(string)
	page := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID+"/comments", reader, "", nil, 200)
	image := page["comments"].([]any)[0].(map[string]any)["image"].(map[string]any)
	imagePath := "/api/v1/posts/" + postID + "/comments/" + cid + "/images/" + image["contentVersionId"].(string) + "/original"
	req, _ := http.NewRequest("GET", s.cPublic.URL+imagePath, nil)
	req.Header.Set("Authorization", "Bearer "+reader)
	res, e := s.client.Do(req)
	if e != nil {
		t.Fatal(e)
	}
	original, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if res.StatusCode != 200 || !bytes.Equal(original, data) || res.Header.Get("Access-Valid-Until") == "" {
		t.Fatal("protected original")
	}
	key := httpTestEncoding(16, 0x84)
	likePath := "/api/v1/comments/" + cid + "/like-commands/" + key
	for n := 0; n < 2; n++ {
		r := postHTTPSJSON(t, s, "PUT", likePath, reader, "", map[string]any{"liked": true}, 200)
		if r["likeCount"] != float64(1) {
			t.Fatal("like replay", r)
		}
	}
	loc := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID+"/comments/"+cid+"/location", reader, "", nil, 200)
	if loc["commentId"] != cid {
		t.Fatal(loc)
	}
	// A current real failure is returned through the existing notification HTTP.
	failed := uuid.NewString()
	input["taskId"] = failed
	input["body"] = "失败内容"
	input["image"] = nil
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 0x85), token, "", input, 202)
	end := time.Now().Add(time.Hour)
	if e = s.c.ApplyAccountMute(ctx, uuid.MustParse(account), 1, &end); e != nil {
		t.Fatal(e)
	}
	notices := postHTTPSJSON(t, s, "GET", "/api/v1/system-notifications?identityId="+identity, token, "", nil, 200)
	encoded, _ := json.Marshal(notices)
	if !bytes.Contains(encoded, []byte("COMMENT_FAILURE")) || !bytes.Contains(encoded, []byte(failed)) {
		t.Fatal("real notification datasource")
	}
	// Another account cannot delete it; a muted owner can.
	forbidden := postHTTPSJSON(t, s, "PUT", "/api/v1/comments/"+cid+"/delete-commands/"+httpTestEncoding(16, 0x86), reader, "", map[string]any{}, 200)
	if forbidden["state"] != "REJECTED" {
		t.Fatal(forbidden)
	}
	postHTTPSJSON(t, s, "PUT", "/api/v1/comments/"+cid+"/delete-commands/"+httpTestEncoding(16, 0x87), token, "", map[string]any{}, 200)
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID+"/comments/"+cid+"/location", reader, "", nil, 404)
	postHTTPSJSON(t, s, "GET", imagePath, reader, "", nil, 404)
}
