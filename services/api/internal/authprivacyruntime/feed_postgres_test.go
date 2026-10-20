package authprivacyruntime

import (
	"context"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

func TestFeedCommonStartupWithoutFeaturesPostgres(t *testing.T) {
	owner, runtime := moderationStartupLab(t)
	ctx := context.Background()
	exec := func(sql string) {
		t.Helper()
		if _, e := owner.Exec(ctx, sql); e != nil {
			t.Fatal(e)
		}
	}
	if e := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); e != nil {
		t.Fatal(e)
	}
	for _, item := range []struct{ breakSQL, restoreSQL string }{
		{`REVOKE DELETE ON c_posts.post_favorites FROM hnuhole_c_runtime`, `GRANT DELETE ON c_posts.post_favorites TO hnuhole_c_runtime`},
		{`ALTER TABLE c_auth.accounts DISABLE TRIGGER interactions_account_closed`, `ALTER TABLE c_auth.accounts ENABLE TRIGGER interactions_account_closed`},
		{`DROP TRIGGER interactions_account_closed ON c_auth.accounts; CREATE TRIGGER interactions_account_closed AFTER INSERT ON c_auth.accounts FOR EACH ROW EXECUTE FUNCTION c_posts.clear_closed_account_interactions()`, `DROP TRIGGER interactions_account_closed ON c_auth.accounts; CREATE TRIGGER interactions_account_closed AFTER UPDATE OF state ON c_auth.accounts FOR EACH ROW EXECUTE FUNCTION c_posts.clear_closed_account_interactions()`},
		{`GRANT UPDATE(account_id) ON c_posts.post_likes TO hnuhole_c_runtime`, `REVOKE UPDATE(account_id) ON c_posts.post_likes FROM hnuhole_c_runtime`},
		{`REVOKE DELETE ON c_posts.post_daily_views FROM hnuhole_c_runtime`, `GRANT DELETE ON c_posts.post_daily_views TO hnuhole_c_runtime`},
		{`ALTER TABLE c_auth.accounts DISABLE TRIGGER feed_account_closed`, `ALTER TABLE c_auth.accounts ENABLE TRIGGER feed_account_closed`},
		{`GRANT UPDATE(account_id) ON c_posts.feed_preferences TO hnuhole_c_runtime`, `REVOKE UPDATE(account_id) ON c_posts.feed_preferences FROM hnuhole_c_runtime`},
	} {
		exec(item.breakSQL)
		if e := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); e == nil {
			t.Fatal("common C startup ignored invalid feed schema/privileges")
		}
		exec(item.restoreSQL)
	}
	exec(`UPDATE public.goose_db_version SET version_id=19; DROP TABLE c_posts.feed_preferences,c_posts.post_daily_views,c_posts.post_view_totals`)
	if e := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); e == nil {
		t.Fatal("0019 ledger with erased tables accepted")
	}
}
