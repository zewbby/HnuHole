package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func moderationLifecycleRuntime(t *testing.T, l *lab) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN")
	if dsn == "" {
		t.Skip("isolated posts runtime DSN absent; lifecycle privilege test not executed")
	}
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	grant, err := os.ReadFile("../../../../infra/postgres/grant-community.sql")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, string(grant))
	config, err := pgxpool.ParseConfig(dsn)
	if err != nil || config.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
		t.Fatal("runtime DSN requires this isolated fixture marker")
	}
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	var database, user string
	var address *string
	if err = pool.QueryRow(context.Background(), `SELECT current_database(),current_user,inet_server_addr()::text`).Scan(&database, &user, &address); err != nil || database != "hnuhole_c" || user != "hnuhole_c_runtime" || address != nil {
		t.Fatal("runtime must use this private-socket disposable C database")
	}
	return pool
}

func TestPostSchemaModerationCleanupPrivilegesWithoutFeaturePostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	config := enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "mod_cleanup_runtime")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "生命周期")
	created := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, identity.IdentityID))
	postTestPublish(t, l)
	caseID := uuid.New()
	mustExec(t, l.cp, `INSERT INTO c_moderation.cases(case_id,post_id,target_account_id,target_identity_id,reason,snapshot_digest,evidence,created_at) VALUES($1,$2,$3,$4,'OTHER','synthetic','{}',clock_timestamp())`, caseID, created.PostID, owner.AccountID, identity.IdentityID)
	runtime := moderationLifecycleRuntime(t, l)
	if err := checkPostSchema(ctx, runtime); err != nil {
		t.Fatal(err)
	}
	copy := *l.c
	copy.pool = runtime
	runtimeCommunity, err := copy.WithPosts(ctx, config)
	enabled, hasFeature := any(runtimeCommunity).(interface{ ModerationEnabled() bool })
	if err != nil || hasFeature && enabled.ModerationEnabled() {
		t.Fatalf("old posts config enabled moderation or rejected cleanup grants: %v", err)
	}
	for _, table := range []string{"cases", "reports", "sanctions", "appeals", "commands", "roles", "access_sessions"} {
		var allowed bool
		if err = runtime.QueryRow(ctx, `SELECT has_table_privilege(current_user,'c_moderation.'||$1,'INSERT')`, table).Scan(&allowed); err != nil || allowed {
			t.Fatalf("cleanup grants opened %s creation: %v", table, err)
		}
	}
	if _, err = runtimeCommunity.ExecutePostCommand(ctx, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: created.PostID}); err != nil {
		t.Fatalf("old runtime delete failed after 0015: %v", err)
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_moderation.cases WHERE case_id=$1 AND state='ENDED' AND outcome='TARGET_DELETED'`, caseID); n != 1 {
		t.Fatal("old delete did not end pending case")
	}
	for _, access := range []struct{ revoke, grant string }{
		{`REVOKE INSERT ON c_moderation.notifications FROM hnuhole_c_runtime`, `GRANT INSERT ON c_moderation.notifications TO hnuhole_c_runtime`},
		{`REVOKE UPDATE(version) ON c_moderation.cases FROM hnuhole_c_runtime`, `GRANT UPDATE(version) ON c_moderation.cases TO hnuhole_c_runtime`},
		{`REVOKE DELETE ON c_moderation.access_sessions FROM hnuhole_c_runtime`, `GRANT DELETE ON c_moderation.access_sessions TO hnuhole_c_runtime`},
		{`REVOKE SELECT(account_id) ON c_moderation.roles FROM hnuhole_c_runtime`, `GRANT SELECT(account_id) ON c_moderation.roles TO hnuhole_c_runtime`},
	} {
		mustExec(t, l.cp, access.revoke)
		if err = checkPostSchema(ctx, runtime); !errors.Is(err, errPostSchema) {
			t.Fatalf("startup accepted missing cleanup privilege: %s: %v", access.revoke, err)
		}
		mustExec(t, l.cp, access.grant)
	}
	mustExec(t, l.cp, `ALTER TABLE c_posts.posts DISABLE TRIGGER moderation_post_deleted`)
	if err = checkPostSchema(ctx, runtime); !errors.Is(err, errPostSchema) {
		t.Fatalf("disabled moderation lifecycle hook passed startup: %v", err)
	}
	mustExec(t, l.cp, `ALTER TABLE c_posts.posts ENABLE TRIGGER moderation_post_deleted`)
	if err = checkPostSchema(ctx, runtime); err != nil {
		t.Fatal(err)
	}
}

func TestPostSchemaModerationAccountClosureWithoutFeaturePostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	config := enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "mod_cleanup_closure")
	identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "清理账号")
	runtime := moderationLifecycleRuntime(t, l)
	copy := *l.c
	copy.pool = runtime
	runtimeCommunity, err := copy.WithPosts(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	// Seed artifacts as migration owner; no moderation creation grant is given
	// to the old runtime. The final close must delete them under its own role.
	token := sha256.Sum256([]byte("synthetic limited session"))
	mustExec(t, l.cp, `INSERT INTO c_moderation.access_sessions(token_digest,account_id,credential_version,session_generation,authorization_generation,expires_at) VALUES($1,$2,1,1,1,clock_timestamp()+interval '1 day')`, token[:], owner.AccountID)
	mustExec(t, l.cp, `INSERT INTO c_moderation.roles(account_id,role) VALUES($1,'REVIEWER')`, owner.AccountID)
	mustExec(t, l.cp, `INSERT INTO c_moderation.notifications(notification_id,event_id,account_id,kind,state,title,body,route_name,resource_id,created_at) VALUES($1,'synthetic:closure',$2,'SANCTION','ACTIVE','synthetic','','SANCTION',$1,clock_timestamp())`, uuid.New(), owner.AccountID)
	request, _ := closureTestRequest(t, owner.SessionToken)
	accepted, err := runtimeCommunity.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	if n, e := runtimeCommunity.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
		t.Fatalf("old runtime closure failed after 0015: %d %v", n, e)
	}
	for _, table := range []string{"access_sessions", "roles", "notifications"} {
		if n := count(t, l.cp, `SELECT count(*) FROM c_moderation.`+table+` WHERE account_id=$1`, owner.AccountID); n != 0 {
			t.Fatalf("closure retained %s", table)
		}
	}
}

func TestPostSchemaPreModerationNeedsNoCleanupGrantPostgres(t *testing.T) {
	l := newLab(t)
	// Remove this fixture's moderation additions, including the optional 0018
	// comment projection. A half-removed 0018 must still fail startup; this case
	// models the pre-moderation installation, not a broken forward migration.
	mustExec(t, l.cp, `DROP SCHEMA c_moderation CASCADE`)
	if err := CheckModerationLifecycleSchema(context.Background(), l.cp); err == nil {
		t.Fatal("partially removed 0018 passed startup")
	}
	mustExec(t, l.cp, `ALTER TABLE c_comments.tasks DROP COLUMN moderation_hidden`)
	mustExec(t, l.cp, `ALTER TABLE c_posts.posts DROP COLUMN moderation_hidden`)
	mustExec(t, l.cp, `ALTER TABLE public.community_identities DROP COLUMN moderation_rename_required`)
	runtime := moderationLifecycleRuntime(t, l)
	if err := checkPostSchema(context.Background(), runtime); err != nil {
		t.Fatalf("0014 acquired a moderation dependency: %v", err)
	}
}

func TestModerationForcedRenameConsumedWithoutFeaturePostgres(t *testing.T) {
	l := newLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "mod_rename_disabled")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "原昵称")
	identityChange(t, l.c, owner.SessionToken, "RENAME", identity.IdentityID, "一次改名")
	mustExec(t, l.cp, `UPDATE public.community_identities SET nickname='待整改123456',moderation_rename_required=true WHERE identity_id=$1`, identity.IdentityID)
	if enabled, ok := any(l.c).(interface{ ModerationEnabled() bool }); ok && enabled.ModerationEnabled() {
		t.Fatal("fixture unexpectedly enabled moderation")
	}
	identityChange(t, l.c, owner.SessionToken, "RENAME", identity.IdentityID, "完成整改")
	if n := count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE identity_id=$1 AND NOT moderation_rename_required`, identity.IdentityID); n != 1 {
		t.Fatal("disabled feature preserved the forced rename exemption")
	}
	result, err := l.c.ChangeOwnIdentity(ctx, IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: "RENAME", IdentityID: identity.IdentityID, Nickname: "再次绕过"})
	if !identityRejected(result, err, "IDENTITY_RENAME_COOLDOWN") {
		t.Fatalf("one-use exemption allowed repeated rename: %+v %v", result, err)
	}
	// The original 0014 shape retains its unchanged rename SQL and cooldown.
	mustExec(t, l.cp, `ALTER TABLE public.community_identities DROP COLUMN moderation_rename_required`)
	other := sessionTestAccount(t, l, "mod_rename_legacy")
	legacy := identityChange(t, l.c, other.SessionToken, "CREATE", uuid.Nil, "旧身份")
	identityChange(t, l.c, other.SessionToken, "RENAME", legacy.IdentityID, "旧版改名")
	if !strings.Contains(identityDirectory(t, l.c, other.SessionToken).Identities[0].Nickname, "旧版") {
		t.Fatal("legacy rename changed unexpectedly")
	}
}
