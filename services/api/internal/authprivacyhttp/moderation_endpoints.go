package authprivacyhttp

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
)

type ModerationBackend interface {
	SubmitReport(context.Context, [32]byte, string, moderation.ReportInput) (authprivacy.PostResponse, error)
	GetReport(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	ReadSystemNotifications(context.Context, [32]byte, string, string, string, int, bool) (authprivacy.PostResponse, error)
	ReadSanction(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	ReadAppeal(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	GetAppealRequest(context.Context, [32]byte, string, string, bool) (authprivacy.PostResponse, error)
	SubmitAppeal(context.Context, [32]byte, string, string, moderation.Material, bool) (authprivacy.PostResponse, error)
	ReadModeration(context.Context, [32]byte, string, string, string, string, int) (authprivacy.PostResponse, error)
	ExecuteModeration(context.Context, [32]byte, string, string, moderation.Decision) (authprivacy.PostResponse, error)
	ReadModerationMaterials(context.Context, [32]byte, string, string, string, bool) (authprivacy.PostResponse, error)
}

var _ ModerationBackend = (*authprivacy.Community)(nil)

type moderationRoute struct {
	kind, id, parent, request, method string
	list, appendMaterial              bool
}

func isModerationPath(path string) bool {
	for _, p := range []string{"reports", "system-notifications", "sanctions", "appeals", "moderation"} {
		prefix := "/api/v1/" + p
		if path == prefix || strings.HasPrefix(path, prefix+"/") {
			return true
		}
	}
	return false
}
func parseModerationRoute(path string) (moderationRoute, error) {
	p := strings.Split(strings.TrimPrefix(path, "/api/v1/"), "/")
	r := moderationRoute{method: "GET"}
	if !strings.HasPrefix(path, "/api/v1/") {
		return r, errMalformed
	}
	switch {
	case len(p) == 3 && p[0] == "appeals" && p[2] == "materials":
		r.kind = "self-materials"
		r.id = p[1]
		r.list = true
	case len(p) == 4 && p[0] == "moderation" && p[1] == "appeals" && p[3] == "materials":
		r.kind = "admin-materials"
		r.id = p[2]
		r.list = true
	case len(p) == 4 && p[0] == "moderation" && p[1] == "cases" && p[3] == "reports":
		r.kind = "admin-reports"
		r.id = p[2]
		r.list = true
	case len(p) == 2 && p[0] == "reports":
		r.kind = "report"
		r.id = p[1]
		r.method = "GET, PUT"
	case p[0] == "system-notifications" && len(p) == 1:
		r.kind = "notifications"
		r.list = true
	case p[0] == "system-notifications" && len(p) == 2:
		r.kind = "notification"
		r.id = p[1]
	case p[0] == "system-notifications" && len(p) == 3 && p[2] == "read":
		r.kind = "read"
		r.id = p[1]
		r.method = "POST"
	case p[0] == "sanctions" && len(p) == 2:
		r.kind = "sanction"
		r.id = p[1]
	case p[0] == "sanctions" && len(p) == 4 && (p[2] == "appeals" || p[2] == "appeal-requests"):
		r.kind = "appeal-request"
		r.parent = p[1]
		r.request = p[3]
		if p[2] == "appeals" {
			r.method = "PUT"
		}
	case p[0] == "appeals" && len(p) == 2:
		r.kind = "appeal"
		r.id = p[1]
	case p[0] == "appeals" && len(p) == 4 && (p[2] == "materials" || p[2] == "material-requests"):
		r.kind = "appeal-request"
		r.parent = p[1]
		r.request = p[3]
		r.appendMaterial = true
		if p[2] == "materials" {
			r.method = "PUT"
		}
	case p[0] == "moderation" && len(p) == 2:
		switch p[1] {
		case "me":
			r.kind = "admin-me"
		case "cases":
			r.kind = "admin-cases"
			r.list = true
		case "appeals":
			r.kind = "admin-appeals"
			r.list = true
		case "accounts":
			r.kind = "admin-accounts"
			r.list = true
		case "audit":
			r.kind = "admin-audit"
			r.list = true
		default:
			return r, errMalformed
		}
	case p[0] == "moderation" && len(p) == 3 && (p[1] == "cases" || p[1] == "appeals"):
		r.id = p[2]
		r.kind = "admin-case"
		if p[1] == "appeals" {
			r.kind = "admin-appeal"
		}
	case p[0] == "moderation" && len(p) == 4 && p[1] == "cases" && (p[3] == "claim" || p[3] == "decision"):
		r.kind = p[3]
		r.id = p[2]
		r.method = "POST"
	case p[0] == "moderation" && len(p) == 4 && p[1] == "appeals" && p[3] == "decision":
		r.kind = "appeal-decision"
		r.id = p[2]
		r.method = "POST"
	case p[0] == "moderation" && len(p) == 4 && p[1] == "sanctions" && p[3] == "revoke":
		r.kind = "revoke"
		r.id = p[2]
		r.method = "POST"
	case p[0] == "moderation" && len(p) == 3 && p[1] == "roles":
		r.kind = "role"
		r.id = p[2]
		r.method = "PUT"
		if len(r.id) != 6 || strings.Trim(r.id, "0123456789") != "" {
			return r, errMalformed
		}
		return r, nil
	default:
		return r, errMalformed
	}
	for _, id := range []string{r.id, r.parent, r.request} {
		if id != "" && !moderation.ValidID(id) {
			return r, errMalformed
		}
	}
	return r, nil
}
func allowsModerationQuery(r *http.Request) bool {
	route, e := parseModerationRoute(r.URL.Path)
	return e == nil && (route.list && r.Method == "GET" || (route.kind == "notification" && r.Method == "GET") || (route.kind == "read" && r.Method == "POST"))
}
func moderationObject(r *http.Request, required, optional []string) (map[string]any, error) {
	rawType, e := singleHeader(r.Header, "Content-Type")
	if e != nil {
		return nil, e
	}
	typ, params, e := mime.ParseMediaType(rawType)
	if e != nil || typ != "application/json" || len(params) > 1 || params["charset"] != "" && !strings.EqualFold(params["charset"], "utf-8") {
		return nil, errMediaType
	}
	b, e := io.ReadAll(io.LimitReader(r.Body, 12*1024*1024+1))
	if e != nil || len(b) > 12*1024*1024 || !utf8.Valid(b) || !validEscapedScalars(b) {
		return nil, errMalformed
	}
	d := json.NewDecoder(bytes.NewReader(b))
	d.UseNumber()
	v, e := moderationValue(d, 0)
	if e != nil {
		return nil, e
	}
	if _, e = d.Token(); !errors.Is(e, io.EOF) {
		return nil, errMalformed
	}
	object, ok := v.(map[string]any)
	if !ok || fields(object, required, optional) != nil {
		return nil, errMalformed
	}
	return object, nil
}
func moderationValue(d *json.Decoder, depth int) (any, error) {
	if depth > 8 {
		return nil, errMalformed
	}
	t, e := d.Token()
	if e != nil {
		return nil, errMalformed
	}
	delim, ok := t.(json.Delim)
	if !ok {
		return t, nil
	}
	switch delim {
	case '{':
		o := map[string]any{}
		for d.More() {
			k, e := d.Token()
			s, ok := k.(string)
			if e != nil || !ok {
				return nil, errMalformed
			}
			if _, exists := o[s]; exists {
				return nil, errMalformed
			}
			v, e := moderationValue(d, depth+1)
			if e != nil {
				return nil, e
			}
			o[s] = v
		}
		end, e := d.Token()
		if e != nil || end != json.Delim('}') {
			return nil, errMalformed
		}
		return o, nil
	case '[':
		a := []any{}
		for d.More() {
			v, e := moderationValue(d, depth+1)
			if e != nil {
				return nil, e
			}
			a = append(a, v)
		}
		end, e := d.Token()
		if e != nil || end != json.Delim(']') {
			return nil, errMalformed
		}
		return a, nil
	}
	return nil, errMalformed
}
func decodeModerationObject(o map[string]any, v any) error {
	for k, value := range o {
		if value == nil && k != "identityId" {
			return errMalformed
		}
		switch k {
		case "postId", "reason", "description", "commandId", "action", "role":
			if _, ok := value.(string); !ok {
				return errMalformed
			}
		case "accept":
			if _, ok := value.(bool); !ok {
				return errMalformed
			}
		}
	}

	if images, exists := o["images"]; exists {
		items, ok := images.([]any)
		if !ok {
			return errMalformed
		}
		for _, item := range items {
			m, ok := item.(map[string]any)
			if !ok || fields(m, []string{"mime", "base64"}, nil) != nil {
				return errMalformed
			}
			if _, e := stringField(m, "mime"); e != nil {
				return e
			}
			if _, e := stringField(m, "base64"); e != nil {
				return e
			}
		}
	}
	b, e := json.Marshal(o)
	if e != nil {
		return e
	}
	return json.Unmarshal(b, v)
}
func (b *boundary) moderationFailure(w http.ResponseWriter, e error) {
	var p *authprivacy.PostError
	if errors.As(e, &p) && p.Status >= 400 && p.Status <= 503 {
		b.postFail(w, p.Status, p.Code, 0)
		return
	}
	if errors.Is(e, moderation.ErrInvalid) || errors.Is(e, errMalformed) {
		b.postFail(w, 400, "MALFORMED_REQUEST", 0)
		return
	}
	b.postFailure(w, e)
}
func (b *boundary) communityModeration(w http.ResponseWriter, r *http.Request, backend ModerationBackend) {
	route, e := parseModerationRoute(r.URL.Path)
	if e != nil || r.URL.RawPath != "" {
		b.moderationFailure(w, errMalformed)
		return
	}
	if !strings.Contains(", "+route.method+",", ", "+r.Method+",") {
		w.Header().Set("Allow", route.method)
		b.postFail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	if backend == nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	for _, header := range []string{"Content-Encoding", "Idempotency-Key", "V-Installation-ID", "OTP-Flow-ID", "Reset-Intent-ID", "Credential-Change-ID"} {
		if hasHeader(r.Header, header) {
			b.moderationFailure(w, errMalformed)
			return
		}
	}
	bearer, e := capability(r.Header, "Bearer")
	if e != nil {
		b.postFail(w, 401, "SESSION_INVALID", 0)
		return
	}
	values, e := url.ParseQuery(r.URL.RawQuery)
	if e != nil {
		b.moderationFailure(w, errMalformed)
		return
	}
	allowed := map[string]bool{}
	switch route.kind {
	case "self-materials", "admin-materials", "admin-reports":
		allowed = map[string]bool{"cursor": true}
	case "notifications":
		allowed = map[string]bool{"identityId": true, "before": true, "limit": true}
	case "notification", "read":
		allowed = map[string]bool{"identityId": true}
	case "admin-cases", "admin-appeals":
		allowed = map[string]bool{"before": true, "limit": true}
	case "admin-accounts":
		allowed = map[string]bool{"number": true, "before": true, "limit": true}
	case "admin-audit":
		allowed = map[string]bool{"caseId": true}
	}
	for k, v := range values {
		if !allowed[k] || len(v) != 1 || v[0] == "" {
			b.moderationFailure(w, errMalformed)
			return
		}
	}
	limit := 50
	if raw := values.Get("limit"); raw != "" {
		limit, e = strconv.Atoi(raw)
		if e != nil || limit < 1 || limit > 50 || strconv.Itoa(limit) != raw {
			b.moderationFailure(w, errMalformed)
			return
		}
	}
	var response authprivacy.PostResponse
	if r.Method == "GET" {
		if r.Body != nil {
			bb, e := io.ReadAll(io.LimitReader(r.Body, 1))
			if e != nil || len(bb) > 0 {
				b.moderationFailure(w, errMalformed)
				return
			}
		}
		switch route.kind {
		case "self-materials", "admin-materials", "admin-reports":
			kind := "APPEAL"
			if route.kind == "admin-reports" {
				kind = "REPORT"
			}
			response, e = backend.ReadModerationMaterials(r.Context(), bearer, kind, route.id, values.Get("cursor"), route.kind != "self-materials")
		case "report":
			response, e = backend.GetReport(r.Context(), bearer, route.id)
		case "notifications", "notification":
			response, e = backend.ReadSystemNotifications(r.Context(), bearer, route.id, values.Get("identityId"), values.Get("before"), limit, false)
		case "sanction":
			response, e = backend.ReadSanction(r.Context(), bearer, route.id)
		case "appeal":
			response, e = backend.ReadAppeal(r.Context(), bearer, route.id)
		case "appeal-request":
			response, e = backend.GetAppealRequest(r.Context(), bearer, route.parent, route.request, route.appendMaterial)
		default:
			kind := strings.TrimPrefix(route.kind, "admin-")
			id := route.id
			if kind == "audit" {
				id = values.Get("caseId")
			}
			response, e = backend.ReadModeration(r.Context(), bearer, kind, id, values.Get("number"), values.Get("before"), limit)
		}
	} else {
		switch route.kind {
		case "report":
			o, err := moderationObject(r, []string{"postId", "reason", "description", "images"}, []string{"identityId", "retryToken"})
			var input moderation.ReportInput
			if err == nil {
				err = decodeModerationObject(o, &input)
			}
			if err != nil {
				b.moderationFailure(w, errMalformed)
				return
			}
			response, e = backend.SubmitReport(r.Context(), bearer, route.id, input)
		case "appeal-request":
			o, err := moderationObject(r, []string{"description", "images"}, []string{"retryToken"})
			var m moderation.Material
			if err == nil {
				err = decodeModerationObject(o, &m)
			}
			if err != nil {
				b.moderationFailure(w, errMalformed)
				return
			}
			response, e = backend.SubmitAppeal(r.Context(), bearer, route.parent, route.request, m, route.appendMaterial)
		case "read":
			_, err := moderationObject(r, nil, nil)
			if err != nil {
				b.moderationFailure(w, errMalformed)
				return
			}
			response, e = backend.ReadSystemNotifications(r.Context(), bearer, route.id, values.Get("identityId"), "", 50, true)
		default:
			required := []string{"commandId", "reason"}
			switch route.kind {
			case "decision":
				required = append(required, "expectedVersion", "action", "days")
			case "claim":
				required = []string{"commandId", "expectedVersion"}
			case "appeal-decision":
				required = append(required, "expectedVersion", "accept")
			case "role":
				required = append(required, "role")
			}
			o, err := moderationObject(r, required, nil)
			var d moderation.Decision
			if err == nil {
				err = decodeModerationObject(o, &d)
			}
			if err != nil {
				b.moderationFailure(w, errMalformed)
				return
			}
			response, e = backend.ExecuteModeration(r.Context(), bearer, route.kind, route.id, d)
		}
	}
	if e != nil {
		b.moderationFailure(w, e)
		return
	}
	if !validPostTime(response.ExpiresAt) || !validPostTime(response.ServerTime) || !response.ExpiresAt.After(response.ServerTime) {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	encoded, e := json.Marshal(response.Value)
	if e != nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Session-Expires-At", utc(response.ExpiresAt))
	w.Header().Set("Server-Time", utc(response.ServerTime))
	w.WriteHeader(200)
	_, _ = w.Write(append(encoded, '\n'))
}
