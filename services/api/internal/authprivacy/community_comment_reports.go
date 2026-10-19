package authprivacy

import (
	"context"
	"encoding/base64"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
)

// The parent row serializes reports with deletion and comment mutations. The
// snapshot is loaded only in the existing final-authorized report transaction.
func commentReportEvidence(ctx context.Context, tx pgx.Tx, post, id string) (uuid.UUID, uuid.UUID, moderation.Evidence, error) {
	var owner, identity uuid.UUID
	evidence := moderation.Evidence{Images: []moderation.Image{}}
	var installed bool
	if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('c_comments.tasks') AND attname='moderation_hidden' AND NOT attisdropped)`).Scan(&installed); e != nil || !installed {
		return owner, identity, evidence, ErrAuthorizationUnavailable
	}
	var visible bool
	e := tx.QueryRow(ctx, `SELECT visibility='PUBLISHED' AND NOT moderation_hidden FROM c_posts.posts WHERE post_id=$1 FOR SHARE`, post).Scan(&visible)
	if errors.Is(e, pgx.ErrNoRows) || e == nil && !visible {
		return owner, identity, evidence, postError("COMMENT_NOT_FOUND", 404)
	}
	if e != nil {
		return owner, identity, evidence, e
	}
	var task string
	var root *string
	var version int
	var image bool
	e = tx.QueryRow(ctx, `SELECT t.owner_account_id,t.identity_id,x.body,t.task_id,x.version,x.image IS NOT NULL,t.root_comment_id::text
 FROM c_comments.tasks t JOIN c_comments.attempts x USING(task_id)
 WHERE t.comment_id=$1 AND t.post_id=$2 AND t.deleted_at IS NULL AND NOT t.moderation_hidden AND x.state='PUBLISHED'
 AND (t.root_comment_id IS NULL OR EXISTS(SELECT 1 FROM c_comments.tasks r WHERE r.comment_id=t.root_comment_id AND r.deleted_at IS NULL AND NOT r.moderation_hidden)) FOR SHARE OF t`, id, post).Scan(&owner, &identity, &evidence.Body, &task, &version, &image, &root)
	if errors.Is(e, pgx.ErrNoRows) {
		return owner, identity, evidence, postError("COMMENT_NOT_FOUND", 404)
	}
	if e != nil {
		return owner, identity, evidence, e
	}
	evidence.Title = "主评论"
	if root != nil {
		evidence.Title = "回复"
	}
	if image {
		var payload []byte
		var mime string
		if e = tx.QueryRow(ctx, `SELECT payload,metadata->>'mimeType' FROM c_comments.images WHERE task_id=$1 AND version=$2 AND payload IS NOT NULL AND erased_at IS NULL`, task, version).Scan(&payload, &mime); e != nil {
			return owner, identity, evidence, ErrAuthorizationUnavailable
		}
		evidence.Images = append(evidence.Images, moderation.Image{MIME: mime, Base64: base64.StdEncoding.EncodeToString(payload)})
	}
	return owner, identity, evidence, nil
}

func hideModerationTarget(ctx context.Context, tx pgx.Tx, post string, comment *string) error {
	if comment == nil {
		_, e := tx.Exec(ctx, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1 AND visibility='PUBLISHED'`, post)
		return e
	}
	_, e := tx.Exec(ctx, `UPDATE c_comments.tasks SET moderation_hidden=true WHERE comment_id=$1 AND post_id=$2 AND deleted_at IS NULL`, *comment, post)
	return e
}

func restoreModerationTarget(ctx context.Context, tx pgx.Tx, caseID string) error {
	var comment *string
	if e := tx.QueryRow(ctx, `SELECT to_jsonb(c)->>'comment_id' FROM c_moderation.cases c WHERE case_id=$1`, caseID).Scan(&comment); e != nil {
		return e
	}
	if comment != nil {
		_, e := tx.Exec(ctx, `UPDATE c_comments.tasks t SET moderation_hidden=false WHERE t.comment_id=$1 AND t.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM c_moderation.sanctions s JOIN c_moderation.cases c USING(case_id) WHERE c.comment_id=t.comment_id AND s.revoked_at IS NULL AND s.action IN('TAKEDOWN','MUTE','BAN'))`, *comment)
		return e
	}
	_, e := tx.Exec(ctx, `UPDATE c_posts.posts p SET moderation_hidden=false WHERE p.post_id=(SELECT post_id FROM c_moderation.cases WHERE case_id=$1) AND p.visibility='PUBLISHED' AND NOT EXISTS(SELECT 1 FROM c_moderation.sanctions s JOIN c_moderation.cases c USING(case_id) WHERE c.post_id=p.post_id AND to_jsonb(c)->>'comment_id' IS NULL AND s.revoked_at IS NULL AND s.action IN('TAKEDOWN','MUTE','BAN'))`, caseID)
	return e
}
