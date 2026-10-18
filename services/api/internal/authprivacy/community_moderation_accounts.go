package authprivacy

import (
	"context"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"strings"
	"time"
)

func readModerationAccounts(ctx context.Context, tx pgx.Tx, number, before string, limit int) (any, error) {
	valid := func(s string) bool { return len(s) == 6 && strings.Trim(s, "0123456789") == "" }
	if number != "" && !valid(number) || before != "" && !valid(before) {
		return nil, moderation.ErrInvalid
	}
	var queryNumber, after any
	if number != "" {
		queryNumber = number
	}
	if before != "" {
		after = before
	}
	rows, e := tx.Query(ctx, `SELECT n.account_id,n.number,a.registered_at,a.state,(SELECT count(*) FROM c_moderation.sanctions s WHERE s.account_id=n.account_id AND s.revoked_at IS NULL) FROM c_moderation.platform_numbers n JOIN c_auth.accounts a USING(account_id) WHERE ($1::text IS NULL OR n.number=$1) AND ($2::text IS NULL OR n.number>$2) ORDER BY n.number LIMIT $3`, queryNumber, after, limit+1)
	if e != nil {
		return nil, e
	}
	type account struct {
		id            uuid.UUID
		number, state string
		created       *time.Time
		violations    int
	}
	all := []account{}
	for rows.Next() {
		var a account
		if e = rows.Scan(&a.id, &a.number, &a.created, &a.state, &a.violations); e != nil {
			break
		}
		all = append(all, a)
	}
	if e == nil {
		e = rows.Err()
	}
	rows.Close()
	if e != nil {
		return nil, e
	}
	var next *string
	if len(all) > limit {
		all = all[:limit]
		s := all[limit-1].number
		next = &s
	}
	items := []any{}
	for _, a := range all {
		sanctions := []moderation.Sanction{}
		if number != "" {
			rows, e := tx.Query(ctx, `SELECT sanction_id FROM c_moderation.sanctions WHERE account_id=$1 ORDER BY starts_at DESC,sanction_id`, a.id)
			if e != nil {
				return nil, e
			}
			ids := []string{}
			for rows.Next() {
				var id string
				if e = rows.Scan(&id); e != nil {
					break
				}
				ids = append(ids, id)
			}
			if e == nil {
				e = rows.Err()
			}
			rows.Close()
			if e != nil {
				return nil, e
			}
			for _, id := range ids {
				s, e := readSanction(ctx, tx, id, uuid.Nil)
				if e != nil {
					return nil, e
				}
				sanctions = append(sanctions, s)
			}
		}
		items = append(items, map[string]any{"platformNumber": a.number, "createdAt": moderationTimeUTC(a.created), "state": a.state, "violationCount": a.violations, "sanctions": sanctions})
	}
	return map[string]any{"items": items, "nextBefore": next}, nil
}
