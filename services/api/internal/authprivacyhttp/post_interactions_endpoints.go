package authprivacyhttp

import (
	"context"
	"net/http"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type PostInteractionBackend interface {
	ReadPostInteractions(context.Context, [32]byte, []string) (authprivacy.PostResponse, error)
	SetPostInteraction(context.Context, [32]byte, string, posts.InteractionKind, bool) (authprivacy.PostResponse, error)
}

func isPostInteractionKind(kind authprivacy.PostReadKind) bool {
	return kind == authprivacy.PostInteractions || kind == authprivacy.PostInteractionBatch || kind == authprivacy.PostLikeSet || kind == authprivacy.PostFavoriteSet
}

func (b *boundary) communityPostInteractions(w http.ResponseWriter, r *http.Request, backend PostBackend, bearer [32]byte, route postRoute) {
	var ids []string
	var enabled bool
	var err error
	switch route.kind {
	case authprivacy.PostInteractions:
		err = noBodyOrQuery(r)
		ids = []string{route.id}
	case authprivacy.PostInteractionBatch:
		var object map[string]any
		object, err = readRequestObject(r, 4096, []string{"postIds"}, nil)
		if err == nil {
			array, ok := object["postIds"].([]any)
			if !ok {
				err = errMalformed
			} else {
				for _, v := range array {
					id, ok := v.(string)
					if !ok {
						err = errMalformed
						break
					}
					ids = append(ids, id)
				}
				if posts.ValidateInteractionIDs(ids) != nil {
					err = errMalformed
				}
			}
		}
	default:
		field := "liked"
		if route.kind == authprivacy.PostFavoriteSet {
			field = "favorited"
		}
		var object map[string]any
		object, err = readRequestObject(r, 1024, []string{field}, nil)
		if err == nil {
			var ok bool
			enabled, ok = object[field].(bool)
			if !ok {
				err = errMalformed
			}
		}
		route.enabled = &enabled
	}
	if err != nil {
		b.postBad(w, err)
		return
	}
	interactions, ok := backend.(PostInteractionBackend)
	if !ok {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	var response authprivacy.PostResponse
	if route.kind == authprivacy.PostInteractions || route.kind == authprivacy.PostInteractionBatch {
		route.ids = ids
		response, err = interactions.ReadPostInteractions(r.Context(), bearer, ids)
		if err == nil && route.kind == authprivacy.PostInteractions {
			page, ok := response.Value.(posts.PostInteractionPage)
			if !ok || len(page.Items) != 1 {
				b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
				return
			}
			response.Value = page.Items[0]
		}
	} else {
		kind := posts.PostLike
		if route.kind == authprivacy.PostFavoriteSet {
			kind = posts.PostFavorite
		}
		response, err = interactions.SetPostInteraction(r.Context(), bearer, route.id, kind, enabled)
	}
	if err != nil {
		b.postFailure(w, err)
		return
	}
	b.writePostResponse(w, response, route, false)
}

func validPostInteractions(item posts.PostInteractions) bool {
	return postValidID(item.PostID) && item.LikeCount >= 0 && item.FavoriteCount >= 0 && item.CommentCount >= 0 && (!item.LikedByMe || item.LikeCount > 0) && (!item.FavoritedByMe || item.FavoriteCount > 0)
}

func strictPostInteractions(value any, route postRoute) (any, error) {
	if route.kind == authprivacy.PostInteractionBatch {
		page, ok := value.(posts.PostInteractionPage)
		if !ok || page.Items == nil || len(page.Items) != len(route.ids) {
			return nil, errMalformed
		}
		for i, item := range page.Items {
			if !validPostInteractions(item) || item.PostID != route.ids[i] {
				return nil, errMalformed
			}
		}
		return page, nil
	}
	item, ok := value.(posts.PostInteractions)
	if !ok || !validPostInteractions(item) || item.PostID != route.id {
		return nil, errMalformed
	}
	if route.enabled != nil && (route.kind == authprivacy.PostLikeSet && item.LikedByMe != *route.enabled || route.kind == authprivacy.PostFavoriteSet && item.FavoritedByMe != *route.enabled) {
		return nil, errMalformed
	}
	return item, nil
}
