package authprivacy

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5/pgxpool"
)

func checkInboxLifecycleSchema(ctx context.Context, pool *pgxpool.Pool) error {
	var installed, ok, runtime bool
	if e := pool.QueryRow(ctx, `SELECT to_regnamespace('c_inbox') IS NOT NULL,current_user='hnuhole_c_runtime'`).Scan(&installed, &runtime); e != nil {
		return e
	}
	if !installed {
		return nil
	}
	for _, pair := range [][2]string{{"c_comments.attempts", "inbox_comment_published"}, {"c_posts.post_likes", "inbox_post_likes"}, {"c_comments.likes", "inbox_comment_likes"}, {"c_auth.accounts", "inbox_account_closed"}} {
		if e := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=to_regclass($1) AND tgname=$2 AND tgenabled='O')`, pair[0], pair[1]).Scan(&ok); e != nil || !ok {
			return errors.New("notification lifecycle hook unavailable")
		}
	}
	if runtime {
		e := pool.QueryRow(ctx, `SELECT has_schema_privilege(current_user,'c_inbox','USAGE') AND NOT has_schema_privilege(current_user,'c_inbox','CREATE')
   AND has_table_privilege(current_user,'c_inbox.records','SELECT') AND has_table_privilege(current_user,'c_inbox.like_events','SELECT')
   AND has_column_privilege(current_user,'c_moderation.notifications','read_at','UPDATE')
   AND NOT has_table_privilege(current_user,'c_inbox.records','INSERT,DELETE,TRIGGER,TRUNCATE')
   AND NOT has_table_privilege(current_user,'c_inbox.like_events','INSERT,UPDATE,DELETE,TRIGGER,TRUNCATE')
   AND has_column_privilege(current_user,'c_inbox.records','read_version','UPDATE') AND has_column_privilege(current_user,'c_inbox.records','seen_like_count','UPDATE')
   AND NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='c_inbox.records'::regclass AND attnum>0 AND NOT attisdropped AND attname NOT IN('read_version','seen_like_count') AND has_column_privilege(current_user,attrelid,attname,'UPDATE'))`).Scan(&ok)
		if e != nil || !ok {
			return errors.New("notification runtime grants unavailable")
		}
	}
	return nil
}
