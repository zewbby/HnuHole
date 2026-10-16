package authprivacy

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

// Real bytes exist before image upload APIs are switched off. The ordinary
// runtime still has to stop publication and erase only the affected account's
// bytes, without acquiring upload verification or tombstone-revival authority.
func TestPostImagesTextOnlyRuntimeLifecycleErasurePostgres(t *testing.T) {
	dsn := os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN")
	if dsn == "" {
		t.Skip("private runtime DSN absent")
	}
	for _, cause := range []string{"cancel", "delete", "ban", "identity", "closure", "formal-closure"} {
		t.Run(cause, func(t *testing.T) {
			control := newGateControl(t)
			l, ctx := control.lab, context.Background()
			enablePostLab(t, l)
			enableImageLab(t, l)
			owner := sessionTestAccount(t, l, "image_terminal_owner")
			other := sessionTestAccount(t, l, "image_terminal_other")
			id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "待清理身份").IdentityID
			identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "保留身份")
			otherID := identityChange(t, l.c, other.SessionToken, "CREATE", uuid.Nil, "其他账号身份").IdentityID
			selection, data := imageFixture(t, "png")
			intent := postTestIntent(t, l, id)
			intent.Images = []postmedia.Selection{selection}
			r := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
			imageUpload(t, l, r, selection, imageGrant(t, l, owner.SessionToken, r, selection.MediaID), data)
			otherIntent := postTestIntent(t, l, otherID)
			otherSelection := selection
			otherSelection.MediaID = uuid.NewString()
			otherIntent.Images = []postmedia.Selection{otherSelection}
			otherPost := postTestCommand(t, l, other.SessionToken, postTestKey(t), otherIntent)
			imageUpload(t, l, otherPost, otherSelection, imageGrant(t, l, other.SessionToken, otherPost, otherSelection.MediaID), data)
			if cause == "delete" {
				postTestPublish(t, l)
			}
			mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
			grants, err := os.ReadFile("../../../../infra/postgres/grant-community.sql")
			if err != nil {
				t.Fatal(err)
			}
			mustExec(t, l.cp, string(grants))
			config, err := pgxpool.ParseConfig(dsn)
			if err != nil || config.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") {
				t.Fatal("restricted-role fixture DSN marker absent")
			}
			runtime, err := pgxpool.NewWithConfig(ctx, config)
			if err != nil {
				t.Fatal(err)
			}
			defer runtime.Close()
			var database, user string
			var address *string
			if err = runtime.QueryRow(ctx, `SELECT current_database(),current_user,inet_server_addr()::text`).Scan(&database, &user, &address); err != nil || database != "hnuhole_c" || user != "hnuhole_c_runtime" || address != nil {
				t.Fatal("terminal image checks require this isolated private-socket runtime database")
			}
			if err = checkPostSchema(ctx, runtime); err != nil {
				t.Fatal(err)
			}
			copyCommunity := *l.c
			copyCommunity.pool, copyCommunity.postImages = runtime, nil
			l.c = &copyCommunity
			if l.c.PostImagesEnabled() {
				t.Fatal("image API must remain disabled")
			}
			if _, err = l.c.WithPostImages(ctx, imageValidator(t)); !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatal("text grants unexpectedly enabled upload API", err)
			}
			for _, sql := range []string{`INSERT INTO c_posts.images SELECT * FROM c_posts.images WHERE false`, `UPDATE c_posts.images SET verified_at=clock_timestamp()`, `UPDATE c_posts.images SET digest=decode(repeat('22',32),'hex')`} {
				_, err = runtime.Exec(ctx, sql)
				var pe *pgconn.PgError
				if !errors.As(err, &pe) || pe.Code != "42501" {
					t.Fatal("text runtime acquired upload authority", err)
				}
			}
			switch cause {
			case "cancel":
				postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.Cancel, TaskID: r.TaskID, ExpectedAttemptVersion: 1})
			case "delete":
				postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: r.PostID})
			case "ban":
				if err = l.c.ApplyAccountBan(ctx, owner.AccountID, 1, nil); err != nil {
					t.Fatal(err)
				}
			case "identity":
				identityChange(t, l.c, owner.SessionToken, "DELETE", id, "")
			case "closure", "formal-closure":
				request, _ := closureTestRequest(t, owner.SessionToken)
				closure, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
				if err != nil {
					t.Fatal(err)
				}
				if cause == "formal-closure" {
					advanceClosureClock(t, control, closure.DueAt)
					if n, err := l.c.FinalizeDueClosures(ctx, 10); err != nil || n != 1 {
						t.Fatal("formal close failed", n, err)
					}
				}
			}
			if cause != "formal-closure" {
				postTestPublish(t, l)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_posts.images WHERE task_id=$1 AND payload IS NULL AND erased_at IS NOT NULL AND grant_digest IS NULL AND grant_expires_at IS NULL`, r.TaskID) != 1 {
				t.Fatal("disabled image API prevented terminal byte erasure")
			}
			if count(t, l.cp, `SELECT count(*) FROM c_posts.images WHERE task_id=$1 AND payload IS NOT NULL AND erased_at IS NULL`, otherPost.TaskID) != 1 {
				t.Fatal("terminal action erased another account's image")
			}
			_, err = runtime.Exec(ctx, `UPDATE c_posts.images SET payload=$2,erased_at=NULL WHERE task_id=$1`, r.TaskID, data)
			var pe *pgconn.PgError
			if !errors.As(err, &pe) || pe.Code != "23514" {
				t.Fatal("erased image was revived through lifecycle columns", err)
			}
		})
	}
}
