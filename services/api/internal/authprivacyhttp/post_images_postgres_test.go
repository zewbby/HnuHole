package authprivacyhttp

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

func TestRealHTTPSPostImagesUploadReadRevocationPostgres(t *testing.T) {
	python := os.Getenv("POST_MEDIA_PYTHON")
	if python == "" {
		t.Skip("dedicated image validator absent")
	}
	script, e := filepath.Abs("../../media/validate_image.py")
	if e != nil {
		t.Fatal(e)
	}
	source, e := os.ReadFile(script)
	if e != nil {
		t.Fatal(e)
	}
	hash := sha256.Sum256(source)
	validator, e := postmedia.NewProcessValidator(python, script, hex.EncodeToString(hash[:]))
	if e != nil {
		t.Fatal(e)
	}
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		enabled, e := c.WithPostImages(context.Background(), validator)
		if e != nil {
			t.Fatal(e)
		}
		return enabled
	})
	token, _ := e2ePrivacySignup(t, s, "media_https")
	reader, _ := e2ePrivacySignup(t, s, "media_http_reader")
	id := postHTTPSIdentity(t, s, token, "图片作者", 73)
	channel := postHTTPSChannel(t, s, token)
	var selections []postmedia.Selection
	var originals [][]byte
	for _, format := range []string{"gif", "webp"} {
		root := os.Getenv("POST_MEDIA_FIXTURES")
		data, e := os.ReadFile(filepath.Join(root, format+".bin"))
		if e != nil {
			t.Fatal(e)
		}
		raw, e := os.ReadFile(filepath.Join(root, format+".json"))
		if e != nil {
			t.Fatal(e)
		}
		var m postmedia.Metadata
		if json.Unmarshal(raw, &m) != nil {
			t.Fatal("fixture metadata")
		}
		selections = append(selections, postmedia.Selection{MediaID: uuid.NewString(), SHA256: m.SHA256, ByteLength: m.ByteLength, MIME: m.MIME, Width: m.Width, Height: m.Height})
		originals = append(originals, data)
	}
	accepted := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 74), token, "", map[string]any{"title": "原格式动画", "body": "", "channelId": channel, "identityId": id, "images": selections}, 202)
	task, post := accepted["taskId"].(string), accepted["postId"].(string)
	base := "/api/v1/me/post-tasks/" + task + "/attempts/1/images"
	postHTTPSJSON(t, s, "GET", base, reader, "", nil, 404)
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post+"/images", reader, "", nil, 404)
	var grants []string
	for i, item := range selections {
		grant := postHTTPSJSON(t, s, "POST", base+"/"+item.MediaID+"/upload-grant", token, "", nil, 200)
		grants = append(grants, grant["uploadToken"].(string))
		mediaHTTPSBytes(t, s, "PUT", base+"/"+item.MediaID+"/bytes", "Upload "+grants[i], item.MIME, originals[i], 204)
	}
	if _, e = s.c.PublishAcceptedPosts(context.Background(), 100); e != nil {
		t.Fatal(e)
	}
	detail := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post, reader, "", nil, 200)
	if detail["post"].(map[string]any)["imageCount"] != float64(2) {
		t.Fatal("detail lost image-only content")
	}
	group := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post+"/images", reader, "", nil, 200)
	items := group["images"].([]any)
	if len(items) != 2 {
		t.Fatal("group incomplete")
	}
	for i, item := range items {
		img := item.(map[string]any)
		if img["animated"] != true || img["frames"] != float64(2) {
			t.Fatal("animation changed")
		}
		original := img["original"].(map[string]any)["path"].(string)
		got := mediaHTTPSBytes(t, s, "GET", original, "Bearer "+reader, "", nil, 200)
		if !bytes.Equal(got, originals[i]) {
			t.Fatal("HTTPS original bytes changed")
		}
		mediaHTTPSBytes(t, s, "GET", original, "Upload "+grants[i], "", nil, 401)
		wrongPost := "/api/v1/posts/" + uuid.NewString() + "/images/" + img["contentVersionId"].(string) + "/original"
		mediaHTTPSBytes(t, s, "GET", wrongPost, "Bearer "+reader, "", nil, 404)
	}
	original := items[0].(map[string]any)["original"].(map[string]any)["path"].(string)
	postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+post+"/delete", token, httpTestEncoding(16, 75), nil, 200)
	mediaHTTPSBytes(t, s, "GET", original, "Bearer "+reader, "", nil, 404)
	if e = s.gate.Freeze(context.Background(), "synthetic media HTTP freeze"); e != nil {
		t.Fatal(e)
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post+"/images", reader, "", nil, 503)
}

// Actual HTTPS transport + original bytes, never prints credentials or payloads.
func mediaHTTPSBytes(t *testing.T, s *e2eServices, method, path, authorization, mime string, data []byte, status int) []byte {
	t.Helper()
	r, e := http.NewRequest(method, s.cPublic.URL+path, bytes.NewReader(data))
	if e != nil {
		t.Fatal("request")
	}
	r.Header.Set("Authorization", authorization)
	if mime != "" {
		r.Header.Set("Content-Type", mime)
	}
	response, e := s.client.Do(r)
	if e != nil {
		t.Fatal("TLS transport")
	}
	defer response.Body.Close()
	raw, e := io.ReadAll(io.LimitReader(response.Body, postmedia.MaxBytes+1))
	if e != nil || response.StatusCode != status {
		t.Fatalf("media HTTP %s status=%d want=%d", method, response.StatusCode, status)
	}
	if response.Header.Get("Cache-Control") != "no-store" {
		t.Fatal("private media became cacheable")
	}
	if status == 200 {
		if response.Header.Get("Content-Type") != "image/gif" && response.Header.Get("Content-Type") != "image/webp" {
			t.Fatal("wrong original MIME")
		}
		if response.Header.Get("X-Content-Type-Options") != "nosniff" || response.Header.Get("ETag") != "" || response.Header.Get("Content-Disposition") != "attachment" {
			t.Fatal("unsafe media response envelope")
		}
	}
	return raw
}
