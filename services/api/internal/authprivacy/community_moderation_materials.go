package authprivacy

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"strings"
	"time"
)

// One authorized batch per response. Appends remain independent facts, with no
// aggregate image cap and no unbounded image scan in queues or detail reads.
func readModerationMaterialPage(ctx context.Context, tx pgx.Tx, kind, id, cursor string) (moderation.MaterialPage, error) {
	page := moderation.MaterialPage{Items: []moderation.Material{}}
	var at, after any
	if cursor != "" {
		p := strings.Split(cursor, "|")
		if len(p) != 2 || !moderation.ValidID(p[1]) {
			return page, moderation.ErrInvalid
		}
		v, e := time.Parse(time.RFC3339Nano, p[0])
		if e != nil {
			return page, moderation.ErrInvalid
		}
		at = v
		after = p[1]
	}
	query := `SELECT request_id,description,images,created_at,'' FROM c_moderation.appeal_materials WHERE appeal_id=$1 AND ($2::timestamptz IS NULL OR (created_at,request_id)>($2,$3::uuid)) ORDER BY created_at,request_id LIMIT 2`
	if kind == "REPORT" {
		query = `SELECT report_id,description,images,created_at,reason FROM c_moderation.reports WHERE case_id=$1 AND ($2::timestamptz IS NULL OR (created_at,report_id)>($2,$3::uuid)) ORDER BY created_at,report_id LIMIT 2`
	}
	rows, e := tx.Query(ctx, query, id, at, after)
	if e != nil {
		return page, e
	}
	defer rows.Close()
	var firstID string
	for rows.Next() {
		var m moderation.Material
		var ref string
		var b []byte
		if e = rows.Scan(&ref, &m.Description, &b, &m.CreatedAt, &m.Reason); e != nil {
			return page, e
		}
		m.CreatedAt = m.CreatedAt.UTC()
		if len(page.Items) == 1 {
			last := page.Items[0]
			next := last.CreatedAt.Format(time.RFC3339Nano) + "|" + firstID
			page.NextCursor = &next
			break
		}
		if e = json.Unmarshal(b, &m.Images); e != nil {
			return page, e
		}
		firstID = ref
		page.Items = append(page.Items, m)
	}
	return page, rows.Err()
}
func (c *Community) ReadModerationMaterials(ctx context.Context, bearer [32]byte, kind, id, cursor string, admin bool) (PostResponse, error) {
	if !c.ModerationEnabled() || !moderation.ValidID(id) || kind != "REPORT" && kind != "APPEAL" || kind == "REPORT" && !admin {
		return PostResponse{}, moderation.ErrInvalid
	}
	action := func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision) (any, error) {
		if kind == "REPORT" {
			if _, e := readCase(ctx, tx, id, false); e != nil {
				if errors.Is(e, pgx.ErrNoRows) {
					return nil, postError("CASE_NOT_FOUND", 404)
				}
				return nil, e
			}
		} else {
			owner := account
			if admin {
				owner = uuid.Nil
			}
			if _, e := readAppealInfo(ctx, tx, id, owner, admin); e != nil {
				return nil, e
			}
		}
		return readModerationMaterialPage(ctx, tx, kind, id, cursor)
	}
	if admin {
		return c.withModerationAccountsSession(ctx, bearer, uuid.Nil, func(tx pgx.Tx, account uuid.UUID) error { _, e := moderationRole(ctx, tx, account); return e }, action)
	}
	return c.withModerationSession(ctx, bearer, true, action)
}
