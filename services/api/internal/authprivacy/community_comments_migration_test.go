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

func TestCommentTextGooseMigrationChainPostgres(t *testing.T) {
	tool := os.Getenv("COMMENT_TEXT_GOOSE")
	if tool == "" {
		t.Skip("owned Goose/private upgrade fixture not configured")
	}
	for _, mode := range []string{"upgrade", "fresh"} {
		t.Run(mode, func(t *testing.T) {
			ctx := context.Background()
			dsn := os.Getenv("COMMENT_TEXT_" + strings.ToUpper(mode) + "_DSN")
			cfg, e := pgxpool.ParseConfig(dsn)
			if e != nil || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(os.Getenv("AUTHLAB_RUNTIME_TAG"), "hnuhole_authlab_") || cfg.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
				t.Fatal("isolated migration marker required")
			}
			pool, e := pgxpool.NewWithConfig(ctx, cfg)
			if e != nil {
				t.Fatal(e)
			}
			defer pool.Close()
			var database, user string
			var super bool
			var address *string
			if e = pool.QueryRow(ctx, `SELECT current_database(),current_user,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),inet_server_addr()::text`).Scan(&database, &user, &super, &address); e != nil || database != "hnuhole_comments_"+mode || user != "hnuhole_c" || super || address != nil {
				t.Fatal("unowned migration database")
			}
			var empty bool
			if e = pool.QueryRow(ctx, `SELECT to_regnamespace('c_auth') IS NULL AND to_regclass('public.goose_db_version') IS NULL`).Scan(&empty); e != nil || !empty {
				t.Fatal("migration database must be new")
			}
			dir, e := filepath.Abs("../../migrations")
			if e != nil {
				t.Fatal(e)
			}
			run := func(command string, args ...string) error {
				argv := append([]string{"-dir", dir, "postgres", dsn, command}, args...)
				return exec.Command(tool, argv...).Run()
			}
			if mode == "upgrade" {
				if e = run("up-to", "14"); e != nil {
					t.Fatal("formal 0001..0014 install failed")
				}
				// A real pre-governance account survives both forward migrations.
				if _, e = pool.Exec(ctx, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('a811e9fa-7663-4182-88c4-465512194416','001527','comment_upgrade_fixture',decode(repeat('11',32),'hex'),decode(repeat('22',16),'hex'),1)`); e != nil {
					t.Fatal(e)
				}
				if e = run("up-to", "15"); e != nil {
					t.Fatal("real governance 0015 upgrade failed")
				}
				if e = run("up"); e != nil {
					t.Fatal("0015 to 0017 upgrade failed")
				}
				var preserved bool
				if e = pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_moderation.platform_numbers WHERE number='001527')`).Scan(&preserved); e != nil || !preserved {
					t.Fatal("upgrade lost historical account")
				}
			} else if e = run("up"); e != nil {
				t.Fatal("empty database 0001..0017 installation failed")
			}
			var versions []int64
			rows, e := pool.Query(ctx, `SELECT version_id FROM public.goose_db_version WHERE is_applied ORDER BY version_id`)
			if e != nil {
				t.Fatal(e)
			}
			for rows.Next() {
				var v int64
				if e = rows.Scan(&v); e != nil {
					t.Fatal(e)
				}
				versions = append(versions, v)
			}
			rows.Close()
			if len(versions) != 18 {
				t.Fatal("missing/extra migration ledger entry")
			}
			for i, v := range versions {
				if v != int64(i) {
					t.Fatal("non-contiguous migration ledger")
				}
			}
			var ready bool
			if e = pool.QueryRow(ctx, `SELECT to_regclass('c_comments.tasks') IS NOT NULL AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='c_posts.post_identity_bindings'::regclass AND conname='comment_binding_post_fk')`).Scan(&ready); e != nil || !ready {
				t.Fatal("comments schema absent")
			}
			if e = run("down"); e == nil {
				t.Fatal("permanent comment facts silently rolled back")
			}
			var current int
			if e = pool.QueryRow(ctx, `SELECT max(version_id) FROM public.goose_db_version WHERE is_applied`).Scan(&current); e != nil || current != 17 {
				t.Fatal("failed Down changed ledger")
			}
		})
	}
}
