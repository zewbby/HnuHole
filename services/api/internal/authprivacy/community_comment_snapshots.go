package authprivacy

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/readtiming"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/commentsnapshot"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func commentSnapshotError(err error) error {
	var quota *commentsnapshot.QuotaError
	switch {
	case err == nil:
		return nil
	case errors.As(err, &quota):
		return &PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: quota.RetryAfter}
	case errors.Is(err, commentsnapshot.ErrInvalid):
		return postError("CURSOR_INVALID", 400)
	case errors.Is(err, commentsnapshot.ErrRequest):
		return postError("MALFORMED_REQUEST", 400)
	case errors.Is(err, commentsnapshot.ErrTooLarge):
		return postError("COMMENT_SNAPSHOT_TOO_LARGE", 422)
	case errors.Is(err, commentsnapshot.ErrCapacity):
		return postError("COMMENT_SNAPSHOT_CAPACITY", 503)
	case errors.Is(err, commentsnapshot.ErrIntegrity):
		return postError("COMMENT_SNAPSHOT_INTEGRITY", 503)
	default:
		return postError("COMMENT_SNAPSHOT_UNAVAILABLE", 503)
	}
}
func snapshotNonce(s string) ([]byte, error) {
	if s == "" {
		b := make([]byte, 16)
		if _, e := rand.Read(b); e != nil {
			return nil, commentsnapshot.ErrUnavailable
		}
		return b, nil
	}
	b, e := base64.RawURLEncoding.Strict().DecodeString(s)
	if e != nil || len(b) != 16 || base64.RawURLEncoding.EncodeToString(b) != s {
		return nil, commentsnapshot.ErrRequest
	}
	if [16]byte(b) == ([16]byte{}) {
		return nil, commentsnapshot.ErrRequest
	}
	return b, nil
}
func (c *Community) legacySnapshotUsage(ctx context.Context, tx pgx.Tx, account uuid.UUID, at time.Time) (commentsnapshot.LegacyUsage, error) {
	defer readtiming.Span(ctx, "legacy_usage")()
	var usage commentsnapshot.LegacyUsage
	var until *time.Time
	e := tx.QueryRow(ctx, `SELECT count(*),min(expires_at) FROM c_comments.snapshots WHERE owner_account_id=$1 AND expires_at>$2`, account, at).Scan(&usage.Count, &until)
	if e != nil {
		return usage, e
	}
	usage.RetryAfter = 1
	if until != nil {
		usage.RetryAfter = max(1, int(until.Sub(at).Seconds()+.999))
	}
	return usage, nil
}
func (c *Community) loadPGSnapshot(ctx context.Context, tx pgx.Tx, account uuid.UUID, scope commentsnapshot.Scope, ref commentsnapshot.Ref, at time.Time, legacy bool) (commentsnapshot.Snapshot, error) {
	var root any
	if scope.Root != uuid.Nil {
		root = scope.Root
	}
	var ids []uuid.UUID
	var expires time.Time
	e := tx.QueryRow(ctx, `SELECT comment_ids,expires_at FROM c_comments.snapshots WHERE snapshot_id=$1 AND owner_account_id=$2 AND post_id=$3 AND root_comment_id IS NOT DISTINCT FROM $4::uuid AND expires_at>$5`, ref.ID, account, scope.Post, root, at).Scan(&ids, &expires)
	if errors.Is(e, pgx.ErrNoRows) {
		return commentsnapshot.Snapshot{}, postError("CURSOR_INVALID", 400)
	}
	if e != nil {
		return commentsnapshot.Snapshot{}, e
	}
	if !legacy && !expires.Equal(ref.Expires) {
		return commentsnapshot.Snapshot{}, postError("CURSOR_INVALID", 400)
	}
	ref.Expires = expires
	if len(ids) > 10000 {
		return commentsnapshot.Snapshot{}, postError("COMMENT_SNAPSHOT_INTEGRITY", 503)
	}
	return commentsnapshot.Snapshot{Ref: ref, Scope: scope, Created: expires.Add(-30 * time.Minute), IDs: ids}, nil
}
func (c *Community) orderedCommentIDs(ctx context.Context, tx pgx.Tx, scope commentsnapshot.Scope) ([]uuid.UUID, error) {
	defer readtiming.Span(ctx, "ordered_ids")()
	var root any
	if scope.Root != uuid.Nil {
		root = scope.Root
	}
	rows, e := tx.Query(ctx, `SELECT t.comment_id::text,x.terminal_at,(SELECT count(*) FROM c_comments.likes l WHERE l.comment_id=t.comment_id) FROM c_comments.tasks t JOIN c_comments.attempts x USING(task_id) WHERE t.post_id=$1 AND t.root_comment_id IS NOT DISTINCT FROM $2::uuid AND x.state='PUBLISHED' AND t.deleted_at IS NULL AND NOT COALESCE((to_jsonb(t)->>'moderation_hidden')::boolean,false) AND NOT EXISTS(SELECT 1 FROM c_comments.tasks root_row WHERE root_row.comment_id=t.root_comment_id AND (root_row.deleted_at IS NOT NULL OR COALESCE((to_jsonb(root_row)->>'moderation_hidden')::boolean,false))) LIMIT 10001`, scope.Post, root)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	order := []comments.OrderItem{}
	for rows.Next() {
		var item comments.OrderItem
		if e = rows.Scan(&item.CommentID, &item.PublishedAt, &item.LikeCount); e != nil {
			return nil, e
		}
		order = append(order, item)
	}
	if e = rows.Err(); e != nil {
		return nil, e
	}
	if len(order) > 10000 {
		return nil, postError("COMMENT_SNAPSHOT_TOO_LARGE", 422)
	}
	sorted, e := comments.NewSortedSnapshot(scope.Kind, order, scope.Sort)
	if e != nil {
		return nil, e
	}
	ids := make([]uuid.UUID, 0, len(order))
	for offset := 0; offset < sorted.Len(); offset += 50 {
		page, e := sorted.Page(offset, 50)
		if e != nil {
			return nil, e
		}
		for _, item := range page.Items {
			ids = append(ids, uuid.MustParse(item.CommentID))
		}
	}
	return ids, nil
}

func (c *Community) readCommentsWithSnapshots(ctx context.Context, bearer [32]byte, q CommentQuery, locate string) (PostResponse, error) {
	ctx = readtiming.Phase(ctx, "comments")
	defer readtiming.Span(ctx, "total")()
	cfg := *c.comments.snapshotConfig
	ctx = commentsnapshot.WithBudget(ctx, cfg.OperationBudgetMilliseconds)
	var timing CommentReadTiming
	var observedAt time.Time
	if c.comments.observeRead != nil {
		observedAt = time.Now()
		timing.Path = "initial"
		if q.Cursor != "" {
			timing.Path = "continuation"
		}
		if q.Replies {
			timing.Path = "reply_preview"
			if q.Expanded {
				timing.Path = "reply_expanded"
			}
		}
		defer func() { timing.Total = time.Since(observedAt); c.comments.observeRead(timing) }()
	}
	if _, e := posts.ParseResourceID(q.ID); e != nil {
		return PostResponse{}, e
	}
	if locate != "" {
		if _, e := posts.ParseResourceID(locate); e != nil {
			return PostResponse{}, e
		}
	}
	if !q.Sort.Valid() || (q.Sort != "" && (q.Cursor != "" || q.Replies)) || (q.Cursor != "" && q.SnapshotRequest != "") {
		return PostResponse{}, comments.ErrInvalid
	}
	if q.Limit == 0 {
		q.Limit = 50
	}
	if q.Limit < 1 || q.Limit > 50 {
		return PostResponse{}, comments.ErrInvalid
	}
	nonce, e := snapshotNonce(q.SnapshotRequest)
	if e != nil {
		return PostResponse{}, commentSnapshotError(e)
	}
	var prepared *commentsnapshot.Prepared
	var ref commentsnapshot.Ref
	var next *int
	legacyCursor := false
	var transactionAt time.Time
	if c.comments.observeRead != nil {
		transactionAt = time.Now()
	}
	response, err := c.withCommentSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		defer readtiming.Span(ctx, "business_action")()
		post := q.ID
		root := uuid.Nil
		kind := comments.MainComments
		if q.Replies {
			root = uuid.MustParse(q.ID)
			kind = comments.Replies
			e := tx.QueryRow(ctx, `SELECT t.post_id::text FROM c_comments.tasks t JOIN c_comments.attempts x USING(task_id) WHERE t.comment_id=$1 AND t.root_comment_id IS NULL AND t.deleted_at IS NULL AND NOT COALESCE((to_jsonb(t)->>'moderation_hidden')::boolean,false) AND x.state='PUBLISHED'`, root).Scan(&post)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("COMMENT_NOT_FOUND", 404)
			}
			if e != nil {
				return nil, e
			}
			if q.PostID != "" && q.PostID != post {
				return nil, postError("COMMENT_NOT_FOUND", 404)
			}
		}
		var visible bool
		if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.posts WHERE post_id=$1 AND visibility='PUBLISHED' AND NOT moderation_hidden)`, post).Scan(&visible); e != nil {
			return nil, e
		}
		if !visible {
			return nil, postError("POST_NOT_FOUND", 404)
		}
		scope := commentsnapshot.Scope{Owner: commentsnapshot.OwnerToken(c.comments.codec.IntentFingerprint, account, cfg.Redis.Namespace), Post: uuid.MustParse(post), Root: root, Kind: kind, Sort: commentsnapshot.NormalizeSort(q.Sort)}
		var snapshot commentsnapshot.Snapshot
		offset := 0
		if q.Cursor != "" {
			decoded, decodeErr := base64.RawURLEncoding.Strict().DecodeString(q.Cursor)
			if decodeErr == nil && len(decoded) == 52 {
				id, o, e := c.parseCommentCursor(q.Cursor)
				if e != nil {
					return nil, e
				}
				offset = o
				ref = commentsnapshot.Ref{Backend: commentsnapshot.Postgres, ID: id, Kind: kind, Sort: scope.Sort}
				legacyCursor = true
			} else {
				var e error
				ref, offset, e = commentsnapshot.DecodeCursor(c.comments.codec.IntentFingerprint, q.Cursor)
				if e != nil {
					return nil, commentSnapshotError(e)
				}
				if ref.Kind != kind || !ref.Expires.After(d.TrustedAt) {
					return nil, postError("CURSOR_INVALID", 400)
				}
				scope.Sort = ref.Sort
			}
			if ref.Backend == commentsnapshot.Redis {
				if !cfg.ReadRedis {
					return nil, postError("CURSOR_INVALID", 400)
				}
				var e error
				snapshot, e = c.comments.snapshotStore.Load(ctx, scope, ref, d.TrustedAt)
				if e != nil {
					return nil, commentSnapshotError(e)
				}
			} else {
				if !cfg.ReadPostgres {
					return nil, postError("CURSOR_INVALID", 400)
				}
				var e error
				snapshot, e = c.loadPGSnapshot(ctx, tx, account, scope, ref, d.TrustedAt, legacyCursor)
				if e != nil {
					return nil, e
				}
				ref = snapshot.Ref
			}
			if offset > len(snapshot.IDs) {
				return nil, postError("CURSOR_INVALID", 400)
			}
		} else {
			var reused *commentsnapshot.Snapshot
			ids, e := c.orderedCommentIDs(ctx, tx, scope)
			if e != nil {
				var limitError *PostError
				if cfg.CreateBackend == "redis" && errors.As(e, &limitError) && limitError.Code == "COMMENT_SNAPSHOT_TOO_LARGE" {
					old, found, lookupError := c.comments.snapshotStore.Lookup(ctx, scope, commentsnapshot.Request(c.comments.codec.IntentFingerprint, scope.Owner, scope, nonce), d.TrustedAt)
					if lookupError != nil {
						return nil, commentSnapshotError(lookupError)
					}
					if found {
						reused = &old
						e = nil
					}
				}
				if e != nil {
					return nil, e
				}
			}
			at := d.TrustedAt.UTC().Truncate(time.Millisecond)
			ref = commentsnapshot.Ref{Backend: commentsnapshot.Postgres, ID: uuid.New(), Expires: at.Add(30 * time.Minute), Kind: kind, Sort: scope.Sort}
			snapshot = commentsnapshot.Snapshot{Ref: ref, Scope: scope, Created: at, IDs: ids}
			legacy := commentsnapshot.LegacyUsage{}
			if cfg.ReadPostgres {
				legacy, e = c.legacySnapshotUsage(ctx, tx, account, d.TrustedAt)
				if e != nil {
					return nil, e
				}
			}
			if cfg.CreateBackend == "redis" {
				if reused != nil {
					snapshot = *reused
				} else {
					p, prepareError := c.comments.snapshotStore.Prepare(ctx, snapshot, commentsnapshot.Request(c.comments.codec.IntentFingerprint, scope.Owner, scope, nonce), legacy)
					prepared = &p
					if prepareError != nil {
						return nil, commentSnapshotError(prepareError)
					}
					snapshot = p.Snapshot
				}
				ref = snapshot.Ref
			} else {
				legacyCursor = cfg.PostgresCursorVersion != 2
				if _, e = commentsnapshot.Encode(c.comments.codec.IntentFingerprint, snapshot, cfg.MaxSnapshotBytes); e != nil {
					return nil, commentSnapshotError(e)
				}
				redisUsage := commentsnapshot.Usage{}
				if cfg.ReadRedis {
					redisUsage, e = c.comments.snapshotStore.Usage(ctx, scope.Owner)
					if e != nil {
						return nil, commentSnapshotError(e)
					}
				}
				if legacy.Count+redisUsage.AccountCount >= cfg.MaxPerAccount {
					wait := redisUsage.RetryAfter
					if legacy.Count > 0 {
						wait = legacy.RetryAfter
					}
					if legacy.Count > 0 && redisUsage.AccountCount > 0 {
						wait = min(wait, redisUsage.RetryAfter)
					}
					return nil, &PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: max(1, wait)}
				}
				var rootValue any
				if root != uuid.Nil {
					rootValue = root
				}
				if _, e = tx.Exec(ctx, `DELETE FROM c_comments.snapshots WHERE owner_account_id=$1 AND expires_at<=$2`, account, d.TrustedAt); e != nil {
					return nil, e
				}
				if _, e = tx.Exec(ctx, `INSERT INTO c_comments.snapshots(snapshot_id,owner_account_id,post_id,root_comment_id,comment_ids,expires_at) VALUES($1,$2,$3,$4,$5,$6)`, ref.ID, account, scope.Post, rootValue, snapshot.IDs, ref.Expires); e != nil {
					return nil, e
				}
			}
			if q.Replies && q.Expanded {
				offset = min(5, len(snapshot.IDs))
			}
		}
		if locate != "" {
			row, e := readTextComment(ctx, tx, locate, account)
			if errors.Is(e, pgx.ErrNoRows) || (e == nil && row.PostID != post) {
				return nil, postError("COMMENT_NOT_FOUND", 404)
			}
			if e != nil {
				return nil, e
			}
			floor := row.ID
			if row.RootCommentID != nil {
				floor = *row.RootCommentID
			}
			for index, id := range snapshot.IDs {
				if id.String() == floor {
					n := index / 50 * 50
					next = &n
					return CommentLocation{SnapshotID: base64.RawURLEncoding.EncodeToString(ref.ID[:]), CommentID: locate, RootCommentID: row.RootCommentID}, nil
				}
			}
			return nil, postError("COMMENT_NOT_FOUND", 404)
		}
		limit := q.Limit
		if q.Replies && !q.Expanded {
			limit = 5
			if offset != 0 {
				return nil, postError("CURSOR_INVALID", 400)
			}
		}
		page := TextCommentPage{SnapshotID: base64.RawURLEncoding.EncodeToString(ref.ID[:]), Comments: []TextComment{}}
		for scanned := 0; scanned < 3 && offset < len(snapshot.IDs); scanned++ {
			end := min(offset+limit, len(snapshot.IDs))
			for _, id := range snapshot.IDs[offset:end] {
				item, e := readTextComment(ctx, tx, id.String(), account)
				if errors.Is(e, pgx.ErrNoRows) {
					continue
				}
				if e != nil {
					return nil, e
				}
				if item.PostID != post || (root == uuid.Nil && item.RootCommentID != nil) || (root != uuid.Nil && (item.RootCommentID == nil || *item.RootCommentID != root.String())) {
					return nil, postError("COMMENT_SNAPSHOT_INTEGRITY", 503)
				}
				page.Comments = append(page.Comments, item)
			}
			offset = end
			if len(page.Comments) > 0 {
				break
			}
		}
		if offset < len(snapshot.IDs) {
			n := offset
			next = &n
		}
		if q.Replies {
			remaining := len(snapshot.IDs) - offset
			page.RootCommentID = &q.ID
			page.RemainingCount = &remaining
		} else {
			counts, e := readVisibleCommentCounts(ctx, tx, []string{post})
			if e != nil {
				return nil, e
			}
			count := counts[post]
			page.TotalCount = &count
		}
		return page, nil
	})
	if c.comments.observeRead != nil {
		timing.Transaction = time.Since(transactionAt)
		timing.StoreInTransaction = commentsnapshot.BudgetElapsed(ctx)
		timing.SQLGateProjection = max(0, timing.Transaction-timing.StoreInTransaction)
		timing.Backend = "postgres"
		if ref.Backend == commentsnapshot.Redis {
			timing.Backend = "redis"
		}
	}
	if err != nil {
		if prepared != nil && prepared.NewlyCreated {
			cleanup, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
			_ = c.comments.snapshotStore.Abort(cleanup, *prepared)
			cancel()
		}
		return PostResponse{}, err
	}
	if prepared != nil {
		var publishAt time.Time
		if c.comments.observeRead != nil {
			publishAt = time.Now()
		}
		publishError := c.comments.snapshotStore.Publish(ctx, *prepared)
		if c.comments.observeRead != nil {
			timing.Publish = time.Since(publishAt)
		}
		if publishError != nil {
			return PostResponse{}, commentSnapshotError(publishError)
		}
	}
	if next != nil {
		var cursor string
		if legacyCursor {
			cursor = c.commentCursor(ref.ID, *next)
		} else {
			var e error
			cursor, e = commentsnapshot.EncodeCursor(c.comments.codec.IntentFingerprint, ref, *next)
			if e != nil {
				return PostResponse{}, commentSnapshotError(e)
			}
		}
		switch value := response.Value.(type) {
		case TextCommentPage:
			value.NextCursor = &cursor
			response.Value = value
		case CommentLocation:
			value.Cursor = &cursor
			response.Value = value
		}
	}
	timing.Succeeded = true
	return response, nil
}
