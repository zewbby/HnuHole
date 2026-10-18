package comments

import (
	"encoding/json"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

// PublicAuthor reuses the identity-level safe projection, including the
// independent inactive-identity label. It exposes neither account nor identity ID.
type PublicAuthor = posts.PublicAuthor

type PublicComment struct {
	CommentID       string `json:"commentId"`
	PostID          string `json:"postId"`
	RootCommentID   string `json:"rootCommentId,omitempty"`
	TargetCommentID string `json:"targetCommentId,omitempty"`
	// TargetAuthor preserves a safe relationship label after target deletion.
	// Target content is never quoted in this projection.
	TargetAuthor    *PublicAuthor `json:"targetAuthor,omitempty"`
	TargetAvailable bool          `json:"targetAvailable"`
	Body            string        `json:"body"`
	ImageCount      int           `json:"imageCount"`
	Author          PublicAuthor  `json:"author"`
	IsPostAuthor    bool          `json:"isPostAuthor"`
	LikeCount       int64         `json:"likeCount"`
	PublishedAt     time.Time     `json:"publishedAt"`
}

func (c PublicComment) Validate() error {
	if !validID(c.CommentID) || !validID(c.PostID) || c.PublishedAt.IsZero() || c.LikeCount < 0 || c.ImageCount < 0 || c.ImageCount > MaxImages || posts.ValidateContentWithImages("评论", c.Body, c.ImageCount) != nil {
		return ErrInvalid
	}
	if _, err := json.Marshal(c.Author); err != nil {
		return ErrInvalid
	}
	if c.RootCommentID == "" && c.TargetCommentID == "" && c.TargetAuthor == nil && !c.TargetAvailable {
		return nil
	}
	if !validID(c.RootCommentID) || c.RootCommentID == c.CommentID || !validID(c.TargetCommentID) || c.TargetCommentID == c.CommentID || c.TargetAuthor == nil {
		return ErrInvalid
	}
	if _, err := json.Marshal(c.TargetAuthor); err != nil {
		return ErrInvalid
	}
	return nil
}

// OwnerCapabilities is fetched privately; public comment projections do not
// reveal whether two public identities share a logged-in account.
type OwnerCapabilities struct {
	CommentID string `json:"commentId"`
	CanDelete bool   `json:"canDelete"`
}
