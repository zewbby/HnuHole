package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"time"
)

// CloseDMCommand orders with every send under the original account lock. SENT
// is returned unchanged; an absent/failed command receives a permanent terminal
// anchor, so a delayed old PUT can never recreate hidden content.
func (c *Community) CloseDMCommand(ctx context.Context, b [32]byte, id string, attempt int) (PostResponse, error) {
	if !dmUUID(id) || attempt < 1 || attempt > 1000 {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	if c.sharedRate != nil {
		ctx = c.sharedRate.engine.WithPolicyFence(ctx)
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		if err := requireSharedPolicyFence(ctx, tx); err != nil {
			return nil, err
		}
		old, fp, err := dmReceipt(ctx, tx, a, id)
		if err == nil && (old.State == "SENT" || old.ErrorCode == "COMMAND_CLOSED") {
			return old, nil
		}
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
		var used int
		var first *time.Time
		if err = tx.QueryRow(ctx, `SELECT count(*),min(closed_at) FROM c_dm.commands WHERE owner_account=$1 AND closed_at>$2`, a, d.TrustedAt.Add(-time.Minute)).Scan(&used, &first); err != nil {
			return nil, err
		}
		if used >= 120 {
			wait := 1
			if first != nil {
				wait = max(1, remainingSeconds(first.Add(time.Minute), d.TrustedAt))
			}
			return nil, &PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: wait}
		}
		if old.Attempt > attempt {
			attempt = old.Attempt
		}
		if len(fp) == 0 {
			digest := requestMAC(c.requestKey, []byte("HNUHOLE/DM-CLOSED/V1"), []byte(a.String()), []byte(id))
			fp = digest[:]
		}
		_, err = tx.Exec(ctx, `INSERT INTO c_dm.commands(owner_account,command_id,fingerprint,attempt,state,error_code,closed_at) VALUES($1,$2,$3,$4,'FAILED','COMMAND_CLOSED',$5) ON CONFLICT(owner_account,command_id) DO UPDATE SET attempt=GREATEST(c_dm.commands.attempt,EXCLUDED.attempt),state='FAILED',error_code='COMMAND_CLOSED',closed_at=EXCLUDED.closed_at`, a, id, fp, attempt, d.TrustedAt)
		if err != nil {
			return nil, err
		}
		key := sha256.Sum256([]byte("HNUHOLE/DM-ADMISSION/V1\x00" + a.String() + "\x00" + id))
		if _, err = tx.Exec(ctx, `DELETE FROM c_rate_limit.admissions WHERE account_id=$1 AND business_kind IN ('dm-text','dm-image') AND key_digest=$2`, a, key[:]); err != nil {
			return nil, err
		}
		return DMReceipt{State: "FAILED", Attempt: attempt, ErrorCode: "COMMAND_CLOSED"}, nil
	})
}
