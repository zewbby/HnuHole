package comments

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"unicode/utf8"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

const MaxFrameBytes = 262144

var ErrFrameTooLarge = errors.New("comment command frame too large")

type Operation string

const (
	Create        Operation = "CREATE"
	Retry         Operation = "RETRY"
	Abandon       Operation = "ABANDON"
	DeleteComment Operation = "DELETE"
	SetLike       Operation = "SET_LIKE"
)

func (o Operation) Valid() bool {
	return o == Create || o == Retry || o == Abandon || o == DeleteComment || o == SetLike
}

// Intent is an immutable command payload. Command keys are transport metadata,
// outside this frame. Liked is a pointer so false differs from an absent field.
type Intent struct {
	Operation                                                  Operation
	TaskID, PostID, IdentityID, RootCommentID, TargetCommentID string
	CommentID                                                  string
	ExpectedAttemptVersion                                     int32
	Body                                                       string
	Image                                                      *postmedia.Selection
	Liked                                                      *bool
}

// FrameIntent validates structure only. Empty, whitespace-only or otherwise
// business-invalid UTF-8 text still receives a stable rejection fingerprint.
// It never trims, normalizes, or replaces newline sequences.
func FrameIntent(intent Intent) ([]byte, error) {
	frame := append([]byte("HNUHOLE/COMMENT-COMMAND/V1"), 0)
	addID := func(value string) bool {
		id, err := posts.ParseResourceID(value)
		if err != nil {
			return false
		}
		frame = append(frame, id[:]...)
		return true
	}
	addOptionalID := func(value string) bool {
		if value == "" {
			frame = append(frame, make([]byte, 16)...)
			return true
		}
		return addID(value)
	}
	addText := func(value string) bool {
		if !utf8.ValidString(value) || len(value) > MaxFrameBytes {
			return false
		}
		frame = binary.BigEndian.AppendUint32(frame, uint32(len(value)))
		frame = append(frame, value...)
		return true
	}
	addVersion := func() bool {
		if intent.ExpectedAttemptVersion < 1 {
			return false
		}
		frame = binary.BigEndian.AppendUint64(frame, uint64(intent.ExpectedAttemptVersion))
		return true
	}
	addImage := func() bool {
		if intent.Image == nil {
			frame = append(frame, 0)
			return true
		}
		s := *intent.Image
		if postmedia.ValidateManifest([]postmedia.Selection{s}) != nil {
			return false
		}
		frame = append(frame, 1)
		if !addID(s.MediaID) || !addText(s.SHA256) || !addText(s.MIME) {
			return false
		}
		frame = binary.BigEndian.AppendUint32(frame, uint32(s.ByteLength))
		frame = binary.BigEndian.AppendUint32(frame, uint32(s.Width))
		frame = binary.BigEndian.AppendUint32(frame, uint32(s.Height))
		return true
	}
	noContext := intent.PostID == "" && intent.IdentityID == "" && intent.RootCommentID == "" && intent.TargetCommentID == ""
	valid := false
	switch intent.Operation {
	case Create:
		frame = append(frame, 1)
		valid = intent.CommentID == "" && intent.ExpectedAttemptVersion == 0 && intent.Liked == nil &&
			(intent.RootCommentID == "") == (intent.TargetCommentID == "") &&
			addID(intent.TaskID) && addID(intent.PostID) && addID(intent.IdentityID) &&
			addOptionalID(intent.RootCommentID) && addOptionalID(intent.TargetCommentID) && addText(intent.Body) && addImage()
	case Retry:
		frame = append(frame, 2)
		valid = noContext && intent.CommentID == "" && intent.Liked == nil && addID(intent.TaskID) && addVersion() && addText(intent.Body) && addImage()
	case Abandon:
		frame = append(frame, 3)
		valid = noContext && intent.CommentID == "" && intent.Body == "" && intent.Image == nil && intent.Liked == nil && addID(intent.TaskID) && addVersion()
	case DeleteComment:
		frame = append(frame, 4)
		valid = noContext && intent.TaskID == "" && intent.ExpectedAttemptVersion == 0 && intent.Body == "" && intent.Image == nil && intent.Liked == nil && addID(intent.CommentID)
	case SetLike:
		frame = append(frame, 5)
		valid = noContext && intent.TaskID == "" && intent.ExpectedAttemptVersion == 0 && intent.Body == "" && intent.Image == nil && intent.Liked != nil && addID(intent.CommentID)
		if valid {
			value := byte(0)
			if *intent.Liked {
				value = 1
			}
			frame = append(frame, value)
		}
	}
	if !valid {
		return nil, ErrInvalid
	}
	if len(frame) > MaxFrameBytes {
		return nil, ErrFrameTooLarge
	}
	return frame, nil
}

func RequestDigest(intent Intent) ([32]byte, error) {
	frame, err := FrameIntent(intent)
	if err != nil {
		return [32]byte{}, err
	}
	return sha256.Sum256(frame), nil
}

// CommandCodec uses the post key's canonical 16-byte base64url structure while
// separating account-scoped key and intent HMAC namespaces from every post key.
type CommandCodec struct {
	keyKey, fingerprintKey [32]byte
}

func NewCommandCodec(keyKey, fingerprintKey []byte) (*CommandCodec, error) {
	if len(keyKey) != 32 || len(fingerprintKey) != 32 || hmac.Equal(keyKey, fingerprintKey) || allZero(keyKey) || allZero(fingerprintKey) {
		return nil, ErrInvalid
	}
	c := &CommandCodec{}
	copy(c.keyKey[:], keyKey)
	copy(c.fingerprintKey[:], fingerprintKey)
	return c, nil
}

func allZero(value []byte) bool {
	var result byte
	for _, b := range value {
		result |= b
	}
	return result == 0
}

func ParseCommandKey(value string) ([16]byte, error) { return posts.ParseCommandKey(value) }

func (c *CommandCodec) KeyDigest(accountID, commandKey string) ([32]byte, error) {
	account, err := posts.ParseResourceID(accountID)
	if err != nil || c == nil {
		return [32]byte{}, ErrInvalid
	}
	key, err := ParseCommandKey(commandKey)
	if err != nil {
		return [32]byte{}, err
	}
	mac := hmac.New(sha256.New, c.keyKey[:])
	_, _ = mac.Write([]byte("HNUHOLE/COMMENT-KEY/V1\x00"))
	_, _ = mac.Write(account[:])
	_, _ = mac.Write(key[:])
	var result [32]byte
	copy(result[:], mac.Sum(nil))
	return result, nil
}

func (c *CommandCodec) IntentFingerprint(digest [32]byte) [32]byte {
	mac := hmac.New(sha256.New, c.fingerprintKey[:])
	_, _ = mac.Write([]byte("HNUHOLE/COMMENT-INTENT/V1\x00"))
	_, _ = mac.Write(digest[:])
	var result [32]byte
	copy(result[:], mac.Sum(nil))
	return result
}
