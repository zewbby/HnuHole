package authprivacy

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type confirmationPeerFunc func(context.Context, string) (RetirementReply, error)

func (f confirmationPeerFunc) RetireUnusedSlot(ctx context.Context, wire string) (RetirementReply, error) {
	return f(ctx, wire)
}

type confirmationMailCapture struct {
	mu   sync.Mutex
	code string
}

func (m *confirmationMailCapture) SendOTP(_ context.Context, _ [32]byte, _, code string) (MailOutcome, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.code = code
	return MailSent, nil
}

func newConfirmationTestEligibility(t *testing.T) (*lab, *Eligibility, *confirmationMailCapture) {
	t.Helper()
	l := newLab(t)
	mail := &confirmationMailCapture{}
	var keys [4][32]byte
	for i := range keys {
		if _, err := rand.Read(keys[i][:]); err != nil {
			t.Fatal("cannot create isolated purpose keys")
		}
	}
	config := EligibilityConfig{OTPKey: keys[0], OTPKeyVersion: 1, MailEncryptionKey: keys[1], MailEncryptionKeyVersion: 1, RequestHMACKey: keys[2], HMACKeyVersion: 1, LimitKey: keys[3], RegistrationEpoch: 1, SendBudget: 100, VerifyBudget: 100}
	e, err := NewEligibility(l.v, config, func(_ context.Context, _ uint32, message []byte) ([]byte, error) {
		return ed25519.Sign(l.vPrivate, message), nil
	}, mail, confirmationPeerFunc(func(context.Context, string) (RetirementReply, error) {
		return RetirementReply{}, errors.New("retirement not expected by fixture")
	}))
	if err != nil {
		t.Fatal(err)
	}
	return l, e, mail
}

func confirmationFixture(t *testing.T, l *lab, e *Eligibility, mail *confirmationMailCapture, email string) ConfirmOTPRequest {
	t.Helper()
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	var installation [16]byte
	if _, err = rand.Read(installation[:]); err != nil {
		t.Fatal(err)
	}
	flow, err := e.RequestOTP(context.Background(), OTPRequest{Key: key, InstallationID: installation, Email: email})
	if err != nil || flow.State != "ACCEPTED" || flow.FlowID == ([32]byte{}) {
		t.Fatalf("request OTP fixture: state=%s err=%v", flow.State, err)
	}
	key, err = random32()
	if err != nil {
		t.Fatal(err)
	}
	ticket, _ := l.ticket(t)
	mail.mu.Lock()
	code := mail.code
	mail.mu.Unlock()
	return ConfirmOTPRequest{Key: key, FlowID: flow.FlowID, InstallationID: installation, OTP: code, SlotID: ticket.Slot, BootstrapPublicKey: ticket.BootstrapKey}
}

func confirmationReceipt(t *testing.T, l *lab, slot protocol.SlotID, purpose protocol.Purpose) string {
	t.Helper()
	r := protocol.Receipt{Purpose: purpose, Epoch: 1, Slot: slot}
	message, err := r.MessageBytes()
	if err != nil {
		t.Fatal(err)
	}
	copy(r.Signature[:], ed25519.Sign(l.cPrivate, message))
	wire, err := r.Encode()
	if err != nil {
		t.Fatal(err)
	}
	return wire
}

func TestConfirmationAtomicTicketReplayAndReadonlyResult(t *testing.T) {
	l, e, mail := newConfirmationTestEligibility(t)
	ctx := context.Background()
	req := confirmationFixture(t, l, e, mail, "confirmation-atomic@hainanu.edu.cn")
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", req.Key[:])
	signCalls := 0
	e.signer = func(_ context.Context, epoch uint32, message []byte) ([]byte, error) {
		signCalls++
		if epoch != 1 || len(message) != 92 || count(t, l.vp, `SELECT count(*) FROM v_auth.otp_flows WHERE flow_id=$1 AND state='CONSUMED'`, req.FlowID[:]) != 1 || count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE current_slot=$1 AND reservation_confirmation_key_digest=$2`, req.SlotID[:], key[:]) != 1 || count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_sign_jobs WHERE confirmation_key_digest=$1 AND reg_message=$2 AND state='PENDING_SIGN'`, key[:], message) != 1 {
			t.Fatal("signer observed a message without committed OTP/quota/job")
		}
		return ed25519.Sign(l.vPrivate, message), nil
	}
	result, err := e.ConfirmOTP(ctx, req)
	if err != nil || result.State != "TICKET_AVAILABLE" || result.RegistrationTicket == "" || signCalls != 1 {
		t.Fatalf("confirmation: state=%s err=%v calls=%d", result.State, err, signCalls)
	}
	var at time.Time
	if err = l.vp.QueryRow(ctx, `SELECT verified_at FROM v_auth.otp_confirmations WHERE confirmation_key_digest=$1`, key[:]).Scan(&at); err != nil {
		t.Fatal(err)
	}
	ticket, err := l.v.verifier.VerifyRegistrationTicket(result.RegistrationTicket, at)
	if err != nil || ticket.Slot != req.SlotID || ticket.BootstrapKey != req.BootstrapPublicKey || ticket.Window != uint32(at.Unix()/1800) {
		t.Fatal("confirmed ticket did not preserve original verified scope/time")
	}
	replayed, err := e.ConfirmOTP(ctx, req)
	if err != nil || replayed.RegistrationTicket != result.RegistrationTicket || signCalls != 1 {
		t.Fatal("original POST replay reverified/resigned or changed ticket")
	}
	status, err := e.GetOTPConfirmationResult(ctx, req.Key, req.FlowID, req.InstallationID)
	if err != nil || status.State != "TICKET_AVAILABLE" || status.RegistrationTicket != "" || signCalls != 1 {
		t.Fatal("GET exposed ticket or drove signing")
	}
	changed := req
	changed.OTP = "000000"
	if changed.OTP == req.OTP {
		changed.OTP = "111111"
	}
	if _, err = e.ConfirmOTP(ctx, changed); !errors.Is(err, ErrConflict) {
		t.Fatal("same key allowed changed original OTP body")
	}
	wrongInstallation := req.InstallationID
	wrongInstallation[0] ^= 1
	if _, err = e.GetOTPConfirmationResult(ctx, req.Key, req.FlowID, wrongInstallation); !errors.Is(err, ErrResultAuthentication) {
		t.Fatal("GET accepted wrong installation")
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events WHERE kind='VERIFY'`) != 1 {
		t.Fatal("replay/result read counted the OTP again")
	}
}

func TestConfirmationLateHSMCannotPublishReleasedSlot(t *testing.T) {
	l, e, mail := newConfirmationTestEligibility(t)
	ctx := context.Background()
	req := confirmationFixture(t, l, e, mail, "confirmation-late-signer@hainanu.edu.cn")
	e.signer = func(ctx context.Context, _ uint32, message []byte) ([]byte, error) {
		if err := l.v.ProcessReceipt(ctx, confirmationReceipt(t, l, req.SlotID, protocol.PurposeReleased), protocol.PurposeReleased); err != nil {
			t.Fatal(err)
		}
		return ed25519.Sign(l.vPrivate, message), nil
	}
	if _, err := e.ConfirmOTP(ctx, req); !errors.Is(err, ErrReverifyRequired) {
		t.Fatalf("late signer published released slot: %v", err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_sign_jobs WHERE state='READY' OR signature IS NOT NULL`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.used_slots WHERE slot_id=$1 AND state='RELEASED'`, req.SlotID[:]) != 1 {
		t.Fatal("late HSM result changed terminal/quota evidence")
	}
}

func TestConfirmationOriginalRetirementContinuesAfterPushedReceipt(t *testing.T) {
	l, e, mail := newConfirmationTestEligibility(t)
	ctx := context.Background()
	email := "confirmation-push-first@hainanu.edu.cn"
	old, _ := l.ticket(t)
	if _, err := l.v.ReserveAfterQualification(ctx, []byte(email), old.BootstrapKey); err != nil {
		t.Fatal(err)
	}
	req := confirmationFixture(t, l, e, mail, email)
	peerCalls := 0
	e.retirePeer = confirmationPeerFunc(func(ctx context.Context, wire string) (RetirementReply, error) {
		peerCalls++
		authorization, err := l.v.verifier.VerifyRetirementAuthorization(wire)
		if err != nil || authorization.Slot != old.Slot || count(t, l.vp, `SELECT count(*) FROM v_auth.retire_pending WHERE old_slot=$1 AND retirement_authorization IS NOT NULL`, old.Slot[:]) != 1 {
			t.Fatal("peer received an uncommitted or wrong original authorization")
		}
		if err = l.v.ProcessReceipt(ctx, confirmationReceipt(t, l, old.Slot, protocol.PurposeRetired), protocol.PurposeRetired); err != nil {
			t.Fatal(err)
		}
		return RetirementReply{Pending: true}, nil // Late PENDING cannot undo push.
	})
	result, err := e.ConfirmOTP(ctx, req)
	if err != nil || result.State != "TICKET_AVAILABLE" || peerCalls != 1 {
		t.Fatalf("push-first continuation: %s %v calls=%d", result.State, err, peerCalls)
	}
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", req.Key[:])
	var verifiedAt, replayUntil time.Time
	var savedOld, savedNew []byte
	if err = l.vp.QueryRow(ctx, `SELECT verified_at,ticket_replay_until,old_slot,new_slot FROM v_auth.otp_confirmations WHERE confirmation_key_digest=$1`, key[:]).Scan(&verifiedAt, &replayUntil, &savedOld, &savedNew); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(savedOld, old.Slot[:]) || !bytes.Equal(savedNew, req.SlotID[:]) || !replayUntil.Equal(verifiedAt.Add(10*time.Minute)) || count(t, l.vp, `SELECT count(*) FROM v_auth.retire_pending`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE current_slot=$1 AND reservation_confirmation_key_digest=$2`, req.SlotID[:], key[:]) != 1 {
		t.Fatal("continuation discarded binding or moved its original replay deadline")
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events WHERE kind='VERIFY'`) != 1 {
		t.Fatal("retirement continuation consumed/recounted OTP twice")
	}
	if _, err = e.ConfirmOTP(ctx, req); err != nil || peerCalls != 1 {
		t.Fatal("completed original replay re-retired old slot")
	}
}

func TestConfirmationContinuationDoesNotClearAnotherReservation(t *testing.T) {
	l, e, mail := newConfirmationTestEligibility(t)
	ctx := context.Background()
	email := "confirmation-competing-reservation@hainanu.edu.cn"
	old, _ := l.ticket(t)
	other, _ := l.ticket(t)
	if _, err := l.v.ReserveAfterQualification(ctx, []byte(email), old.BootstrapKey); err != nil {
		t.Fatal(err)
	}
	req := confirmationFixture(t, l, e, mail, email)
	e.retirePeer = confirmationPeerFunc(func(ctx context.Context, _ string) (RetirementReply, error) {
		if err := l.v.ProcessReceipt(ctx, confirmationReceipt(t, l, old.Slot, protocol.PurposeRetired), protocol.PurposeRetired); err != nil {
			t.Fatal(err)
		}
		if _, err := l.v.ReserveAfterQualification(ctx, []byte(email), other.BootstrapKey); err != nil {
			t.Fatal(err)
		}
		return RetirementReply{SlotNotRetirable: true}, nil // Contradictory late refusal.
	})
	if _, err := e.ConfirmOTP(ctx, req); !errors.Is(err, ErrEligibilityReserved) {
		t.Fatalf("competing reservation was not rejected: %v", err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota WHERE email_exact=$1 AND current_slot=$2`, []byte(email), other.Slot[:]) != 1 || count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_sign_jobs`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.used_slots WHERE slot_id=$1`, req.SlotID[:]) != 0 {
		t.Fatal("original continuation changed another reservation")
	}
}

func TestConfirmationCleanupPreservesExpiredRetirementUntilSettled(t *testing.T) {
	l, e, _ := newConfirmationTestEligibility(t)
	ctx := context.Background()
	email := []byte("confirmation-expired-pending@hainanu.edu.cn")
	old, _ := l.ticket(t)
	newTicket, _ := l.ticket(t)
	if _, err := l.v.ReserveAfterQualification(ctx, email, old.BootstrapKey); err != nil {
		t.Fatal(err)
	}
	rawKey, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	flow, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	var installation [16]byte
	if _, err = rand.Read(installation[:]); err != nil {
		t.Fatal(err)
	}
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", rawKey[:])
	req := ConfirmOTPRequest{Key: rawKey, FlowID: flow, InstallationID: installation, OTP: "123456", SlotID: newTicket.Slot, BootstrapPublicKey: newTicket.BootstrapKey}
	tx, err := e.store.beginAuthorized(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	var verifiedAt time.Time
	if err = verifierTrustedAt(ctx, tx, &verifiedAt); err != nil {
		t.Fatal(err)
	}
	verifiedAt = verifiedAt.Add(-11 * time.Minute)
	version := int64(1)
	r := confirmationRecord{Key: key, Flow: flow, Install: installation, Email: email, OldSlot: old.Slot[:], OldVersion: &version, NewSlot: newTicket.Slot, BootstrapKey: newTicket.BootstrapKey, VerifiedAt: verifiedAt, OTPExpiresAt: verifiedAt.Add(5 * time.Minute), Window: uint32(verifiedAt.Unix() / 1800), Epoch: 1, State: "RETIREMENT_PENDING", AuthorizationGeneration: verifierGeneration(tx)}
	mac := confirmationMAC(e, req)
	if err = e.insertConfirmationAnchor(ctx, tx, req, key, mac, r.State, verifiedAt); err != nil {
		t.Fatal(err)
	}
	if err = insertConfirmation(ctx, tx, r); err != nil {
		t.Fatal(err)
	}
	message := (protocol.Authorization{Epoch: 1, Slot: old.Slot}).MessageBytes()
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.retire_pending(old_slot,email_exact,quota_version,new_slot,new_bootstrap_public_key,retirement_authorization,state,confirmation_key_digest,authorization_message,signing_key_epoch,authorization_generation) VALUES($1,$2,1,$3,$4,NULL,'PENDING',$5,$6,1,$7)`, old.Slot[:], email, newTicket.Slot[:], newTicket.BootstrapKey[:], key[:], message[:], int64(verifierGeneration(tx))); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if n, err := e.CleanupConfirmations(ctx, 10); err != nil || n != 1 {
		t.Fatalf("cleanup original: count=%d err=%v", n, err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.otp_confirmations WHERE confirmation_key_digest=$1 AND flow_id IS NULL AND installation_id IS NULL`, key[:]) != 1 || count(t, l.vp, `SELECT count(*) FROM v_auth.retire_pending WHERE old_slot=$1`, old.Slot[:]) != 1 {
		t.Fatal("cleanup cancelled retirement or retained private result binding")
	}
	if _, err = e.GetOTPConfirmationResult(ctx, rawKey, flow, installation); !errors.Is(err, ErrExpired) {
		t.Fatal("expired result anchor accepted GET")
	}
	e.retirePeer = confirmationPeerFunc(func(_ context.Context, wire string) (RetirementReply, error) {
		authorization, err := l.v.verifier.VerifyRetirementAuthorization(wire)
		if err != nil || authorization.Slot != old.Slot {
			t.Fatal("worker lost original retirement binding after result cleanup")
		}
		return RetirementReply{Receipt: confirmationReceipt(t, l, old.Slot, protocol.PurposeRetired)}, nil
	})
	if n, err := e.ResumePendingConfirmations(ctx, 10); err != nil || n != 1 {
		t.Fatalf("expired original worker: count=%d err=%v", n, err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_sign_jobs`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.used_slots WHERE slot_id=$1`, newTicket.Slot[:]) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.processed_receipts WHERE slot_id=$1 AND purpose='RETIRED'`, old.Slot[:]) != 1 {
		t.Fatal("expired worker minted new qualification or lost terminal old-slot proof")
	}
	if n, err := e.CleanupConfirmations(ctx, 10); err != nil || n != 1 {
		t.Fatalf("resolved cleanup: count=%d err=%v", n, err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.otp_confirmations`) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.request_results WHERE key_digest=$1 AND state='EXPIRED'`, key[:]) != 1 {
		t.Fatal("resolved cleanup retained identity or erased permanent tombstone")
	}
	if _, err = e.ConfirmOTP(ctx, req); !errors.Is(err, ErrExpired) {
		t.Fatal("expired permanent key silently executed as a new request")
	}
}

func TestConfirmationRateLimitedReplayPreservesOriginalWait(t *testing.T) {
	l, e, mail := newConfirmationTestEligibility(t)
	ctx := context.Background()
	email := "confirmation-rate-replay@hainanu.edu.cn"
	req := confirmationFixture(t, l, e, mail, email)
	wrong := "000000"
	if wrong == req.OTP {
		wrong = "111111"
	}
	req.OTP = wrong
	var original *EligibilityError
	for attempt := 0; attempt < 3; attempt++ {
		key, err := random32()
		if err != nil {
			t.Fatal(err)
		}
		req.Key = key
		_, err = e.ConfirmOTP(ctx, req)
		if attempt < 2 {
			if !errors.Is(err, ErrOTPInvalid) {
				t.Fatalf("wrong OTP %d: %v", attempt+1, err)
			}
		} else if !errors.As(err, &original) || original.Code != "RATE_LIMITED" || original.RetryAfterSeconds < 299 || original.RetryAfterSeconds > 300 {
			t.Fatalf("third wrong OTP did not create original five-minute lock: %v", err)
		}
	}
	device := e.deviceEmailDigest([]byte(email))
	var before time.Time
	if err := l.vp.QueryRow(ctx, `SELECT locked_until FROM v_auth.device_email_limits WHERE installation_id=$1 AND email_digest=$2`, req.InstallationID[:], device[:]).Scan(&before); err != nil {
		t.Fatal(err)
	}
	budgetBefore := count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events WHERE kind='VERIFY'`)
	anchorBefore := count(t, l.vp, `SELECT count(*) FROM v_auth.request_results`)
	for replay := 0; replay < 2; replay++ {
		_, err := e.ConfirmOTP(ctx, req)
		var cached *EligibilityError
		if !errors.As(err, &cached) || cached.Code != "RATE_LIMITED" || cached.RetryAfterSeconds < original.RetryAfterSeconds-2 || cached.RetryAfterSeconds > original.RetryAfterSeconds {
			t.Fatalf("cached original lock lost actual remaining wait: %v", err)
		}
	}
	var after time.Time
	if err := l.vp.QueryRow(ctx, `SELECT locked_until FROM v_auth.device_email_limits WHERE installation_id=$1 AND email_digest=$2`, req.InstallationID[:], device[:]).Scan(&after); err != nil {
		t.Fatal(err)
	}
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", req.Key[:])
	var saved time.Time
	if err := l.vp.QueryRow(ctx, `SELECT retry_until FROM v_auth.confirmation_rejections WHERE confirmation_key_digest=$1`, key[:]).Scan(&saved); err != nil {
		t.Fatal(err)
	}
	if !before.Equal(after) || !before.Equal(saved) || count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events WHERE kind='VERIFY'`) != budgetBefore || count(t, l.vp, `SELECT count(*) FROM v_auth.request_results`) != anchorBefore || count(t, l.vp, `SELECT failed_attempts FROM v_auth.otp_flows WHERE flow_id=$1`, req.FlowID[:]) != 3 {
		t.Fatal("original RATE_LIMITED replay changed lock, budget, anchors, or attempts")
	}
	// Already-locked arbitrary new keys have no counted OTP decision and must
	// not allocate permanent anchors or rejection sidecars.
	req.Key, _ = random32()
	if _, err := e.ConfirmOTP(ctx, req); !errors.Is(err, ErrRateLimited) {
		t.Fatal("device lock did not govern a fresh request")
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.request_results`) != anchorBefore || count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_rejections`) != 1 {
		t.Fatal("already-locked uncounted request minted a permanent result")
	}
}

func TestConfirmationExpiredOriginalLockReplayDoesNotExtendOrRecount(t *testing.T) {
	l, e, _ := newConfirmationTestEligibility(t)
	ctx := context.Background()
	ticket, _ := l.ticket(t)
	rawKey, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	flow, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	var installation [16]byte
	if _, err = rand.Read(installation[:]); err != nil {
		t.Fatal(err)
	}
	req := ConfirmOTPRequest{Key: rawKey, FlowID: flow, InstallationID: installation, OTP: "123456", SlotID: ticket.Slot, BootstrapPublicKey: ticket.BootstrapKey}
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", rawKey[:])
	device := e.deviceEmailDigest([]byte("confirmation-expired-lock@hainanu.edu.cn"))
	tx, err := begin(ctx, l.vp)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	var rejectedAt time.Time
	if err = tx.QueryRow(ctx, `SELECT clock_timestamp()-interval '6 minutes'`).Scan(&rejectedAt); err != nil {
		t.Fatal(err)
	}
	until := rejectedAt.Add(5 * time.Minute)
	// The cache is still inside its immutable ten-minute replay lifetime, but
	// its original five-minute lock has elapsed. Its old flow was already erased.
	mac := confirmationMAC(e, req)
	if err = e.insertConfirmationAnchor(ctx, tx, req, key, mac, "RATE_LIMITED", rejectedAt); err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.confirmation_rejections(confirmation_key_digest,retry_until) VALUES($1,$2)`, key[:], until); err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.device_email_limits(installation_id,email_digest,consecutive_errors,locked_until) VALUES($1,$2,3,$3)`, installation[:], device[:], until); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	_, err = e.ConfirmOTP(ctx, req)
	var cached *EligibilityError
	if !errors.As(err, &cached) || cached.Code != "RATE_LIMITED" || cached.RetryAfterSeconds != 0 {
		t.Fatalf("expired original lock recreated a wait or re-executed OTP: %v", err)
	}
	var after time.Time
	if err = l.vp.QueryRow(ctx, `SELECT locked_until FROM v_auth.device_email_limits WHERE installation_id=$1 AND email_digest=$2`, installation[:], device[:]).Scan(&after); err != nil {
		t.Fatal(err)
	}
	if !until.Equal(after) || count(t, l.vp, `SELECT count(*) FROM v_auth.otp_budget_events WHERE kind='VERIFY'`) != 0 || count(t, l.vp, `SELECT consecutive_errors FROM v_auth.device_email_limits WHERE installation_id=$1 AND email_digest=$2`, installation[:], device[:]) != 3 || count(t, l.vp, `SELECT count(*) FROM v_auth.otp_flows`) != 0 {
		t.Fatal("expired cached failure changed lock, verification state, or flow association")
	}
	// A separately inserted historical result has reached its original replay
	// deadline. Cleanup must atomically erase the short-lived rejection detail
	// and shrink its permanent key; it must preserve the still-live result above.
	expired := req
	expired.Key, err = random32()
	if err != nil {
		t.Fatal(err)
	}
	expiredKey := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", expired.Key[:])
	cleanupTx, err := begin(ctx, l.vp)
	if err != nil {
		t.Fatal(err)
	}
	defer cleanupTx.Rollback(ctx)
	var oldAt time.Time
	if err = cleanupTx.QueryRow(ctx, `SELECT clock_timestamp()-interval '11 minutes'`).Scan(&oldAt); err != nil {
		t.Fatal(err)
	}
	mac = confirmationMAC(e, expired)
	if err = e.insertConfirmationAnchor(ctx, cleanupTx, expired, expiredKey, mac, "RATE_LIMITED", oldAt); err != nil {
		t.Fatal(err)
	}
	if _, err = cleanupTx.Exec(ctx, `INSERT INTO v_auth.confirmation_rejections(confirmation_key_digest,retry_until) VALUES($1,$2)`, expiredKey[:], oldAt.Add(5*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if err = cleanupTx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if n, err := e.CleanupConfirmations(ctx, 10); err != nil || n != 1 {
		t.Fatalf("rejection detail cleanup: count=%d err=%v", n, err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.request_results WHERE key_digest=$1 AND state='EXPIRED'`, expiredKey[:]) != 1 || count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_rejections WHERE confirmation_key_digest=$1`, expiredKey[:]) != 0 || count(t, l.vp, `SELECT count(*) FROM v_auth.confirmation_rejections WHERE confirmation_key_digest=$1`, key[:]) != 1 {
		t.Fatal("cleanup left rejection detail or erased a live original deadline")
	}
	if _, err = e.ConfirmOTP(ctx, expired); !errors.Is(err, ErrExpired) {
		t.Fatal("expired rejected key silently became a new attempt")
	}
}
