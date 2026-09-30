package authprivacy

import (
	"context"
	"errors"
	"time"
)

var (
	ErrCredentialNotFound      = errors.New("credential not found")
	ErrCredentialIntentInvalid = errors.New("credential intent invalid")
	ErrCredentialIntentExpired = errors.New("credential intent expired")
	ErrPasskeyLimit            = errors.New("passkey limit reached")
)

type PasskeySummary struct {
	CredentialID   string
	CreatedAt      time.Time
	BackupEligible bool
	BackedUp       bool
}
type RecoveryCredentials struct {
	RecoveryCodeAvailable bool
	Passkeys              []PasskeySummary
	SessionExpiresAt      time.Time
}
type CodeRotationIntent struct {
	ID               [32]byte
	ExpiresAt        time.Time
	NewRecoveryCode  string
	SessionExpiresAt time.Time
}
type CodeRotationConfirmation struct {
	IntentID                    [32]byte
	IdempotencyKey              [32]byte
	NewRecoveryCodeConfirmation string
}
type PasskeyOptions struct {
	ChallengeID      [32]byte
	ExpiresAt        time.Time
	PublicKey        map[string]any
	SessionExpiresAt time.Time
}
type PasskeyRegistration struct {
	ChallengeID    [32]byte
	IdempotencyKey [32]byte
	Response       RegistrationResponse
}
type PasskeyRemovalIntent struct {
	ID               [32]byte
	ExpiresAt        time.Time
	SessionExpiresAt time.Time
}
type PasskeyRemoval struct {
	IntentID       [32]byte
	IdempotencyKey [32]byte
	CredentialID   string
}
type PasskeyResetProof struct {
	ChallengeID [32]byte
	Response    AssertionResponse
}

// WithWebAuthn returns an independent immutable configuration view. Existing
// callers remain fail closed for WebAuthn until they explicitly supply trusted
// deployment configuration; request hosts and origins never select this policy.
func (c *Community) WithWebAuthn(config WebAuthnConfig) (*Community, error) {
	validator, err := NewWebAuthnValidator(config)
	if err != nil {
		return nil, err
	}
	copy := *c
	copy.webauthn = validator
	copy.webauthnConfig = WebAuthnConfig{RPID: config.RPID, Origins: append([]string(nil), config.Origins...)}
	return &copy, nil
}

// CredentialBackend is implemented by Community; HTTP consumes these typed
// results and exposes only the published response fields.
type CredentialBackend interface {
	GetRecoveryCredentials(context.Context, [32]byte) (RecoveryCredentials, error)
	CreateRecoveryCodeRotation(context.Context, [32]byte, string, PasswordVerifier) (CodeRotationIntent, error)
	ConfirmRecoveryCodeRotation(context.Context, [32]byte, CodeRotationConfirmation) (time.Time, error)
	CreatePasskeyOptions(context.Context, [32]byte, string, PasswordVerifier) (PasskeyOptions, error)
	RegisterPasskey(context.Context, [32]byte, PasskeyRegistration) (time.Time, error)
	CreatePasskeyRemovalIntent(ctx context.Context, bearer [32]byte, password string, credentialID string, verifier PasswordVerifier) (PasskeyRemovalIntent, error)
	RemovePasskey(context.Context, [32]byte, PasskeyRemoval) (time.Time, error)
	CreatePasskeyResetOptions(context.Context) (PasskeyOptions, error)
	CreatePasskeyResetIntent(context.Context, PasskeyResetProof) (PasswordResetIntent, error)
}
