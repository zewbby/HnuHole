package authprivacy

import (
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func fenceParent(s string) string {
	if s == "" {
		return uuid.Nil.String()
	}
	return s
}
func sealModerationAttempt(ctx context.Context, tx pgx.Tx, account uuid.UUID, kind, parent, request string) (string, error) {
	token := uuid.NewString()
	_, e := tx.Exec(ctx, `INSERT INTO c_moderation.request_fences(account_id,kind,parent_id,request_id,retry_token) VALUES($1,$2,$3,$4,$5) ON CONFLICT(account_id,kind,parent_id,request_id) DO UPDATE SET retry_token=EXCLUDED.retry_token`, account, kind, fenceParent(parent), request, token)
	return token, e
}
func checkModerationAttempt(ctx context.Context, tx pgx.Tx, account uuid.UUID, kind, parent, request, token string) error {
	var stored string
	e := tx.QueryRow(ctx, `SELECT retry_token FROM c_moderation.request_fences WHERE account_id=$1 AND kind=$2 AND parent_id=$3 AND request_id=$4`, account, kind, fenceParent(parent), request).Scan(&stored)
	if errors.Is(e, pgx.ErrNoRows) {
		if token != "" {
			return postError("REPORT_ATTEMPT_SEALED", 409)
		}
		return nil
	}
	if e != nil {
		return e
	}
	if token != stored {
		return postError("REPORT_ATTEMPT_SEALED", 409)
	}
	return nil
}
