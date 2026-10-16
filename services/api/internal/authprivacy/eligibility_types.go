package authprivacy

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

// Eligibility is the isolated V application boundary. Keys are supplied by the
// operator separately from the database; none is generated from an address.
type Eligibility struct {
	store      *VerifierStore
	config     EligibilityConfig
	signer     Signer
	mail       MailProvider
	retirePeer RetirementPeer
}

type EligibilityConfig struct {
	OTPKey                   [32]byte
	OTPKeyVersion            int64
	MailEncryptionKey        [32]byte
	MailEncryptionKeyVersion int64
	RequestHMACKey           [32]byte
	HMACKeyVersion           int64
	LimitKey                 [32]byte
	RegistrationEpoch        uint32
	SendBudget               int
	VerifyBudget             int
}

func NewEligibility(store *VerifierStore, config EligibilityConfig, signer Signer, mail MailProvider, peer RetirementPeer) (*Eligibility, error) {
	if store == nil || signer == nil || mail == nil || peer == nil ||
		config.OTPKey == ([32]byte{}) || config.MailEncryptionKey == ([32]byte{}) ||
		config.RequestHMACKey == ([32]byte{}) || config.LimitKey == ([32]byte{}) ||
		config.OTPKeyVersion < 1 || config.MailEncryptionKeyVersion < 1 || config.HMACKeyVersion < 1 ||
		config.SendBudget < 1 || config.VerifyBudget < 1 {
		return nil, errors.New("invalid eligibility configuration")
	}
	keys := [][32]byte{config.OTPKey, config.MailEncryptionKey, config.RequestHMACKey, config.LimitKey, store.addressLockKey}
	seen := make(map[[32]byte]bool, len(keys))
	for _, key := range keys {
		if seen[key] {
			return nil, errors.New("eligibility key purposes must be separated")
		}
		seen[key] = true
	}
	return &Eligibility{store: store, config: config, signer: signer, mail: mail, retirePeer: peer}, nil
}

type OTPRequest struct {
	Key            [32]byte
	InstallationID [16]byte
	Email          string
}

type OTPRequestResult struct {
	State             string
	FlowID            [32]byte
	RetryAfterSeconds int
	PollAfterSeconds  int
}

type ConfirmOTPRequest struct {
	Key                [32]byte
	FlowID             [32]byte
	InstallationID     [16]byte
	OTP                string
	SlotID             protocol.SlotID
	BootstrapPublicKey protocol.PublicKey
	ReleaseReceipt     string
}

type ConfirmationResult struct {
	State              string
	RegistrationTicket string
	RetryAfterSeconds  int
}

type OTPVerification struct {
	AttemptCounted bool
	Email          []byte
	FlowID         [32]byte
	Generation     int64
	ExpiresAt      time.Time
	VerifiedAt     time.Time
}

type MailOutcome string

const (
	MailSent    MailOutcome = "SENT"
	MailNotSent MailOutcome = "NOT_SENT"
	MailUnknown MailOutcome = "UNKNOWN"
)

// MailUnknown includes a connection lost after SMTP DATA: acceptance cannot be
// inferred from a timeout. The durable outbox prevents automatic duplicate mail.
type MailProvider interface {
	SendOTP(context.Context, [32]byte, string, string) (MailOutcome, error)
}

type RetirementReply struct {
	Receipt           string
	Pending           bool
	SlotNotRetirable  bool
	RetryAfterSeconds int
}

type RetirementPeer interface {
	RetireUnusedSlot(context.Context, string) (RetirementReply, error)
}

// EligibilityError contains only public contract codes, never database errors,
// addresses, codes, keys or receipts. Internal errors are hidden by HTTP adapters.
type EligibilityError struct {
	Code              string
	RetryAfterSeconds int
}

func (e *EligibilityError) Error() string { return e.Code }
func (e *EligibilityError) Is(target error) bool {
	t, ok := target.(*EligibilityError)
	return ok && e.Code == t.Code
}

var (
	ErrBadRequest            = &EligibilityError{Code: "REQUEST_INVALID"}
	ErrEmailInvalid          = &EligibilityError{Code: "EMAIL_INVALID"}
	ErrOTPInvalid            = &EligibilityError{Code: "OTP_INVALID"}
	ErrOTPExpired            = &EligibilityError{Code: "OTP_EXPIRED"}
	ErrOTPReplaced           = &EligibilityError{Code: "OTP_REPLACED"}
	ErrOTPFlowInvalid        = &EligibilityError{Code: "OTP_FLOW_INVALID"}
	ErrResultAuthentication  = &EligibilityError{Code: "AUTHENTICATION_FAILED"}
	ErrRateLimited           = &EligibilityError{Code: "RATE_LIMITED"}
	ErrBootstrapKeyInvalid   = &EligibilityError{Code: "BOOTSTRAP_KEY_INVALID"}
	ErrSlotBindingInvalid    = &EligibilityError{Code: "SLOT_BINDING_INVALID"}
	ErrReleaseReceiptInvalid = &EligibilityError{Code: "RELEASE_RECEIPT_INVALID"}
	ErrEligibilityReserved   = &EligibilityError{Code: "ELIGIBILITY_RESERVED"}
	ErrReverifyRequired      = &EligibilityError{Code: "REVERIFY_REQUIRED"}
)

func eligibilityError(code string, retry int) error {
	if retry < 0 {
		return fmt.Errorf("invalid eligibility retry")
	}
	return &EligibilityError{Code: code, RetryAfterSeconds: retry}
}
