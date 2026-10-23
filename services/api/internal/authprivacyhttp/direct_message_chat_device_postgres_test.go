package authprivacyhttp

import (
	"bytes"
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
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Opt-in real TLS/SQL fixture, synthetic accounts only. The Android driver
// receives capabilities through a private local file, never source or logs.
func TestDMChatDevicePostgres(t *testing.T) {
	file := os.Getenv("DM_CHAT_DEVICE_FIXTURE")
	if file == "" {
		t.Skip("exclusive Android fixture not requested")
	}
	python, script := os.Getenv("POST_MEDIA_PYTHON"), os.Getenv("POST_MEDIA_VALIDATOR")
	source, e := os.ReadFile(script)
	if e != nil {
		t.Fatal(e)
	}
	digest := sha256.Sum256(source)
	validator, e := postmedia.NewProcessValidator(python, script, hex.EncodeToString(digest[:]))
	if e != nil {
		t.Fatal(e)
	}
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		v, e := c.WithPostImages(context.Background(), validator)
		if e != nil {
			t.Fatal(e)
		}
		v, e = v.WithDirectMessages(context.Background())
		if e != nil {
			t.Fatal(e)
		}
		v, e = v.WithModeration(context.Background())
		if e != nil {
			t.Fatal(e)
		}
		return v
	})
	cert := mobileLabCertificate(t)
	cfg, e := PublicTLSConfig(cert)
	if e != nil {
		t.Fatal(e)
	}
	original := s.cPublic.Config.Handler
	s.cPublic = e2eServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Fault injection is limited to synthetic P2 media bytes. Preserve manifest,
		// length, identity, command and attempt so real decoding persists INVALID_IMAGE.
		if r.Method == "PUT" && strings.HasPrefix(r.URL.Path, "/api/v1/dm/chat/images/") {
			raw, e := io.ReadAll(io.LimitReader(r.Body, 14*1024*1024+8193))
			if e != nil {
				http.Error(w, "fixture input", 400)
				return
			}
			var in map[string]any
			if json.Unmarshal(raw, &in) == nil && in["attempt"] == float64(1) && (in["position"] == float64(7) || in["position"] == float64(8)) {
				encoded, _ := in["data"].(string)
				data, e := base64.StdEncoding.DecodeString(encoded)
				if e == nil && len(data) > 0 {
					data[0] ^= 255
					in["data"] = base64.StdEncoding.EncodeToString(data)
					raw, _ = json.Marshal(in)
				}
			}
			r.Body = io.NopCloser(bytes.NewReader(raw))
			r.ContentLength = int64(len(raw))
		}
		original.ServeHTTP(w, r)
	}), cfg)
	root, e := x509.ParseCertificate(cert.Certificate[1])
	if e != nil {
		t.Fatal(e)
	}
	tr := s.client.Transport.(*http.Transport).Clone()
	tr.TLSClientConfig = tr.TLSClientConfig.Clone()
	tr.TLSClientConfig.RootCAs = tr.TLSClientConfig.RootCAs.Clone()
	tr.TLSClientConfig.RootCAs.AddCert(root)
	s.client.Transport = tr
	t.Cleanup(tr.CloseIdleConnections)
	a, aa := e2ePrivacySignup(t, s, "dm_chat_device_sender")
	b, ba := e2ePrivacySignup(t, s, "dm_chat_device_receiver")
	third, _ := e2ePrivacySignup(t, s, "dm_chat_device_stranger")
	ia := postHTTPSIdentity(t, s, a, "私信甲", 91)
	ib := postHTTPSIdentity(t, s, b, "私信乙", 92)
	channel := postHTTPSChannel(t, s, b)
	p := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 93), b, "", map[string]any{"channelId": channel, "identityId": ib, "title": "可靠文字验收", "body": "仅合成账号与合成内容"}, 202)
	if _, e = s.c.PublishAcceptedPosts(context.Background(), 100); e != nil {
		t.Fatal(e)
	}
	first := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), a, "", authprivacy.DMTextIntent{IdentityID: ia, PeerID: ib, SourcePostID: p["postId"].(string), Text: "图片验收首发", Attempt: 1}, 200)
	conv := first["conversationId"].(string)
	reply := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), b, "", authprivacy.DMTextIntent{IdentityID: ib, PeerID: ia, ConversationID: conv, Text: "图片验收回复", Attempt: 1}, 200)
	if reply["state"] != "SENT" {
		t.Fatal("fixture conversation not open")
	}
	u, _ := url.Parse(s.cPublic.URL)
	imageData, e := os.ReadFile(filepath.Join(os.Getenv("POST_MEDIA_FIXTURES"), "png.bin"))
	if e != nil {
		t.Fatal(e)
	}
	fixture := map[string]string{"DM_IMAGE": base64.StdEncoding.EncodeToString(imageData), "DM_IMAGE_WIDTH": "7", "DM_IMAGE_HEIGHT": "5", "DM_ORIGIN": "https://127.0.0.1:58443", "DM_CA": base64.StdEncoding.EncodeToString(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: root.Raw})), "DM_CONVERSATION": conv, "DM_TOKEN_C": third, "DM_TOKEN_A": a, "DM_TOKEN_B": b, "DM_ACCOUNT_A": aa, "DM_ACCOUNT_B": ba, "DM_IDENTITY_A": ia, "DM_IDENTITY_B": ib, "DM_POST": p["postId"].(string), "HOST_PORT": u.Port()}
	data, _ := json.Marshal(fixture)
	if e = os.WriteFile(file, data, 0600); e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { _ = os.Remove(file) })
	t.Log("DM P2 device fixture ready; private file written")
	timeout := time.NewTimer(25 * time.Minute)
	defer timeout.Stop()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-timeout.C:
			t.Fatal("device fixture deadline")
		case <-ticker.C:
			// Refresh signed evidence without changing session generation while
			// an explicitly requested physical recovery acceptance is active.
			if os.Getenv("DM_DEVICE_RECOVERY") == "1" {
				s.advanceC(0)
				s.advanceV(0)
			}
			if _, e = os.Stat(file + ".done"); e == nil {
				return
			}
		}
	}
}
