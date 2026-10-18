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
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type CommentBackend interface {
	ExecuteCommentCommand(context.Context, [32]byte, string, comments.Intent) (authprivacy.PostResponse, error)
	GetCommentCommand(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	SealCommentCommand(context.Context, [32]byte, string, comments.Operation, [32]byte) (authprivacy.PostResponse, error)
	GetOwnCommentTask(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	ReadComments(context.Context, [32]byte, authprivacy.CommentQuery) (authprivacy.PostResponse, error)
}
type commentRoute struct{ id, post, kind, methods string }

func isCommentPath(path string) bool {
	return path == "/api/v1/comment-commands" || strings.HasPrefix(path, "/api/v1/comment-commands/") || path == "/api/v1/me/comment-tasks" || strings.HasPrefix(path, "/api/v1/me/comment-tasks/") || strings.HasPrefix(path, "/api/v1/posts/") && (strings.HasSuffix(path, "/comments") || strings.HasSuffix(path,"/replies"))
}
func parseCommentRoute(path string) (commentRoute, error) {
	parts := strings.Split(strings.TrimPrefix(path, "/api/v1/"), "/")
	r := commentRoute{methods: "GET"}
	switch {
	case len(parts) == 2 && parts[0] == "comment-commands":
		r.id = parts[1]
		r.kind = "command"
		r.methods = "GET, PUT"
	case len(parts) == 3 && parts[0] == "comment-commands" && parts[2] == "seal":
		r.id = parts[1]
		r.kind = "seal"
		r.methods = "POST"
	case len(parts) == 3 && parts[0] == "me" && parts[1] == "comment-tasks":
		r.id = parts[2]
		r.kind = "task"
	case len(parts) == 3 && parts[0] == "posts" && parts[2] == "comments":
		r.id = parts[1]
		r.kind = "main"
	case len(parts) == 5 && parts[0] == "posts" && parts[2] == "comments" && parts[4]=="replies":
		r.id = parts[3]
		r.post=parts[1]
		if _,e:=posts.ParseResourceID(r.post);e!=nil{return r,e}
		r.kind = "replies"
	default:
		return r, errMalformed
	}
	var e error
	if r.kind == "command" || r.kind == "seal" {
		_, e = comments.ParseCommandKey(r.id)
	} else {
		_, e = posts.ParseResourceID(r.id)
	}
	return r, e
}
func allowsCommentListQuery(r *http.Request) bool {
	route, e := parseCommentRoute(r.URL.Path)
	return e == nil && r.Method == "GET" && (route.kind == "main" || route.kind == "replies")
}
func (b *boundary) communityCommentsPublic(w http.ResponseWriter, r *http.Request, backend CommentBackend) {
	route, e := parseCommentRoute(r.URL.Path)
	if e != nil || r.URL.RawPath != "" {
		b.postBad(w, errMalformed)
		return
	}
	if !strings.Contains(", "+route.methods+", ", ", "+r.Method+", ") {
		w.Header().Set("Allow", route.methods)
		b.postFail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	for _, header := range []string{"Idempotency-Key", "V-Installation-ID", "OTP-Flow-ID", "Reset-Intent-ID", "Credential-Change-ID", "Content-Encoding"} {
		if hasHeader(r.Header, header) {
			b.postBad(w, errMalformed)
			return
		}
	}
	if hasHeader(r.Header, "Authorization") {
		if _, e = singleHeader(r.Header, "Authorization"); e != nil {
			b.postBad(w, e)
			return
		}
	}
	bearer, e := sessionCapability(r.Header, "Bearer")
	if e != nil {
		if errors.Is(e, errMalformed) {
			b.postBad(w, e)
		} else {
			b.postFail(w, 401, "AUTHENTICATION_FAILED", 0)
		}
		return
	}
	if backend == nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	var response authprivacy.PostResponse
	if r.Method == "GET" {
		if r.Body != nil {
			body, e := io.ReadAll(io.LimitReader(r.Body, 1))
			if e != nil || len(body) != 0 {
				b.postBad(w, errMalformed)
				return
			}
		}
		switch route.kind {
		case "command":
			response, e = backend.GetCommentCommand(r.Context(), bearer, route.id)
		case "task":
			response, e = backend.GetOwnCommentTask(r.Context(), bearer, route.id)
		default:
			q := authprivacy.CommentQuery{ID: route.id,PostID:route.post, Replies: route.kind == "replies", Limit: 50}
			var values url.Values
			values, e = url.ParseQuery(r.URL.RawQuery)
			if e == nil {
				for name, items := range values {
					if len(items) != 1 || items[0] == "" {
						e = errMalformed
						break
					}
					switch name {
					case "limit":
						var n int
						n, e = strconv.Atoi(items[0])
						if e == nil && (n < 1 || n > 50 || strconv.Itoa(n) != items[0]) {
							e = errMalformed
						}
						q.Limit = n
					case "cursor":
						q.Cursor = items[0]
					case "expanded":
						if !q.Replies || (items[0] != "true" && items[0] != "false") {
							e = errMalformed
						}
						q.Expanded = items[0] == "true"
					default:
						e = errMalformed
					}
					if e != nil {
						break
					}
				}
			}
			if e != nil {
				b.postBad(w, e)
				return
			}
			response, e = backend.ReadComments(r.Context(), bearer, q)
		}
	} else if route.kind == "seal" {
		var object map[string]any
		object, e = readRequestObject(r, 1024, []string{"operation", "requestDigest"}, nil)
		if e == nil {
			op, e1 := stringField(object, "operation")
			digest, e2 := stringField(object, "requestDigest")
			parsed, e3 := posts.ParseRequestDigest(digest)
			if e1 != nil || e2 != nil || e3 != nil || (op != "CREATE" && op != "RETRY" && op != "ABANDON") {
				e = errMalformed
			} else {
				response, e = backend.SealCommentCommand(r.Context(), bearer, route.id, comments.Operation(op), parsed)
			}
		}
	} else {
		var intent comments.Intent
		intent, e = commentIntent(r)
		if e == nil {
			response, e = backend.ExecuteCommentCommand(r.Context(), bearer, route.id, intent)
		}
	}
	if e != nil {
		var failure *authprivacy.PostError
		if errors.As(e, &failure) {
			b.postFail(w, failure.Status, failure.Code, failure.RetryAfter)
		} else if errors.Is(e, comments.ErrInvalid) || errors.Is(e, errMalformed) || errors.Is(e, errMediaType) || errors.Is(e, errTooLarge) {
			b.postBad(w, e)
		} else {
			b.postFailure(w, e)
		}
		return
	}
	// Serialize only explicit comment DTOs, never domain/private SQL rows.
	status := 200
	switch value := response.Value.(type) {
	case authprivacy.CommentReceipt:
		if value.State == "ACCEPTED" && r.Method == "PUT" {
			status = 202
		}
	case authprivacy.OwnCommentTask, authprivacy.TextCommentPage:
	default:
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if response.ServerTime.IsZero() || !response.ExpiresAt.After(response.ServerTime) {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Session-Expires-At", response.ExpiresAt.UTC().Format(time.RFC3339Nano))
	w.Header().Set("Server-Time", response.ServerTime.UTC().Format(time.RFC3339Nano))
	writeJSON(w, status, response.Value)
}
func commentIntent(r *http.Request) (comments.Intent, error) {
	var in comments.Intent
	object, e := readRequestObjectPolicy(r, comments.MaxFrameBytes+4096, []string{"operation", "taskId"}, []string{"identityId", "postId", "rootCommentId", "targetCommentId", "body", "image", "expectedAttemptVersion"}, true)
	if e != nil {
		return in, e
	}
	op, e1 := stringField(object, "operation")
	in.Operation = comments.Operation(op)
	in.TaskID, e = stringField(object, "taskId")
	if e1 != nil || e != nil {
		return in, errMalformed
	}
	switch in.Operation {
	case comments.Create:
		if fields(object, []string{"operation", "taskId", "identityId", "postId", "rootCommentId", "targetCommentId", "body", "image"}, nil) != nil {
			return in, errMalformed
		}
		in.IdentityID, e = stringField(object, "identityId")
		if e != nil {
			return in, e
		}
		in.PostID, e = stringField(object, "postId")
		if e != nil {
			return in, e
		}
		if object["rootCommentId"] != nil {
			in.RootCommentID, e = stringField(object, "rootCommentId")
			if e != nil {
				return in, e
			}
		}
		if object["targetCommentId"] != nil {
			in.TargetCommentID, e = stringField(object, "targetCommentId")
			if e != nil {
				return in, e
			}
		}
	case comments.Retry, comments.Abandon:
		required := []string{"operation", "taskId", "expectedAttemptVersion"}
		if in.Operation == comments.Retry {
			required = append(required, "body", "image")
		}
		if fields(object, required, nil) != nil {
			return in, errMalformed
		}
		version, e := integerField(object, "expectedAttemptVersion", 1, 2147483647)
		if e != nil {
			return in, e
		}
		in.ExpectedAttemptVersion = int32(version)
	default:
		return in, errMalformed
	}
	if in.Operation != comments.Abandon {
		in.Body, e = stringField(object, "body")
		if e != nil {
			return in, e
		}
		if object["image"] != nil {
			return in, errMalformed
		}
	}
	_, e = comments.FrameIntent(in)
	return in, e
}
