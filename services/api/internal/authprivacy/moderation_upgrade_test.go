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

func TestModerationGooseUpgradeAndDownRefusalPostgres(t *testing.T) {
	tool := os.Getenv("MODERATION_GOOSE")
	if tool == "" {
		t.Skip("owned Goose tool not configured; raw SQL migration regression is separate")
	}
	dsn := os.Getenv("MODERATION_UPGRADE_DSN")
	config, e := pgxpool.ParseConfig(dsn)
	tag := os.Getenv("AUTHLAB_RUNTIME_TAG")
	if e != nil || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(tag, "hnuhole_authlab_") || config.ConnConfig.RuntimeParams["application_name"] != tag {
		t.Fatal("refusing unowned upgrade fixture")
	}
	ctx := context.Background()
	pool, e := pgxpool.NewWithConfig(ctx, config)
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	var db, user string
	var super bool
	var address *string
	if e = pool.QueryRow(ctx, `SELECT current_database(),current_user,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),inet_server_addr()::text`).Scan(&db, &user, &super, &address); e != nil || db != "hnuhole_moderation_upgrade" || user != "hnuhole_c" || super || address != nil {
		t.Fatal("refusing unknown upgrade database")
	}
	var empty bool
	if e = pool.QueryRow(ctx, `SELECT to_regnamespace('c_auth') IS NULL AND to_regclass('public.goose_db_version') IS NULL`).Scan(&empty); e != nil || !empty {
		t.Fatal("upgrade database is not new")
	}
	dir, e := filepath.Abs("../../migrations")
	if e != nil {
		t.Fatal(e)
	}
	run := func(command string, args ...string) error {
		argv := []string{"-dir", dir, "postgres", dsn, command}
		argv = append(argv, args...)
		out, e := exec.Command(tool, argv...).CombinedOutput()
		if e != nil && command != "down" {
			t.Logf("migration command failed: %s", out)
		}
		return e
	}
	if e = run("up-to", "14"); e != nil {
		t.Fatal("formal 0014 installation failed")
	}
	if _, e = pool.Exec(ctx, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('a811e9fa-7663-4182-88c4-465512194416','001527','upgrade_fixture',decode(repeat('11',32),'hex'),decode(repeat('22',16),'hex'),1)`); e != nil {
		t.Fatal(e)
	}
	if e = run("up"); e != nil {
		t.Fatal("formal 14 to 15 upgrade failed")
	}
	var version int
	if e = pool.QueryRow(ctx, `SELECT version_id FROM public.goose_db_version WHERE is_applied ORDER BY id DESC LIMIT 1`).Scan(&version); e != nil || version != 15 {
		t.Fatal("unexpected live migration order", e, version)
	}
	var preserved bool
	if e = pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_moderation.platform_numbers WHERE number='001527') AND EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='c_posts.posts'::regclass AND attname='moderation_hidden') AND to_regclass('public.comments') IS NULL`).Scan(&preserved); e != nil || !preserved {
		t.Fatal("upgrade lost number or requires comments", e)
	}
	bootstrap, e := filepath.Abs("../../../../infra/postgres/bootstrap-moderation-admin.sql")
	if e != nil {
		t.Fatal(e)
	}
	for i := 0; i < 2; i++ {
		_, e = exec.Command("psql", "-X", "-v", "ON_ERROR_STOP=1", "-v", "platform_number=001527", dsn, "-f", bootstrap).CombinedOutput()
		if (i == 0 && e != nil) || (i == 1 && e == nil) {
			t.Fatal("first admin bootstrap boundary failed", i)
		}
	}
	var bootstraps int
	if e = pool.QueryRow(ctx, `SELECT count(*) FROM c_moderation.audit WHERE action='BOOTSTRAP_ADMIN'`).Scan(&bootstraps); e != nil || bootstraps != 1 {
		t.Fatal("bootstrap audit missing or duplicated", e)
	}
	if e = run("down"); e == nil {
		t.Fatal("irreversible migration allowed Goose ledger rollback")
	}
	if e = pool.QueryRow(ctx, `SELECT version_id FROM public.goose_db_version WHERE is_applied ORDER BY id DESC LIMIT 1`).Scan(&version); e != nil || version != 15 {
		t.Fatal("failed Down changed migration ledger", e)
	}
}
