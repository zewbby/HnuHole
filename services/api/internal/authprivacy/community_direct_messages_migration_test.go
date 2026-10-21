package authprivacy

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Reuses the runner's two dedicated, empty upgrade databases. This test is
// selected separately from the older comment migration suite.
func TestDMGooseFreshAndUpgradePostgres(t *testing.T) {
	tool := os.Getenv("COMMENT_TEXT_GOOSE")
	if tool == "" {
		t.Skip("owned Goose fixture absent")
	}
	for _, mode := range []string{"fresh", "upgrade"} {
		t.Run(mode, func(t *testing.T) {
			ctx := context.Background()
			dsn := os.Getenv("COMMENT_TEXT_" + strings.ToUpper(mode) + "_DSN")
			cfg, err := pgxpool.ParseConfig(dsn)
			if err != nil || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" ||
				!strings.HasPrefix(os.Getenv("AUTHLAB_RUNTIME_TAG"), "hnuhole_authlab_") ||
				cfg.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
				t.Fatal("owned migration fixture required")
			}
			pool, err := pgxpool.NewWithConfig(ctx, cfg)
			if err != nil {
				t.Fatal(err)
			}
			defer pool.Close()
			var safe bool
			if err = pool.QueryRow(ctx, `SELECT current_database()=$1 AND current_user='hnuhole_c' AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AND inet_server_addr() IS NULL AND to_regnamespace('c_auth') IS NULL AND to_regclass('public.goose_db_version') IS NULL`, "hnuhole_comments_"+mode).Scan(&safe); err != nil || !safe {
				t.Fatal("fresh dedicated database required", err)
			}
			dir, err := filepath.Abs("../../migrations")
			if err != nil {
				t.Fatal(err)
			}
			run := func(command string, args ...string) error {
				return exec.Command(tool, append([]string{"-dir", dir, "postgres", dsn, command}, args...)...).Run()
			}
			const snapshot = `SELECT md5(jsonb_build_object('accounts',(SELECT jsonb_agg(to_jsonb(a) ORDER BY account_id) FROM c_auth.accounts a),'preferences',(SELECT jsonb_agg(to_jsonb(p) ORDER BY account_id) FROM c_posts.feed_preferences p),'channels',(SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.channels c))::text)`
			var before string
			if mode == "upgrade" {
				if err = run("up-to", "21"); err != nil {
					t.Fatal("0021 baseline", err)
				}
				mustExec(t, pool, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('d2c920f5-5563-452d-901c-be133844b0fa','001829','dm_upgrade',decode(repeat('11',32),'hex'),decode(repeat('22',16),'hex'),1); INSERT INTO c_posts.feed_preferences VALUES('d2c920f5-5563-452d-901c-be133844b0fa','{}',3)`)
				if err = pool.QueryRow(ctx, snapshot).Scan(&before); err != nil {
					t.Fatal(err)
				}
			}
			if err = run("up"); err != nil {
				t.Fatal("0022 upgrade", err)
			}
			if count(t, pool, `SELECT count(*) FROM public.goose_db_version WHERE is_applied`) != 23 || count(t, pool, `SELECT max(version_id) FROM public.goose_db_version WHERE is_applied`) != 22 {
				t.Fatal("migration chain incomplete")
			}
			c := &Community{pool: pool}
			if err = c.checkDMSchema(ctx); err != nil {
				t.Fatal("DM guards", err)
			}
			if mode == "upgrade" {
				var after string
				if err = pool.QueryRow(ctx, snapshot).Scan(&after); err != nil || before != after {
					t.Fatal("existing data changed", err)
				}
			}
			if count(t, pool, `SELECT count(*) FROM c_dm.commands`) != 0 || count(t, pool, `SELECT count(*) FROM c_dm.messages`) != 0 {
				t.Fatal("fabricated DM history")
			}
			if err = run("down"); err == nil {
				t.Fatal("destructive rollback accepted")
			}
			if count(t, pool, `SELECT max(version_id) FROM public.goose_db_version WHERE is_applied`) != 22 {
				t.Fatal("failed Down changed ledger")
			}
		})
	}
}
