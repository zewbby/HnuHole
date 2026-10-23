package authprivacyhttp

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

type IdentityAvatarBackend interface {
	UploadIdentityAvatar(context.Context, [32]byte, uuid.UUID, []byte, string) (time.Time, error)
	ReadIdentityAvatar(context.Context, [32]byte, uuid.UUID) (authprivacy.ImageBytes, time.Time, error)
	AbandonIdentityAvatar(context.Context, [32]byte, uuid.UUID) (time.Time, error)
}

const identityAvatarPath = "/api/v1/identity-avatars/"

func isIdentityAvatarPath(path string) bool { return strings.HasPrefix(path, identityAvatarPath) }
func identityAvatarPathID(path string) (uuid.UUID, error) {
	raw := strings.TrimPrefix(path, identityAvatarPath)
	id, e := uuid.Parse(raw)
	if !isIdentityAvatarPath(path) || e != nil || id == uuid.Nil || raw != id.String() {
		return uuid.Nil, errMalformed
	}
	return id, nil
}
func (b *boundary) identityAvatarFailure(w http.ResponseWriter, e error) {
	var f *authprivacy.PostError
	if errors.As(e, &f) && ((f.Code == "IDENTITY_AVATAR_INVALID" || f.Code == "IDENTITY_AVATAR_LIMIT") && f.Status == 409 || f.Code == "IDENTITY_AVATAR_NOT_FOUND" && f.Status == 404) {
		b.fail(w, f.Status, f.Code, 0)
		return
	}
	if errors.Is(e, postmedia.ErrInvalid) {
		b.fail(w, 422, "IDENTITY_AVATAR_INVALID", 0)
		return
	}
	if errors.Is(e, postmedia.ErrUnavailable) {
		b.fail(w, 503, "MEDIA_VALIDATOR_UNAVAILABLE", 0)
		return
	}
	b.identityFailure(w, e)
}
func (b *boundary) communityIdentityAvatar(w http.ResponseWriter, r *http.Request, backend IdentityAvatarBackend) {
	id, e := identityAvatarPathID(r.URL.Path)
	if e != nil || r.URL.RawPath != "" || r.URL.RawQuery != "" || r.URL.ForceQuery {
		b.bad(w, errMalformed)
		return
	}
	if r.Method != "GET" && r.Method != "PUT" && r.Method != "DELETE" {
		w.Header().Set("Allow", "GET, PUT, DELETE")
		b.fail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	for _, h := range []string{"V-Installation-ID", "OTP-Flow-ID", "Reset-Intent-ID", "Credential-Change-ID", "Idempotency-Key", "Content-Encoding", "Range", "If-None-Match", "If-Modified-Since"} {
		if hasHeader(r.Header, h) {
			b.bad(w, errMalformed)
			return
		}
	}
	token, e := sessionCapability(r.Header, "Bearer")
	if e != nil {
		b.sessionCapabilityFailure(w, e)
		return
	}
	if backend == nil {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if r.Method == "DELETE" {
		if noBodyOrQuery(r) != nil {
			b.bad(w, errMalformed)
			return
		}
		expiry, e := backend.AbandonIdentityAvatar(r.Context(), token, id)
		if e != nil {
			b.identityAvatarFailure(w, e)
			return
		}
		if expiry.IsZero() {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		w.Header().Set("Session-Expires-At", utc(expiry))
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method == "PUT" {
		mime, e := singleHeader(r.Header, "Content-Type")
		if e != nil || (mime != "image/png" && mime != "image/jpeg" && mime != "image/webp" && mime != "image/gif") {
			b.bad(w, errMediaType)
			return
		}
		if r.ContentLength > authprivacy.IdentityAvatarMaxBytes {
			b.bad(w, errTooLarge)
			return
		}
		data, e := io.ReadAll(io.LimitReader(r.Body, authprivacy.IdentityAvatarMaxBytes+1))
		if e != nil {
			b.bad(w, errMalformed)
			return
		}
		if len(data) > authprivacy.IdentityAvatarMaxBytes {
			b.bad(w, errTooLarge)
			return
		}
		expiry, e := backend.UploadIdentityAvatar(r.Context(), token, id, data, mime)
		if e != nil {
			b.identityAvatarFailure(w, e)
			return
		}
		if expiry.IsZero() {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		w.Header().Set("Session-Expires-At", utc(expiry))
		writeJSON(w, 200, struct {
			Avatar string `json:"avatar"`
		}{"avatar-v1:" + id.String()})
		return
	}
	if noBodyOrQuery(r) != nil {
		b.bad(w, errMalformed)
		return
	}
	result, expiry, e := backend.ReadIdentityAvatar(r.Context(), token, id)
	if e != nil {
		b.identityAvatarFailure(w, e)
		return
	}
	if expiry.IsZero() || result.MIME != "image/webp" || len(result.Bytes) < 12 || len(result.Bytes) > postmedia.MaxThumbnailBytes {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Content-Type", "image/webp")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Session-Expires-At", utc(expiry))
	w.WriteHeader(200)
	_, _ = w.Write(result.Bytes)
}
