package comments

import (
	"math"
	"time"
)

type TaskState string

const (
	Accepted  TaskState = "ACCEPTED"
	Published TaskState = "PUBLISHED"
	Failed    TaskState = "FAILED"
	Abandoned TaskState = "ABANDONED"
)

type FailureCode string

const (
	FailurePublication       FailureCode = "PUBLICATION_FAILED"
	FailurePublishingStopped FailureCode = "PUBLISHING_STOPPED"
	FailureIdentityInactive  FailureCode = "IDENTITY_INACTIVE"
	FailureTargetDeleted     FailureCode = "COMMENT_TARGET_DELETED"
	FailurePostUnavailable   FailureCode = "POST_UNAVAILABLE"
)

func (f FailureCode) valid() bool {
	return f == FailurePublication || f == FailurePublishingStopped || f == FailureIdentityInactive || f == FailureTargetDeleted || f == FailurePostUnavailable
}

// AcceptInput describes an already-authorized acceptance. The C service must
// check the Gate/session, ownership, target, and existing account+post binding,
// then write this task and its identity binding in one final SQL transaction.
// Merely choosing an identity must never call Accept or create a binding.
type AcceptInput struct {
	TaskID, CommentID string
	Binding           Binding
	Content           Content
	AcceptedAt        time.Time
}

// Task is an immutable value: transition methods return a new Task and no field
// can be changed directly. It is a rule model, not an in-memory task service.
type Task struct {
	id, commentID  string
	binding        Binding
	content        Content
	state          TaskState
	version        int32
	acceptedAt     time.Time
	terminalAt     time.Time
	failure        FailureCode
	identityActive bool
	ownerVisible   bool
}

func Accept(input AcceptInput) (Task, error) {
	if !validID(input.TaskID) || !validID(input.CommentID) || input.Binding.Validate() != nil || input.Content.Validate() != nil || input.AcceptedAt.IsZero() || input.CommentID == input.Binding.RootCommentID || input.CommentID == input.Binding.TargetCommentID {
		return Task{}, ErrInvalid
	}
	return Task{id: input.TaskID, commentID: input.CommentID, binding: input.Binding, content: cloneContent(input.Content), state: Accepted, version: 1, acceptedAt: input.AcceptedAt.UTC(), identityActive: true, ownerVisible: true}, nil
}

// TaskView is private owner state. Never serialize it as a public comment.
// Retry and abandon flags can only narrow the final service-side authorization.
type TaskView struct {
	TaskID, CommentID string
	Binding           Binding
	State             TaskState
	AttemptVersion    int32
	AcceptedAt        time.Time
	TerminalAt        time.Time
	FailureCode       FailureCode
	OwnerVisible      bool
	Content           *Content
	CanRetry          bool
	CanAbandon        bool
}

func (t Task) View() TaskView {
	v := TaskView{TaskID: t.id, CommentID: t.commentID, Binding: t.binding, State: t.state, AttemptVersion: t.version, AcceptedAt: t.acceptedAt, TerminalAt: t.terminalAt, FailureCode: t.failure, OwnerVisible: t.ownerVisible, CanRetry: t.canRetry(), CanAbandon: t.ownerVisible && t.identityActive && t.state == Failed}
	if t.ownerVisible && t.identityActive && (t.state == Accepted || t.state == Failed) {
		content := cloneContent(t.content)
		v.Content = &content
	}
	return v
}

func (t Task) canRetry() bool {
	// A deleted target must be explicitly reselected in a new sending action;
	// retrying this immutable original task cannot silently redirect it.
	return t.ownerVisible && t.identityActive && t.state == Failed && t.failure != FailureTargetDeleted && t.failure != FailurePostUnavailable && t.failure != FailureIdentityInactive
}

func (t Task) checkVersion(expected int32) error {
	if t.id == "" {
		return ErrInvalid
	}
	if expected < 1 || expected != t.version {
		return ErrVersion
	}
	return nil
}

func (t Task) checkTerminal(expected int32, at time.Time) error {
	if err := t.checkVersion(expected); err != nil {
		return err
	}
	if t.state != Accepted {
		return ErrState
	}
	if at.IsZero() || at.Before(t.acceptedAt) {
		return ErrInvalid
	}
	return nil
}

func (t Task) Publish(expected int32, at time.Time) (Task, error) {
	if err := t.checkTerminal(expected, at); err != nil {
		return Task{}, err
	}
	if !t.identityActive {
		return Task{}, ErrIdentity
	}
	t.state, t.terminalAt = Published, at.UTC()
	return t, nil
}

func (t Task) Fail(expected int32, code FailureCode, at time.Time) (Task, error) {
	if err := t.checkTerminal(expected, at); err != nil {
		return Task{}, err
	}
	if !code.valid() {
		return Task{}, ErrInvalid
	}
	t.state, t.failure, t.terminalAt = Failed, code, at.UTC()
	return t, nil
}

// Retry never accepts a replacement binding. Only content may be changed after
// a confirmed failure, and the service must recheck current sending permission.
func (t Task) Retry(expected int32, content Content, at time.Time) (Task, error) {
	if err := t.checkVersion(expected); err != nil {
		return Task{}, err
	}
	if !t.identityActive {
		return Task{}, ErrIdentity
	}
	if !t.canRetry() {
		return Task{}, ErrState
	}
	if t.version == math.MaxInt32 || content.Validate() != nil || at.IsZero() || at.Before(t.terminalAt) {
		return Task{}, ErrInvalid
	}
	t.version++
	t.state, t.content, t.acceptedAt = Accepted, cloneContent(content), at.UTC()
	t.failure, t.terminalAt = "", time.Time{}
	return t, nil
}

func (t Task) Abandon(expected int32, at time.Time) (Task, error) {
	if err := t.checkVersion(expected); err != nil {
		return Task{}, err
	}
	if !t.identityActive {
		return Task{}, ErrIdentity
	}
	if !t.ownerVisible || t.state != Failed {
		return Task{}, ErrState
	}
	if at.IsZero() || at.Before(t.terminalAt) {
		return Task{}, ErrInvalid
	}
	t.state, t.ownerVisible, t.terminalAt = Abandoned, false, at.UTC()
	return t, nil
}

// IdentityDeleted closes owner recovery and retries. A previously published
// fact remains published; an accepted attempt becomes a confirmed failure.
// Retained system content is not exposed through View after identity deletion.
func (t Task) IdentityDeleted(at time.Time) (Task, error) {
	if t.id == "" || at.IsZero() || at.Before(t.acceptedAt) || (!t.terminalAt.IsZero() && at.Before(t.terminalAt)) {
		return Task{}, ErrInvalid
	}
	if !t.identityActive {
		return t, nil
	}
	t.identityActive, t.ownerVisible = false, false
	if t.state == Accepted {
		t.state, t.failure, t.terminalAt = Failed, FailureIdentityInactive, at.UTC()
	}
	return t, nil
}

// Observation belongs to the caller's knowledge, never the authoritative task
// state. A lost HTTP response cannot be promoted to a failed attempt.
type Observation string

const (
	ResultUnknown Observation = "UNKNOWN"
	TaskAccepted  Observation = "ACCEPTED"
	TaskPublished Observation = "PUBLISHED"
	TaskFailed    Observation = "FAILED"
	TaskAbandoned Observation = "ABANDONED"
)

type RecoveryAction string

const (
	QueryOriginal RecoveryAction = "QUERY_ORIGINAL"
	HandleFailure RecoveryAction = "HANDLE_FAILURE"
	Resolved      RecoveryAction = "RESOLVED"
)

func ReconcileAction(observed Observation) (RecoveryAction, error) {
	switch observed {
	case ResultUnknown, TaskAccepted:
		return QueryOriginal, nil
	case TaskFailed:
		// Re-read owner/task capabilities before offering retry or abandonment.
		return HandleFailure, nil
	case TaskPublished, TaskAbandoned:
		return Resolved, nil
	default:
		return "", ErrReconcile
	}
}
