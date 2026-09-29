// Package protocol implements the fixed authentication protocol frames used by
// the isolated authprivacy validation slice. It does not implement account
// control, slot state transitions, trusted clocks, or disaster recovery gates.
package protocol

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"time"

	"filippo.io/edwards25519"
)

type SlotID [32]byte
type PublicKey [32]byte
type IntentID [32]byte
type Challenge [32]byte
type Signature [64]byte

type Purpose string

const (
	PurposeRegister   Purpose = "REGISTER/V2"
	PurposeRetireAuth Purpose = "RETIRE-AUTH/V1"
	PurposeRetired    Purpose = "RETIRED/V1"
	PurposeReleased   Purpose = "RELEASED/V1"

	RegistrationMessageLength = 92
	RegistrationTicketLength  = 156
	RetirementMessageLength   = 59
	RetirementTicketLength    = 123
	RetiredMessageLength      = 55
	RetiredReceiptLength      = 119
	ReleasedMessageLength     = 56
	ReleasedReceiptLength     = 120
	BootstrapMessageLength    = 153
	AdmissionWindowSeconds    = 1800
)

var (
	ErrEncoding          = errors.New("noncanonical base64url encoding")
	ErrLength            = errors.New("invalid fixed byte length")
	ErrPurpose           = errors.New("unsupported or mismatched protocol purpose")
	ErrPoint             = errors.New("point is not canonical nonidentity prime subgroup")
	ErrSignature         = errors.New("invalid strict Pure Ed25519 signature")
	ErrSlotBinding       = errors.New("slot is not bound to bootstrap key")
	ErrKeyUntrusted      = errors.New("untrusted key purpose or epoch")
	ErrKeyRevoked        = errors.New("trusted key revoked")
	ErrKeyEnvironment    = errors.New("trusted key environment mismatch")
	ErrKeyConfiguration  = errors.New("invalid trusted key configuration")
	ErrTimeInvalid       = errors.New("decision time cannot be represented by protocol")
	ErrTicketExpired     = errors.New("registration ticket expired")
	ErrTicketNotYetValid = errors.New("registration ticket not yet valid")
)

// DecodeCanonicalBase64url accepts exactly expectedLength bytes, encoded with
// the unpadded URL alphabet and zero trailing bits. Length is checked before
// allocation. Newlines are rejected even though encoding/base64 ignores them.
func DecodeCanonicalBase64url(encoded string, expectedLength int) ([]byte, error) {
	if expectedLength < 0 || expectedLength > math.MaxInt/8 || len(encoded) != base64.RawURLEncoding.EncodedLen(expectedLength) {
		return nil, ErrLength
	}
	for i := range encoded {
		c := encoded[i]
		if !(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_') {
			return nil, ErrEncoding
		}
	}
	decoded, err := base64.RawURLEncoding.Strict().DecodeString(encoded)
	if err != nil || base64.RawURLEncoding.EncodeToString(decoded) != encoded {
		return nil, ErrEncoding
	}
	if len(decoded) != expectedLength {
		return nil, ErrLength
	}
	return decoded, nil
}

func EncodeCanonicalBase64url(raw []byte) string {
	return base64.RawURLEncoding.EncodeToString(raw)
}

// ValidatePoint implements the project's stricter A/R acceptance profile.
// SetBytes alone is permissive: re-encoding rejects y>=p and negative zero.
func ValidatePoint(encoded []byte) error {
	if len(encoded) != 32 {
		return ErrLength
	}
	p, err := new(edwards25519.Point).SetBytes(encoded)
	if err != nil || !bytes.Equal(p.Bytes(), encoded) || p.Equal(edwards25519.NewIdentityPoint()) == 1 {
		return ErrPoint
	}
	// The curve group has order 8*L. Multiplication by 8 removes its torsion
	// component. Multiplication by 8^-1 mod L recovers exactly the prime-order
	// component, so equality is equivalent to [L]P=I. Scalar L itself cannot be
	// represented by the library's modulo-L scalar type.
	var eightBytes [32]byte
	eightBytes[0] = 8
	eight, err := new(edwards25519.Scalar).SetCanonicalBytes(eightBytes[:])
	if err != nil {
		panic("protocol: constant scalar 8 is invalid")
	}
	inverseEight := new(edwards25519.Scalar).Invert(eight)
	cofactorCleared := new(edwards25519.Point).MultByCofactor(p)
	primeComponent := new(edwards25519.Point).ScalarMult(inverseEight, cofactorCleared)
	if primeComponent.Equal(p) != 1 {
		return ErrPoint
	}
	return nil
}

// VerifyStrict verifies Pure Ed25519 only after validating canonical, nonidentity
// prime-order A and R and canonical S. It intentionally rejects identity R,
// even when a broader RFC 8032 verifier would accept the signature.
func VerifyStrict(publicKey, message, signature []byte) error {
	if len(signature) != ed25519.SignatureSize {
		return ErrLength
	}
	if err := ValidatePoint(publicKey); err != nil {
		return fmt.Errorf("public key: %w", err)
	}
	if err := ValidatePoint(signature[:32]); err != nil {
		return fmt.Errorf("signature R: %w", err)
	}
	if _, err := new(edwards25519.Scalar).SetCanonicalBytes(signature[32:]); err != nil {
		return ErrSignature
	}
	if !ed25519.Verify(ed25519.PublicKey(publicKey), message, signature) {
		return ErrSignature
	}
	return nil
}

// DeriveSlot checks public key admission before computing the scoped SHA-256.
func DeriveSlot(publicKey PublicKey) (SlotID, error) {
	if err := ValidatePoint(publicKey[:]); err != nil {
		return SlotID{}, err
	}
	message := append([]byte("HNUHOLE/SLOT/V1\x00\x01"), publicKey[:]...)
	return SlotID(sha256.Sum256(message)), nil
}

type Ticket struct {
	Epoch        uint32
	Window       uint32
	Slot         SlotID
	BootstrapKey PublicKey
}

type SignedTicket struct {
	Ticket
	Signature Signature
}

func (t Ticket) MessageBytes() [RegistrationMessageLength]byte {
	var message [RegistrationMessageLength]byte
	offset := copy(message[:], scope(PurposeRegister))
	binary.BigEndian.PutUint32(message[offset:], t.Epoch)
	binary.BigEndian.PutUint32(message[offset+4:], t.Window)
	copy(message[offset+8:], t.Slot[:])
	copy(message[offset+40:], t.BootstrapKey[:])
	return message
}

func (t SignedTicket) MarshalBinary() [RegistrationTicketLength]byte {
	var wire [RegistrationTicketLength]byte
	message := t.MessageBytes()
	copy(wire[:], message[:])
	copy(wire[RegistrationMessageLength:], t.Signature[:])
	return wire
}

func (t SignedTicket) Encode() string {
	wire := t.MarshalBinary()
	return EncodeCanonicalBase64url(wire[:])
}

// ParseRegistrationTicket only parses the fixed frame. Its result is untrusted
// until VerifyRegistrationTicket succeeds at the caller's locked decision time.
func ParseRegistrationTicket(encoded string) (SignedTicket, error) {
	wire, err := DecodeCanonicalBase64url(encoded, RegistrationTicketLength)
	if err != nil {
		return SignedTicket{}, err
	}
	if !bytes.HasPrefix(wire, scope(PurposeRegister)) {
		return SignedTicket{}, ErrPurpose
	}
	var ticket SignedTicket
	offset := len(scope(PurposeRegister))
	ticket.Epoch = binary.BigEndian.Uint32(wire[offset:])
	ticket.Window = binary.BigEndian.Uint32(wire[offset+4:])
	copy(ticket.Slot[:], wire[offset+8:offset+40])
	copy(ticket.BootstrapKey[:], wire[offset+40:RegistrationMessageLength])
	copy(ticket.Signature[:], wire[RegistrationMessageLength:])
	return ticket, nil
}

// ValidateAdmissionWindow is arithmetic validation, not a trusted-clock gate.
// Callers must obtain fresh time after their final SQL locks and separately
// reject a clock rollback, an untrusted time source, or a DR freeze.
func ValidateAdmissionWindow(window uint32, at time.Time) error {
	seconds := at.Unix()
	if seconds < 0 || seconds/AdmissionWindowSeconds > math.MaxUint32 {
		return ErrTimeInvalid
	}
	current := uint32(seconds / AdmissionWindowSeconds)
	if window > current {
		return ErrTicketNotYetValid
	}
	if window == current || current > 0 && window == current-1 {
		return nil
	}
	return ErrTicketExpired
}

type Authorization struct {
	Epoch     uint32
	Slot      SlotID
	Signature Signature
}

func (a Authorization) MessageBytes() [RetirementMessageLength]byte {
	var message [RetirementMessageLength]byte
	offset := copy(message[:], scope(PurposeRetireAuth))
	binary.BigEndian.PutUint32(message[offset:], a.Epoch)
	copy(message[offset+4:], a.Slot[:])
	return message
}

func (a Authorization) MarshalBinary() [RetirementTicketLength]byte {
	var wire [RetirementTicketLength]byte
	message := a.MessageBytes()
	copy(wire[:], message[:])
	copy(wire[RetirementMessageLength:], a.Signature[:])
	return wire
}

func (a Authorization) Encode() string {
	wire := a.MarshalBinary()
	return EncodeCanonicalBase64url(wire[:])
}

func ParseRetirementAuthorization(encoded string) (Authorization, error) {
	wire, err := DecodeCanonicalBase64url(encoded, RetirementTicketLength)
	if err != nil {
		return Authorization{}, err
	}
	if !bytes.HasPrefix(wire, scope(PurposeRetireAuth)) {
		return Authorization{}, ErrPurpose
	}
	var authorization Authorization
	offset := len(scope(PurposeRetireAuth))
	authorization.Epoch = binary.BigEndian.Uint32(wire[offset:])
	copy(authorization.Slot[:], wire[offset+4:RetirementMessageLength])
	copy(authorization.Signature[:], wire[RetirementMessageLength:])
	return authorization, nil
}

type Receipt struct {
	Purpose   Purpose
	Epoch     uint32
	Slot      SlotID
	Signature Signature
}

func (r Receipt) MessageBytes() ([]byte, error) {
	messageLength, _, err := receiptLengths(r.Purpose)
	if err != nil {
		return nil, err
	}
	message := make([]byte, messageLength)
	offset := copy(message, scope(r.Purpose))
	binary.BigEndian.PutUint32(message[offset:], r.Epoch)
	copy(message[offset+4:], r.Slot[:])
	return message, nil
}

func (r Receipt) MarshalBinary() ([]byte, error) {
	message, err := r.MessageBytes()
	if err != nil {
		return nil, err
	}
	return append(message, r.Signature[:]...), nil
}

func (r Receipt) Encode() (string, error) {
	wire, err := r.MarshalBinary()
	if err != nil {
		return "", err
	}
	return EncodeCanonicalBase64url(wire), nil
}

func ParseReceipt(encoded string, expectedPurpose Purpose) (Receipt, error) {
	messageLength, wireLength, err := receiptLengths(expectedPurpose)
	if err != nil {
		return Receipt{}, err
	}
	wire, err := DecodeCanonicalBase64url(encoded, wireLength)
	if err != nil {
		return Receipt{}, err
	}
	if !bytes.HasPrefix(wire, scope(expectedPurpose)) {
		return Receipt{}, ErrPurpose
	}
	receipt := Receipt{Purpose: expectedPurpose}
	offset := len(scope(expectedPurpose))
	receipt.Epoch = binary.BigEndian.Uint32(wire[offset:])
	copy(receipt.Slot[:], wire[offset+4:messageLength])
	copy(receipt.Signature[:], wire[messageLength:])
	return receipt, nil
}

// BootstrapMessageBytes binds the proof to the full, uniquely encoded ticket
// including the V signature, never to a password or recovery digest.
func BootstrapMessageBytes(ticket SignedTicket, intent IntentID, challenge Challenge) [BootstrapMessageLength]byte {
	var message [BootstrapMessageLength]byte
	offset := copy(message[:], []byte("HNUHOLE/BOOTSTRAP-POP/V1\x00"))
	copy(message[offset:], ticket.Slot[:])
	copy(message[offset+32:], intent[:])
	copy(message[offset+64:], challenge[:])
	wire := ticket.MarshalBinary()
	digest := sha256.Sum256(wire[:])
	copy(message[offset+96:], digest[:])
	return message
}

// VerifyBootstrapProof only proves possession. The caller must also verify the
// V ticket at its locked decision time and consume its immutable intent once.
func VerifyBootstrapProof(ticket SignedTicket, intent IntentID, challenge Challenge, encodedSignature string) error {
	signature, err := DecodeCanonicalBase64url(encodedSignature, ed25519.SignatureSize)
	if err != nil {
		return err
	}
	slot, err := DeriveSlot(ticket.BootstrapKey)
	if err != nil {
		return err
	}
	if slot != ticket.Slot {
		return ErrSlotBinding
	}
	message := BootstrapMessageBytes(ticket, intent, challenge)
	return VerifyStrict(ticket.BootstrapKey[:], message[:], signature)
}

// TrustedKey is explicit environment and signing-purpose configuration. An
// epoch is a global rotation version, not data selected by an individual user.
type TrustedKey struct {
	Environment string
	Purpose     Purpose
	Epoch       uint32
	PublicKey   PublicKey
	Revoked     bool
}

type keyID struct {
	purpose Purpose
	epoch   uint32
}

// Verifier copies its key configuration at construction. Replace the verifier
// atomically when keys rotate or revoke; callers must not restore stale trusted
// configurations from a database backup.
type Verifier struct {
	environment string
	keys        map[keyID]TrustedKey
}

func NewVerifier(environment string, trustedKeys []TrustedKey) (*Verifier, error) {
	if environment == "" {
		return nil, ErrKeyConfiguration
	}
	v := &Verifier{environment: environment, keys: make(map[keyID]TrustedKey, len(trustedKeys))}
	for _, key := range trustedKeys {
		if key.Environment != environment {
			return nil, ErrKeyEnvironment
		}
		if !validPurpose(key.Purpose) {
			return nil, ErrPurpose
		}
		if err := ValidatePoint(key.PublicKey[:]); err != nil {
			return nil, fmt.Errorf("trusted key import: %w", err)
		}
		id := keyID{purpose: key.Purpose, epoch: key.Epoch}
		if _, exists := v.keys[id]; exists {
			return nil, ErrKeyConfiguration
		}
		v.keys[id] = key
	}
	return v, nil
}

func (v *Verifier) VerifyRegistrationTicket(encoded string, at time.Time) (SignedTicket, error) {
	ticket, err := ParseRegistrationTicket(encoded)
	if err != nil {
		return SignedTicket{}, err
	}
	key, err := v.lookup(PurposeRegister, ticket.Epoch)
	if err != nil {
		return SignedTicket{}, err
	}
	slot, err := DeriveSlot(ticket.BootstrapKey)
	if err != nil {
		return SignedTicket{}, err
	}
	if slot != ticket.Slot {
		return SignedTicket{}, ErrSlotBinding
	}
	message := ticket.MessageBytes()
	if err := VerifyStrict(key[:], message[:], ticket.Signature[:]); err != nil {
		return SignedTicket{}, err
	}
	if err := ValidateAdmissionWindow(ticket.Window, at); err != nil {
		return SignedTicket{}, err
	}
	return ticket, nil
}

func (v *Verifier) VerifyRetirementAuthorization(encoded string) (Authorization, error) {
	authorization, err := ParseRetirementAuthorization(encoded)
	if err != nil {
		return Authorization{}, err
	}
	key, err := v.lookup(PurposeRetireAuth, authorization.Epoch)
	if err != nil {
		return Authorization{}, err
	}
	message := authorization.MessageBytes()
	if err := VerifyStrict(key[:], message[:], authorization.Signature[:]); err != nil {
		return Authorization{}, err
	}
	return authorization, nil
}

func (v *Verifier) VerifyReceipt(encoded string, expectedPurpose Purpose) (Receipt, error) {
	receipt, err := ParseReceipt(encoded, expectedPurpose)
	if err != nil {
		return Receipt{}, err
	}
	key, err := v.lookup(expectedPurpose, receipt.Epoch)
	if err != nil {
		return Receipt{}, err
	}
	message, err := receipt.MessageBytes()
	if err != nil {
		return Receipt{}, err
	}
	if err := VerifyStrict(key[:], message, receipt.Signature[:]); err != nil {
		return Receipt{}, err
	}
	return receipt, nil
}

func (v *Verifier) lookup(purpose Purpose, epoch uint32) (PublicKey, error) {
	if v == nil || v.environment == "" {
		return PublicKey{}, ErrKeyConfiguration
	}
	key, ok := v.keys[keyID{purpose: purpose, epoch: epoch}]
	if !ok {
		return PublicKey{}, ErrKeyUntrusted
	}
	if key.Environment != v.environment {
		return PublicKey{}, ErrKeyEnvironment
	}
	if key.Revoked {
		return PublicKey{}, ErrKeyRevoked
	}
	return key.PublicKey, nil
}

func validPurpose(purpose Purpose) bool {
	return purpose == PurposeRegister || purpose == PurposeRetireAuth || purpose == PurposeRetired || purpose == PurposeReleased
}

func scope(purpose Purpose) []byte {
	return []byte("HNUHOLE/" + purpose + "\x00")
}

func receiptLengths(purpose Purpose) (int, int, error) {
	switch purpose {
	case PurposeRetired:
		return RetiredMessageLength, RetiredReceiptLength, nil
	case PurposeReleased:
		return ReleasedMessageLength, ReleasedReceiptLength, nil
	default:
		return 0, 0, ErrPurpose
	}
}
