package authprivacy

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type InboxQuery struct {
	IdentityID, Category, Cursor string
	UnreadOnly                   bool
	Limit                        int
}
type InboxNotice struct {
	ID         string  `json:"id"`
	Kind       string  `json:"kind"`
	IdentityID *string `json:"identityId"`
	IsReply    bool    `json:"isReply"`

	Unread          bool                     `json:"unread"`
	Version         int64                    `json:"version"`
	CreatedAt       time.Time                `json:"createdAt"`
	Title           string                   `json:"title"`
	Body            string                   `json:"body"`
	SourceTitle     string                   `json:"sourceTitle"`
	Actor           *CommentAuthor           `json:"actor"`
	PostID          *string                  `json:"postId"`
	CommentID       *string                  `json:"commentId"`
	TargetAvailable bool                     `json:"targetAvailable"`
	HasPostImage    bool                     `json:"hasPostImage"`
	NewLikeCount    int64                    `json:"newLikeCount"`
	System          *moderation.Notification `json:"system"`
}
type InboxPage struct {
	Items      []InboxNotice `json:"items"`
	NextCursor *string       `json:"nextCursor"`
}
type InboxCounts struct {
	All   int64 `json:"all"`
	Reply int64 `json:"reply"`

	Like           int64            `json:"like"`
	System         int64            `json:"system"`
	IdentityUnread map[string]int64 `json:"identityUnread"`
}
type InboxRead struct {
	ID          string `json:"id"`
	ReadVersion int64  `json:"readVersion"`
}
type inboxCursor struct {
	Identity, Category string
	Unread             bool
	At                 time.Time
	ID                 string
}

func inboxCategory(s string) bool {
	return s == "all" || s == "reply" || s == "like" || s == "system"
}
func inboxID(id string) bool {
	if len(id) != 38 || (id[:2] != "i_" && id[:2] != "s_") {
		return false
	}
	_, e := posts.ParseResourceID(id[2:])
	return e == nil
}
func (q *InboxQuery) validate() (inboxCursor, error) {
	var cursor inboxCursor
	if q.Category == "" {
		q.Category = "all"
	}
	if q.Limit == 0 {
		q.Limit = 30
	}
	if !inboxCategory(q.Category) || q.Limit < 1 || q.Limit > 50 {
		return cursor, ErrIntentInvalid
	}
	if q.IdentityID != "" {
		if _, e := posts.ParseResourceID(q.IdentityID); e != nil {
			return cursor, e
		}
	}
	if q.Cursor != "" {
		raw, e := base64.RawURLEncoding.DecodeString(q.Cursor)
		if e != nil || len(raw) > 1024 || json.Unmarshal(raw, &cursor) != nil || cursor.Identity != q.IdentityID || cursor.Category != q.Category || cursor.Unread != q.UnreadOnly || cursor.At.IsZero() || !inboxID(cursor.ID) {
			return cursor, ErrIntentInvalid
		}
	}
	return cursor, nil
}
func inboxIdentity(ctx context.Context, tx pgx.Tx, account uuid.UUID, identity string) error {
	if identity == "" {
		return nil
	}
	var ok bool
	if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE account_id=$1 AND identity_id=$2 AND deleted_at IS NULL)`, account, identity).Scan(&ok); e != nil {
		return e
	}
	if !ok {
		return postError("IDENTITY_UNAVAILABLE", 404)
	}
	return nil
}

// The recipient identity filters interactions only. Every system notice belongs
// to this authenticated account and is shared across its own identity selections.
const inboxRows = `WITH inbox AS (
 SELECT 'i_'||n.notification_id::text AS id,n.updated_at AS at,
 CASE WHEN n.kind='COMMENT' THEN 'comment' ELSE 'like' END AS kind,n.is_reply,
 CASE WHEN n.kind='COMMENT' THEN n.read_version=0 ELSE EXISTS(SELECT 1 FROM c_inbox.like_events e WHERE e.notification_id=n.notification_id AND e.version>n.read_version) END AS unread
 FROM c_inbox.records n JOIN public.community_identities i ON i.identity_id=n.identity_id
 WHERE n.account_id=$1 AND n.identity_id=$2::uuid AND i.deleted_at IS NULL
 AND (n.kind='COMMENT' OR n.seen_like_count>0 OR EXISTS(SELECT 1 FROM c_inbox.like_events e WHERE e.notification_id=n.notification_id))
 UNION ALL
 SELECT 's_'||n.notification_id::text,n.created_at,'system',false,n.read_at IS NULL
 FROM c_moderation.notifications n WHERE n.account_id=$1
 AND (n.identity_id IS NULL OR EXISTS(SELECT 1 FROM public.community_identities i WHERE i.identity_id=n.identity_id AND i.account_id=$1 AND i.deleted_at IS NULL))
) `

func (c *Community) ReadInbox(ctx context.Context, bearer [32]byte, q InboxQuery) (PostResponse, error) {
	cursor, e := q.validate()
	if e != nil {
		return PostResponse{}, e
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		if e := inboxIdentity(ctx, tx, account, q.IdentityID); e != nil {
			return nil, e
		}
		var before any
		if !cursor.At.IsZero() {
			before = cursor.At
		}
		rows, e := tx.Query(ctx, inboxRows+`SELECT id,at FROM inbox WHERE
 ($3='all' OR $3='reply' AND is_reply OR $3=kind)
 AND (NOT $4::boolean OR unread) AND ($5::timestamptz IS NULL OR (at,id)<($5,$6))
 ORDER BY at DESC,id DESC LIMIT $7`, account, nullablePostID(q.IdentityID), q.Category, q.UnreadOnly, before, cursor.ID, q.Limit+1)
		if e != nil {
			return nil, e
		}
		type key struct {
			id string
			at time.Time
		}
		var ids []key
		for rows.Next() {
			var k key
			if e = rows.Scan(&k.id, &k.at); e != nil {
				break
			}
			ids = append(ids, k)
		}
		if e == nil {
			e = rows.Err()
		}
		rows.Close()
		if e != nil {
			return nil, e
		}
		page := InboxPage{Items: []InboxNotice{}}
		if len(ids) > q.Limit {
			ids = ids[:q.Limit]
			last := ids[len(ids)-1]
			raw, _ := json.Marshal(inboxCursor{q.IdentityID, q.Category, q.UnreadOnly, last.at, last.id})
			next := base64.RawURLEncoding.EncodeToString(raw)
			page.NextCursor = &next
		}
		for _, k := range ids {
			n, e := readInboxNotice(ctx, tx, account, q.IdentityID, k.id)
			if e != nil {
				return nil, e
			}
			page.Items = append(page.Items, n)
		}
		return page, nil
	})
}
func (c *Community) ReadInboxCounts(ctx context.Context, bearer [32]byte, identity string) (PostResponse, error) {
	if identity != "" {
		if _, e := posts.ParseResourceID(identity); e != nil {
			return PostResponse{}, e
		}
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		if e := inboxIdentity(ctx, tx, account, identity); e != nil {
			return nil, e
		}
		var counts InboxCounts
		e := tx.QueryRow(ctx, inboxRows+`SELECT count(*),count(*) FILTER(WHERE is_reply),count(*) FILTER(WHERE kind='like'),count(*) FILTER(WHERE kind='system') FROM inbox WHERE unread`, account, nullablePostID(identity)).Scan(&counts.All, &counts.Reply, &counts.Like, &counts.System)
		if e != nil {
			return nil, e
		}
		counts.IdentityUnread = map[string]int64{}
		rows, e := tx.Query(ctx, `SELECT n.identity_id::text,count(*) FROM c_inbox.records n JOIN public.community_identities i ON i.identity_id=n.identity_id WHERE n.account_id=$1 AND i.deleted_at IS NULL AND (n.kind='COMMENT' AND n.read_version=0 OR n.kind<>'COMMENT' AND EXISTS(SELECT 1 FROM c_inbox.like_events e WHERE e.notification_id=n.notification_id AND e.version>n.read_version)) GROUP BY n.identity_id`, account)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		for rows.Next() {
			var id string
			var unread int64
			if e := rows.Scan(&id, &unread); e != nil {
				return nil, e
			}
			counts.IdentityUnread[id] = unread
		}
		return counts, rows.Err()
	})
}
func (c *Community) MarkInboxRead(ctx context.Context, bearer [32]byte, id, identity string, version int64) (PostResponse, error) {
	if !inboxID(id) || version < 1 {
		return PostResponse{}, ErrIntentInvalid
	}
	if identity != "" {
		if _, e := posts.ParseResourceID(identity); e != nil {
			return PostResponse{}, e
		}
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		if e := inboxIdentity(ctx, tx, account, identity); e != nil {
			return nil, e
		}
		if strings.HasPrefix(id, "s_") {
			if version != 1 {
				return nil, ErrIntentInvalid
			}
			tag, e := tx.Exec(ctx, `UPDATE c_moderation.notifications n SET read_at=COALESCE(read_at,$3) WHERE notification_id=$2 AND account_id=$1 AND (identity_id IS NULL OR EXISTS(SELECT 1 FROM public.community_identities i WHERE i.identity_id=n.identity_id AND i.account_id=$1 AND i.deleted_at IS NULL))`, account, id[2:], d.TrustedAt)
			if e != nil {
				return nil, e
			}
			if tag.RowsAffected() == 0 {
				return nil, postError("NOTIFICATION_NOT_FOUND", 404)
			}
		} else {
			tag, e := tx.Exec(ctx, `UPDATE c_inbox.records n SET read_version=GREATEST(read_version,$4),seen_like_count=GREATEST(seen_like_count,(SELECT count(*) FROM c_inbox.like_events e WHERE e.notification_id=n.notification_id AND e.version<=$4)) WHERE account_id=$1 AND notification_id=$2 AND identity_id=$3::uuid AND version>=$4 AND EXISTS(SELECT 1 FROM public.community_identities i WHERE i.identity_id=n.identity_id AND i.deleted_at IS NULL)`, account, id[2:], nullablePostID(identity), version)
			if e != nil {
				return nil, e
			}
			if tag.RowsAffected() == 0 {
				return nil, postError("NOTIFICATION_NOT_FOUND", 404)
			}
		}
		return InboxRead{id, version}, nil
	})
}
func preview(s string) string {
	r := []rune(s)
	if len(r) > 300 {
		return string(r[:300]) + "…"
	}
	return s
}
func readInboxNotice(ctx context.Context, tx pgx.Tx, account uuid.UUID, identity, id string) (InboxNotice, error) {
	n := InboxNotice{ID: id, Version: 1}
	if strings.HasPrefix(id, "s_") {
		original, e := scanNotification(tx.QueryRow(ctx, `SELECT `+notificationFields+` FROM c_moderation.notifications WHERE account_id=$1 AND notification_id=$2`, account, id[2:]))
		if e != nil {
			return n, e
		}
		n.Kind = "system"
		n.System = &original
		n.IdentityID = original.IdentityID
		n.CreatedAt = original.CreatedAt
		n.Title = original.Title
		n.Body = preview(original.Body)
		n.Unread = original.ReadAt == nil
		n.TargetAvailable = true
		return n, nil
	}
	var kind, post string
	var comment *string
	var readVersion, seen int64
	e := tx.QueryRow(ctx, `SELECT kind,identity_id::text,post_id::text,comment_id::text,is_reply,version,read_version,seen_like_count,updated_at FROM c_inbox.records WHERE notification_id=$1 AND account_id=$2 AND identity_id=$3::uuid`, id[2:], account, nullablePostID(identity)).Scan(&kind, &n.IdentityID, &post, &comment, &n.IsReply, &n.Version, &readVersion, &seen, &n.CreatedAt)
	if e != nil {
		return n, e
	}
	n.PostID = &post
	n.CommentID = comment
	p, _, e := readPublicPost(ctx, tx, post)
	if errors.Is(e, pgx.ErrNoRows) {
		n.TargetAvailable = false
		n.SourceTitle = "该帖子已删除或不可访问"
	} else if e != nil {
		return n, e
	} else {
		n.TargetAvailable = true
		n.SourceTitle = preview(p.Title)
		n.HasPostImage = p.ImageCount > 0
	}
	if kind == "COMMENT" {
		n.Kind = "comment"
		n.Unread = readVersion == 0
		n.Title = "回复了你"
		if n.TargetAvailable && comment != nil {
			source, e := readTextComment(ctx, tx, *comment, account)
			if errors.Is(e, pgx.ErrNoRows) {
				n.TargetAvailable = false
				n.Body = "该评论已删除"
			} else if e != nil {
				return n, e
			} else {
				n.Actor = &source.Author
				n.Body = preview(source.Body)
			}
		}
	} else {
		n.Kind = "like"
		e = tx.QueryRow(ctx, `SELECT count(*) FROM c_inbox.like_events WHERE notification_id=$1 AND version>$2`, id[2:], readVersion).Scan(&n.NewLikeCount)
		if e != nil {
			return n, e
		}
		n.Unread = n.NewLikeCount > 0
		n.Title = "你的帖子收到了赞"
		if kind == "LIKE_COMMENT" {
			n.Title = "你的评论收到了赞"
		}
		if !n.Unread {
			n.Title = "你的内容曾收到赞"
		}
		if n.TargetAvailable {
			if comment == nil {
				n.Body = preview(p.Body)
			} else {
				source, e := readTextComment(ctx, tx, *comment, account)
				if errors.Is(e, pgx.ErrNoRows) {
					n.TargetAvailable = false
					n.Body = "该评论已删除"
				} else if e != nil {
					return n, e
				} else {
					n.Body = preview(source.Body)
				}
			}
		}
	}
	if !n.TargetAvailable {
		n.HasPostImage = false
	}
	return n, nil
}
