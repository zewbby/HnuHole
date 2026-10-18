package authprivacyhttp

import (
	"context"
	"net/http"
	"unicode/utf8"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type ModerationAccessBackend interface {
	CreateModerationAccessSession(context.Context, authprivacy.ModerationAccessRequest, authprivacy.PasswordVerifier) (authprivacy.ModerationAccessResult, error)
	RevokeModerationAccessSession(context.Context, [32]byte) error
}

func (b *boundary) communityModerationAccessPublic(w http.ResponseWriter, r *http.Request, backend ModerationAccessBackend, passwords PasswordPreparer) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		b.fail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	if backend == nil {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if hasHeader(r.Header, "Idempotency-Key") || hasHeader(r.Header, "V-Installation-ID") || hasHeader(r.Header, "OTP-Flow-ID") || hasHeader(r.Header, "Reset-Intent-ID") || hasHeader(r.Header, "Credential-Change-ID") {
		b.bad(w, errMalformed)
		return
	}
	if r.URL.Path == "/api/v1/moderation-access/session-revocations" {
		if err := noBodyOrQuery(r); err != nil {
			b.bad(w, err)
			return
		}
		token, err := sessionCapability(r.Header, "Bearer")
		if err != nil {
			b.sessionCapabilityFailure(w, err)
			return
		}
		if err = backend.RevokeModerationAccessSession(r.Context(), token); err != nil {
			b.sessionFailure(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if hasHeader(r.Header, "Authorization") {
		b.bad(w, errMalformed)
		return
	}
	object, err := readRequestObject(r, 8192, []string{"username", "password"}, nil)
	if err != nil {
		b.bad(w, err)
		return
	}
	username, e1 := stringField(object, "username")
	password, e2 := stringField(object, "password")
	if e1 != nil || e2 != nil || !privateUsername.MatchString(username) || password == "" || len(password) > 2048 || !utf8.ValidString(password) || utf8.RuneCountInString(password) > 512 {
		b.bad(w, errMalformed)
		return
	}
	created, err := backend.CreateModerationAccessSession(r.Context(), authprivacy.ModerationAccessRequest{Username: username, Password: password}, passwords)
	if err != nil {
		b.sessionFailure(w, err)
		return
	}
	if created.SessionToken == ([32]byte{}) || created.Subject == ([32]byte{}) || created.ExpiresAt.IsZero() {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Session-Expires-At", utc(created.ExpiresAt))
	writeJSON(w, http.StatusCreated, map[string]string{"sessionToken": protocol.EncodeCanonicalBase64url(created.SessionToken[:]), "moderationSubject": protocol.EncodeCanonicalBase64url(created.Subject[:]), "expiresAt": utc(created.ExpiresAt), "scope": "MODERATION_SELF"})
}
