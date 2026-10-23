package authprivacyhttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

type DirectMessageBackend interface {
	DMContact(context.Context, [32]byte, string, string) (authprivacy.PostResponse, error)
	DirectMessagesEnabled() bool
	SendDMText(context.Context, [32]byte, string, authprivacy.DMTextIntent) (authprivacy.PostResponse, error)
	GetDMCommand(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	ReadDMDirectory(context.Context, [32]byte, string, string) (authprivacy.PostResponse, error)
	PullDM(context.Context, [32]byte) (authprivacy.PostResponse, error)
	AcknowledgeDM(context.Context, [32]byte, []string, bool) (authprivacy.PostResponse, error)
}

func isDMPath(path string) bool {
	return path == "/api/v1/dm" || strings.HasPrefix(path, "/api/v1/dm/")
}
func dmRoute(path, method string) bool {
	if strings.HasPrefix(path, "/api/v1/dm/chat/") {
		return dmChatRoute(path, method)
	}
	switch path {
	case "/api/v1/dm/conversations", "/api/v1/dm/pending", "/api/v1/dm/contact":
		return method == "GET"
	case "/api/v1/dm/ack", "/api/v1/dm/read":
		return method == "POST"
	}
	if strings.HasPrefix(path, "/api/v1/dm/commands/") {
		id := strings.TrimPrefix(path, "/api/v1/dm/commands/")
		u, e := uuid.Parse(id)
		return e == nil && u != uuid.Nil && u.String() == id && (method == "PUT" || method == "GET")
	}
	return false
}
func (b *boundary) communityDM(w http.ResponseWriter, r *http.Request, backend DirectMessageBackend) {
	if !dmRoute(r.URL.Path, r.Method) {
		b.postFail(w, 404, "MALFORMED_REQUEST", 0)
		return
	}
	for _, h := range []string{"V-Installation-ID", "OTP-Flow-ID", "Reset-Intent-ID", "Credential-Change-ID", "Idempotency-Key", "Content-Encoding"} {
		if hasHeader(r.Header, h) {
			b.postBad(w, errMalformed)
			return
		}
	}
	bearer, e := sessionCapability(r.Header, "Bearer")
	if e != nil {
		b.postFail(w, 401, "AUTHENTICATION_FAILED", 0)
		return
	}
	if backend == nil || !backend.DirectMessagesEnabled() {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/api/v1/dm/chat/") {
		chat, _ := backend.(DirectMessageChatBackend)
		b.communityDMChat(w, r, chat, bearer)
		return
	}
	var result authprivacy.PostResponse
	switch r.URL.Path {
	case "/api/v1/dm/contact":
		q, err := url.ParseQuery(r.URL.RawQuery)
		if err != nil || q.Get("postId") == "" || r.ContentLength != 0 {
			b.postBad(w, errMalformed)
			return
		}
		for k, v := range q {
			if len(v) != 1 || (k != "postId" && k != "commentId") {
				b.postBad(w, errMalformed)
				return
			}
		}
		result, e = backend.DMContact(r.Context(), bearer, q.Get("postId"), q.Get("commentId"))
	case "/api/v1/dm/conversations":
		q, err := url.ParseQuery(r.URL.RawQuery)
		if err != nil || len(q) > 2 || q.Get("identityId") == "" {
			b.postBad(w, errMalformed)
			return
		}
		for k, v := range q {
			if len(v) != 1 || (k != "identityId" && k != "after") {
				b.postBad(w, errMalformed)
				return
			}
		}
		if r.ContentLength != 0 {
			b.postBad(w, errMalformed)
			return
		}
		result, e = backend.ReadDMDirectory(r.Context(), bearer, q.Get("identityId"), q.Get("after"))
	case "/api/v1/dm/pending":
		if noBodyOrQuery(r) != nil {
			b.postBad(w, errMalformed)
			return
		}
		result, e = backend.PullDM(r.Context(), bearer)
	case "/api/v1/dm/ack", "/api/v1/dm/read":
		if r.URL.RawQuery != "" {
			b.postBad(w, errMalformed)
			return
		}
		o, err := readRequestObject(r, 8192, []string{"messageIds"}, nil)
		if err != nil {
			b.postBad(w, err)
			return
		}
		raw, ok := o["messageIds"].([]any)
		if !ok || len(raw) == 0 || len(raw) > 100 {
			b.postBad(w, errMalformed)
			return
		}
		ids := make([]string, len(raw))
		for i, v := range raw {
			ids[i], ok = v.(string)
			if !ok {
				b.postBad(w, errMalformed)
				return
			}
		}
		result, e = backend.AcknowledgeDM(r.Context(), bearer, ids, r.URL.Path == "/api/v1/dm/read")
	default:
		id := strings.TrimPrefix(r.URL.Path, "/api/v1/dm/commands/")
		if r.Method == "GET" {
			if noBodyOrQuery(r) != nil {
				b.postBad(w, errMalformed)
				return
			}
			result, e = backend.GetDMCommand(r.Context(), bearer, id)
		} else {
			if r.URL.RawQuery != "" {
				b.postBad(w, errMalformed)
				return
			}
			fields := []string{"identityId", "peerId", "conversationId", "sourcePostId", "sourceCommentId", "text", "attempt"}
			o, err := readRequestObject(r, 100000, fields, nil)
			if err != nil {
				b.postBad(w, err)
				return
			}
			var in authprivacy.DMTextIntent
			destinations := []*string{&in.IdentityID, &in.PeerID, &in.ConversationID, &in.SourcePostID, &in.SourceCommentID, &in.Text}
			for i, p := range destinations {
				*p, err = stringField(o, fields[i])
				if err != nil {
					b.postBad(w, err)
					return
				}
			}
			in.Attempt, err = integerField(o, "attempt", 1, 1000)
			if err != nil {
				b.postBad(w, err)
				return
			}
			result, e = backend.SendDMText(r.Context(), bearer, id, in)
		}
	}
	if e != nil {
		b.postFailure(w, e)
		return
	}
	// Only dedicated DM DTOs may be serialized through this boundary.
	switch result.Value.(type) {
	case authprivacy.DMReceipt, authprivacy.DMDirectory, authprivacy.DMPending, authprivacy.DMApplied, authprivacy.DMContact:
	default:
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if !validPostTime(result.ServerTime) || !result.ExpiresAt.After(result.ServerTime) {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	payload, e := json.Marshal(result.Value)
	if e != nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Session-Expires-At", result.ExpiresAt.Format("2006-01-02T15:04:05.999999999Z07:00"))
	w.Header().Set("Server-Time", utc(result.ServerTime))
	w.WriteHeader(200)
	_, _ = w.Write(payload)
}
