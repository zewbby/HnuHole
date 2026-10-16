package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/auth"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/channels"
)

type SessionValidator interface {
	Validate(ctx context.Context, token string) (string, error)
}

type Handler struct {
	directory *channels.Service
}

func NewRouter(directory *channels.Service, sessions SessionValidator) http.Handler {
	h := &Handler{directory: directory}
	r := chi.NewRouter()
	r.Use(requestID)
	r.Get("/healthz", health)
	r.Route("/api/v1", func(r chi.Router) {
		r.With(requireSession(sessions)).Get("/channels", h.listChannels)
	})
	return r
}

type requestIDKey struct{}

func requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := strings.TrimSpace(r.Header.Get("X-Request-ID"))
		if id == "" {
			id = uuid.NewString()
		}
		ctx := context.WithValue(r.Context(), requestIDKey{}, id)
		w.Header().Set("X-Request-ID", id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func requireSession(sessions SessionValidator) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if sessions == nil {
				writeError(w, r, http.StatusUnauthorized, "AUTHENTICATION_REQUIRED", "authentication is required")
				return
			}
			header := strings.TrimSpace(r.Header.Get("Authorization"))
			parts := strings.SplitN(header, " ", 2)
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
				writeError(w, r, http.StatusUnauthorized, "AUTHENTICATION_REQUIRED", "authentication is required")
				return
			}
			if _, err := sessions.Validate(r.Context(), strings.TrimSpace(parts[1])); err != nil {
				if errors.Is(err, auth.ErrInvalidSession) {
					writeError(w, r, http.StatusUnauthorized, "AUTHENTICATION_REQUIRED", "authentication is required")
					return
				}
				writeError(w, r, http.StatusServiceUnavailable, "AUTHENTICATION_UNAVAILABLE", "authentication is temporarily unavailable")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

type channelResponse struct {
	ID               string `json:"id"`
	Code             string `json:"code"`
	Name             string `json:"name"`
	InitiallyVisible bool   `json:"initiallyVisible"`
	DisplayOrder     int    `json:"displayOrder"`
}

type channelListResponse struct {
	Channels []channelResponse `json:"channels"`
}

func (h *Handler) listChannels(w http.ResponseWriter, r *http.Request) {
	items, err := h.directory.List(r.Context())
	if err != nil {
		writeError(w, r, http.StatusServiceUnavailable, "CHANNEL_DIRECTORY_UNAVAILABLE", "channel directory is temporarily unavailable")
		return
	}

	response := channelListResponse{Channels: make([]channelResponse, 0, len(items))}
	for _, item := range items {
		response.Channels = append(response.Channels, channelResponse{
			ID:               item.ID.String(),
			Code:             item.Code,
			Name:             item.Name,
			InitiallyVisible: item.InitiallyVisible,
			DisplayOrder:     item.DisplayOrder,
		})
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, response)
}

func health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type errorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details any    `json:"details,omitempty"`
}

type errorResponse struct {
	Error     errorDetail `json:"error"`
	RequestID string      `json:"requestId"`
}

func writeError(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	requestID, _ := r.Context().Value(requestIDKey{}).(string)
	writeJSON(w, status, errorResponse{
		Error:     errorDetail{Code: code, Message: message},
		RequestID: requestID,
	})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		return
	}
}
