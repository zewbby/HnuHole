package postmedia

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestManifestBoundsAndIdentity(t *testing.T) {
	s := Selection{MediaID: "11111111-1111-4111-8111-111111111111", SHA256: string(make([]byte, 64)), ByteLength: 2, MIME: "image/png", Width: 3, Height: 2}
	s.SHA256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	if ValidateManifest([]Selection{s}) != nil {
		t.Fatal("valid manifest rejected")
	}
	if ValidateManifest([]Selection{s, s}) == nil {
		t.Fatal("duplicate IDs accepted")
	}
	for _, change := range []func(*Selection){func(s *Selection) { s.ByteLength = MaxBytes + 1 }, func(s *Selection) { s.Width = MaxDimension + 1 }, func(s *Selection) { s.MIME = "image/svg+xml" }, func(s *Selection) { s.SHA256 = "ABC" }, func(s *Selection) { s.Height = 0 }} {
		changed := s
		change(&changed)
		if ValidateManifest([]Selection{changed}) == nil {
			t.Fatal("invalid manifest accepted")
		}
	}
}

func TestRealProcessValidatorOriginalFormats(t *testing.T) {
	python, fixtures := os.Getenv("POST_MEDIA_PYTHON"), os.Getenv("POST_MEDIA_FIXTURES")
	if python == "" || fixtures == "" {
		t.Skip("dedicated Linux image environment absent")
	}
	script, e := filepath.Abs("../../media/validate_image.py")
	if e != nil {
		t.Fatal(e)
	}
	source, e := os.ReadFile(script)
	if e != nil {
		t.Fatal(e)
	}
	hash := sha256.Sum256(source)
	validator, e := NewProcessValidator(python, script, hex.EncodeToString(hash[:]))
	if e != nil {
		t.Fatal(e)
	}
	for _, format := range []string{"png", "jpeg", "gif", "webp"} {
		t.Run(format, func(t *testing.T) {
			data, e := os.ReadFile(filepath.Join(fixtures, format+".bin"))
			if e != nil {
				t.Fatal(e)
			}
			raw, e := os.ReadFile(filepath.Join(fixtures, format+".json"))
			if e != nil {
				t.Fatal(e)
			}
			var expected Metadata
			if json.Unmarshal(raw, &expected) != nil {
				t.Fatal("metadata fixture")
			}
			result, e := validator.Inspect(context.Background(), data)
			if e != nil || result != expected {
				t.Fatal("real full-frame validation mismatch", e)
			}
			if _, e = validator.Inspect(context.Background(), data[:len(data)-1]); !errors.Is(e, ErrInvalid) {
				t.Fatal("truncated original accepted", e)
			}
		})
	}
	if _, e := NewProcessValidator(python, script, string(make([]byte, 64))); e == nil {
		t.Fatal("unpinned helper accepted")
	}
}
