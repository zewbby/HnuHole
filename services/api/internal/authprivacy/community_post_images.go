package authprivacy

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

type postImageServices struct{ validator postmedia.Validator }
type ImageBytes struct {
	Bytes []byte
	MIME  string
}

// WithPostImages is explicit and fail-closed. The text-only configuration and
// endpoints stay usable without a validator or a media schema.
func (c *Community) WithPostImages(ctx context.Context, v postmedia.Validator) (*Community, error) {
	if !c.PostsEnabled() || v == nil {
		return nil, ErrAuthorizationUnavailable
	}
	var ok bool
	e := c.pool.QueryRow(ctx, `SELECT to_regclass('c_posts.images') IS NOT NULL
 AND EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='c_posts.attempt_contents'::regclass AND attname='image_count' AND NOT attisdropped)
 AND (SELECT count(*)=5 FROM pg_trigger WHERE NOT tgisinternal AND tgenabled='O' AND tgname IN
 ('image_immutable','image_set_shape','image_content_shape','image_publication_shape','image_terminal_erase'))
 AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='c_posts.posts'::regclass AND tgname='image_post_delete_erase' AND tgenabled='O')`).Scan(&ok)
	if e != nil || !ok {
		return nil, ErrAuthorizationUnavailable
	}
	for _, privilege := range []string{"SELECT", "INSERT"} {
		if c.pool.QueryRow(ctx, `SELECT has_table_privilege(current_user,'c_posts.images',$1)`, privilege).Scan(&ok) != nil || !ok {
			return nil, ErrAuthorizationUnavailable
		}
	}
	for _, column := range []string{"payload", "verified_at", "erased_at", "display_width", "display_height", "frames", "cycle_duration_ms", "max_frame_duration_ms", "grant_digest", "grant_expires_at"} {
		if c.pool.QueryRow(ctx, `SELECT has_column_privilege(current_user,'c_posts.images',$1,'UPDATE')`, column).Scan(&ok) != nil || !ok {
			return nil, ErrAuthorizationUnavailable
		}
	}
	clone := *c
	clone.postImages = &postImageServices{validator: v}
	return &clone, nil
}
func (c *Community) PostImagesEnabled() bool {
	return c != nil && c.postImages != nil && c.PostsEnabled()
}

func writePostImages(ctx context.Context, tx pgx.Tx, task string, version int32, items []postmedia.Selection) error {
	for i, s := range items {
		content, e := uuid.NewRandom()
		if e != nil {
			return e
		}
		digest, e := hex.DecodeString(s.SHA256)
		if e != nil {
			return postmedia.ErrInvalid
		}
		if _, e = tx.Exec(ctx, `INSERT INTO c_posts.images(task_id,version,media_id,content_version_id,position,digest,byte_length,mime_type,width,height)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, task, version, s.MediaID, content, i, digest, s.ByteLength, s.MIME, s.Width, s.Height); e != nil {
			return e
		}
	}
	return nil
}

// Upload state is private to the current owner; it contains no upload/read
// capability. A lost response is reconciled here instead of resending a post.
func (c *Community) ReadPostImageUploads(ctx context.Context, bearer [32]byte, task string, version int32) (PostResponse, error) {
	if !c.PostImagesEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if !postmedia.ValidID(task) || version < 1 {
		return PostResponse{}, postmedia.ErrInvalid
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, mute restriction) (any, error) {
		var r postmedia.UploadState
		r.TaskID = task
		r.AttemptVersion = version
		r.Items = []postmedia.UploadItem{}
		if e := materializePostStops(ctx, tx, account); e != nil {
			return nil, e
		}
		if e := tx.QueryRow(ctx, `SELECT post_id FROM c_posts.publication_tasks WHERE task_id=$1 AND owner_account_id=$2 AND latest_attempt_version=$3 AND owner_visible`, task, account, version).Scan(&r.PostID); errors.Is(e, pgx.ErrNoRows) {
			return nil, postError("MEDIA_NOT_FOUND", 404)
		} else if e != nil {
			return nil, e
		}
		rows, e := tx.Query(ctx, `SELECT media_id,position,encode(digest,'hex'),byte_length,mime_type,width,height,(payload IS NOT NULL AND erased_at IS NULL) FROM c_posts.images WHERE task_id=$1 AND version=$2 ORDER BY position`, task, version)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		for rows.Next() {
			var s postmedia.UploadItem
			if e = rows.Scan(&s.MediaID, &s.Position, &s.SHA256, &s.ByteLength, &s.MIME, &s.Width, &s.Height, &s.Uploaded); e != nil {
				return nil, e
			}
			r.Items = append(r.Items, s)
		}
		return r, rows.Err()
	})
}

func activeImageAttempt(ctx context.Context, tx pgx.Tx, account uuid.UUID, task, media string, version int32, final AuthorizationDecision, mute restriction) error {
	if mutedAt(mute, final.TrustedAt) {
		return postError("MEDIA_UPLOAD_CLOSED", 409)
	}
	var active bool
	e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.images m JOIN c_posts.publication_tasks t USING(task_id)
 JOIN c_posts.publication_attempts a ON a.task_id=m.task_id AND a.version=m.version
 JOIN c_posts.account_publication_control ctl ON ctl.account_id=t.owner_account_id
 JOIN c_auth.accounts ac ON ac.account_id=t.owner_account_id JOIN public.community_identities i ON i.identity_id=t.identity_id
 WHERE m.task_id=$1 AND m.version=$2 AND m.media_id=$3 AND t.owner_account_id=$4 AND t.latest_attempt_version=m.version
 AND t.owner_visible AND a.state='ACCEPTED' AND a.accepted_stop_generation=ctl.stop_generation AND ac.state='ACTIVE'
 AND i.deleted_at IS NULL AND m.erased_at IS NULL AND $5<a.accepted_at+interval '24 hours')`, task, version, media, account, final.TrustedAt).Scan(&active)
	if e != nil {
		return ErrAuthorizationUnavailable
	}
	if !active {
		return postError("MEDIA_UPLOAD_CLOSED", 409)
	}
	return nil
}

// A random, per-item 15 minute upload-only capability. New grants rotate the
// previous grant for this item. Plaintext exists only in the HTTPS response.
func (c *Community) IssuePostImageGrant(ctx context.Context, bearer [32]byte, task, media string, version int32) (PostResponse, error) {
	if !c.PostImagesEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if !postmedia.ValidID(task) || !postmedia.ValidID(media) || version < 1 {
		return PostResponse{}, postmedia.ErrInvalid
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, mute restriction) (any, error) {
		if e := activeImageAttempt(ctx, tx, account, task, media, version, final, mute); e != nil {
			return nil, e
		}
		var accepted time.Time
		if e := tx.QueryRow(ctx, `SELECT accepted_at FROM c_posts.publication_attempts WHERE task_id=$1 AND version=$2`, task, version).Scan(&accepted); e != nil {
			return nil, e
		}
		expires := final.TrustedAt.Add(15 * time.Minute)
		if deadline := accepted.Add(24 * time.Hour); expires.After(deadline) {
			expires = deadline
		}
		token, e := random32()
		if e != nil {
			return nil, e
		}
		digest := sha256.Sum256(token[:])
		if _, e = tx.Exec(ctx, `UPDATE c_posts.images SET grant_digest=$4,grant_expires_at=$5 WHERE task_id=$1 AND version=$2 AND media_id=$3`, task, version, media, digest[:], expires); e != nil {
			return nil, e
		}
		return postmedia.Grant{TaskID: task, MediaID: media, AttemptVersion: version, UploadToken: protocol.EncodeCanonicalBase64url(token[:]), ExpiresAt: expires.UTC().Format(time.RFC3339Nano)}, nil
	})
}

// UploadPostImage does not authenticate an old session: it is allowed solely by
// the already accepted task's exact-byte item capability. It never reads bytes,
// changes an identity/channel/manifest, or authorizes another client mutation.
func (c *Community) UploadPostImage(ctx context.Context, token [32]byte, task, media string, version int32, data []byte, mime string) (time.Time, error) {
	if !c.PostImagesEnabled() {
		return time.Time{}, ErrAuthorizationUnavailable
	}
	if !postmedia.ValidID(task) || !postmedia.ValidID(media) || version < 1 || len(data) < 1 || len(data) > postmedia.MaxBytes {
		return time.Time{}, postmedia.ErrInvalid
	}
	decision, e := c.gate.Snapshot(ctx)
	if e != nil {
		return time.Time{}, e
	}
	// Preliminary capability/length/hash check avoids decoding arbitrary traffic;
	// everything is rechecked inside the final Gate transaction after inspection.
	grantDigest := sha256.Sum256(token[:])
	hash := sha256.Sum256(data)
	var s postmedia.Selection
	var account uuid.UUID
	var storedHash []byte
	e = c.pool.QueryRow(ctx, `SELECT t.owner_account_id,m.media_id,m.digest,m.byte_length,m.mime_type,m.width,m.height
 FROM c_posts.images m JOIN c_posts.publication_tasks t USING(task_id)
 WHERE m.task_id=$1 AND m.version=$2 AND m.media_id=$3 AND m.grant_digest=$4 AND m.erased_at IS NULL`, task, version, media, grantDigest[:]).Scan(&account, &s.MediaID, &storedHash, &s.ByteLength, &s.MIME, &s.Width, &s.Height)
	if errors.Is(e, pgx.ErrNoRows) {
		return time.Time{}, postError("MEDIA_UPLOAD_DENIED", 403)
	}
	if e != nil {
		return time.Time{}, ErrAuthorizationUnavailable
	}
	s.SHA256 = hex.EncodeToString(storedHash)
	if s.SHA256 != hex.EncodeToString(hash[:]) || len(data) != s.ByteLength || s.MIME != mime {
		return time.Time{}, postmedia.ErrInvalid
	}
	metadata, e := c.postImages.validator.Inspect(ctx, data)
	if e != nil {
		return time.Time{}, e
	}
	if !metadata.Matches(s, data) {
		return time.Time{}, postmedia.ErrInvalid
	}
	tx, e := begin(ctx, c.pool)
	if e != nil {
		return time.Time{}, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state string
	if e = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&state); e != nil {
		return time.Time{}, ErrAuthorizationUnavailable
	}
	ban, e := lockRestriction(ctx, tx, account)
	if e != nil {
		return time.Time{}, e
	}
	var mute restriction
	if e = tx.QueryRow(ctx, `SELECT mute_state,mute_ends_at FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&mute.state, &mute.ends); e != nil {
		return time.Time{}, e
	}
	var at time.Time
	_, e = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if e := c.checkPostProtocolKeys(ctx, tx); e != nil {
			return e
		}
		if state != "ACTIVE" || bannedAt(ban, final.TrustedAt) {
			return postError("MEDIA_UPLOAD_CLOSED", 409)
		}
		if e := activeImageAttempt(ctx, tx, account, task, media, version, final, mute); e != nil {
			return e
		}
		var permitted, uploaded bool
		if e := tx.QueryRow(ctx, `SELECT grant_digest=$4 AND grant_expires_at>$5,payload IS NOT NULL FROM c_posts.images WHERE task_id=$1 AND version=$2 AND media_id=$3`, task, version, media, grantDigest[:], final.TrustedAt).Scan(&permitted, &uploaded); e != nil {
			return postError("MEDIA_UPLOAD_DENIED", 403)
		}
		if !permitted {
			return postError("MEDIA_UPLOAD_DENIED", 403)
		}
		at = final.TrustedAt.UTC()
		if uploaded {
			return nil
		} // lost PUT response: same bytes are idempotent
		_, e := tx.Exec(ctx, `UPDATE c_posts.images SET payload=$4,display_width=$5,display_height=$6,frames=$7,verified_at=$8,cycle_duration_ms=$9,max_frame_duration_ms=$10 WHERE task_id=$1 AND version=$2 AND media_id=$3 AND payload IS NULL`, task, version, media, data, metadata.DisplayWidth, metadata.DisplayHeight, metadata.Frames, at, metadata.CycleDurationMS, metadata.MaxFrameDurationMS)
		return e
	})
	if errors.Is(e, errPostProtocolIntegrity) {
		_ = c.gate.Abort(ctx, tx)
		e = c.freezePostProtocol(ctx)
	}
	return at, e
}

// Protected paths contain no capability. Every manifest/original fetch repeats
// the same host-held Bearer + session generation + final C Gate transaction.
func (c *Community) ReadPostImages(ctx context.Context, bearer [32]byte, post, content string) (PostResponse, error) {
	if !c.PostImagesEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if !postmedia.ValidID(post) || (content != "" && !postmedia.ValidID(content)) {
		return PostResponse{}, postmedia.ErrInvalid
	}
	response, e := c.withPostSession(ctx, bearer, func(tx pgx.Tx, _ uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
		// Serialize the resource visibility check with deletion. No author
		// account lock is acquired after the caller's account lock.
		var published string
		if e := tx.QueryRow(ctx, `SELECT visibility FROM c_posts.posts p WHERE post_id=$1 AND visibility='PUBLISHED' AND NOT COALESCE((to_jsonb(p)->>'moderation_hidden')::boolean,false) FOR SHARE`, post).Scan(&published); errors.Is(e, pgx.ErrNoRows) {
			return nil, postError("MEDIA_NOT_FOUND", 404)
		} else if e != nil {
			return nil, e
		}
		if content != "" {
			var b ImageBytes
			e := tx.QueryRow(ctx, `SELECT m.payload,m.mime_type FROM c_posts.images m JOIN c_posts.publication_tasks t USING(task_id) JOIN c_posts.posts p USING(post_id)
    WHERE p.post_id=$1 AND p.visibility='PUBLISHED' AND m.version=p.published_attempt_version AND m.content_version_id=$2 AND m.erased_at IS NULL AND m.verified_at IS NOT NULL AND m.payload IS NOT NULL`, post, content).Scan(&b.Bytes, &b.MIME)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("MEDIA_NOT_FOUND", 404)
			}
			return b, e
		}
		group := postmedia.Group{PostID: post, Images: []postmedia.Image{}, AccessValidUntil: final.TrustedAt.Add(time.Minute).UTC().Format(time.RFC3339Nano)}
		rows, e := tx.Query(ctx, `SELECT m.media_id,m.content_version_id,m.position,m.width,m.height,m.display_width,m.display_height,m.frames,m.mime_type,m.byte_length
   FROM c_posts.images m JOIN c_posts.publication_tasks t USING(task_id) JOIN c_posts.posts p USING(post_id)
   WHERE p.post_id=$1 AND m.version=p.published_attempt_version AND m.erased_at IS NULL AND m.verified_at IS NOT NULL AND m.payload IS NOT NULL ORDER BY position`, post)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		for rows.Next() {
			var item postmedia.Image
			var mime string
			var size int
			if e = rows.Scan(&item.MediaID, &item.ContentVersionID, &item.Position, &item.Width, &item.Height, &item.PixelWidth, &item.PixelHeight, &item.Frames, &mime, &size); e != nil {
				return nil, e
			}
			item.Animated = item.Frames > 1
			item.SaveAllowed = true
			// v1 reuses the full original as a preview source: explicit, lossless and
			// animation-preserving. It makes no bandwidth-saving derivative claim.
			source := postmedia.Source{Path: "/api/v1/posts/" + post + "/images/" + item.ContentVersionID + "/original", MIME: mime, ByteLength: size}
			item.Thumbnail = source
			item.Full = source
			item.Original = source
			group.Images = append(group.Images, item)
		}
		if e = rows.Err(); e != nil {
			return nil, e
		}
		var expected int
		if e = tx.QueryRow(ctx, `SELECT x.image_count FROM c_posts.posts p JOIN c_posts.publication_tasks t USING(post_id) JOIN c_posts.attempt_contents x ON x.task_id=t.task_id AND x.version=p.published_attempt_version WHERE p.post_id=$1`, post).Scan(&expected); e != nil {
			return nil, e
		}
		if expected != len(group.Images) {
			return nil, ErrAuthorizationUnavailable
		}
		return group, nil
	})
	if e == nil {
		if group, ok := response.Value.(postmedia.Group); ok {
			until, _ := time.Parse(time.RFC3339Nano, group.AccessValidUntil)
			if until.After(response.ExpiresAt) {
				group.AccessValidUntil = response.ExpiresAt.Format(time.RFC3339Nano)
			}
			response.Value = group
		}
	}
	return response, e
}

// Worker checks the entire immutable set again under its final authorization,
// including SQL byte length/hash. No partial post becomes public.
func (c *Community) postImagesReady(ctx context.Context, tx pgx.Tx, task uuid.UUID, version int32, at time.Time) (bool, error) {
	var count int
	if e := tx.QueryRow(ctx, `SELECT COALESCE((to_jsonb(x)->>'image_count')::int,0) FROM c_posts.attempt_contents x WHERE task_id=$1 AND version=$2`, task, version).Scan(&count); e != nil {
		return false, e
	}
	if count == 0 {
		return true, nil
	}
	if !c.PostImagesEnabled() {
		return false, nil
	}
	var ready bool
	e := tx.QueryRow(ctx, `SELECT count(*)=$3 AND bool_and(verified_at IS NOT NULL AND erased_at IS NULL AND payload IS NOT NULL AND octet_length(payload)=byte_length AND sha256(payload)=digest) FROM c_posts.images WHERE task_id=$1 AND version=$2`, task, version, count).Scan(&ready)
	if e != nil {
		return false, e
	}
	if !ready {
		// Expiry uses the final trusted clock, never a client or SQL wall clock.
		_, e = tx.Exec(ctx, `UPDATE c_posts.publication_attempts SET state='FAILED',terminal_at=$3,failure_code='PUBLICATION_FAILED' WHERE task_id=$1 AND version=$2 AND state='ACCEPTED' AND accepted_at+interval '24 hours'<=$3`, task, version, at)
	}
	return ready, e
}

// No additional storage or public URL: the original read repeats the same
// resource/session/Gate transaction before the bounded, stateless transform.
func (c *Community) PostImageThumbnailsEnabled() bool {
	if !c.PostImagesEnabled() {
		return false
	}
	_, ok := c.postImages.validator.(postmedia.Thumbnailer)
	return ok
}

func (c *Community) ReadPostThumbnail(ctx context.Context, bearer [32]byte, post, content string) (PostResponse, error) {
	if !c.PostImageThumbnailsEnabled() {
		return PostResponse{}, postmedia.ErrUnavailable
	}
	response, e := c.ReadPostImages(ctx, bearer, post, content)
	if e != nil {
		return PostResponse{}, e
	}
	original, ok := response.Value.(ImageBytes)
	if !ok {
		return PostResponse{}, postmedia.ErrUnavailable
	}
	data, e := c.postImages.validator.(postmedia.Thumbnailer).Thumbnail(ctx, original.Bytes)
	if e != nil {
		return PostResponse{}, e
	}
	// Transformation happens outside SQL. Recheck the resource and final Gate
	// after CPU work, so deletion, logout or a freeze during encoding wins.
	final, e := c.ReadPostImages(ctx, bearer, post, "")
	if e != nil {
		return PostResponse{}, e
	}
	final.Value = ImageBytes{Bytes: data, MIME: "image/webp"}
	return final, nil
}
