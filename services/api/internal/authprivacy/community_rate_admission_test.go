package authprivacy

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

func sharedRedisAddress(t *testing.T) string {
	t.Helper()
	binary := os.Getenv("HNULIMIT_REDIS_SERVER")
	if binary == "" {
		t.Skip("owned real Redis executable not supplied")
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
		t.Fatal("owned Redis start failed")
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
func sharedEngine(t *testing.T, l *lab, address string, limit int64, edits ...func(*ratelimit.Config)) (*ratelimit.Controller, ratelimit.Config, *ratelimit.PostgresNamespaceStore) {
	t.Helper()
	ctx := context.Background()
	cfg, err := pgxpool.ParseConfig(os.Getenv("AUTHLAB_C_DSN"))
	if err != nil {
		t.Fatal(err)
	}
	cfg.MaxConns = 4
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	store, err := ratelimit.NewPostgresNamespaceStore(pool, "community")
	if err != nil {
		t.Fatal(err)
	}
	client := redis.NewClient(&redis.Options{Addr: address, MaxRetries: -1})
	info, err := client.Info(ctx, "server").Result()
	client.Close()
	if err != nil {
		t.Fatal(err)
	}
	run := ""
	for _, line := range strings.Split(info, "\n") {
		if strings.HasPrefix(line, "run_id:") {
			run = strings.TrimSpace(strings.TrimPrefix(line, "run_id:"))
		}
	}
	config := ratelimit.TrialConfig(address, "community_owned_sql")
	config.DeadlineMilliseconds = 1000
	config.DedupSeconds = 120
	for i := range config.Rules {
		config.Rules[i].Mode = ratelimit.Off
		if config.Rules[i].Action == "post.create" {
			config.Rules[i].Mode = ratelimit.Enforce
			config.Rules[i].Failure = "reject"
			config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 60000, Limit: limit}}
		}
	}
	for _, edit := range edits {
		edit(&config)
	}
	engine, err := ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = engine.Close() })
	ns, err := store.Initialize(ctx, run, engine.PolicyHash(), engine.RecoveryWindow())
	if err != nil {
		t.Fatal(err)
	}
	if err = engine.InitializeRedis(ctx, ns); err != nil {
		t.Fatal(err)
	}
	return engine, config, store
}

func TestSharedRateTwoAPIsRealPostgresGateConcurrentAndRetry(t *testing.T) {
	l := newPostLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "shared_rate_owner")
	first := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "甲身份")
	second := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "乙身份")
	engine, config, store := sharedEngine(t, l, sharedRedisAddress(t), 5)
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	apiA, err := l.c.WithSharedRateLimit(ctx, engine, key)
	if err != nil {
		t.Fatal(err)
	}
	engineB, err := ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer engineB.Close()
	apiB, err := l.c.WithSharedRateLimit(ctx, engineB, key)
	if err != nil {
		t.Fatal(err)
	}
	type result struct {
		key     string
		intent  posts.Intent
		receipt posts.CommandResult
		err     error
	}
	outcomes := make(chan result, 20)
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		command := postTestKey(t)
		identity := first.IdentityID
		if i%2 == 0 {
			identity = second.IdentityID
		}
		intent := postTestIntent(t, l, identity)
		wg.Add(1)
		go func(i int, command string, in posts.Intent) {
			defer wg.Done()
			api := apiA
			if i%2 == 0 {
				api = apiB
			}
			r, e := api.ExecutePostCommand(ctx, owner.SessionToken, command, in)
			v, _ := r.Value.(posts.CommandResult)
			outcomes <- result{command, in, v, e}
		}(i, command, intent)
	}
	wg.Wait()
	close(outcomes)
	accepted := []result{}
	denied := []result{}
	for r := range outcomes {
		if r.err == nil {
			accepted = append(accepted, r)
		} else {
			var e *PostError
			if !errors.As(r.err, &e) || (e.Status != 429 && !(e.Status == 503 && e.Code == "SHARED_RATE_UNAVAILABLE")) {
				t.Fatal("unexpected shared admission failure", r.err)
			}
			denied = append(denied, r)
		}
	}
	if len(accepted) != 5 || len(denied) != 15 {
		t.Fatalf("two APIs admitted %d, denied %d", len(accepted), len(denied))
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_posts.publication_tasks WHERE owner_account_id=$1`, owner.AccountID); n != 5 {
		t.Fatal("SQL business count differs", n)
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_rate_limit.admissions WHERE account_id=$1`, owner.AccountID); n != 0 {
		t.Fatal("429 or final receipt left live coordination markers", n)
	}
	original := accepted[0]
	wg = sync.WaitGroup{}
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			api := apiA
			if i%2 == 0 {
				api = apiB
			}
			r, e := api.ExecutePostCommand(ctx, owner.SessionToken, original.key, original.intent)
			if e != nil || r.Value.(posts.CommandResult) != original.receipt {
				t.Error("same-key concurrent replay changed original", e)
			}
		}(i)
	}
	wg.Wait()
	changed := original.intent
	changed.Body += "changed"
	_, err = apiB.ExecutePostCommand(ctx, owner.SessionToken, original.key, changed)
	postTestError(t, err, "COMMAND_CONFLICT", 409)
	engineB.Close()
	engineB, err = ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer engineB.Close()
	apiB, err = l.c.WithSharedRateLimit(ctx, engineB, key)
	if err != nil {
		t.Fatal(err)
	}
	// Temporary coordinator capacity is a component503, not a user/Gate failure.
	// Once the concurrent round drains, every such same key is retryable and
	// reaches the real shared quota429, without leaving or sealing a marker.
	for _, item := range denied {
		_, err = apiB.ExecutePostCommand(ctx, owner.SessionToken, item.key, item.intent)
		postTestError(t, err, "RATE_LIMITED", 429)
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_rate_limit.admissions WHERE account_id=$1`, owner.AccountID); n != 0 {
		t.Fatal("retried capacity/quota denials leaked markers", n)
	}
	// A denied key has no permanent seal and remains eligible after the window.
	digest, _ := apiB.posts.commands.KeyDigest(owner.AccountID.String(), denied[0].key)
	if n := count(t, l.cp, `SELECT count(*) FROM c_posts.command_receipts WHERE key_digest=$1`, digest[:]); n != 0 {
		t.Fatal("429 became a permanent rejection")
	}
}

func TestSharedRatePreparedExpiryClosesOldKeyThroughOriginalReceipt(t *testing.T) {
	l := newPostLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "shared_expiry_owner")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "身份")
	engine, _, _ := sharedEngine(t, l, sharedRedisAddress(t), 5)
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	api, err := l.c.WithSharedRateLimit(ctx, engine, key)
	if err != nil {
		t.Fatal(err)
	}
	command := postTestKey(t)
	intent := postTestIntent(t, l, identity.IdentityID)
	digest, _ := posts.RequestDigest(intent)
	k, _ := api.posts.commands.KeyDigest(owner.AccountID.String(), command)
	fp := api.posts.commands.IntentFingerprint(digest)
	mustExec(t, l.cp, `INSERT INTO c_rate_limit.admissions(account_id,business_kind,key_digest,fingerprint,nonce,actions,operation,attempt,state,created_at,deadline,generation) VALUES($1,'post',$2,$3,$4,'[{"action":"post.create","cost":1}]','CREATE',0,'PREPARED',clock_timestamp()-interval '3 minutes',clock_timestamp()-interval '1 minute',1)`, owner.AccountID, k[:], fp[:], make([]byte, 16))
	r, err := api.GetPostCommand(ctx, owner.SessionToken, command)
	if err != nil {
		t.Fatal(err)
	}
	if r.Value.(posts.CommandResult).State != "NOT_ACCEPTED" {
		t.Fatal("expired prepared admission stayed unknown")
	}
	_, err = api.ExecutePostCommand(ctx, owner.SessionToken, command, intent)
	postTestError(t, err, "COMMAND_SEALED", 409)
	if n := count(t, l.cp, `SELECT count(*) FROM c_posts.publication_tasks WHERE owner_account_id=$1`, owner.AccountID); n != 0 {
		t.Fatal("late closed command executed")
	}
}

func TestSharedRateRecoveryBarrierStartsAfterLastInFlightNamespaceLock(t *testing.T) {
	l := newPostLab(t)
	_, _, store := sharedEngine(t, l, sharedRedisAddress(t), 5)
	ctx := context.Background()
	ns, err := store.Load(ctx)
	if err != nil {
		t.Fatal(err)
	}
	tx, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	var generation int64
	if err = tx.QueryRow(ctx, `SELECT generation FROM c_rate_limit.namespace WHERE singleton_id=1 FOR SHARE`).Scan(&generation); err != nil {
		t.Fatal(err)
	}
	type outcome struct {
		n ratelimit.Namespace
		e error
	}
	done := make(chan outcome, 1)
	go func() {
		n, e := store.Recover(ctx, ns.Generation, ns.RunID, 500*time.Millisecond)
		done <- outcome{n, e}
	}()
	time.Sleep(800 * time.Millisecond)
	select {
	case result := <-done:
		t.Fatal("recovery crossed an in-flight business transaction", result.e)
	default:
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	result := <-done
	if result.e != nil {
		t.Fatal(result.e)
	}
	remaining := time.Until(result.n.BarrierUntil)
	if remaining < 350*time.Millisecond || remaining > 600*time.Millisecond {
		t.Fatal("recovery barrier was consumed while waiting for the business lock", remaining)
	}
}

func TestSharedRateNewSameKeyConcurrentUsesOneQuotaWithRuntimeRole(t *testing.T) {
	t.Setenv("HNULIMIT_FORMAL_GOOSE", "1")
	l := newPostLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "shared_same_key_owner")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "身份")
	_, config, _ := sharedEngine(t, l, sharedRedisAddress(t), 5)
	sql, err := os.ReadFile("../../../../infra/postgres/grant-community.sql")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, string(sql))
	runtimeConfig, err := pgxpool.ParseConfig(os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
	if err != nil || runtimeConfig.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
		t.Fatal("owned runtime DSN required")
	}
	runtimeConfig.MaxConns = 8
	pool, err := pgxpool.NewWithConfig(ctx, runtimeConfig)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	metadataConfig := runtimeConfig.Copy()
	metadataConfig.MaxConns = 4
	metadata, err := pgxpool.NewWithConfig(ctx, metadataConfig)
	if err != nil {
		t.Fatal(err)
	}
	defer metadata.Close()
	var actor string
	if err = pool.QueryRow(ctx, `SELECT current_user`).Scan(&actor); err != nil || actor != "hnuhole_c_runtime" {
		t.Fatal("test did not use the actual restricted runtime role")
	}
	store, err := ratelimit.NewPostgresNamespaceStore(metadata, "community")
	if err != nil {
		t.Fatal(err)
	}
	first, err := ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer first.Close()
	second, err := ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	clone := *l.c
	clone.pool = pool
	if err = clone.CheckPostSchema(ctx); err != nil {
		t.Fatal("restricted post grants insufficient", err)
	}
	a, err := clone.WithSharedRateLimit(ctx, first, key)
	if err != nil {
		t.Fatal("restricted admission grants insufficient", err)
	}
	b, err := clone.WithSharedRateLimit(ctx, second, key)
	if err != nil {
		t.Fatal(err)
	}
	command := postTestKey(t)
	intent := postTestIntent(t, l, identity.IdentityID)
	var wg sync.WaitGroup
	results := make(chan posts.CommandResult, 20)
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			api := a
			if i%2 == 0 {
				api = b
			}
			r, e := api.ExecutePostCommand(ctx, owner.SessionToken, command, intent)
			if e != nil {
				t.Error("first-use same key failed", e)
				return
			}
			results <- r.Value.(posts.CommandResult)
		}(i)
	}
	wg.Wait()
	close(results)
	var original posts.CommandResult
	n := 0
	for r := range results {
		if n == 0 {
			original = r
		}
		if r != original {
			t.Fatal("new concurrent command returned different receipts")
		}
		n++
	}
	if n != 20 {
		t.Fatal("not all first-use retries obtained original result", n)
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_posts.publication_tasks WHERE owner_account_id=$1`, owner.AccountID); n != 1 {
		t.Fatal("same key caused multiple business effects", n)
	}
	for i := 0; i < 4; i++ {
		if _, err = a.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), intent); err != nil {
			t.Fatal("same key consumed more than one quota", i, err)
		}
	}
	_, err = b.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), intent)
	postTestError(t, err, "RATE_LIMITED", 429)
	if n := count(t, l.cp, `SELECT count(*) FROM c_rate_limit.admissions`); n != 0 {
		t.Fatal("runtime left final/denied admission markers", n)
	}
}

func TestSharedRateDurableAdmissionEpochAndFallbackDirtyRecovery(t *testing.T) {
	l := newPostLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "shared_epoch_owner")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "身份")
	address := sharedRedisAddress(t)
	engine, config, store := sharedEngine(t, l, address, 5, func(config *ratelimit.Config) {
		config.DedupSeconds = 86400
		config.ReadSeconds = 1
		for i := range config.Rules {
			if config.Rules[i].Action == "post.create" {
				config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 100, Limit: 5}}
				config.Rules[i].Failure = "verified-db"
			}
		}
	})
	var err error
	defer engine.Close()
	if engine.RecoveryWindow() > 2200*time.Millisecond || engine.PrepareWindow() != 2*time.Minute {
		t.Fatal("hot receipt TTL/off rules polluted recovery window", engine.RecoveryWindow(), engine.PrepareWindow())
	}
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	api, err := l.c.WithSharedRateLimit(ctx, engine, key)
	if err != nil {
		t.Fatal(err)
	}
	build := func(command string, in posts.Intent) rateSpec {
		digest, _ := posts.RequestDigest(in)
		k, _ := api.posts.commands.KeyDigest(owner.AccountID.String(), command)
		return rateSpec{Account: owner.AccountID, Kind: "post", Operation: "CREATE", Key: k, Fingerprint: api.posts.commands.IntentFingerprint(digest), Charges: []ratelimit.Charge{{Action: "post.create", Cost: 1}}}
	}
	intent := postTestIntent(t, l, identity.IdentityID)
	command := postTestKey(t)
	spec := build(command, intent)
	admitted, err := api.prepareRateAdmission(ctx, owner.SessionToken, func(_ pgx.Tx, _ uuid.UUID) (rateSpec, error) { return spec, nil })
	if err != nil {
		t.Fatal(err)
	}
	// SQL ADMITTED survives ordinary loss of the hot dedup entry. No Probe occurs.
	operator := redis.NewClient(&redis.Options{Addr: address, MaxRetries: -1})
	defer operator.Close()
	subject := api.rateSubject(owner.AccountID)
	stateKey := "hnuhole:" + config.Namespace + ":g1:s:" + subject
	if err = operator.Del(ctx, stateKey).Err(); err != nil {
		t.Fatal(err)
	}
	again, err := api.prepareRateAdmission(ctx, owner.SessionToken, func(_ pgx.Tx, _ uuid.UUID) (rateSpec, error) { return spec, nil })
	if err != nil {
		t.Fatal("durable same-epoch ADMITTED probed hot cache", err)
	}
	result, err := api.executePostCommandOnce(again, owner.SessionToken, command, intent)
	if err != nil || result.Value.(posts.CommandResult).State != "ACCEPTED" {
		t.Fatal("durable SQL admission failed final transaction", err)
	}
	_ = admitted
	// An old-generation PREPARED key is sealed without disturbing the fresh epoch.
	oldCommand := postTestKey(t)
	oldSpec := build(oldCommand, intent)
	mustExec(t, l.cp, `INSERT INTO c_rate_limit.admissions(account_id,business_kind,key_digest,fingerprint,nonce,actions,operation,attempt,state,created_at,deadline,generation) VALUES($1,'post',$2,$3,$4,'[{"action":"post.create","cost":1}]','CREATE',0,'PREPARED',clock_timestamp(),clock_timestamp()+interval '1 minute',1)`, owner.AccountID, oldSpec.Key[:], oldSpec.Fingerprint[:], make([]byte, 16))
	ns, err := store.Load(ctx)
	if err != nil {
		t.Fatal(err)
	}
	ns, err = store.Recover(ctx, ns.Generation, ns.RunID, 30*time.Millisecond)
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(40 * time.Millisecond)
	// A new valid operation performs activation automatically.
	if _, err = engine.Admit(ctx, ratelimit.Digest(key, "test", "fresh", "epoch"), []ratelimit.Charge{{Action: "post.create", Cost: 1}}, ratelimit.Proof{}); err != nil {
		t.Fatal(err)
	}
	_, err = api.ExecutePostCommand(ctx, owner.SessionToken, oldCommand, intent)
	postTestError(t, err, "COMMAND_SEALED", 409)
	ready, err := store.Load(ctx)
	if err != nil || ready.State != "READY" || ready.Generation != ns.Generation {
		t.Fatal("old prepared key restarted global recovery", ready, err)
	}
	// A real disconnected Redis client permits only verified SQL fallback; dirty
	// registration commits atomically with that business effect.
	engine.Close()
	fallbackCommand := postTestKey(t)
	_, err = api.ExecutePostCommand(ctx, owner.SessionToken, fallbackCommand, intent)
	if err != nil {
		t.Fatal("verified DB fallback failed", err)
	}
	dirty, err := store.Load(ctx)
	if err != nil || dirty.DirtyUntil == nil || dirty.State != "READY" {
		t.Fatal("fallback committed without persistent dirty fence", dirty, err)
	}
	healthy, err := ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer healthy.Close()
	_, err = healthy.Admit(ctx, ratelimit.Digest(key, "test", "fresh", "after-fallback"), []ratelimit.Charge{{Action: "post.create", Cost: 1}}, ratelimit.Proof{})
	if !errors.Is(err, ratelimit.ErrUnavailable) {
		t.Fatal("same Redis run accepted unaccounted fallback quota", err)
	}
	recovering, err := store.Load(ctx)
	if err != nil || recovering.State != "RECOVERING" || recovering.Generation != dirty.Generation+1 || recovering.RunID != dirty.RunID {
		t.Fatal("same-run dirty recovery not persisted", recovering, err)
	}
	if healthy.CanDBFallback(ctx) {
		t.Fatal("dirty recovery barrier allowed further DB fallback")
	}
	time.Sleep(time.Until(recovering.BarrierUntil) + 20*time.Millisecond)
	if _, err = healthy.Admit(ctx, ratelimit.Digest(key, "test", "fresh", "after-fallback"), []ratelimit.Charge{{Action: "post.create", Cost: 1}}, ratelimit.Proof{}); err != nil {
		t.Fatal("shared admission did not automatically restore", err)
	}
	restored, _ := store.Load(ctx)
	if restored.State != "READY" || restored.DirtyUntil != nil {
		t.Fatal("activated epoch retained dirty fence")
	}
}

func TestSharedRateVerifierFallbackKeepsOriginalSQLBudgetAndDirtyAtomicity(t *testing.T) {
	t.Setenv("HNULIMIT_FORMAL_GOOSE", "1")
	l, eligibility, _ := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	eligibility.config.SendBudget = 1
	address := sharedRedisAddress(t)
	client := redis.NewClient(&redis.Options{Addr: address, MaxRetries: -1})
	defer client.Close()
	info, err := client.Info(ctx, "server").Result()
	if err != nil {
		t.Fatal(err)
	}
	run := ""
	for _, line := range strings.Split(info, "\n") {
		if strings.HasPrefix(line, "run_id:") {
			run = strings.TrimSpace(strings.TrimPrefix(line, "run_id:"))
		}
	}
	grant, err := os.ReadFile("../../../../infra/postgres/grant-verifier.sql")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.vp, string(grant))
	audit, err := os.ReadFile("../../authlab/privacy-role-audit.sql")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.vp, strings.Replace(string(audit), ":'party'", "'v'", 1))
	runtimeConfig, err := pgxpool.ParseConfig(os.Getenv("AUTHLAB_V_RUNTIME_DSN"))
	if err != nil || runtimeConfig.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
		t.Fatal("owned V runtime DSN required")
	}
	runtimeConfig.MaxConns = 8
	runtimePool, err := pgxpool.NewWithConfig(ctx, runtimeConfig)
	if err != nil {
		t.Fatal(err)
	}
	defer runtimePool.Close()
	metadataConfig := runtimeConfig.Copy()
	metadataConfig.MaxConns = 4
	metadata, err := pgxpool.NewWithConfig(ctx, metadataConfig)
	if err != nil {
		t.Fatal(err)
	}
	defer metadata.Close()
	var actor string
	if runtimePool.QueryRow(ctx, `SELECT current_user`).Scan(&actor) != nil || actor != "hnuhole_v_runtime" {
		t.Fatal("V fallback test did not use runtime role")
	}
	verifier := *eligibility.store
	verifier.pool = runtimePool
	eligibility.store = &verifier
	store, err := ratelimit.NewPostgresNamespaceStore(metadata, "verifier")
	if err != nil {
		t.Fatal(err)
	}
	ownerStore, err := ratelimit.NewPostgresNamespaceStore(l.vp, "verifier")
	if err != nil {
		t.Fatal(err)
	}
	config := ratelimit.TrialConfig(address, "verifier_owned_fallback")
	config.ReadSeconds = 1
	config.DeadlineMilliseconds = 1000
	for i := range config.Rules {
		config.Rules[i].Mode = ratelimit.Off
		if config.Rules[i].Action == "otp.request" {
			config.Rules[i].Mode = ratelimit.Enforce
			config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 100, Limit: 5}}
		}
	}
	engine, err := ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Close()
	ns, err := ownerStore.Initialize(ctx, run, engine.PolicyHash(), engine.RecoveryWindow())
	if err != nil {
		t.Fatal(err)
	}
	if err = engine.InitializeRedis(ctx, ns); err != nil {
		t.Fatal(err)
	}
	engine.Close()
	fallback, err := engine.WithVerifiedDBFallback(ctx)
	if err != nil {
		t.Fatal(err)
	}
	req := otpFixtureRequest(t, "shared-verifier-only@hainanu.edu.cn")
	if _, err = eligibility.RequestOTP(fallback, req); err != nil {
		t.Fatal("verified final SQL fallback failed", err)
	}
	dirty, err := store.Load(ctx)
	if err != nil || dirty.DirtyUntil == nil {
		t.Fatal("V mail business committed without same-transaction dirty marker", err)
	}
	if n := count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events WHERE email_exact=$1 AND kind='SEND'`, []byte(req.Email)); n != 1 {
		t.Fatal("original V budget missing", n)
	}
	// Replay is the old durable request, without an extra mail or budget event.
	if _, err = eligibility.RequestOTP(fallback, req); err != nil {
		t.Fatal("original V receipt replay failed", err)
	}
	expireOTPSendWaitForFixture(t, eligibility, req.Email)
	_, err = eligibility.RequestOTP(fallback, otpFixtureRequestWithInstall(t, req.Email, req.InstallationID))
	var public *EligibilityError
	if !errors.As(err, &public) || public.Code != "RATE_LIMITED" {
		t.Fatal("shared fallback bypassed original email SQL quota", err)
	}
	healthy, err := ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer healthy.Close()
	_, err = healthy.Admit(ctx, ratelimit.Digest([32]byte{1}, "verifier", "source", "synthetic-campus"), []ratelimit.Charge{{Action: "otp.request", Cost: 1}}, ratelimit.Proof{})
	if !errors.Is(err, ratelimit.ErrUnavailable) {
		t.Fatal("V resumed stale shared quota after fallback", err)
	}
	_, err = eligibility.RequestOTP(fallback, otpFixtureRequest(t, "shared-verifier-fenced@hainanu.edu.cn"))
	if !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("in-flight V fallback crossed new recovery generation", err)
	}
	if n := count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events WHERE email_exact=$1`, []byte("shared-verifier-fenced@hainanu.edu.cn")); n != 0 {
		t.Fatal("failed V epoch fence left a budget/business effect")
	}
}

func TestSharedRateRedisSuccessBeforeSQLConfirmationReplaysPreparedLease(t *testing.T) {
	l := newPostLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "shared_prepare_crash")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "身份")
	address := sharedRedisAddress(t)
	engine, config, _ := sharedEngine(t, l, address, 2)
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	api, err := l.c.WithSharedRateLimit(ctx, engine, key)
	if err != nil {
		t.Fatal(err)
	}
	command := postTestKey(t)
	intent := postTestIntent(t, l, identity.IdentityID)
	digest, _ := posts.RequestDigest(intent)
	k, _ := api.posts.commands.KeyDigest(owner.AccountID.String(), command)
	fp := api.posts.commands.IntentFingerprint(digest)
	nonce := make([]byte, 16)
	nonce[0] = 71
	created := time.Now()
	deadline := created.Add(engine.PrepareWindow())
	mustExec(t, l.cp, `INSERT INTO c_rate_limit.admissions(account_id,business_kind,key_digest,fingerprint,nonce,actions,operation,attempt,state,created_at,deadline,generation) VALUES($1,'post',$2,$3,$4,'[{"action":"post.create","cost":1}]','CREATE',0,'PREPARED',$5,$6,1)`, owner.AccountID, k[:], fp[:], nonce, created, deadline)
	spec := rateSpec{Account: owner.AccountID, Kind: "post", Operation: "CREATE", Key: k, Fingerprint: fp, Charges: []ratelimit.Charge{{Action: "post.create", Cost: 1}}}
	proof := api.rateProof(spec, nonce, "", deadline)
	proof.ExpectedGeneration = 1
	d, err := engine.Admit(ctx, api.rateSubject(owner.AccountID), spec.Charges, proof)
	if err != nil || !d.Allowed {
		t.Fatal(err)
	}
	// Simulate a crash after Redis success but before SQL ADMITTED confirmation.
	// Both the SQL generation/nonce and the Redis marker survive the API process.
	restarted, err := ratelimit.New(config, "", mustSharedNamespace(t, l))
	if err != nil {
		t.Fatal(err)
	}
	defer restarted.Close()
	api, err = l.c.WithSharedRateLimit(ctx, restarted, key)
	if err != nil {
		t.Fatal(err)
	}
	r, err := api.ExecutePostCommand(ctx, owner.SessionToken, command, intent)
	if err != nil || r.Value.(posts.CommandResult).State != "ACCEPTED" {
		t.Fatal("prepared crash recovery lost original command", err)
	}
	if _, err = api.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), intent); err != nil {
		t.Fatal("prepared retry double-charged shared quota", err)
	}
	_, err = api.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), intent)
	postTestError(t, err, "RATE_LIMITED", 429)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.publication_tasks WHERE owner_account_id=$1`, owner.AccountID) != 2 {
		t.Fatal("prepared replay duplicated business")
	}
	if engine.PrepareWindow() >= time.Duration(config.DedupSeconds)*time.Second {
		t.Fatal("prepared lease can outlive hot idempotency lease")
	}
}
func mustSharedNamespace(t *testing.T, l *lab) *ratelimit.PostgresNamespaceStore {
	t.Helper()
	store, err := ratelimit.NewPostgresNamespaceStore(l.cp, "community")
	if err != nil {
		t.Fatal(err)
	}
	return store
}
