package protocol

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"testing"
	"time"
)

func TestEmailLoginProofPurposeBindingAndTime(t *testing.T) {
	pub, priv, _ := ed25519.GenerateKey(rand.Reader)
	var key PublicKey
	copy(key[:], pub)
	v, err := NewVerifier("lab", []TrustedKey{{Environment: "lab", Purpose: PurposeEmailLogin, Epoch: 1, PublicKey: key}})
	if err != nil {
		t.Fatal(err)
	}
	at := time.Now().UTC()
	p := EmailLoginProof{Epoch: 1, Environment: sha256.Sum256([]byte("lab")), Slot: SlotID{1}, Binding: EmailLoginBinding([16]byte{2}, [32]byte{3}), Nonce: [32]byte{4}, Expires: uint64(at.Add(time.Minute).Unix())}
	sign := func(p EmailLoginProof) string {
		m := p.MessageBytes()
		copy(p.Signature[:], ed25519.Sign(priv, m[:]))
		return p.Encode()
	}
	wire := sign(p)
	parsed, err := v.VerifyEmailLogin(wire, at)
	if err != nil || parsed.Binding != p.Binding {
		t.Fatal("valid login proof rejected", err)
	}
	if _, err = v.VerifyRegistrationTicket(wire, at); err == nil {
		t.Fatal("login proof admitted as registration")
	}
	for _, change := range []func(*EmailLoginProof){func(p *EmailLoginProof) { p.Expires = uint64(at.Unix()) }, func(p *EmailLoginProof) { p.Expires = uint64(at.Add(3 * time.Minute).Unix()) }, func(p *EmailLoginProof) { p.Environment = sha256.Sum256([]byte("other")) }, func(p *EmailLoginProof) { p.Binding = [32]byte{} }, func(p *EmailLoginProof) { p.Slot = SlotID{} }} {
		q := p
		change(&q)
		if _, err = v.VerifyEmailLogin(sign(q), at); err == nil {
			t.Fatal("invalid login proof accepted")
		}
	}
	raw, _ := DecodeCanonicalBase64url(wire, EmailLoginProofLength)
	raw[30] ^= 1
	if _, err = v.VerifyEmailLogin(EncodeCanonicalBase64url(raw), at); err == nil {
		t.Fatal("forged proof accepted")
	}
	if p.Binding == EmailLoginBinding([16]byte{3}, [32]byte{3}) || p.Binding == EmailLoginBinding([16]byte{2}, [32]byte{4}) {
		t.Fatal("operation binding collision")
	}
}
