package posts

import "encoding/hex"

func ValidInteractionVersion(tag string) bool {
	if len(tag) != 66 || tag[0] != '"' || tag[65] != '"' {
		return false
	}
	for _, c := range tag[1:65] {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	_, err := hex.DecodeString(tag[1:65])
	return err == nil
}

type InteractionKind string

const (
	PostLike     InteractionKind = "like"
	PostFavorite InteractionKind = "favorite"
)

// Only these booleans are account-private; counts never identify contributors.
type PostInteractions struct {
	PostID        string `json:"postId"`
	LikeCount     int64  `json:"likeCount"`
	FavoriteCount int64  `json:"favoriteCount"`
	CommentCount  int    `json:"commentCount"`
	LikedByMe     bool   `json:"likedByMe"`
	FavoritedByMe bool   `json:"favoritedByMe"`
}

type PostInteractionPage struct {
	Items []PostInteractions `json:"items"`
}

func ValidateInteractionIDs(ids []string) error {
	if len(ids) < 1 || len(ids) > 50 {
		return ErrInvalidIntent
	}
	seen := make(map[string]bool, len(ids))
	for _, id := range ids {
		if _, err := ParseResourceID(id); err != nil || seen[id] {
			return ErrInvalidIntent
		}
		seen[id] = true
	}
	return nil
}
