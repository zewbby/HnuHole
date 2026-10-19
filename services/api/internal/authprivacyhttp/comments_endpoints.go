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
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type CommentBackend interface {
	ExecuteCommentCommand(context.Context, [32]byte, string, comments.Intent) (authprivacy.PostResponse, error)
	GetCommentCommand(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	SealCommentCommand(context.Context, [32]byte, string, comments.Operation, [32]byte) (authprivacy.PostResponse, error)
	GetOwnCommentTask(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	ReadComments(context.Context, [32]byte, authprivacy.CommentQuery) (authprivacy.PostResponse, error)
}
type commentBusinessBackend interface {
	ReadOwnComments(context.Context, [32]byte, string, string) (authprivacy.PostResponse, error)
	ReadOneComment(context.Context, [32]byte, string, string) (authprivacy.PostResponse, error)
	ReadCommentContext(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	LocateComment(context.Context, [32]byte, string, string) (authprivacy.PostResponse, error)
	UploadCommentImage(context.Context, [32]byte, string, int32, []byte, string) (authprivacy.PostResponse, error)
	ReadCommentImage(context.Context, [32]byte, string, string, string) (authprivacy.PostResponse, error)
}
type commentRoute struct {
	id, post, kind, methods, command, content string
	version                                   int32
}

func isCommentPath(path string) bool {
	return path == "/api/v1/me/comments" || strings.HasPrefix(path, "/api/v1/comment-commands") || strings.HasPrefix(path, "/api/v1/me/comment-tasks") || strings.HasPrefix(path, "/api/v1/comments/") || strings.HasPrefix(path, "/api/v1/posts/") && (strings.Contains(path, "/comments") || strings.HasSuffix(path, "/comment-context"))
}
func parseCommentRoute(path string) (commentRoute, error) {
	parts := strings.Split(strings.TrimPrefix(path, "/api/v1/"), "/")
	r := commentRoute{methods: "GET"}
	switch {
	case len(parts) == 2 && parts[0] == "me" && parts[1] == "comments":
		r.kind = "own"
		return r, nil
	case len(parts) == 4 && parts[0] == "posts" && parts[2] == "comments":
		r.id = parts[3]
		r.post = parts[1]
		r.kind = "one"
	case len(parts) == 3 && parts[0] == "posts" && parts[2] == "comment-context":
		r.id = parts[1]
		r.kind = "context"
	case len(parts) == 5 && parts[0] == "comments" && (parts[2] == "delete-commands" || parts[2] == "like-commands"):
		return r, errMalformed
	case len(parts) == 4 && parts[0] == "comments" && (parts[2] == "delete-commands" || parts[2] == "like-commands"):
		r.id = parts[1]
		r.command = parts[3]
		r.kind = parts[2]
		r.methods = "PUT"
		if _, e := comments.ParseCommandKey(r.command); e != nil {
			return r, e
		}
	case len(parts) == 6 && parts[0] == "me" && parts[1] == "comment-tasks" && parts[3] == "attempts" && parts[5] == "image":
		r.id = parts[2]
		r.kind = "upload"
		r.methods = "PUT"
		n, e := strconv.ParseInt(parts[4], 10, 32)
		if e != nil || n < 1 || strconv.FormatInt(n, 10) != parts[4] {
			return r, errMalformed
		}
		r.version = int32(n)
	case len(parts) == 5 && parts[0] == "posts" && parts[2] == "comments" && parts[4] == "location":
		r.id = parts[3]
		r.post = parts[1]
		r.kind = "location"
	case len(parts) == 7 && parts[0] == "posts" && parts[2] == "comments" && parts[4] == "images" && parts[6] == "original":
		r.id = parts[3]
		r.post = parts[1]
		r.content = parts[5]
		r.kind = "original"
		if _, e := posts.ParseResourceID(r.content); e != nil {
			return r, e
		}
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
	case len(parts) == 5 && parts[0] == "posts" && parts[2] == "comments" && parts[4] == "replies":
		r.id = parts[3]
		r.post = parts[1]
		if _, e := posts.ParseResourceID(r.post); e != nil {
			return r, e
		}
		r.kind = "replies"
	default:
		return r, errMalformed
	}
	var e error
	if r.post != "" {
		if _, e = posts.ParseResourceID(r.post); e != nil {
			return r, e
		}
	}
	if r.kind == "command" || r.kind == "seal" {
		_, e = comments.ParseCommandKey(r.id)
	} else {
		_, e = posts.ParseResourceID(r.id)
	}
	return r, e
}
func allowsCommentListQuery(r *http.Request) bool {
	route, e := parseCommentRoute(r.URL.Path)
	return e == nil && r.Method == "GET" && (route.kind == "own" || route.kind == "main" || route.kind == "replies")
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
	business, _ := backend.(commentBusinessBackend)
	if (route.kind == "own" || route.kind == "one" || route.kind == "context" || route.kind == "location" || route.kind == "original" || route.kind == "upload") && business == nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if route.kind == "upload" {
		mime, er := singleHeader(r.Header, "Content-Type")
		if er != nil {
			b.postBad(w, er)
			return
		}
		data, er := io.ReadAll(io.LimitReader(r.Body, postmedia.MaxBytes+1))
		if er != nil || len(data) > postmedia.MaxBytes {
			b.postBad(w, errTooLarge)
			return
		}
		response, e = business.UploadCommentImage(r.Context(), bearer, route.id, route.version, data, mime)
	} else if route.kind == "delete-commands" || route.kind == "like-commands" {
		required := []string{}
		if route.kind == "like-commands" {
			required = []string{"liked"}
		}
		object, er := readRequestObject(r, 1024, required, nil)
		if er != nil {
			b.postBad(w, er)
			return
		}
		in := comments.Intent{CommentID: route.id, Operation: comments.DeleteComment}
		if route.kind == "like-commands" {
			liked, ok := object["liked"].(bool)
			if !ok {
				b.postBad(w, errMalformed)
				return
			}
			in.Operation = comments.SetLike
			in.Liked = &liked
		}
		response, e = backend.ExecuteCommentCommand(r.Context(), bearer, route.command, in)
	} else if r.Method == "GET" {
		if r.Body != nil {
			body, e := io.ReadAll(io.LimitReader(r.Body, 1))
			if e != nil || len(body) != 0 {
				b.postBad(w, errMalformed)
				return
			}
		}
		switch route.kind {
		case "own":
			values, er := url.ParseQuery(r.URL.RawQuery)
			identity := values.Get("identityId")
			cursor := values.Get("cursor")
			if er != nil || len(values["identityId"]) != 1 || len(values["cursor"]) > 1 || len(values) > 2 {
				b.postBad(w, errMalformed)
				return
			}
			if _, er = posts.ParseResourceID(identity); er != nil {
				b.postBad(w, errMalformed)
				return
			}
			if cursor != "" {
				if _, er = posts.ParseResourceID(cursor); er != nil {
					b.postBad(w, errMalformed)
					return
				}
			}
			for name := range values {
				if name != "identityId" && name != "cursor" {
					b.postBad(w, errMalformed)
					return
				}
			}
			response, e = business.ReadOwnComments(r.Context(), bearer, identity, cursor)
		case "one":
			response, e = business.ReadOneComment(r.Context(), bearer, route.post, route.id)
		case "context":
			response, e = business.ReadCommentContext(r.Context(), bearer, route.id)
		case "location":
			response, e = business.LocateComment(r.Context(), bearer, route.post, route.id)
		case "original":
			response, e = business.ReadCommentImage(r.Context(), bearer, route.post, route.id, route.content)
		case "command":
			response, e = backend.GetCommentCommand(r.Context(), bearer, route.id)
		case "task":
			response, e = backend.GetOwnCommentTask(r.Context(), bearer, route.id)
		default:
			q := authprivacy.CommentQuery{ID: route.id, PostID: route.post, Replies: route.kind == "replies", Limit: 50}
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
			if e1 != nil || e2 != nil || e3 != nil || !comments.Operation(op).Valid() {
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
		} else if errors.Is(e, postmedia.ErrInvalid) || errors.Is(e, comments.ErrInvalid) || errors.Is(e, errMalformed) || errors.Is(e, errMediaType) || errors.Is(e, errTooLarge) {
			b.postBad(w, e)
		} else {
			b.postFailure(w, e)
		}
		return
	}
	if response.ServerTime.IsZero() || !response.ExpiresAt.After(response.ServerTime) {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	// Serialize only explicit comment DTOs, never domain/private SQL rows.
	status := 200
	switch value := response.Value.(type) {
	case authprivacy.CommentReceipt:
		if value.State == "ACCEPTED" && r.Method == "PUT" {
			status = 202
		}
	case authprivacy.ImageBytes:
		if len(value.Bytes) < 1 || len(value.Bytes) > postmedia.MaxBytes {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		until := response.ServerTime.Add(time.Minute)
		if until.After(response.ExpiresAt) {
			until = response.ExpiresAt
		}
		w.Header().Set("Session-Expires-At", utc(response.ExpiresAt))
		w.Header().Set("Server-Time", utc(response.ServerTime))
		w.Header().Set("Access-Valid-Until", utc(until))
		w.Header().Set("Content-Type", value.MIME)
		w.Header().Set("Content-Disposition", "attachment")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
		w.Header().Add("Vary", "Authorization")
		w.WriteHeader(200)
		_, _ = w.Write(value.Bytes)
		return
	case authprivacy.OwnCommentsPage, authprivacy.TextComment, authprivacy.OwnCommentTask, authprivacy.TextCommentPage, authprivacy.CommentContext, authprivacy.CommentLocation, authprivacy.CommentMediaAck:
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
			if _, e = posts.ParseResourceID(in.RootCommentID); e != nil {
				return in, errMalformed
			}
		}
		if object["targetCommentId"] != nil {
			in.TargetCommentID, e = stringField(object, "targetCommentId")
			if e != nil {
				return in, e
			}
			if _, e = posts.ParseResourceID(in.TargetCommentID); e != nil {
				return in, errMalformed
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
			items, er := parsePostImages(map[string]any{"images": []any{object["image"]}})
			if er != nil {
				return in, er
			}
			in.Image = &items[0]
		}
	}
	_, e = comments.FrameIntent(in)
	return in, e
}
