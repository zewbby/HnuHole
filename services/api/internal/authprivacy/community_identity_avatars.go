package authprivacy

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

const IdentityAvatarMaxBytes = 5 * 1024 * 1024

func ValidIdentityAvatar(ref string) bool {
	if ref == IdentityDefaultAvatar {
		return true
	}
	if !strings.HasPrefix(ref, "avatar-v1:") {
		return false
	}
	id, e := uuid.Parse(strings.TrimPrefix(ref, "avatar-v1:"))
	return e == nil && id != uuid.Nil && ref == "avatar-v1:"+id.String()
}

// Assets have independent random IDs, never post upload IDs or content hashes.
// Both preliminary admission and final storage use the current C Safety Gate.
func (c *Community) UploadIdentityAvatar(ctx context.Context, bearer [32]byte, id uuid.UUID, data []byte, mime string) (time.Time, error) {
	if id == uuid.Nil || len(data) < 1 || len(data) > IdentityAvatarMaxBytes {
		return time.Time{}, postmedia.ErrInvalid
	}
	if c.postImages == nil {
		return time.Time{}, postmedia.ErrUnavailable
	}
	normalizer, ok := c.postImages.validator.(postmedia.Thumbnailer)
	if !ok {
		return time.Time{}, postmedia.ErrUnavailable
	}
	hash := sha256.Sum256(data)
	admission := func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) error {
		var existing []byte
		var live bool
		e := tx.QueryRow(ctx, `SELECT digest,payload IS NOT NULL AND (identity_id IS NOT NULL OR expires_at>$3) FROM public.identity_avatar_assets WHERE asset_id=$1 AND account_id=$2`, id, account, final.TrustedAt).Scan(&existing, &live)
		if e == nil {
			if subtle.ConstantTimeCompare(hash[:], existing) != 1 || !live {
				return postError("IDENTITY_AVATAR_INVALID", 409)
			}
			return nil
		}
		if !errors.Is(e, pgx.ErrNoRows) {
			return ErrAuthorizationUnavailable
		}
		if _, e = tx.Exec(ctx, `UPDATE public.identity_avatar_assets SET payload=NULL WHERE account_id=$1 AND identity_id IS NULL AND expires_at<=$2 AND payload IS NOT NULL`, account, final.TrustedAt); e != nil {
			return ErrAuthorizationUnavailable
		}
		var count int
		if e = tx.QueryRow(ctx, `SELECT count(*) FROM public.identity_avatar_assets WHERE account_id=$1 AND identity_id IS NULL AND payload IS NOT NULL`, account).Scan(&count); e != nil {
			return ErrAuthorizationUnavailable
		}
		if count >= 3 {
			return postError("IDENTITY_AVATAR_LIMIT", 409)
		}
		return nil
	}
	if _, e := c.withIdentitySession(ctx, bearer, admission); e != nil {
		return time.Time{}, e
	}
	metadata, e := c.postImages.validator.Inspect(ctx, data)
	if e != nil {
		return time.Time{}, e
	}
	selection := postmedia.Selection{MediaID: id.String(), SHA256: metadata.SHA256, ByteLength: len(data), MIME: mime, Width: metadata.Width, Height: metadata.Height}
	if !metadata.Matches(selection, data) || metadata.Frames != 1 || metadata.Animated {
		return time.Time{}, postmedia.ErrInvalid
	}
	normalized, e := normalizer.Thumbnail(ctx, data)
	if e != nil {
		return time.Time{}, e
	}
	if len(normalized) < 12 || len(normalized) > postmedia.MaxThumbnailBytes {
		return time.Time{}, postmedia.ErrUnavailable
	}
	return c.withIdentitySession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) error {
		if e := admission(tx, account, final); e != nil {
			return e
		}
		tag, e := tx.Exec(ctx, `INSERT INTO public.identity_avatar_assets(asset_id,account_id,digest,payload,created_at,expires_at) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(asset_id) DO NOTHING`, id, account, hash[:], normalized, final.TrustedAt, final.TrustedAt.Add(24*time.Hour))
		if e != nil {
			return ErrAuthorizationUnavailable
		}
		if tag.RowsAffected() == 0 {
			var matches bool
			if e = tx.QueryRow(ctx, `SELECT account_id=$2 AND digest=$3 AND payload IS NOT NULL FROM public.identity_avatar_assets WHERE asset_id=$1`, id, account, hash[:]).Scan(&matches); e != nil {
				return ErrAuthorizationUnavailable
			}
			if !matches {
				return postError("IDENTITY_AVATAR_INVALID", 409)
			}
		}
		return nil
	})
}

// The caller needs an authorized community session; only a current live profile
// reference (or the owner's unexpired draft) can resolve. No owner metadata is
// returned. Erased/replaced references remain tombstoned and cannot be recycled.
func (c *Community) ReadIdentityAvatar(ctx context.Context, bearer [32]byte, id uuid.UUID) (ImageBytes, time.Time, error) {
	var result ImageBytes
	expires, e := c.withIdentitySession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) error {
		e := tx.QueryRow(ctx, `SELECT m.payload FROM public.identity_avatar_assets m JOIN c_auth.accounts a ON a.account_id=m.account_id
   LEFT JOIN public.community_identities i ON i.identity_id=m.identity_id
   WHERE m.asset_id=$1 AND m.payload IS NOT NULL AND a.state='ACTIVE'
   AND ((m.identity_id IS NULL AND m.account_id=$2 AND m.expires_at>$3)
    OR (i.deleted_at IS NULL AND i.avatar='avatar-v1:'||m.asset_id::text))`, id, account, final.TrustedAt).Scan(&result.Bytes)
		if errors.Is(e, pgx.ErrNoRows) {
			return postError("IDENTITY_AVATAR_NOT_FOUND", 404)
		}
		if e != nil {
			return ErrAuthorizationUnavailable
		}
		result.MIME = "image/webp"
		return nil
	})
	return result, expires, e
}

// Abandon creates a tombstone even if an earlier PUT has not arrived yet. The
// same account lock serializes PUT/bind/abandon; a bound asset is never erased.
func (c *Community) AbandonIdentityAvatar(ctx context.Context, bearer [32]byte, id uuid.UUID) (time.Time, error) {
	if id == uuid.Nil {
		return time.Time{}, postmedia.ErrInvalid
	}
	return c.withIdentitySession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) error {
		var owner uuid.UUID
		var bound *uuid.UUID
		e := tx.QueryRow(ctx, `SELECT account_id,identity_id FROM public.identity_avatar_assets WHERE asset_id=$1`, id).Scan(&owner, &bound)
		if errors.Is(e, pgx.ErrNoRows) {
			_, e = tx.Exec(ctx, `INSERT INTO public.identity_avatar_assets(asset_id,account_id,digest,payload,created_at,expires_at) VALUES($1,$2,$3,NULL,$4,$5)`, id, account, make([]byte, 32), final.TrustedAt, final.TrustedAt.Add(24*time.Hour))
		} else if e == nil {
			if owner != account || bound != nil {
				return postError("IDENTITY_AVATAR_INVALID", 409)
			}
			_, e = tx.Exec(ctx, `UPDATE public.identity_avatar_assets SET payload=NULL WHERE asset_id=$1 AND account_id=$2 AND identity_id IS NULL`, id, account)
		}
		if e != nil {
			return ErrAuthorizationUnavailable
		}
		return nil
	})
}

func identityAvatarAvailable(ctx context.Context, tx pgx.Tx, account, target uuid.UUID, ref string, at time.Time) (bool, error) {
	if ref == IdentityDefaultAvatar {
		return true, nil
	}
	if !ValidIdentityAvatar(ref) {
		return false, nil
	}
	var valid bool
	e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.identity_avatar_assets WHERE asset_id=$1 AND account_id=$2 AND payload IS NOT NULL AND ((identity_id IS NULL AND expires_at>$4) OR identity_id=$3))`, strings.TrimPrefix(ref, "avatar-v1:"), account, target, at).Scan(&valid)
	if e != nil {
		return false, ErrAuthorizationUnavailable
	}
	return valid, nil
}
