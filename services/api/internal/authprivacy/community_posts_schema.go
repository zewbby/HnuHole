package authprivacy

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgxpool"
)

var errPostSchema = errors.New("required text post schema, hooks or privileges absent")

// CheckPostSchema 只在启用文字接口前核对结构和 hook。owner fixture 可核对结构；
// 正式 runtime 还需通过独立的 CheckDatabase，不能把本检查当作 owner 放行入口。
func (c *Community) CheckPostSchema(ctx context.Context) error {
	if c == nil || c.pool == nil {
		return errPostSchema
	}
	return checkPostSchema(ctx, c.pool)
}

func checkPostSchema(ctx context.Context, pool *pgxpool.Pool) error {
	tables := []string{"schema_meta", "protocol_keys", "account_publication_control", "publication_stop_events", "identity_public_labels", "posts", "post_identity_bindings", "publication_tasks", "publication_attempts", "attempt_contents", "command_receipts", "payload_cleanup"}
	columns := map[string][]string{
		"schema_meta":                 {"singleton_id", "version", "hooks_version"},
		"protocol_keys":               {"singleton_id", "version", "command_tag", "fingerprint_tag"},
		"account_publication_control": {"account_id", "stop_generation", "last_public_identity_id", "last_public_at", "last_public_ordinal"},
		"publication_stop_events":     {"account_id", "generation", "stopped_at", "cause", "transaction_id"},
		"identity_public_labels":      {"identity_id", "short_code"},
		"posts":                       {"post_id", "owner_account_id", "channel_id", "visibility", "published_attempt_version", "published_at", "publication_ordinal", "deleted_at"},
		"post_identity_bindings":      {"account_id", "post_id", "identity_id", "bound_at"},
		"publication_tasks":           {"task_id", "post_id", "owner_account_id", "identity_id", "channel_id", "latest_attempt_version", "owner_visible"},
		"publication_attempts":        {"task_id", "version", "accepted_stop_generation", "state", "accepted_at", "acceptance_ordinal", "terminal_at", "failure_code"},
		"attempt_contents":            {"task_id", "version", "title", "body", "request_digest", "erased_at"},
		"command_receipts":            {"key_digest", "owner_account_id", "operation", "intent_fingerprint", "outcome", "task_id", "post_id", "attempt_version", "task_state", "error_code", "committed_at"},
		"payload_cleanup":             {"task_id", "version", "cause", "requested_at", "due_at", "state"},
	}
	var valid bool
	if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM unnest($1::text[]) AS t(name)
WHERE NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='c_posts' AND c.relname=t.name AND c.relkind='r' AND c.relpersistence='p'))`, tables).Scan(&valid); err != nil || !valid {
		return errPostSchema
	}
	if err := pool.QueryRow(ctx, `SELECT count(*)=1 AND bool_and(singleton_id=1 AND version=1 AND hooks_version=1) FROM c_posts.schema_meta`).Scan(&valid); err != nil || !valid {
		return errPostSchema
	}
	for table, names := range columns {
		if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM unnest($2::text[]) AS required(name)
WHERE NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('c_posts.'||$1)
    AND attname=required.name AND attnum>0 AND NOT attisdropped))`, table, names).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	triggers := map[string][]string{
		"c_auth.accounts":                     {"post_control_new_account", "post_account_stop_hook"},
		"c_auth.account_restrictions":         {"post_restriction_stop_hook"},
		"public.community_identities":         {"post_label_new_identity", "post_identity_delete_hook"},
		"c_posts.schema_meta":                 {"post_schema_meta_immutable"},
		"c_posts.protocol_keys":               {"post_protocol_keys_immutable"},
		"c_posts.identity_public_labels":      {"identity_public_label_immutable"},
		"c_posts.account_publication_control": {"publication_control_monotonic", "publication_control_event"},
		"c_posts.publication_stop_events":     {"publication_stop_event_immutable", "publication_event_control"},
		"c_posts.posts":                       {"post_monotonic", "post_publication_shape"},
		"c_posts.post_identity_bindings":      {"post_binding_immutable"},
		"c_posts.publication_tasks":           {"publication_task_monotonic", "task_publication_shape"},
		"c_posts.publication_attempts":        {"publication_attempt_monotonic", "attempt_publication_shape"},
		"c_posts.attempt_contents":            {"attempt_content_erase_only", "content_publication_shape"},
		"c_posts.command_receipts":            {"post_command_receipt_immutable"},
		"c_posts.payload_cleanup":             {"payload_cleanup_monotonic"},
	}
	for table, names := range triggers {
		if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM unnest($2::text[]) AS required(name)
WHERE NOT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE t.tgrelid=to_regclass($1) AND t.tgname=required.name AND t.tgenabled='O' AND NOT t.tgisinternal AND n.nspname='c_posts'))`, table, names).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	if err := pool.QueryRow(ctx, `SELECT count(*)=2 AND bool_and(NOT s.seqcycle AND s.seqincrement=1)
FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='c_posts' AND c.relname IN ('publication_ordinal_seq','acceptance_ordinal_seq')`).Scan(&valid); err != nil || !valid {
		return errPostSchema
	}
	var runtime bool
	if err := pool.QueryRow(ctx, `SELECT current_user='hnuhole_c_runtime'`).Scan(&runtime); err != nil {
		return errPostSchema
	}
	if !runtime {
		return nil
	}
	for _, table := range tables {
		if table == "schema_meta" {
			continue
		}
		if err := pool.QueryRow(ctx, `SELECT has_table_privilege(current_user,'c_posts.'||$1,'INSERT')`, table).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	writable := map[string][]string{
		"account_publication_control": {"stop_generation", "last_public_identity_id", "last_public_at", "last_public_ordinal"},
		"posts":                       {"visibility", "published_attempt_version", "published_at", "publication_ordinal", "deleted_at"},
		"publication_tasks":           {"latest_attempt_version", "owner_visible"},
		"publication_attempts":        {"state", "terminal_at", "failure_code"},
		"attempt_contents":            {"title", "body", "erased_at"},
		"command_receipts":            {"owner_account_id", "outcome", "task_id", "post_id", "attempt_version", "task_state", "error_code"},
		"payload_cleanup":             {"state"},
	}
	for table, names := range writable {
		if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM unnest($2::text[]) AS required(name)
WHERE NOT has_column_privilege(current_user,'c_posts.'||$1,required.name,'UPDATE'))
AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=to_regclass('c_posts.'||$1)
    AND a.attnum>0 AND NOT a.attisdropped AND NOT(a.attname=ANY($2::text[]))
    AND has_column_privilege(current_user,a.attrelid,a.attname,'UPDATE'))`, table, names).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	// 不接受 schema CREATE、DELETE/TRUNCATE 或永久表的 UPDATE。列级 UPDATE
	// 仍由迁移 guard 约束，runtime 不能替换 trigger 绕过受理文字的不可变性。
	if err := pool.QueryRow(ctx, `SELECT has_schema_privilege(current_user,'c_posts','USAGE')
AND NOT has_schema_privilege(current_user,'c_posts','CREATE')
AND NOT EXISTS(SELECT 1 FROM unnest($1::text[]) AS t(name)
    WHERE NOT has_table_privilege(current_user,'c_posts.'||t.name,'SELECT')
      OR has_table_privilege(current_user,'c_posts.'||t.name,'DELETE,TRUNCATE,TRIGGER'))
AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['schema_meta','protocol_keys','identity_public_labels','post_identity_bindings','publication_stop_events']) AS t(name)
    WHERE has_any_column_privilege(current_user,'c_posts.'||t.name,'UPDATE'))
AND has_sequence_privilege(current_user,'c_posts.publication_ordinal_seq','USAGE')
AND has_sequence_privilege(current_user,'c_posts.acceptance_ordinal_seq','USAGE')
AND has_function_privilege(current_user,'c_posts.allocate_identity_label(uuid)','EXECUTE')`, tables).Scan(&valid); err != nil || !valid {
		return errPostSchema
	}
	return nil
}
