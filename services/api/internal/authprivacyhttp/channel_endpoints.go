package authprivacyhttp

import (
    "errors"
    "net/http"

    "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
    "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/channels"
)

func (b *boundary) communityChannelsPublic(w http.ResponseWriter, r *http.Request, backend ChannelBackend) {
    if r.Method != http.MethodGet {
        w.Header().Set("Allow", http.MethodGet)
        b.fail(w, 405, "MALFORMED_REQUEST", 0)
        return
    }
    if noBodyOrQuery(r) != nil || hasHeader(r.Header, "V-Installation-ID") || hasHeader(r.Header, "OTP-Flow-ID") || hasHeader(r.Header, "Idempotency-Key") || hasHeader(r.Header, "Reset-Intent-ID") || hasHeader(r.Header, "Credential-Change-ID") {
        b.bad(w, errMalformed)
        return
    }
    bearer, err := sessionCapability(r.Header, "Bearer")
    if err != nil {
        b.sessionCapabilityFailure(w, err)
        return
    }
    if backend == nil {
        b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
        return
    }
    result, err := backend.ListAuthorizedChannels(r.Context(), bearer)
    if err != nil {
        if errors.Is(err, authprivacy.ErrChannelDirectoryUnavailable) {
            b.fail(w, 503, "CHANNEL_DIRECTORY_UNAVAILABLE", 0)
        } else {
            b.sessionFailure(w, err)
        }
        return
    }
    if result.ExpiresAt.IsZero() || channels.ValidateCatalog(result.Channels) != nil {
        b.fail(w, 503, "CHANNEL_DIRECTORY_UNAVAILABLE", 0)
        return
    }
    w.Header().Set("Session-Expires-At", utc(result.ExpiresAt))
    items := make([]channelRecord, 0, len(result.Channels))
    for _, item := range result.Channels {
        items = append(items, channelRecord{item.ID.String(), item.Code, item.Name, item.InitiallyVisible, item.DisplayOrder})
    }
    writeJSON(w, 200, struct { Channels []channelRecord `json:"channels"` }{items})
}

// Keep the five public fields explicit instead of serializing domain records.
type channelRecord struct {
    ID string `json:"id"`
    Code string `json:"code"`
    Name string `json:"name"`
    InitiallyVisible bool `json:"initiallyVisible"`
    DisplayOrder int `json:"displayOrder"`
}
