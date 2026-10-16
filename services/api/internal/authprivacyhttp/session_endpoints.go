package authprivacyhttp

import (
	"errors"
	"net/http"
	"unicode/utf8"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func sessionCapability(header http.Header, scheme string) ([32]byte, error) {
	var result [32]byte
	value, err := singleHeader(header, "Authorization")
	if err != nil || len(value) < len(scheme)+2 || value[:len(scheme)+1] != scheme+" " {
		return result, errCapability
	}
	raw, err := protocol.DecodeCanonicalBase64url(value[len(scheme)+1:], 32)
	if err != nil {
		return result, errMalformed
	}
	copy(result[:], raw)
	return result, nil
}

func (b *boundary) communitySessionPublic(w http.ResponseWriter, r *http.Request, sessions SessionBackend, passwords PasswordPreparer) {
	if sessions == nil {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if r.URL.Path == "/api/v1/auth/sessions" {
		if hasHeader(r.Header, "Authorization") {
			b.bad(w, errMalformed)
			return
		}
		keyRaw, err := headerBytes(r.Header, "Idempotency-Key", 32)
		if err != nil {
			b.bad(w, err)
			return
		}
		object, err := readRequestObject(r, 8192, []string{"username", "password", "installationId"}, nil)
		if err != nil {
			b.bad(w, err)
			return
		}
		username, e1 := stringField(object, "username")
		password, e2 := stringField(object, "password")
		installation, e3 := stringField(object, "installationId")
		if e1 != nil || e2 != nil || e3 != nil || !privateUsername.MatchString(username) ||
			password == "" || len(password) > 2048 || !utf8.ValidString(password) || utf8.RuneCountInString(password) > 512 {
			b.bad(w, errMalformed)
			return
		}
		installationRaw, err := protocol.DecodeCanonicalBase64url(installation, 16)
		if err != nil {
			b.bad(w, err)
			return
		}
		request := authprivacy.SessionCreateRequest{Username: username, Password: password}
		copy(request.InstallationID[:], installationRaw)
		copy(request.IdempotencyKey[:], keyRaw)
		created, err := sessions.CreateSession(r.Context(), request, passwords)
		if err != nil {
			b.sessionFailure(w, err)
			return
		}
		if created.AccountID.String() == "00000000-0000-0000-0000-000000000000" ||
			created.SessionToken == ([32]byte{}) || created.ExpiresAt.IsZero() {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		w.Header().Set("Session-Expires-At", utc(created.ExpiresAt))
		writeJSON(w, 201, map[string]string{"accountId": created.AccountID.String(),
			"sessionToken": protocol.EncodeCanonicalBase64url(created.SessionToken[:]), "expiresAt": utc(created.ExpiresAt)})
		return
	}
	if hasHeader(r.Header, "Idempotency-Key") || noBodyOrQuery(r) != nil {
		b.bad(w, errMalformed)
		return
	}
	if r.URL.Path == "/api/v1/auth/session-revocations" {
		secret, err := sessionCapability(r.Header, "SessionRevoke")
		if err != nil {
			b.sessionCapabilityFailure(w, err)
			return
		}
		if err := sessions.RevokeSession(r.Context(), secret); err != nil {
			b.sessionFailure(w, err)
			return
		}
		w.WriteHeader(204)
		return
	}
	bearer, err := sessionCapability(r.Header, "Bearer")
	if err != nil {
		b.sessionCapabilityFailure(w, err)
		return
	}
	switch r.URL.Path {
	case "/api/v1/auth/session":
		view, err := sessions.GetCurrentSession(r.Context(), bearer)
		if err != nil {
			b.sessionFailure(w, err)
			return
		}
		if view.AccountID.String() == "00000000-0000-0000-0000-000000000000" ||
			!privateUsername.MatchString(view.Username) || view.ExpiresAt.IsZero() {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		w.Header().Set("Session-Expires-At", utc(view.ExpiresAt))
		writeJSON(w, 200, map[string]string{"accountId": view.AccountID.String(), "username": view.Username,
			"expiresAt": utc(view.ExpiresAt)})
	case "/api/v1/auth/session-renewals":
		expires, err := sessions.RenewCurrentSession(r.Context(), bearer)
		if err != nil {
			b.sessionFailure(w, err)
			return
		}
		if expires.IsZero() {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		w.Header().Set("Session-Expires-At", utc(expires))
		writeJSON(w, 200, map[string]string{"expiresAt": utc(expires)})
	case "/api/v1/auth/devices":
		view, err := sessions.GetDevices(r.Context(), bearer)
		if err != nil {
			b.sessionFailure(w, err)
			return
		}
		if view.SignedInAt.IsZero() || view.ExpiresAt.IsZero() {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		response := map[string]any{"current": map[string]string{"role": "CURRENT", "signedInAt": utc(view.SignedInAt)}}
		if view.LastReplaced != nil {
			response["lastReplaced"] = map[string]string{"role": "REPLACED",
				"signedInAt": utc(view.LastReplaced.SignedInAt), "replacedAt": utc(view.LastReplaced.ReplacedAt)}
		}
		w.Header().Set("Session-Expires-At", utc(view.ExpiresAt))
		writeJSON(w, 200, response)
	default:
		b.fail(w, 404, "RESOURCE_NOT_FOUND", 0)
	}
}

func (b *boundary) sessionCapabilityFailure(w http.ResponseWriter, err error) {
	if errors.Is(err, errMalformed) {
		b.bad(w, err)
		return
	}
	b.fail(w, 401, "AUTHENTICATION_FAILED", 0)
}

func (b *boundary) sessionFailure(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, authprivacy.ErrAuthorizationUnavailable):
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
	case errors.Is(err, authprivacy.ErrAuthenticationFailed):
		b.fail(w, 401, "AUTHENTICATION_FAILED", 0)
	case errors.Is(err, authprivacy.ErrSessionInvalid):
		b.fail(w, 401, "SESSION_INVALID", 0)
	case errors.Is(err, authprivacy.ErrSessionReplaced):
		b.fail(w, 401, "session_replaced", 0)
	case errors.Is(err, authprivacy.ErrAccountUnavailable):
		b.fail(w, 403, "ACCOUNT_UNAVAILABLE", 0)
	case errors.Is(err, authprivacy.ErrCredentialStateChanged):
		b.fail(w, 409, "CREDENTIAL_STATE_CHANGED", 0)
	case errors.Is(err, authprivacy.ErrSessionCreatedReplay):
		b.fail(w, 409, "SESSION_CREATED_RETRY_LOGIN", 0)
	case errors.Is(err, authprivacy.ErrConflict):
		b.fail(w, 409, "IDEMPOTENCY_KEY_REUSED", 0)
	case errors.Is(err, authprivacy.ErrExpired):
		b.fail(w, 410, "RESULT_EXPIRED", 0)
	case errors.Is(err, authprivacy.ErrPasswordBusy):
		b.fail(w, 429, "RATE_LIMITED", 1)
	default:
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
	}
}
