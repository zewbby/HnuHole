package authprivacy

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
)

func readAppealInfo(ctx context.Context, tx pgx.Tx, id string, account uuid.UUID, admin bool) (moderation.Appeal, error) {
	var a moderation.Appeal
	var target, original uuid.UUID
	e := tx.QueryRow(ctx, `SELECT a.appeal_id,a.sanction_id,s.case_id,a.state,a.ordinal,a.version,a.reason,s.account_id,s.actor_id,s.action FROM c_moderation.appeals a JOIN c_moderation.sanctions s USING(sanction_id) WHERE a.appeal_id=$1 AND ($2::uuid IS NULL OR s.account_id=$2)`, id, nullableUUID(account)).Scan(&a.ID, &a.SanctionID, &a.CaseID, &a.State, &a.Ordinal, &a.Version, &a.Reason, &target, &original, &a.Action)
	if errors.Is(e, pgx.ErrNoRows) {
		return a, postError("APPEAL_NOT_FOUND", 404)
	}
	if e != nil {
		return a, e
	}
	if admin {
		a.PlatformNumber, e = moderationNumber(ctx, tx, target)
		if e != nil {
			return a, e
		}
		a.OriginalActorNumber, e = moderationNumber(ctx, tx, original)
		if e != nil {
			return a, e
		}
	}
	a.Materials = []moderation.Material{}
	return a, nil
}
func readAppeal(ctx context.Context, tx pgx.Tx, id string, account uuid.UUID, admin bool) (moderation.Appeal, error) {
	a, e := readAppealInfo(ctx, tx, id, account, admin)
	if e != nil {
		return a, e
	}
	page, e := readModerationMaterialPage(ctx, tx, "APPEAL", id, "")
	a.Materials = page.Items
	a.NextMaterialsCursor = page.NextCursor
	return a, e
}
func (c *Community) ReadAppeal(ctx context.Context, bearer [32]byte, id string) (PostResponse, error) {
	if !moderation.ValidID(id) {
		return PostResponse{}, moderation.ErrInvalid
	}
	return c.withModerationSession(ctx, bearer, true, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision) (any, error) {
		return readAppeal(ctx, tx, id, account, false)
	})
}
func (c *Community) GetAppealRequest(ctx context.Context, bearer [32]byte, parent, request string, appendMaterial bool) (PostResponse, error) {
	if !moderation.ValidID(parent) || !moderation.ValidID(request) {
		return PostResponse{}, moderation.ErrInvalid
	}
	return c.withModerationSession(ctx, bearer, true, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision) (any, error) {
		var id string
		var e error
		if appendMaterial {
			e = tx.QueryRow(ctx, `SELECT a.appeal_id FROM c_moderation.appeals a JOIN c_moderation.sanctions s USING(sanction_id) JOIN c_moderation.appeal_materials m USING(appeal_id) WHERE s.account_id=$1 AND a.appeal_id=$2 AND m.request_id=$3`, account, parent, request).Scan(&id)
		} else {
			e = tx.QueryRow(ctx, `SELECT a.appeal_id FROM c_moderation.appeals a JOIN c_moderation.sanctions s USING(sanction_id) WHERE s.account_id=$1 AND s.sanction_id=$2 AND a.request_id=$3`, account, parent, request).Scan(&id)
		}
		if errors.Is(e, pgx.ErrNoRows) {
			kind := "APPEAL"
			if appendMaterial {
				kind = "MATERIAL"
				if _, e = readAppeal(ctx, tx, parent, account, false); e != nil {
					return nil, e
				}
			} else {
				if _, e = readSanction(ctx, tx, parent, account); errors.Is(e, pgx.ErrNoRows) {
					return nil, postError("SANCTION_NOT_FOUND", 404)
				} else if e != nil {
					return nil, e
				}
			}
			token, e := sealModerationAttempt(ctx, tx, account, kind, parent, request)
			return moderation.AppealResult{State: "NOT_SUBMITTED", RetryToken: token}, e
		}
		if e != nil {
			return nil, e
		}
		a, e := readAppeal(ctx, tx, id, account, false)
		return moderation.AppealResult{State: "SUBMITTED", Appeal: &a}, e
	})
}
func (c *Community) SubmitAppeal(ctx context.Context, bearer [32]byte, parent, request string, m moderation.Material, appendMaterial bool) (PostResponse, error) {
	max := 6
	if appendMaterial {
		max = 3
	}
	if !moderation.ValidID(parent) || !moderation.ValidID(request) || m.Validate(max) != nil || !m.CreatedAt.IsZero() || m.Reason != "" {
		return PostResponse{}, moderation.ErrInvalid
	}
	if e := c.inspectModerationImages(ctx, m.Images, max); e != nil {
		return PostResponse{}, e
	}
	return c.withModerationSession(ctx, bearer, true, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision) (any, error) {
		fingerprintInput := m
		fingerprintInput.RetryToken = ""
		fp := moderation.Fingerprint(fingerprintInput)
		var id, stored, state string
		var e error
		if appendMaterial {
			e = tx.QueryRow(ctx, `SELECT a.appeal_id,m.fingerprint FROM c_moderation.appeals a JOIN c_moderation.sanctions s USING(sanction_id) JOIN c_moderation.appeal_materials m USING(appeal_id) WHERE a.appeal_id=$1 AND s.account_id=$2 AND m.request_id=$3`, parent, account, request).Scan(&id, &stored)
		} else {
			e = tx.QueryRow(ctx, `SELECT a.appeal_id,a.fingerprint FROM c_moderation.appeals a JOIN c_moderation.sanctions s USING(sanction_id) WHERE s.sanction_id=$1 AND s.account_id=$2 AND a.request_id=$3`, parent, account, request).Scan(&id, &stored)
		}
		if e == nil {
			if stored != fp {
				return nil, postError("REQUEST_CONFLICT", 409)
			}
			return readAppeal(ctx, tx, id, account, false)
		}
		if !errors.Is(e, pgx.ErrNoRows) {
			return nil, e
		}
		kind := "APPEAL"
		if appendMaterial {
			kind = "MATERIAL"
		}
		if e = checkModerationAttempt(ctx, tx, account, kind, parent, request, m.RetryToken); e != nil {
			return nil, e
		}
		if appendMaterial {
			e = tx.QueryRow(ctx, `SELECT a.state FROM c_moderation.appeals a JOIN c_moderation.sanctions s USING(sanction_id) WHERE a.appeal_id=$1 AND s.account_id=$2 FOR UPDATE OF a`, parent, account).Scan(&state)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("APPEAL_NOT_FOUND", 404)
			}
			if e != nil {
				return nil, e
			}
			if state != "PENDING" {
				return nil, postError("APPEAL_CLOSED", 409)
			}
			id = parent
		} else {
			s, e := readSanction(ctx, tx, parent, account)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("SANCTION_NOT_FOUND", 404)
			}
			if e != nil {
				return nil, e
			}
			if s.RevokedAt != nil {
				return nil, postError("SANCTION_ALREADY_REVOKED", 409)
			}
			if s.ActiveAppealID != nil {
				return nil, postError("APPEAL_PENDING", 409)
			}
			if s.AppealCount >= 3 {
				return nil, postError("APPEAL_LIMIT", 409)
			}
			var duplicate bool
			if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_moderation.appeals WHERE sanction_id=$1 AND fingerprint=$2)`, parent, fp).Scan(&duplicate); e != nil {
				return nil, e
			}
			if duplicate {
				return nil, postError("NEW_MATERIAL_REQUIRED", 409)
			}
			id = uuid.NewString()
			if _, e = tx.Exec(ctx, `INSERT INTO c_moderation.appeals(appeal_id,sanction_id,request_id,fingerprint,ordinal,created_at) VALUES($1,$2,$3,$4,$5,$6)`, id, parent, request, fp, s.AppealCount+1, final.TrustedAt); e != nil {
				return nil, e
			}
		}
		images, _ := json.Marshal(m.Images)
		if _, e = tx.Exec(ctx, `INSERT INTO c_moderation.appeal_materials(appeal_id,request_id,fingerprint,description,images,created_at) VALUES($1,$2,$3,$4,$5,$6)`, id, request, fp, m.Description, images, final.TrustedAt); e != nil {
			return nil, e
		}
		return readAppeal(ctx, tx, id, account, false)
	})
}
func (c *Community) decideAppeal(ctx context.Context, tx pgx.Tx, actor, target uuid.UUID, role, id string, d moderation.Decision, locked moderationRestrictionState, at time.Time) (any, error) {
	var state, sanction, action string
	var original uuid.UUID
	var revoked *time.Time
	var version int64
	e := tx.QueryRow(ctx, `SELECT a.state,a.version,a.sanction_id,s.actor_id,s.action,s.revoked_at FROM c_moderation.appeals a JOIN c_moderation.sanctions s USING(sanction_id) WHERE a.appeal_id=$1 AND s.account_id=$2 FOR UPDATE OF a,s`, id, target).Scan(&state, &version, &sanction, &original, &action, &revoked)
	if e != nil {
		return nil, e
	}
	if original == actor {
		return nil, postError("REVIEWER_RECUSED", 403)
	}
	if action == "BAN" && role != "ADMIN" {
		return nil, postError("MODERATION_FORBIDDEN", 403)
	}
	if state != "PENDING" || version != d.ExpectedVersion {
		return nil, postError("APPEAL_ALREADY_HANDLED", 409)
	}
	state = "REJECTED"
	if d.Accept {
		state = "ACCEPTED"
		if revoked == nil {
			if e = c.revokeModerationSanction(ctx, tx, actor, target, role, sanction, d.Reason, locked, at); e != nil {
				return nil, e
			}
		}
	}
	if _, e = tx.Exec(ctx, `UPDATE c_moderation.appeals SET state=$2,reason=$3,version=version+1 WHERE appeal_id=$1`, id, state, d.Reason); e != nil {
		return nil, e
	}
	if e = notification(ctx, tx, target, nil, "appeal:"+id+":result", "APPEAL_RESULT", state, "申诉处理结果", d.Reason, "APPEAL", id, at); e != nil {
		return nil, e
	}
	return readAppeal(ctx, tx, id, uuid.Nil, true)
}
