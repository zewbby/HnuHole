package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

func (c *Community) ResolveSharedSubject(ctx context.Context, bearer [32]byte) (string, error) {
	if c.sharedRate == nil {
		return "", nil
	}
	var subject string
	_, err := c.withIdentitySession(ctx, bearer, func(_ pgx.Tx, a uuid.UUID, _ AuthorizationDecision) error { subject = c.rateSubject(a); return nil })
	return subject, err
}
func (c *Community) ResolveCommentUploadSubject(ctx context.Context, bearer [32]byte, task string, version int32) (string, error) {
	if c.sharedRate == nil {
		return "", nil
	}
	var subject string
	_, err := c.withCommentSession(ctx, bearer, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, m restriction) (any, error) {
		t, err := loadCommentTask(ctx, tx, a, task)
		if err != nil {
			return nil, err
		}
		v := t.View()
		if v.State != comments.Accepted || v.AttemptVersion != version || v.Content == nil || v.Content.Image == nil || mutedAt(m, d.TrustedAt) {
			return nil, postError("MEDIA_UPLOAD_CLOSED", 409)
		}
		if err = checkCommentContext(ctx, tx, a, v.Binding); err != nil {
			return nil, err
		}
		subject = c.rateSubject(a)
		return nil, nil
	})
	return subject, err
}

// ResolvePostUploadSubject authenticates the scoped Upload capability before
// body reading. The actual business write still repeats all these checks.
func (c *Community) ResolvePostUploadSubject(ctx context.Context, token [32]byte, task, media string, version int32) (string, error) {
	if c.sharedRate == nil {
		return "", nil
	}
	if !c.PostImagesEnabled() {
		return "", ErrAuthorizationUnavailable
	}
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(token[:])
	var account uuid.UUID
	err = c.pool.QueryRow(ctx, `SELECT t.owner_account_id FROM c_posts.images m JOIN c_posts.publication_tasks t USING(task_id) WHERE m.task_id=$1 AND m.version=$2 AND m.media_id=$3 AND m.grant_digest=$4`, task, version, media, digest[:]).Scan(&account)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", postError("MEDIA_UPLOAD_DENIED", 403)
	}
	if err != nil {
		return "", ErrAuthorizationUnavailable
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return "", ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state string
	if err = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&state); err != nil {
		return "", ErrAuthorizationUnavailable
	}
	ban, err := lockRestriction(ctx, tx, account)
	if err != nil {
		return "", err
	}
	var mute restriction
	if err = tx.QueryRow(ctx, `SELECT mute_state,mute_ends_at FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&mute.state, &mute.ends); err != nil {
		return "", ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, d.Generation, func(final AuthorizationDecision) error {
		if state != "ACTIVE" || bannedAt(ban, final.TrustedAt) {
			return postError("MEDIA_UPLOAD_CLOSED", 409)
		}
		if err := c.checkPostProtocolKeys(ctx, tx); err != nil {
			return err
		}
		if err := activeImageAttempt(ctx, tx, account, task, media, version, final, mute); err != nil {
			return err
		}
		var allowed bool
		err := tx.QueryRow(ctx, `SELECT grant_digest=$4 AND grant_expires_at>$5 FROM c_posts.images WHERE task_id=$1 AND version=$2 AND media_id=$3`, task, version, media, digest[:], final.TrustedAt).Scan(&allowed)
		if err != nil || !allowed {
			return postError("MEDIA_UPLOAD_DENIED", 403)
		}
		return nil
	})
	if errors.Is(err, errPostProtocolIntegrity) {
		_ = c.gate.Abort(ctx, tx)
		return "", c.freezePostProtocol(ctx)
	}
	if err != nil {
		return "", err
	}
	return c.rateSubject(account), nil
}

func (c *Community) ResolveIdentityAvatarUploadSubject(ctx context.Context, bearer [32]byte, id uuid.UUID) (string, error) {
	if c.sharedRate == nil {
		return "", nil
	}
	var subject string
	_, err := c.withIdentitySession(ctx, bearer, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision) error {
		var foreign bool
		if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.identity_avatar_assets WHERE asset_id=$1 AND account_id<>$2)`, id, a).Scan(&foreign); e != nil {
			return ErrAuthorizationUnavailable
		}
		if foreign {
			return postError("IDENTITY_AVATAR_INVALID", 409)
		}
		subject = c.rateSubject(a)
		return nil
	})
	return subject, err
}

func requireSharedPolicyFence(ctx context.Context, tx pgx.Tx) error {
	err := ratelimit.RequirePolicyFence(ctx, tx, "community")
	if errors.Is(err, ratelimit.ErrPolicyMismatch) {
		return &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
	}
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	return nil
}
