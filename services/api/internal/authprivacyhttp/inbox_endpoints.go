package authprivacyhttp

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type InboxBackend interface {
	ReadInbox(context.Context, [32]byte, authprivacy.InboxQuery) (authprivacy.PostResponse, error)
	ReadInboxCounts(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	MarkInboxRead(context.Context, [32]byte, string, string, int64) (authprivacy.PostResponse, error)
}

func isInboxPath(path string) bool {
	return path == "/api/v1/notifications" || strings.HasPrefix(path, "/api/v1/notifications/")
}
func allowsInboxQuery(r *http.Request) bool {
	kind, _, method := inboxRoute(r.URL.Path)
	return kind != "" && r.Method == method
}
func inboxRoute(path string) (kind, id, method string) {
	method = "GET"
	parts := strings.Split(strings.TrimPrefix(path, "/api/v1/"), "/")
	if len(parts) == 1 && parts[0] == "notifications" {
		return "list", "", method
	}
	if len(parts) == 2 && parts[0] == "notifications" && parts[1] == "unread-counts" {
		return "counts", "", method
	}
	if len(parts) == 3 && parts[0] == "notifications" && parts[2] == "read" {
		return "read", parts[1], "POST"
	}
	return "", "", ""
}
func (b *boundary) communityInbox(w http.ResponseWriter, r *http.Request, backend InboxBackend) {
	kind, id, method := inboxRoute(r.URL.Path)
	if kind == "" || r.URL.RawPath != "" {
		b.postBad(w, errMalformed)
		return
	}
	if r.Method != method {
		w.Header().Set("Allow", method)
		b.postFail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	if backend == nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	for _, h := range []string{"Content-Encoding", "Idempotency-Key", "V-Installation-ID", "OTP-Flow-ID", "Reset-Intent-ID", "Credential-Change-ID"} {
		if hasHeader(r.Header, h) {
			b.postBad(w, errMalformed)
			return
		}
	}
	bearer, e := capability(r.Header, "Bearer")
	if e != nil {
		b.postFail(w, 401, "SESSION_INVALID", 0)
		return
	}
	query, e := url.ParseQuery(r.URL.RawQuery)
	if e != nil {
		b.postBad(w, errMalformed)
		return
	}
	allowed := map[string]bool{"identityId": true}
	if kind == "list" {
		allowed["category"] = true
		allowed["cursor"] = true
		allowed["unreadOnly"] = true
		allowed["limit"] = true
	}
	for k, v := range query {
		if !allowed[k] || len(v) != 1 || v[0] == "" {
			b.postBad(w, errMalformed)
			return
		}
	}
	q := authprivacy.InboxQuery{IdentityID: query.Get("identityId"), Category: query.Get("category"), Cursor: query.Get("cursor")}
	if raw := query.Get("limit"); raw != "" {
		q.Limit, e = strconv.Atoi(raw)
		if e != nil || strconv.Itoa(q.Limit) != raw || q.Limit < 1 || q.Limit > 50 {
			b.postBad(w, errMalformed)
			return
		}
	}
	if raw := query.Get("unreadOnly"); raw != "" {
		if raw != "true" && raw != "false" {
			b.postBad(w, errMalformed)
			return
		}
		q.UnreadOnly = raw == "true"
	}
	var response authprivacy.PostResponse
	if method == "GET" {
		if r.Body != nil {
			raw, er := io.ReadAll(io.LimitReader(r.Body, 1))
			if er != nil || len(raw) > 0 {
				b.postBad(w, errMalformed)
				return
			}
		}
		switch kind {
		case "list":
			response, e = backend.ReadInbox(r.Context(), bearer, q)
		case "counts":
			response, e = backend.ReadInboxCounts(r.Context(), bearer, q.IdentityID)
		}
	} else {
		// This route has a validated identity query; preserve the shared JSON
		// parser's no-query invariant for every other command route.
		bodyRequest := r.Clone(r.Context())
		bodyURL := *r.URL
		bodyURL.RawQuery = ""
		bodyRequest.URL = &bodyURL
		object, er := readRequestObjectPolicy(bodyRequest, 1024, []string{"seenVersion"}, nil, false)
		if er != nil {
			b.postBad(w, errMalformed)
			return
		}
		version, er := integerField(object, "seenVersion", 1, 9007199254740991)
		if er != nil {
			b.postBad(w, errMalformed)
			return
		}
		response, e = backend.MarkInboxRead(r.Context(), bearer, id, q.IdentityID, int64(version))
	}
	if e != nil {
		var failure *authprivacy.PostError
		if errors.As(e, &failure) && failure.Status == 404 && (failure.Code == "IDENTITY_UNAVAILABLE" || failure.Code == "NOTIFICATION_NOT_FOUND" || failure.Code == "POST_UNAVAILABLE") {
			b.postFail(w, 404, failure.Code, 0)
			return
		}
		if errors.Is(e, authprivacy.ErrIntentInvalid) || errors.Is(e, posts.ErrInvalidID) {
			b.postBad(w, errMalformed)
			return
		}
		b.postFailure(w, e)
		return
	}
	if response.ServerTime.IsZero() || !response.ExpiresAt.After(response.ServerTime) {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Session-Expires-At", response.ExpiresAt.UTC().Format(time.RFC3339Nano))
	w.Header().Set("Server-Time", response.ServerTime.UTC().Format(time.RFC3339Nano))
	writeJSON(w, 200, response.Value)
}
