package authprivacyhttp

import (
	"bufio"
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

// Record only real endpoint responses, preserving socket/controller access.
type sharedRateDeviceStatus struct {
	http.ResponseWriter
	status int
}

func (w *sharedRateDeviceStatus) Unwrap() http.ResponseWriter { return w.ResponseWriter }
func (w *sharedRateDeviceStatus) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	return http.NewResponseController(w.ResponseWriter).Hijack()
}
func (w *sharedRateDeviceStatus) WriteHeader(status int) {
	if w.status == 0 {
		w.status = status
		w.ResponseWriter.WriteHeader(status)
	}
}
func (w *sharedRateDeviceStatus) Write(body []byte) (int, error) {
	if w.status == 0 {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(body)
}

// Explicit native-device window. No credentials appear in stdout, APK defines
// or test reports. The normal no-DSN/owned-role checks remain e2ePool's authority.
func TestSharedRateDevicePostgres(t *testing.T) {
	file := os.Getenv("SHARED_RATE_DEVICE_FIXTURE")
	if file == "" {
		t.Skip("exclusive shared-rate device fixture not requested")
	}
	if !filepath.IsAbs(file) {
		t.Fatal("private absolute fixture path required")
	}
	if _, e := os.Lstat(file); !os.IsNotExist(e) {
		t.Fatal("fixture output must be a fresh private path")
	}
	ctx := context.Background()
	var validator *postmedia.ProcessValidator
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		source, e := os.ReadFile(os.Getenv("POST_MEDIA_VALIDATOR"))
		if e != nil {
			t.Fatal("owned image validator required")
		}
		h := sha256.Sum256(source)
		validator, e = postmedia.NewProcessValidator(os.Getenv("POST_MEDIA_PYTHON"), os.Getenv("POST_MEDIA_VALIDATOR"), hex.EncodeToString(h[:]))
		if e != nil {
			t.Fatal(e)
		}
		c, e = c.WithPostImages(ctx, validator)
		if e != nil {
			t.Fatal(e)
		}
		c, e = c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: e2eKey(t), FingerprintKey: e2eKey(t)})
		if e != nil {
			t.Fatal(e)
		}
		c, e = c.WithDirectMessages(ctx)
		if e != nil {
			t.Fatal(e)
		}
		return c
	})
	a, account := e2ePrivacySignup(t, s, "shared_device_owner")
	b, peerAccount := e2ePrivacySignup(t, s, "shared_device_peer")
	d, thirdAccount := e2ePrivacySignup(t, s, "shared_device_third")
	own := postHTTPSIdentity(t, s, a, "验收甲", 151)
	alt := postHTTPSIdentity(t, s, a, "验收甲二", 152)
	peer := postHTTPSIdentity(t, s, b, "验收乙", 153)
	third := postHTTPSIdentity(t, s, d, "验收丙", 154)
	channel := postHTTPSChannel(t, s, a)
	source := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 155), b, "", map[string]any{"channelId": channel, "identityId": peer, "title": "共享限流真机验收", "body": "仅本任务合成账号、原生加密存储和真实共享额度。"}, 202)
	if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	makePair := func(token, otherToken, identity, otherIdentity, post string) string {
		first := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), token, "", authprivacy.DMTextIntent{IdentityID: identity, PeerID: otherIdentity, SourcePostID: post, Text: "fixture contact", Attempt: 1}, 200)
		conv := first["conversationId"].(string)
		postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), otherToken, "", authprivacy.DMTextIntent{IdentityID: otherIdentity, PeerID: identity, ConversationID: conv, Text: "fixture reply", Attempt: 1}, 200)
		return conv
	}
	rootTask := uuid.NewString()
	peerRaw, _ := protocol.DecodeCanonicalBase64url(b, 32)
	var peerBearer [32]byte
	copy(peerBearer[:], peerRaw)
	if _, e := s.c.ExecuteCommentCommand(ctx, peerBearer, httpTestEncoding(16, 160), comments.Intent{Operation: comments.Create, TaskID: rootTask, PostID: source["postId"].(string), IdentityID: peer, Body: "合成回复目标"}); e != nil {
		t.Fatal(e)
	}
	if _, e := s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	var rootComment string
	if e := s.cp.QueryRow(ctx, `SELECT comment_id::text FROM c_comments.tasks WHERE task_id=$1`, rootTask).Scan(&rootComment); e != nil {
		t.Fatal(e)
	}
	conv := makePair(a, b, own, peer, source["postId"].(string))
	otherSource := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 156), d, "", map[string]any{"channelId": channel, "identityId": third, "title": "独立会话来源", "body": "合成对话"}, 202)
	if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	otherConv := makePair(a, d, own, third, otherSource["postId"].(string))
	for _, token := range []string{a, b, d} {
		pending := postHTTPSJSON(t, s, "GET", "/api/v1/dm/pending", token, "", nil, 200)["items"].([]any)
		ids := []string{}
		for _, v := range pending {
			ids = append(ids, v.(map[string]any)["messageId"].(string))
		}
		if len(ids) > 0 {
			postHTTPSJSON(t, s, "POST", "/api/v1/dm/ack", token, "", map[string]any{"messageIds": ids}, 200)
		}
	}
	openEngine := func(pool *pgxpool.Pool, service string, key [32]byte) (*ratelimit.Controller, *redis.Client) {
		address := sharedHTTPRedis(t)
		operator := redis.NewClient(&redis.Options{Addr: address, MaxRetries: -1})
		t.Cleanup(func() { operator.Close() })
		metadataConfig := pool.Config()
		metadataConfig.MaxConns = 4
		metadata, e := pgxpool.NewWithConfig(ctx, metadataConfig)
		if e != nil {
			t.Fatal(e)
		}
		t.Cleanup(metadata.Close)
		store, e := ratelimit.NewPostgresNamespaceStore(metadata, service)
		if e != nil {
			t.Fatal(e)
		}
		config := ratelimit.TrialConfig(address, service+"_device")
		config.ReadSeconds = 2
		config.DeadlineMilliseconds = 200
		config.DedupSeconds = 120
		for i := range config.Rules {
			rule := &config.Rules[i]
			rule.Mode = ratelimit.Observe
			if service == "verifier" && rule.Action != "entry.query" && rule.Action != "entry.mutation" && rule.Action != "otp.request" && rule.Action != "otp.verify" {
				rule.Mode = ratelimit.Off
			}
			if service == "community" && (rule.Action == "otp.request" || rule.Action == "otp.verify") {
				rule.Mode = ratelimit.Off
			}
			if service == "community" && (rule.Action == "post.create" || rule.Action == "comment.publish" || rule.Action == "dm.send") {
				rule.Mode = ratelimit.Enforce
				rule.Bucket = nil
				rule.Windows = []ratelimit.Window{{Milliseconds: 12000, Limit: 1}}
				rule.Failure = "reject"
			}
		}
		engine, e := ratelimit.New(config, "", store, key)
		if e != nil {
			t.Fatal(e)
		}
		t.Cleanup(func() { engine.Close() })
		info, e := operator.Info(ctx, "server").Result()
		if e != nil {
			t.Fatal(e)
		}
		run := ""
		for _, line := range strings.Split(info, "\n") {
			if strings.HasPrefix(line, "run_id:") {
				run = strings.TrimSpace(strings.TrimPrefix(line, "run_id:"))
			}
		}
		ns, e := store.Initialize(ctx, run, engine.PolicyHash(), engine.RecoveryWindow())
		if e != nil {
			t.Fatal(e)
		}
		if e = engine.InitializeRedis(ctx, ns); e != nil {
			t.Fatal(e)
		}
		return engine, operator
	}
	sharedKey := e2eKey(t)
	engine, redisControl := openEngine(s.cp, "community", sharedKey)
	vKey := e2eKey(t)
	vEngine, _ := openEngine(s.vp, "verifier", vKey)
	var e error
	s.c, e = s.c.WithSharedRateLimit(ctx, engine, sharedKey)
	if e != nil {
		t.Fatal(e)
	}
	cert := mobileLabCertificate(t)
	cfg, e := PublicTLSConfig(cert)
	if e != nil {
		t.Fatal(e)
	}
	// Keep existing signed internal protocol clients; only public device TLS uses
	// the mobile-compatible ECDSA trust root.
	pki := e2eNewPKI(t)
	passwords, e := authprivacy.NewPasswordPreparer(1, []string{"PasswordPassword123!"})
	if e != nil {
		t.Fatal(e)
	}
	limits := func() NetworkLimits {
		return NetworkLimits{Key: e2eKey(t), MutationCapacity: 10000, QueryCapacity: 10000, MaxEntries: 1024, Window: time.Minute}
	}
	endpoints, e := NewCommunityEndpoints(CommunityOptions{Backend: s.c, Passwords: passwords, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: limits(), Shared: &SharedLimits{Engine: engine, Key: sharedKey, Resolver: s.c}})
	if e != nil {
		t.Fatal(e)
	}
	var mu sync.Mutex
	capture := false
	blockClose := false
	var held *http.Request
	publishing := false
	lateCode := ""
	var dmPrimedAt time.Time
	postCalls, commentCalls, dmCalls := 0, 0, 0
	dm429Responses, dm503Responses := 0, 0
	s.cPublic = e2eServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		closeLost := blockClose && r.Method == "POST" && strings.HasPrefix(r.URL.Path, "/api/v1/dm/commands/") && strings.HasSuffix(r.URL.Path, "/close")
		mu.Unlock()
		if closeLost {
			connection, _, err := w.(http.Hijacker).Hijack()
			if err != nil {
				t.Error("cannot simulate close transport loss")
				return
			}
			connection.Close()
			return
		}
		mu.Lock()
		if r.Method == "PUT" {
			if strings.HasPrefix(r.URL.Path, "/api/v1/post-commands/") {
				postCalls++
			}
			if strings.HasPrefix(r.URL.Path, "/api/v1/comment-commands/") {
				commentCalls++
			}
			if strings.HasPrefix(r.URL.Path, "/api/v1/dm/commands/") {
				dmCalls++
			}
		}
		intercept := capture && r.Method == "PUT" && strings.HasPrefix(r.URL.Path, "/api/v1/dm/commands/") && r.Header.Get("Authorization") == "Bearer "+a
		if intercept {
			capture = false
		}
		mu.Unlock()
		if intercept {
			raw, err := io.ReadAll(io.LimitReader(r.Body, 100001))
			if err != nil || len(raw) > 100000 {
				w.WriteHeader(400)
				return
			}
			copy := r.Clone(context.Background())
			copy.Body = io.NopCloser(bytes.NewReader(raw))
			copy.GetBody = func() (io.ReadCloser, error) { return io.NopCloser(bytes.NewReader(raw)), nil }
			copy.ContentLength = int64(len(raw))
			mu.Lock()
			held = copy
			mu.Unlock()
			connection, _, err := w.(http.Hijacker).Hijack()
			if err != nil {
				t.Error("cannot simulate pre-admission network loss")
				return
			}
			connection.Close()
			return
		}
		if r.Method == "PUT" && (strings.HasPrefix(r.URL.Path, "/api/v1/dm/commands/") || strings.HasPrefix(r.URL.Path, "/api/v1/dm/chat/images/")) {
			recorded := &sharedRateDeviceStatus{ResponseWriter: w}
			endpoints.Public.ServeHTTP(recorded, r)
			mu.Lock()
			if recorded.status == http.StatusTooManyRequests {
				dm429Responses++
			}
			if recorded.status == http.StatusServiceUnavailable {
				dm503Responses++
			}
			mu.Unlock()
			return
		}
		endpoints.Public.ServeHTTP(w, r)
	}), cfg)
	vEndpoints, e := NewVerifierEndpoints(VerifierOptions{Eligibility: s.eligibility, Receipts: s.v, InternalPeer: PeerIdentity{Environment: "lab", Service: CommunityService, Roots: pki.roots}, Limits: limits(), Shared: &SharedLimits{Engine: vEngine, Key: vKey}})
	if e != nil {
		t.Fatal(e)
	}
	s.vPublic = e2eServer(t, vEndpoints.Public, cfg.Clone())
	root, e := x509.ParseCertificate(cert.Certificate[1])
	if e != nil {
		t.Fatal(e)
	}
	transport := s.client.Transport.(*http.Transport).Clone()
	transport.TLSClientConfig = transport.TLSClientConfig.Clone()
	transport.TLSClientConfig.RootCAs = transport.TLSClientConfig.RootCAs.Clone()
	transport.TLSClientConfig.RootCAs.AddCert(root)
	s.client.Transport = transport
	t.Cleanup(transport.CloseIdleConnections)
	aRaw, _ := protocol.DecodeCanonicalBase64url(a, 32)
	bRaw, _ := protocol.DecodeCanonicalBase64url(b, 32)
	var aBearer, bBearer [32]byte
	copy(aBearer[:], aRaw)
	copy(bBearer[:], bRaw)
	secret := httpTestEncoding(32, 157)
	stats := func() map[string]any {
		var tasks, commentsCount, sent, closed, pending int
		for _, q := range []struct {
			sql string
			to  *int
		}{{`SELECT count(*) FROM c_posts.publication_tasks WHERE owner_account_id=$1`, &tasks}, {`SELECT count(*) FROM c_comments.tasks WHERE owner_account_id=$1`, &commentsCount}, {`SELECT count(*) FROM c_dm.commands WHERE owner_account=$1 AND state='SENT'`, &sent}, {`SELECT count(*) FROM c_dm.commands WHERE owner_account=$1 AND error_code='COMMAND_CLOSED'`, &closed}, {`SELECT count(*) FROM c_dm.messages m JOIN public.community_identities i ON i.identity_id=m.recipient WHERE i.account_id=$1 AND NOT m.acknowledged`, &pending}} {
			if err := s.cp.QueryRow(ctx, q.sql, account).Scan(q.to); err != nil {
				t.Error("private stats query failed")
				return map[string]any{"error": true}
			}
		}
		postRecords := []map[string]any{}
		postRows, queryErr := s.cp.Query(ctx, `SELECT t.task_id::text,t.identity_id::text,t.channel_id::text,COALESCE(c.title,''),COALESCE(c.body,''),x.state,COALESCE((SELECT encode(m.digest,'hex') FROM c_posts.images m WHERE m.task_id=t.task_id AND m.version=x.version ORDER BY m.position LIMIT 1),''),COALESCE((SELECT octet_length(m.payload) FROM c_posts.images m WHERE m.task_id=t.task_id AND m.version=x.version ORDER BY m.position LIMIT 1),0) FROM c_posts.publication_tasks t JOIN c_posts.publication_attempts x ON x.task_id=t.task_id AND x.version=t.latest_attempt_version JOIN c_posts.attempt_contents c ON c.task_id=x.task_id AND c.version=x.version WHERE t.owner_account_id=$1 ORDER BY t.task_id LIMIT 16`, account)
		if queryErr != nil {
			t.Error("private post evidence query failed")
			return map[string]any{"error": true}
		}
		for postRows.Next() {
			var task, identity, channel, title, body, state, imageHash string
			var imageBytes int
			if queryErr = postRows.Scan(&task, &identity, &channel, &title, &body, &state, &imageHash, &imageBytes); queryErr != nil {
				break
			}
			titleHash := sha256.Sum256([]byte(title))
			bodyHash := sha256.Sum256([]byte(body))
			postRecords = append(postRecords, map[string]any{"taskId": task, "identityId": identity, "channelId": channel, "titleHash": hex.EncodeToString(titleHash[:]), "bodyHash": hex.EncodeToString(bodyHash[:]), "state": state, "imageHash": imageHash, "imageBytes": imageBytes})
		}
		postRows.Close()
		if queryErr != nil {
			t.Error("private post evidence scan failed")
			return map[string]any{"error": true}
		}
		commentRecords := []map[string]any{}
		commentRows, queryErr := s.cp.Query(ctx, `SELECT t.task_id::text,t.identity_id::text,t.post_id::text,COALESCE(t.root_comment_id::text,''),COALESCE(t.target_comment_id::text,''),COALESCE(x.body,''),x.state,COALESCE(x.image->>'sha256',''),COALESCE(octet_length(i.payload),0) FROM c_comments.tasks t JOIN c_comments.attempts x ON x.task_id=t.task_id AND x.version=(SELECT max(version) FROM c_comments.attempts WHERE task_id=t.task_id) LEFT JOIN c_comments.images i ON i.task_id=x.task_id AND i.version=x.version WHERE t.owner_account_id=$1 ORDER BY t.task_id LIMIT 16`, account)
		if queryErr != nil {
			t.Error("private comment evidence query failed")
			return map[string]any{"error": true}
		}
		for commentRows.Next() {
			var task, identity, post, root, target, body, state, imageHash string
			var imageBytes int
			if queryErr = commentRows.Scan(&task, &identity, &post, &root, &target, &body, &state, &imageHash, &imageBytes); queryErr != nil {
				break
			}
			bodyHash := sha256.Sum256([]byte(body))
			commentRecords = append(commentRecords, map[string]any{"taskId": task, "identityId": identity, "postId": post, "rootCommentId": root, "targetCommentId": target, "bodyHash": hex.EncodeToString(bodyHash[:]), "state": state, "imageHash": imageHash, "imageBytes": imageBytes})
		}
		commentRows.Close()
		if queryErr != nil {
			t.Error("private comment evidence scan failed")
			return map[string]any{"error": true}
		}
		mu.Lock()
		defer mu.Unlock()
		primeAge := int64(-1)
		if !dmPrimedAt.IsZero() {
			primeAge = time.Since(dmPrimedAt).Milliseconds()
		}
		return map[string]any{"dm429Responses": dm429Responses, "dm503Responses": dm503Responses, "dmPrimeAgeMillis": primeAge, "postTasks": tasks, "commentTasks": commentsCount, "dmSent": sent, "closed": closed, "pendingIncoming": pending, "postCalls": postCalls, "commentCalls": commentCalls, "dmCalls": dmCalls, "captured": held != nil, "lateCode": lateCode, "postRecords": postRecords, "commentRecords": commentRecords}
	}
	control := e2eServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || !hmac.Equal([]byte(r.Header.Get("Authorization")), []byte("SharedRateLab "+secret)) {
			w.WriteHeader(403)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		var err error
		switch r.URL.Path {
		case "/prime-post":
			_, err = s.c.ExecutePostCommand(r.Context(), aBearer, httpTestEncoding(16, 158), posts.Intent{Operation: posts.Create, ChannelID: channel, IdentityID: own, Title: "quota prime", Body: "synthetic prime"})
		case "/prime-comment":
			_, err = s.c.ExecuteCommentCommand(r.Context(), aBearer, httpTestEncoding(16, 159), comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: source["postId"].(string), IdentityID: own, Body: "synthetic comment prime"})
		case "/prime-dm":
			_, err = s.c.SendDMText(r.Context(), aBearer, uuid.NewString(), authprivacy.DMTextIntent{IdentityID: own, PeerID: peer, ConversationID: conv, Text: "synthetic quota prime", Attempt: 1})
			if err == nil {
				mu.Lock()
				dmPrimedAt = time.Now()
				mu.Unlock()
			}
		case "/incoming":
			_, err = s.c.SendDMText(r.Context(), bBearer, uuid.NewString(), authprivacy.DMTextIntent{IdentityID: peer, PeerID: own, ConversationID: conv, Text: "真实限流期间收件仍需ACK", Attempt: 1})
		case "/block-close":
			mu.Lock()
			blockClose = true
			mu.Unlock()
		case "/allow-close":
			mu.Lock()
			blockClose = false
			mu.Unlock()
		case "/capture-next":
			mu.Lock()
			capture = true
			mu.Unlock()
		case "/release-late":
			mu.Lock()
			original := held
			held = nil
			mu.Unlock()
			if original == nil {
				w.WriteHeader(409)
				return
			}
			body, _ := original.GetBody()
			request, _ := http.NewRequest("PUT", s.cPublic.URL+original.URL.Path, body)
			request.Header = original.Header.Clone()
			response, sendErr := s.client.Do(request)
			if sendErr != nil {
				err = sendErr
			} else {
				var receipt authprivacy.DMReceipt
				err = json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&receipt)
				response.Body.Close()
				mu.Lock()
				lateCode = receipt.ErrorCode
				mu.Unlock()
			}
		case "/redis-pause":
			err = redisControl.Do(r.Context(), "CLIENT", "PAUSE", 5000, "ALL").Err()
		case "/redis-flush":
			err = redisControl.FlushDB(r.Context()).Err()
		case "/publish":
			mu.Lock()
			publishing = true
			mu.Unlock()
		case "/stats":
			json.NewEncoder(w).Encode(stats())
			return
		default:
			w.WriteHeader(404)
			return
		}
		if err != nil {
			w.WriteHeader(503)
			json.NewEncoder(w).Encode(map[string]bool{"ok": false})
			return
		}
		json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	}), cfg.Clone())
	image, e := os.ReadFile(filepath.Join(os.Getenv("POST_MEDIA_FIXTURES"), "png.bin"))
	if e != nil {
		t.Fatal(e)
	}
	meta, e := validator.Inspect(ctx, image)
	if e != nil {
		t.Fatal(e)
	}
	decision, clockErr := s.gate.Snapshot(ctx)
	if clockErr != nil {
		t.Fatal(clockErr)
	}
	redisAt, clockErr := redisControl.Time(ctx).Result()
	if clockErr != nil {
		t.Fatal(clockErr)
	}
	clockSkew := decision.TrustedAt.Sub(redisAt).Milliseconds()
	if clockSkew < -2000 || clockSkew > 2000 {
		t.Fatal("device fixture clock differs from Redis authority")
	}
	fixture := map[string]any{"url": s.cPublic.URL, "verifier": s.vPublic.URL, "control": control.URL, "controlToken": secret, "certificatePem": string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Certificate[1]})), "token": a, "accountId": account, "peerToken": b, "peerAccountId": peerAccount, "thirdAccountId": thirdAccount, "identityId": own, "alternateIdentityId": alt, "peerId": peer, "thirdId": third, "channelId": channel, "postId": source["postId"], "conversationId": conv, "otherConversationId": otherConv, "image": postmedia.Selection{MediaID: uuid.NewString(), SHA256: meta.SHA256, ByteLength: meta.ByteLength, MIME: meta.MIME, Width: meta.Width, Height: meta.Height}, "imageBytes": base64.StdEncoding.EncodeToString(image), "run": uuid.NewString(), "rootCommentId": rootComment, "targetCommentId": rootComment, "windowSeconds": 12, "clockSkewMillisAtReady": clockSkew}
	raw, e := json.Marshal(fixture)
	if e != nil {
		t.Fatal(e)
	}
	out, e := os.OpenFile(file, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if e != nil {
		t.Fatal("private fixture creation failed")
	}
	if _, e = out.Write(raw); e != nil {
		out.Close()
		t.Fatal(e)
	}
	if e = out.Sync(); e != nil {
		t.Fatal(e)
	}
	out.Close()
	t.Cleanup(func() { os.Remove(file); os.Remove(file + ".stop") })
	t.Log("owned shared-rate device fixture ready; private file only")
	tick := time.NewTicker(250 * time.Millisecond)
	defer tick.Stop()
	renew := time.NewTicker(time.Minute)
	defer renew.Stop()
	deadline := time.NewTimer(28 * time.Minute)
	defer deadline.Stop()
	for {
		select {
		case <-tick.C:
			if _, e = os.Stat(file + ".stop"); e == nil {
				return
			}
			mu.Lock()
			work := publishing
			mu.Unlock()
			if work {
				if _, e = s.c.PublishAcceptedPosts(ctx, 100); e != nil {
					t.Fatal(e)
				}
				if _, e = s.c.PublishAcceptedComments(ctx, 100); e != nil {
					t.Fatal(e)
				}
			}
		case <-renew.C:
			s.advanceC(0)
			s.advanceV(0)
		case <-deadline.C:
			t.Fatal("exclusive device fixture deadline exceeded")
		}
	}
}
