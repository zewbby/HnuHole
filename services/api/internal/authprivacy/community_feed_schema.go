package authprivacy

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Optional for a pre-0019 auth-only installation. Once installed, account
// closure must never run without its cleanup hook and invoker permissions.
func checkFeedSchema(ctx context.Context, pool *pgxpool.Pool, required bool) error {
	var present, valid, runtime bool
	if err := pool.QueryRow(ctx, `SELECT to_regclass('c_posts.feed_preferences') IS NOT NULL OR to_regclass('c_posts.post_daily_views') IS NOT NULL OR to_regclass('c_posts.post_view_totals') IS NOT NULL`).Scan(&present); err != nil {
		return errPostSchema
	}
	if !present && !required {
		var tracker bool
		if err := pool.QueryRow(ctx, `SELECT to_regclass('public.goose_db_version') IS NOT NULL`).Scan(&tracker); err != nil {
			return errPostSchema
		}
		if !tracker {
			return nil
		}
		if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM public.goose_db_version WHERE version_id>=19 AND is_applied)`).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
		return nil
	}
	columns := map[string][]string{
		"post_view_totals": {"post_id", "view_count"},
		"post_daily_views": {"account_id", "post_id", "view_day"},
		"feed_preferences": {"account_id", "blocked_channel_ids", "revision"},
	}
	for table, names := range columns {
		if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('c_posts.'||$1) AND relkind='r' AND relpersistence='p')
 AND NOT EXISTS(SELECT 1 FROM unnest($2::text[]) AS c(name) WHERE NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('c_posts.'||$1) AND attname=c.name AND attnum>0 AND NOT attisdropped))`, table, names).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE t.tgrelid='c_auth.accounts'::regclass AND t.tgname='feed_account_closed' AND t.tgenabled='O' AND NOT t.tgisinternal AND p.oid='c_posts.clear_closed_account_feed()'::regprocedure AND NOT p.prosecdef),current_user='hnuhole_c_runtime'`).Scan(&valid, &runtime); err != nil || !valid {
		return errPostSchema
	}
	if !runtime {
		return nil
	}
	for table := range columns {
		if err := pool.QueryRow(ctx, `SELECT has_table_privilege(current_user,'c_posts.'||$1,'SELECT') AND has_table_privilege(current_user,'c_posts.'||$1,'INSERT') AND NOT has_table_privilege(current_user,'c_posts.'||$1,'TRUNCATE,TRIGGER,REFERENCES')`, table).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	if err := pool.QueryRow(ctx, `SELECT has_schema_privilege(current_user,'c_posts','USAGE') AND NOT has_schema_privilege(current_user,'c_posts','CREATE')
 AND has_column_privilege(current_user,'c_posts.post_view_totals','view_count','UPDATE')
 AND NOT has_column_privilege(current_user,'c_posts.post_view_totals','post_id','UPDATE')
 AND NOT has_table_privilege(current_user,'c_posts.post_view_totals','DELETE')
 AND has_column_privilege(current_user,'c_posts.feed_preferences','blocked_channel_ids','UPDATE')
 AND has_column_privilege(current_user,'c_posts.feed_preferences','revision','UPDATE')
 AND NOT has_column_privilege(current_user,'c_posts.feed_preferences','account_id','UPDATE')
 AND NOT has_any_column_privilege(current_user,'c_posts.post_daily_views','UPDATE')
 AND has_table_privilege(current_user,'c_posts.post_daily_views','DELETE')
 AND has_table_privilege(current_user,'c_posts.feed_preferences','DELETE')`).Scan(&valid); err != nil || !valid {
		return errPostSchema
	}
	return nil
}
