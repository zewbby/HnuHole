package authprivacyruntime

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Avatar lifecycle triggers run even with image/post HTTP disabled.
func checkIdentityAvatarSchema(ctx context.Context, pool *pgxpool.Pool) error {
	var ok bool
	e := pool.QueryRow(ctx, `SELECT to_regclass('public.identity_avatar_assets') IS NOT NULL
 AND NOT pg_has_role(current_user,(SELECT relowner FROM pg_class WHERE oid='public.identity_avatar_assets'::regclass),'MEMBER')
 AND has_table_privilege(current_user,'public.identity_avatar_assets','SELECT')
 AND has_table_privilege(current_user,'public.identity_avatar_assets','INSERT')
 AND NOT has_table_privilege(current_user,'public.identity_avatar_assets','DELETE,TRUNCATE,TRIGGER,REFERENCES')
 AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['asset_id','account_id','digest','created_at','expires_at']) c(name) WHERE has_column_privilege(current_user,'public.identity_avatar_assets',c.name,'UPDATE'))
 AND has_column_privilege(current_user,'public.identity_avatar_assets','payload','UPDATE')
 AND has_column_privilege(current_user,'public.identity_avatar_assets','identity_id','UPDATE')
 AND (SELECT count(*)=3 FROM pg_trigger WHERE NOT tgisinternal AND tgenabled='O' AND
 ((tgrelid='public.identity_avatar_assets'::regclass AND tgname='identity_avatar_immutable') OR
 (tgrelid='public.community_identities'::regclass AND tgname='identity_avatar_binding') OR
 (tgrelid='c_auth.accounts'::regclass AND tgname='identity_avatar_account_closed')))
 AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['guard_identity_avatar','bind_identity_avatar','close_identity_avatars']) f(name) JOIN pg_proc p ON p.proname=f.name JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND (p.prosecdef OR EXISTS(SELECT 1 FROM aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')))
 `).Scan(&ok)
	if e != nil || !ok {
		return errors.New("identity avatar schema or privilege boundary rejected")
	}
	return nil
}
