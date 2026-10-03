package authprivacy

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net"
	"net/url"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/fxamacker/cbor/v2"
)

var (
	ErrWebAuthnValidation    = errors.New("invalid WebAuthn proof")
	ErrWebAuthnConfiguration = errors.New("invalid trusted WebAuthn configuration")
)

// WebAuthnConfig is deployment-owned configuration. An HTTP request must never
// supply the RP ID or extend either origin allowlist. Android signing identities
// are provisioned separately from HTTPS/RP and HTTP CORS configuration. iOS uses
// the associated RP's HTTPS origin; neither platform is inferred from a request.
type WebAuthnConfig struct {
	RPID           string   `json:"rpId"`
	Origins        []string `json:"origins"`
	AndroidOrigins []string `json:"androidOrigins,omitempty"`
}

type RegistrationResponse struct {
	ID, RawID, ClientDataJSON, AttestationObject, Type string
}

type AssertionResponse struct {
	ID, RawID, ClientDataJSON, AuthenticatorData, Signature, UserHandle, Type string
}

type VerifiedRegistration struct {
	CredentialID                []byte
	PublicKey                   []byte // Canonical CBOR COSE EC2, alg=-7, curve=P-256.
	SignCount                   uint32
	BackupEligible, BackupState bool
}

type VerifiedAssertion struct {
	CredentialID                []byte
	SignCount                   uint32
	BackupEligible, BackupState bool
}

// WebAuthnValidator proves a bounded cryptographic ceremony only. Callers must
// additionally bind the credential to its account, recheck current credential
// versions and Gate state under locks, and consume challenges atomically. It
// does not authorize a mutation or ordinary session on its own.
type WebAuthnValidator struct {
	rpIDHash [32]byte
	origins  map[string]struct{}
	decode   cbor.DecMode
	encode   cbor.EncMode
}

func NewWebAuthnValidator(config WebAuthnConfig) (*WebAuthnValidator, error) {
	if !validRPID(config.RPID) || len(config.Origins) < 1 || len(config.Origins) > 16 || len(config.AndroidOrigins) > 16 {
		return nil, ErrWebAuthnConfiguration
	}
	origins := make(map[string]struct{}, len(config.Origins))
	for _, origin := range config.Origins {
		u, err := url.Parse(origin)
		if err != nil || len(origin) > 2048 || u.Scheme != "https" || u.Host == "" || u.User != nil ||
			u.Path != "" || u.RawPath != "" || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" ||
			!validRPID(u.Hostname()) ||
			(u.Hostname() != config.RPID && !strings.HasSuffix(u.Hostname(), "."+config.RPID)) ||
			u.String() != origin {
			return nil, ErrWebAuthnConfiguration
		}
		if port := u.Port(); port != "" {
			number, err := strconv.Atoi(port)
			if err != nil || number < 1 || number > 65535 || strconv.Itoa(number) != port {
				return nil, ErrWebAuthnConfiguration
			}
		} else if u.Host != u.Hostname() {
			return nil, ErrWebAuthnConfiguration
		}
		if _, exists := origins[origin]; exists {
			return nil, ErrWebAuthnConfiguration
		}
		origins[origin] = struct{}{}
	}
	for _, origin := range config.AndroidOrigins {
		const prefix = "android:apk-key-hash:"
		if !strings.HasPrefix(origin, prefix) {
			return nil, ErrWebAuthnConfiguration
		}
		if _, err := webAuthnBytes(strings.TrimPrefix(origin, prefix), 32, 32); err != nil {
			return nil, ErrWebAuthnConfiguration
		}
		if _, exists := origins[origin]; exists {
			return nil, ErrWebAuthnConfiguration
		}
		origins[origin] = struct{}{}
	}
	decode, err := (cbor.DecOptions{
		DupMapKey: cbor.DupMapKeyEnforcedAPF, IndefLength: cbor.IndefLengthForbidden,
		TagsMd: cbor.TagsForbidden, MaxNestedLevels: 4, MaxArrayElements: 16, MaxMapPairs: 16,
	}).DecMode()
	if err != nil {
		return nil, ErrWebAuthnConfiguration
	}
	encode, err := cbor.CanonicalEncOptions().EncMode()
	if err != nil {
		return nil, ErrWebAuthnConfiguration
	}
	return &WebAuthnValidator{rpIDHash: sha256.Sum256([]byte(config.RPID)), origins: origins, decode: decode, encode: encode}, nil
}

func validRPID(rp string) bool {
	if rp == "" || len(rp) > 253 || strings.ToLower(rp) != rp || net.ParseIP(rp) != nil {
		return false
	}
	for _, label := range strings.Split(rp, ".") {
		if len(label) < 1 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return false
		}
		for i := range label {
			c := label[i]
			if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') {
				return false
			}
		}
	}
	return true
}

// VerifyRegistration discards attestation and AAGUID after parsing. The input
// cannot prove resident-key support: the fixed creation options and a real
// discoverable recovery exercise must establish client compatibility.
func (v *WebAuthnValidator) VerifyRegistration(response RegistrationResponse, challenge [32]byte) (VerifiedRegistration, error) {
	var invalid VerifiedRegistration
	if v == nil {
		return invalid, ErrWebAuthnConfiguration
	}
	credentialID, err := webAuthnCredentialID(response.ID, response.RawID, response.Type)
	if err != nil {
		return invalid, err
	}
	if _, err := v.clientData(response.ClientDataJSON, "webauthn.create", challenge); err != nil {
		return invalid, err
	}
	attestation, err := webAuthnBytes(response.AttestationObject, 1, 4096)
	if err != nil {
		return invalid, err
	}
	var object map[string]cbor.RawMessage
	if v.decode.Unmarshal(attestation, &object) != nil || len(object) != 3 {
		return invalid, ErrWebAuthnValidation
	}
	var format string
	var authenticatorData []byte
	var statement map[string]cbor.RawMessage
	if v.decode.Unmarshal(object["fmt"], &format) != nil || format != "none" ||
		v.decode.Unmarshal(object["authData"], &authenticatorData) != nil ||
		v.decode.Unmarshal(object["attStmt"], &statement) != nil || statement == nil || len(statement) != 0 {
		return invalid, ErrWebAuthnValidation
	}
	count, eligible, backedUp, err := v.authenticatorData(authenticatorData, true)
	if err != nil || len(authenticatorData) < 55 {
		return invalid, ErrWebAuthnValidation
	}
	// Bytes 37..52 are the AAGUID. It is intentionally neither returned nor
	// retained: fmt=none does not supply an attested device identity.
	idLength := int(binary.BigEndian.Uint16(authenticatorData[53:55]))
	if idLength < 1 || idLength > 1023 || 55+idLength >= len(authenticatorData) ||
		!bytes.Equal(credentialID, authenticatorData[55:55+idLength]) {
		return invalid, ErrWebAuthnValidation
	}
	publicKey, canonical, err := v.cosePublicKey(authenticatorData[55+idLength:])
	if err != nil || publicKey == nil {
		return invalid, ErrWebAuthnValidation
	}
	return VerifiedRegistration{CredentialID: credentialID, PublicKey: canonical, SignCount: count, BackupEligible: eligible, BackupState: backedUp}, nil
}

// VerifyAssertion requires the randomly assigned 32-byte account handle and the
// account's stored COSE public key. It returns the signed count and backup bits;
// callers compare BE with the immutable registration value and apply a risk
// policy to count regressions without rejecting synced credentials solely for
// non-incrementing counters.
func (v *WebAuthnValidator) VerifyAssertion(response AssertionResponse, challenge [32]byte, publicKey []byte, userHandle [32]byte) (VerifiedAssertion, error) {
	var invalid VerifiedAssertion
	if v == nil {
		return invalid, ErrWebAuthnConfiguration
	}
	credentialID, err := webAuthnCredentialID(response.ID, response.RawID, response.Type)
	if err != nil {
		return invalid, err
	}
	clientData, err := v.clientData(response.ClientDataJSON, "webauthn.get", challenge)
	if err != nil {
		return invalid, err
	}
	handle, err := webAuthnBytes(response.UserHandle, 32, 32)
	if err != nil || subtle.ConstantTimeCompare(handle, userHandle[:]) != 1 {
		return invalid, ErrWebAuthnValidation
	}
	authenticatorData, err := webAuthnBytes(response.AuthenticatorData, 37, 2048)
	if err != nil {
		return invalid, err
	}
	count, eligible, backedUp, err := v.authenticatorData(authenticatorData, false)
	if err != nil {
		return invalid, err
	}
	key, _, err := v.cosePublicKey(publicKey)
	if err != nil {
		return invalid, err
	}
	signature, err := webAuthnBytes(response.Signature, 8, 1024)
	if err != nil {
		return invalid, err
	}
	clientHash := sha256.Sum256(clientData)
	signed := make([]byte, 0, len(authenticatorData)+sha256.Size)
	signed = append(signed, authenticatorData...)
	signed = append(signed, clientHash[:]...)
	signedHash := sha256.Sum256(signed)
	// VerifyASN1 rejects non-minimal DER, extra ASN.1 values/trailing bytes,
	// negative/zero/out-of-range integers, and all non-P-256 signatures.
	if !ecdsa.VerifyASN1(key, signedHash[:], signature) {
		return invalid, ErrWebAuthnValidation
	}
	return VerifiedAssertion{CredentialID: credentialID, SignCount: count, BackupEligible: eligible, BackupState: backedUp}, nil
}

func webAuthnCredentialID(id, rawID, kind string) ([]byte, error) {
	if kind != "public-key" || id != rawID {
		return nil, ErrWebAuthnValidation
	}
	return webAuthnBytes(rawID, 1, 1023)
}

func webAuthnBytes(encoded string, minimum, maximum int) ([]byte, error) {
	if len(encoded) < base64.RawURLEncoding.EncodedLen(minimum) || len(encoded) > base64.RawURLEncoding.EncodedLen(maximum) {
		return nil, ErrWebAuthnValidation
	}
	for i := range encoded {
		c := encoded[i]
		if !(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_') {
			return nil, ErrWebAuthnValidation
		}
	}
	decoded, err := base64.RawURLEncoding.Strict().DecodeString(encoded)
	if err != nil || len(decoded) < minimum || len(decoded) > maximum || base64.RawURLEncoding.EncodeToString(decoded) != encoded {
		return nil, ErrWebAuthnValidation
	}
	return decoded, nil
}

func (v *WebAuthnValidator) clientData(encoded, expectedType string, challenge [32]byte) ([]byte, error) {
	data, err := webAuthnBytes(encoded, 1, 3072)
	if err != nil || !utf8.Valid(data) {
		return nil, ErrWebAuthnValidation
	}
	// WebAuthn UTF-8 decoding strips a leading BOM; the signature still hashes
	// the complete original bytes, including that BOM if present.
	jsonData := bytes.TrimPrefix(data, []byte{0xef, 0xbb, 0xbf})
	decoder := json.NewDecoder(bytes.NewReader(jsonData))
	token, err := decoder.Token()
	if err != nil || token != json.Delim('{') {
		return nil, ErrWebAuthnValidation
	}
	values := make(map[string]json.RawMessage, 4)
	for decoder.More() {
		token, err := decoder.Token()
		name, ok := token.(string)
		if err != nil || !ok {
			return nil, ErrWebAuthnValidation
		}
		if _, exists := values[name]; exists {
			return nil, ErrWebAuthnValidation
		}
		if name == "topOrigin" {
			return nil, ErrWebAuthnValidation
		}
		// WebAuthn 5.8.1 requires tolerance of unknown client-data keys, which
		// are not extension outputs. Keep them in the duplicate-key check but
		// do not use them for authorization. The complete bounded JSON bytes
		// are still included in the assertion's signature hash.
		var value json.RawMessage
		if decoder.Decode(&value) != nil {
			return nil, ErrWebAuthnValidation
		}
		values[name] = value
	}
	if token, err = decoder.Token(); err != nil || token != json.Delim('}') {
		return nil, ErrWebAuthnValidation
	}
	if _, err = decoder.Token(); err != io.EOF {
		return nil, ErrWebAuthnValidation
	}
	var kind, receivedChallenge, origin string
	if json.Unmarshal(values["type"], &kind) != nil || kind != expectedType ||
		json.Unmarshal(values["challenge"], &receivedChallenge) != nil || receivedChallenge != base64.RawURLEncoding.EncodeToString(challenge[:]) ||
		json.Unmarshal(values["origin"], &origin) != nil {
		return nil, ErrWebAuthnValidation
	}
	if _, accepted := v.origins[origin]; !accepted {
		return nil, ErrWebAuthnValidation
	}
	if crossOrigin, exists := values["crossOrigin"]; exists && !bytes.Equal(bytes.TrimSpace(crossOrigin), []byte("false")) {
		return nil, ErrWebAuthnValidation
	}
	return data, nil
}

func (v *WebAuthnValidator) authenticatorData(data []byte, registration bool) (uint32, bool, bool, error) {
	if len(data) < 37 || len(data) > 2048 || subtle.ConstantTimeCompare(data[:32], v.rpIDHash[:]) != 1 {
		return 0, false, false, ErrWebAuthnValidation
	}
	flags := data[32]
	// Require UP/UV, forbid reserved bits and every authenticator extension.
	// This version never requests extensions; an ED bit cannot be trusted as
	// an empty extension declaration without parsing an extra CBOR value.
	if flags&0x05 != 0x05 || flags&0xa2 != 0 || (flags&0x10 != 0 && flags&0x08 == 0) ||
		(registration && flags&0x40 == 0) || (!registration && (flags&0x40 != 0 || len(data) != 37)) {
		return 0, false, false, ErrWebAuthnValidation
	}
	return binary.BigEndian.Uint32(data[33:37]), flags&0x08 != 0, flags&0x10 != 0, nil
}

func (v *WebAuthnValidator) cosePublicKey(encoded []byte) (*ecdsa.PublicKey, []byte, error) {
	if len(encoded) < 1 || len(encoded) > 512 {
		return nil, nil, ErrWebAuthnValidation
	}
	var fields map[int64]cbor.RawMessage
	if v.decode.Unmarshal(encoded, &fields) != nil || len(fields) != 5 {
		return nil, nil, ErrWebAuthnValidation
	}
	var keyType, algorithm, curve int64
	var xBytes, yBytes []byte
	if v.decode.Unmarshal(fields[1], &keyType) != nil || keyType != 2 ||
		v.decode.Unmarshal(fields[3], &algorithm) != nil || algorithm != -7 ||
		v.decode.Unmarshal(fields[-1], &curve) != nil || curve != 1 ||
		v.decode.Unmarshal(fields[-2], &xBytes) != nil || len(xBytes) != 32 ||
		v.decode.Unmarshal(fields[-3], &yBytes) != nil || len(yBytes) != 32 {
		return nil, nil, ErrWebAuthnValidation
	}
	x, y := new(big.Int).SetBytes(xBytes), new(big.Int).SetBytes(yBytes)
	if !elliptic.P256().IsOnCurve(x, y) {
		return nil, nil, ErrWebAuthnValidation
	}
	canonical, err := v.encode.Marshal(map[int64]any{1: int64(2), 3: int64(-7), -1: int64(1), -2: xBytes, -3: yBytes})
	if err != nil {
		return nil, nil, ErrWebAuthnValidation
	}
	return &ecdsa.PublicKey{Curve: elliptic.P256(), X: x, Y: y}, canonical, nil
}
