package authprivacyhttp

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

type PostImageBackend interface {
	ReadPostImageUploads(context.Context, [32]byte, string, int32) (authprivacy.PostResponse, error)
	IssuePostImageGrant(context.Context, [32]byte, string, string, int32) (authprivacy.PostResponse, error)
	UploadPostImage(context.Context, [32]byte, string, string, int32, []byte, string) (time.Time, error)
	ReadPostImages(context.Context, [32]byte, string, string) (authprivacy.PostResponse, error)
}

type PostImageThumbnailBackend interface {
	PostImageThumbnailsEnabled() bool
	ReadPostThumbnail(context.Context, [32]byte, string, string) (authprivacy.PostResponse, error)
}

// Explicit negotiation keeps old strict clients and original-only deployments usable.
func postPreviewRequested(r *http.Request) (bool, error) {
	if !hasHeader(r.Header, "X-Post-Preview") {
		return false, nil
	}
	value, err := singleHeader(r.Header, "X-Post-Preview")
	if err != nil || value != "thumbnail-v1" {
		return false, errMalformed
	}
	return true, nil
}

func isPostImagePath(path string) bool {
	p := strings.Split(strings.TrimPrefix(path, "/api/v1/"), "/")
	return len(p) >= 3 && p[0] == "posts" && p[2] == "images" || len(p) >= 4 && p[0] == "me" && p[1] == "post-tasks" && p[3] == "attempts"
}

type imageRoute struct {
	kind, id, media, method string
	version                 int32
}

func parseImageRoute(path string) (imageRoute, error) {
	p := strings.Split(strings.TrimPrefix(path, "/api/v1/"), "/")
	var r imageRoute
	if !strings.HasPrefix(path, "/api/v1/") {
		return r, errMalformed
	}
	if len(p) >= 3 && p[0] == "posts" && postmedia.ValidID(p[1]) && p[2] == "images" {
		r.id = p[1]
		r.method = "GET"
		if len(p) == 3 {
			r.kind = "group"
			return r, nil
		}
		if len(p) == 5 && postmedia.ValidID(p[3]) && (p[4] == "original" || p[4] == "thumbnail") {
			r.kind = p[4]
			r.media = p[3]
			return r, nil
		}
	}
	if len(p) >= 6 && p[0] == "me" && p[1] == "post-tasks" && postmedia.ValidID(p[2]) && p[3] == "attempts" && p[5] == "images" {
		v, e := strconv.ParseInt(p[4], 10, 32)
		if e != nil || v < 1 || strconv.FormatInt(v, 10) != p[4] {
			return r, errMalformed
		}
		r.id = p[2]
		r.version = int32(v)
		if len(p) == 6 {
			r.kind = "uploads"
			r.method = "GET"
			return r, nil
		}
		if len(p) == 8 && postmedia.ValidID(p[6]) {
			r.media = p[6]
			switch p[7] {
			case "upload-grant":
				r.kind = "grant"
				r.method = "POST"
				return r, nil
			case "bytes":
				r.kind = "put"
				r.method = "PUT"
				return r, nil
			}
		}
	}
	return r, errMalformed
}

func (b *boundary) imageFailure(w http.ResponseWriter, e error) {
	switch {
	case errors.Is(e, postmedia.ErrInvalid):
		b.postFail(w, 422, "MEDIA_INVALID", 0)
	case errors.Is(e, postmedia.ErrUnavailable):
		b.postFail(w, 503, "MEDIA_VALIDATOR_UNAVAILABLE", 0)
	default:
		var failure *authprivacy.PostError
		if errors.As(e, &failure) {
			statuses := map[string]int{"MEDIA_NOT_FOUND": 404, "MEDIA_UPLOAD_DENIED": 403, "MEDIA_UPLOAD_CLOSED": 409}
			if status := statuses[failure.Code]; status != 0 && status == failure.Status {
				b.postFail(w, status, failure.Code, 0)
				return
			}
		}
		b.postFailure(w, e)
	}
}

func (b *boundary) communityPostImages(w http.ResponseWriter, r *http.Request, backend PostImageBackend) {
	route, e := parseImageRoute(r.URL.Path)
	if e != nil || r.URL.RawPath != "" || r.URL.RawQuery != "" || r.URL.ForceQuery {
		b.postBad(w, errMalformed)
		return
	}
	preview, previewErr := postPreviewRequested(r)
	if previewErr != nil {
		b.postBad(w, previewErr)
		return
	}
	if r.Method != route.method {
		w.Header().Set("Allow", route.method)
		b.postFail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	for _, h := range []string{"V-Installation-ID", "OTP-Flow-ID", "Reset-Intent-ID", "Credential-Change-ID", "Content-Encoding", "Idempotency-Key", "Range", "If-None-Match", "If-Modified-Since"} {
		if hasHeader(r.Header, h) {
			b.postBad(w, errMalformed)
			return
		}
	}
	scheme := "Bearer"
	if route.kind == "put" {
		scheme = "Upload"
	}
	token, e := sessionCapability(r.Header, scheme)
	if e != nil {
		if errors.Is(e, errMalformed) {
			b.postBad(w, e)
		} else {
			b.postFail(w, 401, "AUTHENTICATION_FAILED", 0)
		}
		return
	}
	if backend == nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if route.kind == "put" {
		mime, e := singleHeader(r.Header, "Content-Type")
		if e != nil {
			b.postBad(w, errMediaType)
			return
		}
		switch mime {
		case "image/jpeg", "image/png", "image/gif", "image/webp":
		default:
			b.postBad(w, errMediaType)
			return
		}
		if r.ContentLength > postmedia.MaxBytes {
			b.postBad(w, errTooLarge)
			return
		}
		data, e := io.ReadAll(io.LimitReader(r.Body, postmedia.MaxBytes+1))
		if e != nil {
			b.postBad(w, errMalformed)
			return
		}
		if len(data) > postmedia.MaxBytes {
			b.postBad(w, errTooLarge)
			return
		}
		at, e := backend.UploadPostImage(r.Context(), token, route.id, route.media, route.version, data, mime)
		if e != nil {
			b.imageFailure(w, e)
			return
		}
		if !validPostTime(at) {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		w.Header().Set("Server-Time", utc(at))
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.WriteHeader(204)
		return
	}
	if noBodyOrQuery(r) != nil {
		b.postBad(w, errMalformed)
		return
	}
	var response authprivacy.PostResponse
	switch route.kind {
	case "grant":
		response, e = backend.IssuePostImageGrant(r.Context(), token, route.id, route.media, route.version)
	case "thumbnail":
		thumbnailer, ok := backend.(PostImageThumbnailBackend)
		if !ok || !thumbnailer.PostImageThumbnailsEnabled() {
			b.imageFailure(w, postmedia.ErrUnavailable)
			return
		}
		response, e = thumbnailer.ReadPostThumbnail(r.Context(), token, route.id, route.media)
	case "uploads":
		response, e = backend.ReadPostImageUploads(r.Context(), token, route.id, route.version)
	default:
		response, e = backend.ReadPostImages(r.Context(), token, route.id, route.media)
	}
	if e != nil {
		b.imageFailure(w, e)
		return
	}
	if !validPostTime(response.ServerTime) || !validPostTime(response.ExpiresAt) || !response.ExpiresAt.After(response.ServerTime) {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	var encoded []byte
	var mime string
	switch route.kind {
	case "original", "thumbnail":
		v, ok := response.Value.(authprivacy.ImageBytes)
		if !ok || len(v.Bytes) < 1 || len(v.Bytes) > postmedia.MaxBytes {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		switch v.MIME {
		case "image/jpeg", "image/png", "image/gif", "image/webp":
		default:
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		if route.kind == "thumbnail" && (v.MIME != "image/webp" || len(v.Bytes) > postmedia.MaxThumbnailBytes) {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		encoded = v.Bytes
		mime = v.MIME
	case "group":
		v, ok := response.Value.(postmedia.Group)
		if !ok || !validImageGroup(v, route.id, response.ServerTime, response.ExpiresAt) {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		if thumbnailer, ok := backend.(PostImageThumbnailBackend); preview && ok && thumbnailer.PostImageThumbnailsEnabled() {
			// Copy the slice: response validation must not mutate backend state.
			v.Images = append([]postmedia.Image{}, v.Images...)
			for i := range v.Images {
				v.Images[i].Thumbnail = postmedia.Source{
					Path: "/api/v1/posts/" + route.id + "/images/" + v.Images[i].ContentVersionID + "/thumbnail",
					MIME: "image/webp", MaxByteLength: postmedia.MaxThumbnailBytes,
				}
			}
		}
		encoded, e = json.Marshal(v)
	case "uploads":
		v, ok := response.Value.(postmedia.UploadState)
		if !ok || v.TaskID != route.id || v.AttemptVersion != route.version || !postmedia.ValidID(v.PostID) || v.Items == nil || len(v.Items) > 9 {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		items := make([]postmedia.Selection, len(v.Items))
		for i, s := range v.Items {
			if s.Position != i {
				b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
				return
			}
			items[i] = s.Selection
		}
		if postmedia.ValidateManifest(items) != nil {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		encoded, e = json.Marshal(v)
	case "grant":
		v, ok := response.Value.(postmedia.Grant)
		expires, err := time.Parse(time.RFC3339Nano, v.ExpiresAt)
		_, tokenError := protocol.DecodeCanonicalBase64url(v.UploadToken, 32)
		if !ok || v.TaskID != route.id || v.MediaID != route.media || v.AttemptVersion != route.version || err != nil || !expires.After(response.ServerTime) || expires.After(response.ServerTime.Add(15*time.Minute)) || tokenError != nil {
			b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		encoded, e = json.Marshal(v)
	default:
		e = errMalformed
	}
	if e != nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Session-Expires-At", utc(response.ExpiresAt))
	w.Header().Set("Server-Time", utc(response.ServerTime))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
	w.Header().Add("Vary", "Authorization")
	w.Header().Set("Pragma", "no-cache")
	if mime != "" {
		w.Header().Set("Content-Type", mime)
		w.Header().Set("Content-Disposition", "attachment")
		w.Header().Set("Content-Length", strconv.Itoa(len(encoded)))
	}
	w.WriteHeader(200)
	_, _ = w.Write(encoded)
}

func validImageGroup(v postmedia.Group, post string, at, expires time.Time) bool {
	until, e := time.Parse(time.RFC3339Nano, v.AccessValidUntil)
	if v.PostID != post || v.Images == nil || len(v.Images) > 9 || e != nil || !until.After(at) || until.After(at.Add(time.Minute)) || until.After(expires) {
		return false
	}
	ids := map[string]bool{}
	media := map[string]bool{}
	for i, s := range v.Images {
		if !postmedia.ValidID(s.MediaID) || !postmedia.ValidID(s.ContentVersionID) || ids[s.ContentVersionID] || media[s.MediaID] || s.Position != i || !postmedia.ValidSize(s.Width, s.Height) || !postmedia.ValidSize(s.PixelWidth, s.PixelHeight) || s.Frames < 1 || s.Frames > postmedia.MaxFrames || s.Animated != (s.Frames > 1) || !s.SaveAllowed {
			return false
		}
		ids[s.ContentVersionID] = true
		media[s.MediaID] = true
		expected := "/api/v1/posts/" + post + "/images/" + s.ContentVersionID + "/original"
		if s.Full != s.Thumbnail || s.Full != s.Original || s.Full.Path != expected || s.Full.ByteLength < 1 || s.Full.ByteLength > postmedia.MaxBytes || s.Full.MaxByteLength != 0 {
			return false
		}
		switch s.Full.MIME {
		case "image/jpeg", "image/png", "image/gif", "image/webp":
		default:
			return false
		}
	}
	return true
}
