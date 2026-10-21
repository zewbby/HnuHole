package authprivacyhttp

import (
	"context"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"net/http"
)

type emailLoginBackend interface {
	ConfirmEmailLogin(context.Context, authprivacy.EmailLoginConfirmation) (authprivacy.EmailLoginResult, error)
}
type emailSessionBackend interface {
	CreateEmailSession(context.Context, authprivacy.EmailSessionRequest) (authprivacy.SessionCreateResult, error)
}

func (b *boundary) emailLoginConfirmation(w http.ResponseWriter, r *http.Request, backend EligibilityBackend, key [32]byte, installation [16]byte) {
	service, ok := backend.(emailLoginBackend)
	if !ok {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	object, err := readRequestObject(r, 2048, []string{"flowId", "otp", "binding"}, nil)
	if err != nil {
		b.bad(w, err)
		return
	}
	flow, e1 := stringField(object, "flowId")
	otp, e2 := stringField(object, "otp")
	binding, e3 := stringField(object, "binding")
	f, e4 := protocol.DecodeCanonicalBase64url(flow, 32)
	v, e5 := protocol.DecodeCanonicalBase64url(binding, 32)
	if e1 != nil || e2 != nil || e3 != nil || e4 != nil || e5 != nil || !otpPattern.MatchString(otp) {
		b.bad(w, errMalformed)
		return
	}
	req := authprivacy.EmailLoginConfirmation{Key: key, InstallationID: installation, OTP: otp}
	copy(req.FlowID[:], f)
	copy(req.Binding[:], v)
	result, err := service.ConfirmEmailLogin(r.Context(), req)
	if err != nil {
		b.eligibilityFailure(w, err)
		return
	}
	if result.State == "UNREGISTERED" {
		writeJSON(w, 200, map[string]string{"state": result.State})
		return
	}
	if result.State != "PROOF_AVAILABLE" || result.Proof == "" {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	writeJSON(w, 200, map[string]string{"state": result.State, "proof": result.Proof})
}
func (b *boundary) emailSession(w http.ResponseWriter, r *http.Request, backend SessionBackend) {
	service, ok := backend.(emailSessionBackend)
	if !ok {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if hasHeader(r.Header, "Authorization") {
		b.bad(w, errMalformed)
		return
	}
	raw, err := headerBytes(r.Header, "Idempotency-Key", 32)
	if err != nil {
		b.bad(w, err)
		return
	}
	object, err := readRequestObject(r, 2048, []string{"proof", "installationId"}, nil)
	if err != nil {
		b.bad(w, err)
		return
	}
	proof, e1 := stringField(object, "proof")
	installation, e2 := stringField(object, "installationId")
	id, e3 := protocol.DecodeCanonicalBase64url(installation, 16)
	if e1 != nil || e2 != nil || e3 != nil {
		b.bad(w, errMalformed)
		return
	}
	if _, err = protocol.DecodeCanonicalBase64url(proof, protocol.EmailLoginProofLength); err != nil {
		b.fail(w, 422, "EMAIL_PROOF_INVALID", 0)
		return
	}
	req := authprivacy.EmailSessionRequest{Proof: proof}
	copy(req.InstallationID[:], id)
	copy(req.IdempotencyKey[:], raw)
	result, err := service.CreateEmailSession(r.Context(), req)
	if err != nil {
		b.sessionFailure(w, err)
		return
	}
	w.Header().Set("Session-Expires-At", utc(result.ExpiresAt))
	writeJSON(w, 201, map[string]string{"accountId": result.AccountID.String(), "sessionToken": protocol.EncodeCanonicalBase64url(result.SessionToken[:]), "expiresAt": utc(result.ExpiresAt)})
}
