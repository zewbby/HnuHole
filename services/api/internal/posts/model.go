// Package posts 定义文字发布的纯协议边界；授权和数据库事务由 C 服务负责。
package posts

import (
	"encoding/json"
	"errors"
	"time"
)

var (
	ErrInvalidID         = errors.New("invalid post resource ID")
	ErrInvalidCommandKey = errors.New("invalid post command key")
	ErrContentInvalid    = errors.New("post content invalid")
	ErrPayloadTooLarge   = errors.New("post payload too large")
	ErrInvalidIntent     = errors.New("invalid post command intent")
	ErrCursorInvalid     = errors.New("post cursor invalid")
)

type Operation string

const (
	Create     Operation = "CREATE"
	Retry      Operation = "RETRY"
	Cancel     Operation = "CANCEL"
	DeletePost Operation = "DELETE_POST"
	HideTask   Operation = "HIDE_TASK"
)

func (o Operation) Valid() bool {
	return o == Create || o == Retry || o == Cancel || o == DeletePost || o == HideTask
}

type CreatePostInput struct {
	ChannelID  string `json:"channelId"`
	IdentityID string `json:"identityId"`
	Title      string `json:"title"`
	Body       string `json:"body"`
}

type RetryInput struct {
	ExpectedAttemptVersion int32  `json:"expectedAttemptVersion"`
	Title                  string `json:"title"`
	Body                   string `json:"body"`
}

type AttemptVersionInput struct {
	ExpectedAttemptVersion int32 `json:"expectedAttemptVersion"`
}

type SealInput struct {
	Operation     Operation `json:"operation"`
	RequestDigest string    `json:"requestDigest"`
}

type TaskState string

const (
	Accepted  TaskState = "ACCEPTED"
	Published TaskState = "PUBLISHED"
	Failed    TaskState = "FAILED"
	Cancelled TaskState = "CANCELLED"
)

// CommandResult 是历史命令事实，不随当前任务状态变化。
// 统一内部结构经过分支序列化，防止把其他操作字段混进严格 DTO。
type CommandResult struct {
	State          string
	Operation      Operation
	TaskID         string
	PostID         string
	AttemptVersion int32
	TaskState      TaskState
	ErrorCode      string
	Reason         string
}

func (r CommandResult) MarshalJSON() ([]byte, error) {
	m := map[string]any{"state": r.State}
	switch r.State {
	case "UNKNOWN_NOT_OBSERVED", "RESULT_EXPIRED":
	case "ACCEPTED":
		if (r.Operation != Create && r.Operation != Retry) || !validID(r.TaskID) || !validID(r.PostID) || r.AttemptVersion < 1 {
			return nil, ErrInvalidIntent
		}
		m["operation"], m["taskId"], m["postId"], m["attemptVersion"] = r.Operation, r.TaskID, r.PostID, r.AttemptVersion
	case "COMMITTED":
		m["operation"] = r.Operation
		switch r.Operation {
		case Cancel, HideTask:
			if !validID(r.TaskID) || r.AttemptVersion < 1 {
				return nil, ErrInvalidIntent
			}
			m["taskId"], m["attemptVersion"] = r.TaskID, r.AttemptVersion
			if r.Operation == Cancel {
				if r.TaskState != Cancelled && r.TaskState != Published && r.TaskState != Failed {
					return nil, ErrInvalidIntent
				}
				m["taskState"] = r.TaskState
			}
		case DeletePost:
			if !validID(r.PostID) {
				return nil, ErrInvalidIntent
			}
			m["postId"] = r.PostID
		default:
			return nil, ErrInvalidIntent
		}
	case "REJECTED":
		if !r.Operation.Valid() || !validRejection(r.ErrorCode) {
			return nil, ErrInvalidIntent
		}
		m["operation"], m["errorCode"] = r.Operation, r.ErrorCode
	case "NOT_ACCEPTED":
		if !r.Operation.Valid() || r.Reason != "COMMAND_SEALED" {
			return nil, ErrInvalidIntent
		}
		m["operation"], m["reason"] = r.Operation, r.Reason
	default:
		return nil, ErrInvalidIntent
	}
	return json.Marshal(m)
}

func validRejection(code string) bool {
	switch code {
	case "POST_CONTENT_INVALID", "POST_IDENTITY_UNAVAILABLE", "POST_CHANNEL_UNAVAILABLE", "POSTING_RESTRICTED", "ACCOUNT_CLOSING", "TASK_NOT_FOUND", "TASK_NOT_RETRYABLE", "TASK_NOT_HIDEABLE", "TASK_VERSION_CONFLICT", "POST_NOT_FOUND":
		return true
	}
	return false
}

type OwnTaskSummary struct {
	TaskID           string     `json:"taskId"`
	PostID           string     `json:"postId"`
	ChannelID        string     `json:"channelId"`
	IdentityID       string     `json:"identityId"`
	AttemptVersion   int32      `json:"attemptVersion"`
	State            TaskState  `json:"state"`
	AcceptedAt       time.Time  `json:"acceptedAt"`
	ServerSortAt     time.Time  `json:"serverSortAt"`
	TerminalAt       *time.Time `json:"terminalAt"`
	FailureCode      *string    `json:"failureCode"`
	Visible          bool       `json:"visible"`
	ContentAvailable bool       `json:"contentAvailable"`
	CanRetry         bool       `json:"canRetry"`
	CanCancel        bool       `json:"canCancel"`
	CanHide          bool       `json:"canHide"`
}

type OwnTaskContent struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type OwnTaskDetail struct {
	Task    OwnTaskSummary  `json:"task"`
	Content *OwnTaskContent `json:"content"`
}

type OwnTaskList struct {
	Items      []OwnTaskDetail `json:"items"`
	NextCursor *string         `json:"nextCursor"`
}

// PublicAuthor 没有账号或身份 ID；活动与失效分支的字段互不混用。
type PublicAuthor struct {
	State     string
	Nickname  string
	ShortCode string
	Avatar    string
}

func (a PublicAuthor) MarshalJSON() ([]byte, error) {
	switch a.State {
	case "ACTIVE":
		if a.Nickname == "" || a.Avatar != "default-v1" {
			return nil, ErrInvalidIntent
		}
		return json.Marshal(struct {
			State    string `json:"state"`
			Nickname string `json:"nickname"`
			Avatar   string `json:"avatar"`
		}{a.State, a.Nickname, a.Avatar})
	case "DELETED", "ACCOUNT_CLOSED":
		if !ValidShortCode(a.ShortCode) || a.Avatar != "inactive-v1" {
			return nil, ErrInvalidIntent
		}
		return json.Marshal(struct {
			State     string `json:"state"`
			ShortCode string `json:"shortCode"`
			Avatar    string `json:"avatar"`
		}{a.State, a.ShortCode, a.Avatar})
	default:
		return nil, ErrInvalidIntent
	}
}

type PublicPostCard struct {
	PostID      string       `json:"postId"`
	ChannelID   string       `json:"channelId"`
	Title       string       `json:"title"`
	Author      PublicAuthor `json:"author"`
	PublishedAt time.Time    `json:"publishedAt"`
}

type PublicPost struct {
	PostID      string       `json:"postId"`
	ChannelID   string       `json:"channelId"`
	Title       string       `json:"title"`
	Body        string       `json:"body"`
	Author      PublicAuthor `json:"author"`
	PublishedAt time.Time    `json:"publishedAt"`
}

type PublicPostResponse struct {
	Post PublicPost `json:"post"`
}

type FeedPage struct {
	Items      []PublicPostCard `json:"items"`
	NextCursor *string          `json:"nextCursor"`
}

type OwnPostCard struct {
	Post         PublicPostCard `json:"post"`
	ServerSortAt time.Time      `json:"serverSortAt"`
}

type OwnPostPage struct {
	Items      []OwnPostCard `json:"items"`
	NextCursor *string       `json:"nextCursor"`
}

type OwnPostCapabilities struct {
	PostID    string `json:"postId"`
	CanDelete bool   `json:"canDelete"`
	CanEdit   bool   `json:"canEdit"`
}

type ComposerContext struct {
	SelectionState    string  `json:"selectionState"`
	DefaultIdentityID *string `json:"defaultIdentityId"`
}
