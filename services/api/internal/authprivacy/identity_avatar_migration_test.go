package authprivacy

import (
	"context"
	"github.com/jackc/pgx/v5/pgxpool"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestIdentityAvatarGooseFreshAndUpgradePostgres(t *testing.T) {
	tool := os.Getenv("COMMENT_TEXT_GOOSE")
	if tool == "" {
		t.Skip("owned Goose fixture absent")
	}
	for _, mode := range []string{"fresh", "upgrade"} {
		t.Run(mode, func(t *testing.T) {
			ctx := context.Background()
			dsn := os.Getenv("COMMENT_TEXT_" + strings.ToUpper(mode) + "_DSN")
			cfg, e := pgxpool.ParseConfig(dsn)
			if e != nil || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(os.Getenv("AUTHLAB_RUNTIME_TAG"), "hnuhole_authlab_") || cfg.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
				t.Fatal("owned migration fixture required")
			}
			pool, e := pgxpool.NewWithConfig(ctx, cfg)
			if e != nil {
				t.Fatal(e)
			}
			defer pool.Close()
			var safe bool
			e = pool.QueryRow(ctx, `SELECT current_database()=$1 AND current_user='hnuhole_c' AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AND inet_server_addr() IS NULL AND to_regnamespace('c_auth') IS NULL AND to_regclass('public.goose_db_version') IS NULL`, "hnuhole_comments_"+mode).Scan(&safe)
			if e != nil || !safe {
				t.Fatal("fresh dedicated database required", e)
			}
			dir, _ := filepath.Abs("../../migrations")
			run := func(command string, args ...string) error {
				return exec.Command(tool, append([]string{"-dir", dir, "postgres", dsn, command}, args...)...).Run()
			}
			var before string
			const snapshot = `SELECT md5(jsonb_build_object('profiles',(SELECT jsonb_agg(to_jsonb(i)) FROM public.community_identities i),'receipts',(SELECT jsonb_agg(to_jsonb(r)) FROM public.identity_change_receipts r))::text)`
			if mode == "upgrade" {
				if e = run("up-to", "24"); e != nil {
					t.Fatal(e)
				}
				mustExec(t, pool, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('d2c920f5-5563-452d-901c-be133844b0fa','001829','avatar_upgrade',decode(repeat('11',32),'hex'),decode(repeat('22',16),'hex'),1);
INSERT INTO public.identity_account_state VALUES('d2c920f5-5563-452d-901c-be133844b0fa',1,now());
INSERT INTO public.community_identities(identity_id,account_id,nickname,avatar,is_original,created_at) VALUES('11111111-1111-4111-8111-111111111111','d2c920f5-5563-452d-901c-be133844b0fa','旧头像','default-v1',true,now());
INSERT INTO public.identity_change_receipts(account_id,change_key_digest,intent_fingerprint,state,operation,identity_id,committed_at) VALUES('d2c920f5-5563-452d-901c-be133844b0fa',decode(repeat('12',32),'hex'),decode(repeat('13',32),'hex'),'COMMITTED','CREATE','11111111-1111-4111-8111-111111111111',now())`)
				if e = pool.QueryRow(ctx, snapshot).Scan(&before); e != nil {
					t.Fatal(e)
				}
			}
			if e = run("up"); e != nil {
				t.Fatal("0025 migration", e)
			}
   if count(t, pool, `SELECT max(version_id) FROM public.goose_db_version WHERE is_applied`) != 26 || count(t, pool, `SELECT count(*) FROM public.identity_avatar_assets`) != 0 {
				t.Fatal("avatar migration fabricated data")
			}
			if mode == "upgrade" {
				var after string
				if e = pool.QueryRow(ctx, snapshot).Scan(&after); e != nil || before != after {
					t.Fatal("profile or V1 receipt changed", e)
				}
			}
			if e = run("up"); e != nil {
				t.Fatal("migration not repeatable", e)
			}
			if e = run("down"); e == nil {
				t.Fatal("destructive rollback accepted")
			}
		})
	}
}
