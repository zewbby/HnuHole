package authprivacy

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

func checkPostInteractionSchema(ctx context.Context, pool *pgxpool.Pool, required bool) error {
	var present, valid, tracker bool
	if err := pool.QueryRow(ctx, `SELECT to_regclass('c_posts.post_likes') IS NOT NULL OR to_regclass('c_posts.post_favorites') IS NOT NULL,to_regclass('public.goose_db_version') IS NOT NULL`).Scan(&present, &tracker); err != nil {
		return errPostSchema
	}
	if !present && !required {
		if tracker {
			if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM public.goose_db_version WHERE version_id>=20 AND is_applied)`).Scan(&valid); err != nil || !valid {
				return errPostSchema
			}
		}
		return nil
	}
	for _, table := range []string{"post_likes", "post_favorites"} {
		if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('c_posts.'||$1) AND relkind='r' AND relpersistence='p')
 AND EXISTS(SELECT 1 FROM pg_constraint k WHERE k.conrelid=to_regclass('c_posts.'||$1) AND k.contype='p' AND NOT k.condeferrable AND k.convalidated
 AND k.conkey=ARRAY(SELECT a.attnum FROM unnest(ARRAY['account_id','post_id']) WITH ORDINALITY required(name,position)
 JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attname=required.name AND NOT a.attisdropped ORDER BY required.position))`, table).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='c_posts.post_favorites'::regclass AND attname='saved_at' AND atttypid='timestamptz'::regtype AND attnotnull AND NOT attisdropped)
 AND EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE t.tgrelid='c_auth.accounts'::regclass AND t.tgname='interactions_account_closed' AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgtype=17
 AND t.tgattr::text=(SELECT attnum::text FROM pg_attribute WHERE attrelid=t.tgrelid AND attname='state' AND NOT attisdropped)
 AND p.oid='c_posts.clear_closed_account_interactions()'::regprocedure AND NOT p.prosecdef)`).Scan(&valid); err != nil || !valid {
		return errPostSchema
	}
	var runtime bool
	if err := pool.QueryRow(ctx, `SELECT current_user='hnuhole_c_runtime'`).Scan(&runtime); err != nil {
		return errPostSchema
	}
	if runtime {
		for _, table := range []string{"post_likes", "post_favorites"} {
			if err := pool.QueryRow(ctx, `SELECT has_table_privilege(current_user,'c_posts.'||$1,'SELECT') AND has_table_privilege(current_user,'c_posts.'||$1,'INSERT') AND has_table_privilege(current_user,'c_posts.'||$1,'DELETE') AND NOT has_any_column_privilege(current_user,'c_posts.'||$1,'UPDATE') AND NOT has_table_privilege(current_user,'c_posts.'||$1,'TRUNCATE,TRIGGER,REFERENCES')`, table).Scan(&valid); err != nil || !valid {
				return errPostSchema
			}
		}
	}
	return nil
}
