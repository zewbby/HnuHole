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
				if err = run("up-to", "22"); err != nil {
					t.Fatal("0022 baseline", err)
				}
				mustExec(t, pool, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('d2c920f5-5563-452d-901c-be133844b0fa','001829','dm_upgrade',decode(repeat('11',32),'hex'),decode(repeat('22',16),'hex'),1); INSERT INTO c_posts.feed_preferences VALUES('d2c920f5-5563-452d-901c-be133844b0fa','{}',3)`)
				// A real P1 pending message and immutable receipt survive P2.
				mustExec(t, pool, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('d2c920f5-5563-452d-901c-be133844b0fb','001830','dm_upgrade_peer',decode(repeat('11',32),'hex'),decode(repeat('22',16),'hex'),1);
                 INSERT INTO public.identity_account_state VALUES('d2c920f5-5563-452d-901c-be133844b0fa',1,now()),('d2c920f5-5563-452d-901c-be133844b0fb',1,now());
                 INSERT INTO public.community_identities(identity_id,account_id,nickname,avatar,is_original,created_at) VALUES('11111111-1111-4111-8111-111111111111','d2c920f5-5563-452d-901c-be133844b0fa','upgrade one','default-v1',true,now()),('22222222-2222-4222-8222-222222222222','d2c920f5-5563-452d-901c-be133844b0fb','upgrade two','default-v1',true,now());
                 INSERT INTO c_posts.posts(post_id,owner_account_id,channel_id) SELECT '33333333-3333-4333-8333-333333333333','d2c920f5-5563-452d-901c-be133844b0fa',id FROM public.channels ORDER BY id LIMIT 1;
                 INSERT INTO c_posts.post_identity_bindings VALUES('d2c920f5-5563-452d-901c-be133844b0fa','33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111',now());
                 INSERT INTO c_posts.publication_tasks(task_id,post_id,owner_account_id,identity_id,channel_id,latest_attempt_version) SELECT '77777777-7777-4777-8777-777777777777',post_id,owner_account_id,'11111111-1111-4111-8111-111111111111',channel_id,1 FROM c_posts.posts;
                 INSERT INTO c_posts.publication_attempts(task_id,version,accepted_stop_generation,state,accepted_at,acceptance_ordinal) VALUES('77777777-7777-4777-8777-777777777777',1,0,'ACCEPTED',now(),1);
                 INSERT INTO c_posts.attempt_contents(task_id,version,title,body,request_digest) VALUES('77777777-7777-4777-8777-777777777777',1,'upgrade source','upgrade content',decode(repeat('cd',32),'hex'));
                 INSERT INTO c_dm.conversations VALUES('44444444-4444-4444-8444-444444444444','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333',1,true,false);
                 INSERT INTO c_dm.messages(message_id,conversation_id,sequence,sender,recipient,body,accepted_at) VALUES('55555555-5555-4555-8555-555555555555','44444444-4444-4444-8444-444444444444',1,'11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','survives P2 upgrade',now());
                 INSERT INTO c_dm.commands(owner_account,command_id,fingerprint,attempt,state,message_id,conversation_id,sequence,accepted_at) SELECT 'd2c920f5-5563-452d-901c-be133844b0fa','66666666-6666-4666-8666-666666666666',decode(repeat('ab',32),'hex'),1,'SENT',message_id,conversation_id,sequence,accepted_at FROM c_dm.messages;`)
				if err = pool.QueryRow(ctx, snapshot).Scan(&before); err != nil {
					t.Fatal(err)
				}
			}
			if err = run("up"); err != nil {
				t.Fatal("0024 upgrade", err)
			}
			if count(t, pool, `SELECT count(*) FROM public.goose_db_version WHERE is_applied`) != 29 || count(t, pool, `SELECT max(version_id) FROM public.goose_db_version WHERE is_applied`) != 28 {
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
			if mode == "fresh" {
				if count(t, pool, `SELECT count(*) FROM c_dm.messages`) != 0 || count(t, pool, `SELECT count(*) FROM c_dm.commands`) != 0 {
					t.Fatal("fabricated DM history")
				}
			} else {
				if count(t, pool, `SELECT count(*) FROM c_dm.messages WHERE body='survives P2 upgrade' AND NOT acknowledged AND NOT read AND NOT retracted AND kind='TEXT'`) != 1 || count(t, pool, `SELECT count(*) FROM c_dm.commands WHERE state='SENT' AND attempt=1`) != 1 || count(t, pool, `SELECT count(*) FROM c_dm.conversations WHERE low_sent AND NOT high_sent AND sequence=1`) != 1 {
					t.Fatal("P1 pending text, receipt or first quota changed")
				}
			}
			if err = run("down"); err == nil {
				t.Fatal("destructive rollback accepted")
			}
			if count(t, pool, `SELECT max(version_id) FROM public.goose_db_version WHERE is_applied`) != 28 {
				t.Fatal("failed Down changed ledger")
			}
		})
	}
}
