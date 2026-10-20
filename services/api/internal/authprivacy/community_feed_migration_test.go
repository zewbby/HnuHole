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

func TestFeedGooseFreshAndUpgradePostgres(t *testing.T) {
	tool := os.Getenv("FEED_GOOSE")
	if tool == "" {
		t.Skip("owned Goose fixture absent")
	}
	for _, mode := range []string{"fresh", "upgrade", "interactions"} {
		t.Run(mode, func(t *testing.T) {
			ctx := context.Background()
			dsn := os.Getenv("FEED_" + strings.ToUpper(mode) + "_DSN")
			cfg, e := pgxpool.ParseConfig(dsn)
			if e != nil || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(os.Getenv("AUTHLAB_RUNTIME_TAG"), "hnuhole_authlab_feed_") || cfg.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
				t.Fatal("owned migration fixture required")
			}
			pool, e := pgxpool.NewWithConfig(ctx, cfg)
			if e != nil {
				t.Fatal(e)
			}
			defer pool.Close()
			var safe bool
			if e = pool.QueryRow(ctx, `SELECT current_database()=$1 AND current_user='hnuhole_c' AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AND inet_server_addr() IS NULL AND to_regnamespace('c_auth') IS NULL`, "hnuhole_feed_"+mode).Scan(&safe); e != nil || !safe {
				t.Fatal("fresh dedicated database required", e)
			}
			dir, e := filepath.Abs("../../migrations")
			if e != nil {
				t.Fatal(e)
			}
			run := func(command string, args ...string) error {
				return exec.Command(tool, append([]string{"-dir", dir, "postgres", dsn, command}, args...)...).Run()
			}
			var before string
			preserved := `SELECT md5(jsonb_build_object('posts',(SELECT jsonb_agg(to_jsonb(p)) FROM c_posts.posts p),'contents',(SELECT jsonb_agg(to_jsonb(x)) FROM c_posts.attempt_contents x),'tasks',(SELECT jsonb_agg(to_jsonb(t)) FROM c_posts.publication_tasks t),'channels',(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM public.channels c))::text)`
			if mode != "fresh" {
				base := "18"
				if mode == "interactions" {
					base = "19"
				}
				if e = run("up-to", base); e != nil {
					t.Fatal("main schema install", e)
				}
				mustExec(t, pool, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('d2c920f5-5563-452d-901c-be133844b0fa','001829','feed_upgrade',decode(repeat('11',32),'hex'),decode(repeat('22',16),'hex'),1)`)
				mustExec(t, pool, `BEGIN;
 INSERT INTO public.identity_account_state VALUES('d2c920f5-5563-452d-901c-be133844b0fa',1,'2026-10-19T00:00:00Z');
 INSERT INTO public.community_identities(identity_id,account_id,nickname,avatar,is_original,created_at) VALUES('11111111-1111-4111-8111-111111111111','d2c920f5-5563-452d-901c-be133844b0fa','UpgradeAuthor','default-v1',true,'2026-10-19T00:00:00Z');
 INSERT INTO c_posts.posts(post_id,owner_account_id,channel_id) VALUES('22222222-2222-4222-8222-222222222222','d2c920f5-5563-452d-901c-be133844b0fa','5f6f4f88-8f64-4bb2-9d34-000000000001');
 INSERT INTO c_posts.post_identity_bindings(account_id,post_id,identity_id,bound_at) VALUES('d2c920f5-5563-452d-901c-be133844b0fa','22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','2026-10-19T00:00:00Z');
 INSERT INTO c_posts.publication_tasks(task_id,post_id,owner_account_id,identity_id,channel_id,latest_attempt_version) VALUES('33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222','d2c920f5-5563-452d-901c-be133844b0fa','11111111-1111-4111-8111-111111111111','5f6f4f88-8f64-4bb2-9d34-000000000001',1);
 INSERT INTO c_posts.publication_attempts(task_id,version,accepted_stop_generation,state,accepted_at,acceptance_ordinal) VALUES('33333333-3333-4333-8333-333333333333',1,0,'ACCEPTED','2026-10-19T00:00:00Z',nextval('c_posts.acceptance_ordinal_seq'));
 INSERT INTO c_posts.attempt_contents(task_id,version,title,body,request_digest) VALUES('33333333-3333-4333-8333-333333333333',1,'UpgradeTitle','UpgradeBody',decode(repeat('11',32),'hex'));
 UPDATE c_posts.publication_attempts SET state='PUBLISHED',terminal_at='2026-10-19T00:00:00Z' WHERE task_id='33333333-3333-4333-8333-333333333333';
 UPDATE c_posts.posts SET visibility='PUBLISHED',published_attempt_version=1,published_at='2026-10-19T00:00:00Z',publication_ordinal=nextval('c_posts.publication_ordinal_seq') WHERE post_id='22222222-2222-4222-8222-222222222222';
 COMMIT;`)
				if mode == "interactions" {
					mustExec(t, pool, `INSERT INTO c_posts.post_view_totals VALUES('22222222-2222-4222-8222-222222222222',7);
 INSERT INTO c_posts.post_daily_views VALUES('d2c920f5-5563-452d-901c-be133844b0fa','22222222-2222-4222-8222-222222222222','2026-10-19');
 INSERT INTO c_posts.feed_preferences VALUES('d2c920f5-5563-452d-901c-be133844b0fa','{}',3)`)
				}
				if e = pool.QueryRow(ctx, preserved).Scan(&before); e != nil {
					t.Fatal(e)
				}
			}
			if e = run("up"); e != nil {
				t.Fatal("latest migration failed", e)
			}
			if count(t, pool, `SELECT count(*) FROM public.goose_db_version WHERE is_applied`) != 21 {
				t.Fatal("incomplete migration chain")
			}
			if e = checkFeedSchema(ctx, pool, true); e != nil {
				t.Fatal(e)
			}
			if e = checkPostInteractionSchema(ctx, pool, true); e != nil {
				t.Fatal(e)
			}
			if mode != "fresh" && count(t, pool, `SELECT count(*) FROM c_auth.accounts WHERE username='feed_upgrade'`) != 1 {
				t.Fatal("upgrade lost account")
			}
			if mode != "fresh" {
				var after string
				if e = pool.QueryRow(ctx, preserved).Scan(&after); e != nil || after != before {
					t.Fatal("upgrade changed existing posts/content/channels", e)
				}
				if mode == "upgrade" && count(t, pool, `SELECT count(*) FROM c_posts.post_view_totals`) != 0 {
					t.Fatal("historical views fabricated")
				}
				if mode == "interactions" && (count(t, pool, `SELECT view_count FROM c_posts.post_view_totals`) != 7 || count(t, pool, `SELECT count(*) FROM c_posts.post_daily_views`) != 1 || count(t, pool, `SELECT revision FROM c_posts.feed_preferences`) != 3) {
					t.Fatal("0020 changed feed facts")
				}
			}
			if count(t, pool, `SELECT count(*) FROM c_posts.post_likes`) != 0 || count(t, pool, `SELECT count(*) FROM c_posts.post_favorites`) != 0 {
				t.Fatal("fabricated historical interactions")
			}
			if e = run("down"); e == nil {
				t.Fatal("cumulative facts rolled back")
			}
			if count(t, pool, `SELECT max(version_id) FROM public.goose_db_version WHERE is_applied`) != 20 {
				t.Fatal("failed Down changed ledger")
			}
		})
	}
}
