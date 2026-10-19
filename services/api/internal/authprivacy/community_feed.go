package authprivacy

import (
	"context"
	"errors"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

var feedDayZone = time.FixedZone("Asia/Shanghai", 8*60*60)

func recordPostView(ctx context.Context, tx pgx.Tx, account uuid.UUID, id string, at time.Time) (posts.PostView, error) {
	_, _, err := readPublicPost(ctx, tx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return posts.PostView{}, postError("POST_NOT_FOUND", 404)
	}
	if err != nil {
		return posts.PostView{}, err
	}
	views, err := readPostViewCount(ctx, tx, id)
	if err != nil {
		return posts.PostView{}, err
	}
	result := posts.PostView{PostID: id, ViewCount: views}
	var owner uuid.UUID
	if err = tx.QueryRow(ctx, `SELECT owner_account_id FROM c_posts.posts WHERE post_id=$1`, id).Scan(&owner); err != nil {
		return result, err
	}
	if owner == account {
		return result, nil
	}
	day := at.In(feedDayZone).Format("2006-01-02")
	// Old daily keys are unnecessary once the trusted day advances. Totals remain.
	if _, err = tx.Exec(ctx, `DELETE FROM c_posts.post_daily_views WHERE account_id=$1 AND view_day<$2::date`, account, day); err != nil {
		return result, err
	}
	inserted, err := tx.Exec(ctx, `INSERT INTO c_posts.post_daily_views(account_id,post_id,view_day) VALUES($1,$2,$3::date) ON CONFLICT(account_id,post_id,view_day) DO NOTHING`, account, id, day)
	if err != nil || inserted.RowsAffected() == 0 {
		return result, err
	}
	err = tx.QueryRow(ctx, `INSERT INTO c_posts.post_view_totals(post_id,view_count) VALUES($1,1)
 ON CONFLICT(post_id) DO UPDATE SET view_count=c_posts.post_view_totals.view_count+1 RETURNING view_count`, id).Scan(&result.ViewCount)
	return result, err
}

func readPostViewCount(ctx context.Context, tx pgx.Tx, id string) (int64, error) {
	var views int64
	err := tx.QueryRow(ctx, `SELECT COALESCE((SELECT view_count FROM c_posts.post_view_totals WHERE post_id=$1),0)`, id).Scan(&views)
	return views, err
}

func readFeedPreferences(ctx context.Context, tx pgx.Tx, account uuid.UUID) (posts.FeedPreferences, int64, error) {
	p := posts.FeedPreferences{BlockedChannelIDs: []string{}}
	var revision int64
	err := tx.QueryRow(ctx, `SELECT blocked_channel_ids,revision FROM c_posts.feed_preferences WHERE account_id=$1`, account).Scan(&p.BlockedChannelIDs, &revision)
	if errors.Is(err, pgx.ErrNoRows) {
		return p, 0, nil
	}
	return p, revision, err
}

// ReplaceFeedPreferences replaces the complete account preference atomically.
// Replaying the same set is idempotent and does not invalidate existing cursors.
func (c *Community) ReplaceFeedPreferences(ctx context.Context, bearer [32]byte, input posts.FeedPreferences) (PostResponse, error) {
	if input.BlockedChannelIDs == nil || len(input.BlockedChannelIDs) > 7 {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	ids := append([]string{}, input.BlockedChannelIDs...)
	sort.Strings(ids)
	for i, id := range ids {
		if _, err := posts.ParseResourceID(id); err != nil || i > 0 && id == ids[i-1] {
			return PostResponse{}, postError("MALFORMED_REQUEST", 400)
		}
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		var exists bool
		if err := tx.QueryRow(ctx, `SELECT count(*)=cardinality($1::uuid[]) FROM public.channels WHERE id=ANY($1::uuid[])`, ids).Scan(&exists); err != nil {
			return nil, err
		}
		if !exists {
			return nil, postError("POST_CHANNEL_UNAVAILABLE", 404)
		}
		previous, _, err := readFeedPreferences(ctx, tx, account)
		if err != nil {
			return nil, err
		}
		equal := len(previous.BlockedChannelIDs) == len(ids)
		for i := range ids {
			if !equal || previous.BlockedChannelIDs[i] != ids[i] {
				equal = false
				break
			}
		}
		if !equal {
			if _, err = tx.Exec(ctx, `INSERT INTO c_posts.feed_preferences(account_id,blocked_channel_ids,revision) VALUES($1,$2,1)
 ON CONFLICT(account_id) DO UPDATE SET blocked_channel_ids=EXCLUDED.blocked_channel_ids,revision=c_posts.feed_preferences.revision+1`, account, ids); err != nil {
				return nil, err
			}
		}
		return posts.FeedPreferences{BlockedChannelIDs: ids}, nil
	})
}
