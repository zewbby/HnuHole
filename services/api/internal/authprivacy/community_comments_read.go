package authprivacy

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type CommentQuery struct {
	ID, PostID, Cursor string
	Replies, Expanded bool
	Limit             int
}
type CommentAuthor struct {
	Ref      string `json:"ref"`
	Nickname string `json:"nickname"`
	Avatar   string `json:"avatar"`
	State    string `json:"state"`
}
type CommentRelation struct {
	CommentID string        `json:"commentId"`
	Author    CommentAuthor `json:"author"`
}
type TextComment struct {
	ID              string           `json:"id"`
	PostID          string           `json:"postId"`
	RootCommentID   *string          `json:"rootCommentId"`
	TargetCommentID *string          `json:"targetCommentId"`
	Body            string           `json:"body"`
	Image           any              `json:"image"`
	Author          CommentAuthor    `json:"author"`
	ReplyTo         *CommentRelation `json:"replyTo"`
	IsPostAuthor    bool             `json:"isPostAuthor"`
	PublishedAt     time.Time        `json:"publishedAt"`
	LikeCount       int64            `json:"likeCount"`
	LikedByMe       bool             `json:"likedByMe"`
	ReplyCount      int              `json:"replyCount"`
}
type TextCommentPage struct {
	SnapshotID     string        `json:"snapshotId"`
	RootCommentID  *string       `json:"rootCommentId,omitempty"`
	Comments       []TextComment `json:"comments"`
	NextCursor     *string       `json:"nextCursor"`
	TotalCount     *int          `json:"totalCount,omitempty"`
	RemainingCount *int          `json:"remainingCount,omitempty"`
}

func commentCursor(id uuid.UUID, offset int) string {
	b := make([]byte, 20)
	copy(b, id[:])
	binary.BigEndian.PutUint32(b[16:], uint32(offset))
	return base64.RawURLEncoding.EncodeToString(b)
}
func parseCommentCursor(s string) (uuid.UUID, int, error) {
	b, e := base64.RawURLEncoding.Strict().DecodeString(s)
	if e != nil || len(b) != 20 || base64.RawURLEncoding.EncodeToString(b) != s {
		return uuid.Nil, 0, postError("CURSOR_INVALID", 400)
	}
	var id uuid.UUID
	copy(id[:], b[:16])
	offset := binary.BigEndian.Uint32(b[16:])
	if id == uuid.Nil || offset > 10000 {
		return uuid.Nil, 0, postError("CURSOR_INVALID", 400)
	}
	return id, int(offset), nil
}
func (c *Community) ReadComments(ctx context.Context, b [32]byte, q CommentQuery) (PostResponse, error) {
	if _, e := posts.ParseResourceID(q.ID); e != nil {
		return PostResponse{}, e
	}
	if q.Limit == 0 {
		q.Limit = 50
	}
	if q.Limit < 1 || q.Limit > 50 {
		return PostResponse{}, comments.ErrInvalid
	}
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, account uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		postID := q.ID
		var root any
		if q.Replies {
			root = q.ID
			e := tx.QueryRow(ctx, `SELECT t.post_id::text FROM c_comments.tasks t JOIN c_comments.attempts x USING(task_id) WHERE t.comment_id=$1 AND t.root_comment_id IS NULL AND x.state='PUBLISHED'`, q.ID).Scan(&postID)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("COMMENT_NOT_FOUND", 404)
			}
			if e != nil {
				return nil, e
			}
			if q.PostID!="" && q.PostID!=postID{return nil,postError("COMMENT_NOT_FOUND",404)}
		}
		var visible bool
		if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.posts WHERE post_id=$1 AND visibility='PUBLISHED')`, postID).Scan(&visible); e != nil {
			return nil, e
		}
		if !visible {
			return nil, postError("POST_NOT_FOUND", 404)
		}
		ids := []uuid.UUID{}
		snapshotID := uuid.New()
		offset := 0
		if q.Cursor != "" {
			var e error
			snapshotID, offset, e = parseCommentCursor(q.Cursor)
			if e != nil {
				return nil, e
			}
			e = tx.QueryRow(ctx, `SELECT comment_ids FROM c_comments.snapshots WHERE snapshot_id=$1 AND owner_account_id=$2 AND post_id=$3 AND root_comment_id IS NOT DISTINCT FROM $4::uuid AND expires_at>$5`, snapshotID, account, postID, root, d.TrustedAt).Scan(&ids)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("CURSOR_INVALID", 400)
			}
			if e != nil {
				return nil, e
			}
			if offset > len(ids) {
				return nil, postError("CURSOR_INVALID", 400)
			}
		} else {
			rows, e := tx.Query(ctx, `SELECT t.comment_id::text,x.terminal_at FROM c_comments.tasks t JOIN c_comments.attempts x USING(task_id) WHERE t.post_id=$1 AND t.root_comment_id IS NOT DISTINCT FROM $2::uuid AND x.state='PUBLISHED' LIMIT 10001`, postID, root)
			if e != nil {
				return nil, e
			}
			order := []comments.OrderItem{}
			for rows.Next() {
				var i comments.OrderItem
				if e = rows.Scan(&i.CommentID, &i.PublishedAt); e != nil {
					break
				}
				order = append(order, i)
			}
			if e == nil {
				e = rows.Err()
			}
			rows.Close()
			if e != nil {
				return nil, e
			}
			if len(order) > 10000 {
				return nil, postError("RATE_LIMITED", 429)
			}
			kind := comments.MainComments
			if q.Replies {
				kind = comments.Replies
			}
			snapshot, e := comments.NewSnapshot(kind, order)
			if e != nil {
				return nil, e
			}
			for i := 0; i < snapshot.Len(); i += 50 {
				page, e := snapshot.Page(i, 50)
				if e != nil {
					return nil, e
				}
				for _, item := range page.Items {
					ids = append(ids, uuid.MustParse(item.CommentID))
				}
			}
			if _, e = tx.Exec(ctx, `DELETE FROM c_comments.snapshots WHERE expires_at<=$1`, d.TrustedAt); e != nil {
				return nil, e
			}
			var count int
			if e = tx.QueryRow(ctx, `SELECT count(*) FROM c_comments.snapshots WHERE owner_account_id=$1`, account).Scan(&count); e != nil {
				return nil, e
			}
			if count >= 128 {
				return nil, &PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: 60}
			}
			if _, e = tx.Exec(ctx, `INSERT INTO c_comments.snapshots VALUES($1,$2,$3,$4,$5,$6)`, snapshotID, account, postID, root, ids, d.TrustedAt.Add(5*time.Minute)); e != nil {
				return nil, e
			}
			if q.Replies && q.Expanded {
				offset = min(5, len(ids))
			}
		}
		limit := q.Limit
		if q.Replies && !q.Expanded {
			limit = 5
			if offset != 0 {
				return nil, postError("CURSOR_INVALID", 400)
			}
		}
		end := min(offset+limit, len(ids))
		r := TextCommentPage{SnapshotID: base64.RawURLEncoding.EncodeToString(snapshotID[:]), Comments: []TextComment{}}
		for _, id := range ids[offset:end] {
			item, e := readTextComment(ctx, tx, id.String())
			if errors.Is(e, pgx.ErrNoRows) {
				continue
			}
			if e != nil {
				return nil, e
			}
			r.Comments = append(r.Comments, item)
		}
		if end < len(ids) {
			cursor := commentCursor(snapshotID, end)
			r.NextCursor = &cursor
		}
		if q.Replies {
			remaining := len(ids) - end
			r.RemainingCount = &remaining
			r.RootCommentID = &q.ID
		} else {
			var count int
			if e := tx.QueryRow(ctx, `SELECT count(*) FROM c_comments.tasks t JOIN c_comments.attempts x USING(task_id) WHERE t.post_id=$1 AND x.state='PUBLISHED'`, postID).Scan(&count); e != nil {
				return nil, e
			}
			r.TotalCount = &count
		}
		return r, nil
	})
}
func readCommentAuthor(ctx context.Context, tx pgx.Tx, identity string) (CommentAuthor, error) {
	var r CommentAuthor
	var nickname, avatar *string
	var deleted *time.Time
	var state string
	e := tx.QueryRow(ctx, `SELECT l.short_code,i.nickname,i.avatar,i.deleted_at,a.state FROM public.community_identities i JOIN c_auth.accounts a ON a.account_id=i.account_id JOIN c_posts.identity_public_labels l USING(identity_id) WHERE i.identity_id=$1`, identity).Scan(&r.Ref, &nickname, &avatar, &deleted, &state)
	if e != nil {
		return r, e
	}
	r.State = "ACTIVE"
	if state == "CLOSED" {
		r.State = "ACCOUNT_CLOSED"
	} else if deleted != nil {
		r.State = "IDENTITY_DELETED"
	}
	if r.State == "ACTIVE" {
		if nickname == nil || avatar == nil {
			return r, ErrAuthorizationUnavailable
		}
		r.Nickname = *nickname
		r.Avatar = *avatar
	} else {
		r.Nickname = "已停用身份 " + r.Ref
		r.Avatar = "inactive-v1"
	}
	return r, nil
}
func readTextComment(ctx context.Context, tx pgx.Tx, id string) (TextComment, error) {
	var r TextComment
	var identity string
	e := tx.QueryRow(ctx, `SELECT t.comment_id::text,t.post_id::text,t.root_comment_id::text,t.target_comment_id::text,x.body,x.terminal_at,t.identity_id::text,(t.identity_id=p.identity_id),CASE WHEN t.root_comment_id IS NULL THEN (SELECT count(*) FROM c_comments.tasks z JOIN c_comments.attempts a ON a.task_id=z.task_id AND a.state='PUBLISHED' WHERE z.root_comment_id=t.comment_id) ELSE 0 END FROM c_comments.tasks t JOIN c_comments.attempts x ON x.task_id=t.task_id AND x.state='PUBLISHED' JOIN c_posts.posts pp ON pp.post_id=t.post_id AND pp.visibility='PUBLISHED' JOIN c_posts.publication_tasks p ON p.post_id=t.post_id WHERE t.comment_id=$1`, id).Scan(&r.ID, &r.PostID, &r.RootCommentID, &r.TargetCommentID, &r.Body, &r.PublishedAt, &identity, &r.IsPostAuthor, &r.ReplyCount)
	if e != nil {
		return r, e
	}
	r.PublishedAt = r.PublishedAt.UTC()
	r.Author, e = readCommentAuthor(ctx, tx, identity)
	if e != nil {
		return r, e
	}
	if r.TargetCommentID != nil {
		var targetIdentity string
		if e = tx.QueryRow(ctx, `SELECT identity_id::text FROM c_comments.tasks WHERE comment_id=$1`, *r.TargetCommentID).Scan(&targetIdentity); e != nil {
			return r, e
		}
		author, e := readCommentAuthor(ctx, tx, targetIdentity)
		if e != nil {
			return r, e
		}
		r.ReplyTo = &CommentRelation{CommentID: *r.TargetCommentID, Author: author}
	}
	return r, nil
}
