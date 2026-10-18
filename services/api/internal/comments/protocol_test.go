package comments

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func protocolCreate() Intent {
	return Intent{Operation: Create, TaskID: resourceID(1), PostID: resourceID(2), IdentityID: resourceID(3), RootCommentID: resourceID(4), TargetCommentID: resourceID(5), Body: "回复 e\u0301\r\n👩‍💻"}
}

func TestCommentSharedProtocolVectors(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "packages", "comment-protocol-vectors", "v1.json"))
	if err != nil {
		t.Fatal(err)
	}
	var suite struct {
		Version       int    `json:"version"`
		Domain        string `json:"domain"`
		MaxFrameBytes int    `json:"maxFrameBytes"`
		Vectors       []struct {
			Name      string    `json:"name"`
			Operation Operation `json:"operation"`
			Input     struct {
				TaskID                 string               `json:"taskId"`
				PostID                 string               `json:"postId"`
				IdentityID             string               `json:"identityId"`
				RootCommentID          string               `json:"rootCommentId"`
				TargetCommentID        string               `json:"targetCommentId"`
				CommentID              string               `json:"commentId"`
				ExpectedAttemptVersion int32                `json:"expectedAttemptVersion"`
				Body                   string               `json:"body"`
				Image                  *postmedia.Selection `json:"image"`
				Liked                  *bool                `json:"liked"`
			} `json:"input"`
			FrameHex      string `json:"frameHex"`
			RequestDigest string `json:"requestDigest"`
		} `json:"vectors"`
	}
	if err = json.Unmarshal(raw, &suite); err != nil {
		t.Fatal(err)
	}
	if suite.Version != 1 || suite.Domain != "HNUHOLE/COMMENT-COMMAND/V1" || suite.MaxFrameBytes != MaxFrameBytes || len(suite.Vectors) != 12 {
		t.Fatal("shared comment vector version or completeness changed")
	}
	for _, vector := range suite.Vectors {
		t.Run(vector.Name, func(t *testing.T) {
			i := vector.Input
			intent := Intent{Operation: vector.Operation, TaskID: i.TaskID, PostID: i.PostID, IdentityID: i.IdentityID, RootCommentID: i.RootCommentID, TargetCommentID: i.TargetCommentID, CommentID: i.CommentID, ExpectedAttemptVersion: i.ExpectedAttemptVersion, Body: i.Body, Image: i.Image, Liked: i.Liked}
			frame, err := FrameIntent(intent)
			if err != nil || hex.EncodeToString(frame) != vector.FrameHex {
				t.Fatalf("comment frame mismatch: %v", err)
			}
			digest, err := RequestDigest(intent)
			if err != nil || hex.EncodeToString(digest[:]) != vector.RequestDigest {
				t.Fatalf("comment digest mismatch: %v", err)
			}
		})
	}
}

func TestCommentProtocolBindsEveryContextAndMediaField(t *testing.T) {
	base := protocolCreate()
	image := imageSelection()
	base.Image = &image
	original, err := RequestDigest(base)
	if err != nil {
		t.Fatal(err)
	}
	mutations := map[string]func(*Intent){
		"task":     func(i *Intent) { i.TaskID = resourceID(101) },
		"post":     func(i *Intent) { i.PostID = resourceID(102) },
		"identity": func(i *Intent) { i.IdentityID = resourceID(103) },
		"root":     func(i *Intent) { i.RootCommentID = resourceID(104) },
		"target":   func(i *Intent) { i.TargetCommentID = resourceID(105) },
		"body":     func(i *Intent) { i.Body += " " },
		"newline":  func(i *Intent) { i.Body = strings.ReplaceAll(i.Body, "\r\n", "\n") },
		"nfc":      func(i *Intent) { i.Body = strings.ReplaceAll(i.Body, "e\u0301", "é") },
		"media":    func(i *Intent) { i.Image.MediaID = resourceID(106) },
		"digest":   func(i *Intent) { i.Image.SHA256 = strings.Repeat("b", 64) },
		"mime":     func(i *Intent) { i.Image.MIME = "image/webp" },
		"length":   func(i *Intent) { i.Image.ByteLength++ },
		"width":    func(i *Intent) { i.Image.Width++ },
		"height":   func(i *Intent) { i.Image.Height++ },
		"no image": func(i *Intent) { i.Image = nil },
	}
	for name, mutation := range mutations {
		t.Run(name, func(t *testing.T) {
			changed, copyImage := base, *base.Image
			changed.Image = &copyImage
			mutation(&changed)
			digest, err := RequestDigest(changed)
			if err != nil || digest == original {
				t.Fatalf("changed comment intent retained digest: %v", err)
			}
		})
	}
	for _, operation := range []Operation{Retry, Abandon} {
		first := Intent{Operation: operation, TaskID: resourceID(1), ExpectedAttemptVersion: 1}
		second := first
		second.ExpectedAttemptVersion = 2
		a, errA := RequestDigest(first)
		b, errB := RequestDigest(second)
		if errA != nil || errB != nil || a == b {
			t.Fatal("expected attempt version not bound")
		}
	}
	liked, unliked := true, false
	a, _ := RequestDigest(Intent{Operation: SetLike, CommentID: resourceID(1), Liked: &liked})
	b, _ := RequestDigest(Intent{Operation: SetLike, CommentID: resourceID(1), Liked: &unliked})
	if a == b {
		t.Fatal("like and unlike have the same digest")
	}
}

func TestCommentProtocolRejectsOperationUnrelatedFields(t *testing.T) {
	no := false
	image := imageSelection()
	cases := []Intent{
		{Operation: "UNKNOWN"},
		{Operation: Create, TaskID: resourceID(1), PostID: resourceID(2), IdentityID: resourceID(3), CommentID: resourceID(4)},
		{Operation: Create, TaskID: resourceID(1), PostID: resourceID(2), IdentityID: resourceID(3), ExpectedAttemptVersion: 1},
		{Operation: Create, TaskID: resourceID(1), PostID: resourceID(2), IdentityID: resourceID(3), Liked: &no},
		{Operation: Retry, TaskID: resourceID(1), ExpectedAttemptVersion: 1, PostID: resourceID(2)},
		{Operation: Retry, TaskID: resourceID(1), ExpectedAttemptVersion: 1, IdentityID: resourceID(2)},
		{Operation: Retry, TaskID: resourceID(1), ExpectedAttemptVersion: 1, RootCommentID: resourceID(2), TargetCommentID: resourceID(3)},
		{Operation: Retry, TaskID: resourceID(1), ExpectedAttemptVersion: 1, CommentID: resourceID(2)},
		{Operation: Retry, TaskID: resourceID(1), ExpectedAttemptVersion: 1, Liked: &no},
		{Operation: Abandon, TaskID: resourceID(1), ExpectedAttemptVersion: 1, Body: " "},
		{Operation: Abandon, TaskID: resourceID(1), ExpectedAttemptVersion: 1, Image: &image},
		{Operation: Abandon, TaskID: resourceID(1), ExpectedAttemptVersion: 1, PostID: resourceID(2)},
		{Operation: Abandon, TaskID: resourceID(1), ExpectedAttemptVersion: 1, Liked: &no},
		{Operation: DeleteComment, CommentID: resourceID(1), TaskID: resourceID(2)},
		{Operation: DeleteComment, CommentID: resourceID(1), ExpectedAttemptVersion: 1},
		{Operation: DeleteComment, CommentID: resourceID(1), Body: " "},
		{Operation: DeleteComment, CommentID: resourceID(1), Image: &image},
		{Operation: DeleteComment, CommentID: resourceID(1), Liked: &no},
		{Operation: SetLike, CommentID: resourceID(1)},
		{Operation: SetLike, CommentID: resourceID(1), Liked: &no, IdentityID: resourceID(2)},
		{Operation: SetLike, CommentID: resourceID(1), Liked: &no, TaskID: resourceID(2)},
		{Operation: SetLike, CommentID: resourceID(1), Liked: &no, Body: " "},
		{Operation: SetLike, CommentID: resourceID(1), Liked: &no, Image: &image},
	}
	for n, input := range cases {
		if _, err := FrameIntent(input); err == nil {
			t.Fatalf("accepted operation-unrelated fields in case %d", n)
		}
	}
}

func TestCommentProtocolStructuralBudgetsAndRejectionDigests(t *testing.T) {
	for _, body := range []string{"", " \t\n", "\x00", strings.Repeat("文", MaxBodyClusters+1)} {
		input := protocolCreate()
		input.Body = body
		if _, err := FrameIntent(input); err != nil {
			t.Fatal("business-invalid input cannot get a rejection fingerprint", err)
		}
	}
	for _, id := range []string{"", "00000000-0000-0000-0000-000000000000", "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", "{11111111-1111-4111-8111-111111111111}"} {
		input := protocolCreate()
		input.PostID = id
		if _, err := FrameIntent(input); err == nil {
			t.Fatal("accepted invalid UUID")
		}
	}
	for _, version := range []int32{-1, 0} {
		if _, err := FrameIntent(Intent{Operation: Retry, TaskID: resourceID(1), ExpectedAttemptVersion: version}); err == nil {
			t.Fatal("accepted invalid version")
		}
	}
	for _, invalidBody := range []string{"a\xff", "\xed\xa0\x80", strings.Repeat("a", MaxFrameBytes+1)} {
		input := protocolCreate()
		input.Body = invalidBody
		if _, err := FrameIntent(input); err == nil {
			t.Fatal("accepted invalid UTF-8 or oversized text")
		}
	}
	for _, mutate := range []func(*Intent){
		func(i *Intent) { i.RootCommentID = "" },
		func(i *Intent) { i.TargetCommentID = "" },
		func(i *Intent) { i.Image = &postmedia.Selection{} },
	} {
		input := protocolCreate()
		mutate(&input)
		if _, err := FrameIntent(input); err == nil {
			t.Fatal("accepted incomplete target or invalid image")
		}
	}
	input := protocolCreate()
	overhead := len("HNUHOLE/COMMENT-COMMAND/V1") + 2 + 16*5 + 4 + 1
	input.Body = strings.Repeat("a", MaxFrameBytes-overhead)
	if frame, err := FrameIntent(input); err != nil || len(frame) != MaxFrameBytes {
		t.Fatal("exact full frame budget rejected", err)
	}
	input.Body += "a"
	if _, err := FrameIntent(input); err == nil {
		t.Fatal("framing overhead escaped total byte budget")
	}
}

func TestCommentKeyAndFingerprintDomainsAreSeparateFromPosts(t *testing.T) {
	key, fingerprint := bytes.Repeat([]byte{1}, 32), bytes.Repeat([]byte{2}, 32)
	codec, err := NewCommandCodec(key, fingerprint)
	if err != nil {
		t.Fatal(err)
	}
	postCodec, _ := posts.NewCommandCodec(key, fingerprint)
	command := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{3}, 16))
	one, err := codec.KeyDigest(resourceID(1), command)
	otherAccount, _ := codec.KeyDigest(resourceID(2), command)
	postKey, _ := postCodec.KeyDigest(resourceID(1), command)
	if err != nil || one == otherAccount || one == postKey {
		t.Fatal("comment command key lacks account/domain separation")
	}
	digest, _ := RequestDigest(protocolCreate())
	if codec.IntentFingerprint(digest) == postCodec.IntentFingerprint(digest) {
		t.Fatal("post/comment intent fingerprints share a namespace")
	}
	key[0], fingerprint[0] = 99, 99
	if again, _ := codec.KeyDigest(resourceID(1), command); again != one {
		t.Fatal("caller mutated codec key")
	}
	for _, bad := range []string{"", strings.Repeat("A", 22), command + "==", command[:21] + "_"} {
		if _, err := ParseCommandKey(bad); err == nil {
			t.Fatal("noncanonical comment command key accepted")
		}
	}
	for _, pair := range [][2][]byte{{nil, nil}, {bytes.Repeat([]byte{1}, 32), bytes.Repeat([]byte{1}, 32)}, {make([]byte, 32), bytes.Repeat([]byte{2}, 32)}} {
		if _, err := NewCommandCodec(pair[0], pair[1]); err == nil {
			t.Fatal("invalid command codec keys accepted")
		}
	}
}
