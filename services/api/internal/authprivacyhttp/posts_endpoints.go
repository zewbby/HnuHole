package authprivacyhttp

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

// PostBackend 的所有方法须由同一最终 C Gate 事务完成；HTTP 不代替授权。
type PostBackend interface {
	ExecutePostCommand(context.Context, [32]byte, string, posts.Intent) (authprivacy.PostResponse, error)
	GetPostCommand(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	SealPostCommand(context.Context, [32]byte, string, posts.SealInput) (authprivacy.PostResponse, error)
	ReadPosts(context.Context, [32]byte, authprivacy.PostQuery) (authprivacy.PostResponse, error)
}

type postRoute struct {
	kind      authprivacy.PostReadKind
	id        string
	operation posts.Operation
	command   bool
	seal      bool
	methods   string
	limit     int
	version   int32
}

func (route postRoute) allows(method string) bool {
	for _, allowed := range strings.Split(route.methods, ", ") {
		if method == allowed {
			return true
		}
	}
	return false
}

func isPostPath(path string) bool {
	for _, prefix := range []string{"/api/v1/post-commands", "/api/v1/me/post-tasks", "/api/v1/me/posts", "/api/v1/me/post-composer-context", "/api/v1/posts"} {
		if path == prefix || strings.HasPrefix(path, prefix+"/") {
			return true
		}
	}
	return strings.HasPrefix(path, "/api/v1/channels/")
}

func parsePostRoute(path string) (postRoute, error) {
	if !strings.HasPrefix(path, "/api/v1/") {
		return postRoute{}, errMalformed
	}
	parts := strings.Split(strings.TrimPrefix(path, "/api/v1/"), "/")
	if len(parts) == 2 && parts[0] == "post-commands" {
		if _, err := posts.ParseCommandKey(parts[1]); err != nil {
			return postRoute{}, errMalformed
		}
		return postRoute{id: parts[1], command: true, methods: "GET, PUT"}, nil
	}
	if len(parts) == 3 && parts[0] == "post-commands" && parts[2] == "seal" {
		if _, err := posts.ParseCommandKey(parts[1]); err != nil {
			return postRoute{}, errMalformed
		}
		return postRoute{id: parts[1], seal: true, methods: "POST"}, nil
	}
	if len(parts) == 2 && parts[0] == "me" {
		switch parts[1] {
		case "post-composer-context":
			return postRoute{kind: authprivacy.PostComposerContext, methods: "GET"}, nil
		case "post-tasks":
			return postRoute{kind: authprivacy.PostTaskList, methods: "GET"}, nil
		case "posts":
			return postRoute{kind: authprivacy.PostOwnList, methods: "GET"}, nil
		}
	}
	if len(parts) == 3 && parts[0] == "me" && parts[1] == "post-tasks" {
		if _, err := posts.ParseResourceID(parts[2]); err != nil {
			return postRoute{}, errMalformed
		}
		return postRoute{kind: authprivacy.PostTaskDetail, id: parts[2], methods: "GET"}, nil
	}
	if len(parts) == 4 && parts[0] == "me" && parts[1] == "post-tasks" {
		if _, err := posts.ParseResourceID(parts[2]); err != nil {
			return postRoute{}, errMalformed
		}
		operation := map[string]posts.Operation{"cancel": posts.Cancel, "retry": posts.Retry, "hide": posts.HideTask}[parts[3]]
		if !operation.Valid() {
			return postRoute{}, errMalformed
		}
		return postRoute{operation: operation, id: parts[2], methods: "POST"}, nil
	}
	if len(parts) == 4 && parts[0] == "me" && parts[1] == "posts" && parts[3] == "capabilities" {
		if _, err := posts.ParseResourceID(parts[2]); err != nil {
			return postRoute{}, errMalformed
		}
		return postRoute{kind: authprivacy.PostCapabilities, id: parts[2], methods: "GET"}, nil
	}
	if len(parts) == 3 && parts[0] == "channels" && parts[2] == "posts" {
		if _, err := posts.ParseResourceID(parts[1]); err != nil {
			return postRoute{}, errMalformed
		}
		return postRoute{kind: authprivacy.PostChannelFeed, id: parts[1], methods: "GET"}, nil
	}
	if len(parts) == 2 && parts[0] == "posts" {
		if _, err := posts.ParseResourceID(parts[1]); err != nil {
			return postRoute{}, errMalformed
		}
		return postRoute{kind: authprivacy.PostDetail, id: parts[1], methods: "GET"}, nil
	}
	if len(parts) == 3 && parts[0] == "posts" && parts[2] == "delete" {
		if _, err := posts.ParseResourceID(parts[1]); err != nil {
			return postRoute{}, errMalformed
		}
		return postRoute{operation: posts.DeletePost, id: parts[1], methods: "POST"}, nil
	}
	return postRoute{}, errMalformed
}

func postListKind(kind authprivacy.PostReadKind) bool {
	return kind == authprivacy.PostTaskList || kind == authprivacy.PostChannelFeed || kind == authprivacy.PostOwnList
}

func allowsPostListQuery(r *http.Request) bool {
	route, err := parsePostRoute(r.URL.Path)
	return err == nil && r.Method == http.MethodGet && postListKind(route.kind)
}

func (b *boundary) communityPostsPublic(w http.ResponseWriter, r *http.Request, backend PostBackend) {
	route, err := parsePostRoute(r.URL.Path)
	if err != nil || r.URL.RawPath != "" {
		b.postBad(w, errMalformed)
		return
	}
	if !route.allows(r.Method) {
		w.Header().Set("Allow", route.methods)
		b.postFail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	for _, header := range []string{"V-Installation-ID", "OTP-Flow-ID", "Reset-Intent-ID", "Credential-Change-ID", "Content-Encoding"} {
		if hasHeader(r.Header, header) {
			b.postBad(w, errMalformed)
			return
		}
	}
	if hasHeader(r.Header, "Authorization") {
		if _, err := singleHeader(r.Header, "Authorization"); err != nil {
			b.postBad(w, errMalformed)
			return
		}
	}
	bearer, err := sessionCapability(r.Header, "Bearer")
	if err != nil {
		if errors.Is(err, errMalformed) {
			b.postBad(w, err)
			return
		}
		b.postFail(w, 401, "AUTHENTICATION_FAILED", 0)
		return
	}
	command := ""
	if route.command || route.seal || r.Method == http.MethodGet {
		if hasHeader(r.Header, "Idempotency-Key") {
			b.postBad(w, errMalformed)
			return
		}
	} else {
		command, err = singleHeader(r.Header, "Idempotency-Key")
		if err != nil {
			b.postBad(w, errMalformed)
			return
		}
		if _, err = posts.ParseCommandKey(command); err != nil {
			b.postBad(w, errMalformed)
			return
		}
	}
	if backend == nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if r.Method == http.MethodGet {
		query, err := postReadQuery(r, route)
		if err != nil {
			b.postBad(w, err)
			return
		}
		route.limit = query.Limit
		var response authprivacy.PostResponse
		if route.command {
			response, err = backend.GetPostCommand(r.Context(), bearer, route.id)
		} else {
			response, err = backend.ReadPosts(r.Context(), bearer, query)
		}
		if err != nil {
			b.postFailure(w, err)
			return
		}
		b.writePostResponse(w, response, route, false)
		return
	}
	if route.seal {
		object, err := readRequestObject(r, 1024, []string{"operation", "requestDigest"}, nil)
		if err != nil {
			b.postBad(w, err)
			return
		}
		operation, e1 := stringField(object, "operation")
		digest, e2 := stringField(object, "requestDigest")
		input := posts.SealInput{Operation: posts.Operation(operation), RequestDigest: digest}
		if e1 != nil || e2 != nil || !input.Operation.Valid() {
			b.postBad(w, errMalformed)
			return
		}
		if _, err := posts.ParseRequestDigest(input.RequestDigest); err != nil {
			b.postBad(w, errMalformed)
			return
		}
		route.operation = input.Operation
		response, err := backend.SealPostCommand(r.Context(), bearer, route.id, input)
		if err != nil {
			b.postFailure(w, err)
			return
		}
		b.writePostResponse(w, response, route, false)
		return
	}
	intent, err := postIntent(r, route)
	if err != nil {
		b.postBad(w, err)
		return
	}
	if route.command {
		command = route.id
		route.operation = posts.Create
	}
	route.version = intent.ExpectedAttemptVersion
	response, err := backend.ExecutePostCommand(r.Context(), bearer, command, intent)
	if err != nil {
		b.postFailure(w, err)
		return
	}
	b.writePostResponse(w, response, route, true)
}

func postReadQuery(r *http.Request, route postRoute) (authprivacy.PostQuery, error) {
	query := authprivacy.PostQuery{Kind: route.kind, ID: route.id, Limit: 20}
	if r.Body != nil {
		body, err := io.ReadAll(io.LimitReader(r.Body, 1))
		if err != nil || len(body) != 0 {
			return query, errMalformed
		}
	}
	if r.URL.ForceQuery {
		return query, errMalformed
	}
	if !postListKind(route.kind) {
		if r.URL.RawQuery != "" {
			return query, errMalformed
		}
		return query, nil
	}
	if r.URL.RawQuery == "" {
		return query, nil
	}
	for _, part := range strings.Split(r.URL.RawQuery, "&") {
		pair := strings.SplitN(part, "=", 2)
		if len(pair) != 2 || pair[0] == "" || pair[1] == "" {
			return query, errMalformed
		}
	}
	values, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil {
		return query, errMalformed
	}
	for name, items := range values {
		if len(items) != 1 {
			return query, errMalformed
		}
		switch name {
		case "limit":
			limit, err := strconv.Atoi(items[0])
			if err != nil || limit < 1 || limit > 50 || strconv.Itoa(limit) != items[0] {
				return query, errMalformed
			}
			query.Limit = limit
		case "cursor":
			if !validPostCursor(items[0]) {
				return query, posts.ErrCursorInvalid
			}
			query.Cursor = items[0]
		default:
			return query, errMalformed
		}
	}
	return query, nil
}

func validPostCursor(cursor string) bool {
	if len(cursor) < 1 || len(cursor) > 1024 {
		return false
	}
	decoded, err := base64.RawURLEncoding.Strict().DecodeString(cursor)
	return err == nil && len(decoded) > 0 && base64.RawURLEncoding.EncodeToString(decoded) == cursor
}

func postIntent(r *http.Request, route postRoute) (posts.Intent, error) {
	intent := posts.Intent{Operation: route.operation}
	if route.command {
		object, err := readRequestObject(r, posts.MaxRequestBytes, []string{"channelId", "identityId", "title", "body"}, nil)
		if err != nil {
			return intent, err
		}
		var e1, e2, e3, e4 error
		intent.Operation = posts.Create
		intent.ChannelID, e1 = stringField(object, "channelId")
		intent.IdentityID, e2 = stringField(object, "identityId")
		intent.Title, e3 = stringField(object, "title")
		intent.Body, e4 = stringField(object, "body")
		if e1 != nil || e2 != nil || e3 != nil || e4 != nil {
			return intent, errMalformed
		}
	} else if route.operation == posts.DeletePost {
		if noBodyOrQuery(r) != nil {
			return intent, errMalformed
		}
		intent.PostID = route.id
	} else {
		required := []string{"expectedAttemptVersion"}
		if route.operation == posts.Retry {
			required = append(required, "title", "body")
		}
		limit := int64(1024)
		if route.operation == posts.Retry {
			limit = posts.MaxRequestBytes
		}
		object, err := readRequestObject(r, limit, required, nil)
		if err != nil {
			return intent, err
		}
		version, err := integerField(object, "expectedAttemptVersion", 1, 2147483647)
		if err != nil {
			return intent, err
		}
		intent.TaskID = route.id
		intent.ExpectedAttemptVersion = int32(version)
		if route.operation == posts.Retry {
			var e1, e2 error
			intent.Title, e1 = stringField(object, "title")
			intent.Body, e2 = stringField(object, "body")
			if e1 != nil || e2 != nil {
				return intent, errMalformed
			}
		}
	}
	if _, err := posts.FrameIntent(intent); err != nil {
		return intent, errMalformed
	}
	return intent, nil
}

func (b *boundary) postBad(w http.ResponseWriter, err error) {
	status, code := 400, "MALFORMED_REQUEST"
	switch {
	case errors.Is(err, errTooLarge):
		status, code = 413, "PAYLOAD_TOO_LARGE"
	case errors.Is(err, errMediaType):
		status, code = 415, "UNSUPPORTED_MEDIA_TYPE"
	case errors.Is(err, posts.ErrCursorInvalid):
		code = "CURSOR_INVALID"
	}
	b.postFail(w, status, code, 0)
}

func (b *boundary) postFail(w http.ResponseWriter, status int, code string, retry int) {
	w.Header().Del("Session-Expires-At")
	w.Header().Del("Server-Time")
	if status == 429 {
		if retry < 1 {
			retry = 1
		}
		if retry > 300 {
			retry = 300
		}
		w.Header().Set("Retry-After", strconv.Itoa(retry))
	}
	// posts ErrorBody 严格只含 code/message；重试秒数仅放 HTTP header。
	writeJSON(w, status, errorBody{Error: publicError{Code: code, Message: "请求未能完成，请按原操作核对或重试。"}, RequestID: w.Header().Get("X-Request-ID")})
}

func postBusinessStatus(code string) int {
	switch code {
	case "POST_CONTENT_INVALID":
		return 400
	case "TASK_NOT_FOUND", "POST_NOT_FOUND":
		return 404
	case "POST_IDENTITY_UNAVAILABLE", "POST_CHANNEL_UNAVAILABLE", "POSTING_RESTRICTED", "ACCOUNT_CLOSING", "TASK_NOT_RETRYABLE", "TASK_NOT_HIDEABLE", "TASK_VERSION_CONFLICT":
		return 409
	}
	return 0
}

func (b *boundary) postFailure(w http.ResponseWriter, err error) {
	var failure *authprivacy.PostError
	if errors.As(err, &failure) {
		status := postBusinessStatus(failure.Code)
		// 通道列表读的不存在是404；受理命令的同码持久业务拒绝仍是409。
		if failure.Code == "POST_CHANNEL_UNAVAILABLE" && failure.Status == 404 {
			status = 404
		}
		if status == 0 {
			switch failure.Code {
			case "COMMAND_CONFLICT", "COMMAND_SEALED", "RESULT_EXPIRED":
				status = 409
			case "CURSOR_INVALID", "MALFORMED_REQUEST":
				status = 400
			case "RATE_LIMITED":
				status = 429
			case "SERVICE_UNAVAILABLE", "AUTHORIZATION_UNAVAILABLE":
				status = 503
			case "POSTING_RESTRICTED":
				status = 409
			}
		}
		if status != 0 && failure.Status == status {
			b.postFail(w, status, failure.Code, failure.RetryAfter)
			return
		}
	}
	switch {
	case errors.Is(err, authprivacy.ErrAuthenticationFailed):
		b.postFail(w, 401, "AUTHENTICATION_FAILED", 0)
	case errors.Is(err, authprivacy.ErrSessionInvalid):
		b.postFail(w, 401, "SESSION_INVALID", 0)
	case errors.Is(err, authprivacy.ErrSessionReplaced):
		b.postFail(w, 401, "session_replaced", 0)
	case errors.Is(err, authprivacy.ErrAccountUnavailable):
		b.postFail(w, 403, "AUTHENTICATION_FAILED", 0)
	case errors.Is(err, authprivacy.ErrAuthorizationUnavailable):
		b.postFail(w, 503, "AUTHORIZATION_UNAVAILABLE", 0)
	case errors.Is(err, posts.ErrCursorInvalid):
		b.postFail(w, 400, "CURSOR_INVALID", 0)
	default:
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
	}
}

func (b *boundary) writePostResponse(w http.ResponseWriter, response authprivacy.PostResponse, route postRoute, mutation bool) {
	if !validPostTime(response.ExpiresAt) || !validPostTime(response.ServerTime) || !response.ExpiresAt.After(response.ServerTime) {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	value, err := strictPostValue(response.Value, route)
	if err != nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	status := 200
	if mutation {
		result, ok := value.(posts.CommandResult)
		if !ok || result.Operation != route.operation {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		if result.State == "REJECTED" {
			if status := postBusinessStatus(result.ErrorCode); status != 0 {
				b.postFail(w, status, result.ErrorCode, 0)
				return
			}
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		if route.operation == posts.Create || route.operation == posts.Retry {
			if result.State != "ACCEPTED" {
				b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
				return
			}
			status = 202
		} else if result.State != "COMMITTED" {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Session-Expires-At", utc(response.ExpiresAt))
	w.Header().Set("Server-Time", utc(response.ServerTime))
	w.WriteHeader(status)
	_, _ = w.Write(append(encoded, '\n'))
}

// 先限定实际 DTO 类型再校验内容，不能把 backend 的任意 row/map 直接序列化。
func strictPostValue(value any, route postRoute) (any, error) {
	if route.command || route.seal || route.operation.Valid() {
		result, ok := value.(posts.CommandResult)
		if p, yes := value.(*posts.CommandResult); yes && p != nil {
			result, ok = *p, true
		}
		if !ok || route.seal && result.State == "UNKNOWN_NOT_OBSERVED" {
			return nil, errMalformed
		}
		if route.operation.Valid() && result.State != "RESULT_EXPIRED" && result.Operation != route.operation {
			return nil, errMalformed
		}
		if !route.seal && route.operation.Valid() {
			switch result.State {
			case "ACCEPTED":
				if route.operation == posts.Create && result.AttemptVersion != 1 || route.operation == posts.Retry && (result.TaskID != route.id || int64(result.AttemptVersion) != int64(route.version)+1) {
					return nil, errMalformed
				}
			case "COMMITTED":
				if route.operation == posts.DeletePost && result.PostID != route.id || (route.operation == posts.Cancel || route.operation == posts.HideTask) && (result.TaskID != route.id || result.AttemptVersion != route.version) {
					return nil, errMalformed
				}
			}
		}
		if _, err := json.Marshal(result); err != nil {
			return nil, err
		}
		return result, nil
	}
	switch route.kind {
	case authprivacy.PostComposerContext:
		result, ok := value.(posts.ComposerContext)
		if p, yes := value.(*posts.ComposerContext); yes && p != nil {
			result, ok = *p, true
		}
		if !ok {
			return nil, errMalformed
		}
		switch result.SelectionState {
		case "DEFAULT_AVAILABLE":
			if result.DefaultIdentityID == nil || !postValidID(*result.DefaultIdentityID) {
				return nil, errMalformed
			}
		case "INITIAL_SETUP_REQUIRED", "SELECTION_REQUIRED":
			if result.DefaultIdentityID != nil {
				return nil, errMalformed
			}
		default:
			return nil, errMalformed
		}
		return result, nil
	case authprivacy.PostTaskDetail:
		result, ok := value.(posts.OwnTaskDetail)
		if p, yes := value.(*posts.OwnTaskDetail); yes && p != nil {
			result, ok = *p, true
		}
		if !ok || result.Task.TaskID != route.id || !validOwnPostTask(result) {
			return nil, errMalformed
		}
		return result, nil
	case authprivacy.PostTaskList:
		result, ok := value.(posts.OwnTaskList)
		if p, yes := value.(*posts.OwnTaskList); yes && p != nil {
			result, ok = *p, true
		}
		if !ok || result.Items == nil || !validPostPageSize(len(result.Items), route.limit) || !validNullablePostCursor(result.NextCursor) {
			return nil, errMalformed
		}
		for _, task := range result.Items {
			if !validOwnPostTask(task) || !task.Task.Visible || (task.Task.State != posts.Accepted && task.Task.State != posts.Failed) {
				return nil, errMalformed
			}
		}
		return result, nil
	case authprivacy.PostChannelFeed:
		result, ok := value.(posts.FeedPage)
		if p, yes := value.(*posts.FeedPage); yes && p != nil {
			result, ok = *p, true
		}
		if !ok || result.Items == nil || !validPostPageSize(len(result.Items), route.limit) || !validNullablePostCursor(result.NextCursor) {
			return nil, errMalformed
		}
		for _, post := range result.Items {
			if post.ChannelID != route.id || !validPublicPostCard(post) {
				return nil, errMalformed
			}
		}
		return result, nil
	case authprivacy.PostDetail:
		result, ok := value.(posts.PublicPostResponse)
		if p, yes := value.(*posts.PublicPostResponse); yes && p != nil {
			result, ok = *p, true
		}
		if !ok || result.Post.PostID != route.id || !validPublicPostCard(posts.PublicPostCard{PostID: result.Post.PostID, ChannelID: result.Post.ChannelID, Title: result.Post.Title, Author: result.Post.Author, PublishedAt: result.Post.PublishedAt}) || posts.ValidateContent(result.Post.Title, result.Post.Body) != nil {
			return nil, errMalformed
		}
		return result, nil
	case authprivacy.PostOwnList:
		result, ok := value.(posts.OwnPostPage)
		if p, yes := value.(*posts.OwnPostPage); yes && p != nil {
			result, ok = *p, true
		}
		if !ok || result.Items == nil || !validPostPageSize(len(result.Items), route.limit) || !validNullablePostCursor(result.NextCursor) {
			return nil, errMalformed
		}
		for _, post := range result.Items {
			if !validPublicPostCard(post.Post) || post.Post.Author.State != "ACTIVE" || !post.ServerSortAt.Equal(post.Post.PublishedAt) {
				return nil, errMalformed
			}
		}
		return result, nil
	case authprivacy.PostCapabilities:
		result, ok := value.(posts.OwnPostCapabilities)
		if p, yes := value.(*posts.OwnPostCapabilities); yes && p != nil {
			result, ok = *p, true
		}
		if !ok || result.PostID != route.id || !postValidID(result.PostID) || !result.CanDelete || result.CanEdit {
			return nil, errMalformed
		}
		return result, nil
	}
	return nil, errMalformed
}

func postValidID(id string) bool { _, err := posts.ParseResourceID(id); return err == nil }

func validPostPageSize(size, limit int) bool {
	return limit >= 1 && limit <= 50 && size <= limit
}

func validNullablePostCursor(value *string) bool { return value == nil || validPostCursor(*value) }

func validPublicPostCard(post posts.PublicPostCard) bool {
	if !postValidID(post.PostID) || !postValidID(post.ChannelID) || !validPostTime(post.PublishedAt) || posts.ValidateContent(post.Title, "正文") != nil {
		return false
	}
	if post.Author.State == "ACTIVE" && (!utf8.ValidString(post.Author.Nickname) || len(post.Author.Nickname) > 512) {
		return false
	}
	_, err := json.Marshal(post.Author)
	return err == nil
}

func validPostTime(value time.Time) bool {
	return !value.IsZero() && value.Year() >= 1 && value.Year() <= 9999 && value.Location() == time.UTC
}

func validOwnPostTask(detail posts.OwnTaskDetail) bool {
	task := detail.Task
	if !postValidID(task.TaskID) || !postValidID(task.PostID) || !postValidID(task.ChannelID) || !postValidID(task.IdentityID) || task.AttemptVersion < 1 || !validPostTime(task.AcceptedAt) || !task.ServerSortAt.Equal(task.AcceptedAt) || !validPostTime(task.ServerSortAt) || task.ContentAvailable != (detail.Content != nil) {
		return false
	}
	if detail.Content != nil && posts.ValidateContent(detail.Content.Title, detail.Content.Body) != nil {
		return false
	}
	// 已公开任务可核对其公开文字，但不能重建 pending/failed 卡片或维护权限。
	if !task.Visible && (task.CanHide || task.CanCancel || task.CanRetry || task.ContentAvailable && task.State != posts.Published) {
		return false
	}
	if task.TerminalAt != nil && task.TerminalAt.Before(task.AcceptedAt) {
		return false
	}
	switch task.State {
	case posts.Accepted:
		return task.TerminalAt == nil && task.FailureCode == nil && !task.CanRetry && !task.CanHide
	case posts.Failed:
		if task.TerminalAt == nil || !validPostTime(*task.TerminalAt) || task.FailureCode == nil || task.CanCancel {
			return false
		}
		if task.CanRetry && (!task.ContentAvailable || !task.Visible) {
			return false
		}
		return *task.FailureCode == "PUBLICATION_FAILED" || *task.FailureCode == "PUBLISHING_STOPPED" || *task.FailureCode == "IDENTITY_INACTIVE"
	case posts.Published, posts.Cancelled:
		return task.TerminalAt != nil && validPostTime(*task.TerminalAt) && task.FailureCode == nil && !task.CanRetry && !task.CanHide && !task.CanCancel && !task.Visible && (task.State != posts.Cancelled || detail.Content == nil)
	}
	return false
}
