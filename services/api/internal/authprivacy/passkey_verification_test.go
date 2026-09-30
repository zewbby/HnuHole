package authprivacy

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"math/big"
	"testing"

	"github.com/fxamacker/cbor/v2"
)

type passkeyTestFixture struct {
	validator    *WebAuthnValidator
	privateKey   *ecdsa.PrivateKey
	challenge    [32]byte
	userHandle   [32]byte
	credentialID []byte
	publicKey    []byte
	registration RegistrationResponse
	assertion    AssertionResponse
}

func passkeyCBOR(t testing.TB, value any) []byte {
	t.Helper()
	mode, err := cbor.CanonicalEncOptions().EncMode()
	if err != nil {
		t.Fatal(err)
	}
	encoded, err := mode.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return encoded
}

func passkeyEncode(value []byte) string { return base64.RawURLEncoding.EncodeToString(value) }

func passkeyDecode(t testing.TB, encoded string) []byte {
	t.Helper()
	decoded, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatal(err)
	}
	return decoded
}

func passkeyClientData(t testing.TB, kind string, challenge [32]byte) []byte {
	t.Helper()
	data, err := json.Marshal(map[string]any{
		"type": kind, "challenge": passkeyEncode(challenge[:]),
		"origin": "https://auth.example.test", "crossOrigin": false,
	})
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func newPasskeyTestFixture(t testing.TB) passkeyTestFixture {
	t.Helper()
	v, err := NewWebAuthnValidator(WebAuthnConfig{RPID: "example.test", Origins: []string{"https://auth.example.test"}})
	if err != nil {
		t.Fatal(err)
	}
	d := big.NewInt(42)
	x, y := elliptic.P256().ScalarBaseMult(d.Bytes())
	key := &ecdsa.PrivateKey{PublicKey: ecdsa.PublicKey{Curve: elliptic.P256(), X: x, Y: y}, D: d}
	f := passkeyTestFixture{validator: v, privateKey: key, credentialID: bytes.Repeat([]byte{0xc7}, 32)}
	for i := range f.challenge {
		f.challenge[i] = byte(i + 1)
		f.userHandle[i] = byte(i + 70)
	}
	f.publicKey = passkeyCBOR(t, map[int64]any{1: int64(2), 3: int64(-7), -1: int64(1), -2: x.FillBytes(make([]byte, 32)), -3: y.FillBytes(make([]byte, 32))})
	f.registration = f.makeRegistration(t, f.challenge, 0, 0x5d)
	f.assertion = f.makeAssertion(t, f.challenge, 0, 0x1d)
	return f
}

func (f passkeyTestFixture) makeRegistration(t testing.TB, challenge [32]byte, count uint32, flags byte) RegistrationResponse {
	t.Helper()
	rpHash := sha256.Sum256([]byte("example.test"))
	auth := append([]byte{}, rpHash[:]...)
	auth = append(auth, flags)
	auth = binary.BigEndian.AppendUint32(auth, count)
	auth = append(auth, bytes.Repeat([]byte{0x81}, 16)...)
	auth = binary.BigEndian.AppendUint16(auth, uint16(len(f.credentialID)))
	auth = append(auth, f.credentialID...)
	auth = append(auth, f.publicKey...)
	return RegistrationResponse{
		ID: passkeyEncode(f.credentialID), RawID: passkeyEncode(f.credentialID), Type: "public-key",
		ClientDataJSON:    passkeyEncode(passkeyClientData(t, "webauthn.create", challenge)),
		AttestationObject: passkeyEncode(passkeyCBOR(t, map[string]any{"fmt": "none", "authData": auth, "attStmt": map[string]any{}})),
	}
}

func (f passkeyTestFixture) makeAssertion(t testing.TB, challenge [32]byte, count uint32, flags byte) AssertionResponse {
	t.Helper()
	rpHash := sha256.Sum256([]byte("example.test"))
	auth := append([]byte{}, rpHash[:]...)
	auth = append(auth, flags)
	auth = binary.BigEndian.AppendUint32(auth, count)
	client := passkeyClientData(t, "webauthn.get", challenge)
	clientHash := sha256.Sum256(client)
	signed := append(append([]byte{}, auth...), clientHash[:]...)
	hash := sha256.Sum256(signed)
	signature, err := ecdsa.SignASN1(rand.Reader, f.privateKey, hash[:])
	if err != nil {
		t.Fatal(err)
	}
	return AssertionResponse{ID: passkeyEncode(f.credentialID), RawID: passkeyEncode(f.credentialID), Type: "public-key",
		ClientDataJSON: passkeyEncode(client), AuthenticatorData: passkeyEncode(auth), Signature: passkeyEncode(signature), UserHandle: passkeyEncode(f.userHandle[:])}
}

func passkeyAttestationParts(t testing.TB, response RegistrationResponse) map[string]any {
	t.Helper()
	var parts map[string]any
	if err := cbor.Unmarshal(passkeyDecode(t, response.AttestationObject), &parts); err != nil {
		t.Fatal(err)
	}
	return parts
}

func TestWebAuthnRegistrationAndAssertionVerifyES256(t *testing.T) {
	f := newPasskeyTestFixture(t)
	registration, err := f.validator.VerifyRegistration(f.registration, f.challenge)
	if err != nil || !bytes.Equal(registration.CredentialID, f.credentialID) || !bytes.Equal(registration.PublicKey, f.publicKey) ||
		registration.SignCount != 0 || !registration.BackupEligible || !registration.BackupState {
		t.Fatalf("valid none-attestation registration failed: %+v %v", registration, err)
	}
	// A synced credential with count=0 is valid; monotonicity is a caller risk
	// signal, and must not be confused with the ES256 cryptographic proof.
	for _, count := range []uint32{0, 1, 0xffffffff} {
		response := f.makeAssertion(t, f.challenge, count, 0x1d)
		assertion, err := f.validator.VerifyAssertion(response, f.challenge, registration.PublicKey, f.userHandle)
		if err != nil || assertion.SignCount != count || !bytes.Equal(assertion.CredentialID, f.credentialID) || !assertion.BackupEligible || !assertion.BackupState {
			t.Fatalf("valid signed assertion count=%d failed: %+v %v", count, assertion, err)
		}
	}
	// Backup state may transition independently of the immutable BE value.
	response := f.makeAssertion(t, f.challenge, 0, 0x0d)
	assertion, err := f.validator.VerifyAssertion(response, f.challenge, registration.PublicKey, f.userHandle)
	if err != nil || !assertion.BackupEligible || assertion.BackupState {
		t.Fatalf("valid backup-state transition rejected: %+v %v", assertion, err)
	}
}

func TestWebAuthnCredentialIDAndEncodingBounds(t *testing.T) {
	f := newPasskeyTestFixture(t)
	for _, length := range []int{1, 1023} {
		f.credentialID = bytes.Repeat([]byte{0xf7}, length)
		response := f.makeRegistration(t, f.challenge, 1, 0x45)
		registered, err := f.validator.VerifyRegistration(response, f.challenge)
		if err != nil || len(registered.CredentialID) != length || registered.BackupEligible || registered.BackupState {
			t.Fatalf("valid credential bound length=%d rejected: %+v %v", length, registered, err)
		}
	}
	for _, length := range []int{0, 1024} {
		f.credentialID = bytes.Repeat([]byte{0xf7}, length)
		response := f.makeRegistration(t, f.challenge, 1, 0x45)
		if _, err := f.validator.VerifyRegistration(response, f.challenge); !errors.Is(err, ErrWebAuthnValidation) {
			t.Fatalf("invalid credential bound length=%d accepted: %v", length, err)
		}
	}
	f.credentialID = []byte{0xff}
	response := f.makeRegistration(t, f.challenge, 1, 0x45)
	response.ID, response.RawID = "_x", "_x" // Decodes to ff only in a permissive decoder; low pad bits are not zero.
	if _, err := f.validator.VerifyRegistration(response, f.challenge); !errors.Is(err, ErrWebAuthnValidation) {
		t.Fatalf("noncanonical credential encoding accepted: %v", err)
	}
	response = f.registration
	response.ClientDataJSON = passkeyEncode(bytes.Repeat([]byte{' '}, 3073))
	if _, err := f.validator.VerifyRegistration(response, f.challenge); !errors.Is(err, ErrWebAuthnValidation) {
		t.Fatalf("oversized client data accepted: %v", err)
	}
	var absent *WebAuthnValidator
	if _, err := absent.VerifyRegistration(f.registration, f.challenge); !errors.Is(err, ErrWebAuthnConfiguration) {
		t.Fatalf("absent trusted configuration should fail closed: %v", err)
	}
}

func TestWebAuthnTrustedConfigurationIsCopiedAndStrict(t *testing.T) {
	for _, config := range []WebAuthnConfig{
		{}, {RPID: "example.test"}, {RPID: "https://example.test", Origins: []string{"https://example.test"}},
		{RPID: "Example.test", Origins: []string{"https://example.test"}},
		{RPID: "example.test.", Origins: []string{"https://example.test."}},
		{RPID: "127.0.0.1", Origins: []string{"https://127.0.0.1"}},
		{RPID: "-example.test", Origins: []string{"https://-example.test"}},
		{RPID: "example.test", Origins: []string{"http://example.test"}},
		{RPID: "example.test", Origins: []string{"https://example.test/"}},
		{RPID: "example.test", Origins: []string{"https://example.test?"}},
		{RPID: "example.test", Origins: []string{"https://user@example.test"}},
		{RPID: "example.test", Origins: []string{"https://badexample.test"}},
		{RPID: "example.test", Origins: []string{"https://bad..example.test"}},
		{RPID: "example.test", Origins: []string{"https://example.test:65536"}},
		{RPID: "example.test", Origins: []string{"https://example.test:000443"}},
		{RPID: "example.test", Origins: []string{"https://example.test:"}},
		{RPID: "example.test", Origins: []string{"https://example.test", "https://example.test"}},
	} {
		if _, err := NewWebAuthnValidator(config); !errors.Is(err, ErrWebAuthnConfiguration) {
			t.Fatalf("untrusted configuration accepted: %+v, error=%v", config, err)
		}
	}
	f := newPasskeyTestFixture(t)
	origins := []string{"https://auth.example.test"}
	v, err := NewWebAuthnValidator(WebAuthnConfig{RPID: "example.test", Origins: origins})
	if err != nil {
		t.Fatal(err)
	}
	origins[0] = "https://evil.example.test"
	if _, err := v.VerifyRegistration(f.registration, f.challenge); err != nil {
		t.Fatalf("allowlist changed after caller mutated original slice: %v", err)
	}
}

func TestWebAuthnRejectsClientDataBindingAndDuplicateFields(t *testing.T) {
	f := newPasskeyTestFixture(t)
	challenge := passkeyEncode(f.challenge[:])
	for name, client := range map[string]string{
		"wrong_type":            `{"type":"webauthn.get","challenge":"` + challenge + `","origin":"https://auth.example.test"}`,
		"wrong_challenge":       `{"type":"webauthn.create","challenge":"wrong","origin":"https://auth.example.test"}`,
		"foreign_origin":        `{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://evil.example.test"}`,
		"origin_trailing_slash": `{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://auth.example.test/"}`,
		"cross_origin":          `{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://auth.example.test","crossOrigin":true}`,
		"cross_origin_null":     `{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://auth.example.test","crossOrigin":null}`,
		"top_origin":            `{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://auth.example.test","topOrigin":null}`,
		"duplicate_origin":      `{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://evil.example.test","origin":"https://auth.example.test"}`,
		"escaped_duplicate":     `{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://auth.example.test","\u006frigin":"https://auth.example.test"}`,
		"missing_origin":        `{"type":"webauthn.create","challenge":"` + challenge + `"}`,
		"trailing_json":         `{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://auth.example.test"}{}`,
		"array":                 `[]`,
		"invalid_utf8":          string([]byte{0xff}),
	} {
		t.Run(name, func(t *testing.T) {
			response := f.registration
			response.ClientDataJSON = passkeyEncode([]byte(client))
			if _, err := f.validator.VerifyRegistration(response, f.challenge); !errors.Is(err, ErrWebAuthnValidation) {
				t.Fatalf("unbound/ambiguous client data accepted: %v", err)
			}
		})
	}
	response := f.registration
	response.ClientDataJSON = passkeyEncode([]byte(`{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://auth.example.test"}`))
	if _, err := f.validator.VerifyRegistration(response, f.challenge); err != nil {
		t.Fatalf("absent crossOrigin should mean false: %v", err)
	}
	response.ClientDataJSON = passkeyEncode(append([]byte{0xef, 0xbb, 0xbf}, passkeyDecode(t, response.ClientDataJSON)...))
	if _, err := f.validator.VerifyRegistration(response, f.challenge); err != nil {
		t.Fatalf("WebAuthn UTF-8 leading BOM rejected: %v", err)
	}
	response.ClientDataJSON = passkeyEncode([]byte(`{"type":"webauthn.create","challenge":"` + challenge + `","origin":"https://auth.example.test","other_keys_can_be_added_here":"client-data is extensible"}`))
	if _, err := f.validator.VerifyRegistration(response, f.challenge); err != nil {
		t.Fatalf("WebAuthn client-data unknown field rejected: %v", err)
	}
}

func TestWebAuthnAssertionHashesOriginalClientDataBytes(t *testing.T) {
	f := newPasskeyTestFixture(t)
	for _, prefix := range [][]byte{nil, {0xef, 0xbb, 0xbf}} {
		response := f.assertion
		client := append(append([]byte{}, prefix...), []byte(`{"origin":"https://auth.example.test","future":{"opaque":"value"},"challenge":"`+passkeyEncode(f.challenge[:])+`","type":"webauthn.get"}`)...)
		response.ClientDataJSON = passkeyEncode(client)
		clientHash := sha256.Sum256(client)
		signed := append(passkeyDecode(t, response.AuthenticatorData), clientHash[:]...)
		hash := sha256.Sum256(signed)
		signature, err := ecdsa.SignASN1(rand.Reader, f.privateKey, hash[:])
		if err != nil {
			t.Fatal(err)
		}
		response.Signature = passkeyEncode(signature)
		if _, err := f.validator.VerifyAssertion(response, f.challenge, f.publicKey, f.userHandle); err != nil {
			t.Fatalf("valid signature over original extensible/BOM data rejected: %v", err)
		}
		// JSON-normalizing before verification would conceal this byte change;
		// the signature is over the original browser encoding, not its values.
		response.ClientDataJSON = passkeyEncode(append(client, ' '))
		if _, err := f.validator.VerifyAssertion(response, f.challenge, f.publicKey, f.userHandle); !errors.Is(err, ErrWebAuthnValidation) {
			t.Fatalf("unsigned client-data whitespace change accepted: %v", err)
		}
	}
}

func TestWebAuthnRegistrationRejectsUntrustedAuthenticatorMaterial(t *testing.T) {
	f := newPasskeyTestFixture(t)
	for name, alter := range map[string]func(map[string]any){
		"wrong_format":               func(p map[string]any) { p["fmt"] = "packed" },
		"nonempty_attestation":       func(p map[string]any) { p["attStmt"] = map[string]any{"x5c": []any{[]byte("device")}} },
		"null_attestation":           func(p map[string]any) { p["attStmt"] = nil },
		"unknown_field":              func(p map[string]any) { p["extension"] = true },
		"wrong_rp":                   func(p map[string]any) { p["authData"].([]byte)[0] ^= 1 },
		"no_presence":                func(p map[string]any) { p["authData"].([]byte)[32] &^= 1 },
		"no_verification":            func(p map[string]any) { p["authData"].([]byte)[32] &^= 4 },
		"no_attested_data":           func(p map[string]any) { p["authData"].([]byte)[32] &^= 0x40 },
		"backup_without_eligibility": func(p map[string]any) { p["authData"].([]byte)[32] &^= 8 },
		"extension_flag":             func(p map[string]any) { p["authData"].([]byte)[32] |= 0x80 },
		"reserved_flag":              func(p map[string]any) { p["authData"].([]byte)[32] |= 2 },
		"different_credential":       func(p map[string]any) { p["authData"].([]byte)[55] ^= 1 },
		"zero_credential_length":     func(p map[string]any) { p["authData"].([]byte)[54] = 0 },
		"truncated_credential":       func(p map[string]any) { p["authData"] = p["authData"].([]byte)[:56] },
		"trailing_key_bytes":         func(p map[string]any) { p["authData"] = append(p["authData"].([]byte), 0) },
	} {
		t.Run(name, func(t *testing.T) {
			parts := passkeyAttestationParts(t, f.registration)
			alter(parts)
			response := f.registration
			response.AttestationObject = passkeyEncode(passkeyCBOR(t, parts))
			if _, err := f.validator.VerifyRegistration(response, f.challenge); !errors.Is(err, ErrWebAuthnValidation) {
				t.Fatalf("untrusted authenticator material accepted: %v", err)
			}
		})
	}
}

func TestWebAuthnRejectsDuplicateUnboundedAndTaggedCBOR(t *testing.T) {
	f := newPasskeyTestFixture(t)
	valid := passkeyDecode(t, f.registration.AttestationObject)
	duplicate := append([]byte{}, valid...)
	duplicate[0] = 0xa4 // Existing three entries plus a second fmt.
	duplicate = append(duplicate, 0x63, 'f', 'm', 't', 0x64, 'n', 'o', 'n', 'e')
	indefinite := append([]byte{0xbf}, valid[1:]...)
	indefinite = append(indefinite, 0xff)
	for name, wire := range map[string][]byte{
		"duplicate": duplicate, "indefinite": indefinite,
		"tagged": append([]byte{0xc0}, valid...), "trailing": append(valid, 0),
		"huge_map_claim":   {0xba, 0xff, 0xff, 0xff, 0xff},
		"huge_bytes_claim": {0x5a, 0xff, 0xff, 0xff, 0xff},
		"oversized":        bytes.Repeat([]byte{0}, 4097),
	} {
		t.Run(name, func(t *testing.T) {
			response := f.registration
			response.AttestationObject = passkeyEncode(wire)
			if _, err := f.validator.VerifyRegistration(response, f.challenge); !errors.Is(err, ErrWebAuthnValidation) {
				t.Fatalf("ambiguous or unbounded CBOR accepted: %v", err)
			}
		})
	}
}

func TestWebAuthnRejectsNonES256AndMalformedCOSEKeys(t *testing.T) {
	f := newPasskeyTestFixture(t)
	for name, alter := range map[string]func(map[int64]any){
		"RSA_type":          func(k map[int64]any) { k[1] = int64(3) },
		"EdDSA_algorithm":   func(k map[int64]any) { k[3] = int64(-8) },
		"wrong_curve":       func(k map[int64]any) { k[-1] = int64(2) },
		"short_x":           func(k map[int64]any) { k[-2] = k[-2].([]byte)[1:] },
		"overlong_y":        func(k map[int64]any) { k[-3] = append([]byte{0}, k[-3].([]byte)...) },
		"off_curve":         func(k map[int64]any) { k[-2] = make([]byte, 32); k[-3] = make([]byte, 32) },
		"unknown_parameter": func(k map[int64]any) { k[4] = []int{2} },
		"missing_parameter": func(k map[int64]any) { delete(k, 3) },
	} {
		t.Run(name, func(t *testing.T) {
			var fields map[int64]any
			if err := cbor.Unmarshal(f.publicKey, &fields); err != nil {
				t.Fatal(err)
			}
			alter(fields)
			parts := passkeyAttestationParts(t, f.registration)
			parts["authData"] = append(parts["authData"].([]byte)[:55+len(f.credentialID)], passkeyCBOR(t, fields)...)
			response := f.registration
			response.AttestationObject = passkeyEncode(passkeyCBOR(t, parts))
			if _, err := f.validator.VerifyRegistration(response, f.challenge); !errors.Is(err, ErrWebAuthnValidation) {
				t.Fatalf("invalid COSE key registered: %v", err)
			}
			if _, err := f.validator.VerifyAssertion(f.assertion, f.challenge, passkeyCBOR(t, fields), f.userHandle); !errors.Is(err, ErrWebAuthnValidation) {
				t.Fatalf("invalid stored COSE key verified: %v", err)
			}
		})
	}
	duplicate := append([]byte{}, f.publicKey...)
	duplicate[0] = 0xa6
	duplicate = append(duplicate, 0x03, 0x26) // alg=-7 repeated.
	if _, err := f.validator.VerifyAssertion(f.assertion, f.challenge, duplicate, f.userHandle); !errors.Is(err, ErrWebAuthnValidation) {
		t.Fatalf("duplicate COSE algorithm accepted: %v", err)
	}
}

func TestWebAuthnAssertionRejectsWrongSignatureAccountAndFlags(t *testing.T) {
	f := newPasskeyTestFixture(t)
	for name, alter := range map[string]func(*AssertionResponse){
		"different_id": func(r *AssertionResponse) { r.ID = passkeyEncode([]byte("another")) },
		"wrong_type":   func(r *AssertionResponse) { r.Type = "password" },
		"wrong_user":   func(r *AssertionResponse) { r.UserHandle = passkeyEncode(bytes.Repeat([]byte{0}, 32)) },
		"missing_user": func(r *AssertionResponse) { r.UserHandle = "" },
		"tampered_signature": func(r *AssertionResponse) {
			b := passkeyDecode(t, r.Signature)
			b[len(b)-1] ^= 1
			r.Signature = passkeyEncode(b)
		},
		"trailing_signature":     func(r *AssertionResponse) { r.Signature = passkeyEncode(append(passkeyDecode(t, r.Signature), 0)) },
		"negative_integer_DER":   func(r *AssertionResponse) { r.Signature = passkeyEncode([]byte{0x30, 6, 2, 1, 0xff, 2, 1, 1}) },
		"nonminimal_integer_DER": func(r *AssertionResponse) { r.Signature = passkeyEncode([]byte{0x30, 7, 2, 2, 0, 1, 2, 1, 1}) },
		"tampered_client":        func(r *AssertionResponse) { r.ClientDataJSON = f.registration.ClientDataJSON },
		"tampered_counter": func(r *AssertionResponse) {
			b := passkeyDecode(t, r.AuthenticatorData)
			b[36] ^= 1
			r.AuthenticatorData = passkeyEncode(b)
		},
		"trailing_auth_data": func(r *AssertionResponse) {
			r.AuthenticatorData = passkeyEncode(append(passkeyDecode(t, r.AuthenticatorData), 0))
		},
		"padded_signature":   func(r *AssertionResponse) { r.Signature += "=" },
		"newline_credential": func(r *AssertionResponse) { r.ID += "\n"; r.RawID = r.ID },
	} {
		t.Run(name, func(t *testing.T) {
			response := f.assertion
			alter(&response)
			if _, err := f.validator.VerifyAssertion(response, f.challenge, f.publicKey, f.userHandle); !errors.Is(err, ErrWebAuthnValidation) {
				t.Fatalf("forged or account-unbound assertion accepted: %v", err)
			}
		})
	}
	for _, flags := range []byte{0x1c, 0x19, 0x15, 0x1f, 0x3d, 0x5d, 0x9d} {
		response := f.makeAssertion(t, f.challenge, 1, flags)
		if _, err := f.validator.VerifyAssertion(response, f.challenge, f.publicKey, f.userHandle); !errors.Is(err, ErrWebAuthnValidation) {
			t.Fatalf("invalid signed flags %#x accepted: %v", flags, err)
		}
	}
	challenge := f.challenge
	challenge[0] ^= 1
	if _, err := f.validator.VerifyAssertion(f.assertion, challenge, f.publicKey, f.userHandle); !errors.Is(err, ErrWebAuthnValidation) {
		t.Fatalf("assertion replayed across challenges: %v", err)
	}
}
