package authprivacy

import (
	"context"
	"crypto/sha256"
	"testing"

	"github.com/google/uuid"
)

func TestModerationLifecycleClosureWithoutPostsOrModerationPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "mod_no_posts_closure")
	identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "旧配置闭号")
	runtime := moderationLifecycleRuntime(t, l)
	if err := CheckModerationLifecycleSchema(ctx, runtime); err != nil {
		t.Fatal("common C cleanup validation failed", err)
	}
	copy := *l.c
	copy.pool = runtime
	if copy.PostsEnabled() || copy.ModerationEnabled() {
		t.Fatal("old C fixture enabled optional feature")
	}
	// Old configurations cannot create these artifacts. Seed them as migration
	// owner and verify that the ordinary final-close path can still erase them.
	token := sha256.Sum256([]byte("synthetic disabled-feature limited session"))
	mustExec(t, l.cp, `INSERT INTO c_moderation.access_sessions(token_digest,account_id,credential_version,session_generation,authorization_generation,expires_at) VALUES($1,$2,1,1,1,clock_timestamp()+interval '1 day')`, token[:], owner.AccountID)
	mustExec(t, l.cp, `INSERT INTO c_moderation.roles(account_id,role) VALUES($1,'REVIEWER')`, owner.AccountID)
	mustExec(t, l.cp, `INSERT INTO c_moderation.notifications(notification_id,event_id,account_id,kind,state,title,body,route_name,resource_id,created_at) VALUES($1,'synthetic:no-posts-closure',$2,'SANCTION','ACTIVE','synthetic','','SANCTION',$1,clock_timestamp())`, uuid.New(), owner.AccountID)
	request, _ := closureTestRequest(t, owner.SessionToken)
	accepted, err := copy.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal("old C closure request failed", err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	if n, err := copy.FinalizeDueClosures(ctx, 10); err != nil || n != 1 {
		t.Fatalf("old C final closure failed: %d %v", n, err)
	}
	if n := count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='CLOSED'`, owner.AccountID); n != 1 {
		t.Fatal("old C account did not close")
	}
	for _, table := range []string{"access_sessions", "roles", "notifications"} {
		if n := count(t, l.cp, `SELECT count(*) FROM c_moderation.`+table+` WHERE account_id=$1`, owner.AccountID); n != 0 {
			t.Fatalf("old C closure retained %s", table)
		}
	}
}
