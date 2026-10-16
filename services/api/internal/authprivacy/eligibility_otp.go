package authprivacy

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"math/big"
	"net/mail"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
)

const otpRequestOperation = "OTP_REQUEST"

// validateCampusEmail never canonicalizes an address. ParseAddress is an
// additional syntax check, not an excuse to accept display names or trim bytes.
func validateCampusEmail(email string) error {
	if len(email) < 16 || len(email) > 254 || !utf8.ValidString(email) ||
		strings.Count(email, "@") != 1 || !strings.HasSuffix(email, "@hainanu.edu.cn") ||
		strings.IndexFunc(email, func(r rune) bool { return unicode.IsSpace(r) || unicode.IsControl(r) }) >= 0 {
		return ErrEmailInvalid
	}
	parsed, err := mail.ParseAddress(email)
	if err != nil || parsed.Name != "" || parsed.Address != email {
		return ErrEmailInvalid
	}
	return nil
}

func remainingSeconds(until, at time.Time) int {
	if !at.Before(until) {
		return 0
	}
	return int(math.Ceil(until.Sub(at).Seconds()))
}

func otpDigest(key [32]byte, email []byte, generation int64, flow [32]byte, code string) [32]byte {
	var version [8]byte
	binary.BigEndian.PutUint64(version[:], uint64(generation))
	return requestMAC(key, []byte("HNUHOLE/V-OTP-CODE/V1"), email, version[:], flow[:], []byte(code))
}

func (e *Eligibility) deviceEmailDigest(email []byte) [32]byte {
	return requestMAC(e.config.LimitKey, []byte("HNUHOLE/V-DEVICE-EMAIL-LIMIT/V1"), email)
}

func (e *Eligibility) mailAEAD() (cipher.AEAD, error) {
	block, err := aes.NewCipher(e.config.MailEncryptionKey[:])
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

func mailAAD(operation, flow [32]byte, email []byte) []byte {
	value := append([]byte("HNUHOLE/V-MAIL-OTP/V1\x00"), operation[:]...)
	value = append(value, flow[:]...)
	return append(value, email...)
}

func (e *Eligibility) lookupOTPFlowEmail(ctx context.Context, flow [32]byte) ([]byte, error) {
	var email []byte
	err := e.store.pool.QueryRow(ctx, `SELECT email_exact FROM v_auth.otp_flows WHERE flow_id=$1`, flow[:]).Scan(&email)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrOTPFlowInvalid
	}
	return email, err
}

func (e *Eligibility) lockOTPDevice(ctx context.Context, tx pgx.Tx, installation [16]byte, email []byte, at time.Time) (int, *time.Time, error) {
	d := e.deviceEmailDigest(email)
	_, err := tx.Exec(ctx, `INSERT INTO v_auth.device_email_limits(installation_id,email_digest,last_activity_at) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`, installation[:], d[:], at)
	if err != nil {
		return 0, nil, err
	}
	var consecutive int
	var locked *time.Time
	err = tx.QueryRow(ctx, `SELECT consecutive_errors,locked_until FROM v_auth.device_email_limits WHERE installation_id=$1 AND email_digest=$2 FOR UPDATE`, installation[:], d[:]).Scan(&consecutive, &locked)
	if err != nil {
		return 0, nil, err
	}
	if _, err = tx.Exec(ctx, `UPDATE v_auth.device_email_limits SET last_activity_at={trusted_at} WHERE installation_id=$1 AND email_digest=$2`, installation[:], d[:]); err != nil {
		return 0, nil, err
	}
	if locked != nil && !at.Before(*locked) {
		_, err = tx.Exec(ctx, `UPDATE v_auth.device_email_limits SET consecutive_errors=0,locked_until=NULL WHERE installation_id=$1 AND email_digest=$2`, installation[:], d[:])
		return 0, nil, err
	}
	return consecutive, locked, nil
}

func (e *Eligibility) consumeOTPBudget(ctx context.Context, tx pgx.Tx, email []byte, kind string, at time.Time) error {
	window, limit := time.Hour, e.config.SendBudget
	if kind == "VERIFY" {
		window, limit = 10*time.Minute, e.config.VerifyBudget
	}
	_, err := tx.Exec(ctx, `DELETE FROM v_auth.otp_budget_events WHERE email_exact=$1 AND kind=$2 AND occurred_at <= $3`, email, kind, at.Add(-window))
	if err != nil {
		return err
	}
	var count int
	var first *time.Time
	if err = tx.QueryRow(ctx, `SELECT count(*),min(occurred_at) FROM v_auth.otp_budget_events WHERE email_exact=$1 AND kind=$2`, email, kind).Scan(&count, &first); err != nil {
		return err
	}
	if count >= limit {
		retry := 1
		if first != nil {
			retry = remainingSeconds(first.Add(window), at)
		}
		return eligibilityError("RATE_LIMITED", max(1, retry))
	}
	_, err = tx.Exec(ctx, `INSERT INTO v_auth.otp_budget_events(email_exact,kind,occurred_at) VALUES($1,$2,$3)`, email, kind, at)
	return err
}

type otpMailRow struct {
	operation, flow             [32]byte
	state                       string
	email, encrypted, nonce     []byte
	keyVersion                  *int64
	expires, wait, previousWait time.Time
	authorizationGeneration     uint64
}

func readOTPMail(ctx context.Context, tx pgx.Tx, key [32]byte, lock bool) (otpMailRow, error) {
	var row otpMailRow
	var operation, flow []byte
	sql := `SELECT operation_id,flow_id,state,email_exact,ciphertext,nonce,encryption_key_version,expires_at,send_wait_until,previous_send_wait_until,authorization_generation FROM v_auth.mail_outbox WHERE key_digest=$1`
	if lock {
		sql += ` FOR UPDATE`
	}
	err := tx.QueryRow(ctx, sql, key[:]).Scan(&operation, &flow, &row.state, &row.email, &row.encrypted, &row.nonce, &row.keyVersion, &row.expires, &row.wait, &row.previousWait, &row.authorizationGeneration)
	if err == nil {
		copy(row.operation[:], operation)
		copy(row.flow[:], flow)
	}
	return row, err
}

func otpRequestResult(row otpMailRow, at time.Time) OTPRequestResult {
	result := OTPRequestResult{State: "ACCEPTED", FlowID: row.flow, RetryAfterSeconds: min(60, remainingSeconds(row.wait, at))}
	if row.state == "NOT_SENT" {
		result.State = "NOT_SENT"
		result.FlowID = [32]byte{}
		result.RetryAfterSeconds = min(60, remainingSeconds(row.previousWait, at))
	} else if row.state == "DISPATCHING" || row.state == "UNKNOWN" {
		result.State = "PENDING"
		result.FlowID = [32]byte{}
		result.RetryAfterSeconds = 5
		result.PollAfterSeconds = 5
	}
	return result
}

func (e *Eligibility) RequestOTP(ctx context.Context, req OTPRequest) (OTPRequestResult, error) {
	if req.Key == ([32]byte{}) || req.InstallationID == ([16]byte{}) {
		return OTPRequestResult{}, ErrBadRequest
	}
	result, err := e.queueOTP(ctx, req)
	if err != nil {
		return result, err
	}
	// A bounded SMTP attempt happens only after the operation is durable. A
	// same-key retry may drive QUEUED, never DISPATCHING or UNKNOWN.
	sendCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	_, _ = e.DispatchMail(sendCtx, req.Key)
	known, readErr := e.GetOTPRequestResult(ctx, req.Key, req.InstallationID)
	if readErr != nil {
		return OTPRequestResult{}, readErr
	}
	// POST's 202 means durable acceptance and requires its original flow ID;
	// delivery uncertainty is reported by the separate result query.
	result.State = "ACCEPTED"
	if known.State == "NOT_SENT" {
		result.RetryAfterSeconds = known.RetryAfterSeconds
	}
	return result, nil
}

func (e *Eligibility) queueOTP(ctx context.Context, req OTPRequest) (OTPRequestResult, error) {
	if err := validateCampusEmail(req.Email); err != nil {
		return OTPRequestResult{}, err
	}
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", req.Key[:])
	mac := requestMAC(e.config.RequestHMACKey, []byte("HNUHOLE/V-OTP-REQUEST/V1"), []byte(req.Email), req.InstallationID[:])
	tx, err := e.store.beginAuthorized(ctx)
	if err != nil {
		return OTPRequestResult{}, err
	}
	defer tx.Rollback(ctx)
	if err = e.store.lockAddress(ctx, tx, []byte(req.Email)); err != nil {
		return OTPRequestResult{}, err
	}
	if err = lockVRequest(ctx, tx, key); err != nil {
		return OTPRequestResult{}, err
	}
	var operation, state string
	var storedMAC, installation []byte
	var hmacVersion *int64
	var expires *time.Time
	err = tx.QueryRow(ctx, `SELECT operation,state,request_hmac,hmac_key_version,installation_id,expires_at FROM v_auth.request_results WHERE key_digest=$1 FOR UPDATE`, key[:]).Scan(&operation, &state, &storedMAC, &hmacVersion, &installation, &expires)
	if err == nil {
		if state == "EXPIRED" {
			return OTPRequestResult{}, ErrExpired
		}
		if operation != otpRequestOperation || !bytes.Equal(installation, req.InstallationID[:]) {
			return OTPRequestResult{}, ErrConflict
		}
		if hmacVersion == nil || *hmacVersion != e.config.HMACKeyVersion {
			return OTPRequestResult{}, errors.New("request HMAC key unavailable")
		}
		if !hmac.Equal(storedMAC, mac[:]) {
			return OTPRequestResult{}, ErrConflict
		}
		row, readErr := readOTPMail(ctx, tx, key, true)
		if readErr != nil {
			return OTPRequestResult{}, readErr
		}
		var at time.Time
		if err = verifierTrustedAt(ctx, tx, &at); err != nil {
			return OTPRequestResult{}, err
		}
		if expires != nil && !at.Before(*expires) && row.state != "DISPATCHING" && row.state != "QUEUED" {
			if err = expireOTPRequestResult(ctx, tx, key); err != nil {
				return OTPRequestResult{}, err
			}
			if err = tx.Commit(ctx); err != nil {
				return OTPRequestResult{}, err
			}
			return OTPRequestResult{}, ErrExpired
		}
		if row.authorizationGeneration == 0 || row.authorizationGeneration != verifierGeneration(tx) {
			return OTPRequestResult{}, ErrExpired
		}
		result := OTPRequestResult{State: "ACCEPTED", FlowID: row.flow, RetryAfterSeconds: min(60, remainingSeconds(row.wait, at))}
		if row.state == "NOT_SENT" {
			result.RetryAfterSeconds = min(60, remainingSeconds(row.previousWait, at))
		}
		if err = tx.Commit(ctx); err != nil {
			return OTPRequestResult{}, err
		}
		return result, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return OTPRequestResult{}, err
	}
	var at time.Time
	if err = verifierTrustedAt(ctx, tx, &at); err != nil {
		return OTPRequestResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.otp_email_state(email_exact,send_wait_until,last_activity_at) VALUES($1,$2,$2) ON CONFLICT DO NOTHING`, []byte(req.Email), at); err != nil {
		return OTPRequestResult{}, err
	}
	var generation int64
	var latest []byte
	var previousWait time.Time
	if err = tx.QueryRow(ctx, `SELECT code_generation,latest_flow_id,send_wait_until FROM v_auth.otp_email_state WHERE email_exact=$1 FOR UPDATE`, []byte(req.Email)).Scan(&generation, &latest, &previousWait); err != nil {
		return OTPRequestResult{}, err
	}
	_, locked, err := e.lockOTPDevice(ctx, tx, req.InstallationID, []byte(req.Email), at)
	if err != nil {
		return OTPRequestResult{}, err
	}
	// Sample again after the device and email rows have actually been locked.
	if err = verifierTrustedAt(ctx, tx, &at); err != nil {
		return OTPRequestResult{}, err
	}
	_, locked, err = e.lockOTPDevice(ctx, tx, req.InstallationID, []byte(req.Email), at)
	if err != nil {
		return OTPRequestResult{}, err
	}
	if locked != nil && at.Before(*locked) {
		return OTPRequestResult{}, eligibilityError("RATE_LIMITED", remainingSeconds(*locked, at))
	}
	if at.Before(previousWait) {
		return OTPRequestResult{}, eligibilityError("RATE_LIMITED", remainingSeconds(previousWait, at))
	}
	var pending bool
	if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.mail_outbox m JOIN v_auth.otp_flows f USING(flow_id) WHERE f.email_exact=$1 AND m.state IN ('QUEUED','DISPATCHING','UNKNOWN'))`, []byte(req.Email)).Scan(&pending); err != nil {
		return OTPRequestResult{}, err
	}
	if pending {
		return OTPRequestResult{}, eligibilityError("RATE_LIMITED", 5)
	}
	if err = e.consumeOTPBudget(ctx, tx, []byte(req.Email), "SEND", at); err != nil {
		return OTPRequestResult{}, err
	}
	if generation == math.MaxInt64 {
		return OTPRequestResult{}, errors.New("OTP generation exhausted")
	}
	flow, err := random32()
	if err != nil {
		return OTPRequestResult{}, err
	}
	job, err := random32()
	if err != nil {
		return OTPRequestResult{}, err
	}
	code, err := e.generateOTP(ctx, tx, []byte(req.Email), at)
	if err != nil {
		return OTPRequestResult{}, err
	}
	generation++
	expiresAt := at.Add(5 * time.Minute)
	wait := at.Add(time.Minute)
	codeMAC := otpDigest(e.config.OTPKey, []byte(req.Email), generation, flow, code)
	aead, err := e.mailAEAD()
	if err != nil {
		return OTPRequestResult{}, err
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return OTPRequestResult{}, err
	}
	encrypted := aead.Seal(nil, nonce, []byte(code), mailAAD(job, flow, []byte(req.Email)))
	if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_flows SET state='REPLACED' WHERE email_exact=$1 AND state='ACTIVE'`, []byte(req.Email)); err != nil {
		return OTPRequestResult{}, err
	}
	if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_code_versions SET state='REPLACED' WHERE email_exact=$1 AND state='ACTIVE'`, []byte(req.Email)); err != nil {
		return OTPRequestResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.otp_flows(flow_id,email_exact,installation_id,code_generation,state,created_at,expires_at,authorization_generation) VALUES($1,$2,$3,$4,'ACTIVE',$5,$6,$7)`, flow[:], []byte(req.Email), req.InstallationID[:], generation, at, expiresAt, int64(verifierGeneration(tx))); err != nil {
		return OTPRequestResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.otp_code_versions(email_exact,code_generation,flow_id,code_hmac,otp_key_version,state,expires_at,retain_until) VALUES($1,$2,$3,$4,$5,'ACTIVE',$6::timestamptz,$6::timestamptz+interval '5 minutes')`, []byte(req.Email), generation, flow[:], codeMAC[:], e.config.OTPKeyVersion, expiresAt); err != nil {
		return OTPRequestResult{}, err
	}
	if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_email_state SET code_generation=$1,latest_flow_id=$2,send_wait_until=$3,last_activity_at={trusted_at} WHERE email_exact=$4`, generation, flow[:], wait, []byte(req.Email)); err != nil {
		return OTPRequestResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.request_results(operation,key_digest,state,request_hmac,hmac_key_version,installation_id,flow_id,result_code,expires_at) VALUES($1,$2,'LIVE',$3,$4,$5,$6,'ACCEPTED',$7::timestamptz+interval '10 minutes')`, otpRequestOperation, key[:], mac[:], e.config.HMACKeyVersion, req.InstallationID[:], flow[:], at); err != nil {
		return OTPRequestResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.mail_outbox(operation_id,key_digest,flow_id,state,email_exact,ciphertext,nonce,encryption_key_version,expires_at,send_wait_until,previous_send_wait_until,authorization_generation) VALUES($1,$2,$3,'QUEUED',$4,$5,$6,$7,$8,$9,$10,$11)`, job[:], key[:], flow[:], []byte(req.Email), encrypted, nonce, e.config.MailEncryptionKeyVersion, expiresAt, wait, previousWait, int64(verifierGeneration(tx))); err != nil {
		return OTPRequestResult{}, err
	}
	if err = verifierFinalCheck(tx, func(d AuthorizationDecision) error {
		if !d.TrustedAt.Before(expiresAt) {
			return ErrOTPExpired
		}
		return nil
	}); err != nil {
		return OTPRequestResult{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return OTPRequestResult{}, err
	}
	return OTPRequestResult{State: "ACCEPTED", FlowID: flow, RetryAfterSeconds: 60}, nil
}

func (e *Eligibility) generateOTP(ctx context.Context, tx pgx.Tx, email []byte, at time.Time) (string, error) {
	if _, err := tx.Exec(ctx, `DELETE FROM v_auth.otp_code_versions WHERE email_exact=$1 AND retain_until <= $2`, email, at); err != nil {
		return "", err
	}
	rows, err := tx.Query(ctx, `SELECT flow_id,code_generation,code_hmac,otp_key_version FROM v_auth.otp_code_versions WHERE email_exact=$1`, email)
	if err != nil {
		return "", err
	}
	type previousCode struct {
		flow       [32]byte
		generation int64
		hmac       []byte
		version    int64
	}
	var prior []previousCode
	for rows.Next() {
		var p previousCode
		var flow []byte
		if err = rows.Scan(&flow, &p.generation, &p.hmac, &p.version); err != nil {
			rows.Close()
			return "", err
		}
		copy(p.flow[:], flow)
		prior = append(prior, p)
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return "", err
	}
	for attempt := 0; attempt < 20; attempt++ {
		n, err := rand.Int(rand.Reader, big.NewInt(1000000))
		if err != nil {
			return "", err
		}
		code := fmt.Sprintf("%06d", n.Int64())
		duplicate := false
		for _, old := range prior {
			if old.version != e.config.OTPKeyVersion {
				return "", errors.New("OTP retained key unavailable")
			}
			mac := otpDigest(e.config.OTPKey, email, old.generation, old.flow, code)
			if hmac.Equal(mac[:], old.hmac) {
				duplicate = true
				break
			}
		}
		if !duplicate {
			return code, nil
		}
	}
	return "", errors.New("OTP generation collision budget exhausted")
}

func expireOTPRequestResult(ctx context.Context, tx pgx.Tx, key [32]byte) error {
	if _, err := tx.Exec(ctx, `DELETE FROM v_auth.mail_outbox WHERE key_digest=$1 AND state IN ('SENT','NOT_SENT','UNKNOWN')`, key[:]); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `UPDATE v_auth.request_results SET state='EXPIRED',request_hmac=NULL,hmac_key_version=NULL,installation_id=NULL,flow_id=NULL,result_code=NULL,expires_at=NULL WHERE key_digest=$1`, key[:])
	return err
}

func (e *Eligibility) GetOTPRequestResult(ctx context.Context, keyBytes [32]byte, installation [16]byte) (result OTPRequestResult, resultErr error) {
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", keyBytes[:])
	tx, err := e.store.beginAuthorized(ctx)
	if err != nil {
		return OTPRequestResult{}, err
	}
	defer tx.Rollback(ctx)
	defer func() {
		if resultErr == nil {
			if err := tx.Commit(ctx); err != nil {
				result = OTPRequestResult{}
				resultErr = err
			}
		}
	}()
	if err = lockVRequest(ctx, tx, key); err != nil {
		return OTPRequestResult{}, err
	}
	var op, state string
	var storedInstallation []byte
	var expires *time.Time
	err = tx.QueryRow(ctx, `SELECT operation,state,installation_id,expires_at FROM v_auth.request_results WHERE key_digest=$1 FOR UPDATE`, key[:]).Scan(&op, &state, &storedInstallation, &expires)
	if errors.Is(err, pgx.ErrNoRows) {
		return OTPRequestResult{State: "PENDING", RetryAfterSeconds: 5, PollAfterSeconds: 5}, nil
	}
	if err != nil {
		return OTPRequestResult{}, err
	}
	if state == "EXPIRED" {
		return OTPRequestResult{}, ErrExpired
	}
	if op != otpRequestOperation || !hmac.Equal(storedInstallation, installation[:]) {
		return OTPRequestResult{}, ErrResultAuthentication
	}
	row, err := readOTPMail(ctx, tx, key, true)
	if err != nil {
		return OTPRequestResult{}, err
	}
	var at time.Time
	if err = verifierTrustedAt(ctx, tx, &at); err != nil {
		return OTPRequestResult{}, err
	}
	if expires != nil && !at.Before(*expires) && row.state != "QUEUED" && row.state != "DISPATCHING" {
		return OTPRequestResult{}, ErrExpired
	}
	if expires != nil && row.state != "QUEUED" && row.state != "DISPATCHING" {
		if err = verifierFinalCheck(tx, func(d AuthorizationDecision) error {
			if !d.TrustedAt.Before(*expires) {
				return ErrExpired
			}
			return nil
		}); err != nil {
			return OTPRequestResult{}, err
		}
	}
	result = otpRequestResult(row, at)
	if row.authorizationGeneration != verifierGeneration(tx) {
		if row.state == "QUEUED" {
			result.FlowID = [32]byte{}
			result.State = "NOT_SENT"
			result.RetryAfterSeconds = 0
		}
	}
	return result, nil
}

// verifyOTPInTx must be composed with quota reservation/confirmation in the
// caller's transaction. Public errors may have durable counters: commit them.
func (e *Eligibility) verifyOTPInTx(ctx context.Context, tx pgx.Tx, req ConfirmOTPRequest, _ time.Time) (OTPVerification, error) {
	var result OTPVerification
	var email, originalInstall []byte
	var originalGeneration int64
	var authorizationGeneration uint64
	err := tx.QueryRow(ctx, `SELECT email_exact,installation_id,code_generation,authorization_generation FROM v_auth.otp_flows WHERE flow_id=$1 FOR UPDATE`, req.FlowID[:]).Scan(&email, &originalInstall, &originalGeneration, &authorizationGeneration)
	if errors.Is(err, pgx.ErrNoRows) {
		return result, ErrOTPFlowInvalid
	}
	if err != nil {
		return result, err
	}
	if authorizationGeneration == 0 || authorizationGeneration != verifierGeneration(tx) {
		return result, ErrOTPExpired
	}
	if !hmac.Equal(originalInstall, req.InstallationID[:]) {
		return result, ErrOTPFlowInvalid
	}
	var generation int64
	var latest []byte
	if err = tx.QueryRow(ctx, `SELECT code_generation,latest_flow_id FROM v_auth.otp_email_state WHERE email_exact=$1 FOR UPDATE`, email).Scan(&generation, &latest); err != nil {
		return result, err
	}
	if len(latest) != 32 {
		return result, ErrOTPExpired
	}
	var latestState string
	var failures int
	var expires time.Time
	if err = tx.QueryRow(ctx, `SELECT state,failed_attempts,expires_at FROM v_auth.otp_flows WHERE flow_id=$1 FOR UPDATE`, latest).Scan(&latestState, &failures, &expires); err != nil {
		return result, err
	}
	var at time.Time
	if err = verifierTrustedAt(ctx, tx, &at); err != nil {
		return result, err
	}
	consecutive, locked, err := e.lockOTPDevice(ctx, tx, req.InstallationID, email, at)
	if err != nil {
		return result, err
	}
	if err = verifierTrustedAt(ctx, tx, &at); err != nil {
		return result, err
	}
	consecutive, locked, err = e.lockOTPDevice(ctx, tx, req.InstallationID, email, at)
	if err != nil {
		return result, err
	}
	if err = e.consumeOTPBudget(ctx, tx, email, "VERIFY", at); err != nil {
		return result, err
	}
	if locked != nil && at.Before(*locked) {
		return result, eligibilityError("RATE_LIMITED", remainingSeconds(*locked, at))
	}
	if len(req.OTP) != 6 || strings.IndexFunc(req.OTP, func(r rune) bool { return r < '0' || r > '9' }) >= 0 {
		return result, ErrBadRequest
	}
	if _, err = tx.Exec(ctx, `DELETE FROM v_auth.otp_code_versions WHERE email_exact=$1 AND retain_until <= $2`, email, at); err != nil {
		return result, err
	}
	rows, err := tx.Query(ctx, `SELECT flow_id,code_generation,code_hmac,otp_key_version,state,expires_at FROM v_auth.otp_code_versions WHERE email_exact=$1`, email)
	if err != nil {
		return result, err
	}
	matched := false
	var matchedGeneration int64
	var matchedState string
	var matchedExpiry time.Time
	for rows.Next() {
		var flow, stored []byte
		var g, keyVersion int64
		var state string
		var until time.Time
		if err = rows.Scan(&flow, &g, &stored, &keyVersion, &state, &until); err != nil {
			rows.Close()
			return result, err
		}
		if keyVersion != e.config.OTPKeyVersion {
			rows.Close()
			return result, errors.New("OTP retained key unavailable")
		}
		var id [32]byte
		copy(id[:], flow)
		candidate := otpDigest(e.config.OTPKey, email, g, id, req.OTP)
		if hmac.Equal(candidate[:], stored) {
			matched = true
			matchedGeneration = g
			matchedState = state
			matchedExpiry = until
		}
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return result, err
	}
	if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_email_state SET last_activity_at={trusted_at} WHERE email_exact=$1`, email); err != nil {
		return result, err
	}
	result.AttemptCounted = true
	if matched {
		if !at.Before(matchedExpiry) {
			return result, ErrOTPExpired
		}
		if matchedGeneration != generation || originalGeneration != generation || !bytes.Equal(latest, req.FlowID[:]) || matchedState != "ACTIVE" || latestState != "ACTIVE" {
			return result, ErrOTPReplaced
		}
		if !at.Before(expires) {
			return result, ErrOTPExpired
		}
		if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_flows SET state='CONSUMED' WHERE flow_id=$1`, req.FlowID[:]); err != nil {
			return result, err
		}
		if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_code_versions SET state='CONSUMED' WHERE email_exact=$1 AND code_generation=$2`, email, generation); err != nil {
			return result, err
		}
		d := e.deviceEmailDigest(email)
		if _, err = tx.Exec(ctx, `UPDATE v_auth.device_email_limits SET consecutive_errors=0,locked_until=NULL WHERE installation_id=$1 AND email_digest=$2`, req.InstallationID[:], d[:]); err != nil {
			return result, err
		}
		if err = verifierFinalCheck(tx, func(d AuthorizationDecision) error {
			if d.Generation != authorizationGeneration {
				return ErrAuthorizationUnavailable
			}
			if !d.TrustedAt.Before(expires) {
				return ErrOTPExpired
			}
			return nil
		}); err != nil {
			return result, err
		}
		return OTPVerification{Email: email, FlowID: req.FlowID, Generation: generation, ExpiresAt: expires, VerifiedAt: at, AttemptCounted: true}, nil
	}
	consecutive++
	var newLock *time.Time
	if consecutive >= 3 {
		consecutive = 3
		until := at.Add(5 * time.Minute)
		newLock = &until
	}
	d := e.deviceEmailDigest(email)
	if _, err = tx.Exec(ctx, `UPDATE v_auth.device_email_limits SET consecutive_errors=$1,locked_until=$2 WHERE installation_id=$3 AND email_digest=$4`, consecutive, newLock, req.InstallationID[:], d[:]); err != nil {
		return result, err
	}
	if latestState == "ACTIVE" && at.Before(expires) {
		failures++
		state := "ACTIVE"
		if failures >= 10 {
			state = "INVALIDATED"
		}
		if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_flows SET failed_attempts=$1,state=$2 WHERE flow_id=$3`, failures, state, latest); err != nil {
			return result, err
		}
		if state == "INVALIDATED" {
			if _, err = tx.Exec(ctx, `UPDATE v_auth.otp_code_versions SET state='INVALIDATED' WHERE email_exact=$1 AND code_generation=$2`, email, generation); err != nil {
				return result, err
			}
		}
	}
	if newLock != nil {
		return result, eligibilityError("RATE_LIMITED", remainingSeconds(*newLock, at))
	}
	return result, ErrOTPInvalid
}

// DispatchMail claims exactly one attempt durably before touching SMTP. Even a
// crash or ambiguous DATA response cannot make a later worker send it again.
func (e *Eligibility) DispatchMail(ctx context.Context, keyBytes [32]byte) (MailOutcome, error) {
	key := digest("HNUHOLE/V-REQUEST-TOMBSTONE/V1", keyBytes[:])
	return e.dispatchMailDigest(ctx, key)
}

// dispatchMailDigest consumes the persistent digest, never a reconstructed raw
// idempotency key or a fresh business operation. Only QUEUED may be claimed.
func (e *Eligibility) dispatchMailDigest(ctx context.Context, key [32]byte) (MailOutcome, error) {
	if _, err := e.store.gate.Snapshot(ctx); err != nil {
		return MailUnknown, err
	}
	var email []byte
	err := e.store.pool.QueryRow(ctx, `SELECT f.email_exact FROM v_auth.mail_outbox m JOIN v_auth.otp_flows f USING(flow_id) WHERE m.key_digest=$1`, key[:]).Scan(&email)
	if errors.Is(err, pgx.ErrNoRows) {
		return MailUnknown, nil
	}
	if err != nil {
		return MailUnknown, err
	}
	tx, err := e.store.beginAuthorized(ctx)
	if err != nil {
		return MailUnknown, err
	}
	defer tx.Rollback(ctx)
	if err = e.store.lockAddress(ctx, tx, email); err != nil {
		return MailUnknown, err
	}
	if err = lockVRequest(ctx, tx, key); err != nil {
		return MailUnknown, err
	}
	row, err := readOTPMail(ctx, tx, key, true)
	if err != nil {
		return MailUnknown, err
	}
	if row.state != "QUEUED" {
		if row.state == "SENT" {
			return MailSent, tx.Commit(ctx)
		}
		if row.state == "NOT_SENT" {
			return MailNotSent, tx.Commit(ctx)
		}
		return MailUnknown, tx.Commit(ctx)
	}
	var at time.Time
	if err = verifierTrustedAt(ctx, tx, &at); err != nil {
		return MailUnknown, err
	}
	if row.authorizationGeneration == 0 || row.authorizationGeneration != verifierGeneration(tx) || !at.Before(row.expires) {
		if err = e.finishMailInTx(ctx, tx, key, row, email, MailNotSent); err != nil {
			return MailUnknown, err
		}
		return MailNotSent, tx.Commit(ctx)
	}
	if row.keyVersion == nil || *row.keyVersion != e.config.MailEncryptionKeyVersion {
		return MailUnknown, errors.New("mail encryption key unavailable")
	}
	aead, err := e.mailAEAD()
	if err != nil {
		return MailUnknown, err
	}
	raw, err := aead.Open(nil, row.nonce, row.encrypted, mailAAD(row.operation, row.flow, email))
	if err != nil {
		return MailUnknown, errors.New("invalid encrypted mail material")
	}
	code := string(raw)
	if len(code) != 6 || strings.IndexFunc(code, func(r rune) bool { return r < '0' || r > '9' }) >= 0 {
		return MailUnknown, errors.New("invalid mail code material")
	}
	if err = verifierFinalCheck(tx, func(d AuthorizationDecision) error {
		if !d.TrustedAt.Before(row.expires) {
			return ErrExpired
		}
		return nil
	}); err != nil {
		return MailUnknown, err
	}
	if _, err = tx.Exec(ctx, `UPDATE v_auth.mail_outbox SET state='DISPATCHING' WHERE key_digest=$1 AND state='QUEUED' AND authorization_generation=$2`, key[:], int64(row.authorizationGeneration)); err != nil {
		return MailUnknown, err
	}
	if err = tx.Commit(ctx); err != nil {
		return MailUnknown, err
	}
	currentGate, gateErr := e.store.gate.Snapshot(ctx)
	if gateErr != nil || currentGate.Generation != row.authorizationGeneration {
		for i := range raw {
			raw[i] = 0
		}
		if gateErr == nil {
			gateErr = ErrAuthorizationUnavailable
		}
		return MailUnknown, gateErr
	}
	if !currentGate.TrustedAt.Before(row.expires) {
		for i := range raw {
			raw[i] = 0
		}
		// The durable claim prevents retry. Cleanup settles/erases the claim;
		// it never dispatches a code that expired while this refresh waited.
		return MailUnknown, ErrOTPExpired
	}
	sendCtx, sendCancel := context.WithTimeout(ctx, 10*time.Second)
	outcome, sendErr := e.mail.SendOTP(sendCtx, row.operation, string(email), code)
	sendCancel()
	for i := range raw {
		raw[i] = 0
	}
	if outcome != MailSent && outcome != MailNotSent {
		outcome = MailUnknown
	}
	// A provider error is never evidence of non-delivery after an attempted send.
	if sendErr != nil && outcome != MailNotSent {
		outcome = MailUnknown
	}
	finalCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	final, err := e.store.beginAuthorized(finalCtx)
	if err != nil {
		return MailUnknown, err
	}
	defer final.Rollback(finalCtx)
	if err = e.store.lockAddress(finalCtx, final, email); err != nil {
		return MailUnknown, err
	}
	if err = lockVRequest(finalCtx, final, key); err != nil {
		return MailUnknown, err
	}
	current, err := readOTPMail(finalCtx, final, key, true)
	if err != nil {
		return MailUnknown, err
	}
	if current.authorizationGeneration != row.authorizationGeneration || verifierGeneration(final) != row.authorizationGeneration {
		return MailUnknown, ErrAuthorizationUnavailable
	}
	if current.state != "DISPATCHING" {
		return MailUnknown, final.Commit(finalCtx)
	}
	if err = e.finishMailInTx(finalCtx, final, key, current, email, outcome); err != nil {
		return MailUnknown, err
	}
	if err = final.Commit(finalCtx); err != nil {
		return MailUnknown, err
	}
	return outcome, sendErr
}

// ResumeQueuedMail enumerates at most limit durable jobs. Concurrent workers
// share the address -> request -> outbox lock order; DISPATCHING and UNKNOWN
// never appear in the enumeration and cannot be automatically dispatched.
func (e *Eligibility) ResumeQueuedMail(ctx context.Context, limit int) (int, error) {
	if limit < 1 || limit > 500 {
		return 0, ErrBadRequest
	}
	rows, err := e.store.queryCandidates(ctx, `SELECT key_digest FROM v_auth.mail_outbox WHERE state='QUEUED' ORDER BY expires_at,key_digest LIMIT $1`, limit)
	if err != nil {
		return 0, err
	}
	var keys [][32]byte
	for rows.Next() {
		var raw []byte
		if err = rows.Scan(&raw); err != nil || len(raw) != 32 {
			rows.Close()
			return 0, ErrReconciliation
		}
		var key [32]byte
		copy(key[:], raw)
		keys = append(keys, key)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return 0, err
	}
	processed := 0
	for _, key := range keys {
		if err = ctx.Err(); err != nil {
			return processed, err
		}
		_, err = e.dispatchMailDigest(ctx, key)
		processed++
		if err != nil {
			return processed, err
		}
	}
	return processed, nil
}

func (e *Eligibility) finishMailInTx(ctx context.Context, tx pgx.Tx, key [32]byte, row otpMailRow, email []byte, outcome MailOutcome) error {
	if _, err := tx.Exec(ctx, `UPDATE v_auth.mail_outbox SET state=$1,email_exact=NULL,ciphertext=NULL,nonce=NULL,encryption_key_version=NULL WHERE key_digest=$2 AND authorization_generation=$3`, string(outcome), key[:], int64(row.authorizationGeneration)); err != nil {
		return err
	}
	if outcome == MailNotSent {
		if _, err := tx.Exec(ctx, `UPDATE v_auth.otp_email_state SET send_wait_until=$1 WHERE email_exact=$2 AND latest_flow_id=$3 AND send_wait_until=$4`, row.previousWait, email, row.flow[:], row.wait); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE v_auth.otp_flows SET state='EXPIRED' WHERE flow_id=$1 AND state='ACTIVE'`, row.flow[:]); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE v_auth.otp_code_versions SET state='EXPIRED' WHERE flow_id=$1 AND state='ACTIVE'`, row.flow[:]); err != nil {
			return err
		}
	}
	result := "ACCEPTED"
	if outcome == MailNotSent {
		result = "NOT_SENT"
	}
	if outcome == MailUnknown {
		result = "PENDING"
	}
	_, err := tx.Exec(ctx, `UPDATE v_auth.request_results SET result_code=$1 WHERE key_digest=$2 AND state='LIVE'`, result, key[:])
	return err
}

// CleanupOTP bounds each work class by limit. Run it periodically: expired
// encryption is erased without reopening UNKNOWN sends; retained recognition
// HMACs, rolling budgets, resolved results and flow associations are minimized.
// Device metadata and unreferenced address/generation state expire after 24h
// without activity. Existing quota or continuation evidence keeps its generation.
func (e *Eligibility) CleanupOTP(ctx context.Context, limit int) error {
	if limit < 1 || limit > 500 {
		return ErrBadRequest
	}
	rows, err := e.store.queryCandidates(ctx, `SELECT m.key_digest,f.email_exact FROM v_auth.mail_outbox m JOIN v_auth.otp_flows f USING(flow_id) WHERE m.state IN ('QUEUED','DISPATCHING') AND m.expires_at<={trusted_at} ORDER BY m.expires_at,m.key_digest LIMIT $1`, limit)
	if err != nil {
		return err
	}
	type pending struct {
		key   [32]byte
		email []byte
	}
	var jobs []pending
	for rows.Next() {
		var p pending
		var key []byte
		if err = rows.Scan(&key, &p.email); err != nil {
			rows.Close()
			return err
		}
		copy(p.key[:], key)
		jobs = append(jobs, p)
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return err
	}
	for _, job := range jobs {
		tx, err := e.store.beginAuthorized(ctx)
		if err != nil {
			return err
		}
		if err = e.store.lockAddress(ctx, tx, job.email); err == nil {
			err = lockVRequest(ctx, tx, job.key)
		}
		if err == nil {
			var row otpMailRow
			row, err = readOTPMail(ctx, tx, job.key, true)
			if errors.Is(err, pgx.ErrNoRows) {
				err = nil
			}
			if err == nil {
				var at time.Time
				err = verifierTrustedAt(ctx, tx, &at)
				if err == nil && !at.Before(row.expires) && (row.state == "QUEUED" || row.state == "DISPATCHING") {
					outcome := MailNotSent
					if row.state == "DISPATCHING" {
						outcome = MailUnknown
					}
					err = e.finishMailInTx(ctx, tx, job.key, row, job.email, outcome)
				}
			}
		}
		if err == nil {
			err = tx.Commit(ctx)
		} else {
			_ = tx.Rollback(ctx)
		}
		if err != nil {
			return err
		}
	}
	_, err = e.store.execAuthorized(ctx, `DELETE FROM v_auth.otp_code_versions WHERE (email_exact,code_generation) IN (SELECT email_exact,code_generation FROM v_auth.otp_code_versions WHERE retain_until<={trusted_at} ORDER BY retain_until,email_exact,code_generation LIMIT $1)`, limit)
	if err != nil {
		return err
	}
	_, err = e.store.execAuthorized(ctx, `DELETE FROM v_auth.otp_budget_events WHERE event_id IN (SELECT event_id FROM v_auth.otp_budget_events WHERE (kind='SEND' AND occurred_at<={trusted_at}-interval '1 hour') OR (kind='VERIFY' AND occurred_at<={trusted_at}-interval '10 minutes') ORDER BY event_id LIMIT $1)`, limit)
	if err != nil {
		return err
	}
	rows, err = e.store.queryCandidates(ctx, `SELECT r.key_digest FROM v_auth.request_results r JOIN v_auth.mail_outbox m USING(key_digest) WHERE r.operation=$1 AND r.state='LIVE' AND r.expires_at<={trusted_at} AND m.state IN ('SENT','NOT_SENT','UNKNOWN') ORDER BY r.expires_at,r.key_digest LIMIT $2`, otpRequestOperation, limit)
	if err != nil {
		return err
	}
	var keys [][32]byte
	for rows.Next() {
		var keyBytes []byte
		if err = rows.Scan(&keyBytes); err != nil {
			rows.Close()
			return err
		}
		var key [32]byte
		copy(key[:], keyBytes)
		keys = append(keys, key)
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return err
	}
	for _, key := range keys {
		tx, err := e.store.beginAuthorized(ctx)
		if err != nil {
			return err
		}
		if err = lockVRequest(ctx, tx, key); err == nil {
			var allowed bool
			err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.request_results r JOIN v_auth.mail_outbox m USING(key_digest) WHERE r.key_digest=$1 AND r.operation=$2 AND r.state='LIVE' AND r.expires_at<={trusted_at} AND m.state IN ('SENT','NOT_SENT','UNKNOWN'))`, key[:], otpRequestOperation).Scan(&allowed)
			if err == nil && allowed {
				err = expireOTPRequestResult(ctx, tx, key)
			}
		}
		if err == nil {
			err = tx.Commit(ctx)
		} else {
			_ = tx.Rollback(ctx)
		}
		if err != nil {
			return err
		}
	}
	rows, err = e.store.queryCandidates(ctx, `SELECT f.flow_id,f.email_exact FROM v_auth.otp_flows f WHERE f.expires_at+interval '5 minutes'<={trusted_at} AND NOT EXISTS(SELECT 1 FROM v_auth.otp_code_versions c WHERE c.flow_id=f.flow_id) AND NOT EXISTS(SELECT 1 FROM v_auth.mail_outbox m WHERE m.flow_id=f.flow_id) ORDER BY f.expires_at,f.flow_id LIMIT $1`, limit)
	if err != nil {
		return err
	}
	type oldFlow struct {
		id    [32]byte
		email []byte
	}
	var flows []oldFlow
	for rows.Next() {
		var f oldFlow
		var id []byte
		if err = rows.Scan(&id, &f.email); err != nil {
			rows.Close()
			return err
		}
		copy(f.id[:], id)
		flows = append(flows, f)
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return err
	}
	for _, flow := range flows {
		tx, err := e.store.beginAuthorized(ctx)
		if err != nil {
			return err
		}
		if err = e.store.lockAddress(ctx, tx, flow.email); err == nil {
			_, err = tx.Exec(ctx, `UPDATE v_auth.otp_email_state SET latest_flow_id=NULL WHERE email_exact=$1 AND latest_flow_id=$2`, flow.email, flow.id[:])
			if err == nil {
				_, err = tx.Exec(ctx, `DELETE FROM v_auth.otp_flows WHERE flow_id=$1 AND expires_at+interval '5 minutes'<={trusted_at} AND NOT EXISTS(SELECT 1 FROM v_auth.otp_code_versions c WHERE c.flow_id=$1) AND NOT EXISTS(SELECT 1 FROM v_auth.mail_outbox m WHERE m.flow_id=$1)`, flow.id[:])
			}
		}
		if err == nil {
			err = tx.Commit(ctx)
		} else {
			_ = tx.Rollback(ctx)
		}
		if err != nil {
			return err
		}
	}
	// Device row locks synchronize cleanup with lockOTPDevice. An active lock
	// survives even if a historical timestamp was already older than 24 hours.
	_, err = e.store.execAuthorized(ctx, `DELETE FROM v_auth.device_email_limits WHERE (installation_id,email_digest) IN (SELECT installation_id,email_digest FROM v_auth.device_email_limits WHERE last_activity_at<={trusted_at}-interval '24 hours' AND (locked_until IS NULL OR locked_until<={trusted_at}) ORDER BY last_activity_at,installation_id,email_digest LIMIT $1 FOR UPDATE SKIP LOCKED) AND last_activity_at<={trusted_at}-interval '24 hours' AND (locked_until IS NULL OR locked_until<={trusted_at})`, limit)
	if err != nil {
		return err
	}
	rows, err = e.store.queryCandidates(ctx, `SELECT s.email_exact FROM v_auth.otp_email_state s WHERE s.last_activity_at<={trusted_at}-interval '24 hours' AND s.send_wait_until<={trusted_at} AND s.latest_flow_id IS NULL AND NOT EXISTS(SELECT 1 FROM v_auth.email_quota q WHERE q.email_exact=s.email_exact) AND NOT EXISTS(SELECT 1 FROM v_auth.retire_pending p WHERE p.email_exact=s.email_exact) AND NOT EXISTS(SELECT 1 FROM v_auth.otp_flows f WHERE f.email_exact=s.email_exact) AND NOT EXISTS(SELECT 1 FROM v_auth.otp_budget_events b WHERE b.email_exact=s.email_exact) AND NOT EXISTS(SELECT 1 FROM v_auth.otp_confirmations c WHERE c.email_exact=s.email_exact) ORDER BY s.last_activity_at,s.email_exact LIMIT $1`, limit)
	if err != nil {
		return err
	}
	var emails [][]byte
	for rows.Next() {
		var email []byte
		if err = rows.Scan(&email); err != nil {
			rows.Close()
			return err
		}
		emails = append(emails, email)
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return err
	}
	for _, email := range emails {
		tx, err := e.store.beginAuthorized(ctx)
		if err != nil {
			return err
		}
		if err = e.store.lockAddress(ctx, tx, email); err == nil {
			// Recheck after the address lock: a concurrent request, reservation,
			// or retirement must prevent removal and generation restart.
			_, err = tx.Exec(ctx, `DELETE FROM v_auth.otp_email_state s WHERE s.email_exact=$1 AND s.last_activity_at<={trusted_at}-interval '24 hours' AND s.send_wait_until<={trusted_at} AND s.latest_flow_id IS NULL AND NOT EXISTS(SELECT 1 FROM v_auth.email_quota q WHERE q.email_exact=s.email_exact) AND NOT EXISTS(SELECT 1 FROM v_auth.retire_pending p WHERE p.email_exact=s.email_exact) AND NOT EXISTS(SELECT 1 FROM v_auth.otp_flows f WHERE f.email_exact=s.email_exact) AND NOT EXISTS(SELECT 1 FROM v_auth.otp_budget_events b WHERE b.email_exact=s.email_exact) AND NOT EXISTS(SELECT 1 FROM v_auth.otp_confirmations c WHERE c.email_exact=s.email_exact)`, email)
		}
		if err == nil {
			err = tx.Commit(ctx)
		} else {
			_ = tx.Rollback(ctx)
		}
		if err != nil {
			return err
		}
	}
	return nil
}
