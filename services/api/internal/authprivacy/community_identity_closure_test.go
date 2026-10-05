package authprivacy

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func identityClosureAccount(t *testing.T, control *gateControl, username string, identities int) (SignupResult, []uuid.UUID) {
	t.Helper()
	owner := sessionTestAccount(t, control.lab, username)
	ids := make([]uuid.UUID, 0, identities)
	for i := 0; i < identities; i++ {
		created := identityChange(t, control.lab.c, owner.SessionToken, "CREATE", uuid.Nil, fmt.Sprintf("身份%d", i+1))
		ids = append(ids, created.IdentityID)
	}
	return owner, ids
}

func identityReceiptSnapshot(t *testing.T, l *lab, account uuid.UUID) string {
	t.Helper()
	var snapshot string
	if err := l.cp.QueryRow(context.Background(), `SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY change_key_digest)::text,'[]') FROM public.identity_change_receipts r WHERE account_id=$1`, account).Scan(&snapshot); err != nil {
		t.Fatal(err)
	}
	return snapshot
}

func identityProfileSnapshot(t *testing.T, l *lab, account uuid.UUID) string {
	t.Helper()
	var snapshot string
	if err := l.cp.QueryRow(context.Background(), `SELECT jsonb_build_object(
		'identities',COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY identity_id) FROM public.community_identities i WHERE account_id=$1),'[]'::jsonb),
		'counter',(SELECT to_jsonb(s) FROM public.identity_account_state s WHERE account_id=$1))::text`, account).Scan(&snapshot); err != nil {
		t.Fatal(err)
	}
	return snapshot
}

// The complete pending account/slot/outbox snapshot detects partial closure
// even when its externally visible account state still looks unchanged.
func identityClosureAuthoritySnapshot(t *testing.T, l *lab, account uuid.UUID) string {
	t.Helper()
	var snapshot string
	if err := l.cp.QueryRow(context.Background(), `SELECT jsonb_build_object(
		'account',(SELECT to_jsonb(a) FROM c_auth.accounts a WHERE account_id=$1),
		'slot',(SELECT to_jsonb(s) FROM c_auth.slot_ledger s WHERE account_id=$1),
		'closure',(SELECT to_jsonb(c) FROM c_auth.closure_requests c WHERE account_id=$1),
		'outboxes',COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY slot_id) FROM c_auth.receipt_outbox o),'[]'::jsonb))::text`, account).Scan(&snapshot); err != nil {
		t.Fatal(err)
	}
	return snapshot
}

func TestIdentityFormalClosureZeroOneAndThreePostgres(t *testing.T) {
	for _, identities := range []int{0, 1, 3} {
		t.Run(fmt.Sprintf("identities_%d", identities), func(t *testing.T) {
			control := newGateControl(t)
			l, ctx := control.lab, context.Background()
			owner, ids := identityClosureAccount(t, control, "identity_close_user", identities)
			foreign, _ := identityClosureAccount(t, control, "identity_close_foreign", 1)
			var oldCreated time.Time
			if identities > 0 {
				if err := l.cp.QueryRow(ctx, `SELECT last_created_at FROM public.identity_account_state WHERE account_id=$1`, owner.AccountID).Scan(&oldCreated); err != nil {
					t.Fatal(err)
				}
			}
			var deletedAt time.Time
			if identities == 3 {
				identityChange(t, l.c, owner.SessionToken, "RENAME", ids[1], "改名身份")
				identityChange(t, l.c, owner.SessionToken, "DELETE", ids[0], "")
				if err := l.cp.QueryRow(ctx, `SELECT deleted_at FROM public.community_identities WHERE identity_id=$1`, ids[0]).Scan(&deletedAt); err != nil {
					t.Fatal(err)
				}
			}
			receipts := identityReceiptSnapshot(t, l, owner.AccountID)
			request, _ := closureTestRequest(t, owner.SessionToken)
			accepted, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
			if err != nil {
				t.Fatal(err)
			}
			active := identities
			if identities == 3 {
				active--
			}
			if count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND deleted_at IS NULL AND nickname IS NOT NULL AND avatar='default-v1'`, owner.AccountID) != active {
				t.Fatal("seven-day request changed identity profiles")
			}
			advanceClosureClock(t, control, accepted.DueAt.Add(-time.Microsecond))
			if n, err := l.c.FinalizeDueClosures(ctx, 10); err != nil || n != 0 {
				t.Fatalf("closed before deadline: %d %v", n, err)
			}
			advanceClosureClock(t, control, accepted.DueAt)
			if n, err := l.c.FinalizeDueClosures(ctx, 10); err != nil || n != 1 {
				t.Fatalf("formal identity close: %d %v", n, err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts WHERE account_id=$1 AND state='CLOSED'`, owner.AccountID) != 1 || count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND (deleted_at IS NULL OR nickname IS NOT NULL OR avatar IS NOT NULL OR last_renamed_at IS NOT NULL)`, owner.AccountID) != 0 {
				t.Fatal("CLOSED retained a public profile")
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE state='CLOSED' AND NOT receipt_acknowledged`) != 1 {
				t.Fatal("profile erasure incorrectly waited for V release ACK")
			}
			if count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND deleted_at=$2`, owner.AccountID, accepted.DueAt) != active {
				t.Fatal("closure tombstones did not use final authority time")
			}
			if identities == 0 {
				if count(t, l.cp, `SELECT count(*) FROM public.identity_account_state WHERE account_id=$1`, owner.AccountID) != 0 {
					t.Fatal("zero identity close created a counter")
				}
			} else {
				if count(t, l.cp, `SELECT created_count FROM public.identity_account_state WHERE account_id=$1`, owner.AccountID) != identities || count(t, l.cp, `SELECT count(*) FROM public.identity_account_state WHERE account_id=$1 AND last_created_at=$2`, owner.AccountID, oldCreated) != 1 {
					t.Fatal("closure changed cumulative creation state")
				}
			}
			if identities == 3 && count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE identity_id=$1 AND deleted_at=$2`, ids[0], deletedAt) != 1 {
				t.Fatal("closure rewrote an existing tombstone")
			}
			if identityReceiptSnapshot(t, l, owner.AccountID) != receipts {
				t.Fatal("closure changed permanent mutation receipts")
			}
			if count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND deleted_at IS NULL`, foreign.AccountID) != 1 {
				t.Fatal("closure changed another account's identity")
			}
			if _, err := l.c.ListOwnIdentities(ctx, owner.SessionToken); !errors.Is(err, ErrSessionInvalid) {
				t.Fatalf("closed bearer read identity directory: %v", err)
			}
			if n, err := l.c.FinalizeDueClosures(ctx, 10); err != nil || n != 0 {
				t.Fatalf("repeated worker did not settle: %d %v", n, err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE purpose='RELEASED'`) != 1 || identityReceiptSnapshot(t, l, owner.AccountID) != receipts {
				t.Fatal("retry duplicated release or mutated history")
			}
		})
	}
}

func TestIdentityClosureCancellationPreservesProfilesPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	owner, ids := identityClosureAccount(t, control, "identity_close_cancel", 3)
	identityChange(t, l.c, owner.SessionToken, "RENAME", ids[0], "缓冲身份")
	before := identityReceiptSnapshot(t, l, owner.AccountID)
	profiles := identityProfileSnapshot(t, l, owner.AccountID)
	request, secret := closureTestRequest(t, owner.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt.Add(-time.Second))
	login, err := l.c.CreateSession(ctx, sessionTestRequest(t, "identity_close_cancel"), sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	view := identityDirectory(t, l.c, login.SessionToken)
	if len(view.Identities) != 3 || view.CreatedCount != 3 || identityReceiptSnapshot(t, l, owner.AccountID) != before {
		t.Fatal("cancel changed profiles, counter or receipts")
	}
	if identityProfileSnapshot(t, l, owner.AccountID) != profiles {
		t.Fatal("cancel did not preserve every profile/counter field exactly")
	}
	if count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE identity_id=$1 AND nickname='缓冲身份' AND last_renamed_at IS NOT NULL AND deleted_at IS NULL`, ids[0]) != 1 {
		t.Fatal("cancel erased or reset prior rename")
	}
	if state, err := l.c.GetAccountClosureStatus(ctx, request.ID, secret); err != nil || state.State != "CANCELLED" {
		t.Fatalf("cancel status: %+v %v", state, err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	if n, err := l.c.FinalizeDueClosures(ctx, 10); err != nil || n != 0 {
		t.Fatalf("cancelled job closed account: %d %v", n, err)
	}
}

func TestIdentityClosureMultipleWorkersCommitOncePostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	owner, _ := identityClosureAccount(t, control, "identity_close_workers", 3)
	request, _ := closureTestRequest(t, owner.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	receipts := identityReceiptSnapshot(t, l, owner.AccountID)
	start := make(chan struct{})
	type answer struct {
		closed bool
		err    error
	}
	answers := make(chan answer, 4)
	for i := 0; i < 4; i++ {
		go func() {
			<-start
			closed, e := l.c.finalizeAccountClosure(ctx, owner.AccountID)
			answers <- answer{closed, e}
		}()
	}
	close(start)
	closed := 0
	for i := 0; i < 4; i++ {
		a := <-answers
		if a.err != nil {
			t.Fatal(a.err)
		}
		if a.closed {
			closed++
		}
	}
	if closed != 1 || count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE purpose='RELEASED'`) != 1 || count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND deleted_at=$2 AND nickname IS NULL AND avatar IS NULL AND last_renamed_at IS NULL`, owner.AccountID, accepted.DueAt) != 3 || identityReceiptSnapshot(t, l, owner.AccountID) != receipts {
		t.Fatal("concurrent workers duplicated or partially applied closure")
	}
}

// Pause before the Gate row is locked, after the caller has acquired its
// account/session locks. Other callers can take snapshots and visibly wait on
// the same account, giving both real business serialization orders.
type identityClosureCommitBarrier struct {
	AuthorizationGate
	mu                sync.Mutex
	paused            bool
	captured, release chan struct{}
}

func (g *identityClosureCommitBarrier) CommitAuthorized(ctx context.Context, tx pgx.Tx, generation uint64, checks ...func(AuthorizationDecision) error) (AuthorizationDecision, error) {
	g.mu.Lock()
	pause := !g.paused
	g.paused = true
	g.mu.Unlock()
	if pause {
		close(g.captured)
		select {
		case <-g.release:
		case <-ctx.Done():
			return AuthorizationDecision{}, ErrAuthorizationUnavailable
		}
	}
	return g.AuthorizationGate.CommitAuthorized(ctx, tx, generation, checks...)
}

func TestIdentityMutationAndClosureSerializePostgres(t *testing.T) {
	for _, operation := range []string{"CREATE", "RENAME"} {
		for _, order := range []string{"mutation_first", "closure_first"} {
			t.Run(operation+"_"+order, func(t *testing.T) {
				control := newGateControl(t)
				l := control.lab
				ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
				defer cancel()
				owner, ids := identityClosureAccount(t, control, "identity_close_race", 1)
				mutation := IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: operation, Nickname: "最新身份"}
				if operation == "RENAME" {
					mutation.IdentityID = ids[0]
				}
				request, _ := closureTestRequest(t, owner.SessionToken)
				passwords := sessionTestPasswordWorker(t, 1)
				barrier := &identityClosureCommitBarrier{AuthorizationGate: control.gate, captured: make(chan struct{}), release: make(chan struct{})}
				l.c.gate = barrier
				profiles, receipts := identityProfileSnapshot(t, l, owner.AccountID), identityReceiptSnapshot(t, l, owner.AccountID)
				type changeAnswer struct {
					result IdentityChangeResult
					err    error
				}
				type closeAnswer struct {
					accepted ClosureAccepted
					err      error
				}
				changes := make(chan changeAnswer, 1)
				closures := make(chan closeAnswer, 1)
				change := func() { result, e := l.c.ChangeOwnIdentity(ctx, mutation); changes <- changeAnswer{result, e} }
				closeAccount := func() {
					accepted, e := l.c.RequestAccountClosure(ctx, request, passwords)
					closures <- closeAnswer{accepted, e}
				}
				if order == "mutation_first" {
					go change()
				} else {
					go closeAccount()
				}
				<-barrier.captured
				if order == "mutation_first" {
					go closeAccount()
				} else {
					go change()
				}
				waitLock(t, l.cp, "transactionid", 1)
				close(barrier.release)
				changed, closed := <-changes, <-closures
				if closed.err != nil {
					t.Fatalf("serialized closure failed: %v", closed.err)
				}
				if order == "mutation_first" {
					if changed.err != nil || changed.result.State != "COMMITTED" || count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND nickname='最新身份' AND deleted_at IS NULL`, owner.AccountID) != 1 {
						t.Fatalf("leading mutation did not commit before closure: %v", changed.err)
					}
					expectedCount := 1
					if operation == "CREATE" {
						expectedCount = 2
					}
					if count(t, l.cp, `SELECT created_count FROM public.identity_account_state WHERE account_id=$1`, owner.AccountID) != expectedCount {
						t.Fatal("leading create count lost")
					}
				} else {
					if !errors.Is(changed.err, ErrSessionInvalid) || identityProfileSnapshot(t, l, owner.AccountID) != profiles || identityReceiptSnapshot(t, l, owner.AccountID) != receipts {
						t.Fatalf("late waiting mutation changed profiles/counter/receipts: %v", changed.err)
					}
				}
				beforeFinalReceipts := identityReceiptSnapshot(t, l, owner.AccountID)
				advanceClosureClock(t, control, closed.accepted.DueAt)
				if n, e := l.c.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
					t.Fatalf("serialized final closure: %d %v", n, e)
				}
				if count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND (deleted_at IS NULL OR nickname IS NOT NULL OR avatar IS NOT NULL OR last_renamed_at IS NOT NULL)`, owner.AccountID) != 0 || identityReceiptSnapshot(t, l, owner.AccountID) != beforeFinalReceipts {
					t.Fatal("formal closure retained leading mutation or changed receipts")
				}
			})
		}
	}
}

func TestIdentityClosureSQLFaultRollsBackEveryBoundaryPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	owner, ids := identityClosureAccount(t, control, "identity_close_fault", 3)
	identityChange(t, l.c, owner.SessionToken, "RENAME", ids[1], "故障前改名")
	identityChange(t, l.c, owner.SessionToken, "DELETE", ids[0], "")
	request, _ := closureTestRequest(t, owner.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	profiles, receipts, authority := identityProfileSnapshot(t, l, owner.AccountID), identityReceiptSnapshot(t, l, owner.AccountID), identityClosureAuthoritySnapshot(t, l, owner.AccountID)
	mustExec(t, l.cp, `CREATE FUNCTION c_auth.fail_identity_release_fixture() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
		IF NEW.purpose='RELEASED' THEN RAISE EXCEPTION 'isolated identity release insert fault'; END IF; RETURN NEW; END $$;
		CREATE TRIGGER identity_release_fault_fixture BEFORE INSERT ON c_auth.receipt_outbox FOR EACH ROW EXECUTE FUNCTION c_auth.fail_identity_release_fixture()`)
	if _, err = l.c.FinalizeDueClosures(ctx, 10); err == nil {
		t.Fatal("injected release failure committed")
	}
	if identityProfileSnapshot(t, l, owner.AccountID) != profiles || identityReceiptSnapshot(t, l, owner.AccountID) != receipts || identityClosureAuthoritySnapshot(t, l, owner.AccountID) != authority {
		t.Fatal("SQL fault partially changed account/slot/outbox/profile/history")
	}
	if _, err = control.gate.Snapshot(ctx); err != nil {
		t.Fatal("ordinary SQL business failure froze valid authorization")
	}
	mustExec(t, l.cp, `DROP TRIGGER identity_release_fault_fixture ON c_auth.receipt_outbox;DROP FUNCTION c_auth.fail_identity_release_fixture()`)
	if n, e := l.c.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
		t.Fatalf("SQL fault retry: %d %v", n, e)
	}
	if n, e := l.c.FinalizeDueClosures(ctx, 10); e != nil || n != 0 {
		t.Fatalf("SQL fault retry repeated close: %d %v", n, e)
	}
	if count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND deleted_at IS NULL`, owner.AccountID) != 0 || count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE purpose='RELEASED'`) != 1 || identityReceiptSnapshot(t, l, owner.AccountID) != receipts {
		t.Fatal("SQL retry did not close exactly once")
	}
}

func TestIdentityClosureWaiterRejectsFreezeAndOldGenerationPostgres(t *testing.T) {
	for _, mode := range []string{"frozen", "recovered_before_waiter"} {
		t.Run(mode, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			owner, ids := identityClosureAccount(t, control, "identity_close_freeze", 1)
			request, _ := closureTestRequest(t, owner.SessionToken)
			accepted, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
			if err != nil {
				t.Fatal(err)
			}
			advanceClosureClock(t, control, accepted.DueAt)
			profiles, receipts, authority := identityProfileSnapshot(t, l, owner.AccountID), identityReceiptSnapshot(t, l, owner.AccountID), identityClosureAuthoritySnapshot(t, l, owner.AccountID)
			hold, err := l.cp.Begin(ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer hold.Rollback(ctx)
			var id uuid.UUID
			if err = hold.QueryRow(ctx, `SELECT identity_id FROM public.community_identities WHERE identity_id=$1 FOR UPDATE`, ids[0]).Scan(&id); err != nil {
				t.Fatal(err)
			}
			answer := make(chan error, 1)
			go func() { _, e := l.c.FinalizeDueClosures(ctx, 10); answer <- e }()
			waitLock(t, l.cp, "transactionid", 1)
			if err = control.gate.Freeze(ctx, "identity dependent wait checkpoint"); err != nil {
				t.Fatal(err)
			}
			if mode == "recovered_before_waiter" {
				control.clock.set(control.clock.now().Add(time.Second))
				control.recover(t, AuthorizationRecoveryNormal, 3, 4)
			}
			if err = hold.Commit(ctx); err != nil {
				t.Fatal(err)
			}
			if err = <-answer; !errors.Is(err, ErrAuthorizationUnavailable) {
				t.Fatalf("old/frozen waiter passed final authorization: %v", err)
			}
			if identityProfileSnapshot(t, l, owner.AccountID) != profiles || identityReceiptSnapshot(t, l, owner.AccountID) != receipts || identityClosureAuthoritySnapshot(t, l, owner.AccountID) != authority {
				t.Fatal("freeze/stale waiter partially changed account/slot/outbox/profile/history")
			}
			if mode == "frozen" {
				control.clock.set(control.clock.now().Add(time.Second))
				control.recover(t, AuthorizationRecoveryNormal, 3, 4)
			}
			if n, e := l.c.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
				t.Fatalf("current generation retry failed: %d %v", n, e)
			}
			if n, e := l.c.FinalizeDueClosures(ctx, 10); e != nil || n != 0 {
				t.Fatalf("current generation repeated close: %d %v", n, e)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_auth.receipt_outbox WHERE purpose='RELEASED'`) != 1 || count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND deleted_at IS NULL`, owner.AccountID) != 0 || identityReceiptSnapshot(t, l, owner.AccountID) != receipts {
				t.Fatal("recovery retry duplicated release or retained profiles")
			}
		})
	}
}

// This helper deliberately uses the existing isolated synthetic eligibility
// storage command. The C signup, close, signed release, V processing and ACK
// below are real SQL operations; this does not prove OTP/SMTP or a phone flow.
func identityReturnQualifiedAccount(t *testing.T, control *gateControl, email []byte, username string) (SignupResult, protocol.SlotID) {
	t.Helper()
	l := control.lab
	ticket, private := l.ticket(t)
	ticket.Window = uint32(control.clock.now().Unix() / 1800)
	message := ticket.MessageBytes()
	copy(ticket.Signature[:], ed25519.Sign(l.vPrivate, message[:]))
	slot, err := l.v.ReserveAfterQualification(context.Background(), email, ticket.BootstrapKey)
	if err != nil {
		t.Fatal(err)
	}
	_, request := l.intent(t, ticket, private, username)
	account, err := l.c.CommitSignup(context.Background(), request)
	if err != nil {
		t.Fatal(err)
	}
	return account, slot
}

func TestIdentityClosedAccountReturnHasIndependentHistoryPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	email := []byte("identity-return@hainanu.edu.cn")
	old, slot := identityReturnQualifiedAccount(t, control, email, "identity_return_user")
	oldIDs := make([]uuid.UUID, 0, 3)
	for i := 0; i < 3; i++ {
		oldIDs = append(oldIDs, identityChange(t, l.c, old.SessionToken, "CREATE", uuid.Nil, fmt.Sprintf("历史身份%d", i+1)).IdentityID)
	}
	identityChange(t, l.c, old.SessionToken, "DELETE", oldIDs[0], "")
	receipts := identityReceiptSnapshot(t, l, old.AccountID)
	request, _ := closureTestRequest(t, old.SessionToken)
	accepted, err := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	if n, e := l.c.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
		t.Fatalf("return setup close: %d %v", n, e)
	}
	closedProfiles := identityProfileSnapshot(t, l, old.AccountID)
	probe, _ := l.ticket(t)
	if _, err = l.v.ReserveAfterQualification(ctx, email, probe.BootstrapKey); !errors.Is(err, ErrSlotUnavailable) {
		t.Fatalf("unACKed release admitted another qualification: %v", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND (deleted_at IS NULL OR nickname IS NOT NULL OR avatar IS NOT NULL)`, old.AccountID) != 0 {
		t.Fatal("pending V ACK left profiles visible")
	}
	signer := func(_ context.Context, _ uint32, message []byte) ([]byte, error) {
		return ed25519.Sign(l.cPrivate, message), nil
	}
	if ok, e := l.c.SignReceipt(ctx, slot, signer); e != nil || !ok {
		t.Fatalf("return release signing: %v %v", ok, e)
	}
	if err = l.c.DeliverReceipt(ctx, slot, func(ctx context.Context, encoded string, purpose protocol.Purpose) error {
		return l.v.ProcessReceipt(ctx, encoded, purpose)
	}); err != nil {
		t.Fatal(err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE email_exact=$1`, email) != 0 || count(t, l.cp, `SELECT count(*) FROM c_auth.slot_ledger WHERE slot_id=$1 AND receipt_acknowledged`, slot[:]) != 1 {
		t.Fatal("release ACK did not free exact-email quota")
	}
	fresh, newSlot := identityReturnQualifiedAccount(t, control, email, "identity_return_user")
	if fresh.AccountID == old.AccountID || newSlot == slot {
		t.Fatal("return reused closed account or old qualification slot")
	}
	view := identityDirectory(t, l.c, fresh.SessionToken)
	if view.CreatedCount != 0 || len(view.Identities) != 0 || view.NextCreateAt != nil {
		t.Fatal("new account inherited identities or cumulative creation cooldown")
	}
	created := identityChange(t, l.c, fresh.SessionToken, "CREATE", uuid.Nil, "历史身份1")
	for _, id := range oldIDs {
		if created.IdentityID == id {
			t.Fatal("new account inherited an old identity ID")
		}
	}
	view = identityDirectory(t, l.c, fresh.SessionToken)
	if view.CreatedCount != 1 || len(view.Identities) != 1 || !view.Identities[0].IsOriginal || view.NextCreateAt != nil {
		t.Fatal("new account did not start independent creation history")
	}
	if identityProfileSnapshot(t, l, old.AccountID) != closedProfiles || identityReceiptSnapshot(t, l, old.AccountID) != receipts || count(t, l.cp, `SELECT created_count FROM public.identity_account_state WHERE account_id=$1`, old.AccountID) != 3 {
		t.Fatal("return rebound or changed old tombstones/counter/receipts")
	}
	if count(t, l.cp, `SELECT count(*) FROM public.identity_change_receipts WHERE account_id=$1`, fresh.AccountID) != 1 {
		t.Fatal("new account inherited old mutation receipts")
	}
	if _, err = l.c.ListOwnIdentities(ctx, old.SessionToken); !errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("old bearer inherited new account authority: %v", err)
	}
}

func TestIdentityClosureConstraintSerializesDirectDeletionPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	owner, ids := identityClosureAccount(t, control, "identity_delete_sql", 2)
	receipts := identityReceiptSnapshot(t, l, owner.AccountID)
	transactions := make([]pgx.Tx, 0, 2)
	for _, id := range ids {
		tx, err := l.cp.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		if _, err = tx.Exec(ctx, `UPDATE public.community_identities SET nickname=NULL,avatar=NULL,last_renamed_at=NULL,deleted_at=$2 WHERE identity_id=$1`, id, control.clock.now()); err != nil {
			t.Fatal(err)
		}
		transactions = append(transactions, tx)
	}
	start := make(chan struct{})
	answers := make(chan error, 2)
	for _, tx := range transactions {
		go func(tx pgx.Tx) { <-start; answers <- tx.Commit(ctx) }(tx)
	}
	close(start)
	success, rejected := 0, 0
	for range transactions {
		err := <-answers
		if err == nil {
			success++
			continue
		}
		var constraint *pgconn.PgError
		if !errors.As(err, &constraint) || constraint.Code != "23514" {
			t.Fatalf("unexpected direct deletion commit failure: %v", err)
		}
		rejected++
	}
	if success != 1 || rejected != 1 || count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND deleted_at IS NULL`, owner.AccountID) != 1 || count(t, l.cp, `SELECT created_count FROM public.identity_account_state WHERE account_id=$1`, owner.AccountID) != 2 || identityReceiptSnapshot(t, l, owner.AccountID) != receipts {
		t.Fatal("deferred account shape allowed direct concurrent deletion of the last identity")
	}
}

func TestInactiveIdentityProjectionHasNoAccountLinks(t *testing.T) {
	first, second := uuid.New(), uuid.New()
	deleted, err := ProjectInactiveIdentityLifecycle(first, false, true)
	if err != nil {
		t.Fatal(err)
	}
	closed, err := ProjectInactiveIdentityLifecycle(first, true, true)
	if err != nil {
		t.Fatal(err)
	}
	other, err := ProjectInactiveIdentityLifecycle(second, true, false)
	if err != nil {
		t.Fatal(err)
	}
	if closed.State != IdentityAccountClosed || deleted.State != IdentityDeleted || closed.Avatar != IdentityInactiveAvatar || other.Avatar != closed.Avatar || deleted.PlaceholderToken != closed.PlaceholderToken || closed.PlaceholderToken == other.PlaceholderToken {
		t.Fatal("inactive projection linked masks or ignored closure precedence")
	}
	raw, err := base64.RawURLEncoding.DecodeString(closed.PlaceholderToken)
	if err != nil || len(raw) != 32 {
		t.Fatal("placeholder must be a full opaque identity token")
	}
	wire, err := json.Marshal(closed)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err = json.Unmarshal(wire, &fields); err != nil {
		t.Fatal(err)
	}
	if len(fields) != 3 || fields["placeholderToken"] != closed.PlaceholderToken || fields["avatar"] != IdentityInactiveAvatar || fields["state"] != string(IdentityAccountClosed) {
		t.Fatal("projection exposed account/profile/internal fields")
	}
	if _, err = ProjectInactiveIdentityLifecycle(first, false, false); err == nil {
		t.Fatal("active identity projected as deleted")
	}
	if _, err = ProjectInactiveIdentityLifecycle(uuid.Nil, true, true); err == nil {
		t.Fatal("empty identity token accepted")
	}
	if _, err = ProjectInactiveIdentity(first, InactiveIdentityState("PENDING_CLOSE")); err == nil {
		t.Fatal("buffered closure exposed inactive state")
	}
}
