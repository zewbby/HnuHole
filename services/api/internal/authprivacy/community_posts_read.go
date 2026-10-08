package authprivacy

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type PostReadKind string

const (
	PostComposerContext PostReadKind = "composer"
	PostTaskList        PostReadKind = "tasks"
	PostTaskDetail      PostReadKind = "task"
	PostChannelFeed     PostReadKind = "channel"
	PostDetail          PostReadKind = "post"
	PostOwnList         PostReadKind = "own"
	PostCapabilities    PostReadKind = "capabilities"
)

type PostQuery struct {
	Kind       PostReadKind
	ID, Cursor string
	Limit      int
}

func readOwnPostTask(ctx context.Context, tx pgx.Tx, account uuid.UUID, id string, at time.Time, mute restriction) (posts.OwnTaskDetail, error) {
	var r posts.OwnTaskDetail
	var state string
	var ownerVisible bool
	var deleted, erased *time.Time
	var title, body *string
	var postVisibility string
	var cleanup bool
	err := tx.QueryRow(ctx, `SELECT t.task_id,t.post_id,t.channel_id,t.identity_id,t.latest_attempt_version,a.state,a.accepted_at,a.terminal_at,a.failure_code,t.owner_visible,i.deleted_at,x.erased_at,x.title,x.body,p.visibility,
 EXISTS(SELECT 1 FROM c_posts.payload_cleanup q WHERE q.task_id=a.task_id AND q.version=a.version)
 FROM c_posts.publication_tasks t JOIN c_posts.publication_attempts a ON a.task_id=t.task_id AND a.version=t.latest_attempt_version
 JOIN public.community_identities i ON i.identity_id=t.identity_id JOIN c_posts.attempt_contents x ON x.task_id=a.task_id AND x.version=a.version JOIN c_posts.posts p ON p.post_id=t.post_id
 WHERE t.task_id=$1 AND t.owner_account_id=$2`, id, account).Scan(&r.Task.TaskID, &r.Task.PostID, &r.Task.ChannelID, &r.Task.IdentityID, &r.Task.AttemptVersion, &state, &r.Task.AcceptedAt, &r.Task.TerminalAt, &r.Task.FailureCode, &ownerVisible, &deleted, &erased, &title, &body, &postVisibility, &cleanup)
	if err != nil {
		return r, err
	}
	r.Task.State = posts.TaskState(state)
	r.Task.AcceptedAt = r.Task.AcceptedAt.UTC()
	r.Task.ServerSortAt = r.Task.AcceptedAt
	if r.Task.TerminalAt != nil {
		utc := r.Task.TerminalAt.UTC()
		r.Task.TerminalAt = &utc
	}
	r.Task.Visible = ownerVisible && deleted == nil && (r.Task.State == posts.Accepted || r.Task.State == posts.Failed)
	r.Task.ContentAvailable = ownerVisible && deleted == nil && erased == nil && !cleanup && title != nil && body != nil && r.Task.State != posts.Cancelled && postVisibility != "DELETED"
	if r.Task.ContentAvailable {
		r.Content = &posts.OwnTaskContent{Title: *title, Body: *body}
	}
	r.Task.CanCancel = r.Task.Visible && r.Task.State == posts.Accepted
	r.Task.CanHide = r.Task.Visible && r.Task.State == posts.Failed
	r.Task.CanRetry = r.Task.CanHide && r.Task.ContentAvailable && !mutedAt(mute, at)
	return r, nil
}

func (c *Community) ReadPosts(ctx context.Context, bearer [32]byte, query PostQuery) (PostResponse, error) {
	switch query.Kind {
	case PostTaskDetail, PostChannelFeed, PostDetail, PostCapabilities:
		if _, err := posts.ParseResourceID(query.ID); err != nil {
			return PostResponse{}, err
		}
	case PostComposerContext, PostTaskList, PostOwnList:
		if query.ID != "" {
			return PostResponse{}, posts.ErrInvalidID
		}
	default:
		return PostResponse{}, posts.ErrInvalidIntent
	}
	if query.Limit == 0 {
		query.Limit = 20
	}
	if query.Limit < 1 || query.Limit > 50 {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, mute restriction) (any, error) {
		switch query.Kind {
		case PostComposerContext:
			return readPostComposerContext(ctx, tx, account)
		case PostTaskDetail:
			if err := materializePostStops(ctx, tx, account); err != nil {
				return nil, err
			}
			r, err := readOwnPostTask(ctx, tx, account, query.ID, final.TrustedAt, mute)
			if errors.Is(err, pgx.ErrNoRows) {
				return nil, postError("TASK_NOT_FOUND", 404)
			}
			return r, err
		case PostTaskList:
			if err := materializePostStops(ctx, tx, account); err != nil {
				return nil, err
			}
			return c.listPostTasks(ctx, tx, account, query, final.TrustedAt, mute)
		case PostCapabilities:
			var exists bool
			err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.posts WHERE post_id=$1 AND owner_account_id=$2 AND visibility='PUBLISHED')`, query.ID, account).Scan(&exists)
			if err != nil {
				return nil, err
			}
			if !exists {
				return nil, postError("POST_NOT_FOUND", 404)
			}
			return posts.OwnPostCapabilities{PostID: query.ID, CanDelete: true, CanEdit: false}, nil
		case PostDetail:
			r, _, err := readPublicPost(ctx, tx, query.ID)
			if errors.Is(err, pgx.ErrNoRows) {
				return nil, postError("POST_NOT_FOUND", 404)
			}
			return posts.PublicPostResponse{Post: r}, err
		case PostChannelFeed, PostOwnList:
			return c.listPublicPosts(ctx, tx, account, query, final.TrustedAt)
		}
		return nil, posts.ErrInvalidIntent
	})
}

func readPostComposerContext(ctx context.Context, tx pgx.Tx, account uuid.UUID) (posts.ComposerContext, error) {
	items, err := readOwnIdentities(ctx, tx, account)
	if err != nil {
		return posts.ComposerContext{}, err
	}
	r := posts.ComposerContext{SelectionState: "SELECTION_REQUIRED"}
	if len(items) == 0 {
		r.SelectionState = "INITIAL_SETUP_REQUIRED"
		return r, nil
	}
	var last *uuid.UUID
	if err = tx.QueryRow(ctx, `SELECT last_public_identity_id FROM c_posts.account_publication_control WHERE account_id=$1`, account).Scan(&last); err != nil {
		return r, err
	}
	choose := func(id uuid.UUID) {
		value := id.String()
		r.DefaultIdentityID = &value
		r.SelectionState = "DEFAULT_AVAILABLE"
	}
	if last != nil {
		for _, item := range items {
			if item.ID == *last {
				choose(item.ID)
				return r, nil
			}
		}
	} else {
		for _, item := range items {
			if item.IsOriginal {
				choose(item.ID)
				return r, nil
			}
		}
	}
	if len(items) == 1 {
		choose(items[0].ID)
	}
	return r, nil
}

// 投影只读取当前公开状态。没有账号ID、身份ID或本人权能进入公共DTO。
func readPublicPost(ctx context.Context, tx pgx.Tx, id string) (posts.PublicPost, int64, error) {
	var r posts.PublicPost
	var ordinal int64
	var accountState string
	var deleted *time.Time
	var nickname, avatar *string
	var short string
	err := tx.QueryRow(ctx, `SELECT p.post_id,p.channel_id,x.title,x.body,p.published_at,p.publication_ordinal,a.state,i.deleted_at,i.nickname,i.avatar,l.short_code
 FROM c_posts.posts p JOIN c_posts.publication_tasks t ON t.post_id=p.post_id JOIN c_posts.attempt_contents x ON x.task_id=t.task_id AND x.version=p.published_attempt_version
 JOIN public.community_identities i ON i.identity_id=t.identity_id JOIN c_auth.accounts a ON a.account_id=p.owner_account_id JOIN c_posts.identity_public_labels l ON l.identity_id=i.identity_id
 WHERE p.post_id=$1 AND p.visibility='PUBLISHED' AND x.erased_at IS NULL`, id).Scan(&r.PostID, &r.ChannelID, &r.Title, &r.Body, &r.PublishedAt, &ordinal, &accountState, &deleted, &nickname, &avatar, &short)
	if err != nil {
		return r, 0, err
	}
	r.PublishedAt = r.PublishedAt.UTC()
	switch {
	case accountState == "CLOSED":
		r.Author = posts.PublicAuthor{State: "ACCOUNT_CLOSED", ShortCode: short, Avatar: "inactive-v1"}
	case deleted != nil:
		r.Author = posts.PublicAuthor{State: "DELETED", ShortCode: short, Avatar: "inactive-v1"}
	default:
		if nickname == nil || avatar == nil {
			return r, 0, ErrAuthorizationUnavailable
		}
		r.Author = posts.PublicAuthor{State: "ACTIVE", Nickname: *nickname, Avatar: *avatar}
	}
	return r, ordinal, nil
}
func postCard(r posts.PublicPost) posts.PublicPostCard {
	return posts.PublicPostCard{PostID: r.PostID, ChannelID: r.ChannelID, Title: r.Title, Author: r.Author, PublishedAt: r.PublishedAt}
}
func (c *Community) postCursor(ctx context.Context, tx pgx.Tx, account uuid.UUID, query PostQuery, at time.Time) (posts.CursorPosition, error) {
	scope := posts.CursorChannel
	channel := query.ID
	sequence := "publication_ordinal"
	if query.Kind == PostOwnList {
		scope = posts.CursorOwn
		channel = ""
	}
	if query.Kind == PostTaskList {
		scope = posts.CursorTask
		channel = ""
		sequence = "acceptance_ordinal"
	}
	p := posts.CursorPosition{Scope: scope, AccountID: account.String(), ChannelID: channel, Limit: query.Limit, ExpiresAt: at.Add(30 * time.Minute)}
	if query.Cursor != "" {
		return c.posts.cursors.Decode(query.Cursor, p, at)
	}
	sql := `SELECT COALESCE(MAX(publication_ordinal),0) FROM c_posts.posts`
	if sequence == "acceptance_ordinal" {
		sql = `SELECT COALESCE(MAX(acceptance_ordinal),0) FROM c_posts.publication_attempts`
	}
	err := tx.QueryRow(ctx, sql).Scan(&p.Ceiling)
	return p, err
}
func (c *Community) listPublicPosts(ctx context.Context, tx pgx.Tx, account uuid.UUID, query PostQuery, at time.Time) (any, error) {
	if query.Kind == PostChannelFeed {
		var exists bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.channels WHERE id=$1)`, query.ID).Scan(&exists); err != nil {
			return nil, err
		}
		if !exists {
			return nil, postError("POST_CHANNEL_UNAVAILABLE", 404)
		}
	}
	position, err := c.postCursor(ctx, tx, account, query, at)
	if err != nil {
		return nil, err
	}
	var lastAt any
	var lastOrdinal any
	if !position.LastAt.IsZero() {
		lastAt = position.LastAt
		lastOrdinal = position.LastOrdinal
	}
	var channel, owner any
	if query.Kind == PostChannelFeed {
		channel = query.ID
	} else {
		owner = account
	}
	rows, err := tx.Query(ctx, `SELECT p.post_id FROM c_posts.posts p JOIN c_posts.publication_tasks t ON t.post_id=p.post_id JOIN public.community_identities i ON i.identity_id=t.identity_id
 WHERE p.visibility='PUBLISHED' AND p.publication_ordinal<=$1 AND ($2::uuid IS NULL OR p.channel_id=$2) AND ($3::uuid IS NULL OR (p.owner_account_id=$3 AND i.deleted_at IS NULL))
 AND ($4::timestamptz IS NULL OR (p.published_at,p.publication_ordinal)<($4,$5::bigint)) ORDER BY p.published_at DESC,p.publication_ordinal DESC LIMIT $6`, position.Ceiling, channel, owner, lastAt, lastOrdinal, query.Limit+1)
	if err != nil {
		return nil, err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			break
		}
		ids = append(ids, id)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return nil, err
	}
	page := posts.FeedPage{Items: make([]posts.PublicPostCard, 0, query.Limit)}
	own := posts.OwnPostPage{Items: make([]posts.OwnPostCard, 0, query.Limit)}
	more := len(ids) > query.Limit
	if more {
		ids = ids[:query.Limit]
	}
	for _, id := range ids {
		item, ordinal, e := readPublicPost(ctx, tx, id)
		if e != nil {
			return nil, e
		}
		card := postCard(item)
		page.Items = append(page.Items, card)
		own.Items = append(own.Items, posts.OwnPostCard{Post: card, ServerSortAt: item.PublishedAt})
		position.LastAt = item.PublishedAt
		position.LastOrdinal = ordinal
	}
	if more {
		cursor, e := c.posts.cursors.Encode(position)
		if e != nil {
			return nil, e
		}
		page.NextCursor = &cursor
		own.NextCursor = &cursor
	}
	if query.Kind == PostOwnList {
		return own, nil
	}
	return page, nil
}
func (c *Community) listPostTasks(ctx context.Context, tx pgx.Tx, account uuid.UUID, query PostQuery, at time.Time, mute restriction) (posts.OwnTaskList, error) {
	page := posts.OwnTaskList{Items: make([]posts.OwnTaskDetail, 0, query.Limit)}
	position, err := c.postCursor(ctx, tx, account, query, at)
	if err != nil {
		return page, err
	}
	var lastAt, lastID any
	if !position.LastAt.IsZero() {
		lastAt = position.LastAt
		lastID = position.LastID
	}
	rows, err := tx.Query(ctx, `SELECT t.task_id,a.acceptance_ordinal FROM c_posts.publication_tasks t JOIN c_posts.publication_attempts a ON a.task_id=t.task_id AND a.version=t.latest_attempt_version
 JOIN public.community_identities i ON i.identity_id=t.identity_id WHERE t.owner_account_id=$1 AND t.owner_visible AND i.deleted_at IS NULL AND a.state IN ('ACCEPTED','FAILED') AND a.acceptance_ordinal<=$2
 AND ($3::timestamptz IS NULL OR (a.accepted_at,t.task_id)<($3,$4::uuid)) ORDER BY a.accepted_at DESC,t.task_id DESC LIMIT $5`, account, position.Ceiling, lastAt, lastID, query.Limit+1)
	if err != nil {
		return page, err
	}
	type ref struct {
		id      string
		ordinal int64
	}
	var refs []ref
	for rows.Next() {
		var item ref
		if err = rows.Scan(&item.id, &item.ordinal); err != nil {
			break
		}
		refs = append(refs, item)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return page, err
	}
	more := len(refs) > query.Limit
	if more {
		refs = refs[:query.Limit]
	}
	for _, ref := range refs {
		item, e := readOwnPostTask(ctx, tx, account, ref.id, at, mute)
		if e != nil {
			return page, e
		}
		page.Items = append(page.Items, item)
		position.LastAt = item.Task.AcceptedAt
		position.LastID = ref.id
	}
	if more {
		cursor, e := c.posts.cursors.Encode(position)
		if e != nil {
			return page, e
		}
		page.NextCursor = &cursor
	}
	return page, nil
}
