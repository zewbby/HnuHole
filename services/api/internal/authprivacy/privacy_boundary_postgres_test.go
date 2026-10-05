package authprivacy

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

func privacyRelations(t *testing.T, pool *pgxpool.Pool) []string {
	t.Helper()
	rows, err := pool.Query(context.Background(), `SELECT n.nspname,c.relname,c.relkind::text
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('public','c_auth','v_auth') AND c.relkind IN ('r','p','v','m','f')
ORDER BY n.nspname,c.relname`)
	if err != nil {
		t.Fatal("cannot inventory privacy schema")
	}
	defer rows.Close()
	var names []string
	for rows.Next() {
		var schema, name, kind string
		if rows.Scan(&schema, &name, &kind) != nil {
			t.Fatal("cannot read privacy schema inventory")
		}
		if kind != "r" {
			t.Fatal("unexpected view, foreign or partitioned privacy relation")
		}
		names = append(names, schema+"."+name)
	}
	if rows.Err() != nil {
		t.Fatal("incomplete privacy schema inventory")
	}
	return names
}

func TestPrivacySchemaPartyBoundaryPostgres(t *testing.T) {
	l := newLab(t)
	for _, spec := range []struct {
		name       string
		pool       *pgxpool.Pool
		relations  []string
		prohibited []string
	}{
		{"community", l.cp, []string{
			"c_auth.account_restrictions", "c_auth.accounts", "c_auth.auth_challenges",
			"c_auth.authorization_gate", "c_auth.authorization_gate_audit", "c_auth.closure_requests",
			"c_auth.credential_change_intents", "c_auth.passkeys", "c_auth.receipt_outbox",
			"c_auth.recent_device_replacement", "c_auth.recovery_codes", "c_auth.request_results",
			"c_auth.reset_intents", "c_auth.security_events", "c_auth.sessions", "c_auth.signup_intents",
			"c_auth.slot_ledger", "public.channels", "public.community_identities",
			"public.identity_account_state", "public.identity_change_receipts", "public.sessions",
		}, []string{"email", "otp", "mail"}},
		{"verifier", l.vp, []string{
			"v_auth.authorization_gate", "v_auth.authorization_gate_audit", "v_auth.confirmation_rejections",
			"v_auth.confirmation_sign_jobs", "v_auth.device_email_limits", "v_auth.email_quota",
			"v_auth.mail_outbox", "v_auth.otp_budget_events", "v_auth.otp_code_versions",
			"v_auth.otp_confirmations", "v_auth.otp_email_state", "v_auth.otp_flows",
			"v_auth.processed_receipts", "v_auth.request_results", "v_auth.retire_pending", "v_auth.used_slots",
		}, []string{"account", "community", "identity", "username", "nickname", "avatar", "password", "recovery", "session", "platform", "user_handle", "credential", "revoke", "reset"}},
	} {
		t.Run(spec.name, func(t *testing.T) {
			want := append([]string(nil), spec.relations...)
			sort.Strings(want)
			if strings.Join(privacyRelations(t, spec.pool), "\n") != strings.Join(want, "\n") {
				t.Fatal("party schema relation inventory changed; audit the new data boundary")
			}
			rows, err := spec.pool.Query(context.Background(), `SELECT table_schema,table_name,column_name
FROM information_schema.columns WHERE table_schema IN ('public','c_auth','v_auth')`)
			if err != nil {
				t.Fatal("cannot inventory privacy columns")
			}
			defer rows.Close()
			for rows.Next() {
				var schema, table, column string
				if rows.Scan(&schema, &table, &column) != nil {
					t.Fatal("cannot read privacy column inventory")
				}
				for _, prohibited := range spec.prohibited {
					if strings.Contains(strings.ToLower(column), prohibited) {
						t.Fatalf("unexpected party column: %s.%s.%s", schema, table, column)
					}
				}
			}
			if rows.Err() != nil {
				t.Fatal("incomplete privacy column inventory")
			}
			if count(t, spec.pool, `SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('public','c_auth','v_auth') AND p.prosecdef`) != 0 ||
				count(t, spec.pool, `SELECT count(*) FROM pg_foreign_server`) != 0 {
				t.Fatal("unexpected privileged function or foreign-server bridge")
			}
		})
	}
}

func privacyRows(t *testing.T, pool *pgxpool.Pool) string {
	t.Helper()
	var result strings.Builder
	for _, name := range privacyRelations(t, pool) {
		parts := strings.SplitN(name, ".", 2)
		var rows string
		query := `SELECT COALESCE(jsonb_agg(to_jsonb(r))::text,'[]') FROM ` + pgx.Identifier(parts).Sanitize() + ` r`
		if pool.QueryRow(context.Background(), query).Scan(&rows) != nil {
			t.Fatal("cannot inspect isolated party rows")
		}
		result.WriteString(rows)
	}
	return result.String()
}

// Synthetic eligibility is used solely to seed the storage boundary. This
// test does not claim to prove production OTP delivery or a complete app flow.
func TestPrivacySeededPartyRowsPostgres(t *testing.T) {
	l, e, _ := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	email := "privacy-boundary@hainanu.edu.cn"
	vRequest := otpFixtureRequest(t, email)
	if _, err := e.RequestOTP(ctx, vRequest); err != nil {
		t.Fatal("cannot seed isolated verifier OTP state")
	}
	ticket, private := l.ticket(t)
	if _, err := l.v.ReserveAfterQualification(ctx, []byte(email), ticket.BootstrapKey); err != nil {
		t.Fatal("cannot seed isolated verifier quota")
	}
	username, nickname := "privacy_boundary_user", "隐私边界"
	_, request := l.intent(t, ticket, private, username)
	account, err := l.c.CommitSignup(ctx, request)
	if err != nil {
		t.Fatal("cannot seed isolated community account")
	}
	identity := identityChange(t, l.c, account.SessionToken, "CREATE", uuid.Nil, nickname)
	var passwordHash, cInstallation []byte
	if l.cp.QueryRow(ctx, `SELECT a.password_hash,s.installation_id FROM c_auth.accounts a
JOIN c_auth.sessions s USING(account_id) WHERE a.account_id=$1`, account.AccountID).Scan(&passwordHash, &cInstallation) != nil {
		t.Fatal("cannot inspect synthetic community credentials")
	}
	if len(cInstallation) != 16 || bytes.Equal(cInstallation, vRequest.InstallationID[:]) {
		t.Fatal("party installation identifiers were reused")
	}
	cRows, vRows := privacyRows(t, l.cp), privacyRows(t, l.vp)
	emailHash := sha256.Sum256([]byte(email))
	for _, forbidden := range []string{email, hex.EncodeToString([]byte(email)), hex.EncodeToString(emailHash[:]), hex.EncodeToString(vRequest.InstallationID[:])} {
		if strings.Contains(cRows, forbidden) {
			t.Fatal("community rows retained verifier email, unkeyed email hash or installation")
		}
	}
	for _, forbidden := range []string{account.AccountID.String(), identity.IdentityID.String(), username, nickname, hex.EncodeToString(passwordHash), hex.EncodeToString(cInstallation)} {
		if strings.Contains(vRows, forbidden) {
			t.Fatal("verifier rows retained community account, profile, credential or installation")
		}
	}
	// The common qualification slot is intentional. Both-party access can join
	// these records; this check must not promise unlinkability under collusion.
	if !strings.Contains(cRows, hex.EncodeToString(ticket.Slot[:])) || !strings.Contains(vRows, hex.EncodeToString(ticket.Slot[:])) {
		t.Fatal("synthetic signup did not populate the intended shared slot boundary")
	}
}

func TestPrivacyDatabaseDiagnosticsPostgres(t *testing.T) {
	l := newLab(t)
	settings := map[string]string{
		"log_statement": "none", "log_min_messages": "panic", "log_min_error_statement": "panic",
		"log_error_verbosity": "terse", "log_parameter_max_length": "0", "log_parameter_max_length_on_error": "0",
		"log_min_duration_statement": "-1", "log_min_duration_sample": "-1", "log_transaction_sample_rate": "0", "log_duration": "off",
	}
	for _, pool := range []*pgxpool.Pool{l.cp, l.vp} {
		for name, want := range settings {
			var setting string
			if pool.QueryRow(context.Background(), `SELECT setting FROM pg_settings WHERE name=$1`, name).Scan(&setting) != nil || setting != want {
				t.Fatalf("unsafe or absent database diagnostic setting: %s", name)
			}
		}
	}
	logPath := os.Getenv("AUTHLAB_POSTGRES_LOG")
	if logPath == "" || !filepath.IsAbs(logPath) {
		t.Fatal("isolated PostgreSQL log is required for the diagnostic canary")
	}
	if _, err := os.ReadFile(logPath); err != nil {
		t.Fatal("cannot read isolated PostgreSQL log before canary")
	}
	key, err := random32()
	if err != nil {
		t.Fatal("cannot create synthetic diagnostic sentinel")
	}
	// PostgreSQL may truncate per-column values in constraint DETAIL. Keep the
	// sentinel below that bound so the positive assertion checks the actual
	// secret, rather than accidentally demanding an untruncated long string.
	secret := "ac03-private-" + hex.EncodeToString(key[:16])
	for _, pool := range []*pgxpool.Pool{l.cp, l.vp} {
		conn, err := pool.Acquire(context.Background())
		if err != nil {
			t.Fatal("cannot acquire isolated diagnostic connection")
		}
		func() {
			defer conn.Release()
			for _, sql := range []string{
				`CREATE TEMP TABLE privacy_diagnostic_canary(value text UNIQUE,valid boolean CHECK(valid))`,
				`CREATE FUNCTION pg_temp.privacy_diagnostic_error(v text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic diagnostic error' USING DETAIL=v,HINT=v; END $$`,
			} {
				if _, err := conn.Exec(context.Background(), sql); err != nil {
					t.Fatal("cannot prepare isolated diagnostic canary")
				}
			}
			if _, err := conn.Exec(context.Background(), `INSERT INTO privacy_diagnostic_canary VALUES($1,true)`, secret); err != nil {
				t.Fatal("cannot seed isolated diagnostic canary")
			}
			for _, probe := range []struct {
				sql, code string
				args      []any
				detail    bool
			}{
				{`INSERT INTO privacy_diagnostic_canary VALUES($1,true)`, "23505", []any{secret}, true},
				{`INSERT INTO privacy_diagnostic_canary VALUES($1,false)`, "23514", []any{secret + "-check"}, true},
				{`SELECT pg_temp.privacy_diagnostic_error($1::text)`, "P0001", []any{secret}, true},
				{`SELECT $1::text::uuid`, "22P02", []any{secret}, false},
			} {
				_, err := conn.Exec(context.Background(), probe.sql, probe.args...)
				var pgError *pgconn.PgError
				if !errors.As(err, &pgError) || pgError.Code != probe.code {
					t.Fatal("diagnostic canary did not trigger its expected database error")
				}
				material := pgError.Message
				if probe.detail {
					material = pgError.Detail
				}
				if !strings.Contains(material, secret) {
					t.Fatalf("database error did not exercise the sensitive material boundary (%s)", probe.code)
				}
			}
		}()
	}
	logBytes, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal("cannot read isolated PostgreSQL log after canary")
	}
	if bytes.Contains(logBytes, []byte(secret)) || bytes.Contains(logBytes, []byte("privacy_diagnostic_canary")) || bytes.Contains(logBytes, []byte("privacy_diagnostic_error")) {
		t.Fatal("ordinary PostgreSQL diagnostics exposed canary SQL or synthetic secret")
	}
}
