package authprivacy

import (
	"crypto/sha256"
	"encoding/base64"
	"errors"

	"github.com/google/uuid"
)

type InactiveIdentityState string

const (
	IdentityDeleted        InactiveIdentityState = "DELETED"
	IdentityAccountClosed  InactiveIdentityState = "ACCOUNT_CLOSED"
	IdentityInactiveAvatar                       = "inactive-v1"
)

// InactiveIdentityProjection contains only identity-level presentation data.
// Future post/chat callers must first authorize their resource and determine
// its identity's lifecycle state. This pure projection provides neither an
// identity lookup endpoint nor access to an account or its other identities.
// PlaceholderToken is opaque data; its eventual human-facing number format
// and the visual avatar asset are product design decisions, not fixed here.
type InactiveIdentityProjection struct {
	PlaceholderToken string                `json:"placeholderToken"`
	Avatar           string                `json:"avatar"`
	State            InactiveIdentityState `json:"state"`
}

// ProjectInactiveIdentityLifecycle gives formal account closure precedence
// over an earlier individual deletion, without changing that old tombstone.
// Both flags must come from the authorized business resource read; this helper
// intentionally accepts no account identifier or any other identity's data.
func ProjectInactiveIdentityLifecycle(identity uuid.UUID, accountClosed, identityDeleted bool) (InactiveIdentityProjection, error) {
	if accountClosed {
		return ProjectInactiveIdentity(identity, IdentityAccountClosed)
	}
	if identityDeleted {
		return ProjectInactiveIdentity(identity, IdentityDeleted)
	}
	return InactiveIdentityProjection{}, errors.New("active identity has no inactive projection")
}

func ProjectInactiveIdentity(identity uuid.UUID, state InactiveIdentityState) (InactiveIdentityProjection, error) {
	if identity == uuid.Nil || (state != IdentityDeleted && state != IdentityAccountClosed) {
		return InactiveIdentityProjection{}, errors.New("invalid inactive identity projection")
	}
	// Different masks use different random identity UUIDs. No account ID,
	// original-mask flag, nickname, timestamp or shared account number enters
	// this token, including when several masks close in the same transaction.
	message := append([]byte("HNUHOLE/INACTIVE-IDENTITY-PROJECTION/V1\x00"), identity[:]...)
	digest := sha256.Sum256(message)
	return InactiveIdentityProjection{
		PlaceholderToken: base64.RawURLEncoding.EncodeToString(digest[:]),
		Avatar:           IdentityInactiveAvatar,
		State:            state,
	}, nil
}
