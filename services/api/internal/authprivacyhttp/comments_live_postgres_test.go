package authprivacyhttp

import (
	"context"
	"crypto/x509"
	"encoding/pem"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestCommentBusinessDartLivePostgres(t *testing.T) {
	probe := os.Getenv("COMMENT_LIVE_PROBE")
	if probe == "" {
		t.Skip("owned compiled Dart transport probe not configured")
	}
	ctx := context.Background()
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		var e error
		c, e = c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: e2eKey(t), FingerprintKey: e2eKey(t)})
		if e != nil {
			t.Fatal(e)
		}
		// Same whole-container validator used by the other real HTTPS media test.
		return c
	})
	// Text probes exercise the production Dart command/task parser. Media bytes
	// are separately exercised by TestCommentBusinessHTTPSPostgres.
	certificate := mobileLabCertificate(t)
	config, e := PublicTLSConfig(certificate)
	if e != nil {
		t.Fatal(e)
	}
	var mu sync.Mutex
	createCount := 0
	drop := true
	original := s.cPublic.Config.Handler
	wrapped := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := httptest.NewRecorder()
		original.ServeHTTP(rec, r)
		mu.Lock()
		isCreate := r.Method == "PUT" && strings.HasPrefix(r.URL.Path, "/api/v1/comment-commands/")
		if isCreate {
			createCount++
		}
		lose := drop && isCreate && rec.Code == 202
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
		w.Write(rec.Body.Bytes())
	})
	s.cPublic = e2eServer(t, wrapped, config)
	transport := s.client.Transport.(*http.Transport).Clone()
	transport.TLSClientConfig = transport.TLSClientConfig.Clone()
	transport.TLSClientConfig.RootCAs = transport.TLSClientConfig.RootCAs.Clone()
	root, e := x509.ParseCertificate(certificate.Certificate[1])
	if e != nil {
		t.Fatal(e)
	}
	transport.TLSClientConfig.RootCAs.AddCert(root)
	s.client.Transport = transport
	t.Cleanup(transport.CloseIdleConnections)
	token, account := e2ePrivacySignup(t, s, "comment_dart_live")
	identity := postHTTPSIdentity(t, s, token, "Dart评论身份", 0x91)
	channel := postHTTPSChannel(t, s, token)
	post := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 0x92), token, "", map[string]any{"channelId": channel, "identityId": identity, "title": "Dart联调", "body": "真实TLS与SQL"}, 202)
	if _, e = s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	fixture := map[string]any{"url": s.cPublic.URL, "certificatePem": string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certificate.Certificate[1]})), "token": token, "identityId": identity, "postId": post["postId"], "taskId": uuid.NewString(), "key": httpTestEncoding(16, 0xff), "body": "Dart原文\r\ne\u0301"}
	created := runLiveGovernanceProbe(t, probe, fixture, "create")
	if created["unknownObserved"] != true {
		t.Fatal("committed response loss not injected")
	}
	mu.Lock()
	n := createCount
	mu.Unlock()
	if n != 1 {
		t.Fatal("unknown command automatically replayed")
	}
	if _, e = s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	published := runLiveGovernanceProbe(t, probe, fixture, "read")
	cid := published["commentId"].(string)
	fixture["commentId"] = cid
	fixture["key"] = httpTestEncoding(16, 0xfe)
	runLiveGovernanceProbe(t, probe, fixture, "like")
	fixture["root"] = cid
	fixture["target"] = cid
	fixture["taskId"] = uuid.NewString()
	fixture["key"] = httpTestEncoding(16, 0x95)
	fixture["body"] = "Dart回复具体内容"
	runLiveGovernanceProbe(t, probe, fixture, "create")
	if _, e = s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	reply := runLiveGovernanceProbe(t, probe, fixture, "read")
	if reply["commentId"] == cid {
		t.Fatal("wrong reply")
	}
	fixture["taskId"] = uuid.NewString()
	fixture["key"] = httpTestEncoding(16, 0x96)
	runLiveGovernanceProbe(t, probe, fixture, "create")
	end := time.Now().Add(time.Second)
	if e = s.c.ApplyAccountMute(ctx, uuid.MustParse(account), 1, &end); e != nil {
		t.Fatal(e)
	}
	failed := runLiveGovernanceProbe(t, probe, fixture, "failed")
	fixture["version"] = failed["version"]
	fixture["key"] = httpTestEncoding(16, 0x97)
	runLiveGovernanceProbe(t, probe, fixture, "abandon")
	fixture["commentId"] = cid
	fixture["key"] = httpTestEncoding(16, 0xfb)
	runLiveGovernanceProbe(t, probe, fixture, "delete")
}
