package authprivacy

import (
	"context"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"os"
	"testing"
	"time"
)

func TestCommentBusinessMediaDeleteLikesNoticesPostgres(t *testing.T) {
	l := commentTextLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "cb_owner")
	other := sessionTestAccount(t, l, "cb_other")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "图片评论").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, id)
	// Exercise actual minimum grants rather than the owner connection.
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	for _, p := range []string{"../../../../infra/postgres/grant-community.sql", "../../../../infra/postgres/grant-comments.sql"} {
		b, e := os.ReadFile(p)
		if e != nil {
			t.Fatal(e)
		}
		mustExec(t, l.cp, string(b))
	}
	pool, e := pgxpool.New(ctx, os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	clone := *l.c
	clone.pool = pool
	l.c = &clone
	if e = l.c.CheckCommentSchema(ctx); e != nil {
		t.Fatal(e)
	}
	selection, data := imageFixture(t, "gif")
	in := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: id.String(), Image: &selection}
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), in)
	commentTextPublish(t, l)
	if commentTextOwn(t, l, owner.SessionToken, in.TaskID).State != comments.Accepted {
		t.Fatal("image published without verified bytes")
	}
	if _, e = l.c.UploadCommentImage(ctx, other.SessionToken, in.TaskID, 1, data, selection.MIME); e == nil {
		t.Fatal("foreign upload")
	}
	if _, e = l.c.UploadCommentImage(ctx, owner.SessionToken, in.TaskID, 1, data, selection.MIME); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.UploadCommentImage(ctx, owner.SessionToken, in.TaskID, 1, data, selection.MIME); e != nil {
		t.Fatal("idempotent upload", e)
	}
	commentTextPublish(t, l)
	own := commentTextOwn(t, l, owner.SessionToken, in.TaskID)
	if own.State != comments.Published {
		t.Fatal(own)
	}
	cid := *own.PublishedCommentID
	page, e := l.c.ReadComments(ctx, owner.SessionToken, CommentQuery{ID: post})
	if e != nil {
		t.Fatal(e)
	}
	item := page.Value.(TextCommentPage).Comments[0]
	image := item.Image.(PublishedCommentImage)
	if _, e = l.c.ReadCommentImage(ctx, other.SessionToken, post, cid, image.ContentVersionID); e != nil {
		t.Fatal(e)
	}
	yes := true
	like := comments.Intent{Operation: comments.SetLike, CommentID: cid, Liked: &yes}
	key := postTestKey(t)
	first := commentTextSend(t, l, other.SessionToken, key, like)
	again := commentTextSend(t, l, other.SessionToken, key, like)
	if *first.LikeCount != 1 || *again.LikeCount != 1 {
		t.Fatal("duplicate like")
	}
	commentTextSend(t, l, other.SessionToken, postTestKey(t), like)
	if count(t, l.cp, `SELECT count(*) FROM c_comments.likes WHERE comment_id=$1`, cid) != 1 {
		t.Fatal("account duplicated")
	}
	reply := comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: id.String(), RootCommentID: cid, TargetCommentID: cid, Body: "原对象"}
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), reply)
	commentTextPublish(t, l)
	rid := *commentTextOwn(t, l, owner.SessionToken, reply.TaskID).PublishedCommentID
	loc, e := l.c.LocateComment(ctx, owner.SessionToken, post, rid)
	if e != nil || loc.Value.(CommentLocation).RootCommentID == nil {
		t.Fatal("exact reply location", e)
	}
	// A real stop fails pending work and inserts the unified identity notification.
	pending := reply
	pending.TaskID = uuid.NewString()
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), pending)
	end := time.Now().Add(time.Hour)
	if e = l.c.ApplyAccountMute(ctx, owner.AccountID, 1, &end); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.notifications WHERE resource_id=$1 AND kind='COMMENT_FAILURE' AND identity_id=$2`, pending.TaskID, id) != 1 {
		t.Fatal("real failure notification absent")
	}
	abandoned := commentTextSend(t, l, owner.SessionToken, postTestKey(t), comments.Intent{Operation: comments.Abandon, TaskID: pending.TaskID, ExpectedAttemptVersion: 1})
	if abandoned.State != "APPLIED" {
		t.Fatal(abandoned)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.notifications WHERE resource_id=$1`, pending.TaskID) != 0 {
		t.Fatal("abandon retained notification")
	}
	// Muted owners may delete, other accounts may not. Root removes the floor.
	foreign := commentTextSend(t, l, other.SessionToken, postTestKey(t), comments.Intent{Operation: comments.DeleteComment, CommentID: cid})
	if foreign.State != "REJECTED" {
		t.Fatal("foreign delete")
	}
	removed := commentTextSend(t, l, owner.SessionToken, postTestKey(t), comments.Intent{Operation: comments.DeleteComment, CommentID: cid})
	if *removed.DeletedCount != 2 {
		t.Fatal(removed)
	}
	if _, e = l.c.ReadCommentImage(ctx, other.SessionToken, post, cid, image.ContentVersionID); e == nil {
		t.Fatal("deleted original readable")
	}
	if _, e = l.c.LocateComment(ctx, owner.SessionToken, post, rid); e == nil {
		t.Fatal("deleted reply locatable")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_comments.images WHERE task_id=$1 AND payload IS NOT NULL`, in.TaskID) != 0 {
		t.Fatal("original not erased")
	}
}
