package authprivacy

import (
	"context"
	"errors"
)

var errCommentSchema = errors.New("required comment text schema, hooks or runtime grants absent")

// Ordered migration readiness is separately blocked until governance is merged.
// This check makes the explicitly enabled component fail closed at startup.
func (c *Community) CheckCommentSchema(ctx context.Context) error {
	if c == nil || c.pool == nil {
		return errCommentSchema
	}
	for _, table := range []string{"protocol_keys", "tasks", "attempts", "receipts", "snapshots"} {
		var ok bool
		if e := c.pool.QueryRow(ctx, `SELECT to_regclass('c_comments.'||$1) IS NOT NULL`, table).Scan(&ok); e != nil || !ok {
			return errCommentSchema
		}
	}
	for _, pair := range [][2]string{{"c_comments.tasks", "comment_task_guard"}, {"c_comments.attempts", "comment_attempt_guard"}, {"c_comments.receipts", "comment_receipt_immutable"}, {"c_comments.protocol_keys", "comment_keys_immutable"}, {"c_posts.publication_stop_events", "comment_stop_hook"}, {"public.community_identities", "comment_identity_hook"}} {
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
	if e := c.pool.QueryRow(ctx, `SELECT has_schema_privilege(current_user,'c_comments','USAGE') AND NOT has_schema_privilege(current_user,'c_comments','CREATE')
 AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['protocol_keys','tasks','attempts','receipts','snapshots']) t(name) WHERE NOT has_table_privilege(current_user,'c_comments.'||name,'SELECT') OR NOT has_table_privilege(current_user,'c_comments.'||name,'INSERT') OR has_table_privilege(current_user,'c_comments.'||name,'TRUNCATE,TRIGGER'))
 AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['protocol_keys','tasks','attempts','receipts']) t(name) WHERE has_table_privilege(current_user,'c_comments.'||name,'DELETE'))
 AND NOT has_any_column_privilege(current_user,'c_comments.protocol_keys','UPDATE')
 AND NOT has_any_column_privilege(current_user,'c_comments.receipts','UPDATE')
 AND has_column_privilege(current_user,'c_comments.tasks','owner_visible','UPDATE')
 AND has_column_privilege(current_user,'c_comments.tasks','abandoned_at','UPDATE')
 AND has_column_privilege(current_user,'c_comments.attempts','state','UPDATE')
 AND has_column_privilege(current_user,'c_comments.attempts','terminal_at','UPDATE')
 AND has_column_privilege(current_user,'c_comments.attempts','failure_code','UPDATE')
 AND has_column_privilege(current_user,'c_comments.attempts','body','UPDATE')`).Scan(&ok); e != nil || !ok {
		return errCommentSchema
	}
	return nil
}
