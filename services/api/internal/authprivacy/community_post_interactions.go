package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func (c *Community) ReadPostInteractions(ctx context.Context, bearer [32]byte, ids []string) (PostResponse, error) {
	if err := posts.ValidateInteractionIDs(ids); err != nil {
		return PostResponse{}, err
	}
	var tag string
	r, err := c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		page, err := readPostInteractions(ctx, tx, account, ids)
		if err == nil && len(ids) == 1 {
			tag, err = c.postInteractionVersion(ctx, tx, account, page.Items[0])
		}
		return page, err
	})
	r.InteractionVersion = tag
	return r, err
}

// Opaque write fence binds only the account, post and persistent random version.
// Aggregate counts can change independently; they must never revive an old fence.
func (c *Community) postInteractionVersion(ctx context.Context, tx pgx.Tx, account uuid.UUID, item posts.PostInteractions) (string, error) {
	var version string
	err := tx.QueryRow(ctx, `SELECT version::text FROM c_posts.post_interaction_versions WHERE account_id=$1 AND post_id=$2`, account, item.PostID).Scan(&version)
	if err != nil && err != pgx.ErrNoRows {
		return "", err
	}
	encoded, err := json.Marshal([]any{"HNUHOLE/POST-INTERACTION-VERSION/V1", account.String(), item.PostID, version})
	if err != nil {
		return "", err
	}
	mac := hmac.New(sha256.New, c.requestKey[:])
	_, _ = mac.Write(encoded)
	return `"` + hex.EncodeToString(mac.Sum(nil)) + `"`, nil
}

func readPostInteractions(ctx context.Context, tx pgx.Tx, account uuid.UUID, ids []string) (posts.PostInteractionPage, error) {
	page := posts.PostInteractionPage{Items: make([]posts.PostInteractions, 0, len(ids))}
	rows, err := tx.Query(ctx, `SELECT p.post_id,
 (SELECT count(*) FROM c_posts.post_likes l WHERE l.post_id=p.post_id),
 (SELECT count(*) FROM c_posts.post_favorites f WHERE f.post_id=p.post_id),
 EXISTS(SELECT 1 FROM c_posts.post_likes l WHERE l.post_id=p.post_id AND l.account_id=$2),
 EXISTS(SELECT 1 FROM c_posts.post_favorites f WHERE f.post_id=p.post_id AND f.account_id=$2)
 FROM unnest($1::uuid[]) WITH ORDINALITY requested(id,position)
 JOIN c_posts.posts p ON p.post_id=requested.id
 JOIN c_posts.publication_tasks t ON t.post_id=p.post_id
 JOIN c_posts.attempt_contents x ON x.task_id=t.task_id AND x.version=p.published_attempt_version
 WHERE p.visibility='PUBLISHED' AND NOT p.moderation_hidden AND x.erased_at IS NULL
 ORDER BY requested.position`, ids, account)
	if err != nil {
		return page, err
	}
	for rows.Next() {
		var item posts.PostInteractions
		if err = rows.Scan(&item.PostID, &item.LikeCount, &item.FavoriteCount, &item.LikedByMe, &item.FavoritedByMe); err != nil {
			break
		}
		page.Items = append(page.Items, item)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return page, err
	}
	// No partial response may expose inaccessible/deleted post identifiers.
	if len(page.Items) != len(ids) {
		return posts.PostInteractionPage{}, postError("POST_NOT_FOUND", 404)
	}
	counts, err := readVisibleCommentCounts(ctx, tx, ids)
	if err != nil {
		return page, err
	}
	for i := range page.Items {
		page.Items[i].CommentCount = counts[page.Items[i].PostID]
	}
	return page, nil
}

// Set operations are idempotent, not toggles. Account lock precedes post lock,
// matching publication/deletion; no speaking identity is selected or bound.
func (c *Community) SetPostInteraction(ctx context.Context, bearer [32]byte, id string, kind posts.InteractionKind, enabled bool) (PostResponse, error) {
	return c.SetPostInteractionConditional(ctx, bearer, id, kind, enabled, "")
}

// expected is either empty (legacy commit-order behavior) or one opaque write version.
// Every successful write rotates the fence, including same-value legacy writes.
func (c *Community) SetPostInteractionConditional(ctx context.Context, bearer [32]byte, id string, kind posts.InteractionKind, enabled bool, expected string) (PostResponse, error) {
	if _, err := posts.ParseResourceID(id); err != nil || kind != posts.PostLike && kind != posts.PostFavorite {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	if expected != "" && !posts.ValidInteractionVersion(expected) {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	var tag string
	r, err := c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
		var visible bool
		if err := tx.QueryRow(ctx, `SELECT visibility='PUBLISHED' AND NOT moderation_hidden FROM c_posts.posts WHERE post_id=$1 FOR UPDATE`, id).Scan(&visible); err != nil || !visible {
			if err != nil && err != pgx.ErrNoRows {
				return nil, err
			}
			return nil, postError("POST_NOT_FOUND", 404)
		}
		// Also require the same content availability as public post reads.
		page, err := readPostInteractions(ctx, tx, account, []string{id})
		if err != nil {
			return nil, err
		}
		current, err := c.postInteractionVersion(ctx, tx, account, page.Items[0])
		if err != nil {
			return nil, err
		}
		if expected != "" && !hmac.Equal([]byte(expected), []byte(current)) {
			return nil, postError("INTERACTION_VERSION_CONFLICT", 412)
		}
		if err := writePostInteraction(ctx, tx, account, id, kind, enabled, final.TrustedAt); err != nil {
			return nil, err
		}
		version, err := uuid.NewRandom()
		if err != nil {
			return nil, err
		}
		if _, err = tx.Exec(ctx, `INSERT INTO c_posts.post_interaction_versions(account_id,post_id,version) VALUES($1,$2,$3) ON CONFLICT(account_id,post_id) DO UPDATE SET version=excluded.version`, account, id, version); err != nil {
			return nil, err
		}
		page, err = readPostInteractions(ctx, tx, account, []string{id})
		if err != nil {
			return nil, err
		}
		tag, err = c.postInteractionVersion(ctx, tx, account, page.Items[0])
		if err != nil {
			return nil, err
		}
		return page.Items[0], nil
	})
	r.InteractionVersion = tag
	return r, err
}

func writePostInteraction(ctx context.Context, tx pgx.Tx, account uuid.UUID, id string, kind posts.InteractionKind, enabled bool, at time.Time) error {
	var err error
	if kind == posts.PostLike {
		if enabled {
			_, err = tx.Exec(ctx, `INSERT INTO c_posts.post_likes(account_id,post_id) VALUES($1,$2) ON CONFLICT(account_id,post_id) DO NOTHING`, account, id)
		} else {
			_, err = tx.Exec(ctx, `DELETE FROM c_posts.post_likes WHERE account_id=$1 AND post_id=$2`, account, id)
		}
	} else if enabled {
		_, err = tx.Exec(ctx, `INSERT INTO c_posts.post_favorites(account_id,post_id,saved_at) VALUES($1,$2,$3) ON CONFLICT(account_id,post_id) DO NOTHING`, account, id, at)
	} else {
		_, err = tx.Exec(ctx, `DELETE FROM c_posts.post_favorites WHERE account_id=$1 AND post_id=$2`, account, id)
	}
	return err
}
