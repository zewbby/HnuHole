package authprivacy

import "context"

// Fail closed when a migration/index/receipt guard is missing. Owner fixtures
// validate structure; restricted runtime checks additionally forbid broad writes.
func (c *Community) checkDMSchema(ctx context.Context) error {
	var valid bool
	e := c.pool.QueryRow(ctx, `SELECT
 (SELECT count(*) FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='c_dm' AND t.relkind='r' AND t.relname IN ('conversations','commands','messages','binding_acceptances'))=4
 AND (SELECT count(*) FROM pg_constraint x JOIN pg_namespace n ON n.oid=x.connamespace WHERE n.nspname='c_dm' AND x.contype='p')=4
 AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='c_dm.conversations'::regclass AND contype='u' AND pg_get_constraintdef(oid)='UNIQUE (low_identity, high_identity)')
 AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='c_dm.messages'::regclass AND contype='u' AND pg_get_constraintdef(oid)='UNIQUE (conversation_id, sequence)')
 AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='c_posts.post_identity_bindings'::regclass AND tgname='comment_binding_acceptance' AND tgenabled='O' AND tgdeferrable AND tginitdeferred)
 AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='c_dm.binding_acceptances'::regclass AND tgname='dm_binding_immutable' AND tgenabled='O')
 AND has_schema_privilege(current_user,'c_dm','USAGE')
 AND has_table_privilege(current_user,'c_dm.messages','SELECT,INSERT')
 AND has_column_privilege(current_user,'c_dm.messages','body','UPDATE')
 AND has_table_privilege(current_user,'c_dm.commands','SELECT,INSERT')
 AND has_table_privilege(current_user,'c_dm.conversations','SELECT,INSERT')
 AND has_table_privilege(current_user,'c_dm.binding_acceptances','SELECT,INSERT')`).Scan(&valid)
	if e != nil || !valid {
		return ErrAuthorizationUnavailable
	}
	var owner bool
	if e = c.pool.QueryRow(ctx, `SELECT current_user=pg_get_userbyid(relowner) FROM pg_class WHERE oid='c_dm.messages'::regclass`).Scan(&owner); e != nil {
		return ErrAuthorizationUnavailable
	}
	if !owner {
		if e = c.pool.QueryRow(ctx, `SELECT NOT has_table_privilege(current_user,'c_dm.messages','DELETE') AND NOT has_column_privilege(current_user,'c_dm.messages','sender','UPDATE') AND NOT has_column_privilege(current_user,'c_dm.commands','fingerprint','UPDATE') AND NOT has_table_privilege(current_user,'c_dm.binding_acceptances','UPDATE,DELETE')`).Scan(&valid); e != nil || !valid {
			return ErrAuthorizationUnavailable
		}
	}
	return nil
}
