package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func (p *probe) verifierRequest(ctx context.Context, status int) (map[string]any, map[string]string, string, error) {
	installation, err := randomCapability(16)
	if err != nil {
		return nil, nil, "", err
	}
	key, err := randomCapability(32)
	if err != nil {
		return nil, nil, "", err
	}
	sum := sha256.Sum256([]byte(key))
	email := fmt.Sprintf("runtime-v-gate-%x@hainanu.edu.cn", sum[:8])
	headers := map[string]string{"Idempotency-Key": key, "V-Installation-ID": installation}
	reply, _, err := p.request(ctx, "POST", p.v, "/api/v1/eligibility/otp-requests", map[string]string{"email": email}, headers, status)
	return reply, headers, email, err
}

// The unconsumed OTP is created by the actual V service. Its request remains
// private runner state so recovery fencing can be exercised over public HTTPS.
func (p *probe) verifierStage(ctx context.Context, s *state) error {
	reply, headers, email, err := p.verifierRequest(ctx, 202)
	if err != nil {
		return err
	}
	flow, err := field(reply, "flowId")
	if err != nil {
		return err
	}
	code, err := p.otp(ctx, email)
	if err != nil {
		return err
	}
	public, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return err
	}
	var key protocol.PublicKey
	copy(key[:], public)
	slot, err := protocol.DeriveSlot(key)
	if err != nil {
		return err
	}
	confirmKey, err := randomCapability(32)
	if err != nil {
		return err
	}
	s.VerifierConfirmationBody = map[string]string{"flowId": flow, "otp": code, "slotId": protocol.EncodeCanonicalBase64url(slot[:]), "bootstrapPublicKey": protocol.EncodeCanonicalBase64url(public)}
	s.VerifierConfirmationHeaders = map[string]string{"Idempotency-Key": confirmKey, "V-Installation-ID": headers["V-Installation-ID"]}
	return nil
}

func (p *probe) verifierCommunityStillOpen(ctx context.Context, s state) error {
	_, _, err := p.request(ctx, "GET", p.c, "/api/v1/auth/session", nil, map[string]string{"Authorization": "Bearer " + s.Token}, 200)
	return err
}
func (p *probe) verifierFrozen(ctx context.Context, s state) error {
	if err := p.verifierCommunityStillOpen(ctx, s); err != nil {
		return err
	}
	if _, _, _, err := p.verifierRequest(ctx, 503); err != nil {
		return err
	}
	if s.VerifierConfirmationBody == nil {
		return errors.New("V gate stage was not captured")
	}
	_, _, err := p.request(ctx, "POST", p.v, "/api/v1/eligibility/otp-confirmations", s.VerifierConfirmationBody, s.VerifierConfirmationHeaders, 503)
	return err
}
func (p *probe) verifierRecovered(ctx context.Context, s state) error {
	if err := p.verifierCommunityStillOpen(ctx, s); err != nil {
		return err
	}
	if s.VerifierConfirmationBody == nil {
		return errors.New("V gate stage was not captured")
	}
	rejected, _, err := p.request(ctx, "POST", p.v, "/api/v1/eligibility/otp-confirmations", s.VerifierConfirmationBody, s.VerifierConfirmationHeaders, 422)
	if err != nil {
		return err
	}
	failure, ok := rejected["error"].(map[string]any)
	if !ok || failure["code"] != "OTP_EXPIRED" {
		return errors.New("recovered V did not fence the old OTP generation")
	}
	_, _, _, err = p.verifierRequest(ctx, 202)
	return err
}
