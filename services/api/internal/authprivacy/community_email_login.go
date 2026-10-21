package authprivacy

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

var ErrEmailUnregistered = errors.New("verified email has no active account")
var ErrEmailProofInvalid = errors.New("email login proof invalid")

type EmailSessionRequest struct {
	Proof          string
	InstallationID [16]byte
	IdempotencyKey [32]byte
}

func (c *Community) CreateEmailSession(ctx context.Context, req EmailSessionRequest) (SessionCreateResult, error) {
	var zero SessionCreateResult
	d, err := c.gate.Snapshot(ctx)
	if err != nil {
		return zero, err
	}
	if req.InstallationID == ([16]byte{}) || req.IdempotencyKey == ([32]byte{}) {
		return zero, ErrEmailProofInvalid
	}
	proof, err := c.verifier.VerifyEmailLogin(req.Proof, d.TrustedAt)
	if err != nil || proof.Binding != protocol.EmailLoginBinding(req.InstallationID, req.IdempotencyKey) {
		return zero, ErrEmailProofInvalid
	}
	var username string
	err = c.pool.QueryRow(ctx, `SELECT a.username FROM c_auth.accounts a JOIN c_auth.slot_ledger l ON l.account_id=a.account_id WHERE l.slot_id=$1 AND l.state='ACTIVE' AND a.state IN ('ACTIVE','PENDING_CLOSE')`, proof.Slot[:]).Scan(&username)
	if errors.Is(err, pgx.ErrNoRows) {
		return zero, ErrEmailUnregistered
	}
	if err != nil {
		return zero, ErrAuthorizationUnavailable
	}
	// Opaque signed authorization is included in the existing purpose-specific
	// request MAC. The shared transaction enforces credential, closure, restriction,
	// one-mobile-session and final Gate fences exactly as password login does.
	return c.createSession(ctx, SessionCreateRequest{Username: username, Password: req.Proof, InstallationID: req.InstallationID, IdempotencyKey: req.IdempotencyKey}, nil, &proof)
}
