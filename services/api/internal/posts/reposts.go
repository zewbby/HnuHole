package posts

import "time"

// These DTOs are private to the authenticated owner. Never put them in feed DTOs.
type RepostMark struct {
	IdentityID string    `json:"identityId"`
	RepostedAt time.Time `json:"repostedAt"`
}
type RepostState struct {
	PostID string       `json:"postId"`
	Items  []RepostMark `json:"items"`
}
type RepostItem struct {
	PostID     string      `json:"postId"`
	IdentityID string      `json:"identityId"`
	RepostedAt time.Time   `json:"repostedAt"`
	Post       *PublicPost `json:"post"`
	ordinal    int64
}
type RepostPage struct {
	Items      []RepostItem `json:"items"`
	NextCursor *string      `json:"nextCursor"`
}
