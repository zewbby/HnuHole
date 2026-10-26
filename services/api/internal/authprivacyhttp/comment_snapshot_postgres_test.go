package authprivacyhttp

import (
	"context"
	"encoding/pem"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/commentsnapshot"
)

func TestCommentSnapshotHTTPSPostgres(t *testing.T) {
	ctx := context.Background()
	var process *exec.Cmd
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		binary := os.Getenv("COMMENT_SNAPSHOT_REDIS_SERVER")
		if binary == "" {
			t.Fatal("owned Redis required with SQL DSNs")
		}
		listener, e := net.Listen("tcp", "127.0.0.1:0")
		if e != nil {
			t.Fatal(e)
		}
		address := listener.Addr().String()
		port := listener.Addr().(*net.TCPAddr).Port
		_ = listener.Close()
		dir := t.TempDir()
		process = exec.Command(binary, "--bind", "127.0.0.1", "--port", strconv.Itoa(port), "--save", "", "--appendonly", "no", "--maxmemory", "64mb", "--maxmemory-policy", "noeviction", "--dir", dir, "--logfile", filepath.Join(dir, "redis.log"))
		if e = process.Start(); e != nil {
			t.Fatal(e)
		}
		t.Cleanup(func() { _ = process.Process.Kill(); _ = process.Wait() })
		client := redis.NewClient(&redis.Options{Addr: address, MaxRetries: -1})
		defer client.Close()
		ready := false
		for i := 0; i < 100; i++ {
			info, e := client.Info(ctx, "server").Result()
			if e == nil {
				if !strings.Contains(info, "process_id:"+strconv.Itoa(process.Process.Pid)+"\r\n") {
					t.Fatal("Redis owner mismatch")
				}
				ready = true
				break
			}
			time.Sleep(10 * time.Millisecond)
		}
		if !ready {
			t.Fatal("owned Redis unavailable")
		}
		cfg := commentsnapshot.DefaultConfig()
		cfg.ReadPostgres = false
		cfg.ReadRedis = true
		cfg.CreateBackend = "redis"
		cfg.MaxPerAccount = 2
		cfg.Redis.Address = address
		cfg.Redis.Namespace = "hnuhole:comment-snapshot:v2:httpsql:"
		cfg.Redis.Epoch = uuid.NewString()
		key, fingerprint := e2eKey(t), e2eKey(t)
		codec, e := comments.NewCommandCodec(key[:], fingerprint[:])
		if e != nil {
			t.Fatal(e)
		}
		store, e := commentsnapshot.New(cfg, "", codec.IntentFingerprint)
		if e != nil {
			t.Fatal(e)
		}
		t.Cleanup(func() { _ = store.Close() })
		if e = store.InitializeNew(ctx); e != nil {
			t.Fatal(e)
		}
		result, e := c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: key, FingerprintKey: fingerprint, Snapshots: &cfg, SnapshotStore: store})
		if e != nil {
			t.Fatal(e)
		}
		return result
	})
	token, _ := e2ePrivacySignup(t, s, "snapshot_http")
	identity := postHTTPSIdentity(t, s, token, "分页", 0x72)
	channel := postHTTPSChannel(t, s, token)
	post := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 0x73), token, "", map[string]any{"channelId": channel, "identityId": identity, "title": "snapshot", "body": "post"}, 202)
	if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	postID := post["postId"].(string)
	for i := 0; i < 3; i++ {
		postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, byte(0x75+i)), token, "", map[string]any{"operation": "CREATE", "taskId": uuid.NewString(), "identityId": identity, "postId": postID, "rootCommentId": nil, "targetCommentId": nil, "body": "comment", "image": nil}, 202)
	}
	if _, e := s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	path := s.cPublic.URL + "/api/v1/posts/" + postID + "/comments"
	headers := map[string]string{"Authorization": "Bearer " + token, "X-Comment-Snapshot-Request": httpTestEncoding(16, 0x79)}
	first := e2eJSON(t, s.client, "GET", path+"?limit=1&sort=recent", nil, headers, 200)
	again := e2eJSON(t, s.client, "GET", path+"?limit=1&sort=recent", nil, headers, 200)
	if first["snapshotId"] != again["snapshotId"] || first["nextCursor"] != again["nextCursor"] {
		t.Fatal("HTTP initial-read nonce not preserved")
	}
	cursor := first["nextCursor"].(string)
	continuation := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID+"/comments?cursor="+cursor, token, "", nil, 200)
	if len(continuation["comments"].([]any)) != 2 {
		t.Fatal("HTTP continuation changed membership")
	}
	bad := e2eJSON(t, s.client, "GET", path+"?cursor="+cursor, nil, headers, 400)
	if bad["error"].(map[string]any)["code"] != "MALFORMED_REQUEST" {
		t.Fatal("nonce with continuation accepted")
	}
	probe := os.Getenv("COMMENT_SNAPSHOT_LIVE_PROBE")
	var liveFixture map[string]any
	if probe != "" {
		certificate := mobileLabCertificate(t)
		config, e := PublicTLSConfig(certificate)
		if e != nil {
			t.Fatal(e)
		}
		original := s.cPublic.Config.Handler
		var mu sync.Mutex
		lost := false
		nonces := []string{}
		wrapped := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			rec := httptest.NewRecorder()
			original.ServeHTTP(rec, r)
			mu.Lock()
			nonce := r.Header.Get("X-Comment-Snapshot-Request")
			if nonce != "" {
				nonces = append(nonces, nonce)
			}
			drop := !lost && nonce != "" && rec.Code == 200
			if drop {
				lost = true
			}
			mu.Unlock()
			if drop {
				connection, _, e := w.(http.Hijacker).Hijack()
				if e != nil {
					t.Error(e)
					return
				}
				_ = connection.Close()
				return
			}
			for key, values := range rec.Header() {
				w.Header()[key] = values
			}
			w.WriteHeader(rec.Code)
			_, _ = w.Write(rec.Body.Bytes())
		})
		mobile := e2eServer(t, wrapped, config)
		liveFixture = map[string]any{"url": mobile.URL, "certificatePem": string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certificate.Certificate[1]})), "token": token, "postId": postID, "cursor": cursor}
		runLiveGovernanceProbe(t, probe, liveFixture, "live")
		mu.Lock()
		valid := lost && len(nonces) == 3 && nonces[0] == nonces[1] && nonces[2] != nonces[0]
		mu.Unlock()
		if !valid {
			t.Fatal("actual Dart HTTP nonce/retry or quota proof")
		}
	}
	// Stop only this test's verified child; transport failure stays distinct from
	// expired cursor and does not silently create a PostgreSQL replacement.
	if e := process.Process.Kill(); e != nil {
		t.Fatal(e)
	}
	failed := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID+"/comments?cursor="+cursor, token, "", nil, 503)
	if failed["error"].(map[string]any)["code"] != "COMMENT_SNAPSHOT_UNAVAILABLE" {
		t.Fatal("storage failure misclassified")
	}
	if probe != "" {
		runLiveGovernanceProbe(t, probe, liveFixture, "down")
	}
}
