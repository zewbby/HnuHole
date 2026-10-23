package authprivacyhttp

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"net/http"
	"strings"
)

type DirectMessageGovernanceBackend interface {
	DMBlocks(context.Context, [32]byte) (authprivacy.PostResponse, error)
	GetDMBlock(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	ChangeDMBlock(context.Context, [32]byte, string, authprivacy.DMBlockInput) (authprivacy.PostResponse, error)
	GetDMReport(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	SubmitDMReport(context.Context, [32]byte, string, authprivacy.DMReportInput) (authprivacy.PostResponse, error)
}

func dmGovernanceRoute(path, method string) bool {
	if path == "/api/v1/dm/governance/blocks" {
		return method == "GET"
	}
	for _, prefix := range []string{"/api/v1/dm/governance/blocks/", "/api/v1/dm/governance/reports/"} {
		if strings.HasPrefix(path, prefix) {
			id := strings.TrimPrefix(path, prefix)
			u, e := uuid.Parse(id)
			return e == nil && u != uuid.Nil && u.String() == id && (method == "GET" || method == "PUT")
		}
	}
	return false
}
func (b *boundary) communityDMGovernance(w http.ResponseWriter, r *http.Request, backend DirectMessageGovernanceBackend, bearer [32]byte) {
	if backend == nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	var result authprivacy.PostResponse
	var e error
	path := r.URL.Path
	id := path[strings.LastIndex(path, "/")+1:]
	report := strings.Contains(path, "/reports/")
	if r.Method == "GET" {
		if noBodyOrQuery(r) != nil {
			b.postBad(w, errMalformed)
			return
		}
		if path == "/api/v1/dm/governance/blocks" {
			result, e = backend.DMBlocks(r.Context(), bearer)
		} else if report {
			result, e = backend.GetDMReport(r.Context(), bearer, id)
		} else {
			result, e = backend.GetDMBlock(r.Context(), bearer, id)
		}
	} else {
		if r.URL.RawQuery != "" {
			b.postBad(w, errMalformed)
			return
		}
		fields := []string{"identityId", "conversationId", "blocked"}
		var optional []string
		limit := int64(8192)
		if report {
			fields = []string{"identityId", "conversationId", "firstSequence", "lastSequence", "reason", "description", "images", "authorized", "entries"}
			optional = []string{"retryToken"}
			limit = 48 * 1024 * 1024
		}
		object, err := readRequestObject(r, limit, fields, optional)
		if err != nil {
			b.postBad(w, err)
			return
		}
		raw, _ := json.Marshal(object)
		dec := json.NewDecoder(bytes.NewReader(raw))
		dec.DisallowUnknownFields()
		if report {
			var in authprivacy.DMReportInput
			if dec.Decode(&in) != nil {
				b.postBad(w, errMalformed)
				return
			}
			result, e = backend.SubmitDMReport(r.Context(), bearer, id, in)
		} else {
			var in authprivacy.DMBlockInput
			if dec.Decode(&in) != nil {
				b.postBad(w, errMalformed)
				return
			}
			result, e = backend.ChangeDMBlock(r.Context(), bearer, id, in)
		}
	}
	if e != nil {
		b.moderationFailure(w, e)
		return
	}
	switch result.Value.(type) {
	case authprivacy.DMBlocks, authprivacy.DMBlockResult, moderation.ReportResult:
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
