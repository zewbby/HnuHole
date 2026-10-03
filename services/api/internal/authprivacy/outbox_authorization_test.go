package authprivacy

import (
	"context"
	"crypto/ed25519"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func TestReleaseACKCannotCrossFreezeAndRetriesAfterRecoveryPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	ticket, private := l.ticket(t)
	_, signup := l.intent(t, ticket, private, "release_ack_gate_user")
	account, err := l.c.CommitSignup(ctx, signup)
	if err != nil {
		t.Fatal(err)
	}
	email := []byte("release.ack-gate@hainanu.edu.cn")
	reserved, err := l.v.ReserveAfterQualification(ctx, email, ticket.BootstrapKey)
	if err != nil || reserved != ticket.Slot {
		t.Fatalf("synthetic V reservation did not match the registered slot: %v", err)
	}
	request, secret := closureTestRequest(t, account.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt.Add(time.Second))
	if closed, err := l.c.FinalizeDueClosures(ctx, 1); err != nil || closed != 1 {
		t.Fatalf("closure did not produce one committed terminal receipt job: %d %v", closed, err)
	}
	if ready, err := l.c.SignReceipt(ctx, ticket.Slot, func(_ context.Context, _ uint32, message []byte) ([]byte, error) {
		return ed25519.Sign(l.cPrivate, message), nil
	}); err != nil || !ready {
		t.Fatalf("committed release did not become ready: %v %v", ready, err)
	}
	var message, signature []byte
	if err = l.cp.QueryRow(ctx, `SELECT receipt_message,signature FROM c_auth.receipt_outbox
		WHERE slot_id=$1 AND purpose='RELEASED' AND state='READY'`, ticket.Slot[:]).Scan(&message, &signature); err != nil {
		t.Fatal(err)
	}
	originalWire := protocol.EncodeCanonicalBase64url(append(append([]byte{}, message...), signature...))
	receiver := func(ctx context.Context, wire string, purpose protocol.Purpose) error {
		if wire != originalWire || purpose != protocol.PurposeReleased {
			return fmt.Errorf("retry changed the original terminal release receipt")
		}
		return l.v.ProcessReceipt(ctx, wire, purpose)
	}
	assertUnacknowledged := func() {
		t.Helper()
		if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger l
			JOIN c_auth.receipt_outbox o USING(slot_id)
			JOIN c_auth.closure_requests r USING(slot_id)
			WHERE l.slot_id=$1 AND l.state='CLOSED' AND NOT l.receipt_acknowledged
			AND o.state='READY' AND o.ack_at IS NULL
			AND r.state='CLOSED_RELEASE_PENDING' AND r.released_at IS NULL`, ticket.Slot[:]) != 1 {
			t.Fatal("failed local ACK partially committed ledger, delivery or status authority")
		}
	}

	// V processes the real receipt before C reaches its ACK transaction. Hold
	// only the slot locks so Freeze can commit while that transaction waits.
	hold, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(context.Background())
	deliveryReached := make(chan struct{})
	pausedReceiver := func(ctx context.Context, wire string, purpose protocol.Purpose) error {
		if err := receiver(ctx, wire, purpose); err != nil { return err }
		if err := lockSlot(ctx, hold, ticket.Slot[:]); err != nil { return err }
		var heldState string
		if err := hold.QueryRow(ctx, `SELECT state FROM c_auth.slot_ledger WHERE slot_id=$1 FOR UPDATE`, ticket.Slot[:]).Scan(&heldState); err != nil { return err }
		close(deliveryReached)
		return nil
	}
	done := make(chan error, 1)
	go func() { done <- l.c.DeliverReceipt(ctx, ticket.Slot, pausedReceiver) }()
	select { case <-deliveryReached: case err := <-done: t.Fatalf("delivery did not reach the ACK barrier: %v",err); case <-ctx.Done(): t.Fatal("delivery barrier timed out") }
	waitLock(t, l.cp, "advisory", 1)
	if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE email_exact=$1`, email) != 0 ||
		count(t, l.vp, `SELECT count(*) FROM v_auth.processed_receipts WHERE slot_id=$1 AND purpose='RELEASED'`, ticket.Slot[:]) != 1 {
		t.Fatal("ACK lock barrier was reached without durable V release")
	}
	if err = control.gate.Freeze(ctx, "release ACK paused on slot lock"); err != nil {
		t.Fatal(err)
	}
	if err = hold.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	select {
	case err = <-done:
		if !errors.Is(err, ErrAuthorizationUnavailable) {
			t.Fatalf("waiting ACK crossed the gate freeze: %v", err)
		}
	case <-ctx.Done():
		t.Fatal("frozen ACK did not return after releasing its lock barrier")
	}
	assertFrozen(t, control)
	assertUnacknowledged()

	// The permanent terminal receipt can be retried after an explicit new
	// generation. Failure at the last local status write must roll back the
	// outbox and ledger updates that preceded it in the same transaction.
	control.clock.set(control.clock.now().Add(time.Second))
	control.recover(t, AuthorizationRecoveryNormal, 3, 4)
	mustExec(t, l.cp, `CREATE FUNCTION c_auth.fail_release_ack_status_fixture() RETURNS trigger LANGUAGE plpgsql AS $$
		BEGIN RAISE EXCEPTION 'isolated release ACK status write fault'; END $$;
		CREATE TRIGGER release_ack_status_fault_fixture BEFORE UPDATE ON c_auth.closure_requests
		FOR EACH ROW WHEN (OLD.released_at IS NULL AND NEW.released_at IS NOT NULL)
		EXECUTE FUNCTION c_auth.fail_release_ack_status_fixture()`)
	t.Cleanup(func() {
		_, _ = l.cp.Exec(context.Background(), `DROP TRIGGER IF EXISTS release_ack_status_fault_fixture ON c_auth.closure_requests;
			DROP FUNCTION IF EXISTS c_auth.fail_release_ack_status_fixture()`)
	})
	ackErr := l.c.DeliverReceipt(ctx, ticket.Slot, receiver)
	var databaseFailure *pgconn.PgError
	if !errors.As(ackErr, &databaseFailure) || databaseFailure.Code != "P0001" {
		t.Fatalf("last ACK write did not exercise the injected SQL rollback: %v", ackErr)
	}
	assertUnacknowledged()
	if count(t, l.vp, `SELECT count(*) FROM v_auth.processed_receipts WHERE slot_id=$1 AND purpose='RELEASED'`, ticket.Slot[:]) != 1 {
		t.Fatal("failed C ACK rewrote V's durable receipt result")
	}
	mustExec(t, l.cp, `DROP TRIGGER release_ack_status_fault_fixture ON c_auth.closure_requests;
		DROP FUNCTION c_auth.fail_release_ack_status_fixture()`)
	if err = l.c.DeliverReceipt(ctx, ticket.Slot, receiver); err != nil {
		t.Fatalf("original release receipt could not retry after verified recovery and SQL repair: %v", err)
	}
	var acknowledgedAt, releasedAt time.Time
	if err = l.cp.QueryRow(ctx, `SELECT o.ack_at,r.released_at FROM c_auth.receipt_outbox o
		JOIN c_auth.closure_requests r USING(slot_id) JOIN c_auth.slot_ledger l USING(slot_id)
		WHERE o.slot_id=$1 AND o.state='ACKED' AND l.receipt_acknowledged`, ticket.Slot[:]).Scan(&acknowledgedAt, &releasedAt); err != nil {
		t.Fatal(err)
	}
	if !acknowledgedAt.Equal(releasedAt) || !releasedAt.Equal(control.clock.now()) {
		t.Fatal("ACK and status retention did not use the same final trusted time")
	}
	status, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret)
	if err != nil || status.State != "RELEASED" || status.ReleaseReceipt != originalWire {
		t.Fatalf("durable ACK did not expose the original bounded release result: %+v %v", status, err)
	}
	advanceClosureClock(t, control, releasedAt.Add(24*time.Hour))
	if err = l.c.recordACK(ctx, ticket.Slot, protocol.PurposeReleased); err != nil {
		t.Fatalf("same-replica ACK replay was not idempotent: %v", err)
	}
	var repeatedAt, repeatedRelease time.Time
	if err = l.cp.QueryRow(ctx, `SELECT o.ack_at,r.released_at FROM c_auth.receipt_outbox o
		JOIN c_auth.closure_requests r USING(slot_id) WHERE o.slot_id=$1`, ticket.Slot[:]).Scan(&repeatedAt, &repeatedRelease); err != nil {
		t.Fatal(err)
	}
	if !repeatedAt.Equal(acknowledgedAt) || !repeatedRelease.Equal(releasedAt) {
		t.Fatal("duplicate ACK restarted delivery or status retention")
	}
}
