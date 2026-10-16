// Package authprivacy is an isolated PostgreSQL validation slice. It is not
// registered on the application's HTTP router and has no production deployment.
package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/binary"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func sqlPurpose(p protocol.Purpose) string {
	switch p {
	case protocol.PurposeRetired:
		return "RETIRED"
	case protocol.PurposeReleased:
		return "RELEASED"
	default:
		return ""
	}
}

func wirePurpose(p string) protocol.Purpose {
	switch p {
	case "RETIRED":
		return protocol.PurposeRetired
	case "RELEASED":
		return protocol.PurposeReleased
	default:
		return ""
	}
}

var (
	ErrSlotUnavailable = errors.New("slot unavailable")
	ErrIntentInvalid   = errors.New("signup intent invalid")
	ErrUsernameTaken   = errors.New("username unavailable")
	ErrReconciliation  = errors.New("receipt reconciliation required")
	ErrConflict        = errors.New("idempotency conflict")
	ErrExpired         = errors.New("idempotency result expired")
	ErrReceiptPending  = errors.New("receipt pending")
)

func random32() ([32]byte, error) {
	var value [32]byte
	_, err := rand.Read(value[:])
	return value, err
}

func digest(domain string, value []byte) [32]byte {
	h := sha256.New()
	h.Write([]byte(domain))
	h.Write([]byte{0})
	h.Write(value)
	var out [32]byte
	copy(out[:], h.Sum(nil))
	return out
}

func requestMAC(key [32]byte, parts ...[]byte) [32]byte {
	h := hmac.New(sha256.New, key[:])
	for _, part := range parts {
		var length [8]byte
		binary.BigEndian.PutUint64(length[:], uint64(len(part)))
		h.Write(length[:])
		h.Write(part)
	}
	var result [32]byte
	copy(result[:], h.Sum(nil))
	return result
}

func lockSlot(ctx context.Context, tx pgx.Tx, slot []byte) error {
	key := digest("HNUHOLE/C-SLOT-LOCK/V1", slot)
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, int64(binary.BigEndian.Uint64(key[:8])))
	return err
}

func recoveryDigest(code string) ([32]byte, error) {
	normal := strings.ToUpper(strings.NewReplacer("-", "", " ", "").Replace(code))
	encoding := base32.StdEncoding.WithPadding(base32.NoPadding)
	raw, err := encoding.DecodeString(normal)
	if err != nil || len(raw) != 16 || encoding.EncodeToString(raw) != normal {
		return [32]byte{}, ErrIntentInvalid
	}
	return digest("HNUHOLE/RECOVERY/V1", raw), nil
}

func begin(ctx context.Context, pool interface {
	BeginTx(context.Context, pgx.TxOptions) (pgx.Tx, error)
}) (pgx.Tx, error) {
	tx, err := pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
	if err != nil {
		return nil, err
	}
	if _, err = tx.Exec(ctx, `SET LOCAL lock_timeout = '5s'; SET LOCAL statement_timeout = '10s'`); err != nil {
		_ = tx.Rollback(ctx)
		return nil, err
	}
	return tx, nil
}
