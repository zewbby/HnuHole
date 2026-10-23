package authprivacyruntime

import (
	"context"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"testing"
)

func TestFeedRepostsLeastPrivilegeAndLifecyclePostgres(t *testing.T) {
	owner, runtime := moderationStartupLab(t)
	ctx := context.Background()
	if e := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); e != nil {
		t.Fatal("baseline", e)
	}
	for _, tc := range []struct{ breakSQL, repairSQL string }{
		{`REVOKE DELETE ON c_posts.post_reposts FROM hnuhole_c_runtime`, `GRANT DELETE ON c_posts.post_reposts TO hnuhole_c_runtime`},
		{`REVOKE UPDATE(version) ON c_posts.post_repost_versions FROM hnuhole_c_runtime`, `GRANT UPDATE(version) ON c_posts.post_repost_versions TO hnuhole_c_runtime`},
		{`GRANT UPDATE(account_id) ON c_posts.post_repost_versions TO hnuhole_c_runtime`, `REVOKE UPDATE(account_id) ON c_posts.post_repost_versions FROM hnuhole_c_runtime`},
		{`ALTER TABLE c_auth.accounts DISABLE TRIGGER account_reposts_cleanup`, `ALTER TABLE c_auth.accounts ENABLE TRIGGER account_reposts_cleanup`},
		{`ALTER TABLE public.community_identities DISABLE TRIGGER identity_reposts_cleanup`, `ALTER TABLE public.community_identities ENABLE TRIGGER identity_reposts_cleanup`},
		{`ALTER TABLE c_posts.post_reposts DROP CONSTRAINT post_reposts_pkey`, `ALTER TABLE c_posts.post_reposts ADD PRIMARY KEY(identity_id,post_id)`},
	} {
		if _, e := owner.Exec(ctx, tc.breakSQL); e != nil {
			t.Fatal(e)
		}
		if CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService) == nil {
			t.Fatal("broken schema/privilege accepted")
		}
		if _, e := owner.Exec(ctx, tc.repairSQL); e != nil {
			t.Fatal(e)
		}
	}
	if _, e := owner.Exec(ctx, `UPDATE public.goose_db_version SET version_id=25`); e != nil {
		t.Fatal(e)
	}
	if CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService) == nil {
		t.Fatal("pre-repost deployment accepted")
	}
}
