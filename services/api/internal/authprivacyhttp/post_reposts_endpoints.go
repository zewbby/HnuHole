package authprivacyhttp

import (
	"context"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"net/http"
)

type PostRepostBackend interface {
	ReadPostReposts(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	SetPostRepost(context.Context, [32]byte, string, string, bool, string) (authprivacy.PostResponse, error)
	ListPostReposts(context.Context, [32]byte, authprivacy.PostQuery) (authprivacy.PostResponse, error)
}

func isRepostKind(kind authprivacy.PostReadKind) bool {
	return kind == authprivacy.PostRepostState || kind == authprivacy.PostRepostSet || kind == authprivacy.PostRepostList
}
func (b *boundary) communityPostReposts(w http.ResponseWriter, r *http.Request, backend PostBackend, bearer [32]byte, route postRoute) {
	service, ok := backend.(PostRepostBackend)
	if !ok {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if hasHeader(r.Header, "If-Match") {
		b.postBad(w, errMalformed)
		return
	}
	var response authprivacy.PostResponse
	var err error
	if r.Method == http.MethodPut {
		expected, e := singleHeader(r.Header, "If-Interaction-Version")
		if e != nil || !posts.ValidInteractionVersion(expected) {
			b.postBad(w, errMalformed)
			return
		}
		object, e := readRequestObject(r, 1024, []string{"identityId", "reposted"}, nil)
		if e != nil {
			b.postBad(w, e)
			return
		}
		identity, ok := object["identityId"].(string)
		enabled, yes := object["reposted"].(bool)
		if !ok || !yes || !postValidID(identity) {
			b.postBad(w, errMalformed)
			return
		}
		route.repostIdentity = identity
		route.enabled = &enabled
		response, err = service.SetPostRepost(r.Context(), bearer, route.id, identity, enabled, expected)
	} else {
		if hasHeader(r.Header, "If-Interaction-Version") {
			b.postBad(w, errMalformed)
			return
		}
		query, e := postReadQuery(r, route)
		if e != nil {
			b.postBad(w, e)
			return
		}
		route.limit = query.Limit
		if route.kind == authprivacy.PostRepostList {
			response, err = service.ListPostReposts(r.Context(), bearer, query)
		} else {
			response, err = service.ReadPostReposts(r.Context(), bearer, route.id)
		}
	}
	if err != nil {
		b.postFailure(w, err)
		return
	}
	if route.kind != authprivacy.PostRepostList && !posts.ValidInteractionVersion(response.InteractionVersion) {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	b.writePostResponse(w, response, route, false)
}
func strictRepostValue(value any, route postRoute) (any, error) {
	if route.kind == authprivacy.PostRepostList {
		page, ok := value.(posts.RepostPage)
		if !ok || page.Items == nil || !validPostPageSize(len(page.Items), route.limit) || !validNullablePostCursor(page.NextCursor) {
			return nil, errMalformed
		}
		seen := map[string]bool{}
		for _, item := range page.Items {
			key := item.IdentityID + "/" + item.PostID
			if !postValidID(item.PostID) || !postValidID(item.IdentityID) || !validPostTime(item.RepostedAt) || seen[key] {
				return nil, errMalformed
			}
			seen[key] = true
			if item.Post != nil {
				if _, err := strictPostValue(posts.PublicPostResponse{Post: *item.Post}, postRoute{kind: authprivacy.PostDetail, id: item.PostID}); err != nil {
					return nil, err
				}
			}
		}
		return page, nil
	}
	state, ok := value.(posts.RepostState)
	if !ok || state.PostID != route.id || state.Items == nil || len(state.Items) > 3 {
		return nil, errMalformed
	}
	seen := map[string]bool{}
	for _, item := range state.Items {
		if !postValidID(item.IdentityID) || !validPostTime(item.RepostedAt) || seen[item.IdentityID] {
			return nil, errMalformed
		}
		seen[item.IdentityID] = true
	}
	if route.enabled != nil && seen[route.repostIdentity] != *route.enabled {
		return nil, errMalformed
	}
	return state, nil
}
