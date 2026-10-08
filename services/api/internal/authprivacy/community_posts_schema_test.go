package authprivacy

import (
	"context"
	"errors"
	"os"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type postSchemaFixture struct {
	account, identity, post, task uuid.UUID
	at                            time.Time
	bearer                        [32]byte
}

func insertPostSchemaFixture(t *testing.T, l *lab, name string) postSchemaFixture {
	t.Helper()
	owner := sessionTestAccount(t, l, name)
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "测试身份")
	f := postSchemaFixture{account: owner.AccountID, identity: identity.IdentityID, post: uuid.New(), task: uuid.New(), at: time.Now().UTC().Truncate(time.Microsecond), bearer: owner.SessionToken}
	ctx := context.Background()
	tx, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	for _, command := range []struct {
		sql  string
		args []any
	}{
		{`INSERT INTO c_posts.posts(post_id,owner_account_id,channel_id) VALUES($1,$2,'5f6f4f88-8f64-4bb2-9d34-000000000001')`, []any{f.post, f.account}},
		{`INSERT INTO c_posts.post_identity_bindings(account_id,post_id,identity_id,bound_at) VALUES($1,$2,$3,$4)`, []any{f.account, f.post, f.identity, f.at}},
		{`INSERT INTO c_posts.publication_tasks(task_id,post_id,owner_account_id,identity_id,channel_id,latest_attempt_version) VALUES($1,$2,$3,$4,'5f6f4f88-8f64-4bb2-9d34-000000000001',1)`, []any{f.task, f.post, f.account, f.identity}},
		{`INSERT INTO c_posts.publication_attempts(task_id,version,accepted_stop_generation,state,accepted_at,acceptance_ordinal) VALUES($1,1,0,'ACCEPTED',$2,nextval('c_posts.acceptance_ordinal_seq'))`, []any{f.task, f.at}},
		{`INSERT INTO c_posts.attempt_contents(task_id,version,title,body,request_digest) VALUES($1,1,'标题','正文',decode(repeat('11',32),'hex'))`, []any{f.task}},
		{`INSERT INTO c_posts.command_receipts(key_digest,owner_account_id,operation,intent_fingerprint,outcome,task_id,post_id,attempt_version,task_state,committed_at) VALUES(decode(replace($1::text,'-','')||replace($1::text,'-',''),'hex'),$2,'CREATE',decode(repeat('22',32),'hex'),'ACCEPTED',$1::uuid,$3,1,'ACCEPTED',$4)`, []any{f.task, f.account, f.post, f.at}},
	} {
		if _, err = tx.Exec(ctx, command.sql, command.args...); err != nil {
			t.Fatal(err)
		}
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	return f
}

func expectPostSQLRejected(t *testing.T, l *lab, sql string, args ...any) {
	t.Helper()
	ctx := context.Background()
	tx, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, sql, args...)
	if err == nil {
		err = tx.Commit(ctx)
	}
	var postgresError *pgconn.PgError
	if !errors.As(err, &postgresError) || (postgresError.Code != "23514" && postgresError.Code != "23503" && postgresError.Code != "23505") {
		t.Fatalf("expected constraint rejection, got %v", err)
	}
}

func TestPostSchemaPermanentFactsAndTextGuardsPostgres(t *testing.T) {
	l := newLab(t)
	f := insertPostSchemaFixture(t, l, "posts_schema_guard")
	for _, sql := range []string{
		`UPDATE c_posts.post_identity_bindings SET bound_at=bound_at+interval '1 second' WHERE post_id=$1`,
		`DELETE FROM c_posts.post_identity_bindings WHERE post_id=$1`,
		`UPDATE c_posts.command_receipts SET outcome='COMMITTED' WHERE post_id=$1`,
		`DELETE FROM c_posts.command_receipts WHERE post_id=$1`,
		`UPDATE c_posts.posts SET publication_ordinal=1,published_at=now(),published_attempt_version=1,visibility='PUBLISHED' WHERE post_id=$1`,
	} {
		expectPostSQLRejected(t, l, sql, f.post)
	}
	expectPostSQLRejected(t, l, `UPDATE c_posts.attempt_contents SET title='被替换' WHERE task_id=$1`, f.task)
	expectPostSQLRejected(t, l, `UPDATE c_posts.publication_attempts SET accepted_stop_generation=1 WHERE task_id=$1`, f.task)
	expectPostSQLRejected(t, l, `UPDATE c_posts.publication_attempts SET state='FAILED',failure_code='PUBLICATION_FAILED',terminal_at=NULL WHERE task_id=$1`, f.task)
	expectPostSQLRejected(t, l, `UPDATE c_posts.publication_attempts SET state='CANCELLED',terminal_at=NULL WHERE task_id=$1`, f.task)
	expectPostSQLRejected(t, l, `UPDATE c_posts.publication_tasks SET latest_attempt_version=2 WHERE task_id=$1`, f.task)
	expectPostSQLRejected(t, l, `UPDATE c_posts.account_publication_control SET stop_generation=1 WHERE account_id=$1`, f.account)
	mustExec(t, l.cp, `UPDATE c_posts.attempt_contents SET title=NULL,body=NULL,erased_at=$2 WHERE task_id=$1`, f.task, f.at)
	expectPostSQLRejected(t, l, `UPDATE c_posts.attempt_contents SET title='恢复',body='正文',erased_at=NULL WHERE task_id=$1`, f.task)
}

func TestPostSchemaFixedOwnershipAndTerminalStatePostgres(t *testing.T) {
	l := newLab(t)
	f := insertPostSchemaFixture(t, l, "posts_schema_owner")
	other := sessionTestAccount(t, l, "posts_schema_other")
	otherIdentity := identityChange(t, l.c, other.SessionToken, "CREATE", uuid.Nil, "另一身份")
	expectPostSQLRejected(t, l, `UPDATE c_posts.publication_tasks SET identity_id=$2 WHERE task_id=$1`, f.task, otherIdentity.IdentityID)
	expectPostSQLRejected(t, l, `INSERT INTO c_posts.post_identity_bindings(account_id,post_id,identity_id,bound_at) VALUES($1,$2,$3,$4)`, other.AccountID, f.post, otherIdentity.IdentityID, f.at)
	mustExec(t, l.cp, `UPDATE c_posts.publication_attempts SET state='FAILED',terminal_at=$2,failure_code='PUBLICATION_FAILED' WHERE task_id=$1`, f.task, f.at)
	expectPostSQLRejected(t, l, `UPDATE c_posts.publication_attempts SET state='ACCEPTED',terminal_at=NULL,failure_code=NULL WHERE task_id=$1`, f.task)
	expectPostSQLRejected(t, l, `UPDATE c_posts.publication_attempts SET terminal_at=terminal_at+interval '1 second' WHERE task_id=$1`, f.task)
}

func TestPostSchemaLegacyBackfillAndStableLabelsPostgres(t *testing.T) {
	l := newLab(t)
	f := insertPostSchemaFixture(t, l, "posts_schema_label")
	// 仅重建本 fixture 私有 schema，保留历史身份来证明升级回填。
	mustExec(t, l.cp, `DROP SCHEMA c_posts CASCADE`)
	source, err := os.ReadFile("../../migrations/0013_community_text_posts.sql")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, strings.SplitN(string(source), "-- +goose Down", 2)[0])
	var label string
	if err = l.cp.QueryRow(context.Background(), `SELECT short_code FROM c_posts.identity_public_labels WHERE identity_id=$1`, f.identity).Scan(&label); err != nil || !regexp.MustCompile(`^[A-Z2-7]{12}$`).MatchString(label) {
		t.Fatalf("historical label was not independently backfilled: %v", err)
	}
	expectPostSQLRejected(t, l, `UPDATE c_posts.identity_public_labels SET short_code='AAAAAAAAAAAA' WHERE identity_id=$1`, f.identity)
	expectPostSQLRejected(t, l, `DELETE FROM c_posts.identity_public_labels WHERE identity_id=$1`, f.identity)
	newIdentity := identityChange(t, l.c, f.bearer, "CREATE", uuid.Nil, "新身份")
	if count(t, l.cp, `SELECT count(*) FROM c_posts.identity_public_labels WHERE identity_id=$1 AND short_code<>$2 AND short_code ~ '^[A-Z2-7]{12}$'`, newIdentity.IdentityID, label) != 1 {
		t.Fatal("new identity did not atomically allocate a distinct stable label")
	}
}

func TestPostSchemaStartupRejectsMissingHookPostgres(t *testing.T) {
	l := newLab(t)
	if err := l.c.CheckPostSchema(context.Background()); err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, `ALTER TABLE c_auth.accounts DISABLE TRIGGER post_account_stop_hook`)
	if err := l.c.CheckPostSchema(context.Background()); !errors.Is(err, errPostSchema) {
		t.Fatalf("missing stop hook was accepted: %v", err)
	}
}

func TestPostSchemaLifecycleHookBlocksOldWriterPostgres(t *testing.T) {
	for _, cause := range []string{"REQUEST_CLOSURE", "MUTE", "BAN", "ACCOUNT_CLOSED"} {
		t.Run(cause, func(t *testing.T) {
			l := newLab(t)
			f := insertPostSchemaFixture(t, l, "posts_old_writer")
			statement := `UPDATE c_auth.accounts SET state='PENDING_CLOSE' WHERE account_id=$1`
			switch cause {
			case "MUTE":
				statement = `UPDATE c_auth.account_restrictions SET mute_state='MUTED',version=version+1 WHERE account_id=$1`
			case "BAN":
				statement = `UPDATE c_auth.account_restrictions SET ban_state='BANNED',version=version+1 WHERE account_id=$1`
			case "ACCOUNT_CLOSED":
				// CLOSED 的 identity 约束由本 fixture 完整清理身份，不省略已存在边界。
				statement = `UPDATE c_auth.accounts SET state='CLOSED',username=NULL,password_hash=NULL,password_salt=NULL,password_params_version=NULL WHERE account_id=$1`
			}
			mutate := func(withHook bool) error {
				ctx := context.Background()
				tx, err := l.cp.Begin(ctx)
				if err != nil {
					return err
				}
				defer tx.Rollback(ctx)
				if withHook {
					if _, err = tx.Exec(ctx, `UPDATE c_posts.account_publication_control SET stop_generation=stop_generation+1 WHERE account_id=$1`, f.account); err != nil {
						return err
					}
					if _, err = tx.Exec(ctx, `INSERT INTO c_posts.publication_stop_events(account_id,generation,stopped_at,cause) VALUES($1,1,$2,$3)`, f.account, f.at, cause); err != nil {
						return err
					}
				}
				if cause == "ACCOUNT_CLOSED" {
					if withHook {
						if _, err = tx.Exec(ctx, `UPDATE c_posts.publication_attempts SET state='FAILED',terminal_at=$2,failure_code='PUBLISHING_STOPPED' WHERE task_id=$1`, f.task, f.at); err != nil {
							return err
						}
						if _, err = tx.Exec(ctx, `UPDATE c_posts.publication_tasks SET owner_visible=false WHERE task_id=$1`, f.task); err != nil {
							return err
						}
						if _, err = tx.Exec(ctx, `INSERT INTO c_posts.payload_cleanup(task_id,version,cause,requested_at,due_at,state) VALUES($1,1,'ACCOUNT_CLOSED',$2,$2,'PENDING')`, f.task, f.at); err != nil {
							return err
						}
					}
					if _, err = tx.Exec(ctx, `UPDATE public.community_identities SET nickname=NULL,avatar=NULL,last_renamed_at=NULL,deleted_at=$2 WHERE account_id=$1 AND deleted_at IS NULL`, f.account, f.at); err != nil {
						return err
					}
				}
				if _, err = tx.Exec(ctx, statement, f.account); err != nil {
					return err
				}
				return tx.Commit(ctx)
			}
			var postgresError *pgconn.PgError
			if err := mutate(false); !errors.As(err, &postgresError) || postgresError.Code != "23514" {
				t.Fatalf("old writer lifecycle mutation was not rejected: %v", err)
			}
			if err := mutate(true); err != nil {
				t.Fatalf("same-transaction stop event failed: %v", err)
			}
			expectPostSQLRejected(t, l, `DELETE FROM c_posts.publication_stop_events WHERE account_id=$1`, f.account)
		})
	}
}

func TestPostSchemaRestrictedRuntimePrivilegesPostgres(t *testing.T) {
	dsn := os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN")
	if dsn == "" {
		t.Skip("isolated posts runtime DSN absent; restricted-role checks not executed")
	}
	l := newLab(t)
	f := insertPostSchemaFixture(t, l, "posts_runtime_role")
	// 此表仅使正式 grants 的历史 Goose SELECT 在 raw migration fixture 中存在。
	// 本检查不把它当作真实 Goose 升级证据。
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	source, err := os.ReadFile("../../../../infra/postgres/grant-community.sql")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, string(source))
	config, err := pgxpool.ParseConfig(dsn)
	if err != nil || config.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
		t.Fatal("restricted-role fixture DSN marker absent")
	}
	runtime, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	var database, user string
	var address *string
	if err = runtime.QueryRow(context.Background(), `SELECT current_database(),current_user,inet_server_addr()::text`).Scan(&database, &user, &address); err != nil || database != "hnuhole_c" || user != "hnuhole_c_runtime" || address != nil {
		t.Fatal("restricted-role checks require this isolated private-socket runtime database")
	}
	if err = checkPostSchema(context.Background(), runtime); err != nil {
		t.Fatal(err)
	}
	// 将真实受限 pool 放入同一个实验 Gate，验证身份创建的标签 trigger
	// 不依赖 owner 权限，也不会留下一条没有标签的活动身份。
	runtimeCommunity := *l.c
	runtimeCommunity.pool = runtime
	runtimeIdentity := identityChange(t, &runtimeCommunity, f.bearer, "CREATE", uuid.Nil, "受限身份")
	if count(t, l.cp, `SELECT count(*) FROM c_posts.identity_public_labels WHERE identity_id=$1`, runtimeIdentity.IdentityID) != 1 {
		t.Fatal("restricted runtime identity creation missed its atomic label")
	}
	for _, sql := range []string{
		`DELETE FROM c_posts.post_identity_bindings`,
		`DELETE FROM c_posts.command_receipts`,
		`UPDATE c_posts.publication_attempts SET accepted_stop_generation=1`,
		`UPDATE c_posts.command_receipts SET intent_fingerprint=decode(repeat('11',32),'hex')`,
		`UPDATE c_posts.identity_public_labels SET short_code='AAAAAAAAAAAA'`,
		`TRUNCATE c_posts.posts CASCADE`,
		`CREATE TABLE c_posts.runtime_forbidden(value integer)`,
	} {
		_, err = runtime.Exec(context.Background(), sql)
		var postgresError *pgconn.PgError
		if !errors.As(err, &postgresError) || postgresError.Code != "42501" {
			t.Fatalf("runtime must lack this SQL privilege, got %v", err)
		}
	}
	_, err = runtime.Exec(context.Background(), `UPDATE c_posts.attempt_contents SET body='改写' WHERE task_id=$1`, f.task)
	var postgresError *pgconn.PgError
	if !errors.As(err, &postgresError) || postgresError.Code != "23514" {
		t.Fatalf("runtime content column grant bypassed erase-only guard: %v", err)
	}
	// 账号关闭触发器需要查询 c_posts，缺少 SELECT 会在授权事务中直接失败。
	// 原文字按约定整份擦除则能够通过列权限与 guard。
	if _, err = runtime.Exec(context.Background(), `UPDATE c_posts.attempt_contents SET title=NULL,body=NULL,erased_at=$2 WHERE task_id=$1`, f.task, f.at); err != nil {
		t.Fatalf("precise runtime erasure failed: %v", err)
	}
	var recoveryCanRead, businessCanRead bool
	if err = l.cp.QueryRow(context.Background(), `SELECT has_schema_privilege('hnuhole_c_recovery','c_posts','USAGE'),has_schema_privilege('hnuhole_business','c_posts','USAGE')`).Scan(&recoveryCanRead, &businessCanRead); err != nil || recoveryCanRead || businessCanRead {
		t.Fatal("posts data became available to recovery or business roles")
	}
	mustExec(t, l.cp, `GRANT UPDATE(accepted_stop_generation) ON c_posts.publication_attempts TO hnuhole_c_runtime`)
	if err = checkPostSchema(context.Background(), runtime); !errors.Is(err, errPostSchema) {
		t.Fatalf("overbroad immutable-input UPDATE was accepted at startup: %v", err)
	}
	mustExec(t, l.cp, `REVOKE UPDATE(accepted_stop_generation) ON c_posts.publication_attempts FROM hnuhole_c_runtime`)
	for _, privilege := range []struct {
		revoke, grant string
	}{
		{`REVOKE INSERT ON c_posts.command_receipts FROM hnuhole_c_runtime`, `GRANT INSERT ON c_posts.command_receipts TO hnuhole_c_runtime`},
		{`REVOKE UPDATE(terminal_at) ON c_posts.publication_attempts FROM hnuhole_c_runtime`, `GRANT UPDATE(terminal_at) ON c_posts.publication_attempts TO hnuhole_c_runtime`},
	} {
		mustExec(t, l.cp, privilege.revoke)
		if err = checkPostSchema(context.Background(), runtime); !errors.Is(err, errPostSchema) {
			t.Fatalf("missing required runtime DML was accepted at startup: %v", err)
		}
		mustExec(t, l.cp, privilege.grant)
	}
	if err = checkPostSchema(context.Background(), runtime); err != nil {
		t.Fatalf("restored precise runtime privileges failed: %v", err)
	}
}

func TestPostSchemaPartyInventoryAndPrivateColumnsPostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	expected := []string{"account_publication_control", "attempt_contents", "command_receipts", "identity_public_labels", "payload_cleanup", "post_identity_bindings", "posts", "protocol_keys", "publication_attempts", "publication_stop_events", "publication_tasks", "schema_meta"}
	rows, err := l.cp.Query(ctx, `SELECT c.relname,c.relkind::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='c_posts' AND c.relkind IN ('r','p','v','m','f') ORDER BY c.relname`)
	if err != nil {
		t.Fatal(err)
	}
	var actual []string
	for rows.Next() {
		var name, kind string
		if err = rows.Scan(&name, &kind); err != nil {
			break
		}
		if kind != "r" {
			t.Fatalf("posts schema acquired a view/foreign/partitioned relation: %s", name)
		}
		actual = append(actual, name)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	sort.Strings(expected)
	if err != nil || strings.Join(expected, "\n") != strings.Join(actual, "\n") {
		t.Fatalf("posts relation inventory drift: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM information_schema.columns WHERE table_schema IN ('c_posts','c_auth','public') AND (column_name ILIKE '%email%' OR column_name ILIKE '%otp%' OR column_name ILIKE '%mail%')`) != 0 {
		t.Fatal("community acquired verifier email/OTP/mail storage")
	}
	if count(t, l.cp, `SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='c_posts' AND p.prosecdef`) != 0 || count(t, l.cp, `SELECT count(*) FROM pg_foreign_server`) != 0 {
		t.Fatal("posts acquired a privileged function or foreign-party bridge")
	}
	if count(t, l.vp, `SELECT count(*) FROM pg_namespace WHERE nspname='c_posts'`) != 0 {
		t.Fatal("verifier database acquired community posts schema")
	}
	if count(t, l.vp, `SELECT count(*) FROM information_schema.columns WHERE table_schema='v_auth' AND (column_name ILIKE '%account%' OR column_name ILIKE '%identity%' OR column_name ILIKE '%community%' OR column_name ILIKE '%post%')`) != 0 {
		t.Fatal("verifier acquired community account/identity/post locators")
	}
}

func TestPostSchemaProtocolKeyBindingImmutablePostgres(t *testing.T) {
	l := newLab(t)
	mustExec(t, l.cp, `INSERT INTO c_posts.protocol_keys(singleton_id,version,command_tag,fingerprint_tag) VALUES(1,1,decode(repeat('11',32),'hex'),decode(repeat('22',32),'hex'))`)
	expectPostSQLRejected(t, l, `UPDATE c_posts.protocol_keys SET command_tag=decode(repeat('33',32),'hex')`)
	expectPostSQLRejected(t, l, `UPDATE c_posts.protocol_keys SET fingerprint_tag=decode(repeat('44',32),'hex')`)
	expectPostSQLRejected(t, l, `DELETE FROM c_posts.protocol_keys`)
	expectPostSQLRejected(t, l, `INSERT INTO c_posts.protocol_keys(singleton_id,version,command_tag,fingerprint_tag) VALUES(1,1,decode(repeat('11',32),'hex'),decode(repeat('22',32),'hex'))`)
}

func TestPostSchemaIdentityDeletionRequiresPrivateTaskHookPostgres(t *testing.T) {
	l := newLab(t)
	f := insertPostSchemaFixture(t, l, "posts_identity_hook")
	identityChange(t, l.c, f.bearer, "CREATE", uuid.Nil, "保留身份")
	expectPostSQLRejected(t, l, `UPDATE public.community_identities SET nickname=NULL,avatar=NULL,last_renamed_at=NULL,deleted_at=$2 WHERE identity_id=$1`, f.identity, f.at)
	ctx := context.Background()
	tx, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	for _, command := range []struct {
		sql  string
		args []any
	}{
		{`UPDATE c_posts.publication_attempts SET state='FAILED',terminal_at=$2,failure_code='IDENTITY_INACTIVE' WHERE task_id=$1`, []any{f.task, f.at}},
		{`UPDATE c_posts.publication_tasks SET owner_visible=false WHERE task_id=$1`, []any{f.task}},
		{`INSERT INTO c_posts.payload_cleanup(task_id,version,cause,requested_at,due_at,state) VALUES($1,1,'IDENTITY_DELETED',$2,$2,'PENDING')`, []any{f.task, f.at}},
		{`UPDATE public.community_identities SET nickname=NULL,avatar=NULL,last_renamed_at=NULL,deleted_at=$2 WHERE identity_id=$1`, []any{f.identity, f.at}},
	} {
		if _, err = tx.Exec(ctx, command.sql, command.args...); err != nil {
			t.Fatal(err)
		}
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.publication_attempts WHERE task_id=$1 AND state='FAILED' AND terminal_at=$2`, f.task, f.at) != 1 {
		t.Fatal("identity deletion failed to preserve its authoritative terminal time")
	}
}
