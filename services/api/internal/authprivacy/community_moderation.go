package authprivacy

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
)

func moderationRole(ctx context.Context, tx pgx.Tx, actor uuid.UUID) (string, error) {
	var role string
	e := tx.QueryRow(ctx, `SELECT role FROM c_moderation.roles WHERE account_id=$1 FOR SHARE`, actor).Scan(&role)
	if errors.Is(e, pgx.ErrNoRows) {
		return "", postError("MODERATION_FORBIDDEN", 403)
	}
	return role, e
}
func moderationNumber(ctx context.Context, tx pgx.Tx, account uuid.UUID) (string, error) {
	var number string
	e := tx.QueryRow(ctx, `SELECT number FROM c_moderation.platform_numbers WHERE account_id=$1`, account).Scan(&number)
	return number, e
}

const caseFields = `c.case_id,c.number::text,COALESCE(c.post_id::text,''),c.reason,c.state,c.version,c.created_at,n.number,c.outcome,c.explanation,to_jsonb(c)->>'comment_id',to_jsonb(c)->>'conversation_id'`

func scanCase(row pgx.Row) (moderation.Case, error) {
	var c moderation.Case
	e := row.Scan(&c.ID, &c.Number, &c.PostID, &c.Reason, &c.State, &c.Version, &c.CreatedAt, &c.PlatformNumber, &c.Outcome, &c.Explanation, &c.CommentID, &c.ConversationID)
	c.CreatedAt = c.CreatedAt.UTC()
	return c, e
}
func readCase(ctx context.Context, tx pgx.Tx, id string, detail bool) (moderation.Case, error) {
	out, e := scanCase(tx.QueryRow(ctx, `SELECT `+caseFields+` FROM c_moderation.cases c JOIN c_moderation.platform_numbers n ON n.account_id=c.target_account_id WHERE c.case_id=$1`, id))
	if e != nil {
		return out, e
	}
	if !detail {
		return out, nil
	}
	var payload []byte
	if e = tx.QueryRow(ctx, `SELECT evidence FROM c_moderation.cases WHERE case_id=$1`, id).Scan(&payload); e != nil {
		return out, e
	}
	var evidence moderation.Evidence
	if e = json.Unmarshal(payload, &evidence); e != nil {
		return out, e
	}
	out.Evidence = &evidence
	page, e := readModerationMaterialPage(ctx, tx, "REPORT", id, "")
	if e != nil {
		return out, e
	}
	out.Reports = page.Items
	out.NextReportsCursor = page.NextCursor
	rows, e := tx.Query(ctx, `SELECT sanction_id FROM c_moderation.sanctions WHERE case_id=$1 ORDER BY starts_at,sanction_id`, id)
	if e != nil {
		return out, e
	}
	ids := []string{}
	for rows.Next() {
		var s string
		if e = rows.Scan(&s); e != nil {
			break
		}
		ids = append(ids, s)
	}
	if e == nil {
		e = rows.Err()
	}
	rows.Close()
	if e != nil {
		return out, e
	}
	for _, s := range ids {
		v, e := readSanction(ctx, tx, s, uuid.Nil)
		if e != nil {
			return out, e
		}
		out.Sanctions = append(out.Sanctions, v)
	}
	return out, nil
}
func readSanction(ctx context.Context, tx pgx.Tx, id string, account uuid.UUID) (moderation.Sanction, error) {
	var s moderation.Sanction
	e := tx.QueryRow(ctx, `SELECT s.sanction_id,s.case_id,s.action,s.reason,s.starts_at,s.ends_at,s.revoked_at,COALESCE(c.post_id::text,''),(SELECT count(*) FROM c_moderation.appeals a WHERE a.sanction_id=s.sanction_id),(SELECT a.appeal_id FROM c_moderation.appeals a WHERE a.sanction_id=s.sanction_id AND a.state='PENDING'),to_jsonb(c)->>'comment_id',to_jsonb(c)->>'conversation_id' FROM c_moderation.sanctions s JOIN c_moderation.cases c USING(case_id) WHERE s.sanction_id=$1 AND ($2::uuid IS NULL OR s.account_id=$2)`, id, nullableUUID(account)).Scan(&s.ID, &s.CaseID, &s.Action, &s.Reason, &s.StartsAt, &s.EndsAt, &s.RevokedAt, &s.PostID, &s.AppealCount, &s.ActiveAppealID, &s.CommentID, &s.ConversationID)
	s.StartsAt = s.StartsAt.UTC()
	s.EndsAt = moderationTimeUTC(s.EndsAt)
	s.RevokedAt = moderationTimeUTC(s.RevokedAt)
	return s, e
}
func moderationTimeUTC(value *time.Time) *time.Time {
	if value == nil {
		return nil
	}
	u := value.UTC()
	return &u
}
func nullableUUID(id uuid.UUID) any {
	if id == uuid.Nil {
		return nil
	}
	return id
}
func (c *Community) ReadSanction(ctx context.Context, bearer [32]byte, id string) (PostResponse, error) {
	if !moderation.ValidID(id) {
		return PostResponse{}, moderation.ErrInvalid
	}
	return c.withModerationSession(ctx, bearer, true, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision) (any, error) {
		s, e := readSanction(ctx, tx, id, account)
		if errors.Is(e, pgx.ErrNoRows) {
			return nil, postError("SANCTION_NOT_FOUND", 404)
		}
		return s, e
	})
}
func auditModeration(ctx context.Context, tx pgx.Tx, actor, target uuid.UUID, caseID, action, reason string, at time.Time) error {
	a, e := moderationNumber(ctx, tx, actor)
	if e != nil {
		return e
	}
	t, e := moderationNumber(ctx, tx, target)
	if e != nil {
		return e
	}
	var caseRef any
	if caseID != "" {
		caseRef = caseID
	}
	_, e = tx.Exec(ctx, `INSERT INTO c_moderation.audit(actor_number,target_number,case_id,action,reason,created_at) VALUES($1,$2,$3,$4,$5,$6)`, a, t, caseRef, action, reason, at)
	return e
}
func commandResult(ctx context.Context, tx pgx.Tx, actor uuid.UUID, key, fp string) (any, bool, error) {
	var stored string
	var b []byte
	e := tx.QueryRow(ctx, `SELECT fingerprint,result FROM c_moderation.commands WHERE actor_id=$1 AND command_id=$2`, actor, key).Scan(&stored, &b)
	if errors.Is(e, pgx.ErrNoRows) {
		return nil, false, nil
	}
	if e != nil {
		return nil, false, e
	}
	if stored != fp {
		return nil, true, postError("REQUEST_CONFLICT", 409)
	}
	var v any
	e = json.Unmarshal(b, &v)
	return v, true, e
}
func storeModerationCommand(ctx context.Context, tx pgx.Tx, actor uuid.UUID, key, fp string, result any) error {
	b, e := json.Marshal(result)
	if e != nil {
		return e
	}
	_, e = tx.Exec(ctx, `INSERT INTO c_moderation.commands VALUES($1,$2,$3,$4)`, actor, key, fp, b)
	return e
}
func notifyReporters(ctx context.Context, tx pgx.Tx, caseID, kind, state, title, body string, at time.Time) error {
	rows, e := tx.Query(ctx, `SELECT report_id,request_id,reporter_account_id,identity_id FROM c_moderation.reports WHERE case_id=$1 AND reporter_account_id IS NOT NULL`, caseID)
	if e != nil {
		return e
	}
	type receiver struct {
		id, request string
		account     uuid.UUID
		identity    *string
	}
	all := []receiver{}
	for rows.Next() {
		var r receiver
		if e = rows.Scan(&r.id, &r.request, &r.account, &r.identity); e != nil {
			break
		}
		all = append(all, r)
	}
	if e == nil {
		e = rows.Err()
	}
	rows.Close()
	if e != nil {
		return e
	}
	for _, r := range all {
		if e = notification(ctx, tx, r.account, r.identity, "report:"+r.id+":"+state, kind, state, title, body, "REPORT", r.request, at); e != nil {
			return e
		}
	}
	return nil
}

// ReadModeration emits explicit DTOs. It never serializes an internal account row.
func (c *Community) ReadModeration(ctx context.Context, bearer [32]byte, kind, id, number, before string, limit int) (PostResponse, error) {
	if !c.ModerationEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if id != "" && !moderation.ValidID(id) {
		return PostResponse{}, moderation.ErrInvalid
	}
	if limit == 0 {
		limit = 50
	}
	if limit < 1 || limit > 50 {
		return PostResponse{}, moderation.ErrInvalid
	}
	var role string
	return c.withModerationAccountsSession(ctx, bearer, uuid.Nil, func(tx pgx.Tx, actor uuid.UUID) error {
		var e error
		role, e = moderationRole(ctx, tx, actor)
		return e
	}, func(tx pgx.Tx, actor uuid.UUID, _ AuthorizationDecision) (any, error) {
		switch kind {
		case "me":
			n, e := moderationNumber(ctx, tx, actor)
			return map[string]any{"role": role, "platformNumber": n}, e
		case "case":
			v, e := readCase(ctx, tx, id, true)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("CASE_NOT_FOUND", 404)
			}
			if e == nil && v.ConversationID != nil {
				var target uuid.UUID
				e = tx.QueryRow(ctx, `SELECT target_account_id FROM c_moderation.cases WHERE case_id=$1`, id).Scan(&target)
				if e == nil {
					e = auditModeration(ctx, tx, actor, target, id, "READ_DM_EVIDENCE", "查看已明确授权的私信证据", time.Now().UTC())
				}
			}
			return v, e
		case "cases":
			var cutoff, cutoffID any
			if before != "" {
				parts := strings.Split(before, "|")
				if len(parts) != 2 || !moderation.ValidID(parts[1]) {
					return nil, moderation.ErrInvalid
				}
				at, e := time.Parse(time.RFC3339Nano, parts[0])
				if e != nil {
					return nil, moderation.ErrInvalid
				}
				cutoff = at
				cutoffID = parts[1]
			}
			rows, e := tx.Query(ctx, `SELECT `+caseFields+` FROM c_moderation.cases c JOIN c_moderation.platform_numbers n ON n.account_id=c.target_account_id WHERE ($1::timestamptz IS NULL OR (c.created_at,c.case_id)<($1,$2::uuid)) ORDER BY c.created_at DESC,c.case_id DESC LIMIT $3`, cutoff, cutoffID, limit+1)
			if e != nil {
				return nil, e
			}
			items := []moderation.Case{}
			for rows.Next() {
				v, e := scanCase(rows)
				if e != nil {
					rows.Close()
					return nil, e
				}
				items = append(items, v)
			}
			e = rows.Err()
			rows.Close()
			var next *string
			if len(items) > limit {
				items = items[:limit]
				s := items[limit-1].CreatedAt.Format(time.RFC3339Nano) + "|" + items[limit-1].ID
				next = &s
			}
			return map[string]any{"items": items, "nextBefore": next}, e
		case "appeal":
			return readAppeal(ctx, tx, id, uuid.Nil, true)
		case "appeals":
			var cutoff, cutoffID any
			if before != "" {
				parts := strings.Split(before, "|")
				if len(parts) != 2 || !moderation.ValidID(parts[1]) {
					return nil, moderation.ErrInvalid
				}
				at, e := time.Parse(time.RFC3339Nano, parts[0])
				if e != nil {
					return nil, moderation.ErrInvalid
				}
				cutoff = at
				cutoffID = parts[1]
			}
			rows, e := tx.Query(ctx, `SELECT appeal_id,created_at FROM c_moderation.appeals WHERE state='PENDING' AND ($1::timestamptz IS NULL OR (created_at,appeal_id)<($1,$2::uuid)) ORDER BY created_at DESC,appeal_id DESC LIMIT $3`, cutoff, cutoffID, limit+1)
			if e != nil {
				return nil, e
			}
			type ref struct {
				id string
				at time.Time
			}
			refs := []ref{}
			for rows.Next() {
				var r ref
				if e = rows.Scan(&r.id, &r.at); e != nil {
					break
				}
				refs = append(refs, r)
			}
			if e == nil {
				e = rows.Err()
			}
			rows.Close()
			if e != nil {
				return nil, e
			}
			var next *string
			if len(refs) > limit {
				refs = refs[:limit]
				cursor := refs[limit-1].at.Format(time.RFC3339Nano) + "|" + refs[limit-1].id
				next = &cursor
			}
			items := []moderation.Appeal{}
			for _, r := range refs {
				v, e := readAppealInfo(ctx, tx, r.id, uuid.Nil, true)
				if e != nil {
					return nil, e
				}
				v.Materials = []moderation.Material{}
				items = append(items, v)
			}
			return map[string]any{"items": items, "nextBefore": next}, nil
		case "accounts":
			return readModerationAccounts(ctx, tx, number, before, limit)
		case "audit":
			if id == "" {
				return nil, moderation.ErrInvalid
			}
			rows, e := tx.Query(ctx, `SELECT actor_number,target_number,action,reason,created_at,case_id FROM c_moderation.audit WHERE case_id=$1 ORDER BY audit_id`, id)
			if e != nil {
				return nil, e
			}
			defer rows.Close()
			items := []any{}
			for rows.Next() {
				var a, t, action, reason, caseID string
				var at time.Time
				if e = rows.Scan(&a, &t, &action, &reason, &at, &caseID); e != nil {
					return nil, e
				}
				items = append(items, map[string]any{"actorNumber": a, "targetNumber": t, "action": action, "reason": reason, "createdAt": at.UTC(), "caseId": caseID})
			}
			return map[string]any{"items": items}, rows.Err()
		}
		return nil, moderation.ErrInvalid
	})
}
func (c *Community) ExecuteModeration(ctx context.Context, bearer [32]byte, operation, id string, d moderation.Decision) (PostResponse, error) {
	if !c.ModerationEnabled() || !moderation.ValidID(d.CommandID) {
		return PostResponse{}, moderation.ErrInvalid
	}
	if operation == "decision" && d.Validate() != nil {
		return PostResponse{}, moderation.ErrInvalid
	}
	if operation != "claim" && (!moderation.Text(d.Reason, 500) || strings.TrimSpace(d.Reason) == "") {
		return PostResponse{}, moderation.ErrInvalid
	}
	var target uuid.UUID
	var caseID string
	var e error
	switch operation {
	case "decision", "claim":
		e = c.pool.QueryRow(ctx, `SELECT target_account_id,case_id FROM c_moderation.cases WHERE case_id=$1`, id).Scan(&target, &caseID)
	case "appeal-decision":
		e = c.pool.QueryRow(ctx, `SELECT s.account_id,s.case_id FROM c_moderation.appeals a JOIN c_moderation.sanctions s USING(sanction_id) WHERE a.appeal_id=$1`, id).Scan(&target, &caseID)
	case "revoke":
		e = c.pool.QueryRow(ctx, `SELECT account_id,case_id FROM c_moderation.sanctions WHERE sanction_id=$1`, id).Scan(&target, &caseID)
	case "role":
		e = c.pool.QueryRow(ctx, `SELECT account_id FROM c_moderation.platform_numbers WHERE number=$1`, id).Scan(&target)
	default:
		return PostResponse{}, moderation.ErrInvalid
	}
	missing := errors.Is(e, pgx.ErrNoRows)
	if missing {
		target = uuid.Nil
		e = nil
	}
	if e != nil {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	var role string
	var locked moderationRestrictionState
	return c.withModerationAccountsSession(ctx, bearer, target, func(tx pgx.Tx, actor uuid.UUID) error {
		// One short advisory serialization domain covers permission changes and cases.
		if _, e := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(850018)`); e != nil {
			return e
		}
		var e error
		role, e = moderationRole(ctx, tx, actor)
		if e != nil {
			return e
		}
		if (operation == "role" || d.Action == "BAN") && role != "ADMIN" {
			return postError("MODERATION_FORBIDDEN", 403)
		}
		if target == uuid.Nil {
			return nil
		}
		locked, e = c.lockModerationRestrictionTx(ctx, tx, target, "BAN")
		return e
	}, func(tx pgx.Tx, actor uuid.UUID, final AuthorizationDecision) (any, error) {
		if missing {
			return nil, postError("CASE_NOT_FOUND", 404)
		}
		if operation == "claim" {
			d.Reason = "开始审核"
		}
		fp := moderation.Fingerprint([]any{operation, id, d})
		if v, found, e := commandResult(ctx, tx, actor, d.CommandID, fp); found || e != nil {
			return v, e
		}
		var result any
		var e error
		switch operation {
		case "role":
			if d.Role != "NONE" && d.Role != "REVIEWER" && d.Role != "ADMIN" {
				return nil, moderation.ErrInvalid
			}
			var admins int
			var previous string
			e = tx.QueryRow(ctx, `SELECT role FROM c_moderation.roles WHERE account_id=$1`, target).Scan(&previous)
			if e != nil && !errors.Is(e, pgx.ErrNoRows) {
				return nil, e
			}
			if previous == "ADMIN" && d.Role != "ADMIN" {
				if e = tx.QueryRow(ctx, `SELECT count(*) FROM c_moderation.roles WHERE role='ADMIN'`).Scan(&admins); e != nil {
					return nil, e
				}
				if admins <= 1 {
					return nil, postError("LAST_ADMIN", 409)
				}
			}
			if d.Role == "NONE" {
				_, e = tx.Exec(ctx, `DELETE FROM c_moderation.roles WHERE account_id=$1`, target)
			} else {
				_, e = tx.Exec(ctx, `INSERT INTO c_moderation.roles VALUES($1,$2) ON CONFLICT(account_id) DO UPDATE SET role=EXCLUDED.role`, target, d.Role)
			}
			if e != nil {
				return nil, e
			}
			n, e := moderationNumber(ctx, tx, target)
			if e != nil {
				return nil, e
			}
			result = map[string]any{"platformNumber": n, "role": d.Role}
		case "claim", "decision":
			var state, post string
			var comment, conversation *string
			var version int64
			var actual uuid.UUID
			e = tx.QueryRow(ctx, `SELECT state,version,COALESCE(post_id::text,''),target_account_id,to_jsonb(c)->>'comment_id',to_jsonb(c)->>'conversation_id' FROM c_moderation.cases c WHERE case_id=$1 FOR UPDATE`, id).Scan(&state, &version, &post, &actual, &comment, &conversation)
			if e != nil {
				return nil, e
			}
			if actual != target || state == "ENDED" || operation == "claim" && state != "PENDING" || version != d.ExpectedVersion {
				return nil, postError("CASE_ALREADY_HANDLED", 409)
			}
			if conversation != nil && operation == "decision" && d.Action != "MUTE" && d.Action != "BAN" && d.Action != "DISMISS" {
				return nil, moderation.ErrInvalid
			}
			if conversation == nil {
				var visibility string
				if e = tx.QueryRow(ctx, `SELECT visibility FROM c_posts.posts WHERE post_id=$1 FOR UPDATE`, post).Scan(&visibility); e != nil {
					return nil, e
				}
				if visibility != "PUBLISHED" {
					return nil, postError("CASE_ALREADY_HANDLED", 409)
				}
			}
			if comment != nil {
				var deleted *time.Time
				e = tx.QueryRow(ctx, `SELECT t.deleted_at FROM c_comments.tasks t JOIN c_comments.attempts a USING(task_id) WHERE t.comment_id=$1 AND t.post_id=$2 AND a.state='PUBLISHED' FOR UPDATE OF t`, *comment, post).Scan(&deleted)
				if errors.Is(e, pgx.ErrNoRows) || e == nil && deleted != nil {
					return nil, postError("CASE_ALREADY_HANDLED", 409)
				}
				if e != nil {
					return nil, e
				}
			}
			if operation == "claim" {
				_, e = tx.Exec(ctx, `UPDATE c_moderation.cases SET state='PROCESSING',version=version+1 WHERE case_id=$1`, id)
				if e != nil {
					return nil, e
				}
				e = notifyReporters(ctx, tx, id, "REPORT_PROGRESS", "PROCESSING", "举报正在处理中", "提交举报不代表认定违规。", final.TrustedAt)
			} else {
				outcome := "UPHELD"
				if d.Action == "DISMISS" {
					outcome = "DISMISSED"
				}
				_, e = tx.Exec(ctx, `UPDATE c_moderation.cases SET state='ENDED',version=version+1,outcome=$2,explanation=$3,decided_by=$4 WHERE case_id=$1`, id, outcome, d.Reason, actor)
				if e != nil {
					return nil, e
				}
				if d.Action != "DISMISS" {
					sanctionID := uuid.New()
					var ends *time.Time
					if d.Days > 0 {
						at := final.TrustedAt.Add(time.Duration(d.Days) * 24 * time.Hour)
						ends = &at
					}
					_, e = tx.Exec(ctx, `INSERT INTO c_moderation.sanctions(sanction_id,case_id,account_id,action,reason,starts_at,ends_at,actor_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, sanctionID, id, target, d.Action, d.Reason, final.TrustedAt, ends, actor)
					if e != nil {
						return nil, e
					}
					switch d.Action {
					case "TAKEDOWN", "MUTE", "BAN":
						if conversation == nil {
							if e = hideModerationTarget(ctx, tx, post, comment); e != nil {
								return nil, e
							}
						}
						if d.Action != "TAKEDOWN" {
							effective, e := effectiveModerationEnd(ctx, tx, target, d.Action, final.TrustedAt)
							if e != nil {
								return nil, e
							}
							if e = c.applyModerationRestrictionTx(ctx, tx, locked, d.Action, effective, final.TrustedAt); e != nil {
								return nil, e
							}
						}
					case "RESET_NICKNAME":
						nickname := ""
						for attempt := 0; attempt < 32; attempt++ {
							candidate := "待整改" + strings.ReplaceAll(uuid.NewString(), "-", "")[:6]
							var exists bool
							if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE account_id=$1 AND nickname=$2 AND deleted_at IS NULL)`, target, candidate).Scan(&exists); e != nil {
								return nil, e
							}
							if !exists {
								nickname = candidate
								break
							}
						}
						if nickname == "" {
							return nil, ErrAuthorizationUnavailable
						}
						_, e = tx.Exec(ctx, `UPDATE public.community_identities SET nickname=$2,moderation_rename_required=true WHERE identity_id=(SELECT target_identity_id FROM c_moderation.cases WHERE case_id=$1) AND deleted_at IS NULL`, id, nickname)
					case "RESET_AVATAR":
						_, e = tx.Exec(ctx, `UPDATE public.community_identities SET avatar='default-v1' WHERE identity_id=(SELECT target_identity_id FROM c_moderation.cases WHERE case_id=$1) AND deleted_at IS NULL`, id)
					}
					if e != nil {
						return nil, e
					}
					if e = notification(ctx, tx, target, nil, "sanction:"+sanctionID.String(), "SANCTION", "ACTIVE", "违规处理通知", d.Reason, "SANCTION", sanctionID.String(), final.TrustedAt); e != nil {
						return nil, e
					}
				}
				e = notifyReporters(ctx, tx, id, "REPORT_RESULT", "ENDED", "举报处理已结束", d.Reason, final.TrustedAt)
			}
			if e != nil {
				return nil, e
			}
			result, e = readCase(ctx, tx, id, true)
		case "appeal-decision":
			result, e = c.decideAppeal(ctx, tx, actor, target, role, id, d, locked, final.TrustedAt)
		case "revoke":
			e = c.revokeModerationSanction(ctx, tx, actor, target, role, id, d.Reason, locked, final.TrustedAt)
			if e == nil {
				result, e = readSanction(ctx, tx, id, uuid.Nil)
			}
		}
		if e != nil {
			return nil, e
		}
		action := d.Action
		if operation != "decision" {
			action = strings.ToUpper(operation)
		}
		if e = auditModeration(ctx, tx, actor, target, caseID, action, d.Reason, final.TrustedAt); e != nil {
			return nil, e
		}
		if e = storeModerationCommand(ctx, tx, actor, d.CommandID, fp, result); e != nil {
			return nil, e
		}
		return result, nil
	})
}
func effectiveModerationEnd(ctx context.Context, tx pgx.Tx, account uuid.UUID, action string, at time.Time) (*time.Time, error) {
	var permanent bool
	var ends *time.Time
	e := tx.QueryRow(ctx, `SELECT COALESCE(bool_or(ends_at IS NULL),false),max(ends_at) FROM (SELECT ends_at FROM c_moderation.sanctions WHERE account_id=$1 AND action=$2 AND revoked_at IS NULL AND (ends_at IS NULL OR ends_at>$3) UNION ALL SELECT CASE WHEN $2='BAN' THEN ban_ends_at ELSE mute_ends_at END FROM c_moderation.legacy_restrictions WHERE account_id=$1 AND CASE WHEN $2='BAN' THEN ban_state='BANNED' AND (ban_ends_at IS NULL OR ban_ends_at>$3) ELSE mute_state='MUTED' AND (mute_ends_at IS NULL OR mute_ends_at>$3) END) s`, account, action, at).Scan(&permanent, &ends)
	if permanent {
		return nil, e
	}
	return ends, e
}
func (c *Community) revokeModerationSanction(ctx context.Context, tx pgx.Tx, actor, target uuid.UUID, role, id, reason string, locked moderationRestrictionState, at time.Time) error {
	var action, caseID string
	var original uuid.UUID
	var revoked *time.Time
	e := tx.QueryRow(ctx, `SELECT action,case_id,actor_id,revoked_at FROM c_moderation.sanctions WHERE sanction_id=$1 AND account_id=$2 FOR UPDATE`, id, target).Scan(&action, &caseID, &original, &revoked)
	if e != nil {
		return e
	}
	if original == actor {
		return postError("REVIEWER_RECUSED", 403)
	}
	if action == "BAN" && role != "ADMIN" {
		return postError("MODERATION_FORBIDDEN", 403)
	}
	if revoked != nil {
		return postError("SANCTION_ALREADY_REVOKED", 409)
	}
	if _, e = tx.Exec(ctx, `UPDATE c_moderation.sanctions SET revoked_at=$2 WHERE sanction_id=$1`, id, at); e != nil {
		return e
	}
	if action == "BAN" || action == "MUTE" {
		ends, e := effectiveModerationEnd(ctx, tx, target, action, at)
		if e != nil {
			return e
		}
		var active bool
		if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_moderation.sanctions WHERE account_id=$1 AND action=$2 AND revoked_at IS NULL AND (ends_at IS NULL OR ends_at>$3)) OR EXISTS(SELECT 1 FROM c_moderation.legacy_restrictions WHERE account_id=$1 AND CASE WHEN $2='BAN' THEN ban_state='BANNED' AND (ban_ends_at IS NULL OR ban_ends_at>$3) ELSE mute_state='MUTED' AND (mute_ends_at IS NULL OR mute_ends_at>$3) END)`, target, action, at).Scan(&active); e != nil {
			return e
		}
		if !active {
			action = "UN" + action
		}
		if e = c.applyModerationRestrictionTx(ctx, tx, locked, action, ends, at); e != nil {
			return e
		}
	}
	// A deleted post remains terminal. Every other active takedown reason is checked.
	e = restoreModerationTarget(ctx, tx, caseID)
	if e != nil {
		return e
	}
	if _, e = tx.Exec(ctx, `UPDATE c_moderation.cases SET outcome='REVERSED',explanation=$2,version=version+1 WHERE case_id=$1`, caseID, reason); e != nil {
		return e
	}
	if e = notifyReporters(ctx, tx, caseID, "REPORT_RESULT", "REVERSED", "举报处理结果已更正", "原处理经复核撤销。", at); e != nil {
		return e
	}
	return notification(ctx, tx, target, nil, "sanction:"+id+":revoked", "SANCTION", "REVOKED", "处罚已撤销", reason, "SANCTION", id, at)
}
