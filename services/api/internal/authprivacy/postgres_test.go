package authprivacy

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"golang.org/x/crypto/argon2"
)

type lab struct {
	c                                *Community
	v                                *VerifierStore
	gate                             *PostgresAuthorizationGate
	vGate                            *PostgresAuthorizationGate
	cp, vp                           *pgxpool.Pool
	vPrivate, cPrivate, cNextPrivate ed25519.PrivateKey
}

func connectLab(t *testing.T, role, dsn string) *pgxpool.Pool {
	t.Helper()
	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal("invalid lab DSN configuration")
	}
	tag := os.Getenv("AUTHLAB_RUNTIME_TAG")
	if os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(tag, "hnuhole_authlab_") || config.ConnConfig.RuntimeParams["application_name"] != tag {
		t.Fatal("lab reset requires explicit reset flag and matching isolated runtime marker")
	}
	config.MaxConns = 12
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		t.Fatal("cannot create lab pool")
	}
	t.Cleanup(pool.Close)
	var db, user string
	var super bool
	var address *string
	err = pool.QueryRow(context.Background(), `SELECT current_database(),current_user,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),inet_server_addr()::text`).Scan(&db, &user, &super, &address)
	if err != nil {
		t.Fatal("cannot verify disposable lab database")
	}
	if db != "hnuhole_"+role || user != "hnuhole_"+role || super || address != nil {
		t.Fatal("refusing schema reset: expected private-socket hnuhole_c/v database and non-superuser role")
	}
	return pool
}

func newLab(t *testing.T) *lab {
	t.Helper()
	cDSN, vDSN := os.Getenv("AUTHLAB_C_DSN"), os.Getenv("AUTHLAB_V_DSN")
	if cDSN == "" && vDSN == "" {
		t.Skip("real PostgreSQL lab DSNs absent; integration tests not executed")
	}
	if cDSN == "" || vDSN == "" {
		t.Fatal("both isolated database DSNs are required")
	}
	if cDSN == vDSN {
		t.Fatal("C and V require separate databases")
	}
	l := &lab{cp: connectLab(t, "c", cDSN), vp: connectLab(t, "v", vDSN)}
	for _, spec := range []struct {
		pool        *pgxpool.Pool
		schema, dir string
	}{{l.cp, "c_auth", "migrations"}, {l.vp, "v_auth", "verifier-migrations"}} {
		files, err := filepath.Glob(filepath.Join("..", "..", spec.dir, "*.sql"))
		if err != nil {
			t.Fatal(err)
		}
		if len(files) == 0 {
			t.Fatal("lab migrations absent")
		}
		tx, err := spec.pool.Begin(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if _, err = tx.Exec(context.Background(), `DROP SCHEMA IF EXISTS `+spec.schema+` CASCADE`); err != nil {
			_ = tx.Rollback(context.Background())
			t.Fatal(err)
		}
		if spec.schema == "c_auth" {
			if _, err = tx.Exec(context.Background(), `DROP SCHEMA IF EXISTS c_posts CASCADE`); err != nil {
				t.Fatal(err)
			}
			if _, err = tx.Exec(context.Background(), `DROP TABLE IF EXISTS public.identity_change_receipts, public.community_identities, public.identity_account_state, public.sessions, public.channels CASCADE`); err != nil {
				t.Fatal(err)
			}
			if _, err = tx.Exec(context.Background(), `DROP FUNCTION IF EXISTS public.guard_identity_account_state(), public.guard_community_identity(), public.guard_identity_receipt(), public.check_identity_account_shape() CASCADE`); err != nil {
				t.Fatal(err)
			}
		}
		for _, file := range files {
			sql, readErr := os.ReadFile(file)
			if readErr != nil {
				_ = tx.Rollback(context.Background())
				t.Fatal(readErr)
			}
			if _, err = tx.Exec(context.Background(), strings.SplitN(string(sql), "-- +goose Down", 2)[0]); err != nil {
				_ = tx.Rollback(context.Background())
				t.Fatalf("migration %s: %v", filepath.Base(file), err)
			}
		}
		if err = tx.Commit(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	var keys []protocol.TrustedKey
	for _, spec := range []struct {
		purpose protocol.Purpose
		epoch   uint32
		dst     *ed25519.PrivateKey
	}{{protocol.PurposeRegister, 1, &l.vPrivate}, {protocol.PurposeRetired, 1, &l.cPrivate}, {protocol.PurposeRetired, 2, &l.cNextPrivate}} {
		public, private, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		*spec.dst = private
		var key protocol.PublicKey
		copy(key[:], public)
		keys = append(keys, protocol.TrustedKey{Environment: "lab", Purpose: spec.purpose, Epoch: spec.epoch, PublicKey: key})
		if spec.purpose == protocol.PurposeRegister {
			keys = append(keys, protocol.TrustedKey{Environment: "lab", Purpose: protocol.PurposeRetireAuth, Epoch: 1, PublicKey: key})
		}
		if spec.purpose == protocol.PurposeRetired {
			keys = append(keys, protocol.TrustedKey{Environment: "lab", Purpose: protocol.PurposeReleased, Epoch: spec.epoch, PublicKey: key})
		}
	}
	verifier, err := protocol.NewVerifier("lab", keys)
	if err != nil {
		t.Fatal(err)
	}
	requestKey, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	lockKey, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	l.gate = newLabGate(t, l.cp)
	l.vGate = newLabGateForSchema(t, l.vp, "v_auth")
	l.c, err = NewCommunity(l.cp, verifier, 1, requestKey, l.gate)
	if err != nil {
		t.Fatal(err)
	}
	l.v, err = NewVerifierStore(l.vp, verifier, lockKey, l.vGate)
	if err != nil {
		t.Fatal(err)
	}
	return l
}

func newLabGate(t *testing.T, pool *pgxpool.Pool) *PostgresAuthorizationGate {
	t.Helper()
	return newLabGateForSchema(t, pool, "c_auth")
}

func newLabGateForSchema(t *testing.T, pool *pgxpool.Pool, schema string) *PostgresAuthorizationGate {
	t.Helper()
	domain := "hnuhole-authlab-community"
	if schema == "v_auth" {
		domain = "hnuhole-authlab-verifier"
		// V refreshes trusted time while a business transaction is open. Keep
		// that refresh on a bounded, independent pool so business saturation
		// cannot prevent the transaction holding its locks from progressing.
		config := pool.Config().Copy()
		config.MaxConns = 2
		config.MinConns = 0
		gatePool, err := pgxpool.NewWithConfig(context.Background(), config)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(gatePool.Close)
		pool = gatePool
	}
	publicEvidence, privateEvidence, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	publicRecovery, privateRecovery, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	publicBreakGlass, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	_, privateAnchor, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	provider := NewFileAuthorizationEvidenceProvider(filepath.Join(dir, "time-evidence.json"))
	anchor, err := NewFileAuthorizationAnchorStore(filepath.Join(dir, "checkpoint.json"), privateAnchor)
	if err != nil {
		t.Fatal(err)
	}
	gate, err := NewPostgresAuthorizationGate(AuthorizationGateConfig{
		Pool: pool, Schema: schema, Domain: domain, Evidence: provider,
		EvidencePublicKey: publicEvidence, RecoveryPublicKey: publicRecovery,
		BreakGlassPublicKey: publicBreakGlass, Anchor: anchor, Clock: time.Now,
	})
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	evidence, err := SignAuthorizationEvidence(privateEvidence, AuthorizationEvidence{
		Domain: domain, Version: 1, Generation: 1,
		IssuedAt: now, TrustedAt: now, ValidUntil: now.Add(authorizationEvidenceTTL),
	})
	if err != nil {
		t.Fatal(err)
	}
	if err = provider.Store(context.Background(), evidence); err != nil {
		t.Fatal(err)
	}
	request, err := SignAuthorizationRecovery(privateRecovery, AuthorizationRecoveryRequest{
		Role: "authorization-recovery", Actor: "isolated-test", Reason: "fresh lab bootstrap",
		OperationID: "lab-bootstrap", Mode: AuthorizationRecoveryNormal, Evidence: evidence,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err = gate.Recover(context.Background(), request); err != nil {
		t.Fatal(err)
	}
	return gate
}

func (l *lab) ticket(t *testing.T) (protocol.SignedTicket, ed25519.PrivateKey) {
	t.Helper()
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	var key protocol.PublicKey
	copy(key[:], public)
	slot, err := protocol.DeriveSlot(key)
	if err != nil {
		t.Fatal(err)
	}
	var at time.Time
	if err = l.cp.QueryRow(context.Background(), `SELECT clock_timestamp()`).Scan(&at); err != nil {
		t.Fatal(err)
	}
	ticket := protocol.SignedTicket{Ticket: protocol.Ticket{Epoch: 1, Window: uint32(at.Unix() / 1800), Slot: slot, BootstrapKey: key}}
	message := ticket.MessageBytes()
	copy(ticket.Signature[:], ed25519.Sign(l.vPrivate, message[:]))
	return ticket, private
}

func (l *lab) authorization(slot protocol.SlotID) string {
	a := protocol.Authorization{Epoch: 1, Slot: slot}
	message := a.MessageBytes()
	copy(a.Signature[:], ed25519.Sign(l.vPrivate, message[:]))
	return a.Encode()
}

func (l *lab) intent(t *testing.T, ticket protocol.SignedTicket, private ed25519.PrivateKey, username string) (SignupIntent, SignupRequest) {
	t.Helper()
	var password PasswordMaterial
	if _, err := rand.Read(password.Salt[:]); err != nil {
		t.Fatal(err)
	}
	copy(password.Hash[:], argon2.IDKey([]byte("isolated test credential independent of email"), password.Salt[:], 3, 64*1024, 4, 32))
	password.ParametersVersion = 1
	var installation [16]byte
	if _, err := rand.Read(installation[:]); err != nil {
		t.Fatal(err)
	}
	decision, err := l.gate.Snapshot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	intent, err := l.c.CreateSignupIntent(context.Background(), ticket.Encode(), username, password, installation, decision.Generation)
	if err != nil {
		t.Fatal(err)
	}
	message := protocol.BootstrapMessageBytes(ticket, intent.ID, intent.Challenge)
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	return intent, SignupRequest{IntentID: intent.ID, Proof: protocol.EncodeCanonicalBase64url(ed25519.Sign(private, message[:])), RecoveryCode: intent.RecoveryCode, IdempotencyKey: key}
}

func count(t *testing.T, pool *pgxpool.Pool, query string, args ...any) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(), query, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func mustExec(t *testing.T, pool *pgxpool.Pool, sql string, args ...any) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), sql, args...); err != nil {
		t.Fatal(err)
	}
}

func rejectedSQL(t *testing.T, pool *pgxpool.Pool, sql string, args ...any) {
	t.Helper()
	tx, err := pool.Begin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	_, err = tx.Exec(context.Background(), sql, args...)
	if err == nil {
		_, err = tx.Exec(context.Background(), `SET CONSTRAINTS ALL IMMEDIATE`)
	}
	var pgerr *pgconn.PgError
	if !errors.As(err, &pgerr) || !(pgerr.Code == "23514" || pgerr.Code == "23503" || pgerr.Code == "23505") {
		t.Fatalf("expected relational constraint rejection, got %v", err)
	}
}

func waitBlocked(t *testing.T, pool *pgxpool.Pool, want int) {
	waitLock(t, pool, "advisory", want)
}

func waitLock(t *testing.T, pool *pgxpool.Pool, kind string, want int) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	for {
		var n int
		err := pool.QueryRow(ctx, `SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE l.locktype=$1 AND NOT l.granted AND a.datname=current_database()`, kind).Scan(&n)
		if err != nil {
			t.Fatalf("did not observe %d blocked slot transactions", want)
		}
		if n >= want {
			return
		}
		select {
		case <-ctx.Done():
			t.Fatal("transactions did not reach lock barrier")
		case <-time.After(time.Millisecond):
		}
	}
}

func shortIntent(t *testing.T, l *lab, ticket protocol.SignedTicket, private ed25519.PrivateKey, source SignupIntent, request SignupRequest) SignupRequest {
	t.Helper()
	id, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	challenge, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, `INSERT INTO c_auth.signup_intents(intent_id,challenge,ticket,slot_id,bootstrap_public_key,admission_window,username,password_hash,password_salt,password_params_version,recovery_digest,installation_id,created_at,expires_at,state,attempts,authorization_generation)
	SELECT $1,$2,ticket,slot_id,bootstrap_public_key,admission_window,username,password_hash,password_salt,password_params_version,recovery_digest,installation_id,clock_timestamp(),clock_timestamp()+interval '300 milliseconds','OPEN',0,authorization_generation FROM c_auth.signup_intents WHERE intent_id=$3`, id[:], challenge[:], source.ID[:])
	request.IntentID = protocol.IntentID(id)
	message := protocol.BootstrapMessageBytes(ticket, request.IntentID, protocol.Challenge(challenge))
	request.Proof = protocol.EncodeCanonicalBase64url(ed25519.Sign(private, message[:]))
	return request
}

func waitIntentExpired(t *testing.T, l *lab, id protocol.IntentID) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	for {
		var expired bool
		if err := l.cp.QueryRow(ctx, `SELECT clock_timestamp()>=expires_at FROM c_auth.signup_intents WHERE intent_id=$1`, id[:]).Scan(&expired); err != nil {
			t.Fatal(err)
		}
		if expired {
			return
		}
		select {
		case <-ctx.Done():
			t.Fatal("short fixture did not expire")
		case <-time.After(time.Millisecond):
		}
	}
}

func TestPostgresIsolatedSlice(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	t.Run("signup_commit_atomic_and_replay_has_no_secrets", func(t *testing.T) {
		ticket, private := l.ticket(t)
		intent, req := l.intent(t, ticket, private, "first_user")
		wrong := req
		wrong.RecoveryCode = "AAAAAAAAAAAAAAAAAAAAAAAAAA"
		if _, err := l.c.CommitSignup(ctx, wrong); !errors.Is(err, ErrIntentInvalid) {
			t.Fatalf("wrong recovery confirmation: %v", err)
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1`, ticket.Slot[:]) != 0 {
			t.Fatal("failed proof consumed slot")
		}
		result, err := l.c.CommitSignup(ctx, req)
		if err != nil || !result.Created || result.Replay || result.SessionToken == ([32]byte{}) {
			t.Fatalf("first signup outcome: created=%v err=%v", result.Created, err)
		}
		if result.RevokeSecret != digest("HNUHOLE/SESSION-REVOKE/V1", result.SessionToken[:]) {
			t.Fatal("revoke capability not derived from bearer")
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger l JOIN c_auth.accounts a USING(account_id) JOIN c_auth.sessions s USING(account_id) JOIN c_auth.recovery_codes r USING(account_id) WHERE l.slot_id=$1 AND l.state='ACTIVE' AND a.state='ACTIVE' AND s.revoked_at IS NULL`, ticket.Slot[:]) != 1 {
			t.Fatal("signup facts not atomic")
		}
		replay, err := l.c.CommitSignup(ctx, req)
		if err != nil || !replay.Created || !replay.Replay || replay.SessionToken != ([32]byte{}) || replay.RevokeSecret != ([32]byte{}) {
			t.Fatal("replay returned authority or wrong outcome")
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.signup_intents WHERE intent_id=$1 AND state='CONSUMED' AND ticket IS NULL AND recovery_digest IS NULL`, intent.ID[:]) != 1 {
			t.Fatal("processed intent still contains authentication material")
		}
		changed := req
		changed.RecoveryCode = "AAAAAAAAAAAAAAAAAAAAAAAAAA"
		if _, err = l.c.CommitSignup(ctx, changed); !errors.Is(err, ErrConflict) {
			t.Fatalf("same key different payload: %v", err)
		}
		if err = l.c.RetireSlot(ctx, l.authorization(ticket.Slot)); !errors.Is(err, ErrSlotUnavailable) {
			t.Fatalf("active account retired: %v", err)
		}
		rejectedSQL(t, l.cp, `UPDATE c_auth.slot_ledger SET state='CLOSED',account_id=NULL WHERE slot_id=$1`, ticket.Slot[:])
	})
	t.Run("username_conflict_consumes_proof_without_slot", func(t *testing.T) {
		ticket, private := l.ticket(t)
		intent, req := l.intent(t, ticket, private, "first_user")
		if _, err := l.c.CommitSignup(ctx, req); !errors.Is(err, ErrUsernameTaken) {
			t.Fatalf("username conflict: %v", err)
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1`, ticket.Slot[:]) != 0 {
			t.Fatal("username conflict consumed slot")
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.signup_intents WHERE intent_id=$1 AND state='ABANDONED' AND challenge IS NULL`, intent.ID[:]) != 1 {
			t.Fatal("verified conflicting challenge still live")
		}
		nextKey, err := random32()
		if err != nil {
			t.Fatal(err)
		}
		req.IdempotencyKey = nextKey
		if _, err = l.c.CommitSignup(ctx, req); !errors.Is(err, ErrIntentInvalid) {
			t.Fatal("consumed proof could be retried under new key")
		}
		_, fresh := l.intent(t, ticket, private, "second_user")
		if _, err = l.c.CommitSignup(ctx, fresh); err != nil {
			t.Fatal(err)
		}
	})
	t.Run("expired_result_anchor_rejects_late_post", func(t *testing.T) {
		ticket, private := l.ticket(t)
		_, req := l.intent(t, ticket, private, "anchor_user")
		if _, err := l.c.CommitSignup(ctx, req); err != nil {
			t.Fatal(err)
		}
		key := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", req.IdempotencyKey[:])
		mustExec(t, l.cp, `UPDATE c_auth.request_results SET state='EXPIRED',request_hmac=NULL,hmac_key_version=NULL,intent_id=NULL,result_code=NULL,expires_at=NULL WHERE key_digest=$1`, key[:])
		if _, err := l.c.CommitSignup(ctx, req); !errors.Is(err, ErrExpired) {
			t.Fatalf("late post: %v", err)
		}
		rejectedSQL(t, l.cp, `DELETE FROM c_auth.request_results WHERE key_digest=$1`, key[:])
	})
	t.Run("register_and_retire_compete_for_one_terminal", func(t *testing.T) {
		for i := 0; i < 4; i++ {
			ticket, private := l.ticket(t)
			_, req := l.intent(t, ticket, private, fmt.Sprintf("race_user_%d", i))
			hold, err := l.cp.Begin(ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer hold.Rollback(ctx)
			if err = lockSlot(ctx, hold, ticket.Slot[:]); err != nil {
				t.Fatal(err)
			}
			registered, retired := make(chan error, 1), make(chan error, 1)
			go func() { _, e := l.c.CommitSignup(ctx, req); registered <- e }()
			go func() { retired <- l.c.RetireSlot(ctx, l.authorization(ticket.Slot)) }()
			waitBlocked(t, l.cp, 2)
			if err = hold.Commit(ctx); err != nil {
				t.Fatal(err)
			}
			r1, r2 := <-registered, <-retired
			if (r1 == nil) == (r2 == nil) {
				t.Fatalf("need exactly one winner, signup=%v retire=%v", r1, r2)
			}
			if r1 != nil && !errors.Is(r1, ErrSlotUnavailable) {
				t.Fatal(r1)
			}
			if r2 != nil && !errors.Is(r2, ErrSlotUnavailable) {
				t.Fatal(r2)
			}
			var state string
			if err = l.cp.QueryRow(ctx, `SELECT state FROM c_auth.slot_ledger WHERE slot_id=$1`, ticket.Slot[:]).Scan(&state); err != nil {
				t.Fatal(err)
			}
			if state == "RETIRED" {
				if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE username=$1`, fmt.Sprintf("race_user_%d", i)) != 0 {
					t.Fatal("retired slot also created account")
				}
			}
		}
	})
	t.Run("unique_index_wait_rechecks_deadline_after_provisional_writes", func(t *testing.T) {
		ticket, private := l.ticket(t)
		source, request := l.intent(t, ticket, private, "final_fence_user")
		hold, err := l.cp.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer hold.Rollback(ctx)
		_, err = hold.Exec(ctx, `INSERT INTO c_auth.accounts(account_id,platform_number,state,username,password_hash,password_salt,password_params_version,credential_version,session_generation)
		SELECT gen_random_uuid(),(SELECT lpad(n::text,6,'0') FROM generate_series(0,999999) n WHERE NOT EXISTS(SELECT 1 FROM c_auth.accounts a WHERE a.platform_number=lpad(n::text,6,'0')) LIMIT 1),'ACTIVE',username,password_hash,password_salt,password_params_version,1,1 FROM c_auth.signup_intents WHERE intent_id=$1`, source.ID[:])
		if err != nil {
			t.Fatal(err)
		}
		request = shortIntent(t, l, ticket, private, source, request)
		answer := make(chan error, 1)
		go func() { _, e := l.c.CommitSignup(ctx, request); answer <- e }()
		waitLock(t, l.cp, "transactionid", 1)
		waitIntentExpired(t, l, request.IntentID)
		if err = hold.Rollback(ctx); err != nil {
			t.Fatal(err)
		}
		if err = <-answer; !errors.Is(err, ErrIntentInvalid) {
			t.Fatalf("expected final fence to roll back late signup, got %v", err)
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1`, ticket.Slot[:]) != 0 || count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE username='final_fence_user'`) != 0 {
			t.Fatal("expired provisional writes committed")
		}
		key := digest("HNUHOLE/C-REQUEST-TOMBSTONE/V1", request.IdempotencyKey[:])
		if count(t, l.cp, `SELECT count(*) FROM c_auth.request_results WHERE key_digest=$1`, key[:]) != 0 {
			t.Fatal("rolled-back signup left a committed result")
		}
	})
	t.Run("same_request_concurrent_replay_never_duplicates_session", func(t *testing.T) {
		ticket, private := l.ticket(t)
		_, req := l.intent(t, ticket, private, "samekey_user")
		hold, err := l.cp.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer hold.Rollback(ctx)
		if err = lockSlot(ctx, hold, ticket.Slot[:]); err != nil {
			t.Fatal(err)
		}
		type answer struct {
			r SignupResult
			e error
		}
		answers := make(chan answer, 2)
		for i := 0; i < 2; i++ {
			go func() { r, e := l.c.CommitSignup(ctx, req); answers <- answer{r, e} }()
		}
		waitBlocked(t, l.cp, 2)
		if err = hold.Commit(ctx); err != nil {
			t.Fatal(err)
		}
		one, two := <-answers, <-answers
		if one.e != nil || two.e != nil || one.r.Replay == two.r.Replay {
			t.Fatalf("one fresh and one replay required: %v %v", one.e, two.e)
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.sessions s JOIN c_auth.slot_ledger l USING(account_id) WHERE l.slot_id=$1`, ticket.Slot[:]) != 1 {
			t.Fatal("duplicate session committed")
		}
	})
	t.Run("lock_wait_rechecks_intent_expiry_with_database_time", func(t *testing.T) {
		ticket, private := l.ticket(t)
		intent, req := l.intent(t, ticket, private, "expiry_user")
		// Insert a short-lived immutable test fixture, without weakening the
		// production intent immutability trigger or updating its deadline.
		shortID, err := random32()
		if err != nil {
			t.Fatal(err)
		}
		shortChallenge, err := random32()
		if err != nil {
			t.Fatal(err)
		}
		mustExec(t, l.cp, `INSERT INTO c_auth.signup_intents(intent_id,challenge,ticket,slot_id,bootstrap_public_key,admission_window,username,password_hash,password_salt,password_params_version,recovery_digest,installation_id,created_at,expires_at,state,attempts,authorization_generation)
		SELECT $1,$2,ticket,slot_id,bootstrap_public_key,admission_window,username,password_hash,password_salt,password_params_version,recovery_digest,installation_id,clock_timestamp(),clock_timestamp()+interval '150 milliseconds','OPEN',0,authorization_generation FROM c_auth.signup_intents WHERE intent_id=$3`, shortID[:], shortChallenge[:], intent.ID[:])
		req.IntentID = protocol.IntentID(shortID)
		message := protocol.BootstrapMessageBytes(ticket, req.IntentID, protocol.Challenge(shortChallenge))
		req.Proof = protocol.EncodeCanonicalBase64url(ed25519.Sign(private, message[:]))
		hold, err := l.cp.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer hold.Rollback(ctx)
		if err = lockSlot(ctx, hold, ticket.Slot[:]); err != nil {
			t.Fatal(err)
		}
		answer := make(chan error, 1)
		go func() { _, e := l.c.CommitSignup(ctx, req); answer <- e }()
		waitBlocked(t, l.cp, 1)
		waitContext, cancel := context.WithTimeout(ctx, 3*time.Second)
		defer cancel()
		for {
			var expired bool
			if e := l.cp.QueryRow(waitContext, `SELECT clock_timestamp()>=expires_at FROM c_auth.signup_intents WHERE intent_id=$1`, shortID[:]).Scan(&expired); e != nil {
				t.Fatal(e)
			}
			if expired {
				break
			}
			select {
			case <-waitContext.Done():
				t.Fatal("short fixture did not expire")
			case <-time.After(time.Millisecond):
			}
		}
		if err = hold.Commit(ctx); err != nil {
			t.Fatal(err)
		}
		if err = <-answer; !errors.Is(err, ErrIntentInvalid) {
			t.Fatalf("expired lock waiter: %v", err)
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1`, ticket.Slot[:]) != 0 {
			t.Fatal("stale lock waiter consumed slot")
		}
	})
	t.Run("receipt_ack_loss_retry_and_new_slot_preservation", func(t *testing.T) {
		ticket, _ := l.ticket(t)
		newTicket, _ := l.ticket(t)
		email := []byte("ack.case+1@hainanu.edu.cn")
		if _, err := l.v.ReserveAfterQualification(ctx, email, ticket.BootstrapKey); err != nil {
			t.Fatal(err)
		}
		auth := l.authorization(ticket.Slot)
		if err := l.v.PrepareRetirement(ctx, email, newTicket.BootstrapKey, auth); err != nil {
			t.Fatal(err)
		}
		if err := l.c.RetireSlot(ctx, auth); err != nil {
			t.Fatal(err)
		}
		job, err := l.c.ReceiptJob(ctx, ticket.Slot)
		if err != nil {
			t.Fatal(err)
		}
		signerFailure := errors.New("synthetic HSM unavailable")
		if _, err = l.c.SignReceipt(ctx, ticket.Slot, func(context.Context, uint32, []byte) ([]byte, error) { return nil, signerFailure }); !errors.Is(err, signerFailure) {
			t.Fatal("HSM failure incorrectly committed signature")
		}
		if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE email_exact=$1`, email) != 1 {
			t.Fatal("signer failure released quota")
		}
		if _, err = l.c.SignReceipt(ctx, ticket.Slot, func(_ context.Context, epoch uint32, message []byte) ([]byte, error) {
			return ed25519.Sign(l.cPrivate, message), nil
		}); err != nil {
			t.Fatal(err)
		}
		lostACK := errors.New("synthetic ACK reply lost")
		if err = l.c.DeliverReceipt(ctx, ticket.Slot, func(ctx context.Context, wire string, purpose protocol.Purpose) error {
			if e := l.v.ProcessReceipt(ctx, wire, purpose); e != nil {
				return e
			}
			return lostACK
		}); !errors.Is(err, lostACK) {
			t.Fatalf("lost ACK: %v", err)
		}
		if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE email_exact=$1`, email) != 0 {
			t.Fatal("V commit was undone by lost ACK")
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='READY'`, ticket.Slot[:]) != 1 {
			t.Fatal("C cleaned unacknowledged material")
		}
		rejectedSQL(t, l.cp, `DELETE FROM c_auth.receipt_outbox WHERE slot_id=$1`, ticket.Slot[:])
		// Abort C's ACK transaction after its outbox UPDATE, using a real DB
		// failure at the ledger write. Both C facts must roll back together.
		mustExec(t, l.cp, `CREATE FUNCTION c_auth.lab_fail_ack() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic ACK ledger write failure'; END $$;
		CREATE TRIGGER lab_fail_ack BEFORE UPDATE ON c_auth.slot_ledger FOR EACH ROW WHEN (NEW.receipt_acknowledged) EXECUTE FUNCTION c_auth.lab_fail_ack()`)
		ackErr := l.c.DeliverReceipt(ctx, ticket.Slot, l.v.ProcessReceipt)
		mustExec(t, l.cp, `DROP TRIGGER lab_fail_ack ON c_auth.slot_ledger; DROP FUNCTION c_auth.lab_fail_ack()`)
		var ackPG *pgconn.PgError
		if !errors.As(ackErr, &ackPG) || ackPG.Code != "P0001" {
			t.Fatalf("expected injected local ACK rollback, got %v", ackErr)
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger l JOIN c_auth.receipt_outbox o USING(slot_id) WHERE l.slot_id=$1 AND NOT l.receipt_acknowledged AND o.state='READY' AND o.ack_at IS NULL`, ticket.Slot[:]) != 1 {
			t.Fatal("failed C ACK left partial committed state")
		}
		if _, err = l.v.ReserveAfterQualification(ctx, email, newTicket.BootstrapKey); err != nil {
			t.Fatal(err)
		}
		// A receipt already processed by V remains a durable terminal fact.
		// Local ACK CAS rejects the superseded epoch; the current job retries
		// the same slot/purpose without releasing a later reservation.
		if err = l.c.DeliverReceipt(ctx, ticket.Slot, func(ctx context.Context, wire string, purpose protocol.Purpose) error {
			if e := l.v.ProcessReceipt(ctx, wire, purpose); e != nil {
				return e
			}
			return l.c.RotateReceiptEpoch(ctx, ticket.Slot, 2)
		}); !errors.Is(err, ErrReceiptPending) {
			t.Fatalf("superseded epoch accepted a late ACK: %v", err)
		}
		if _, err = l.c.SignReceipt(ctx, ticket.Slot, func(_ context.Context, _ uint32, message []byte) ([]byte, error) {
			return ed25519.Sign(l.cNextPrivate, message), nil
		}); err != nil {
			t.Fatal(err)
		}
		if err = l.c.DeliverReceipt(ctx, ticket.Slot, l.v.ProcessReceipt); err != nil {
			t.Fatal(err)
		}
		if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE email_exact=$1 AND current_slot=$2`, email, newTicket.Slot[:]) != 1 {
			t.Fatal("old receipt cleared later reservation")
		}
		var ackAt time.Time
		if err = l.cp.QueryRow(ctx, `SELECT ack_at FROM c_auth.receipt_outbox WHERE slot_id=$1`, ticket.Slot[:]).Scan(&ackAt); err != nil {
			t.Fatal(err)
		}
		if err = l.c.recordACK(ctx, ticket.Slot, protocol.PurposeRetired); err != nil {
			t.Fatal(err)
		}
		var again time.Time
		if err = l.cp.QueryRow(ctx, `SELECT ack_at FROM c_auth.receipt_outbox WHERE slot_id=$1`, ticket.Slot[:]).Scan(&again); err != nil || !again.Equal(ackAt) {
			t.Fatal("duplicate ACK extended cleanup deadline")
		}
		if n, err := l.c.CleanupAcknowledged(ctx, ackAt.Add(time.Second)); err != nil || n != 1 {
			t.Fatalf("cleanup: rows=%d err=%v", n, err)
		}
		if stored, err := l.c.StoreSignature(ctx, job, ed25519.Sign(l.cPrivate, job.Message)); err != nil || stored {
			t.Fatal("late signer resurrected cleaned outbox")
		}
		rejectedSQL(t, l.cp, `UPDATE c_auth.slot_ledger SET receipt_acknowledged=false WHERE slot_id=$1`, ticket.Slot[:])
		rejectedSQL(t, l.cp, `DELETE FROM c_auth.slot_ledger WHERE slot_id=$1`, ticket.Slot[:])
		if err = l.c.RetireSlot(ctx, auth); err != nil {
			t.Fatal(err)
		}
		if count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1`, ticket.Slot[:]) != 0 {
			t.Fatal("repeat retirement rebuilt acknowledged outbox")
		}
		conflict := protocol.Receipt{Purpose: protocol.PurposeReleased, Epoch: 1, Slot: ticket.Slot}
		msg, err := conflict.MessageBytes()
		if err != nil {
			t.Fatal(err)
		}
		copy(conflict.Signature[:], ed25519.Sign(l.cPrivate, msg))
		wire, err := conflict.Encode()
		if err != nil {
			t.Fatal(err)
		}
		if err = l.v.ProcessReceipt(ctx, wire, protocol.PurposeReleased); !errors.Is(err, ErrReconciliation) {
			t.Fatal("opposite purpose accepted")
		}
	})
	t.Run("same_email_quota_serializes_exact_bytes", func(t *testing.T) {
		one, _ := l.ticket(t)
		two, _ := l.ticket(t)
		email := []byte("quota.case@hainanu.edu.cn")
		done := make(chan error, 2)
		for _, key := range []protocol.PublicKey{one.BootstrapKey, two.BootstrapKey} {
			go func(key protocol.PublicKey) { _, e := l.v.ReserveAfterQualification(ctx, email, key); done <- e }(key)
		}
		e1, e2 := <-done, <-done
		if (e1 == nil) == (e2 == nil) {
			t.Fatalf("need one quota winner: %v %v", e1, e2)
		}
		if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE email_exact=$1`, email) != 1 {
			t.Fatal("same exact address duplicated")
		}
		upper, _ := l.ticket(t)
		if _, err := l.v.ReserveAfterQualification(ctx, []byte("Quota.case@hainanu.edu.cn"), upper.BootstrapKey); err != nil {
			t.Fatal("case-distinct exact address incorrectly folded")
		}
	})
	t.Run("unknown_and_unsigned_receipts_cannot_release", func(t *testing.T) {
		ticket, _ := l.ticket(t)
		r := protocol.Receipt{Purpose: protocol.PurposeRetired, Epoch: 1, Slot: ticket.Slot}
		msg, err := r.MessageBytes()
		if err != nil {
			t.Fatal(err)
		}
		copy(r.Signature[:], ed25519.Sign(l.cPrivate, msg))
		wire, err := r.Encode()
		if err != nil {
			t.Fatal(err)
		}
		if err = l.v.ProcessReceipt(ctx, wire, protocol.PurposeRetired); !errors.Is(err, ErrReconciliation) {
			t.Fatal("unknown mapped receipt acknowledged")
		}
		r.Signature[0] ^= 1
		wire, _ = r.Encode()
		if err = l.v.ProcessReceipt(ctx, wire, protocol.PurposeRetired); err == nil {
			t.Fatal("invalid signature acknowledged")
		}
		if count(t, l.vp, `SELECT count(*) FROM v_auth.processed_receipts WHERE slot_id=$1`, ticket.Slot[:]) != 0 {
			t.Fatal("rejected receipt left processed fact")
		}
	})
	t.Run("database_columns_do_not_join_email_or_store_plaintext_secrets", func(t *testing.T) {
		if count(t, l.cp, `SELECT count(*) FROM information_schema.columns WHERE table_schema='c_auth' AND column_name ILIKE '%email%'`) != 0 {
			t.Fatal("C has email column")
		}
		if count(t, l.vp, `SELECT count(*) FROM information_schema.columns WHERE table_schema='v_auth' AND (column_name ILIKE '%account%' OR column_name ILIKE '%username%' OR column_name ILIKE '%password%' OR column_name ILIKE '%recovery%')`) != 0 {
			t.Fatal("V has community credential column")
		}
		var token []byte
		if err := l.cp.QueryRow(ctx, `SELECT token_digest FROM c_auth.sessions LIMIT 1`).Scan(&token); err != nil || bytes.Equal(token, make([]byte, 32)) {
			t.Fatal("missing derived session digest")
		}
	})
}
