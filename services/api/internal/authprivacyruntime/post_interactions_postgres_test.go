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
 DROP TABLE c_posts.post_likes,c_posts.post_favorites;
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
