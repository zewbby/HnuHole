package authprivacy

import (
	"context"
	"crypto/ed25519"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func TestRetirementTerminalWriteAndReplayRequireFinalGatePostgres(t *testing.T) {
	for _, scenario := range []string{"frozen-start", "freeze-during-lock", "recover-during-lock"} {
		t.Run(scenario, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			ticket, _ := l.ticket(t)
			authorization := l.authorization(ticket.Slot)
			var result error
			if scenario == "frozen-start" {
				if err := control.gate.Freeze(ctx, "retirement before snapshot"); err != nil { t.Fatal(err) }
				result = l.c.RetireSlot(ctx, authorization)
			} else {
				hold, err := l.cp.Begin(ctx)
				if err != nil { t.Fatal(err) }
				defer hold.Rollback(context.Background())
				if err = lockSlot(ctx, hold, ticket.Slot[:]); err != nil { t.Fatal(err) }
				done := make(chan error, 1)
				go func() { done <- l.c.RetireSlot(ctx, authorization) }()
				waitLock(t, l.cp, "advisory", 1)
				if err = control.gate.Freeze(ctx, "retirement waiting for slot"); err != nil { t.Fatal(err) }
				if scenario == "recover-during-lock" {
					control.clock.set(control.clock.now().Add(time.Second))
					control.recover(t, AuthorizationRecoveryNormal, 3, 4)
				}
				if err = hold.Rollback(ctx); err != nil { t.Fatal(err) }
				select { case result = <-done: case <-ctx.Done(): t.Fatal("retirement did not stop at the final Gate") }
			}
			if !errors.Is(result, ErrAuthorizationUnavailable) { t.Fatalf("unauthorized retirement committed: %v", result) }
			if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1`, ticket.Slot[:]) != 0 ||
				count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1`, ticket.Slot[:]) != 0 {
				t.Fatal("frozen or old-generation retirement left permanent facts")
			}
			if scenario != "recover-during-lock" {
				control.clock.set(control.clock.now().Add(time.Second))
				control.recover(t, AuthorizationRecoveryNormal, 3, 4)
			}
			if err := l.c.RetireSlot(ctx, authorization); err != nil { t.Fatal(err) }
			if err := control.gate.Freeze(ctx, "retirement replay frozen"); err != nil { t.Fatal(err) }
			if err := l.c.RetireSlot(ctx, authorization); !errors.Is(err, ErrAuthorizationUnavailable) { t.Fatalf("terminal replay bypassed Gate: %v", err) }
			if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1 AND state='RETIRED'`, ticket.Slot[:]) != 1 ||
				count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1 AND state='PENDING_SIGN'`, ticket.Slot[:]) != 1 {
				t.Fatal("replay changed the original terminal event")
			}
		})
	}
}

func TestAcknowledgedRetirementResignRejectsFreezeAndRecoveryPostgres(t *testing.T) {
	for _, recoverWhileSigning := range []bool{false, true} {
		name := "freeze"
		if recoverWhileSigning { name = "recover" }
		t.Run(name, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			slot := retiredWorkerSlot(t, l)
			sign := func(_ context.Context, _ uint32, message []byte) ([]byte, error) { return ed25519.Sign(l.cPrivate, message), nil }
			if stored, err := l.c.SignReceipt(ctx, slot, sign); err != nil || !stored { t.Fatalf("prepare signature: %v", err) }
			// This regression probes C's durable ACK and Gate boundary. The remote
			// receiver is a successful transport stub; V release is covered elsewhere.
			if err := l.c.DeliverReceipt(ctx, slot, func(context.Context, string, protocol.Purpose) error { return nil }); err != nil { t.Fatal(err) }
			advanceClosureClock(t, control, control.clock.now().Add(time.Second))
			if removed, err := l.c.CleanupAcknowledgedBatch(ctx, 0, 1); err != nil || removed != 1 { t.Fatalf("prepare cleaned ACK: %v", err) }
			signing, release := make(chan struct{}), make(chan struct{})
			var releaseOnce sync.Once
			unblock := func() { releaseOnce.Do(func() { close(release) }) }
			defer unblock()
			l.c.receiptSigner = func(signCtx context.Context, epoch uint32, message []byte) ([]byte, error) {
				close(signing)
				select { case <-release: return sign(signCtx, epoch, message); case <-signCtx.Done(): return nil, signCtx.Err() }
			}
			type answer struct { reply RetirementReply; err error }
			done := make(chan answer, 1)
			go func() { reply, err := l.c.RetireUnusedSlot(ctx, l.authorization(slot)); done <- answer{reply, err} }()
			select { case <-signing: case <-ctx.Done(): t.Fatal("read-only re-signing did not start") }
			if err := control.gate.Freeze(ctx, "acknowledged retirement signer in flight"); err != nil { t.Fatal(err) }
			if recoverWhileSigning {
				control.clock.set(control.clock.now().Add(time.Second))
				control.recover(t, AuthorizationRecoveryNormal, 3, 4)
			}
			unblock()
			var result answer
			select { case result = <-done: case <-ctx.Done(): t.Fatal("late signer did not finish") }
			if !errors.Is(result.err, ErrAuthorizationUnavailable) || result.reply.Receipt != "" || result.reply.Pending {
				t.Fatalf("late receipt used frozen or recovered authority: %v", result.err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1`, slot[:]) != 0 ||
				count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1 AND state='RETIRED' AND receipt_acknowledged`, slot[:]) != 1 {
				t.Fatal("late re-signing recreated delivery material or changed durable ACK")
			}
			if !recoverWhileSigning {
				control.clock.set(control.clock.now().Add(time.Second))
				control.recover(t, AuthorizationRecoveryNormal, 3, 4)
			}
			l.c.receiptSigner = sign
			fresh, err := l.c.RetireUnusedSlot(ctx, l.authorization(slot))
			if err != nil || fresh.Pending || fresh.Receipt == "" { t.Fatalf("fresh generation could not re-sign permanent terminal fact: %v", err) }
			if _, err = l.c.verifier.VerifyReceipt(fresh.Receipt, protocol.PurposeRetired); err != nil { t.Fatal(err) }
			if count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE slot_id=$1`, slot[:]) != 0 { t.Fatal("read-only re-signing resurrected the outbox") }
		})
	}
}
