package authprivacy

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5/pgxpool"
)

var errCommentSchema = errors.New("required comment text schema, hooks or runtime grants absent")

func checkCommentLifecycleSchema(ctx context.Context, pool *pgxpool.Pool) error {
	var installed, runtime, ok bool
	if e := pool.QueryRow(ctx, `SELECT to_regnamespace('c_comments') IS NOT NULL,current_user='hnuhole_c_runtime'`).Scan(&installed, &runtime); e != nil {
		return errCommentSchema
	}
	if !installed {
		return nil
	}
	if e := pool.QueryRow(ctx, `SELECT to_regclass('c_comments.tasks') IS NOT NULL AND to_regclass('c_comments.attempts') IS NOT NULL AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='c_posts.publication_stop_events'::regclass AND tgname='comment_stop_hook' AND tgenabled='O') AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.community_identities'::regclass AND tgname='comment_identity_hook' AND tgenabled='O')`).Scan(&ok); e != nil || !ok {
		return errCommentSchema
	}
	if runtime {
		if e := pool.QueryRow(ctx, `SELECT has_schema_privilege(current_user,'c_comments','USAGE') AND has_table_privilege(current_user,'c_comments.tasks','SELECT') AND has_table_privilege(current_user,'c_comments.attempts','SELECT') AND has_column_privilege(current_user,'c_comments.tasks','owner_visible','UPDATE') AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['state','terminal_at','failure_code','body']) c(name) WHERE NOT has_column_privilege(current_user,'c_comments.attempts',c.name,'UPDATE'))`).Scan(&ok); e != nil || !ok {
			return errCommentSchema
		}
	}
	var media bool
	if e := pool.QueryRow(ctx, `SELECT to_regclass('c_comments.images') IS NOT NULL`).Scan(&media); e != nil {
		return errCommentSchema
	}
	if media && runtime {
		if e := pool.QueryRow(ctx, `SELECT has_table_privilege(current_user,'c_comments.images','SELECT') AND has_column_privilege(current_user,'c_comments.images','payload','UPDATE') AND has_column_privilege(current_user,'c_comments.images','metadata','UPDATE') AND has_column_privilege(current_user,'c_comments.images','erased_at','UPDATE') AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='c_posts.posts'::regclass AND tgname='comment_post_deleted' AND tgenabled='O')`).Scan(&ok); e != nil || !ok {
			return errCommentSchema
		}
	}
	return nil
}

// This check makes the explicitly enabled component fail closed at startup.
func (c *Community) CheckCommentSchema(ctx context.Context) error {
	if c == nil || c.pool == nil {
		return errCommentSchema
	}
	for _, table := range []string{"protocol_keys", "tasks", "attempts", "receipts", "snapshots", "images", "likes"} {
		var ok bool
		if e := c.pool.QueryRow(ctx, `SELECT to_regclass('c_comments.'||$1) IS NOT NULL`, table).Scan(&ok); e != nil || !ok {
			return errCommentSchema
		}
	}
	for _, pair := range [][2]string{{"c_comments.tasks", "comment_task_guard"}, {"c_comments.tasks", "comment_task_acceptance"}, {"c_posts.post_identity_bindings", "comment_binding_acceptance"}, {"c_comments.attempts", "comment_attempt_guard"}, {"c_comments.receipts", "comment_receipt_immutable"}, {"c_comments.protocol_keys", "comment_keys_immutable"}, {"c_posts.publication_stop_events", "comment_stop_hook"}, {"public.community_identities", "comment_identity_hook"}, {"c_comments.tasks", "comment_delete_monotonic"}, {"c_comments.attempts", "comment_media_attempt"}, {"c_comments.images", "comment_original_guard"}, {"c_comments.attempts", "comment_failure_notice"}, {"c_comments.tasks", "comment_task_notice"}, {"c_posts.posts", "comment_post_deleted"}} {
		var ok bool
		if e := c.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=to_regclass($1) AND tgname=$2 AND tgenabled='O')`, pair[0], pair[1]).Scan(&ok); e != nil || !ok {
			return errCommentSchema
		}
	}
	var ok bool
	if e := c.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='c_posts.post_identity_bindings'::regclass AND conname='comment_binding_post_fk' AND convalidated)`).Scan(&ok); e != nil || !ok {
		return errCommentSchema
	}
	var runtime bool
	if e := c.pool.QueryRow(ctx, `SELECT current_user='hnuhole_c_runtime'`).Scan(&runtime); e != nil {
		return errCommentSchema
	}
	if !runtime {
		return nil
	}
	for table, columns := range map[string][]string{"tasks": {"owner_visible", "abandoned_at", "deleted_at"}, "attempts": {"state", "terminal_at", "failure_code", "body"}, "snapshots": {}, "images": {"payload", "metadata", "erased_at"}, "likes": {}} {
		if e := c.pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('c_comments.'||$1) AND attnum>0 AND NOT attisdropped AND NOT(attname=ANY($2::text[])) AND has_column_privilege(current_user,attrelid,attname,'UPDATE'))`, table, columns).Scan(&ok); e != nil || !ok {
			return errCommentSchema
		}
	}
	if e := c.pool.QueryRow(ctx, `SELECT has_schema_privilege(current_user,'c_comments','USAGE') AND NOT has_schema_privilege(current_user,'c_comments','CREATE')
 AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['protocol_keys','tasks','attempts','receipts','snapshots']) t(name) WHERE NOT has_table_privilege(current_user,'c_comments.'||name,'SELECT') OR NOT has_table_privilege(current_user,'c_comments.'||name,'INSERT') OR has_table_privilege(current_user,'c_comments.'||name,'TRUNCATE,TRIGGER'))
 AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['protocol_keys','tasks','attempts','receipts']) t(name) WHERE has_table_privilege(current_user,'c_comments.'||name,'DELETE'))
 AND NOT has_any_column_privilege(current_user,'c_comments.protocol_keys','UPDATE')
 AND NOT has_any_column_privilege(current_user,'c_comments.receipts','UPDATE')
 AND has_column_privilege(current_user,'c_comments.tasks','owner_visible','UPDATE')
 AND has_column_privilege(current_user,'c_comments.tasks','abandoned_at','UPDATE')
 AND has_column_privilege(current_user,'c_comments.tasks','deleted_at','UPDATE')
 AND has_table_privilege(current_user,'c_comments.images','SELECT,INSERT')
 AND NOT has_table_privilege(current_user,'c_comments.images','DELETE,TRUNCATE,TRIGGER')
 AND has_column_privilege(current_user,'c_comments.images','payload','UPDATE')
 AND has_column_privilege(current_user,'c_comments.images','metadata','UPDATE')
 AND has_column_privilege(current_user,'c_comments.images','erased_at','UPDATE')
 AND has_table_privilege(current_user,'c_comments.likes','SELECT,INSERT,DELETE')
 AND NOT has_table_privilege(current_user,'c_comments.likes','TRUNCATE,TRIGGER')
 AND has_column_privilege(current_user,'c_comments.attempts','state','UPDATE')
 AND has_column_privilege(current_user,'c_comments.attempts','terminal_at','UPDATE')
 AND has_column_privilege(current_user,'c_comments.attempts','failure_code','UPDATE')
 AND has_column_privilege(current_user,'c_comments.attempts','body','UPDATE')`).Scan(&ok); e != nil || !ok {
		return errCommentSchema
	}
	return nil
}
