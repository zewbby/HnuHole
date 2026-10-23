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
)

func (c *Community) ModerationEnabled() bool { return c != nil && c.moderationEnabled }
func (c *Community) inspectModerationImages(ctx context.Context, items []moderation.Image, max int) error {
	raw, e := moderation.Images(items, max)
	if e != nil {
		return moderation.ErrInvalid
	}
	if len(raw) == 0 {
		return nil
	}
	if !c.PostImagesEnabled() {
		return ErrAuthorizationUnavailable
	}
	for i, b := range raw {
		m, e := c.postImages.validator.Inspect(ctx, b)
		if e != nil || m.MIME != items[i].MIME {
			return moderation.ErrInvalid
		}
	}
	return nil
}
func notification(ctx context.Context, tx pgx.Tx, account uuid.UUID, identity *string, event, kind, state, title, body, route, resource string, at time.Time) error {
	_, e := tx.Exec(ctx, `INSERT INTO c_moderation.notifications(notification_id,event_id,account_id,identity_id,kind,state,title,body,route_name,resource_id,created_at) SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11 WHERE EXISTS(SELECT 1 FROM c_auth.accounts WHERE account_id=$3 AND state<>'CLOSED') ON CONFLICT(account_id,event_id) DO NOTHING`, uuid.New(), event, account, identity, kind, state, title, body, route, resource, at)
	return e
}
func readReport(ctx context.Context, tx pgx.Tx, account uuid.UUID, request string) (moderation.ReportResult, error) {
	out := moderation.ReportResult{State: "NOT_SUBMITTED"}
	var r moderation.Report
	e := tx.QueryRow(ctx, `SELECT r.request_id,c.case_id,c.state,COALESCE(c.post_id::text,''),r.reason,r.description,r.created_at,c.outcome,c.explanation,to_jsonb(c)->>'comment_id',to_jsonb(c)->>'conversation_id' FROM c_moderation.reports r JOIN c_moderation.cases c USING(case_id) WHERE r.reporter_account_id=$1 AND r.request_id=$2`, account, request).Scan(&r.ID, &r.CaseID, &r.State, &r.PostID, &r.Reason, &r.Description, &r.CreatedAt, &r.Outcome, &r.Explanation, &r.CommentID, &r.ConversationID)
	r.CreatedAt = r.CreatedAt.UTC()
	if errors.Is(e, pgx.ErrNoRows) {
		return out, nil
	}
	if e != nil {
		return out, e
	}
	out.State = "SUBMITTED"
	out.Report = &r
	return out, nil
}
func (c *Community) GetReport(ctx context.Context, bearer [32]byte, request string) (PostResponse, error) {
	if !c.ModerationEnabled() || !moderation.ValidID(request) {
		return PostResponse{}, moderation.ErrInvalid
	}
	return c.withModerationSession(ctx, bearer, false, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision) (any, error) {
		result, e := readReport(ctx, tx, account, request)
		if e == nil && result.State == "NOT_SUBMITTED" {
			result.RetryToken, e = sealModerationAttempt(ctx, tx, account, "REPORT", "", request)
		}
		return result, e
	})
}
func (c *Community) SubmitReport(ctx context.Context, bearer [32]byte, request string, input moderation.ReportInput) (PostResponse, error) {
	if !c.ModerationEnabled() || !moderation.ValidID(request) || input.Validate() != nil {
		return PostResponse{}, moderation.ErrInvalid
	}
	if e := c.inspectModerationImages(ctx, input.Images, 6); e != nil {
		return PostResponse{}, e
	}
	return c.withModerationSession(ctx, bearer, false, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) (any, error) {
		fingerprintInput := input
		fingerprintInput.RetryToken = ""
		fingerprint := moderation.Fingerprint(fingerprintInput)
		var stored string
		e := tx.QueryRow(ctx, `SELECT fingerprint FROM c_moderation.reports WHERE reporter_account_id=$1 AND request_id=$2`, account, request).Scan(&stored)
		if e == nil {
			if stored != fingerprint {
				return nil, postError("REQUEST_CONFLICT", 409)
			}
			return readReport(ctx, tx, account, request)
		}
		if !errors.Is(e, pgx.ErrNoRows) {
			return nil, e
		}
		if e = checkModerationAttempt(ctx, tx, account, "REPORT", "", request, input.RetryToken); e != nil {
			return nil, e
		}
		if input.IdentityID != nil {
			var exists bool
			if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE identity_id=$1 AND account_id=$2 AND deleted_at IS NULL)`, *input.IdentityID, account).Scan(&exists); e != nil {
				return nil, e
			}
			if !exists {
				return nil, postError("IDENTITY_UNAVAILABLE", 404)
			}
		}
		var target, identity uuid.UUID
		var evidence moderation.Evidence
		var task string
		var version int
		var expectedImages int
		if input.CommentID != nil {
			target, identity, evidence, e = commentReportEvidence(ctx, tx, input.PostID, *input.CommentID)
			if e != nil {
				return nil, e
			}
		} else {
			e = tx.QueryRow(ctx, `SELECT p.owner_account_id,t.identity_id,x.title,x.body,t.task_id,p.published_attempt_version,COALESCE((to_jsonb(x)->>'image_count')::int,0) FROM c_posts.posts p JOIN c_posts.publication_tasks t USING(post_id) JOIN c_posts.attempt_contents x ON x.task_id=t.task_id AND x.version=p.published_attempt_version WHERE p.post_id=$1 AND p.visibility='PUBLISHED' AND NOT p.moderation_hidden FOR SHARE OF p`, input.PostID).Scan(&target, &identity, &evidence.Title, &evidence.Body, &task, &version, &expectedImages)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("POST_NOT_FOUND", 404)
			}
			if e != nil {
				return nil, e
			}
			evidence.Images = []moderation.Image{}
			var mediaSchema bool
			if e = tx.QueryRow(ctx, `SELECT to_regclass('c_posts.images') IS NOT NULL`).Scan(&mediaSchema); e != nil {
				return nil, e
			}
			if mediaSchema {
				rows, e := tx.Query(ctx, `SELECT mime_type,payload FROM c_posts.images WHERE task_id=$1 AND version=$2 AND verified_at IS NOT NULL AND erased_at IS NULL ORDER BY position`, task, version)
				if e != nil {
					return nil, e
				}
				for rows.Next() {
					var mime string
					var b []byte
					if e = rows.Scan(&mime, &b); e != nil {
						break
					}
					evidence.Images = append(evidence.Images, moderation.Image{MIME: mime, Base64: base64.StdEncoding.EncodeToString(b)})
				}
				if e == nil {
					e = rows.Err()
				}
				rows.Close()
				if e != nil {
					return nil, e
				}
			}
			if len(evidence.Images) != expectedImages {
				return nil, ErrAuthorizationUnavailable
			}
		}
		payload, e := json.Marshal(evidence)
		if e != nil {
			return nil, e
		}
		caseID := uuid.New()
		snapshot := moderation.Fingerprint(evidence)
		if input.CommentID != nil {
			// Separate resource facts even when two comments contain identical bytes.
			snapshot = moderation.Fingerprint([]any{"COMMENT", *input.CommentID, evidence})
			e = tx.QueryRow(ctx, `INSERT INTO c_moderation.cases(case_id,post_id,comment_id,target_account_id,target_identity_id,reason,snapshot_digest,evidence,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(post_id,snapshot_digest) DO UPDATE SET version=c_moderation.cases.version RETURNING case_id`, caseID, input.PostID, *input.CommentID, target, identity, input.Reason, snapshot, payload, final.TrustedAt).Scan(&caseID)
		} else {
			e = tx.QueryRow(ctx, `INSERT INTO c_moderation.cases(case_id,post_id,target_account_id,target_identity_id,reason,snapshot_digest,evidence,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(post_id,snapshot_digest) DO UPDATE SET version=c_moderation.cases.version RETURNING case_id`, caseID, input.PostID, target, identity, input.Reason, snapshot, payload, final.TrustedAt).Scan(&caseID)
		}
		if e != nil {
			return nil, e
		}
		reportID := uuid.New()
		images, _ := json.Marshal(input.Images)
		if _, e = tx.Exec(ctx, `INSERT INTO c_moderation.reports(report_id,request_id,reporter_account_id,identity_id,case_id,reason,fingerprint,description,images,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, reportID, request, account, input.IdentityID, caseID, input.Reason, fingerprint, input.Description, images, final.TrustedAt); e != nil {
			return nil, e
		}
		result, e := readReport(ctx, tx, account, request)
		if e != nil {
			return nil, e
		}
		title := "举报已提交，等待处理"
		kind := "REPORT_PROGRESS"
		if result.Report.State == "ENDED" {
			title = "举报已结束"
			kind = "REPORT_RESULT"
		}
		if e = notification(ctx, tx, account, input.IdentityID, "report:"+reportID.String()+":submitted", kind, result.Report.State, title, result.Report.Explanation, "REPORT", request, final.TrustedAt); e != nil {
			return nil, e
		}
		return result, nil
	})
}
func scanNotification(row pgx.Row) (moderation.Notification, error) {
	var n moderation.Notification
	n.Source = "SERVER"
	e := row.Scan(&n.ID, &n.EventID, &n.IdentityID, &n.Kind, &n.State, &n.Title, &n.Body, &n.CreatedAt, &n.ReadAt, &n.Route.Name, &n.Route.ResourceID)
	n.CreatedAt = n.CreatedAt.UTC()
	n.ReadAt = moderationTimeUTC(n.ReadAt)
	n.Scope = "ACCOUNT"
	if n.IdentityID != nil {
		n.Scope = "IDENTITY"
	}
	return n, e
}

const notificationFields = `notification_id,event_id,identity_id,kind,state,title,body,created_at,read_at,route_name,resource_id`

func (c *Community) ReadSystemNotifications(ctx context.Context, bearer [32]byte, id, identity, before string, limit int, markRead bool) (PostResponse, error) {
	if !c.ModerationEnabled() || id != "" && !moderation.ValidID(id) || identity != "" && !moderation.ValidID(identity) {
		return PostResponse{}, moderation.ErrInvalid
	}
	if limit == 0 {
		limit = 50
	}
	if limit < 1 || limit > 50 {
		return PostResponse{}, moderation.ErrInvalid
	}
	var beforeAt any
	var beforeID any
	if before != "" {
		parts := strings.Split(before, "|")
		if len(parts) != 2 || !moderation.ValidID(parts[1]) {
			return PostResponse{}, moderation.ErrInvalid
		}
		at, e := time.Parse(time.RFC3339Nano, parts[0])
		if e != nil {
			return PostResponse{}, moderation.ErrInvalid
		}
		beforeAt = at
		beforeID = parts[1]
	}
	return c.withModerationSession(ctx, bearer, true, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) (any, error) {
		restricted, e := moderationAccessOnly(ctx, tx, bearer)
		if e != nil {
			return nil, e
		}
		if restricted && identity != "" {
			return nil, postError("MODERATION_FORBIDDEN", 403)
		}
		var selected any
		if identity != "" {
			var exists bool
			if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE account_id=$1 AND identity_id=$2 AND deleted_at IS NULL)`, account, identity).Scan(&exists); e != nil {
				return nil, e
			}
			if !exists {
				return nil, postError("IDENTITY_UNAVAILABLE", 404)
			}
			selected = identity
		}
		ownership := ` account_id=$1 AND (identity_id IS NULL OR EXISTS(SELECT 1 FROM public.community_identities i WHERE i.identity_id=c_moderation.notifications.identity_id AND i.account_id=$1 AND i.deleted_at IS NULL))`
		if restricted {
			ownership += ` AND identity_id IS NULL AND kind IN ('SANCTION','APPEAL_RESULT')`
		}
		if id != "" {
			ownership += ` AND (identity_id IS NULL OR identity_id=$4)`
			if markRead {
				_, e := tx.Exec(ctx, `UPDATE c_moderation.notifications SET read_at=COALESCE(read_at,$3) WHERE notification_id=$2 AND`+ownership, account, id, final.TrustedAt, selected)
				if e != nil {
					return nil, e
				}
			}
			n, e := scanNotification(tx.QueryRow(ctx, `SELECT `+notificationFields+` FROM c_moderation.notifications WHERE notification_id=$2 AND $3::boolean=true AND`+ownership, account, id, true, selected))
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("NOTIFICATION_NOT_FOUND", 404)
			}
			return n, e
		}
		rows, e := tx.Query(ctx, `SELECT `+notificationFields+` FROM c_moderation.notifications WHERE`+ownership+` AND (identity_id IS NULL OR identity_id=$2) AND ($3::timestamptz IS NULL OR (created_at,notification_id)<($3,$4::uuid)) ORDER BY created_at DESC,notification_id DESC LIMIT $5`, account, selected, beforeAt, beforeID, limit+1)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		page := moderation.NotificationPage{Items: []moderation.Notification{}}
		for rows.Next() {
			n, e := scanNotification(rows)
			if e != nil {
				return nil, e
			}
			page.Items = append(page.Items, n)
		}
		if e = rows.Err(); e != nil {
			return nil, e
		}
		if len(page.Items) > limit {
			page.Items = page.Items[:limit]
			last := page.Items[limit-1]
			cursor := last.CreatedAt.Format(time.RFC3339Nano) + "|" + last.ID
			page.NextBefore = &cursor
		}
		return page, nil
	})
}
