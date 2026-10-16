package authprivacyhttp

import (
	"errors"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func validPasswordInput(password string) bool {
	return password != "" && utf8.ValidString(password) && len(password) <= 2048 && utf8.RuneCountInString(password) <= 512
}

func encoded32Field(object map[string]any, field string) ([32]byte, error) {
	var result [32]byte
	value, err := stringField(object, field)
	if err != nil {
		return result, errMalformed
	}
	raw, err := protocol.DecodeCanonicalBase64url(value, 32)
	if err != nil {
		return result, errMalformed
	}
	copy(result[:], raw)
	return result, nil
}

func (b *boundary) communityRecoveryPublic(w http.ResponseWriter, r *http.Request, backend RecoveryBackend, passwords PasswordPreparer) {
	if backend == nil {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if r.URL.Path == "/api/v1/auth/password-reset-result" {
		if noBodyOrQuery(r) != nil || hasHeader(r.Header, "Idempotency-Key") {
			b.bad(w, errMalformed)
			return
		}
		key, err := sessionCapability(r.Header, "ResetResult")
		if err != nil {
			b.sessionCapabilityFailure(w, err)
			return
		}
		intentRaw, err := headerBytes(r.Header, "Reset-Intent-ID", 32)
		if err != nil {
			b.bad(w, err)
			return
		}
		var intent [32]byte
		copy(intent[:], intentRaw)
		state, err := backend.GetPasswordResetResult(r.Context(), key, intent)
		if err != nil {
			b.recoveryClosureFailure(w, err)
			return
		}
		switch state {
		case "COMMITTED", "NOT_COMMITTED":
			writeJSON(w, 200, map[string]string{"state": state})
		case "PENDING":
			w.Header().Set("Retry-After", "2")
			writeJSON(w, 202, map[string]string{"state": state})
		default:
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		}
		return
	}
	if hasHeader(r.Header, "Authorization") {
		b.bad(w, errMalformed)
		return
	}
	if r.URL.Path == "/api/v1/auth/recovery-code-reset-intents" {
		if hasHeader(r.Header, "Idempotency-Key") {
			b.bad(w, errMalformed)
			return
		}
		object, err := readRequestObject(r, 8192, []string{"recoveryCode"}, nil)
		if err != nil {
			b.bad(w, err)
			return
		}
		code, err := stringField(object, "recoveryCode")
		if err != nil || !validRecoveryCode(code, false) {
			b.bad(w, errMalformed)
			return
		}
		intent, err := backend.CreateRecoveryCodeResetIntent(r.Context(), code)
		if err != nil {
			b.recoveryClosureFailure(w, err)
			return
		}
		if intent.ID == ([32]byte{}) || intent.ExpiresAt.IsZero() || !privateUsername.MatchString(intent.Username) || !validRecoveryCode(intent.NewRecoveryCode, true) {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		writeJSON(w, 201, map[string]string{"resetIntentId": protocol.EncodeCanonicalBase64url(intent.ID[:]),
			"expiresAt": utc(intent.ExpiresAt), "username": intent.Username, "newRecoveryCode": intent.NewRecoveryCode})
		return
	}
	keyRaw, err := headerBytes(r.Header, "Idempotency-Key", 32)
	if err != nil {
		b.bad(w, err)
		return
	}
	object, err := readRequestObject(r, 8192, []string{"resetIntentId", "newPassword", "newRecoveryCodeConfirmation"}, nil)
	if err != nil {
		b.bad(w, err)
		return
	}
	intent, e1 := encoded32Field(object, "resetIntentId")
	password, e2 := stringField(object, "newPassword")
	code, e3 := stringField(object, "newRecoveryCodeConfirmation")
	if e1 != nil || e2 != nil || e3 != nil || !validPasswordInput(password) || !validRecoveryCode(code, false) {
		b.bad(w, errMalformed)
		return
	}
	request := authprivacy.PasswordResetRequest{IntentID: intent, NewPassword: password, NewRecoveryCodeConfirmation: code}
	copy(request.IdempotencyKey[:], keyRaw)
	if err := backend.CommitPasswordReset(r.Context(), request, passwords); err != nil {
		b.recoveryClosureFailure(w, err)
		return
	}
	w.WriteHeader(204)
}

func (b *boundary) communityClosurePublic(w http.ResponseWriter, r *http.Request, backend ClosureBackend, passwords PasswordPreparer) {
	if backend == nil {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if hasHeader(r.Header, "Idempotency-Key") {
		b.bad(w, errMalformed)
		return
	}
	if r.URL.Path == "/api/v1/account-closures" {
		bearer, err := sessionCapability(r.Header, "Bearer")
		if err != nil {
			b.sessionCapabilityFailure(w, err)
			return
		}
		object, err := readRequestObject(r, 8192, []string{"password", "closureId", "statusDigest"}, nil)
		if err != nil {
			b.bad(w, err)
			return
		}
		id, e1 := encoded32Field(object, "closureId")
		digest, e2 := encoded32Field(object, "statusDigest")
		password, e3 := stringField(object, "password")
		if e1 != nil || e2 != nil || e3 != nil || !validPasswordInput(password) {
			b.bad(w, errMalformed)
			return
		}
		accepted, err := backend.RequestAccountClosure(r.Context(), authprivacy.ClosureRequest{
			Bearer: bearer, ID: id, StatusDigest: digest, Password: password}, passwords)
		if err != nil {
			b.recoveryClosureFailure(w, err)
			return
		}
		if accepted.ID != id || accepted.DueAt.IsZero() {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		writeJSON(w, 202, map[string]string{"closureId": protocol.EncodeCanonicalBase64url(id[:]), "dueAt": utc(accepted.DueAt)})
		return
	}
	if noBodyOrQuery(r) != nil {
		b.bad(w, errMalformed)
		return
	}
	secret, err := sessionCapability(r.Header, "ClosureStatus")
	if err != nil {
		b.sessionCapabilityFailure(w, err)
		return
	}
	raw, err := protocol.DecodeCanonicalBase64url(strings.TrimPrefix(r.URL.Path, "/api/v1/account-closures/"), 32)
	if err != nil {
		b.bad(w, errMalformed)
		return
	}
	var id [32]byte
	copy(id[:], raw)
	status, err := backend.GetAccountClosureStatus(r.Context(), id, secret)
	if err != nil {
		b.recoveryClosureFailure(w, err)
		return
	}
	response := map[string]string{"state": status.State}
	switch status.State {
	case "PENDING", "FINALIZING":
		if status.DueAt == nil || status.DueAt.IsZero() || status.ReleaseReceipt != "" {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		response["dueAt"] = utc(*status.DueAt)
	case "CANCELLED":
		if status.DueAt != nil || status.ReleaseReceipt != "" {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
	case "CLOSED_RELEASE_PENDING", "RELEASED":
		if status.DueAt != nil || (status.State == "RELEASED" && status.ReleaseReceipt == "") {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		if status.ReleaseReceipt != "" {
			if _, err := protocol.ParseReceipt(status.ReleaseReceipt, protocol.PurposeReleased); err != nil {
				b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
				return
			}
			response["releaseReceipt"] = status.ReleaseReceipt
		}
	default:
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	writeJSON(w, 200, response)
}

func (b *boundary) recoveryClosureFailure(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, authprivacy.ErrRecoveryProofInvalid):
		b.fail(w, 401, "AUTHENTICATION_FAILED", 0)
	case errors.Is(err, authprivacy.ErrResetIntentInvalid):
		b.fail(w, 409, "INTENT_INVALID", 0)
	case errors.Is(err, authprivacy.ErrResetIntentExpired):
		b.fail(w, 410, "INTENT_EXPIRED", 0)
	case errors.Is(err, authprivacy.ErrResetResultNotFound), errors.Is(err, authprivacy.ErrClosureNotFound):
		b.fail(w, 404, "RESOURCE_NOT_FOUND", 0)
	case errors.Is(err, authprivacy.ErrPasswordPolicy):
		b.fail(w, 422, "PASSWORD_POLICY_FAILED", 0)
	default:
		b.sessionFailure(w, err)
	}
}
