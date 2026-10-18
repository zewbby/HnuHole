// Package comments defines pure comment rules. It performs no authorization,
// persistence, background publication, or notification delivery.
package comments

import (
	"errors"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

var (
	ErrInvalid       = errors.New("invalid comment input")
	ErrState         = errors.New("comment task transition unavailable")
	ErrVersion       = errors.New("comment task version conflict")
	ErrIdentity      = errors.New("comment identity inactive")
	ErrIdentityBound = errors.New("post already bound to another identity")
	ErrReconcile     = errors.New("comment result requires reconciliation")
	ErrPage          = errors.New("invalid comment snapshot page")
)

const MaxImages = 1

// MaxBodyClusters is the inherited post implementation's temporary technical
// budget, not a newly confirmed comment product limit.
const MaxBodyClusters = posts.MaxBodyClusters

// Content preserves the submitted text and immutable original image manifest.
// This type is private task content, not a long-lived comment draft product.
type Content struct {
	Body  string               `json:"body"`
	Image *postmedia.Selection `json:"image"`
}

func (c Content) Validate() error {
	var images []postmedia.Selection
	if c.Image != nil {
		images = []postmedia.Selection{*c.Image}
	}
	if postmedia.ValidateManifest(images) != nil {
		return ErrInvalid
	}
	// Reuse the frozen Unicode 16 body rules without imposing a title on comments.
	if posts.ValidateContentWithImages("评论", c.Body, len(images)) != nil {
		return ErrInvalid
	}
	return nil
}

func cloneContent(c Content) Content {
	if c.Image != nil {
		image := *c.Image
		c.Image = &image
	}
	return c
}

func validID(id string) bool {
	_, err := posts.ParseResourceID(id)
	return err == nil
}

// Binding is the private original sending context. An accepted task cannot
// change any field, including when its target or identity later becomes invalid.
// Main comments have no root/target; replies identify both concrete resources.
type Binding struct {
	PostID          string `json:"postId"`
	IdentityID      string `json:"identityId"`
	RootCommentID   string `json:"rootCommentId,omitempty"`
	TargetCommentID string `json:"targetCommentId,omitempty"`
}

func (b Binding) Validate() error {
	if !validID(b.PostID) || !validID(b.IdentityID) {
		return ErrInvalid
	}
	if b.RootCommentID == "" && b.TargetCommentID == "" {
		return nil
	}
	if !validID(b.RootCommentID) || !validID(b.TargetCommentID) {
		return ErrInvalid
	}
	return nil
}

// ThreadIdentityBinding is private account+post state. The account key is held
// by the authorized caller and is deliberately absent from public projections.
type ThreadIdentityBinding struct {
	PostID, IdentityID string
}

// AcceptanceBinding resolves the invariant at task acceptance, not while
// opening a composer or merely selecting an identity. NeedsInsert means the
// final C transaction must insert this binding atomically with the task;
// concurrent unique conflicts must be re-read and resolved by the same rule.
func AcceptanceBinding(postID, identityID string, existing *ThreadIdentityBinding) (binding ThreadIdentityBinding, needsInsert bool, err error) {
	if !validID(postID) || !validID(identityID) {
		return binding, false, ErrInvalid
	}
	binding = ThreadIdentityBinding{PostID: postID, IdentityID: identityID}
	if existing == nil {
		return binding, true, nil
	}
	if !validID(existing.PostID) || !validID(existing.IdentityID) || existing.PostID != postID {
		return ThreadIdentityBinding{}, false, ErrInvalid
	}
	if existing.IdentityID != identityID {
		return ThreadIdentityBinding{}, false, ErrIdentityBound
	}
	return *existing, false, nil
}
