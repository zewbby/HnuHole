package authprivacyruntime

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

// This suite uses the same explicitly disposable, private-socket C database as
// the other SQL suites. Run packages serially; never reset a shared/live schema.
func moderationStartupLab(t *testing.T) (*pgxpool.Pool, *pgxpool.Pool) {
	t.Helper()
	ownerDSN, runtimeDSN := os.Getenv("AUTHLAB_C_DSN"), os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN")
	if ownerDSN == "" && runtimeDSN == "" {
		t.Skip("isolated C owner/runtime DSNs absent; startup SQL regression not executed")
	}
	tag := os.Getenv("AUTHLAB_RUNTIME_TAG")
	if ownerDSN == "" || runtimeDSN == "" || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(tag, "hnuhole_authlab_") {
		t.Fatal("startup test requires an explicitly disposable owner/runtime fixture")
	}
	ctx := context.Background()
	connect := func(dsn, expected string) *pgxpool.Pool {
		config, err := pgxpool.ParseConfig(dsn)
		if err != nil || config.ConnConfig.RuntimeParams["application_name"] != tag {
			t.Fatal("startup fixture marker mismatch")
		}
		pool, err := pgxpool.NewWithConfig(ctx, config)
		if err != nil {
			t.Fatal("startup fixture connection failed")
		}
		t.Cleanup(pool.Close)
		var database, user string
		var privileged bool
		var address *string
		err = pool.QueryRow(ctx, `SELECT current_database(),current_user,(SELECT rolsuper OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname=current_user),inet_server_addr()::text`).Scan(&database, &user, &privileged, &address)
		if err != nil || database != "hnuhole_c" || user != expected || privileged || address != nil {
			t.Fatal("refusing reset outside the non-superuser, private-socket C fixture")
		}
		return pool
	}
	owner := connect(ownerDSN, "hnuhole_c")
	runtime := connect(runtimeDSN, "hnuhole_c_runtime")
	tx, err := owner.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `DROP SCHEMA IF EXISTS c_comments,c_moderation,c_posts,c_auth CASCADE;
DROP TABLE IF EXISTS public.identity_change_receipts,public.community_identities,public.identity_account_state,public.sessions,public.channels,public.goose_db_version CASCADE;
DROP FUNCTION IF EXISTS public.guard_identity_account_state(),public.guard_community_identity(),public.guard_identity_receipt(),public.check_identity_account_shape() CASCADE`); err != nil {
		t.Fatal(err)
	}
	files, err := filepath.Glob("../../migrations/*.sql")
	if err != nil || len(files) == 0 {
		t.Fatal("formal C migrations absent")
	}
	for _, file := range files {
		sql, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = tx.Exec(ctx, strings.SplitN(string(sql), "-- +goose Down", 2)[0]); err != nil {
			t.Fatalf("formal migration %s: %v", filepath.Base(file), err)
		}
	}
	if _, err = tx.Exec(ctx, `CREATE TABLE public.goose_db_version(version_id bigint,is_applied boolean);
INSERT INTO public.goose_db_version VALUES(15,true);
REVOKE CREATE,TEMP ON DATABASE hnuhole_c FROM PUBLIC,hnuhole_c_runtime`); err != nil {
		t.Fatal(err)
	}
	grant, err := os.ReadFile("../../../../infra/postgres/grant-community.sql")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec(ctx, string(grant)); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	return owner, runtime
}

func TestModerationLifecycleCommonCStartupWithoutFeaturesPostgres(t *testing.T) {
	owner, runtime := moderationStartupLab(t)
	ctx := context.Background()
	// CheckDatabase is deliberately called without optional Posts/Moderation
	// configuration, exactly as Run does before constructing those features.
	if err := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); err != nil {
		t.Fatalf("old C config rejected complete lifecycle cleanup grants: %v", err)
	}
	exec := func(t *testing.T, sql string) {
		t.Helper()
		if _, err := owner.Exec(ctx, sql); err != nil {
			t.Fatal(err)
		}
	}
	for _, access := range []struct{ name, revoke, grant string }{
		{"access session cleanup", `REVOKE DELETE ON c_moderation.access_sessions FROM hnuhole_c_runtime`, `GRANT DELETE ON c_moderation.access_sessions TO hnuhole_c_runtime`},
		{"case state cleanup", `REVOKE UPDATE(version) ON c_moderation.cases FROM hnuhole_c_runtime`, `GRANT UPDATE(version) ON c_moderation.cases TO hnuhole_c_runtime`},
		{"notification cleanup", `REVOKE DELETE ON c_moderation.notifications FROM hnuhole_c_runtime`, `GRANT DELETE ON c_moderation.notifications TO hnuhole_c_runtime`},
		{"role lookup for cleanup", `REVOKE SELECT(account_id) ON c_moderation.roles FROM hnuhole_c_runtime`, `GRANT SELECT(account_id) ON c_moderation.roles TO hnuhole_c_runtime`},
	} {
		t.Run(access.name, func(t *testing.T) {
			exec(t, access.revoke)
			defer exec(t, access.grant)
			if err := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); err == nil || err.Error() != "moderation lifecycle schema or privileges absent" {
				t.Fatalf("common C startup accepted missing cleanup permission: %v", err)
			}
		})
	}
	for _, access := range []struct{ name, revoke, grant string }{
		{"legacy write", `REVOKE UPDATE(mute_state) ON c_moderation.legacy_restrictions FROM hnuhole_c_runtime`, `GRANT UPDATE(mute_state) ON c_moderation.legacy_restrictions TO hnuhole_c_runtime`},
		{"legacy aggregate", `REVOKE SELECT(action) ON c_moderation.sanctions FROM hnuhole_c_runtime`, `GRANT SELECT(action) ON c_moderation.sanctions TO hnuhole_c_runtime`},
	} {
		t.Run(access.name, func(t *testing.T) {
			exec(t, access.revoke)
			defer exec(t, access.grant)
			if err := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); err == nil || err.Error() != "moderation legacy restriction schema or privileges absent" {
				t.Fatal("common C startup accepted missing legacy grant", err)
			}
		})
	}
	for _, hook := range []struct{ table, name, restore string }{
		{"c_auth.accounts", "moderation_account_closed", `CREATE TRIGGER moderation_account_closed AFTER UPDATE OF state ON c_auth.accounts FOR EACH ROW EXECUTE FUNCTION c_moderation.closed_account()`},
		{"c_posts.posts", "moderation_post_deleted", `CREATE TRIGGER moderation_post_deleted AFTER UPDATE OF visibility ON c_posts.posts FOR EACH ROW EXECUTE FUNCTION c_moderation.deleted_post()`},
	} {
		t.Run(hook.name, func(t *testing.T) {
			exec(t, "DROP TRIGGER "+hook.name+" ON "+hook.table)
			defer exec(t, hook.restore)
			if err := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); err == nil || err.Error() != "moderation lifecycle schema or privileges absent" {
				t.Fatalf("common C startup accepted missing lifecycle hook: %v", err)
			}
		})
	}
	if err := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); err != nil {
		t.Fatal("restored lifecycle permissions/hooks rejected", err)
	}
	exec(t, `ALTER TABLE c_moderation.legacy_restrictions DROP COLUMN ban_ends_at`)
	if err := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); err == nil || err.Error() != "moderation legacy restriction schema or privileges absent" {
		t.Fatal("common C startup accepted missing legacy column", err)
	}
	// Model the formal 0014 shape, without requiring absent moderation objects.
	exec(t, `DROP SCHEMA c_moderation CASCADE;
ALTER TABLE c_posts.posts DROP COLUMN moderation_hidden;
ALTER TABLE public.community_identities DROP COLUMN moderation_rename_required;
UPDATE public.goose_db_version SET version_id=14`)
	if err := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); err != nil {
		t.Fatalf("0014 C startup acquired a moderation dependency: %v", err)
	}
}
