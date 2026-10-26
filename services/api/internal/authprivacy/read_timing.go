package authprivacy

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/readtiming"
)

func (g *PostgresAuthorizationGate) observedAnchorWrite(ctx context.Context, a authorizationAnchor) error {
	defer readtiming.Span(ctx, "anchor_write")()
	return g.anchor.writeLocked(a)
}

func (g *PostgresAuthorizationGate) observedAnchorLock(ctx context.Context, fn func(*authorizationAnchor, bool) error) error {
	finish := readtiming.Span(ctx, "anchor_lock_read_verify")
	entered := false
	defer func() {
		if !entered {
			finish()
		}
	}()
	return g.anchor.withLocked(func(a *authorizationAnchor, exists bool) error {
		entered = true
		finish()
		return fn(a, exists)
	})
}

func observedAuthorizationCommit(ctx context.Context, tx pgx.Tx) error {
	defer readtiming.Span(ctx, "sql_commit")()
	return tx.Commit(ctx)
}

func observedAuthorizationAbort(ctx context.Context, gate AuthorizationGate, tx pgx.Tx) {
	defer readtiming.Span(ctx, "gate_abort")()
	_ = gate.Abort(ctx, tx)
}
