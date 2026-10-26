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

func TestNotificationInboxGooseMigrationPostgres(t *testing.T) {
	tool := os.Getenv("COMMENT_TEXT_GOOSE")
	if tool == "" {
		t.Skip("owned Goose fixture absent")
	}
	for _, mode := range []string{"upgrade", "fresh"} {
		t.Run(mode, func(t *testing.T) {
			ctx := context.Background()
			dsn := os.Getenv("NOTIFICATION_" + strings.ToUpper(mode) + "_DSN")
			if dsn == "" {
				t.Skip("owned notification migration fixture absent")
			}
			cfg, e := pgxpool.ParseConfig(dsn)
			if e != nil || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(os.Getenv("AUTHLAB_RUNTIME_TAG"), "hnuhole_authlab_") || cfg.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
				t.Fatal("owned fixture marker required")
			}
			pool, e := pgxpool.NewWithConfig(ctx, cfg)
			if e != nil {
				t.Fatal(e)
			}
			defer pool.Close()
			var safe bool
			e = pool.QueryRow(ctx, `SELECT current_database()=$1 AND current_user='hnuhole_c' AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AND inet_server_addr() IS NULL AND to_regnamespace('c_auth') IS NULL AND to_regclass('public.goose_db_version') IS NULL`, "hnuhole_notifications_"+mode).Scan(&safe)
			if e != nil || !safe {
				t.Fatal("dedicated empty private-socket database required", e)
			}
			dir, e := filepath.Abs("../../migrations")
			if e != nil {
				t.Fatal(e)
			}
			run := func(args ...string) error {
				return exec.Command(tool, append([]string{"-dir", dir, "postgres", dsn}, args...)...).Run()
			}
			if mode == "upgrade" {
				if e = run("up-to", "27"); e != nil {
					t.Fatal("main migration chain", e)
				}
				mustExec(t, pool, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('d2c920f5-5563-452d-901c-be133844b0fa','001829','notice_upgrade',decode(repeat('11',32),'hex'),decode(repeat('22',16),'hex'),1)`)
			}
			if e = run("up-to", "28"); e != nil {
				t.Fatal("notification migration", e)
			}
			if count(t, pool, `SELECT count(*) FROM public.goose_db_version WHERE is_applied`) != 29 {
				t.Fatal("incomplete migration chain")
			}
			if mode == "upgrade" && count(t, pool, `SELECT count(*) FROM c_auth.accounts WHERE username='notice_upgrade'`) != 1 {
				t.Fatal("lost historical account")
			}
			if e = checkInboxLifecycleSchema(ctx, pool); e != nil {
				t.Fatal(e)
			}
			if e = run("down"); e == nil {
				t.Fatal("recipient facts rolled back")
			}
			if count(t, pool, `SELECT count(*) FROM public.goose_db_version WHERE is_applied AND version_id=28`) != 1 {
				t.Fatal("failed down changed ledger")
			}
		})
	}
}
