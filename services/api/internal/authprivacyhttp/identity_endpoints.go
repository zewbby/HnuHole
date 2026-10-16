package authprivacyhttp

import (
    "context"
    "errors"
    "net/http"
    "strings"
    "time"

    "github.com/google/uuid"
    "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

// IdentityBackend is the private, owner-only management contract. No public
// lookup or account identifier is exposed by this HTTP surface.
type IdentityBackend interface {
    ListOwnIdentities(context.Context, [32]byte) (authprivacy.IdentityDirectory, error)
    ChangeOwnIdentity(context.Context, authprivacy.IdentityChangeRequest) (authprivacy.IdentityChangeResult, error)
    GetIdentityChangeResult(context.Context, [32]byte, [16]byte) (authprivacy.IdentityChangeResult, error)
}

const identitiesPath = "/api/v1/identities"
const identityResultPath = "/api/v1/identity-change-result"

func isIdentityPath(path string) bool {
    return path == identitiesPath || path == identityResultPath || strings.HasPrefix(path, identitiesPath+"/")
}

func identityPathID(path string) (uuid.UUID, error) {
    raw := strings.TrimPrefix(path, identitiesPath+"/")
    id, err := uuid.Parse(raw)
    if !strings.HasPrefix(path, identitiesPath+"/") || err != nil || id == uuid.Nil || raw != id.String() {
        return uuid.Nil, errMalformed
    }
    return id, nil
}

func (b *boundary) communityIdentitiesPublic(w http.ResponseWriter, r *http.Request, backend IdentityBackend) {
    allowed := "GET, POST"
    if r.URL.Path == identityResultPath { allowed = "GET" }
    if strings.HasPrefix(r.URL.Path, identitiesPath+"/") {
        if _, err := identityPathID(r.URL.Path); err != nil { b.bad(w, err); return }
        allowed = "PATCH, DELETE"
    }
    if !publicMethodAllowed(CommunityService, r.URL.Path, r.Method) {
        w.Header().Set("Allow", allowed)
        b.fail(w, 405, "MALFORMED_REQUEST", 0)
        return
    }
    for _, header := range []string{"V-Installation-ID", "OTP-Flow-ID", "Reset-Intent-ID", "Credential-Change-ID"} {
        if hasHeader(r.Header, header) { b.bad(w, errMalformed); return }
    }
    bearer, err := sessionCapability(r.Header, "Bearer")
    if err != nil { b.sessionCapabilityFailure(w, err); return }
    if backend == nil { b.fail(w, 503, "SERVICE_UNAVAILABLE", 0); return }
    if r.Method == http.MethodGet && r.URL.Path == identitiesPath {
        if hasHeader(r.Header, "Idempotency-Key") || noBodyOrQuery(r) != nil { b.bad(w, errMalformed); return }
        result, err := backend.ListOwnIdentities(r.Context(), bearer)
        if err != nil { b.identityFailure(w, err); return }
        if result.ExpiresAt.IsZero() || result.ServerTime.IsZero() || len(result.Identities) > 3 || result.CreatedCount < int64(len(result.Identities)) {
            b.fail(w, 503, "SERVICE_UNAVAILABLE", 0); return
        }
        items := make([]ownIdentityRecord, 0, len(result.Identities))
        ids, names := map[uuid.UUID]bool{}, map[string]bool{}
        originals := 0
        for _, item := range result.Identities {
            canonical, nameErr := authprivacy.ValidateIdentityNickname(item.Nickname)
            if nameErr != nil || canonical != item.Nickname || item.ID == uuid.Nil || item.Avatar != "default-v1" || item.CreatedAt.IsZero() || ids[item.ID] || names[item.Nickname] {
                b.fail(w, 503, "SERVICE_UNAVAILABLE", 0); return
            }
            if item.IsOriginal { originals++ }
            ids[item.ID], names[item.Nickname] = true, true
            items = append(items, ownIdentityRecord{item.ID.String(), item.Nickname, item.Avatar, item.IsOriginal, utc(item.CreatedAt), nullableUTC(item.RenameAvailableAt)})
        }
        if originals > 1 || (result.CreatedCount >= 3 && result.NextCreateAt == nil) || (result.CreatedCount < 3 && result.NextCreateAt != nil) {
            b.fail(w, 503, "SERVICE_UNAVAILABLE", 0); return
        }
        w.Header().Set("Session-Expires-At", utc(result.ExpiresAt))
        writeJSON(w, 200, struct {
            Identities []ownIdentityRecord `json:"identities"`
            CreatedCount int64 `json:"createdCount"`
            NextCreateAt *string `json:"nextCreateAt"`
            ServerTime string `json:"serverTime"`
        }{items, result.CreatedCount, nullableUTC(result.NextCreateAt), utc(result.ServerTime)})
        return
    }
    raw, err := headerBytes(r.Header, "Idempotency-Key", 16)
    if err != nil { b.bad(w, err); return }
    var key [16]byte
    copy(key[:], raw)
    if r.URL.Path == identityResultPath {
        if noBodyOrQuery(r) != nil { b.bad(w, errMalformed); return }
        result, err := backend.GetIdentityChangeResult(r.Context(), bearer, key)
        if err != nil { b.identityFailure(w, err); return }
        b.writeIdentityChange(w, result, true)
        return
    }
    request := authprivacy.IdentityChangeRequest{Bearer: bearer, ChangeID: key}
    switch r.Method {
    case http.MethodPost:
        request.Operation = "CREATE"
    case http.MethodPatch:
        request.Operation = "RENAME"
        request.IdentityID, _ = identityPathID(r.URL.Path)
    case http.MethodDelete:
        request.Operation = "DELETE"
        request.IdentityID, _ = identityPathID(r.URL.Path)
    }
    if request.Operation == "DELETE" {
        if noBodyOrQuery(r) != nil { b.bad(w, errMalformed); return }
    } else {
        object, err := readRequestObject(r, 1024, []string{"nickname"}, nil)
        if err != nil { b.bad(w, err); return }
        request.Nickname, err = stringField(object, "nickname")
        if err != nil { b.bad(w, err); return }
    }
    result, err := backend.ChangeOwnIdentity(r.Context(), request)
    if err != nil { b.identityFailure(w, err); return }
    if result.State == "REJECTED" && result.Operation == request.Operation && result.IdentityID == uuid.Nil && !result.ExpiresAt.IsZero() {
        status := identityRejectionStatus(result.ErrorCode)
        if status != 0 { b.fail(w, status, result.ErrorCode, 0); return }
    }
    if result.Operation != request.Operation || (request.Operation != "CREATE" && result.IdentityID != request.IdentityID) {
        b.fail(w, 503, "SERVICE_UNAVAILABLE", 0); return
    }
    b.writeIdentityChange(w, result, false)
}

type ownIdentityRecord struct {
    ID string `json:"id"`
    Nickname string `json:"nickname"`
    Avatar string `json:"avatar"`
    IsOriginal bool `json:"isOriginal"`
    CreatedAt string `json:"createdAt"`
    RenameAvailableAt *string `json:"renameAvailableAt"`
}

func nullableUTC(value *time.Time) *string {
    if value == nil { return nil }
    result := utc(*value)
    return &result
}

func (b *boundary) writeIdentityChange(w http.ResponseWriter, result authprivacy.IdentityChangeResult, query bool) {
    var operation, id, errorCode *string
    validOperation := result.Operation == "CREATE" || result.Operation == "RENAME" || result.Operation == "DELETE"
    if result.State == "COMMITTED" && result.IdentityID != uuid.Nil && validOperation && result.ErrorCode == "" {
        raw := result.IdentityID.String()
        operation, id = &result.Operation, &raw
    } else if query && result.State == "REJECTED" && validOperation && result.IdentityID == uuid.Nil && identityRejectionStatus(result.ErrorCode) != 0 {
        operation, errorCode = &result.Operation, &result.ErrorCode
    } else if !query || result.State != "NOT_FOUND" || result.Operation != "" || result.IdentityID != uuid.Nil || result.ErrorCode != "" {
        b.fail(w, 503, "SERVICE_UNAVAILABLE", 0); return
    }
    if result.ExpiresAt.IsZero() { b.fail(w, 503, "SERVICE_UNAVAILABLE", 0); return }
    w.Header().Set("Session-Expires-At", utc(result.ExpiresAt))
    writeJSON(w, 200, struct {
        State string `json:"state"`
        Operation *string `json:"operation"`
        IdentityID *string `json:"identityId"`
        ErrorCode *string `json:"errorCode"`
    }{result.State, operation, id, errorCode})
}

func identityRejectionStatus(code string) int {
    switch code {
    case "IDENTITY_INVALID_NAME": return 400
    case "IDENTITY_NOT_FOUND": return 404
    case "IDENTITY_DUPLICATE_NAME", "IDENTITY_LIMIT", "IDENTITY_CREATE_COOLDOWN", "IDENTITY_RENAME_COOLDOWN", "IDENTITY_LAST_REQUIRED": return 409
    }
    return 0
}

func (b *boundary) identityFailure(w http.ResponseWriter, err error) {
    failures := []struct{ err error; status int; code string }{
        {authprivacy.ErrIdentityInvalidName, 400, "IDENTITY_INVALID_NAME"},
        {authprivacy.ErrIdentityDuplicateName, 409, "IDENTITY_DUPLICATE_NAME"},
        {authprivacy.ErrIdentityLimit, 409, "IDENTITY_LIMIT"},
        {authprivacy.ErrIdentityCreateCooldown, 409, "IDENTITY_CREATE_COOLDOWN"},
        {authprivacy.ErrIdentityRenameCooldown, 409, "IDENTITY_RENAME_COOLDOWN"},
        {authprivacy.ErrIdentityLast, 409, "IDENTITY_LAST_REQUIRED"},
        {authprivacy.ErrIdentityNotFound, 404, "IDENTITY_NOT_FOUND"},
        {authprivacy.ErrIdentityChangeConflict, 409, "IDENTITY_CHANGE_CONFLICT"},
    }
    for _, failure := range failures {
        if errors.Is(err, failure.err) { b.fail(w, failure.status, failure.code, 0); return }
    }
    b.sessionFailure(w, err)
}
