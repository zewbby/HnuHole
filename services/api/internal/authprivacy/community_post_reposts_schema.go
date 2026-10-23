package authprivacy

import (
	"context"
	"github.com/jackc/pgx/v5/pgxpool"
)

func checkPostRepostSchema(ctx context.Context, pool *pgxpool.Pool, required bool) error {
	var present, tracker, valid, runtime bool
	if err := pool.QueryRow(ctx, `SELECT to_regclass('c_posts.post_reposts') IS NOT NULL OR to_regclass('c_posts.post_repost_versions') IS NOT NULL,to_regclass('public.goose_db_version') IS NOT NULL,current_user='hnuhole_c_runtime'`).Scan(&present, &tracker, &runtime); err != nil {
		return errPostSchema
	}
	if !present && !required {
		if tracker {
			if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM public.goose_db_version WHERE is_applied AND version_id>=26)`).Scan(&valid); err != nil || !valid {
				return errPostSchema
			}
		}
		return nil
	}
	for table, columns := range map[string][]string{"post_reposts": {"identity_id", "post_id"}, "post_repost_versions": {"account_id", "post_id"}} {
		if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('c_posts.'||$1) AND relkind='r' AND relpersistence='p')
 AND EXISTS(SELECT 1 FROM pg_constraint k WHERE k.conrelid=to_regclass('c_posts.'||$1) AND k.contype='p' AND NOT k.condeferrable AND k.convalidated
 AND k.conkey=ARRAY(SELECT a.attnum FROM unnest($2::text[]) WITH ORDINALITY required(name,position) JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attname=required.name AND NOT a.attisdropped ORDER BY required.position))`, table, columns).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
		if runtime {
			if err := pool.QueryRow(ctx, `SELECT has_table_privilege(current_user,'c_posts.'||$1,'SELECT') AND has_table_privilege(current_user,'c_posts.'||$1,'INSERT') AND has_table_privilege(current_user,'c_posts.'||$1,'DELETE') AND NOT has_table_privilege(current_user,'c_posts.'||$1,'UPDATE,TRUNCATE,TRIGGER,REFERENCES')`, table).Scan(&valid); err != nil || !valid {
				return errPostSchema
			}
		}
	}
	if err := pool.QueryRow(ctx, `SELECT
 EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='c_posts.post_reposts'::regclass AND contype='f' AND confrelid='public.community_identities'::regclass AND convalidated)
 AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.community_identities'::regclass AND tgname='identity_reposts_cleanup' AND tgenabled='O' AND tgfoid='c_posts.clear_identity_reposts()'::regprocedure)
 AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='c_auth.accounts'::regclass AND tgname='account_reposts_cleanup' AND tgenabled='O' AND tgfoid='c_posts.clear_account_reposts()'::regprocedure)
 AND NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid IN ('c_posts.clear_identity_reposts()'::regprocedure,'c_posts.clear_account_reposts()'::regprocedure) AND prosecdef)`).Scan(&valid); err != nil || !valid {
		return errPostSchema
	}
	if runtime {
		if err := pool.QueryRow(ctx, `SELECT has_sequence_privilege(current_user,'c_posts.post_reposts_ordinal_seq','USAGE')
 AND NOT has_any_column_privilege(current_user,'c_posts.post_reposts','UPDATE')
 AND has_column_privilege(current_user,'c_posts.post_repost_versions','version','UPDATE')
 AND NOT has_column_privilege(current_user,'c_posts.post_repost_versions','account_id','UPDATE')
 AND NOT has_column_privilege(current_user,'c_posts.post_repost_versions','post_id','UPDATE')`).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	return nil
}
