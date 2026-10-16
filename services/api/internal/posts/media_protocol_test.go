package posts

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

func TestMediaIntentBindsFullManifestAndPreservesTextDomain(t *testing.T) {
	text := Intent{Operation: Create, ChannelID: "11111111-1111-4111-8111-111111111111", IdentityID: "22222222-2222-4222-8222-222222222222", Title: "标题", Body: "正文"}
	original, e := FrameIntent(text)
	if e != nil || !bytes.HasPrefix(original, []byte("HNUHOLE/POST-COMMAND/V1\x00")) {
		t.Fatal("text domain changed")
	}
	item := postmedia.Selection{MediaID: "33333333-3333-4333-8333-333333333333", SHA256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", MIME: "image/gif", ByteLength: 120, Width: 3, Height: 2}
	media := text
	media.Images = []postmedia.Selection{item}
	first, e := RequestDigest(media)
	if e != nil {
		t.Fatal(e)
	}
	for _, change := range []func(*postmedia.Selection){func(s *postmedia.Selection) { s.Width = 4 }, func(s *postmedia.Selection) { s.Height = 4 }, func(s *postmedia.Selection) { s.ByteLength = 121 }, func(s *postmedia.Selection) { s.MIME = "image/webp" }, func(s *postmedia.Selection) { s.MediaID = "44444444-4444-4444-8444-444444444444" }, func(s *postmedia.Selection) {
		s.SHA256 = "1123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	}} {
		copyIntent := media
		copyIntent.Images = []postmedia.Selection{item}
		change(&copyIntent.Images[0])
		digest, e := RequestDigest(copyIntent)
		if e != nil || digest == first {
			t.Fatal("manifest field not bound", e)
		}
	}
	if ValidateContentWithImages("标题", "", 1) != nil || ValidateContentWithImages("标题", "", 0) == nil || ValidateContentWithImages("标题", "", 10) == nil {
		t.Fatal("image-only post rule")
	}
	// Empty arrays intentionally share the unchanged text intent semantics.
	text.Images = []postmedia.Selection{}
	again, e := FrameIntent(text)
	if e != nil || !bytes.Equal(original, again) {
		t.Fatal("empty manifest changes old digest")
	}
}

func TestMediaProtocolIndependentGoldenVectors(t *testing.T) {
	data, e := os.ReadFile("../../../../packages/post-protocol-vectors/media-v1.json")
	if e != nil {
		t.Fatal(e)
	}
	var fixture struct {
		Vectors []struct {
			Intent Intent `json:"intent"`
			Frame  string `json:"frameBase64"`
			Digest string `json:"requestDigest"`
		} `json:"vectors"`
	}
	if json.Unmarshal(data, &fixture) != nil || len(fixture.Vectors) != 2 {
		t.Fatal("media vectors absent")
	}
	for _, v := range fixture.Vectors {
		frame, e := FrameIntent(v.Intent)
		if e != nil || base64.StdEncoding.EncodeToString(frame) != v.Frame {
			t.Fatal("independent framing mismatch", e)
		}
		digest, e := RequestDigest(v.Intent)
		if e != nil || hex.EncodeToString(digest[:]) != v.Digest {
			t.Fatal("independent requestDigest mismatch", e)
		}
	}
}
