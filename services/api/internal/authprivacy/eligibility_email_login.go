package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"time"
)

type EmailLoginConfirmation struct {
	Key            [32]byte
	FlowID         [32]byte
	InstallationID [16]byte
	Binding        [32]byte
	OTP            string
}
type EmailLoginResult struct {
	State string
	Proof string
}

func (e *Eligibility) ConfirmEmailLogin(ctx context.Context, req EmailLoginConfirmation) (EmailLoginResult, error) {
	var zero EmailLoginResult
	if req.Key == ([32]byte{}) || req.FlowID == ([32]byte{}) || req.InstallationID == ([16]byte{}) || req.Binding == ([32]byte{}) || !validOTPShape(req.OTP) {
		return zero, ErrBadRequest
	}
	key := digest("HNUHOLE/V-EMAIL-LOGIN-CONFIRM/V1", req.Key[:])
	mac := requestMAC(e.config.RequestHMACKey, []byte("EMAIL_LOGIN_CONFIRM"), req.FlowID[:], req.InstallationID[:], req.Binding[:], []byte(req.OTP))
	if _, err := e.store.gate.Snapshot(ctx); err != nil {
		return zero, err
	}
	var prior string
	preErr := e.store.pool.QueryRow(ctx, `SELECT result_code FROM v_auth.email_login_confirmations WHERE key_digest=$1`, key[:]).Scan(&prior)
	if preErr == nil && prior == "EXPIRED" {
		return zero, ErrExpired
	}
	if preErr != nil && !errors.Is(preErr, pgx.ErrNoRows) {
		return zero, preErr
	}
	email, err := e.lookupOTPFlowEmail(ctx, req.FlowID)
	if err != nil {
		return zero, err
	}
	tx, err := e.store.beginAuthorized(ctx)
	if err != nil {
		return zero, err
	}
	defer tx.Rollback(ctx)
	if err = e.store.lockAddress(ctx, tx, email); err != nil {
		return zero, err
	}
	if err = lockVRequest(ctx, tx, key); err != nil {
		return zero, err
	}
	var stored []byte
	var code string
	var proof *string
	var expires time.Time
	var generation uint64
	err = tx.QueryRow(ctx, `SELECT request_hmac,result_code,proof,expires_at,authorization_generation FROM v_auth.email_login_confirmations WHERE key_digest=$1 FOR UPDATE`, key[:]).Scan(&stored, &code, &proof, &expires, &generation)
	var at time.Time
	if e2 := verifierTrustedAt(ctx, tx, &at); e2 != nil {
		return zero, e2
	}
	if err == nil {
		if code == "EXPIRED" || generation != verifierGeneration(tx) || !at.Before(expires) {
			return zero, ErrExpired
		}
		if !hmac.Equal(stored, mac[:]) {
			return zero, ErrConflict
		}
		if err = tx.Commit(ctx); err != nil {
			return zero, err
		}
		if code != "PROOF_AVAILABLE" && code != "UNREGISTERED" {
			return zero, eligibilityError(code, 0)
		}
		result := EmailLoginResult{State: code}
		if proof != nil {
			result.Proof = *proof
		}
		return result, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return zero, err
	}
	verified, verifyErr := e.verifyOTPInTx(ctx, tx, ConfirmOTPRequest{Purpose: "LOGIN", FlowID: req.FlowID, InstallationID: req.InstallationID, OTP: req.OTP}, at)
	if verifyErr != nil && !expectedOTPError(verifyErr) {
		return zero, verifyErr
	}
	if verifyErr != nil && !verified.AttemptCounted {
		return zero, verifyErr
	}
	result := EmailLoginResult{State: "UNREGISTERED"}
	var signed *string
	expires = at.Add(2 * time.Minute)
	if verifyErr != nil {
		var rejected *EligibilityError
		if !errors.As(verifyErr, &rejected) {
			return zero, verifyErr
		}
		result.State = rejected.Code
	} else {
		var slot []byte
		var retiring bool
		err = tx.QueryRow(ctx, `SELECT current_slot,EXISTS(SELECT 1 FROM v_auth.retire_pending p WHERE p.old_slot=q.current_slot) FROM v_auth.email_quota q WHERE email_exact=$1 FOR UPDATE`, email).Scan(&slot, &retiring)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return zero, err
		}
		if retiring {
			return zero, ErrEligibilityReserved
		}
		if len(slot) == 32 {
			nonce, er := random32()
			if er != nil {
				return zero, er
			}
			value := protocol.EmailLoginProof{Epoch: e.config.RegistrationEpoch, Environment: sha256.Sum256([]byte(e.store.verifier.Environment())), Binding: req.Binding, Nonce: nonce, Expires: uint64(expires.Unix())}
			copy(value.Slot[:], slot)
			message := value.MessageBytes()
			sig, er := e.signer(ctx, value.Epoch, message[:])
			if er != nil || len(sig) != 64 {
				return zero, ErrAuthorizationUnavailable
			}
			copy(value.Signature[:], sig)
			encoded := value.Encode()
			signed = &encoded
			result = EmailLoginResult{State: "PROOF_AVAILABLE", Proof: encoded}
		}
	}
	if _, err = tx.Exec(ctx, `INSERT INTO v_auth.email_login_confirmations(key_digest,request_hmac,flow_id,installation_id,binding,result_code,proof,expires_at,authorization_generation) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, key[:], mac[:], req.FlowID[:], req.InstallationID[:], req.Binding[:], result.State, signed, expires, int64(verifierGeneration(tx))); err != nil {
		return zero, err
	}
	if err = verifierFinalCheck(tx, func(d AuthorizationDecision) error {
		if !d.TrustedAt.Before(expires) {
			return ErrExpired
		}
		return nil
	}); err != nil {
		return zero, err
	}
	if err = tx.Commit(ctx); err != nil {
		return zero, err
	}
	if verifyErr != nil {
		return zero, verifyErr
	}
	return result, nil
}
