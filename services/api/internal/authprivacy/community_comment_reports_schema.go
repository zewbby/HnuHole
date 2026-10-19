package authprivacy

import (
	"context"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Optional before 0018. Once installed, neither an old configuration nor a
// disabled feature can bypass its deletion/publication lifecycle hooks.
func checkCommentModerationSchema(ctx context.Context, pool *pgxpool.Pool, requireWrite bool) error {
	var cases, tasks, runtime, ok bool
	e := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('c_moderation.cases') AND attname='comment_id' AND NOT attisdropped),EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('c_comments.tasks') AND attname='moderation_hidden' AND NOT attisdropped),current_user='hnuhole_c_runtime'`).Scan(&cases, &tasks, &runtime)
	if e != nil {
		return errPostSchema
	}
	if !cases && !tasks {
		return nil
	}
	if !cases || !tasks {
		return errPostSchema
	}
	for _, spec := range [][3]string{{"c_comments.tasks", "moderation_comment_deleted", "deleted_comment"}, {"c_comments.attempts", "moderation_comment_publication", "comment_publication_guard"}} {
		if e = pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_namespace n ON n.oid=p.pronamespace WHERE t.tgrelid=to_regclass($1) AND t.tgname=$2 AND t.tgenabled='O' AND NOT t.tgisinternal AND n.nspname='c_moderation' AND p.proname=$3)`, spec[0], spec[1], spec[2]).Scan(&ok); e != nil || !ok {
			return errPostSchema
		}
	}
	if e = pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='c_moderation.cases'::regclass AND attname='comment_id' AND atttypid='uuid'::regtype AND NOT attisdropped) AND EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='c_comments.tasks'::regclass AND attname='moderation_hidden' AND atttypid='boolean'::regtype AND attnotnull AND NOT attisdropped)`).Scan(&ok); e != nil || !ok {
		return errPostSchema
	}
	if runtime {
		if e = pool.QueryRow(ctx, `SELECT has_column_privilege(current_user,'c_moderation.cases','comment_id','SELECT') AND has_table_privilege(current_user,'c_comments.tasks','SELECT') AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['state','outcome','explanation','version']) c(name) WHERE NOT has_column_privilege(current_user,'c_moderation.cases',name,'UPDATE')) AND has_table_privilege(current_user,'c_moderation.reports','SELECT') AND has_table_privilege(current_user,'c_moderation.notifications','INSERT') AND (NOT $1::boolean OR has_column_privilege(current_user,'c_comments.tasks','moderation_hidden','UPDATE'))`, requireWrite).Scan(&ok); e != nil || !ok {
			return errPostSchema
		}
	}
	return nil
}
