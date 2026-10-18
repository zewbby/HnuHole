package authprivacy

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// CheckModerationLegacyRestrictionSchema covers the trusted old restriction
// entry points even when moderation HTTP features are disabled. It is a no-op
// before 0015 and never grants access by itself.
func CheckModerationLegacyRestrictionSchema(ctx context.Context, pool *pgxpool.Pool) error {
	var installed, runtime, ok bool
	if err := pool.QueryRow(ctx, `SELECT to_regnamespace('c_moderation') IS NOT NULL,current_user='hnuhole_c_runtime'`).Scan(&installed, &runtime); err != nil {
		return ErrAuthorizationUnavailable
	}
	if !installed {
		return nil
	}
	if err := pool.QueryRow(ctx, `SELECT to_regclass('c_moderation.legacy_restrictions') IS NOT NULL AND to_regclass('c_moderation.sanctions') IS NOT NULL`).Scan(&ok); err != nil || !ok {
		return ErrAuthorizationUnavailable
	}
	if !runtime {
		return nil
	}
	if err := pool.QueryRow(ctx, `SELECT has_table_privilege(current_user,'c_moderation.legacy_restrictions','SELECT') AND NOT has_table_privilege(current_user,'c_moderation.legacy_restrictions','INSERT,DELETE,TRUNCATE,TRIGGER,REFERENCES') AND NOT has_schema_privilege(current_user,'c_moderation','CREATE') AND NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='c_moderation.legacy_restrictions'::regclass AND attnum>0 AND NOT attisdropped AND (has_column_privilege(current_user,attrelid,attname,'INSERT')<>(attname=ANY(ARRAY['account_id','ban_state','ban_ends_at','mute_state','mute_ends_at'])) OR has_column_privilege(current_user,attrelid,attname,'UPDATE')<>(attname=ANY(ARRAY['ban_state','ban_ends_at','mute_state','mute_ends_at'])))) AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['account_id','action','revoked_at','ends_at']) AS c(name) WHERE NOT has_column_privilege(current_user,'c_moderation.sanctions',c.name,'SELECT'))`).Scan(&ok); err != nil || !ok {
		return ErrAuthorizationUnavailable
	}
	return nil
}
