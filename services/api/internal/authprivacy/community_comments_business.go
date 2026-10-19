package authprivacy

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"time"
)

// The caller holds its account lock. All mutations then lock the same post as
// acceptance/publication, so deleting a floor cannot race a new visible reply.
func (c *Community) applyCommentMutation(ctx context.Context, tx pgx.Tx, a uuid.UUID, in comments.Intent, at time.Time) (CommentReceipt, error) {
	var post, owner string
	var root *string
	var deleted *time.Time
	e := tx.QueryRow(ctx, `SELECT post_id::text,owner_account_id::text,root_comment_id::text,deleted_at FROM c_comments.tasks t WHERE comment_id=$1 AND EXISTS(SELECT 1 FROM c_comments.attempts x WHERE x.task_id=t.task_id AND x.state='PUBLISHED')`, in.CommentID).Scan(&post, &owner, &root, &deleted)
	if errors.Is(e, pgx.ErrNoRows) {
		return CommentReceipt{}, postError("COMMENT_TARGET_DELETED", 404)
	}
	if e != nil {
		return CommentReceipt{}, e
	}
	var visible bool
	e = tx.QueryRow(ctx, `SELECT visibility='PUBLISHED' AND NOT moderation_hidden FROM c_posts.posts WHERE post_id=$1 FOR UPDATE`, post).Scan(&visible)
	if e != nil {
		return CommentReceipt{}, e
	}
	if !visible {
		return CommentReceipt{}, postError("POST_UNAVAILABLE", 404)
	}
	if e = tx.QueryRow(ctx, `SELECT deleted_at FROM c_comments.tasks WHERE comment_id=$1`, in.CommentID).Scan(&deleted); e != nil {
		return CommentReceipt{}, e
	}
	if deleted != nil {
		return CommentReceipt{}, postError("COMMENT_TARGET_DELETED", 404)
	}
	r := CommentReceipt{State: "APPLIED", Operation: in.Operation, CommentID: in.CommentID}
	if in.Operation == comments.DeleteComment {
		if owner != a.String() {
			return CommentReceipt{}, postError("PERMISSION_DENIED", 403)
		}
		tag, e := tx.Exec(ctx, `UPDATE c_comments.tasks SET deleted_at=$2 WHERE deleted_at IS NULL AND (comment_id=$1 OR root_comment_id=$1 AND $3::boolean) AND EXISTS(SELECT 1 FROM c_comments.attempts x WHERE x.task_id=c_comments.tasks.task_id AND x.state='PUBLISHED')`, in.CommentID, at, root == nil)
		if e != nil {
			return CommentReceipt{}, e
		}
		count := tag.RowsAffected()
		r.DeletedCount = &count
	} else {
		var state string
		if e = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1`, a).Scan(&state); e != nil {
			return CommentReceipt{}, e
		}
		if state != "ACTIVE" {
			return CommentReceipt{}, postError("PERMISSION_DENIED", 403)
		}
		if *in.Liked {
			_, e = tx.Exec(ctx, `INSERT INTO c_comments.likes VALUES($1,$2) ON CONFLICT DO NOTHING`, a, in.CommentID)
		} else {
			_, e = tx.Exec(ctx, `DELETE FROM c_comments.likes WHERE account_id=$1 AND comment_id=$2`, a, in.CommentID)
		}
		if e != nil {
			return CommentReceipt{}, e
		}
		var count int64
		if e = tx.QueryRow(ctx, `SELECT count(*) FROM c_comments.likes WHERE comment_id=$1`, in.CommentID).Scan(&count); e != nil {
			return CommentReceipt{}, e
		}
		r.Liked = in.Liked
		r.LikeCount = &count
	}
	return r, nil
}

type CommentContext struct {
	TotalCount      int      `json:"totalCount"`
	BoundIdentityID *string  `json:"boundIdentityId"`
	OwnCommentIDs   []string `json:"ownCommentIds"`
}

func (c *Community) ReadCommentContext(ctx context.Context, b [32]byte, post string) (PostResponse, error) {
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		var visible bool
		if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.posts WHERE post_id=$1 AND visibility='PUBLISHED' AND NOT moderation_hidden)`, post).Scan(&visible); e != nil {
			return nil, e
		}
		if !visible {
			return nil, postError("POST_NOT_FOUND", 404)
		}
		r := CommentContext{OwnCommentIDs: []string{}}
		if e := tx.QueryRow(ctx, `SELECT count(*) FROM c_comments.tasks t JOIN c_comments.attempts x ON x.task_id=t.task_id AND x.state='PUBLISHED' WHERE t.post_id=$1 AND t.deleted_at IS NULL`, post).Scan(&r.TotalCount); e != nil {
			return nil, e
		}
		e := tx.QueryRow(ctx, `SELECT identity_id::text FROM c_posts.post_identity_bindings WHERE account_id=$1 AND post_id=$2`, a, post).Scan(&r.BoundIdentityID)
		if e != nil && !errors.Is(e, pgx.ErrNoRows) {
			return nil, e
		}
		rows, e := tx.Query(ctx, `SELECT comment_id::text FROM c_comments.tasks t WHERE owner_account_id=$1 AND post_id=$2 AND deleted_at IS NULL AND EXISTS(SELECT 1 FROM c_comments.attempts x WHERE x.task_id=t.task_id AND x.state='PUBLISHED')`, a, post)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		for rows.Next() {
			var id string
			if e = rows.Scan(&id); e != nil {
				return nil, e
			}
			r.OwnCommentIDs = append(r.OwnCommentIDs, id)
		}
		return r, rows.Err()
	})
}

type CommentMediaAck struct {
	Uploaded bool `json:"uploaded"`
}

func (c *Community) ReadOneComment(ctx context.Context, b [32]byte, post, id string) (PostResponse, error) {
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		row, e := readTextComment(ctx, tx, id, a)
		if errors.Is(e, pgx.ErrNoRows) || e == nil && row.PostID != post {
			return nil, postError("COMMENT_NOT_FOUND", 404)
		}
		return row, e
	})
}

type OwnCommentsPage struct {
	Items      []TextComment `json:"items"`
	NextCursor *string       `json:"nextCursor"`
}

func (c *Community) ReadOwnComments(ctx context.Context, b [32]byte, identity, cursor string) (PostResponse, error) {
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		var active bool
		if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE identity_id=$1 AND account_id=$2 AND deleted_at IS NULL)`, identity, a).Scan(&active); e != nil {
			return nil, e
		}
		if !active {
			return nil, postError("IDENTITY_UNAVAILABLE", 404)
		}
		var before *time.Time
		var cid any
		if cursor != "" {
			var at time.Time
			e := tx.QueryRow(ctx, `SELECT x.terminal_at FROM c_comments.tasks t JOIN c_comments.attempts x ON x.task_id=t.task_id AND x.state='PUBLISHED' WHERE t.comment_id=$1 AND t.owner_account_id=$2 AND t.identity_id=$3`, cursor, a, identity).Scan(&at)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("CURSOR_INVALID", 400)
			}
			if e != nil {
				return nil, e
			}
			before = &at
			cid = cursor
		}
		rows, e := tx.Query(ctx, `SELECT t.comment_id::text FROM c_comments.tasks t JOIN c_comments.attempts x ON x.task_id=t.task_id AND x.state='PUBLISHED' JOIN c_posts.posts p ON p.post_id=t.post_id AND p.visibility='PUBLISHED' AND NOT p.moderation_hidden WHERE t.owner_account_id=$1 AND t.identity_id=$2 AND t.deleted_at IS NULL AND ($3::timestamptz IS NULL OR (x.terminal_at,t.comment_id)<($3,$4::uuid)) ORDER BY x.terminal_at DESC,t.comment_id DESC LIMIT 21`, a, identity, before, cid)
		if e != nil {
			return nil, e
		}
		ids := []string{}
		for rows.Next() {
			var id string
			if e = rows.Scan(&id); e != nil {
				break
			}
			ids = append(ids, id)
		}
		if e == nil {
			e = rows.Err()
		}
		rows.Close()
		if e != nil {
			return nil, e
		}
		r := OwnCommentsPage{Items: []TextComment{}}
		if len(ids) > 20 {
			ids = ids[:20]
			r.NextCursor = commentString(ids[19])
		}
		for _, id := range ids {
			row, e := readTextComment(ctx, tx, id, a)
			if errors.Is(e, pgx.ErrNoRows) {
				continue
			}
			if e != nil {
				return nil, e
			}
			r.Items = append(r.Items, row)
		}
		return r, nil
	})
}

// Full byte validation happens before the final session/Gate transaction; the
// immutable manifest, current attempt, ownership and visibility are checked again.
func (c *Community) UploadCommentImage(ctx context.Context, b [32]byte, task string, version int32, data []byte, mime string) (PostResponse, error) {
	if !c.PostImagesEnabled() || version < 1 || len(data) < 1 || len(data) > postmedia.MaxBytes {
		return PostResponse{}, postmedia.ErrInvalid
	}
	// Reject unauthenticated/foreign/stale or manifest-mismatched traffic before
	// occupying the shared bounded decoder. Final authorization is repeated below.
	_, e := c.withCommentSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, m restriction) (any, error) {
		t, e := loadCommentTask(ctx, tx, a, task)
		if e != nil {
			return nil, e
		}
		v := t.View()
		if v.State != comments.Accepted || v.AttemptVersion != version || v.Content == nil || v.Content.Image == nil || mutedAt(m, d.TrustedAt) {
			return nil, postError("MEDIA_UPLOAD_CLOSED", 409)
		}
		s := v.Content.Image
		hash := sha256.Sum256(data)
		if s.ByteLength != len(data) || s.MIME != mime || s.SHA256 != hex.EncodeToString(hash[:]) {
			return nil, postmedia.ErrInvalid
		}
		if e = checkCommentContext(ctx, tx, a, v.Binding); e != nil {
			return nil, e
		}
		return CommentMediaAck{true}, nil
	})
	if e != nil {
		return PostResponse{}, e
	}
	metadata, e := c.postImages.validator.Inspect(ctx, data)
	if e != nil {
		return PostResponse{}, e
	}
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, m restriction) (any, error) {
		t, e := loadCommentTask(ctx, tx, a, task)
		if e != nil {
			return nil, e
		}
		v := t.View()
		if v.State != comments.Accepted || v.AttemptVersion != version || v.Content == nil || v.Content.Image == nil || mutedAt(m, d.TrustedAt) {
			return nil, postError("MEDIA_UPLOAD_CLOSED", 409)
		}
		if !metadata.Matches(*v.Content.Image, data) || mime != metadata.MIME {
			return nil, postmedia.ErrInvalid
		}
		if e = checkCommentContext(ctx, tx, a, v.Binding); e != nil {
			return nil, e
		}
		var generationOK bool
		if e = tx.QueryRow(ctx, `SELECT x.accepted_stop_generation=c.stop_generation FROM c_comments.attempts x,c_posts.account_publication_control c WHERE x.task_id=$1 AND x.version=$2 AND c.account_id=$3`, task, version, a).Scan(&generationOK); e != nil {
			return nil, e
		}
		if !generationOK {
			return nil, postError("MEDIA_UPLOAD_CLOSED", 409)
		}
		meta, _ := json.Marshal(metadata)
		tag, e := tx.Exec(ctx, `UPDATE c_comments.images SET payload=$3,metadata=$4 WHERE task_id=$1 AND version=$2 AND erased_at IS NULL AND payload IS NULL`, task, version, data, meta)
		if e != nil {
			return nil, e
		}
		if tag.RowsAffected() == 0 {
			var equal bool
			if e = tx.QueryRow(ctx, `SELECT payload=$3 AND erased_at IS NULL FROM c_comments.images WHERE task_id=$1 AND version=$2`, task, version, data).Scan(&equal); e != nil {
				return nil, e
			}
			if !equal {
				return nil, postError("MEDIA_UPLOAD_CLOSED", 409)
			}
		}
		return CommentMediaAck{true}, nil
	})
}

func (c *Community) ReadCommentImage(ctx context.Context, b [32]byte, post, comment, content string) (PostResponse, error) {
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, _ uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		var visible bool
		e := tx.QueryRow(ctx, `SELECT visibility='PUBLISHED' AND NOT moderation_hidden FROM c_posts.posts WHERE post_id=$1 FOR SHARE`, post).Scan(&visible)
		if errors.Is(e, pgx.ErrNoRows) || e == nil && !visible {
			return nil, postError("MEDIA_NOT_FOUND", 404)
		}
		if e != nil {
			return nil, e
		}
		var image ImageBytes
		e = tx.QueryRow(ctx, `SELECT m.payload,m.metadata->>'mimeType' FROM c_comments.tasks t JOIN c_comments.attempts x ON x.task_id=t.task_id AND x.state='PUBLISHED' JOIN c_comments.images m ON m.task_id=x.task_id AND m.version=x.version WHERE t.post_id=$1 AND t.comment_id=$2 AND m.content_version_id=$3 AND t.deleted_at IS NULL AND m.erased_at IS NULL AND m.payload IS NOT NULL FOR SHARE OF t`, post, comment, content).Scan(&image.Bytes, &image.MIME)
		if errors.Is(e, pgx.ErrNoRows) {
			return nil, postError("MEDIA_NOT_FOUND", 404)
		}
		return image, e
	})
}
