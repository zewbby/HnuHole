package auth

import (
	"context"
	"crypto/sha256"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrInvalidSession = errors.New("invalid session")

type SessionValidator struct {
	pool *pgxpool.Pool
}

func NewSessionValidator(pool *pgxpool.Pool) *SessionValidator {
	return &SessionValidator{pool: pool}
}

func (v *SessionValidator) Validate(ctx context.Context, token string) (string, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return "", ErrInvalidSession
	}

	digest := sha256.Sum256([]byte(token))
	var accountID string
	err := v.pool.QueryRow(ctx, `
SELECT account_id::text
FROM sessions
WHERE token_hash = $1
  AND revoked_at IS NULL
  AND expires_at > now()`, digest[:]).Scan(&accountID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrInvalidSession
	}
	if err != nil {
		return "", err
	}
	return accountID, nil
}
