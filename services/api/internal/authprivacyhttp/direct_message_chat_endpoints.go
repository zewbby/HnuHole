package authprivacyhttp

import (
	"context"
	"encoding/json"
	"github.com/google/uuid"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

type DirectMessageChatBackend interface {
	SendDMImage(context.Context, [32]byte, string, authprivacy.DMImageIntent) (authprivacy.PostResponse, error)
	ReadDMPrivateMedia(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	ReadDMChatDirectory(context.Context, [32]byte, string, string) (authprivacy.PostResponse, error)
	PullDMChat(context.Context, [32]byte) (authprivacy.PostResponse, error)
	GetDMChatOperation(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	ExecuteDMChatOperation(context.Context, [32]byte, string, authprivacy.DMChatOperation) (authprivacy.PostResponse, error)
	PullDMControls(context.Context, [32]byte, int64) (authprivacy.PostResponse, error)
}

func dmChatRoute(path, method string) bool {
	switch path {
	case "/api/v1/dm/chat/conversations", "/api/v1/dm/chat/pending", "/api/v1/dm/chat/controls":
		return method == "GET"
	}
	for _, prefix := range []string{"/api/v1/dm/chat/images/", "/api/v1/dm/chat/media/", "/api/v1/dm/chat/operations/"} {
		if strings.HasPrefix(path, prefix) {
			id := strings.TrimPrefix(path, prefix)
			u, e := uuid.Parse(id)
			if e != nil || u == uuid.Nil || u.String() != id {
				return false
			}
			switch prefix {
			case "/api/v1/dm/chat/images/":
				return method == "PUT"
			case "/api/v1/dm/chat/media/":
				return method == "GET"
			default:
				return method == "GET" || method == "PUT"
			}
		}
	}
	return false
}
func (b *boundary) communityDMChat(w http.ResponseWriter, r *http.Request, backend DirectMessageChatBackend, bearer [32]byte) {
	if backend == nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	var result authprivacy.PostResponse
	var e error
	path := r.URL.Path
	switch path {
	case "/api/v1/dm/chat/pending":
		if noBodyOrQuery(r) != nil {
			b.postBad(w, errMalformed)
			return
		}
		result, e = backend.PullDMChat(r.Context(), bearer)
	case "/api/v1/dm/chat/conversations", "/api/v1/dm/chat/controls":
		q, err := url.ParseQuery(r.URL.RawQuery)
		if err != nil || r.ContentLength != 0 {
			b.postBad(w, errMalformed)
			return
		}
		controls := strings.HasSuffix(path, "/controls")
		for k, v := range q {
			if len(v) != 1 || (k != "after" && (controls || k != "identityId")) {
				b.postBad(w, errMalformed)
				return
			}
		}
		if controls {
			after := int64(0)
			if q.Has("after") {
				after, err = strconv.ParseInt(q.Get("after"), 10, 64)
			}
			if err != nil || after < 0 {
				b.postBad(w, errMalformed)
				return
			}
			result, e = backend.PullDMControls(r.Context(), bearer, after)
		} else {
			if q.Get("identityId") == "" {
				b.postBad(w, errMalformed)
				return
			}
			result, e = backend.ReadDMChatDirectory(r.Context(), bearer, q.Get("identityId"), q.Get("after"))
		}
	default:
		id := path[strings.LastIndex(path, "/")+1:]
		if r.Method == "GET" {
			if noBodyOrQuery(r) != nil {
				b.postBad(w, errMalformed)
				return
			}
			if strings.Contains(path, "/media/") {
				result, e = backend.ReadDMPrivateMedia(r.Context(), bearer, id)
			} else {
				result, e = backend.GetDMChatOperation(r.Context(), bearer, id)
			}
		} else {
			if r.URL.RawQuery != "" {
				b.postBad(w, errMalformed)
				return
			}
			if strings.Contains(path, "/images/") {
				fields := []string{"identityId", "peerId", "conversationId", "groupId", "position", "groupSize", "mediaId", "sha256", "byteLength", "mimeType", "width", "height", "data", "attempt"}
				o, err := readRequestObject(r, 14*1024*1024+8192, fields, nil)
				if err != nil {
					b.postBad(w, err)
					return
				}
				raw, _ := json.Marshal(o)
				var in authprivacy.DMImageIntent
				if json.Unmarshal(raw, &in) != nil {
					b.postBad(w, errMalformed)
					return
				}
				result, e = backend.SendDMImage(r.Context(), bearer, id, in)
			} else {
				o, err := readRequestObject(r, 8192, []string{"identityId", "conversationId", "operation", "expectedVersion"}, []string{"pinned", "muted", "note", "throughSequence", "messageId"})
				if err != nil {
					b.postBad(w, err)
					return
				}
				if o["operation"] == "SETTINGS" {
					for _, f := range []string{"pinned", "muted", "note"} {
						if _, ok := o[f]; !ok {
							b.postBad(w, errMalformed)
							return
						}
					}
				}
				if o["operation"] == "DELETE" {
					if _, ok := o["throughSequence"]; !ok {
						b.postBad(w, errMalformed)
						return
					}
				}
				raw, _ := json.Marshal(o)
				var in authprivacy.DMChatOperation
				if json.Unmarshal(raw, &in) != nil {
					b.postBad(w, errMalformed)
					return
				}
				result, e = backend.ExecuteDMChatOperation(r.Context(), bearer, id, in)
			}
		}
	}
	if e != nil {
		b.postFailure(w, e)
		return
	}
	switch result.Value.(type) {
	case authprivacy.DMReceipt, authprivacy.DMPrivateMedia, authprivacy.DMChatDirectory, authprivacy.DMChatPending, authprivacy.DMChatResult, authprivacy.DMControls:
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
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Session-Expires-At", result.ExpiresAt.Format("2006-01-02T15:04:05.999999999Z07:00"))
	w.Header().Set("Server-Time", utc(result.ServerTime))
	w.WriteHeader(200)
	_, _ = w.Write(payload)
}
