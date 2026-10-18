package authprivacy

import (
	"context"
	"strings"
)

// WithModeration is explicit and fail-closed for missing schema, hooks or DML.
func (c *Community) WithModeration(ctx context.Context) (*Community, error) {
	if !c.PostsEnabled() {
		return nil, ErrAuthorizationUnavailable
	}
	var ok bool
	tables := []string{"schema_meta", "platform_numbers", "roles", "access_sessions", "legacy_restrictions", "cases", "reports", "sanctions", "appeals", "appeal_materials", "notifications", "commands", "request_fences", "audit"}
	for _, t := range tables {
		if e := c.pool.QueryRow(ctx, `SELECT to_regclass('c_moderation.'||$1) IS NOT NULL`, t).Scan(&ok); e != nil || !ok {
			return nil, ErrAuthorizationUnavailable
		}
	}
	if e := c.pool.QueryRow(ctx, `SELECT version=1 FROM c_moderation.schema_meta WHERE singleton_id=1`).Scan(&ok); e != nil || !ok {
		return nil, ErrAuthorizationUnavailable
	}
	for _, t := range []struct{ table, name string }{{"c_moderation.audit", "moderation_audit_immutable"}, {"c_posts.posts", "moderation_post_deleted"}, {"c_auth.accounts", "moderation_account_closed"}} {
		if e := c.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=to_regclass($1) AND tgname=$2 AND tgenabled='O' AND NOT tgisinternal)`, t.table, t.name).Scan(&ok); e != nil || !ok {
			return nil, ErrAuthorizationUnavailable
		}
	}
	var runtime bool
	if e := c.pool.QueryRow(ctx, `SELECT current_user='hnuhole_c_runtime'`).Scan(&runtime); e != nil {
		return nil, ErrAuthorizationUnavailable
	}
	if runtime {
		insert := map[string]bool{}
		for _, t := range []string{"roles", "access_sessions", "cases", "reports", "sanctions", "appeals", "appeal_materials", "notifications", "commands", "request_fences", "audit"} {
			insert[t] = true
		}
		deletable := map[string]bool{"roles": true, "access_sessions": true, "notifications": true}
		writable := map[string][]string{"roles": {"role"}, "access_sessions": {"revoked_at"}, "cases": {"state", "version", "outcome", "explanation", "decided_by"}, "reports": {"reporter_account_id", "identity_id"}, "sanctions": {"revoked_at"}, "appeals": {"state", "version", "reason"}, "notifications": {"read_at"}, "request_fences": {"retry_token"}}
		for _, t := range tables {
			if e := c.pool.QueryRow(ctx, `SELECT has_table_privilege(current_user,$1,'SELECT') AND has_table_privilege(current_user,$1,'INSERT')=$2 AND has_table_privilege(current_user,$1,'DELETE')=$3 AND NOT has_table_privilege(current_user,$1,'TRUNCATE')`, "c_moderation."+t, insert[t], deletable[t]).Scan(&ok); e != nil || !ok {
				return nil, ErrAuthorizationUnavailable
			}
			if t == "platform_numbers" {
				continue
			}
			columns := writable[t]
			if columns == nil {
				columns = []string{}
			}
			if e := c.pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass($1) AND attnum>0 AND NOT attisdropped AND has_column_privilege(current_user,attrelid,attname,'UPDATE')<>(attname=ANY($2::text[])))`, "c_moderation."+t, columns).Scan(&ok); e != nil || !ok {
				return nil, ErrAuthorizationUnavailable
			}
		}
		for _, spec := range []string{"c_posts.posts|moderation_hidden", "public.community_identities|moderation_rename_required"} {
			p := strings.Split(spec, "|")
			if e := c.pool.QueryRow(ctx, `SELECT has_column_privilege(current_user,$1,$2,'UPDATE')`, p[0], p[1]).Scan(&ok); e != nil || !ok {
				return nil, ErrAuthorizationUnavailable
			}
		}
		for _, s := range []string{"cases_number_seq", "audit_audit_id_seq"} {
			if e := c.pool.QueryRow(ctx, `SELECT has_sequence_privilege(current_user,$1,'USAGE')`, "c_moderation."+s).Scan(&ok); e != nil || !ok {
				return nil, ErrAuthorizationUnavailable
			}
		}
		if e := c.pool.QueryRow(ctx, `SELECT NOT has_schema_privilege(current_user,'c_moderation','CREATE')`).Scan(&ok); e != nil || !ok {
			return nil, ErrAuthorizationUnavailable
		}
	}
	clone := *c
	clone.moderationEnabled = true
	return &clone, nil
}
