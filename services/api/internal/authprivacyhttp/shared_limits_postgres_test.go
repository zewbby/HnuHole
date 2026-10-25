package authprivacyhttp

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

func sharedHTTPRedis(t *testing.T) string {
	t.Helper()
	binary := os.Getenv("HNULIMIT_REDIS_SERVER")
	if binary == "" {
		t.Skip("owned Redis binary required for shared TLS acceptance")
	}
	socket, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := socket.Addr().(*net.TCPAddr).Port
	socket.Close()
	dir := t.TempDir()
	command := exec.Command(binary, "--bind", "127.0.0.1", "--port", strconv.Itoa(port), "--save", "", "--appendonly", "no", "--maxmemory", "128mb", "--maxmemory-policy", "noeviction", "--dir", dir, "--logfile", filepath.Join(dir, "redis.log"))
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	if err = command.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = command.Process.Kill(); _ = command.Wait() })
	address := fmt.Sprintf("127.0.0.1:%d", port)
	client := redis.NewClient(&redis.Options{Addr: address, MaxRetries: -1})
	defer client.Close()
	for i := 0; i < 100; i++ {
		if client.Ping(context.Background()).Err() == nil {
			return address
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("owned Redis not ready")
	return ""
}

func TestSharedRateRealTLSRuntimeNewSameKeyAndFaultIsolationPostgres(t *testing.T) {
	t.Setenv("HNULIMIT_FORMAL_GOOSE", "1")
	s := e2eNewServices(t)
	ctx := context.Background()
	token, _ := e2ePrivacySignup(t, s, "shared_tls_owner")
	campusPeer, _ := e2ePrivacySignup(t, s, "shared_tls_peer")
	secondIdentity := postHTTPSIdentity(t, s, token, "第二身份", 89)
	channel := postHTTPSChannel(t, s, token)
	identity := postHTTPSIdentity(t, s, token, "身份", 91)
	for _, file := range []string{"grant-community.sql"} {
		raw, err := os.ReadFile("../../../../infra/postgres/" + file)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = s.cp.Exec(ctx, string(raw)); err != nil {
			t.Fatal("cannot apply owned runtime grants")
		}
	}
	runtimeConfig, err := pgxpool.ParseConfig(os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
	if err != nil || runtimeConfig.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
		t.Fatal("owned runtime marker absent")
	}
	runtimeConfig.MaxConns = 8
	openRuntime := func(max int32) *pgxpool.Pool {
		cfg := runtimeConfig.Copy()
		cfg.MaxConns = max
		pool, e := pgxpool.NewWithConfig(ctx, cfg)
		if e != nil {
			t.Fatal(e)
		}
		t.Cleanup(pool.Close)
		return pool
	}
	metadata := openRuntime(4)
	store, err := ratelimit.NewPostgresNamespaceStore(metadata, "community")
	if err != nil {
		t.Fatal(err)
	}
	ownerStore, err := ratelimit.NewPostgresNamespaceStore(s.cp, "community")
	if err != nil {
		t.Fatal(err)
	}
	address := sharedHTTPRedis(t)
	operator := redis.NewClient(&redis.Options{Addr: address, MaxRetries: -1})
	defer operator.Close()
	info, err := operator.Info(ctx, "server").Result()
	if err != nil {
		t.Fatal(err)
	}
	runID := ""
	for _, line := range strings.Split(info, "\n") {
		if strings.HasPrefix(line, "run_id:") {
			runID = strings.TrimSpace(strings.TrimPrefix(line, "run_id:"))
		}
	}
	sharedKey := e2eKey(t)
	config := ratelimit.TrialConfig(address, "community_tls_owned")
	config.DeadlineMilliseconds = 1000
	config.ReadSeconds = 1
	for i := range config.Rules {
		config.Rules[i].Mode = ratelimit.Enforce
		if config.Rules[i].Action == "upload.bytes" {
			config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 1000, Limit: 64}}
		}
		if config.Rules[i].Action == "upload.attempt" {
			config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 5000, Limit: 10}}
		}
		if config.Rules[i].Action == "login.failure" {
			config.Rules[i].Bucket = nil
			config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 5000, Limit: 2}}
		}
		if config.Rules[i].Action == "read.account" {
			config.Rules[i].Bucket = nil
			config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 10000, Limit: 1}}
		}
		if config.Rules[i].Action == "post.create" {
			config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 60000, Limit: 5}}
			config.Rules[i].Failure = "reject"
		}
	}
	first, err := ratelimit.New(config, "", store, sharedKey)
	if err != nil {
		t.Fatal(err)
	}
	defer first.Close()
	ns, err := ownerStore.Initialize(ctx, runID, first.PolicyHash(), first.RecoveryWindow())
	if err != nil {
		t.Fatal(err)
	}
	if err = first.InitializeRedis(ctx, ns); err != nil {
		t.Fatal(err)
	}
	second, err := ratelimit.New(config, "", store, sharedKey)
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	pki := e2eNewPKI(t)
	cert := pki.cert(t, "lab", CommunityService)
	tlsConfig, err := PublicTLSConfig(cert)
	if err != nil {
		t.Fatal(err)
	}
	peer := PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}
	passwords, err := authprivacy.NewPasswordPreparer(1, []string{"PasswordPassword123!"})
	if err != nil {
		t.Fatal(err)
	}
	endpoint := func(engine *ratelimit.Controller) *httptest.Server {
		pool := openRuntime(8)
		var actor string
		if pool.QueryRow(ctx, `SELECT current_user`).Scan(&actor) != nil || actor != "hnuhole_c_runtime" {
			t.Fatal("TLS API did not use runtime actor")
		}
		community, e := authprivacy.NewCommunityWithReceiptSigner(pool, s.verifierRaw, 1, s.cRequestKey, s.cSigner, s.gate)
		if e != nil {
			t.Fatal(e)
		}
		community, e = community.WithPosts(ctx, s.postConfig)
		if e != nil {
			t.Fatal("post runtime schema/grants rejected", e)
		}
		community, e = community.WithSharedRateLimit(ctx, engine, sharedKey)
		if e != nil {
			t.Fatal("shared runtime schema/grants rejected", e)
		}
		endpoints, e := NewCommunityEndpoints(CommunityOptions{Backend: community, Passwords: passwords, InternalPeer: peer, Limits: NetworkLimits{Key: e2eKey(t), MutationCapacity: 10000, QueryCapacity: 10000, Window: time.Minute, MaxEntries: 1024}, Shared: &SharedLimits{Engine: engine, Key: sharedKey, Resolver: community}})
		if e != nil {
			t.Fatal(e)
		}
		return e2eServer(t, endpoints.Public, tlsConfig.Clone())
	}
	apiA, apiB := endpoint(first), endpoint(second)
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pki.roots, MinVersion: tls.VersionTLS13}, Proxy: nil}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 20 * time.Second}
	body, _ := json.Marshal(map[string]string{"channelId": channel, "identityId": identity, "title": "共享原键", "body": "真实双TLS实例"})
	type reply struct {
		status int
		body   []byte
		retry  string
		err    error
	}
	call := func(base, method, path string, payload []byte) reply {
		r, e := http.NewRequest(method, base+path, bytes.NewReader(payload))
		if e != nil {
			return reply{err: e}
		}
		r.Header.Set("Authorization", "Bearer "+token)
		if len(payload) > 0 {
			r.Header.Set("Content-Type", "application/json")
		}
		response, e := client.Do(r)
		if e != nil {
			return reply{err: e}
		}
		defer response.Body.Close()
		data, e := io.ReadAll(io.LimitReader(response.Body, 16384))
		if response.Header.Get("Cache-Control") != "no-store" || response.Header.Get("X-Request-ID") == "" {
			return reply{err: fmt.Errorf("private envelope absent")}
		}
		return reply{response.StatusCode, data, response.Header.Get("Retry-After"), e}
	}
	// All clients share the loopback campus egress. Distinct verified accounts
	// retain independent read quotas; a forged source header has no authority.
	campusRead := func(bearer string) reply {
		r, _ := http.NewRequest("GET", apiA.URL+"/api/v1/channels", nil)
		r.Header.Set("Authorization", "Bearer "+bearer)
		r.Header.Set("X-Forwarded-For", "203.0.113.19")
		response, e := client.Do(r)
		if e != nil {
			return reply{err: e}
		}
		defer response.Body.Close()
		data, e := io.ReadAll(response.Body)
		return reply{status: response.StatusCode, body: data, err: e}
	}
	if r := campusRead(token); r.err != nil || r.status != 200 {
		t.Fatal("first campus account read failed", r.status, r.err)
	}
	if r := campusRead(campusPeer); r.err != nil || r.status != 200 {
		t.Fatal("shared campus IP blocked independent account", r.status, r.err)
	}
	if r := campusRead(token); r.err != nil || r.status != 429 {
		t.Fatal("account read quota absent", r.status, r.err)
	}
	// Valid and absent identifiers take the same public failure path. Limited
	// failures expire instead of permanently locking a victim account.
	loginSequence := byte(1)
	login := func(name, password, forged string) reply {
		loginSequence++
		body, _ := json.Marshal(map[string]string{"username": name, "password": password, "installationId": httpTestEncoding(16, loginSequence)})
		r, _ := http.NewRequest("POST", apiA.URL+"/api/v1/auth/sessions", bytes.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("Idempotency-Key", httpTestEncoding(32, loginSequence))
		r.Header.Set("X-Forwarded-For", forged)
		response, e := client.Do(r)
		if e != nil {
			return reply{err: e}
		}
		defer response.Body.Close()
		data, e := io.ReadAll(response.Body)
		return reply{status: response.StatusCode, body: data, retry: response.Header.Get("Retry-After"), err: e}
	}
	var existingFailure, absentFailure []byte
	for _, name := range []string{"shared_tls_owner", "shared_absent_user"} {
		for i := 0; i < 2; i++ {
			r := login(name, "incorrect-synthetic-password", "198.51.100.1")
			if r.err != nil || r.status != 401 {
				t.Fatal("valid/absent identifier failure path differed", r.status, r.err)
			}
			if name == "shared_tls_owner" {
				existingFailure = r.body
			} else {
				absentFailure = r.body
			}
		}
		r := login(name, "incorrect-synthetic-password", "192.0.2.99")
		seconds, parseErr := strconv.Atoi(r.retry)
		if r.err != nil || r.status != 429 || parseErr != nil || seconds < 1 || seconds > 5 {
			t.Fatal("forged forwarding header bypassed shared failure budget", r.status, r.retry, r.err)
		}
	}
	publicLoginError := func(raw []byte) []byte {
		var value errorBody
		if json.Unmarshal(raw, &value) != nil {
			t.Fatal("invalid login error dialect")
		}
		body, e := json.Marshal(value.Error)
		if e != nil {
			t.Fatal(e)
		}
		return body
	}
	if !bytes.Equal(publicLoginError(existingFailure), publicLoginError(absentFailure)) {
		t.Fatal("login public error leaked identifier existence")
	}
	time.Sleep(5100 * time.Millisecond)
	resumed := login("shared_tls_owner", "separate-community-privacy-audit-password", "198.51.100.1")
	if resumed.err != nil || resumed.status != 201 {
		t.Fatal("expired failure window permanently locked account", resumed.status, resumed.err)
	}
	var renewed struct {
		SessionToken string `json:"sessionToken"`
	}
	if json.Unmarshal(resumed.body, &renewed) != nil || renewed.SessionToken == "" {
		t.Fatal("successful login omitted new verified session")
	}
	token = renewed.SessionToken
	command := httpTestEncoding(16, 92)
	path := "/api/v1/post-commands/" + command
	results := make(chan reply, 20)
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			base := apiA.URL
			if i%2 == 0 {
				base = apiB.URL
			}
			results <- call(base, "PUT", path, body)
		}(i)
	}
	wg.Wait()
	close(results)
	var original []byte
	for result := range results {
		if result.err != nil || result.status != 202 {
			t.Fatal("new-key cross-TLS retry failed", result.status, result.err)
		}
		if original == nil {
			original = result.body
		}
		if !bytes.Equal(original, result.body) {
			t.Fatal("new-key concurrent receipts differ")
		}
	}
	var count int
	if s.cp.QueryRow(ctx, `SELECT count(*) FROM c_posts.publication_tasks`).Scan(&count) != nil || count != 1 {
		t.Fatal("concurrent new key produced duplicate business", count)
	}
	restarted, err := ratelimit.New(config, "", store, sharedKey)
	if err != nil {
		t.Fatal(err)
	}
	defer restarted.Close()
	restartedAPI := endpoint(restarted)
	for i := 0; i < 4; i++ {
		currentBody := body
		if i%2 == 0 {
			currentBody = bytes.Replace(body, []byte(identity), []byte(secondIdentity), 1)
		}
		r := call(restartedAPI.URL, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, byte(93+i)), currentBody)
		if r.err != nil || r.status != 202 {
			t.Fatal("same-key retries spent extra quota", i, r.status, r.err)
		}
	}
	r := call(apiB.URL, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 100), body)
	if r.err != nil || r.status != 429 || r.retry == "" {
		t.Fatal("shared limit absent", r.status, r.err)
	}
	changed := bytes.Replace(body, []byte("真实双TLS实例"), []byte("不同正文"), 1)
	r = call(apiB.URL, "PUT", path, changed)
	if r.err != nil || r.status != 409 {
		t.Fatal("exhausted quota masked original-key conflict", r.status, r.err)
	}
	// A real TLS peer stalls mid-body: server-side socket deadline must end
	// ReadFull, preserve actual received bytes, and keep data out of decoders.
	uploadEngine, err := ratelimit.New(config, "", store, sharedKey)
	if err != nil {
		t.Fatal(err)
	}
	defer uploadEngine.Close()
	uploadSubject := ratelimit.Digest(sharedKey, "test", "physical-upload", "slow-tls")
	var decoded atomic.Bool
	uploadBoundary := &boundary{service: CommunityService, shared: &SharedLimits{Engine: uploadEngine, Key: sharedKey}}
	uploadServer := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if data, ok := uploadBoundary.readSharedBody(w, r, uploadSubject, 1024); ok {
			decoded.Store(true)
			_ = data
			w.WriteHeader(204)
		}
	}))
	uploadServer.TLS = tlsConfig.Clone()
	uploadServer.StartTLS()
	defer uploadServer.Close()
	uploadURL, _ := url.Parse(uploadServer.URL)
	connection, err := tls.Dial("tcp", uploadURL.Host, &tls.Config{RootCAs: pki.roots, MinVersion: tls.VersionTLS13, NextProtos: []string{"http/1.1"}})
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	connection.SetDeadline(time.Now().Add(4 * time.Second))
	start := time.Now()
	if _, err = fmt.Fprintf(connection, "POST /api/v1/identities/avatar HTTP/1.1\r\nHost: %s\r\nContent-Length: 64\r\nConnection: close\r\n\r\n0123456789abcdef", uploadURL.Host); err != nil {
		t.Fatal(err)
	}
	slowResponse, err := http.ReadResponse(bufio.NewReader(connection), nil)
	if err != nil {
		t.Fatal("real stalled TLS body had no bounded response", err)
	}
	io.Copy(io.Discard, slowResponse.Body)
	slowResponse.Body.Close()
	if time.Since(start) > 2*time.Second || slowResponse.StatusCode != 503 || decoded.Load() {
		t.Fatal("real stalled body crossed reader deadline/decoder", time.Since(start), slowResponse.StatusCode, decoded.Load())
	}
	remaining, err := uploadEngine.BeginTransfer(ctx, uploadSubject, "after-slow-tls", 64)
	if err != nil || !remaining.Allowed || remaining.Reserved != 48 {
		t.Fatal("actual TLS bytes accompanying read timeout were not billed", remaining, err)
	}
	if err = uploadEngine.SettleChunk(ctx, uploadSubject, "after-slow-tls", 0); err != nil {
		t.Fatal(err)
	}
	// A verified component fault keeps task recovery distinct from Gate failure.
	first.Close()
	r = call(apiA.URL, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 101), body)
	if r.err != nil || r.status != 503 || !bytes.Contains(r.body, []byte("SHARED_RATE_UNAVAILABLE")) {
		t.Fatal("verified component outage lost stable code", r.status, r.err)
	}
	r = call(apiA.URL, "GET", path, nil)
	if r.err != nil || r.status != 200 {
		t.Fatal("component outage blocked original receipt lookup", r.status, r.err)
	}
	if err = s.gate.Freeze(ctx, "owned shared-limit Gate negative"); err != nil {
		t.Fatal(err)
	}
	r = call(apiA.URL, "GET", path, nil)
	if r.err != nil || r.status != 503 || bytes.Contains(r.body, []byte("SHARED_RATE_UNAVAILABLE")) {
		t.Fatal("true Gate outage was treated as a component-only failure", r.status, r.err)
	}
}
