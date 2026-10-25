package authprivacyhttp

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

func TestSharedRateFourUploadPathsRealTLSWireBytesAndRetransmission(t *testing.T) {
	// The existing e2e guard must decide no-DSN SKIP before image requirements.
	// With owned SQL configured, missing media inputs remain a hard failure.
	var validator *postmedia.ProcessValidator
	var err error
	ctx := context.Background()
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		python, script := os.Getenv("POST_MEDIA_PYTHON"), os.Getenv("POST_MEDIA_VALIDATOR")
		if python == "" || script == "" || os.Getenv("POST_MEDIA_FIXTURES") == "" {
			t.Fatal("shared upload acceptance requires the owned pinned image fixture")
		}
		raw, err := os.ReadFile(script)
		if err != nil {
			t.Fatal(err)
		}
		hash := sha256.Sum256(raw)
		validator, err = postmedia.NewProcessValidator(python, script, hex.EncodeToString(hash[:]))
		if err != nil {
			t.Fatal(err)
		}
		var e error
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
	owner, account := e2ePrivacySignup(t, s, "shared_upload_owner")
	peer, _ := e2ePrivacySignup(t, s, "shared_upload_peer")
	identity := postHTTPSIdentity(t, s, owner, "图片作者", 31)
	other := postHTTPSIdentity(t, s, peer, "另一同学", 32)
	channel := postHTTPSChannel(t, s, owner)
	source := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 33), peer, "", map[string]any{"channelId": channel, "identityId": other, "title": "图片来源", "body": "source"}, 202)
	if _, err = s.c.PublishAcceptedPosts(ctx, 100); err != nil {
		t.Fatal(err)
	}
	first := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), owner, "", authprivacy.DMTextIntent{IdentityID: identity, PeerID: other, SourcePostID: source["postId"].(string), Text: "hello", Attempt: 1}, 200)
	conversation := first["conversationId"].(string)
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), peer, "", authprivacy.DMTextIntent{IdentityID: other, PeerID: identity, ConversationID: conversation, Text: "reply", Attempt: 1}, 200)
	data, err := os.ReadFile(filepath.Join(os.Getenv("POST_MEDIA_FIXTURES"), "png.bin"))
	if err != nil {
		t.Fatal(err)
	}
	metadata, err := validator.Inspect(ctx, data)
	if err != nil {
		t.Fatal(err)
	}
	selection := postmedia.Selection{MediaID: uuid.NewString(), SHA256: metadata.SHA256, ByteLength: metadata.ByteLength, MIME: metadata.MIME, Width: metadata.Width, Height: metadata.Height}
	imageIntent := authprivacy.DMImageIntent{IdentityID: identity, PeerID: other, ConversationID: conversation, GroupID: uuid.NewString(), GroupSize: 1, Selection: selection, Data: base64.StdEncoding.EncodeToString(data), Attempt: 1}
	dmWire, err := json.Marshal(imageIntent)
	if err != nil {
		t.Fatal(err)
	}
	budget := int64(6*len(data) + 2*len(dmWire))
	address := sharedHTTPRedis(t)
	operator := redis.NewClient(&redis.Options{Addr: address, MaxRetries: -1})
	defer operator.Close()
	info, err := operator.Info(ctx, "server").Result()
	if err != nil {
		t.Fatal(err)
	}
	run := ""
	for _, line := range strings.Split(info, "\n") {
		if strings.HasPrefix(line, "run_id:") {
			run = strings.TrimSpace(strings.TrimPrefix(line, "run_id:"))
		}
	}
	store, err := ratelimit.NewPostgresNamespaceStore(s.cp, "community")
	if err != nil {
		t.Fatal(err)
	}
	config := ratelimit.TrialConfig(address, "community_four_uploads")
	config.DeadlineMilliseconds = 1000
	for i := range config.Rules {
		config.Rules[i].Mode = ratelimit.Off
		switch config.Rules[i].Action {
		case "upload.attempt":
			config.Rules[i].Mode = ratelimit.Enforce
			config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 60000, Limit: 20}}
		case "upload.bytes":
			config.Rules[i].Mode = ratelimit.Enforce
			config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 60000, Limit: budget}}
		}
	}
	key := e2eKey(t)
	engine, err := ratelimit.New(config, "", store, key)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Close()
	ns, err := store.Initialize(ctx, run, engine.PolicyHash(), engine.RecoveryWindow())
	if err != nil {
		t.Fatal(err)
	}
	if err = engine.InitializeRedis(ctx, ns); err != nil {
		t.Fatal(err)
	}
	community, err := s.c.WithSharedRateLimit(ctx, engine, key)
	if err != nil {
		t.Fatal(err)
	}
	pki := e2eNewPKI(t)
	cert := pki.cert(t, "lab", CommunityService)
	tlsConfig, err := PublicTLSConfig(cert)
	if err != nil {
		t.Fatal(err)
	}
	passwords, err := authprivacy.NewPasswordPreparer(1, []string{"PasswordPassword123!"})
	if err != nil {
		t.Fatal(err)
	}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{Backend: community, Passwords: passwords, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: NetworkLimits{Key: e2eKey(t), MutationCapacity: 10000, QueryCapacity: 10000, Window: time.Minute, MaxEntries: 1024}, Shared: &SharedLimits{Engine: engine, Key: key, Resolver: community}})
	if err != nil {
		t.Fatal(err)
	}
	server := e2eServer(t, endpoints.Public, tlsConfig)
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pki.roots, MinVersion: tls.VersionTLS13}, Proxy: nil}
	defer transport.CloseIdleConnections()
	s.cPublic = server
	s.client = &http.Client{Transport: transport, Timeout: 20 * time.Second}
	s.c = community
	subject := ratelimit.Digest(key, "community", "account", account)
	stateKey := "hnuhole:" + config.Namespace + ":g1:s:" + subject
	assertUsage := func(wantBytes, wantAttempts int64) {
		t.Helper()
		raw, e := operator.Get(ctx, stateKey).Bytes()
		if e != nil {
			t.Fatal(e)
		}
		var state struct {
			Actions map[string]map[string][]struct {
				Cost int64 `json:"cost"`
			} `json:"actions"`
			Reserves map[string]any `json:"reserves"`
		}
		if json.Unmarshal(raw, &state) != nil {
			t.Fatal("invalid private state")
		}
		sum := func(action string) int64 {
			var total int64
			for _, v := range state.Actions[action]["1"] {
				total += v.Cost
			}
			return total
		}
		if sum("upload.bytes") != wantBytes || sum("upload.attempt") != wantAttempts || len(state.Reserves) != 0 {
			t.Fatal("actual wire accounting differs", sum("upload.bytes"), sum("upload.attempt"), wantBytes, wantAttempts, len(state.Reserves))
		}
	}
	upload := func(path, authorization, mime string, payload []byte, status int) {
		t.Helper()
		r, e := http.NewRequest("PUT", server.URL+path, bytes.NewReader(payload))
		if e != nil {
			t.Fatal(e)
		}
		r.Header.Set("Authorization", authorization)
		r.Header.Set("Content-Type", mime)
		r.Header.Set("X-Forwarded-For", "198.51.100.9")
		response, e := s.client.Do(r)
		if e != nil {
			t.Fatal(e)
		}
		io.Copy(io.Discard, response.Body)
		response.Body.Close()
		if response.StatusCode != status || response.Header.Get("Cache-Control") != "no-store" {
			t.Fatal("real upload status/envelope", response.StatusCode, status)
		}
		if status == 429 {
			seconds, e := strconv.Atoi(response.Header.Get("Retry-After"))
			if e != nil || seconds < 1 || seconds > 86400 {
				t.Fatal("strict physical upload wait missing")
			}
		}
	}
	// Post's scoped upload grant resolves its original owner before reading.
	accepted := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 34), owner, "", map[string]any{"channelId": channel, "identityId": identity, "title": "图片", "body": "", "images": []postmedia.Selection{selection}}, 202)
	task := accepted["taskId"].(string)
	base := "/api/v1/me/post-tasks/" + task + "/attempts/1/images/" + selection.MediaID
	grant := postHTTPSJSON(t, s, "POST", base+"/upload-grant", owner, "", nil, 200)["uploadToken"].(string)
	upload(base+"/bytes", "Upload "+grant, metadata.MIME, data, 204)
	upload(base+"/bytes", "Upload "+grant, metadata.MIME, data, 204)
	assertUsage(int64(2*len(data)), 2)
	// Foreign comment task is rejected before physical quota/body consumption.
	commentTask := uuid.NewString()
	commentInput := map[string]any{"operation": "CREATE", "taskId": commentTask, "identityId": identity, "postId": source["postId"], "rootCommentId": nil, "targetCommentId": nil, "body": "", "image": selection}
	postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, 35), owner, "", commentInput, 202)
	commentPath := "/api/v1/me/comment-tasks/" + commentTask + "/attempts/1/image"
	upload(commentPath, "Bearer "+peer, metadata.MIME, data, 404)
	assertUsage(int64(2*len(data)), 2)
	upload(commentPath, "Bearer "+owner, metadata.MIME, data, 200)
	upload(commentPath, "Bearer "+owner, metadata.MIME, data, 200)
	assertUsage(int64(4*len(data)), 4)
	avatarPath := identityAvatarPath + uuid.NewString()
	upload(avatarPath, "Bearer "+owner, metadata.MIME, data, 200)
	upload(avatarPath, "Bearer "+owner, metadata.MIME, data, 200)
	assertUsage(int64(6*len(data)), 6)
	// DM charges the JSON/base64 wire envelope again on a same-id retransmission,
	// while the permanent business receipt remains exactly the same.
	dmPath := "/api/v1/dm/chat/images/" + uuid.NewString()
	upload(dmPath, "Bearer "+owner, "application/json", dmWire, 200)
	upload(dmPath, "Bearer "+owner, "application/json", dmWire, 200)
	assertUsage(budget, 8)
	var count int
	if err = s.cp.QueryRow(ctx, `SELECT count(*) FROM c_dm.messages WHERE kind='IMAGE'`).Scan(&count); err != nil || count != 1 {
		t.Fatal("same image id repeated business effect", count, err)
	}
	// The real close endpoint is a control operation and never takes another
	// physical upload/send debit. Already-SENT images retain their receipt.
	sentClose := postHTTPSJSON(t, s, "POST", "/api/v1/dm/commands/"+strings.TrimPrefix(dmPath, "/api/v1/dm/chat/images/")+"/close", owner, "", map[string]int{"attempt": 1000}, 200)
	if sentClose["state"] != "SENT" {
		t.Fatal("TLS close falsely revoked sent image")
	}
	absent := uuid.NewString()
	closed := postHTTPSJSON(t, s, "POST", "/api/v1/dm/commands/"+absent+"/close", owner, "", map[string]int{"attempt": 2}, 200)
	if closed["errorCode"] != "COMMAND_CLOSED" || closed["attempt"] != float64(2) {
		t.Fatal("real TLS absent close missing authoritative permanent anchor")
	}
	assertUsage(budget, 8)
	upload(identityAvatarPath+uuid.NewString(), "Bearer "+owner, metadata.MIME, []byte{1}, 429)
	assertUsage(budget, 8)
}
