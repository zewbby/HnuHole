package posts

import (
	"bytes"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestScopedCursorEncryption(t *testing.T) {
	now := time.Date(2026, 10, 8, 1, 2, 3, 123456789, time.UTC)
	key := bytes.Repeat([]byte{9}, 32)
	codec, err := NewCursorCodec(key, "development-a")
	if err != nil {
		t.Fatal(err)
	}
	positions := []CursorPosition{
		{Scope: CursorChannel, AccountID: testID, ChannelID: otherID, Ceiling: 42, LastAt: now.Add(-time.Hour), LastOrdinal: 21, Limit: 20, ExpiresAt: now.Add(CursorTTL)},
		{Scope: CursorOwn, AccountID: testID, Ceiling: 42, LastAt: now.Add(-time.Hour), LastOrdinal: 21, Limit: 20, ExpiresAt: now.Add(CursorTTL)},
		{Scope: CursorTask, AccountID: testID, Ceiling: 42, LastAt: now.Add(-time.Hour), LastID: otherID, Limit: 20, ExpiresAt: now.Add(CursorTTL)},
	}
	for _, p := range positions {
		t.Run(p.Scope, func(t *testing.T) {
			token, err := codec.Encode(p)
			if err != nil {
				t.Fatal(err)
			}
			another, _ := codec.Encode(p)
			if token == another {
				t.Fatal("cursor nonce must be random")
			}
			raw, _ := base64.RawURLEncoding.DecodeString(token)
			if bytes.Contains(raw, []byte(testID)) || bytes.Contains(raw, []byte(p.Scope)) {
				t.Fatal("private cursor fields exposed as plaintext")
			}
			got, err := codec.Decode(token, p, now)
			if err != nil || got != p {
				t.Fatalf("cursor roundtrip failed: %v", err)
			}
			for _, mutate := range []func(*CursorPosition){
				func(p *CursorPosition) { p.AccountID = otherID }, func(p *CursorPosition) { p.Scope = "foreign" }, func(p *CursorPosition) { p.ChannelID = testID }, func(p *CursorPosition) { p.Limit = 50 },
			} {
				wrong := p
				mutate(&wrong)
				if _, err := codec.Decode(token, wrong, now); !errors.Is(err, ErrCursorInvalid) {
					t.Fatal("accepted wrong scope/account/channel/limit")
				}
			}
			if _, err := codec.Decode(token, p, p.ExpiresAt); !errors.Is(err, ErrCursorInvalid) {
				t.Fatal("accepted cursor at expiry")
			}
			if _, err := codec.Decode(token, p, now.Add(-time.Second)); !errors.Is(err, ErrCursorInvalid) {
				t.Fatal("accepted cursor beyond 30m validity")
			}
			for _, environment := range []string{"development-b", "production"} {
				other, _ := NewCursorCodec(key, environment)
				if _, err := other.Decode(token, p, now); !errors.Is(err, ErrCursorInvalid) {
					t.Fatal("accepted different environment")
				}
			}
			raw[len(raw)-1] ^= 1
			for _, bad := range []string{base64.RawURLEncoding.EncodeToString(raw), token + "=", "", strings.Repeat("A", 1025)} {
				if _, err := codec.Decode(bad, p, now); !errors.Is(err, ErrCursorInvalid) {
					t.Fatal("accepted tampered/noncanonical cursor")
				}
			}
		})
	}
}
