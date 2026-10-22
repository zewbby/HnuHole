package authprivacy

import (
	"context"
	"errors"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"sync"
	"testing"
)

func TestEmailLoginExistingAccountAndReplayPostgres(t *testing.T) {
	l, e, capture := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	ticket, priv := l.ticket(t)
	_, signup := l.intent(t, ticket, priv, "email_login_user")
	old, err := l.c.CommitSignup(ctx, signup)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = l.v.ReserveAfterQualification(ctx, []byte("existing@hainanu.edu.cn"), ticket.BootstrapKey); err != nil {
		t.Fatal(err)
	}
	request := otpFixtureRequest(t, "existing@hainanu.edu.cn")
	request.Purpose = "LOGIN"
	accepted, err := e.RequestOTP(ctx, request)
	if err != nil {
		t.Fatal(err)
	}
	_, code := capture.captured()
	cReq := EmailSessionRequest{InstallationID: [16]byte{11}, IdempotencyKey: [32]byte{12}}
	confirm := EmailLoginConfirmation{Key: [32]byte{13}, FlowID: accepted.FlowID, InstallationID: request.InstallationID, Binding: protocol.EmailLoginBinding(cReq.InstallationID, cReq.IdempotencyKey), OTP: code}
	// Registration cannot consume the login code or allocate qualification.
	if _, err = e.ConfirmOTP(ctx, ConfirmOTPRequest{Key: [32]byte{14}, FlowID: accepted.FlowID, InstallationID: request.InstallationID, OTP: code, SlotID: ticket.Slot, BootstrapPublicKey: ticket.BootstrapKey}); !errors.Is(err, ErrOTPFlowInvalid) {
		t.Fatal("login OTP crossed purpose", err)
	}
	result, err := e.ConfirmEmailLogin(ctx, confirm)
	if err != nil || result.State != "PROOF_AVAILABLE" {
		t.Fatal("login proof missing", err)
	}
	replay, err := e.ConfirmEmailLogin(ctx, confirm)
	if err != nil || replay != result {
		t.Fatal("confirmation replay changed", err)
	}
	changed := confirm
	changed.Binding[0] ^= 1
	if _, err = e.ConfirmEmailLogin(ctx, changed); !errors.Is(err, ErrConflict) {
		t.Fatal("binding substitution admitted", err)
	}
	cReq.Proof = result.Proof
	wrong := cReq
	wrong.InstallationID[0] ^= 1
	if _, err = l.c.CreateEmailSession(ctx, wrong); !errors.Is(err, ErrEmailProofInvalid) {
		t.Fatal("wrong device admitted", err)
	}
	var wg sync.WaitGroup
	var mu sync.Mutex
	success, replays := 0, 0
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			created, er := l.c.CreateEmailSession(ctx, cReq)
			mu.Lock()
			defer mu.Unlock()
			if er == nil {
				success++
				if created.AccountID != old.AccountID {
					t.Error("login created a replacement account")
				}
			} else if errors.Is(er, ErrSessionCreatedReplay) {
				replays++
			} else {
				t.Error(er)
			}
		}()
	}
	wg.Wait()
	if success != 1 || replays != 1 {
		t.Fatal("same-key race created extra sessions", success, replays)
	}
	if _, err = l.c.AuthorizeExistingSession(ctx, old.SessionToken); !errors.Is(err, ErrSessionReplaced) {
		t.Fatal("old device still active", err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_auth.accounts`) != 1 || count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota`) != 1 {
		t.Fatal("login changed account/quota count")
	}
	if calls, _ := capture.captured(); calls != 1 {
		t.Fatal("duplicate SMTP send")
	}
	mustExec(t, l.vp, `UPDATE v_auth.email_login_confirmations SET expires_at=clock_timestamp()-interval '1 second'`)
	if err = e.CleanupOTP(ctx, 16); err != nil {
		t.Fatal(err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.email_login_confirmations WHERE result_code='EXPIRED' AND proof IS NULL AND flow_id IS NULL AND installation_id IS NULL AND binding IS NULL AND request_hmac IS NULL`) != 1 {
		t.Fatal("confirmation associations retained after expiry")
	}
	if _, err = e.ConfirmEmailLogin(ctx, confirm); !errors.Is(err, ErrExpired) {
		t.Fatal("expired anchor reopened", err)
	}

}
func TestEmailLoginUnregisteredAndWrongCodePostgres(t *testing.T) {
	l, e, capture := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	request := otpFixtureRequest(t, "newemail@hainanu.edu.cn")
	request.Purpose = "LOGIN"
	accepted, err := e.RequestOTP(ctx, request)
	if err != nil {
		t.Fatal(err)
	}
	_, code := capture.captured()
	req := EmailLoginConfirmation{Key: [32]byte{1}, FlowID: accepted.FlowID, InstallationID: request.InstallationID, Binding: [32]byte{2}, OTP: wrongOTP(code)}
	if _, err = e.ConfirmEmailLogin(ctx, req); !errors.Is(err, ErrOTPInvalid) {
		t.Fatal(err)
	}
	if _, err = e.ConfirmEmailLogin(ctx, req); !errors.Is(err, ErrOTPInvalid) {
		t.Fatal(err)
	}
	if count(t, l.vp, `SELECT failed_attempts FROM v_auth.otp_flows WHERE flow_id=$1`, accepted.FlowID[:]) != 1 {
		t.Fatal("same wrong operation counted twice")
	}
	req.Key = [32]byte{3}
	req.OTP = code
	result, err := e.ConfirmEmailLogin(ctx, req)
	if err != nil || result.State != "UNREGISTERED" || result.Proof != "" {
		t.Fatal("new email did not require explicit registration", err)
	}
	if count(t, l.vp, `SELECT count(*) FROM v_auth.email_quota`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_auth.accounts`) != 0 {
		t.Fatal("login silently registered")
	}
}
