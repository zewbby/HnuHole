package posts

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const testID = "11111111-1111-4111-8111-111111111111"
const otherID = "22222222-2222-4222-8222-222222222222"

func TestSharedProtocolVectors(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "packages", "post-protocol-vectors", "post-command-v1.json"))
	if err != nil {
		t.Fatal(err)
	}
	var suite struct {
		UnicodeVersion string `json:"unicodeVersion"`
		Cases          []struct {
			ID        string    `json:"id"`
			Operation Operation `json:"operation"`
			Input     struct {
				ChannelID              string `json:"channelId"`
				IdentityID             string `json:"identityId"`
				TaskID                 string `json:"taskId"`
				PostID                 string `json:"postId"`
				ExpectedAttemptVersion int32  `json:"expectedAttemptVersion"`
				Title                  string `json:"title"`
				Body                   string `json:"body"`
			} `json:"input"`
			FrameHex      string `json:"frameHex"`
			RequestDigest string `json:"requestDigest"`
		} `json:"cases"`
		GraphemeCases []struct {
			ID               string `json:"id"`
			Text             string `json:"text"`
			ExpectedClusters int    `json:"expectedClusters"`
		} `json:"graphemeCases"`
	}
	if err := json.Unmarshal(raw, &suite); err != nil {
		t.Fatal(err)
	}
	if suite.UnicodeVersion != UnicodeVersion || len(suite.Cases) != 9 || len(suite.GraphemeCases) != 7 {
		t.Fatal("共享向量版本或完整性发生变化，必须重新审核")
	}
	for _, c := range suite.Cases {
		t.Run(c.ID, func(t *testing.T) {
			intent := Intent{Operation: c.Operation, ChannelID: c.Input.ChannelID, IdentityID: c.Input.IdentityID, TaskID: c.Input.TaskID, PostID: c.Input.PostID, ExpectedAttemptVersion: c.Input.ExpectedAttemptVersion, Title: c.Input.Title, Body: c.Input.Body}
			frame, err := FrameIntent(intent)
			if err != nil || hex.EncodeToString(frame) != c.FrameHex {
				t.Fatalf("frame mismatch: %v", err)
			}
			digest, err := RequestDigest(intent)
			if err != nil || hex.EncodeToString(digest[:]) != c.RequestDigest {
				t.Fatalf("digest mismatch: %v", err)
			}
		})
	}
	for _, c := range suite.GraphemeCases {
		t.Run(c.ID, func(t *testing.T) {
			actual, err := CountGraphemes(c.Text)
			if err != nil || actual != c.ExpectedClusters {
				t.Fatalf("got %d clusters, expected %d: %v", actual, c.ExpectedClusters, err)
			}
		})
	}
}

func TestStrictResourceAndCommandKeys(t *testing.T) {
	for _, value := range []string{"", "00000000-0000-0000-0000-000000000000", "11111111111141118111111111111111", "{11111111-1111-4111-8111-111111111111}", "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", "urn:uuid:" + testID} {
		if _, err := ParseResourceID(value); !errors.Is(err, ErrInvalidID) {
			t.Fatalf("accepted noncanonical ID %q", value)
		}
	}
	if _, err := ParseResourceID(testID); err != nil {
		t.Fatal(err)
	}
	valid := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0x42}, 16))
	if _, err := ParseCommandKey(valid); err != nil {
		t.Fatal(err)
	}
	for _, value := range []string{"", strings.Repeat("A", 22), valid + "==", valid[:21] + "h", " " + valid, strings.Repeat("_", 22)} {
		if _, err := ParseCommandKey(value); !errors.Is(err, ErrInvalidCommandKey) {
			t.Fatalf("accepted noncanonical key %q", value)
		}
	}
}

func TestCommandDomainsAndExactText(t *testing.T) {
	keyKey, fingerprintKey := bytes.Repeat([]byte{1}, 32), bytes.Repeat([]byte{2}, 32)
	codec, err := NewCommandCodec(keyKey, fingerprintKey)
	if err != nil {
		t.Fatal(err)
	}
	command := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{3}, 16))
	one, err := codec.KeyDigest(testID, command)
	if err != nil {
		t.Fatal(err)
	}
	two, err := codec.KeyDigest(otherID, command)
	if err != nil || one == two {
		t.Fatal("同一key不得跨账号共用")
	}
	// 输入钥被调用者修改也不能改变已有codec。
	keyKey[0] = 99
	oneAgain, _ := codec.KeyDigest(testID, command)
	if oneAgain != one {
		t.Fatal("codec retained caller mutable key")
	}
	intent := Intent{Operation: Create, ChannelID: testID, IdentityID: otherID, Title: "é", Body: "a\nb"}
	digest, _ := RequestDigest(intent)
	for _, mutation := range []func(*Intent){func(i *Intent) { i.Title = "e\u0301" }, func(i *Intent) { i.Body = "a\r\nb" }, func(i *Intent) { i.Body = " a\nb " }} {
		changed := intent
		mutation(&changed)
		other, _ := RequestDigest(changed)
		if other == digest {
			t.Fatal("不能正规化原文摘要")
		}
	}
	if codec.IntentFingerprint(digest) == digest {
		t.Fatal("数据库指纹不得等于公开摘要")
	}
	for _, bad := range [][]byte{nil, bytes.Repeat([]byte{0}, 32), bytes.Repeat([]byte{1}, 31)} {
		if _, err := NewCommandCodec(bad, fingerprintKey); err == nil {
			t.Fatal("accepted invalid key")
		}
	}
	if _, err := NewCommandCodec(fingerprintKey, fingerprintKey); err == nil {
		t.Fatal("未隔离key与fingerprint域")
	}
	intent.Title = strings.Repeat("字", 16)
	if _, err := RequestDigest(intent); err != nil {
		t.Fatal("业务无效文本仍需稳定命令摘要", err)
	}
	if err := ValidateContent(intent.Title, intent.Body); !errors.Is(err, ErrContentInvalid) {
		t.Fatal("expected business rejection")
	}
	intent.TaskID = testID
	if _, err := RequestDigest(intent); !errors.Is(err, ErrInvalidIntent) {
		t.Fatal("接受与操作不符的额外路径字段")
	}
}

func TestRandomIdentityShortCodes(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 100; i++ {
		code, err := NewShortCode()
		if err != nil || !ValidShortCode(code) || seen[code] {
			t.Fatal("bad random identity code", err)
		}
		seen[code] = true
	}
	for _, code := range []string{"", "ABCDEFGHIJK1", "abcdefghijkl", "ABCDEFGHIJKLM"} {
		if ValidShortCode(code) {
			t.Fatal("accepted invalid identity code")
		}
	}
}
