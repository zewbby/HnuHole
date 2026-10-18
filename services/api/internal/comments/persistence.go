package comments

import "time"

// Record is trusted private persistence, never a wire DTO. Restore validates a
// stored checkpoint; all changes still go through the existing Task methods.
type Record struct {
	TaskID, CommentID            string
	Binding                      Binding
	Content                      *Content
	State                        TaskState
	Version                      int32
	AcceptedAt, TerminalAt       time.Time
	Failure                      FailureCode
	IdentityActive, OwnerVisible bool
}

func Restore(r Record) (Task, error) {
	if !validID(r.TaskID) || !validID(r.CommentID) || r.Binding.Validate() != nil || r.Version < 1 || r.AcceptedAt.IsZero() || r.CommentID == r.Binding.RootCommentID || r.CommentID == r.Binding.TargetCommentID {
		return Task{}, ErrInvalid
	}
	if r.Content == nil {
		if r.IdentityActive && r.State != Abandoned {
			return Task{}, ErrInvalid
		}
	} else if r.Content.Validate() != nil {
		return Task{}, ErrInvalid
	}
	if !r.IdentityActive && r.OwnerVisible {
		return Task{}, ErrInvalid
	}
	switch r.State {
	case Accepted:
		if !r.TerminalAt.IsZero() || r.Failure != "" || !r.IdentityActive || !r.OwnerVisible {
			return Task{}, ErrInvalid
		}
	case Published:
		if r.TerminalAt.Before(r.AcceptedAt) || r.Failure != "" {
			return Task{}, ErrInvalid
		}
	case Failed:
		if r.TerminalAt.Before(r.AcceptedAt) || !r.Failure.valid() {
			return Task{}, ErrInvalid
		}
	case Abandoned:
		if r.TerminalAt.Before(r.AcceptedAt) || !r.Failure.valid() || r.OwnerVisible {
			return Task{}, ErrInvalid
		}
	default:
		return Task{}, ErrInvalid
	}
	t := Task{id: r.TaskID, commentID: r.CommentID, binding: r.Binding, state: r.State, version: r.Version, acceptedAt: r.AcceptedAt, terminalAt: r.TerminalAt, failure: r.Failure, identityActive: r.IdentityActive, ownerVisible: r.OwnerVisible}
	if r.Content != nil {
		t.content = cloneContent(*r.Content)
	}
	return t, nil
}
