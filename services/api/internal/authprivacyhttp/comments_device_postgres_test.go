package authprivacyhttp

import (
	"context"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// Explicit opt-in private test server for the exclusive USB device window.
// Only synthetic disposable accounts, private CA, loopback TLS and owned PG.
func TestCommentBusinessDevicePostgres(t *testing.T) {
	file := os.Getenv("COMMENT_DEVICE_FIXTURE")
	if file == "" {
		t.Skip("exclusive device fixture not requested")
	}
	ctx := context.Background()
	script := os.Getenv("POST_MEDIA_VALIDATOR")
	source, e := os.ReadFile(script)
	if e != nil {
		t.Fatal(e)
	}
	h := sha256.Sum256(source)
	validator, e := postmedia.NewProcessValidator(os.Getenv("POST_MEDIA_PYTHON"), script, hex.EncodeToString(h[:]))
	if e != nil {
		t.Fatal(e)
	}
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		var e error
		c, e = c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: e2eKey(t), FingerprintKey: e2eKey(t)})
		if e != nil {
			t.Fatal(e)
		}
		c, e = c.WithPostImages(ctx, validator)
		if e != nil {
			t.Fatal(e)
		}
		c, e = c.WithModeration(ctx)
		if e != nil {
			t.Fatal(e)
		}
		return c
	})
	cert := mobileLabCertificate(t)
	tls, e := PublicTLSConfig(cert)
	if e != nil {
		t.Fatal(e)
	}
	var mu sync.Mutex
	paused := true
	drop := true
	creates := 0
	original := s.cPublic.Config.Handler
	s.cPublic = e2eServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := httptest.NewRecorder()
		original.ServeHTTP(rec, r)
		mu.Lock()
		mutation := r.Method == "PUT" && strings.HasPrefix(r.URL.Path, "/api/v1/comment-commands/")
		if mutation {
			creates++
		}
		lose := mutation && drop && rec.Code == 202
		if lose {
			drop = false
		}
		mu.Unlock()
		if lose {
			conn, _, err := w.(http.Hijacker).Hijack()
			if err != nil {
				t.Error(err)
				return
			}
			conn.Close()
			return
		}
		for k, v := range rec.Header() {
			w.Header()[k] = v
		}
		w.WriteHeader(rec.Code)
		w.Write(rec.Body.Bytes())
	}), tls)
	s.vPublic = e2eServer(t, s.vPublic.Config.Handler, tls)
	transport := s.client.Transport.(*http.Transport).Clone()
	transport.TLSClientConfig = transport.TLSClientConfig.Clone()
	transport.TLSClientConfig.RootCAs = transport.TLSClientConfig.RootCAs.Clone()
	root, e := x509.ParseCertificate(cert.Certificate[1])
	if e != nil {
		t.Fatal(e)
	}
	transport.TLSClientConfig.RootCAs.AddCert(root)
	s.client.Transport = transport
	t.Cleanup(transport.CloseIdleConnections)
	owner, ownerID := e2ePrivacySignup(t, s, "comment_device_owner")
	other, otherID := e2ePrivacySignup(t, s, "comment_device_other")
	identity := postHTTPSIdentity(t, s, owner, "真机原身份", 0xa1)
	channel := postHTTPSChannel(t, s, owner)
	post := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 0xa2), owner, "", map[string]any{"channelId": channel, "identityId": identity, "title": "评论真机验收", "body": "正文区域保持独立滚动。仅合成数据。"}, 202)
	if _, e = s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	secret := httpTestEncoding(32, 0xa3)
	control := e2eServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.Header.Get("Authorization") != "CommentLab "+secret {
			w.WriteHeader(403)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		switch r.URL.Path {
		case "/resume":
			mu.Lock()
			paused = false
			mu.Unlock()
		case "/pause":
			mu.Lock()
			paused = true
			mu.Unlock()
		case "/fail":
			end := time.Now().Add(time.Second)
			if e := s.c.ApplyAccountMute(r.Context(), uuid.MustParse(ownerID), 1, &end); e != nil {
				w.WriteHeader(500)
				return
			}
			s.advanceC(2 * time.Second)
		case "/counts":
			mu.Lock()
			n := creates
			mu.Unlock()
			json.NewEncoder(w).Encode(map[string]int{"creates": n})
			return
		default:
			w.WriteHeader(404)
			return
		}
		json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	}), tls)
	data, e := os.ReadFile(filepath.Join(os.Getenv("POST_MEDIA_FIXTURES"), "gif.bin"))
	if e != nil {
		t.Fatal(e)
	}
	metadata, e := validator.Inspect(ctx, data)
	if e != nil {
		t.Fatal(e)
	}
	selection := postmedia.Selection{MediaID: uuid.NewString(), SHA256: metadata.SHA256, ByteLength: metadata.ByteLength, MIME: metadata.MIME, Width: metadata.Width, Height: metadata.Height}
	fixture := map[string]any{"url": s.cPublic.URL, "verifier": s.vPublic.URL, "control": control.URL, "controlToken": secret, "certificatePem": string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Certificate[1]})), "token": owner, "accountId": ownerID, "otherToken": other, "otherAccountId": otherID, "identityId": identity, "postId": post["postId"], "taskId": uuid.NewString(), "image": selection, "imageBytes": base64.StdEncoding.EncodeToString(data), "run": uuid.NewString()}
	encoded, e := json.Marshal(fixture)
	if e != nil {
		t.Fatal(e)
	}
	if e = os.WriteFile(file, encoded, 0600); e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { os.Remove(file); os.Remove(file + ".stop") })
	t.Log("exclusive device fixture ready; private material remains outside repository")
	tick := time.NewTicker(250 * time.Millisecond)
	defer tick.Stop()
	renew := time.NewTicker(time.Minute)
	defer renew.Stop()
	timeout := time.NewTimer(20 * time.Minute)
	defer timeout.Stop()
	for {
		select {
		case <-tick.C:
			if _, e = os.Stat(file + ".stop"); e == nil {
				t.Log("device window completed")
				return
			}
			mu.Lock()
			hold := paused
			mu.Unlock()
			if !hold {
				if _, e = s.c.PublishAcceptedComments(ctx, 100); e != nil {
					t.Fatal(e)
				}
			}
		case <-renew.C:
			s.advanceC(0)
			s.advanceV(0)
		case <-timeout.C:
			t.Fatal("device fixture deadline exceeded")
			return
		}
	}
}
