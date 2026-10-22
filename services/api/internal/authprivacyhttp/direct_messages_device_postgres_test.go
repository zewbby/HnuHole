package authprivacyhttp

import (
	"context"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

// Opt-in real TLS/SQL fixture, synthetic accounts only. The Android driver
// receives capabilities through a private local file, never source or logs.
func TestDMDevicePostgres(t *testing.T) {
	file := os.Getenv("DM_DEVICE_FIXTURE")
	if file == "" {
		t.Skip("exclusive Android fixture not requested")
	}
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		v, e := c.WithDirectMessages(context.Background())
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
	var mu sync.Mutex
	drop := true
	s.cPublic = e2eServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := httptest.NewRecorder()
		original.ServeHTTP(rec, r)
		mu.Lock()
		lose := drop && r.Method == "PUT" && strings.HasPrefix(r.URL.Path, "/api/v1/dm/commands/") && rec.Code == 200
		if lose {
			drop = false
		}
		mu.Unlock()
		if lose {
			conn, _, e := w.(http.Hijacker).Hijack()
			if e != nil {
				t.Error(e)
				return
			}
			conn.Close()
			return
		}
		for k, v := range rec.Header() {
			w.Header()[k] = v
		}
		w.WriteHeader(rec.Code)
		_, _ = w.Write(rec.Body.Bytes())
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
	a, aa := e2ePrivacySignup(t, s, "dm_device_sender")
	b, ba := e2ePrivacySignup(t, s, "dm_device_receiver")
	ia := postHTTPSIdentity(t, s, a, "私信甲", 91)
	ib := postHTTPSIdentity(t, s, b, "私信乙", 92)
	channel := postHTTPSChannel(t, s, b)
	p := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 93), b, "", map[string]any{"channelId": channel, "identityId": ib, "title": "可靠文字验收", "body": "仅合成账号与合成内容"}, 202)
	if _, e = s.c.PublishAcceptedPosts(context.Background(), 100); e != nil {
		t.Fatal(e)
	}
	u, _ := url.Parse(s.cPublic.URL)
	fixture := map[string]string{"DM_ORIGIN": "https://127.0.0.1:58443", "DM_CA": base64.StdEncoding.EncodeToString(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: root.Raw})), "DM_TOKEN_A": a, "DM_TOKEN_B": b, "DM_ACCOUNT_A": aa, "DM_ACCOUNT_B": ba, "DM_IDENTITY_A": ia, "DM_IDENTITY_B": ib, "DM_POST": p["postId"].(string), "HOST_PORT": u.Port()}
	data, _ := json.Marshal(fixture)
	if e = os.WriteFile(file, data, 0600); e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { _ = os.Remove(file) })
	t.Log("DM device fixture ready; private file written")
	timeout := time.NewTimer(25 * time.Minute)
	defer timeout.Stop()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-timeout.C:
			t.Fatal("device fixture deadline")
		case <-ticker.C:
			if _, e = os.Stat(file + ".done"); e == nil {
				return
			}
		}
	}
}
