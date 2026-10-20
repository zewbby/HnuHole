package authprivacyruntime

import (
	"context"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

func TestFeedInteractionLedgerAndPreMigrationCommonCPostgres(t *testing.T) {
	owner, runtime := moderationStartupLab(t)
	ctx := context.Background()
	if _, err := owner.Exec(ctx, `DROP TRIGGER interactions_account_closed ON c_auth.accounts;
 DROP FUNCTION c_posts.clear_closed_account_interactions();
 DROP TABLE c_posts.post_likes,c_posts.post_favorites,c_posts.post_interaction_versions;
 UPDATE public.goose_db_version SET version_id=19`); err != nil {
		t.Fatal(err)
	}
	if err := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); err != nil {
		t.Fatal("pre-0020 auth-only C lost compatibility", err)
	}
	if _, err := owner.Exec(ctx, `UPDATE public.goose_db_version SET version_id=20`); err != nil {
		t.Fatal(err)
	}
	if err := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); err == nil {
		t.Fatal("0020 ledger accepted erased interaction tables")
	}
}

func TestFeedInteractionVersionLedgerPrivilegesAndCleanupPostgres(t *testing.T) {
	owner, runtime := moderationStartupLab(t)
	ctx := context.Background()
	for _, tc := range []struct{ breakSQL, repairSQL string }{
		{`REVOKE UPDATE(version) ON c_posts.post_interaction_versions FROM hnuhole_c_runtime`, `GRANT UPDATE(version) ON c_posts.post_interaction_versions TO hnuhole_c_runtime`},
		{`GRANT UPDATE(account_id) ON c_posts.post_interaction_versions TO hnuhole_c_runtime`, `REVOKE UPDATE(account_id) ON c_posts.post_interaction_versions FROM hnuhole_c_runtime`},
		{`REVOKE DELETE ON c_posts.post_interaction_versions FROM hnuhole_c_runtime`, `GRANT DELETE ON c_posts.post_interaction_versions TO hnuhole_c_runtime`},
	} {
		if _, e := owner.Exec(ctx, tc.breakSQL); e != nil {
			t.Fatal(e)
		}
		if CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService) == nil {
			t.Fatal("common C accepted missing/excess fence privilege")
		}
		if _, e := owner.Exec(ctx, tc.repairSQL); e != nil {
			t.Fatal(e)
		}
	}
	if _, e := owner.Exec(ctx, `DROP TABLE c_posts.post_interaction_versions; UPDATE public.goose_db_version SET version_id=21`); e != nil {
		t.Fatal(e)
	}
	if CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService) == nil {
		t.Fatal("0021 ledger accepted lost fences")
	}
	// A pre-0021 auth-only C database remains compatible. Posts require0021.
	if _, e := owner.Exec(ctx, `UPDATE public.goose_db_version SET version_id=20`); e != nil {
		t.Fatal(e)
	}
	if e := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); e != nil {
		t.Fatal("pre0021 auth-only compatibility", e)
	}
}
