package protocol

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

const fixtureSHA256 = "da913014063f3972dbc15a6c79a87757e7f113ff9cd5911bbb4b42918e5262b1"

type fixtureKey struct {
	ID           string `json:"id"`
	SeedHex      string `json:"testSeedHex"`
	PublicKeyHex string `json:"publicKeyHex"`
}

type signatureVector struct {
	ID           string                 `json:"id"`
	Purpose      Purpose                `json:"purpose"`
	KeyID        string                 `json:"keyId"`
	PublicKeyHex string                 `json:"publicKeyHex"`
	MessageHex   string                 `json:"messageHex"`
	SignatureHex string                 `json:"signatureHex"`
	WireBase64   string                 `json:"wireBase64url"`
	WireHex      string                 `json:"wireBytesHex"`
	Fields       map[string]interface{} `json:"fields"`
}

type protocolFixture struct {
	TestOnly            bool              `json:"testOnly"`
	Keys                []fixtureKey      `json:"keys"`
	RFCControls         []signatureVector `json:"rfc8032Controls"`
	PositiveSignatures  []signatureVector `json:"positiveSignatures"`
	NegativeSignatures  []signatureVector `json:"negativeSignatures"`
	BareCounterexamples []signatureVector `json:"bareVerifierCounterexamples"`
	LibraryControls     []signatureVector `json:"libraryBehaviorControls"`
	SlotDerivations     []struct {
		ID       string `json:"id"`
		KeyID    string `json:"keyId"`
		SlotHex  string `json:"slotIdHex"`
		InputHex string `json:"inputHex"`
	} `json:"slotDerivations"`
	PublicKeyCases []struct {
		ID       string `json:"id"`
		PointHex string `json:"publicKeyHex"`
		Valid    bool   `json:"expectedPublicKeyValid"`
	} `json:"publicKeyCases"`
	SignaturePointCases []struct {
		ID       string `json:"id"`
		PointHex string `json:"pointHex"`
		Valid    bool   `json:"expectedPointValid"`
	} `json:"signaturePointCases"`
	EncodingCases []struct {
		ID       string `json:"id"`
		Wire     string `json:"wireString"`
		Length   int    `json:"expectedDecodedByteLength"`
		Decision string `json:"expectedDecision"`
	} `json:"base64urlCases"`
	FramingCases []struct {
		ID       string `json:"id"`
		WireHex  string `json:"signedBytesHex"`
		Decision string `json:"expectedDecision"`
	} `json:"framingCases"`
	TimeCases []struct {
		ID        string `json:"id"`
		Window    uint32 `json:"ticketWindow"`
		At        int64  `json:"lockedDecisionUnixSeconds"`
		Watermark int64  `json:"timeHighWatermarkUnixSeconds"`
		Decision  string `json:"expectedDecision"`
		Reason    string `json:"reason"`
	} `json:"timeCases"`
	PolicyCases []struct {
		ID        string  `json:"id"`
		VectorID  string  `json:"signatureVectorId"`
		Purpose   Purpose `json:"requiredPurpose"`
		Decision  string  `json:"expectedDecision"`
		KeyState  string  `json:"trustedKeyState"`
		KeyEnv    string  `json:"keyEnvironment"`
		VerifyEnv string  `json:"verifierEnvironment"`
	} `json:"protocolPolicyCases"`
}

func loadFixture(t *testing.T) protocolFixture {
	t.Helper()
	_, source, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot locate public fixture")
	}
	root := filepath.Join(filepath.Dir(source), "../../../../../packages/auth-protocol-vectors")
	raw, err := os.ReadFile(filepath.Join(root, "v1.json"))
	if err != nil {
		t.Fatal(err)
	}
	if fmt.Sprintf("%x", sha256.Sum256(raw)) != fixtureSHA256 {
		t.Fatal("public fixture changed; review the protocol vectors and hash")
	}
	var fixture protocolFixture
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	if !fixture.TestOnly {
		t.Fatal("expected public synthetic test-only keys")
	}
	var staticReport struct {
		SHA256 string `json:"fixtureSha256"`
	}
	report, err := os.ReadFile(filepath.Join(root, "static-verification-report.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(report, &staticReport); err != nil || staticReport.SHA256 != fixtureSHA256 {
		t.Fatal("static report does not refer to this fixture")
	}
	return fixture
}

func decodeHex(t *testing.T, value string) []byte {
	t.Helper()
	raw, err := hex.DecodeString(value)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func publicKey(t *testing.T, value string) PublicKey {
	t.Helper()
	raw := decodeHex(t, value)
	if len(raw) != 32 {
		t.Fatal("fixture public key length is not 32")
	}
	return PublicKey(raw)
}

func keyMap(t *testing.T, fixture protocolFixture) map[string]fixtureKey {
	t.Helper()
	keys := make(map[string]fixtureKey)
	for _, key := range fixture.Keys {
		keys[key.ID] = key
	}
	return keys
}

func fixtureTrustedKeys(t *testing.T, fixture protocolFixture) []TrustedKey {
	t.Helper()
	keys := keyMap(t, fixture)
	vKey := publicKey(t, keys["v_rfc8032_test1"].PublicKeyHex)
	cKey := publicKey(t, keys["c_rfc8032_test2"].PublicKeyHex)
	return []TrustedKey{
		{Environment: "isolated-test", Purpose: PurposeRegister, Epoch: 0x01020304, PublicKey: vKey},
		{Environment: "isolated-test", Purpose: PurposeRetireAuth, Epoch: 0x01020304, PublicKey: vKey},
		{Environment: "isolated-test", Purpose: PurposeRetired, Epoch: 0x05060708, PublicKey: cKey},
		{Environment: "isolated-test", Purpose: PurposeReleased, Epoch: 0x05060708, PublicKey: cKey},
	}
}

func fixtureVerifier(t *testing.T, fixture protocolFixture) *Verifier {
	t.Helper()
	v, err := NewVerifier("isolated-test", fixtureTrustedKeys(t, fixture))
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func vectorMap(fixture protocolFixture) map[string]signatureVector {
	vectors := make(map[string]signatureVector)
	for _, vector := range fixture.PositiveSignatures {
		vectors[vector.ID] = vector
	}
	return vectors
}

func TestPublicVectorsPureEd25519(t *testing.T) {
	fixture := loadFixture(t)
	keys := keyMap(t, fixture)
	controls := append(append([]signatureVector{}, fixture.RFCControls...), fixture.PositiveSignatures...)
	for _, vector := range controls {
		t.Run(vector.ID, func(t *testing.T) {
			key := keys[vector.KeyID]
			private := ed25519.NewKeyFromSeed(decodeHex(t, key.SeedHex))
			public := decodeHex(t, key.PublicKeyHex)
			if !bytes.Equal(private.Public().(ed25519.PublicKey), public) {
				t.Fatal("derived public key differs from fixture")
			}
			message, signature := decodeHex(t, vector.MessageHex), decodeHex(t, vector.SignatureHex)
			if !bytes.Equal(ed25519.Sign(private, message), signature) {
				t.Fatal("Pure Ed25519 signature differs from fixed fixture")
			}
			if err := VerifyStrict(public, message, signature); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestPublicVectorsRejectInvalidSignaturesAndWeakVerifierCases(t *testing.T) {
	fixture := loadFixture(t)
	for _, set := range [][]signatureVector{fixture.NegativeSignatures, fixture.BareCounterexamples, fixture.LibraryControls} {
		for _, vector := range set {
			t.Run(vector.ID, func(t *testing.T) {
				public, message, signature := decodeHex(t, vector.PublicKeyHex), decodeHex(t, vector.MessageHex), decodeHex(t, vector.SignatureHex)
				if err := VerifyStrict(public, message, signature); err == nil {
					t.Fatal("project acceptance profile accepted an invalid or weak signature")
				}
				if len(public) == ed25519.PublicKeySize {
					t.Logf("bare Go verifier accepts=%v; strict profile rejects", ed25519.Verify(public, message, signature))
				}
			})
		}
	}
}

func TestPublicVectorsAAndRPointAdmission(t *testing.T) {
	fixture := loadFixture(t)
	for _, vector := range fixture.PublicKeyCases {
		t.Run(vector.ID, func(t *testing.T) {
			if valid := ValidatePoint(decodeHex(t, vector.PointHex)) == nil; valid != vector.Valid {
				t.Fatalf("point accepted=%v, expected=%v", valid, vector.Valid)
			}
		})
	}
	for _, vector := range fixture.SignaturePointCases {
		t.Run(vector.ID, func(t *testing.T) {
			if valid := ValidatePoint(decodeHex(t, vector.PointHex)) == nil; valid != vector.Valid {
				t.Fatalf("R accepted=%v, expected=%v", valid, vector.Valid)
			}
		})
	}
}

func TestPublicVectorsSlotDerivation(t *testing.T) {
	fixture := loadFixture(t)
	keys := keyMap(t, fixture)
	for _, vector := range fixture.SlotDerivations {
		t.Run(vector.ID, func(t *testing.T) {
			slot, err := DeriveSlot(publicKey(t, keys[vector.KeyID].PublicKeyHex))
			if err != nil || !bytes.Equal(slot[:], decodeHex(t, vector.SlotHex)) {
				t.Fatalf("slot derivation: %x %v", slot, err)
			}
			if digest := sha256.Sum256(decodeHex(t, vector.InputHex)); SlotID(digest) != slot {
				t.Fatal("scoped slot hash differs")
			}
		})
	}
}

func TestPublicVectorsCanonicalBase64url(t *testing.T) {
	for _, vector := range loadFixture(t).EncodingCases {
		t.Run(vector.ID, func(t *testing.T) {
			raw, err := DecodeCanonicalBase64url(vector.Wire, vector.Length)
			if (err == nil) != (vector.Decision == "ACCEPT") {
				t.Fatalf("decision mismatch: %v", err)
			}
			if err == nil && EncodeCanonicalBase64url(raw) != vector.Wire {
				t.Fatal("accepted encoding did not round-trip")
			}
		})
	}
	for _, length := range []int{-1, math.MaxInt} {
		if _, err := DecodeCanonicalBase64url("", length); !errors.Is(err, ErrLength) {
			t.Fatalf("invalid expected length %d: %v", length, err)
		}
	}
}

func TestPublicVectorsFixedFramesAndPurposeBinding(t *testing.T) {
	fixture := loadFixture(t)
	v := fixtureVerifier(t, fixture)
	for _, vector := range fixture.FramingCases {
		t.Run(vector.ID, func(t *testing.T) {
			wire, err := hex.DecodeString(vector.WireHex)
			if err == nil {
				_, err = v.VerifyRegistrationTicket(EncodeCanonicalBase64url(wire), time.Unix(1800000000, 0))
			}
			if (err == nil) != (vector.Decision == "ACCEPT") {
				t.Fatalf("frame decision mismatch: %v", err)
			}
		})
	}
	for _, vector := range fixture.PositiveSignatures {
		t.Run("roundtrip_"+vector.ID, func(t *testing.T) {
			var encoded string
			switch vector.Purpose {
			case PurposeRegister:
				ticket, err := ParseRegistrationTicket(vector.WireBase64)
				if err != nil {
					t.Fatal(err)
				}
				message := ticket.MessageBytes()
				if !bytes.Equal(message[:], decodeHex(t, vector.MessageHex)) {
					t.Fatal("registration fixed message differs")
				}
				encoded = ticket.Encode()
			case PurposeRetireAuth:
				authorization, err := v.VerifyRetirementAuthorization(vector.WireBase64)
				if err != nil {
					t.Fatal(err)
				}
				message := authorization.MessageBytes()
				if !bytes.Equal(message[:], decodeHex(t, vector.MessageHex)) {
					t.Fatal("retire authorization fixed message differs")
				}
				encoded = authorization.Encode()
			case PurposeRetired, PurposeReleased:
				receipt, err := v.VerifyReceipt(vector.WireBase64, vector.Purpose)
				if err != nil {
					t.Fatal(err)
				}
				message, err := receipt.MessageBytes()
				if err != nil || !bytes.Equal(message, decodeHex(t, vector.MessageHex)) {
					t.Fatal("receipt fixed message differs")
				}
				encoded, err = receipt.Encode()
				if err != nil {
					t.Fatal(err)
				}
			default:
				return // PoP is a detached signature; legacy REGISTER/V1 must reject.
			}
			if encoded != vector.WireBase64 {
				t.Fatal("fixed frame did not round-trip")
			}
		})
	}
}

func TestPublicVectorsProtocolPolicy(t *testing.T) {
	fixture := loadFixture(t)
	vectors := vectorMap(fixture)
	for _, policy := range fixture.PolicyCases {
		t.Run(policy.ID, func(t *testing.T) {
			keys := fixtureTrustedKeys(t, fixture)
			if policy.KeyState == "REVOKED" {
				keys[0].Revoked = true
			}
			environment := "isolated-test"
			if policy.VerifyEnv != "" {
				environment = policy.VerifyEnv
				for i := range keys {
					keys[i].Environment = policy.KeyEnv
				}
			}
			v, err := NewVerifier(environment, keys)
			if err == nil {
				vector := vectors[policy.VectorID]
				if policy.Purpose != "" {
					_, err = v.VerifyReceipt(vector.WireBase64, policy.Purpose)
				} else {
					_, err = v.VerifyRegistrationTicket(vector.WireBase64, time.Unix(1800000000, 0))
				}
			}
			if (err == nil) != (policy.Decision == "ACCEPT_FORMAT_BINDING") {
				t.Fatalf("protocol policy decision mismatch: %v", err)
			}
		})
	}
}

func TestPublicVectorsAdmissionWindowArithmetic(t *testing.T) {
	for _, vector := range loadFixture(t).TimeCases {
		t.Run(vector.ID, func(t *testing.T) {
			if vector.Decision == "FREEZE" {
				// Window arithmetic alone accepts this ticket. The real PostgreSQL
				// gate test in authprivacy executes the same fixture and rejects the
				// rollback; keep that caller boundary explicit instead of skipping it.
				if vector.Watermark-vector.At <= 5 || ValidateAdmissionWindow(vector.Window, time.Unix(vector.At, 0)) != nil {
					t.Fatal("rollback fixture must need the authorization gate despite a valid ticket window")
				}
				return
			}
			err := ValidateAdmissionWindow(vector.Window, time.Unix(vector.At, 0))
			if (err == nil) != (vector.Decision == "ACCEPT") {
				t.Fatalf("window decision mismatch: %v", err)
			}
			if vector.Reason == "REGISTRATION_TICKET_EXPIRED" && !errors.Is(err, ErrTicketExpired) {
				t.Fatalf("wanted expired error: %v", err)
			}
			if vector.Reason == "REGISTRATION_TICKET_NOT_YET_VALID" && !errors.Is(err, ErrTicketNotYetValid) {
				t.Fatalf("wanted future error: %v", err)
			}
		})
	}
	for _, at := range []int64{-1, (int64(math.MaxUint32) + 1) * AdmissionWindowSeconds} {
		if err := ValidateAdmissionWindow(0, time.Unix(at, 0)); !errors.Is(err, ErrTimeInvalid) {
			t.Fatalf("unrepresentable time accepted: %d %v", at, err)
		}
	}
	if err := ValidateAdmissionWindow(math.MaxUint32, time.Unix(int64(math.MaxUint32)*AdmissionWindowSeconds, 0)); err != nil {
		t.Fatal(err)
	}
}

func TestBootstrapProofBindsTicketIntentAndChallenge(t *testing.T) {
	fixture := loadFixture(t)
	vectors := vectorMap(fixture)
	ticket, err := fixtureVerifier(t, fixture).VerifyRegistrationTicket(vectors["SIG_REGISTER_CURRENT"].WireBase64, time.Unix(1800000000, 0))
	if err != nil {
		t.Fatal(err)
	}
	proof := vectors["SIG_BOOTSTRAP_POP"]
	intent := IntentID(decodeHex(t, proof.Fields["intentIdHex"].(string)))
	challenge := Challenge(decodeHex(t, proof.Fields["challengeHex"].(string)))
	message := BootstrapMessageBytes(ticket, intent, challenge)
	if !bytes.Equal(message[:], decodeHex(t, proof.MessageHex)) {
		t.Fatal("fixed bootstrap message differs")
	}
	if err := VerifyBootstrapProof(ticket, intent, challenge, proof.WireBase64); err != nil {
		t.Fatal(err)
	}
	t.Run("changed_intent", func(t *testing.T) {
		changed := intent
		changed[0] ^= 1
		if err := VerifyBootstrapProof(ticket, changed, challenge, proof.WireBase64); err == nil {
			t.Fatal("PoP accepted another intent")
		}
	})
	t.Run("changed_challenge", func(t *testing.T) {
		changed := challenge
		changed[0] ^= 1
		if err := VerifyBootstrapProof(ticket, intent, changed, proof.WireBase64); err == nil {
			t.Fatal("PoP accepted another challenge")
		}
	})
	t.Run("changed_ticket_signature", func(t *testing.T) {
		changed := ticket
		changed.Signature[0] ^= 1
		if err := VerifyBootstrapProof(changed, intent, challenge, proof.WireBase64); err == nil {
			t.Fatal("PoP accepted another ticket")
		}
	})
	t.Run("changed_bootstrap_key", func(t *testing.T) {
		changed := ticket
		changed.BootstrapKey = publicKey(t, keyMap(t, fixture)["attacker_public_test_seed"].PublicKeyHex)
		if err := VerifyBootstrapProof(changed, intent, challenge, proof.WireBase64); !errors.Is(err, ErrSlotBinding) {
			t.Fatalf("key substitution not rejected by slot binding: %v", err)
		}
	})
	t.Run("signature_frame_extra_byte", func(t *testing.T) {
		if err := VerifyBootstrapProof(ticket, intent, challenge, EncodeCanonicalBase64url(append(decodeHex(t, proof.SignatureHex), 0))); err == nil {
			t.Fatal("PoP accepted a signature with trailing fields")
		}
	})
}

func TestKeyImportAndPurposeEpochIsolation(t *testing.T) {
	fixture := loadFixture(t)
	keys := fixtureTrustedKeys(t, fixture)
	register := vectorMap(fixture)["SIG_REGISTER_CURRENT"]
	for _, point := range fixture.PublicKeyCases {
		if point.Valid || len(decodeHex(t, point.PointHex)) != 32 {
			continue
		}
		t.Run("import_"+point.ID, func(t *testing.T) {
			changed := append([]TrustedKey{}, keys...)
			changed[0].PublicKey = PublicKey(decodeHex(t, point.PointHex))
			if _, err := NewVerifier("isolated-test", changed); err == nil {
				t.Fatal("trusted key import bypassed point validation")
			}
		})
	}
	t.Run("wrong_purpose", func(t *testing.T) {
		v, err := NewVerifier("isolated-test", keys[1:])
		if err != nil {
			t.Fatal(err)
		}
		if _, err := v.VerifyRegistrationTicket(register.WireBase64, time.Unix(1800000000, 0)); !errors.Is(err, ErrKeyUntrusted) {
			t.Fatalf("another purpose authorized register: %v", err)
		}
	})
	t.Run("unknown_epoch", func(t *testing.T) {
		changed := append([]TrustedKey{}, keys...)
		changed[0].Epoch++
		v, err := NewVerifier("isolated-test", changed)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := v.VerifyRegistrationTicket(register.WireBase64, time.Unix(1800000000, 0)); !errors.Is(err, ErrKeyUntrusted) {
			t.Fatalf("unknown epoch accepted: %v", err)
		}
	})
	t.Run("configuration_copy", func(t *testing.T) {
		changed := append([]TrustedKey{}, keys...)
		v, err := NewVerifier("isolated-test", changed)
		if err != nil {
			t.Fatal(err)
		}
		changed[0].Revoked = true
		changed[0].PublicKey = PublicKey{}
		if _, err := v.VerifyRegistrationTicket(register.WireBase64, time.Unix(1800000000, 0)); err != nil {
			t.Fatalf("external slice mutation changed imported trust: %v", err)
		}
	})
	if _, err := NewVerifier("isolated-test", append(keys, keys[0])); !errors.Is(err, ErrKeyConfiguration) {
		t.Fatalf("duplicate purpose/epoch accepted: %v", err)
	}
	if _, err := NewVerifier("", keys); !errors.Is(err, ErrKeyConfiguration) {
		t.Fatalf("unbound environment accepted: %v", err)
	}
	var nilVerifier *Verifier
	if _, err := nilVerifier.VerifyRegistrationTicket(register.WireBase64, time.Unix(1800000000, 0)); !errors.Is(err, ErrKeyConfiguration) {
		t.Fatalf("nil verifier must fail closed: %v", err)
	}
}
