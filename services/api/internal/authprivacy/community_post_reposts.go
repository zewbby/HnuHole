package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"time"
)

const PostRepostState PostReadKind = "repostState"
const PostRepostSet PostReadKind = "repostSet"
const PostRepostList PostReadKind = "repostList"

func (c *Community) repostVersion(ctx context.Context, tx pgx.Tx, account uuid.UUID, id string) (string, error) {
	var version string
	err := tx.QueryRow(ctx, `SELECT version::text FROM c_posts.post_repost_versions WHERE account_id=$1 AND post_id=$2`, account, id).Scan(&version)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return "", err
	}
	encoded, _ := json.Marshal([]string{"HNUHOLE/REPOST/V1", account.String(), id, version})
	mac := hmac.New(sha256.New, c.requestKey[:])
	_, _ = mac.Write(encoded)
	return `"` + hex.EncodeToString(mac.Sum(nil)) + `"`, nil
}
func readRepostState(ctx context.Context, tx pgx.Tx, account uuid.UUID, id string) (posts.RepostState, error) {
	result := posts.RepostState{PostID: id, Items: []posts.RepostMark{}}
	rows, err := tx.Query(ctx, `SELECT r.identity_id,r.reposted_at FROM c_posts.post_reposts r
 JOIN public.community_identities i ON i.identity_id=r.identity_id
 WHERE r.account_id=$1 AND r.post_id=$2 AND i.deleted_at IS NULL ORDER BY r.identity_id`, account, id)
	if err != nil {
		return result, err
	}
	defer rows.Close()
	for rows.Next() {
		var item posts.RepostMark
		if err = rows.Scan(&item.IdentityID, &item.RepostedAt); err != nil {
			return result, err
		}
		item.RepostedAt = item.RepostedAt.UTC()
		result.Items = append(result.Items, item)
	}
	return result, rows.Err()
}
func repostReadable(ctx context.Context, tx pgx.Tx, account uuid.UUID, id string) error {
	_, _, err := readPublicPost(ctx, tx, id)
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	var known bool
	if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.post_repost_versions WHERE account_id=$1 AND post_id=$2)`, account, id).Scan(&known); err != nil {
		return err
	}
	if !known {
		return postError("POST_NOT_FOUND", 404)
	}
	return nil
}
func (c *Community) ReadPostReposts(ctx context.Context, bearer [32]byte, id string) (PostResponse, error) {
	if _, err := posts.ParseResourceID(id); err != nil {
		return PostResponse{}, err
	}
	var tag string
	r, err := c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		if err := repostReadable(ctx, tx, account, id); err != nil {
			return nil, err
		}
		value, err := readRepostState(ctx, tx, account, id)
		if err != nil {
			return nil, err
		}
		tag, err = c.repostVersion(ctx, tx, account, id)
		return value, err
	})
	r.InteractionVersion = tag
	return r, err
}
func (c *Community) SetPostRepost(ctx context.Context, bearer [32]byte, id, identity string, enabled bool, expected string) (PostResponse, error) {
	if _, err := posts.ParseResourceID(id); err != nil {
		return PostResponse{}, err
	}
	if _, err := posts.ParseResourceID(identity); err != nil {
		return PostResponse{}, err
	}
	if !posts.ValidInteractionVersion(expected) {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	var tag string
	r, err := c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
		// withPostSession locks the account first, shared with identity deletion/closure.
		var owned bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE account_id=$1 AND identity_id=$2 AND deleted_at IS NULL)`, account, identity).Scan(&owned); err != nil {
			return nil, err
		}
		if !owned {
			return nil, postError("POST_IDENTITY_UNAVAILABLE", 409)
		}
		if err := repostReadable(ctx, tx, account, id); err != nil {
			return nil, err
		}
		// Lock original so deletion/hiding cannot race a successful creation.
		var locked string
		if err := tx.QueryRow(ctx, `SELECT post_id FROM c_posts.posts WHERE post_id=$1 FOR UPDATE`, id).Scan(&locked); err != nil {
			return nil, err
		}
		if enabled {
			if _, _, err := readPublicPost(ctx, tx, id); err != nil {
				if errors.Is(err, pgx.ErrNoRows) {
					return nil, postError("POST_NOT_FOUND", 404)
				}
				return nil, err
			}
		}
		current, err := c.repostVersion(ctx, tx, account, id)
		if err != nil {
			return nil, err
		}
		if !hmac.Equal([]byte(current), []byte(expected)) {
			return nil, postError("INTERACTION_VERSION_CONFLICT", 412)
		}
		if enabled {
			_, err = tx.Exec(ctx, `INSERT INTO c_posts.post_reposts(account_id,identity_id,post_id,reposted_at) VALUES($1,$2,$3,$4) ON CONFLICT(identity_id,post_id) DO NOTHING`, account, identity, id, final.TrustedAt)
		} else {
			_, err = tx.Exec(ctx, `DELETE FROM c_posts.post_reposts WHERE account_id=$1 AND identity_id=$2 AND post_id=$3`, account, identity, id)
		}
		if err != nil {
			return nil, err
		}
		version, err := uuid.NewRandom()
		if err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, `INSERT INTO c_posts.post_repost_versions(account_id,post_id,version) VALUES($1,$2,$3) ON CONFLICT(account_id,post_id) DO UPDATE SET version=excluded.version`, account, id, version)
		if err != nil {
			return nil, err
		}
		value, err := readRepostState(ctx, tx, account, id)
		if err != nil {
			return nil, err
		}
		tag, err = c.repostVersion(ctx, tx, account, id)
		return value, err
	})
	r.InteractionVersion = tag
	return r, err
}
func (c *Community) ListPostReposts(ctx context.Context, bearer [32]byte, query PostQuery) (PostResponse, error) {
	if query.Limit == 0 {
		query.Limit = 20
	}
	if query.Limit < 1 || query.Limit > 50 || query.ID != "" {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
		position := posts.CursorPosition{Scope: posts.CursorReposts, AccountID: account.String(), Limit: query.Limit, ExpiresAt: final.TrustedAt.Add(posts.CursorTTL)}
		var err error
		if query.Cursor != "" {
			position, err = c.posts.cursors.Decode(query.Cursor, position, final.TrustedAt)
		} else {
			err = tx.QueryRow(ctx, `SELECT COALESCE(MAX(ordinal),0) FROM c_posts.post_reposts WHERE account_id=$1`, account).Scan(&position.Ceiling)
		}
		if err != nil {
			return nil, err
		}
		rows, err := tx.Query(ctx, `SELECT r.post_id,r.identity_id,r.reposted_at,r.ordinal FROM c_posts.post_reposts r
 JOIN public.community_identities i ON i.identity_id=r.identity_id
 WHERE r.account_id=$1 AND i.deleted_at IS NULL AND r.ordinal<=$2
 AND ($3::timestamptz IS NULL OR (r.reposted_at,r.ordinal)<($3,$4))
 ORDER BY r.reposted_at DESC,r.ordinal DESC LIMIT $5`, account, position.Ceiling, repostLastTime(position), position.LastOrdinal, query.Limit+1)
		if err != nil {
			return nil, err
		}
		page := posts.RepostPage{Items: []posts.RepostItem{}}
		ordinals := []int64{}
		for rows.Next() {
			var item posts.RepostItem
			var ordinal int64
			if err = rows.Scan(&item.PostID, &item.IdentityID, &item.RepostedAt, &ordinal); err != nil {
				break
			}
			item.RepostedAt = item.RepostedAt.UTC()
			page.Items = append(page.Items, item)
			ordinals = append(ordinals, ordinal)
		}
		if err == nil {
			err = rows.Err()
		}
		rows.Close()
		if err != nil {
			return nil, err
		}
		if len(page.Items) > query.Limit {
			page.Items = page.Items[:query.Limit]
			last := page.Items[len(page.Items)-1]
			position.LastAt = last.RepostedAt
			position.LastOrdinal = ordinals[query.Limit-1]
			cursor, err := c.posts.cursors.Encode(position)
			if err != nil {
				return nil, err
			}
			page.NextCursor = &cursor
		}
		for n := range page.Items {
			post, _, err := readPublicPost(ctx, tx, page.Items[n].PostID)
			if errors.Is(err, pgx.ErrNoRows) {
				continue
			}
			if err != nil {
				return nil, err
			}
			page.Items[n].Post = &post
		}
		return page, nil
	})
}
func repostLastTime(p posts.CursorPosition) *time.Time {
	if p.LastAt.IsZero() {
		return nil
	}
	return &p.LastAt
}
