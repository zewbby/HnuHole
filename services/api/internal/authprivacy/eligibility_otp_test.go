package authprivacy

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"
)

type otpCaptureProvider struct {
	mu      sync.Mutex
	outcome MailOutcome
	calls   int
	codes   []string
}

func (p *otpCaptureProvider) SendOTP(_ context.Context, _ [32]byte, _ string, code string) (MailOutcome, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.calls++
	p.codes = append(p.codes, code)
	return p.outcome, nil
}
func (p *otpCaptureProvider) captured() (int, string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.codes) == 0 {
		return p.calls, ""
	}
	return p.calls, p.codes[len(p.codes)-1]
}

type otpNoRetirePeer struct{}

func (otpNoRetirePeer) RetireUnusedSlot(context.Context, string) (RetirementReply, error) {
	return RetirementReply{}, errors.New("retirement not used in OTP boundary test")
}

func newOTPTestEligibility(t *testing.T, outcome MailOutcome) (*lab, *Eligibility, *otpCaptureProvider) {
	t.Helper()
	l := newLab(t)
	capture := &otpCaptureProvider{outcome: outcome}
	var keys [4][32]byte
	for i := range keys {
		if _, err := rand.Read(keys[i][:]); err != nil {
			t.Fatal("cannot create isolated keys")
		}
	}
	config := EligibilityConfig{OTPKey: keys[0], OTPKeyVersion: 1, MailEncryptionKey: keys[1], MailEncryptionKeyVersion: 1, RequestHMACKey: keys[2], HMACKeyVersion: 1, LimitKey: keys[3], RegistrationEpoch: 1, SendBudget: 100, VerifyBudget: 100}
	e, err := NewEligibility(l.v, config, func(_ context.Context, _ uint32, message []byte) ([]byte, error) {
		return ed25519.Sign(l.vPrivate, message), nil
	}, capture, otpNoRetirePeer{})
	if err != nil {
		t.Fatal(err)
	}
	return l, e, capture
}
func otpFixtureRequest(t *testing.T, email string) OTPRequest {
	t.Helper()
	key, err := random32()
	if err != nil {
		t.Fatal("random key unavailable")
	}
	var install [16]byte
	if _, err = rand.Read(install[:]); err != nil {
		t.Fatal("random install unavailable")
	}
	return OTPRequest{Key: key, InstallationID: install, Email: email}
}
func expireOTPSendWaitForFixture(t *testing.T, e *Eligibility, email string) {
	t.Helper()
	_, err := e.store.pool.Exec(context.Background(), `UPDATE v_auth.otp_email_state SET send_wait_until=clock_timestamp()-interval '1 second' WHERE email_exact=$1`, []byte(email))
	if err != nil {
		t.Fatal(err)
	}
}
func otpVerifyForTest(t *testing.T, e *Eligibility, req ConfirmOTPRequest) (OTPVerification, error) {
	t.Helper()
	ctx := context.Background()
	email, err := e.lookupOTPFlowEmail(ctx, req.FlowID)
	if err != nil {
		return OTPVerification{}, err
	}
	tx, err := e.store.beginAuthorized(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if err = e.store.lockAddress(ctx, tx, email); err != nil {
		t.Fatal(err)
	}
	result, verificationErr := e.verifyOTPInTx(ctx, tx, req, time.Time{})
	if verificationErr != nil && !expectedOTPError(verificationErr) {
		t.Fatal("unexpected OTP store error", verificationErr)
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	return result, verificationErr
}
func wrongOTP(code string) string {
	if code != "000000" {
		return "000000"
	}
	return "000001"
}
func wrongForCodes(codes ...string) string {
	for i := 0; i <= len(codes); i++ {
		candidate := fmt.Sprintf("%06d", i)
		found := false
		for _, code := range codes {
			if candidate == code {
				found = true
			}
		}
		if !found {
			return candidate
		}
	}
	panic("unreachable finite OTP candidates")
}

func TestCampusEmailExactValidation(t *testing.T) {
	for _, email := range []string{"Student.A+tag@hainanu.edu.cn", "12345678@hainanu.edu.cn"} {
		if err := validateCampusEmail(email); err != nil {
			t.Fatal("valid exact address rejected")
		}
	}
	for _, email := range []string{" student@hainanu.edu.cn", "student@Hainanu.edu.cn", "student@sub.hainanu.edu.cn", "display <student@hainanu.edu.cn>", "student..a@hainanu.edu.cn", "student\n@hainanu.edu.cn", "student@hainanu.edu.cn ", "@hainanu.edu.cn"} {
		if !errors.Is(validateCampusEmail(email), ErrEmailInvalid) {
			t.Fatal("invalid address accepted")
		}
	}
}

func TestOTPRequestIdempotencyPrivacyAndCooldown(t *testing.T) {
	l, e, capture := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	req := otpFixtureRequest(t, "otpprivacy@hainanu.edu.cn")
	first, err := e.RequestOTP(ctx, req)
	if err != nil {
		t.Fatal(err)
	}
	if first.FlowID == ([32]byte{}) || first.RetryAfterSeconds != 60 {
		t.Fatal("missing original flow/cooldown")
	}
	second, err := e.RequestOTP(ctx, req)
	if err != nil {
		t.Fatal(err)
	}
	calls, code := capture.captured()
	if calls != 1 || code == "" || second.FlowID != first.FlowID || second.RetryAfterSeconds > first.RetryAfterSeconds {
		t.Fatal("same operation resent or restarted cooldown")
	}
	var cipherText, email []byte
	if err = l.vp.QueryRow(ctx, `SELECT ciphertext,email_exact FROM v_auth.mail_outbox`).Scan(&cipherText, &email); err != nil {
		t.Fatal(err)
	}
	if cipherText != nil || email != nil {
		t.Fatal("sent mail plaintext association was retained")
	}
	var stored []byte
	if err = l.vp.QueryRow(ctx, `SELECT code_hmac FROM v_auth.otp_code_versions`).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if len(stored) != 32 || bytes.Equal(stored, []byte(code)) {
		t.Fatal("invalid OTP stored representation")
	}
	changed := req
	changed.Email = "different@hainanu.edu.cn"
	if _, err = e.RequestOTP(ctx, changed); !errors.Is(err, ErrConflict) {
		t.Fatal("request key payload substitution accepted")
	}
	if _, err = e.RequestOTP(ctx, otpFixtureRequest(t, req.Email)); !errors.Is(err, ErrRateLimited) {
		t.Fatal("cooldown bypassed by new key")
	}
	wrongInstall := req.InstallationID
	wrongInstall[0] ^= 1
	if _, err = e.GetOTPRequestResult(ctx, req.Key, wrongInstall); !errors.Is(err, ErrResultAuthentication) {
		t.Fatal("result installation binding missing")
	}
	unknown, err := e.GetOTPRequestResult(ctx, [32]byte{1}, req.InstallationID)
	if err != nil || unknown.State != "PENDING" {
		t.Fatal("missing result falsely proved not sent")
	}
}

func TestOTPDeviceLockDoesNotExtendAndBlocksResend(t *testing.T) {
	_, e, capture := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	req := otpFixtureRequest(t, "otplock@hainanu.edu.cn")
	result, err := e.RequestOTP(ctx, req)
	if err != nil {
		t.Fatal(err)
	}
	_, code := capture.captured()
	confirm := ConfirmOTPRequest{FlowID: result.FlowID, InstallationID: req.InstallationID, OTP: wrongOTP(code)}
	for i := 0; i < 3; i++ {
		_, err = otpVerifyForTest(t, e, confirm)
		if i < 2 && !errors.Is(err, ErrOTPInvalid) {
			t.Fatal("wrong OTP failed to count")
		}
		if i == 2 && !errors.Is(err, ErrRateLimited) {
			t.Fatal("third wrong attempt did not lock")
		}
	}
	d := e.deviceEmailDigest([]byte(req.Email))
	var before, after time.Time
	if err = e.store.pool.QueryRow(ctx, `SELECT locked_until FROM v_auth.device_email_limits WHERE installation_id=$1 AND email_digest=$2`, req.InstallationID[:], d[:]).Scan(&before); err != nil {
		t.Fatal(err)
	}
	if _, err = otpVerifyForTest(t, e, confirm); !errors.Is(err, ErrRateLimited) {
		t.Fatal("locked request was accepted")
	}
	if err = e.store.pool.QueryRow(ctx, `SELECT locked_until FROM v_auth.device_email_limits WHERE installation_id=$1 AND email_digest=$2`, req.InstallationID[:], d[:]).Scan(&after); err != nil {
		t.Fatal(err)
	}
	if !before.Equal(after) {
		t.Fatal("retry extended device lock")
	}
	expireOTPSendWaitForFixture(t, e, req.Email)
	if _, err = e.RequestOTP(ctx, otpFixtureRequestWithInstall(t, req.Email, req.InstallationID)); !errors.Is(err, ErrRateLimited) {
		t.Fatal("locked device resent code")
	}
	var failed int
	if err = e.store.pool.QueryRow(ctx, `SELECT failed_attempts FROM v_auth.otp_flows WHERE flow_id=$1`, result.FlowID[:]).Scan(&failed); err != nil {
		t.Fatal(err)
	}
	if failed != 3 {
		t.Fatal("locked retry changed global error count")
	}
}
func otpFixtureRequestWithInstall(t *testing.T, email string, install [16]byte) OTPRequest {
	req := otpFixtureRequest(t, email)
	req.InstallationID = install
	return req
}

func TestOTPLatestGenerationAndConfirmedOldCodeExemption(t *testing.T) {
	_, e, capture := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	req := otpFixtureRequest(t, "otpold@hainanu.edu.cn")
	first, err := e.RequestOTP(ctx, req)
	if err != nil {
		t.Fatal(err)
	}
	_, oldCode := capture.captured()
	expireOTPSendWaitForFixture(t, e, req.Email)
	next := otpFixtureRequestWithInstall(t, req.Email, req.InstallationID)
	latest, err := e.RequestOTP(ctx, next)
	if err != nil {
		t.Fatal(err)
	}
	_, newCode := capture.captured()
	if oldCode == newCode {
		t.Fatal("new generation reused retained old code")
	}
	if _, err = otpVerifyForTest(t, e, ConfirmOTPRequest{FlowID: latest.FlowID, InstallationID: req.InstallationID, OTP: oldCode}); !errors.Is(err, ErrOTPReplaced) {
		t.Fatal("old code was not identified")
	}
	var attempts, device int
	d := e.deviceEmailDigest([]byte(req.Email))
	if err = e.store.pool.QueryRow(ctx, `SELECT failed_attempts FROM v_auth.otp_flows WHERE flow_id=$1`, latest.FlowID[:]).Scan(&attempts); err != nil {
		t.Fatal(err)
	}
	if err = e.store.pool.QueryRow(ctx, `SELECT consecutive_errors FROM v_auth.device_email_limits WHERE installation_id=$1 AND email_digest=$2`, req.InstallationID[:], d[:]).Scan(&device); err != nil {
		t.Fatal(err)
	}
	if attempts != 0 || device != 0 {
		t.Fatal("confirmed old code consumed wrong-attempt budget")
	}
	bad := wrongForCodes(oldCode, newCode)
	if _, err = otpVerifyForTest(t, e, ConfirmOTPRequest{FlowID: first.FlowID, InstallationID: req.InstallationID, OTP: bad}); !errors.Is(err, ErrOTPInvalid) {
		t.Fatal("arbitrary wrong code was mislabeled as old")
	}
	verified, err := otpVerifyForTest(t, e, ConfirmOTPRequest{FlowID: latest.FlowID, InstallationID: req.InstallationID, OTP: newCode})
	if err != nil || verified.Generation != 2 || verified.VerifiedAt.IsZero() {
		t.Fatal("latest correct code failed authoritative verification")
	}
	if _, err = otpVerifyForTest(t, e, ConfirmOTPRequest{FlowID: latest.FlowID, InstallationID: req.InstallationID, OTP: newCode}); !errors.Is(err, ErrOTPReplaced) {
		t.Fatal("consumed code was reusable outside original operation")
	}
}

func TestOTPGlobalTenWrongAcrossDevicesAndFlows(t *testing.T) {
	_, e, capture := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	email := "otpten@hainanu.edu.cn"
	var requests []OTPRequest
	var results []OTPRequestResult
	var codes []string
	for i := 0; i < 4; i++ {
		if i > 0 {
			expireOTPSendWaitForFixture(t, e, email)
		}
		req := otpFixtureRequest(t, email)
		result, err := e.RequestOTP(ctx, req)
		if err != nil {
			t.Fatal(err)
		}
		_, code := capture.captured()
		requests = append(requests, req)
		results = append(results, result)
		codes = append(codes, code)
	}
	bad := wrongForCodes(codes...)
	for i := 0; i < 4; i++ {
		count := 3
		if i == 3 {
			count = 1
		}
		for j := 0; j < count; j++ {
			_, err := otpVerifyForTest(t, e, ConfirmOTPRequest{FlowID: results[i].FlowID, InstallationID: requests[i].InstallationID, OTP: bad})
			if !errors.Is(err, ErrOTPInvalid) && !errors.Is(err, ErrRateLimited) {
				t.Fatal("wrong code did not produce expected rejection")
			}
		}
	}
	var count int
	var state string
	if err := e.store.pool.QueryRow(ctx, `SELECT failed_attempts,state FROM v_auth.otp_flows WHERE flow_id=$1`, results[3].FlowID[:]).Scan(&count, &state); err != nil {
		t.Fatal(err)
	}
	if count != 10 || state != "INVALIDATED" {
		t.Fatal("cross-device current code cap was bypassed")
	}
	if _, err := otpVerifyForTest(t, e, ConfirmOTPRequest{FlowID: results[3].FlowID, InstallationID: requests[3].InstallationID, OTP: codes[3]}); !errors.Is(err, ErrOTPReplaced) {
		t.Fatal("invalidated current code was accepted")
	}
}

func TestOTPAmbiguousMailFreezesWithoutDuplicate(t *testing.T) {
	_, e, capture := newOTPTestEligibility(t, MailUnknown)
	ctx := context.Background()
	req := otpFixtureRequest(t, "otpunknown@hainanu.edu.cn")
	first, err := e.RequestOTP(ctx, req)
	if err != nil {
		t.Fatal(err)
	}
	query, err := e.GetOTPRequestResult(ctx, req.Key, req.InstallationID)
	if err != nil || query.State != "PENDING" {
		t.Fatal("ambiguous delivery claimed known outcome")
	}
	again, err := e.RequestOTP(ctx, req)
	if err != nil || again.FlowID != first.FlowID {
		t.Fatal("same ambiguous operation lost original flow")
	}
	calls, _ := capture.captured()
	if calls != 1 {
		t.Fatal("ambiguous SMTP attempt was automatically repeated")
	}
	expireOTPSendWaitForFixture(t, e, req.Email)
	if _, err = e.RequestOTP(ctx, otpFixtureRequest(t, req.Email)); !errors.Is(err, ErrRateLimited) {
		t.Fatal("new key bypassed unresolved SMTP send")
	}
	var payload, address []byte
	if err = e.store.pool.QueryRow(ctx, `SELECT ciphertext,email_exact FROM v_auth.mail_outbox`).Scan(&payload, &address); err != nil {
		t.Fatal(err)
	}
	if payload != nil || address != nil {
		t.Fatal("unknown send retained encrypted OTP unnecessarily")
	}
}

func TestOTPMailEncryptedBeforeCommitAndErasedAfterSending(t *testing.T) {
	_, e, capture := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	req := otpFixtureRequest(t, "otpsealed@hainanu.edu.cn")
	result, err := e.queueOTP(ctx, req)
	if err != nil {
		t.Fatal(err)
	}
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", req.Key[:])
	tx, err := e.store.beginAuthorized(ctx)
	if err != nil {
		t.Fatal(err)
	}
	row, err := readOTPMail(ctx, tx, key, false)
	_ = tx.Rollback(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(row.encrypted) != 22 || len(row.nonce) != 12 || row.keyVersion == nil || *row.keyVersion != 1 {
		t.Fatal("mail payload was not sealed")
	}
	aead, err := e.mailAEAD()
	if err != nil {
		t.Fatal(err)
	}
	raw, err := aead.Open(nil, row.nonce, row.encrypted, mailAAD(row.operation, result.FlowID, []byte(req.Email)))
	if err != nil || !validOTPShape(string(raw)) {
		t.Fatal("valid encrypted payload cannot be opened")
	}
	wrongAddress := []byte("other@hainanu.edu.cn")
	if _, err = aead.Open(nil, row.nonce, row.encrypted, mailAAD(row.operation, result.FlowID, wrongAddress)); err == nil {
		t.Fatal("encrypted mail lost recipient binding")
	}
	if outcome, err := e.DispatchMail(ctx, req.Key); err != nil || outcome != MailSent {
		t.Fatal("queued dispatch failed")
	}
	calls, code := capture.captured()
	if calls != 1 || code != string(raw) {
		t.Fatal("dispatch failed to use original sealed code")
	}
}

func TestOTPCleanupPreservesGenerationAndExpiredAnchor(t *testing.T) {
	_, e, capture := newOTPTestEligibility(t, MailSent)
	ctx := context.Background()
	req := otpFixtureRequest(t, "otpcleanup@hainanu.edu.cn")
	flow, _ := random32()
	job, _ := random32()
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", req.Key[:])
	mac := requestMAC(e.config.RequestHMACKey, []byte("HNUHOLE/V-OTP-REQUEST/V1"), []byte(req.Email), req.InstallationID[:])
	tx, err := e.store.beginAuthorized(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	var old time.Time
	if err = tx.QueryRow(ctx, `SELECT clock_timestamp()-interval '11 minutes'`).Scan(&old); err != nil {
		t.Fatal(err)
	}
	steps := []struct {
		sql  string
		args []any
	}{
		{`INSERT INTO v_auth.otp_email_state(email_exact,code_generation,latest_flow_id,send_wait_until) VALUES($1,1,$2,$3)`, []any{[]byte(req.Email), flow[:], old.Add(time.Minute)}},
		{`INSERT INTO v_auth.otp_flows(flow_id,email_exact,installation_id,code_generation,state,created_at,expires_at) VALUES($1,$2,$3,1,'ACTIVE',$4,$4::timestamptz+interval '5 minutes')`, []any{flow[:], []byte(req.Email), req.InstallationID[:], old}},
		{`INSERT INTO v_auth.otp_code_versions(email_exact,code_generation,flow_id,code_hmac,otp_key_version,state,expires_at,retain_until) VALUES($1,1,$2,$3,1,'ACTIVE',$4::timestamptz+interval '5 minutes',$4::timestamptz+interval '10 minutes')`, []any{[]byte(req.Email), flow[:], make([]byte, 32), old}},
		{`INSERT INTO v_auth.request_results(operation,key_digest,state,request_hmac,hmac_key_version,installation_id,flow_id,result_code,expires_at) VALUES('OTP_REQUEST',$1,'LIVE',$2,1,$3,$4,'ACCEPTED',$5::timestamptz+interval '10 minutes')`, []any{key[:], mac[:], req.InstallationID[:], flow[:], old}},
		{`INSERT INTO v_auth.mail_outbox(operation_id,key_digest,flow_id,state,email_exact,ciphertext,nonce,encryption_key_version,expires_at,send_wait_until,previous_send_wait_until) VALUES($1,$2,$3,'QUEUED',$4,$5,$6,1,$7::timestamptz+interval '5 minutes',$7::timestamptz+interval '1 minute',$7)`, []any{job[:], key[:], flow[:], []byte(req.Email), make([]byte, 22), make([]byte, 12), old}},
	}
	for _, step := range steps {
		if _, err = tx.Exec(ctx, step.sql, step.args...); err != nil {
			t.Fatal(err)
		}
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err = e.CleanupOTP(ctx, 10); err != nil {
		t.Fatal(err)
	}
	calls, _ := capture.captured()
	if calls != 0 {
		t.Fatal("cleanup sent expired mail")
	}
	for _, table := range []string{"otp_code_versions", "otp_flows", "mail_outbox"} {
		var count int
		if err = e.store.pool.QueryRow(ctx, `SELECT count(*) FROM v_auth.`+table).Scan(&count); err != nil || count != 0 {
			t.Fatal("cleanup retained expired association")
		}
	}
	var generation int64
	var latest []byte
	if err = e.store.pool.QueryRow(ctx, `SELECT code_generation,latest_flow_id FROM v_auth.otp_email_state WHERE email_exact=$1`, []byte(req.Email)).Scan(&generation, &latest); err != nil {
		t.Fatal(err)
	}
	if generation != 1 || latest != nil {
		t.Fatal("cleanup reset generation or retained flow")
	}
	if _, err = e.GetOTPRequestResult(ctx, req.Key, [16]byte{1}); !errors.Is(err, ErrExpired) {
		t.Fatal("expired anchor required deleted installation binding")
	}
	if _, err = e.RequestOTP(ctx, req); !errors.Is(err, ErrExpired) {
		t.Fatal("old original key replayed after cleanup")
	}
	if _, err = e.RequestOTP(ctx, otpFixtureRequest(t, req.Email)); err != nil {
		t.Fatal(err)
	}
	if err = e.store.pool.QueryRow(ctx, `SELECT code_generation FROM v_auth.otp_email_state WHERE email_exact=$1`, []byte(req.Email)).Scan(&generation); err != nil || generation != 2 {
		t.Fatal("new flow did not preserve generation")
	}
}

func TestOTPCleanupTwentyFourHourMetadata(t *testing.T) {
	l, e, capture := newOTPTestEligibility(t, MailUnknown)
	ctx := context.Background()
	pendingRequest := otpFixtureRequest(t, "pendingmetadata@hainanu.edu.cn")
	pendingFlow, err := e.RequestOTP(ctx, pendingRequest)
	if err != nil {
		t.Fatal(err)
	}
	_, pendingCode := capture.captured()
	quotaEmail := "quotametadata@hainanu.edu.cn"
	oldTicket, _ := l.ticket(t)
	newTicket, _ := l.ticket(t)
	if _, err = l.v.ReserveAfterQualification(ctx, []byte(quotaEmail), oldTicket.BootstrapKey); err != nil {
		t.Fatal(err)
	}
	if err = l.v.PrepareRetirement(ctx, []byte(quotaEmail), newTicket.BootstrapKey, l.authorization(oldTicket.Slot)); err != nil {
		t.Fatal(err)
	}
	var old, now time.Time
	if err = e.store.pool.QueryRow(ctx, `SELECT clock_timestamp()-interval '25 hours',clock_timestamp()`).Scan(&old, &now); err != nil {
		t.Fatal(err)
	}
	for _, address := range []string{"empty-one@hainanu.edu.cn", "empty-two@hainanu.edu.cn", quotaEmail, "confirmationmetadata@hainanu.edu.cn", "budgetmetadata@hainanu.edu.cn"} {
		if _, err = e.store.pool.Exec(ctx, `INSERT INTO v_auth.otp_email_state(email_exact,code_generation,send_wait_until,last_activity_at) VALUES($1,7,$2,$2)`, []byte(address), old); err != nil {
			t.Fatal(err)
		}
	}
	if _, err = e.store.pool.Exec(ctx, `UPDATE v_auth.otp_email_state SET last_activity_at=$2 WHERE email_exact=$1`, []byte(pendingRequest.Email), old); err != nil {
		t.Fatal(err)
	}
	if _, err = e.store.pool.Exec(ctx, `INSERT INTO v_auth.otp_budget_events(email_exact,kind,occurred_at) VALUES($1,'SEND',clock_timestamp())`, []byte("budgetmetadata@hainanu.edu.cn")); err != nil {
		t.Fatal(err)
	}
	confirmationKey, _ := random32()
	if _, err = e.store.pool.Exec(ctx, `INSERT INTO v_auth.request_results(operation,key_digest,state) VALUES('OTP_CONFIRMATION',$1,'EXPIRED')`, confirmationKey[:]); err != nil {
		t.Fatal(err)
	}
	if _, err = e.store.pool.Exec(ctx, `INSERT INTO v_auth.otp_confirmations(confirmation_key_digest,email_exact,new_slot,new_bootstrap_public_key,verified_at,verified_otp_expires_at,admission_window,signing_key_epoch,state) VALUES($1,$2,$3,$4,$5,$5::timestamptz+interval '5 minutes',0,1,'ELIGIBILITY_RESERVED')`, confirmationKey[:], []byte("confirmationmetadata@hainanu.edu.cn"), newTicket.Slot[:], newTicket.BootstrapKey[:], old); err != nil {
		t.Fatal(err)
	}
	digest := e.deviceEmailDigest([]byte("devicemetadata@hainanu.edu.cn"))
	for _, device := range []struct {
		id     byte
		at     time.Time
		errors int
		lock   *time.Time
	}{{1, old, 0, nil}, {2, old, 3, &old}, {3, old, 3, timePointer(now.Add(5 * time.Minute))}, {4, now, 0, nil}} {
		installation := [16]byte{device.id}
		if _, err = e.store.pool.Exec(ctx, `INSERT INTO v_auth.device_email_limits(installation_id,email_digest,consecutive_errors,locked_until,last_activity_at) VALUES($1,$2,$3,$4,$5)`, installation[:], digest[:], device.errors, device.lock, device.at); err != nil {
			t.Fatal(err)
		}
	}
	if err = e.CleanupOTP(ctx, 1); err != nil {
		t.Fatal(err)
	}
	var count int
	if err = e.store.pool.QueryRow(ctx, `SELECT count(*) FROM v_auth.otp_email_state WHERE email_exact IN($1,$2)`, []byte("empty-one@hainanu.edu.cn"), []byte("empty-two@hainanu.edu.cn")).Scan(&count); err != nil || count != 1 {
		t.Fatal("address cleanup did not obey its batch limit")
	}
	if err = e.store.pool.QueryRow(ctx, `SELECT count(*) FROM v_auth.device_email_limits WHERE email_digest=$1 AND installation_id IN($2,$3)`, digest[:], []byte{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, []byte{2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}).Scan(&count); err != nil || count != 1 {
		t.Fatal("device cleanup did not obey its batch limit")
	}
	if err = e.CleanupOTP(ctx, 10); err != nil {
		t.Fatal(err)
	}
	if err = e.store.pool.QueryRow(ctx, `SELECT count(*) FROM v_auth.device_email_limits WHERE email_digest=$1`, digest[:]).Scan(&count); err != nil || count != 2 {
		t.Fatal("cleanup removed a fresh device or active lock, or retained expired metadata")
	}
	for _, address := range []string{quotaEmail, pendingRequest.Email, "confirmationmetadata@hainanu.edu.cn", "budgetmetadata@hainanu.edu.cn"} {
		var generation int64
		if err = e.store.pool.QueryRow(ctx, `SELECT code_generation FROM v_auth.otp_email_state WHERE email_exact=$1`, []byte(address)).Scan(&generation); err != nil {
			t.Fatal("cleanup removed referenced address state", err)
		}
		if (address == pendingRequest.Email && generation != 1) || (address != pendingRequest.Email && generation != 7) {
			t.Fatal("cleanup changed a retained generation")
		}
	}
	if _, err = e.RequestOTP(ctx, otpFixtureRequest(t, "empty-one@hainanu.edu.cn")); err != nil {
		t.Fatal("completely drained address could not begin a fresh generation", err)
	}
	var generation int64
	if err = e.store.pool.QueryRow(ctx, `SELECT code_generation FROM v_auth.otp_email_state WHERE email_exact=$1`, []byte("empty-one@hainanu.edu.cn")).Scan(&generation); err != nil || generation != 1 {
		t.Fatal("drained address generation did not restart safely")
	}
	deviceDigest := e.deviceEmailDigest([]byte(pendingRequest.Email))
	if _, err = e.store.pool.Exec(ctx, `UPDATE v_auth.device_email_limits SET last_activity_at=$3 WHERE installation_id=$1 AND email_digest=$2`, pendingRequest.InstallationID[:], deviceDigest[:], old); err != nil {
		t.Fatal(err)
	}
	if _, err = otpVerifyForTest(t, e, ConfirmOTPRequest{FlowID: pendingFlow.FlowID, InstallationID: pendingRequest.InstallationID, OTP: pendingCode}); err != nil {
		t.Fatal(err)
	}
	var active bool
	if err = e.store.pool.QueryRow(ctx, `SELECT s.last_activity_at>clock_timestamp()-interval '1 minute' AND d.last_activity_at>clock_timestamp()-interval '1 minute' FROM v_auth.otp_email_state s JOIN v_auth.device_email_limits d ON d.installation_id=$2 AND d.email_digest=$3 WHERE s.email_exact=$1`, []byte(pendingRequest.Email), pendingRequest.InstallationID[:], deviceDigest[:]).Scan(&active); err != nil || !active {
		t.Fatal("successful verification did not refresh database activity time")
	}
}

func timePointer(value time.Time) *time.Time { return &value }
