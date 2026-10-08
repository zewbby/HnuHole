package posts

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"
)

func ParseResourceID(value string) (uuid.UUID, error) {
	id, err := uuid.Parse(value)
	if err != nil || id == uuid.Nil || id.String() != value {
		return uuid.Nil, ErrInvalidID
	}
	return id, nil
}

func validID(value string) bool {
	_, err := ParseResourceID(value)
	return err == nil
}

func ParseCommandKey(value string) ([16]byte, error) {
	var key [16]byte
	if len(value) != 22 {
		return key, ErrInvalidCommandKey
	}
	decoded, err := base64.RawURLEncoding.Strict().DecodeString(value)
	if err != nil || len(decoded) != len(key) || base64.RawURLEncoding.EncodeToString(decoded) != value {
		return key, ErrInvalidCommandKey
	}
	copy(key[:], decoded)
	if key == [16]byte{} {
		return key, ErrInvalidCommandKey
	}
	return key, nil
}

func ParseRequestDigest(value string) ([32]byte, error) {
	var digest [32]byte
	if len(value) != 64 || strings.ToLower(value) != value {
		return digest, ErrInvalidIntent
	}
	decoded, err := hex.DecodeString(value)
	if err != nil {
		return digest, ErrInvalidIntent
	}
	copy(digest[:], decoded)
	return digest, nil
}

type Intent struct {
	Operation              Operation
	ChannelID              string
	IdentityID             string
	TaskID                 string
	PostID                 string
	ExpectedAttemptVersion int32
	Title                  string
	Body                   string
}

// FrameIntent 按协议字段编码，不对 JSON 字节或正规化文本计算摘要。
// 字素和可见字符验证独立进行，使无效业务内容仍可记录稳定拒绝回执。
func FrameIntent(intent Intent) ([]byte, error) {
	frame := append([]byte("HNUHOLE/POST-COMMAND/V1"), 0)
	addID := func(value string) bool {
		id, err := ParseResourceID(value)
		if err != nil {
			return false
		}
		frame = append(frame, id[:]...)
		return true
	}
	addText := func(value string) bool {
		if !utf8.ValidString(value) || len(value) > MaxRequestBytes {
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
	valid := false
	switch intent.Operation {
	case Create:
		frame = append(frame, 1)
		valid = intent.TaskID == "" && intent.PostID == "" && intent.ExpectedAttemptVersion == 0 && addID(intent.ChannelID) && addID(intent.IdentityID) && addText(intent.Title) && addText(intent.Body)
	case Retry:
		frame = append(frame, 2)
		valid = intent.ChannelID == "" && intent.IdentityID == "" && intent.PostID == "" && addID(intent.TaskID) && addVersion() && addText(intent.Title) && addText(intent.Body)
	case Cancel, HideTask:
		operationByte := byte(3)
		if intent.Operation == HideTask {
			operationByte = 5
		}
		frame = append(frame, operationByte)
		valid = intent.ChannelID == "" && intent.IdentityID == "" && intent.PostID == "" && intent.Title == "" && intent.Body == "" && addID(intent.TaskID) && addVersion()
	case DeletePost:
		frame = append(frame, 4)
		valid = intent.ChannelID == "" && intent.IdentityID == "" && intent.TaskID == "" && intent.Title == "" && intent.Body == "" && intent.ExpectedAttemptVersion == 0 && addID(intent.PostID)
	}
	if !valid {
		return nil, ErrInvalidIntent
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

type CommandCodec struct {
	keyKey         [32]byte
	fingerprintKey [32]byte
}

func NewCommandCodec(keyKey, fingerprintKey []byte) (*CommandCodec, error) {
	if len(keyKey) != 32 || len(fingerprintKey) != 32 || hmac.Equal(keyKey, fingerprintKey) || zeroKey(keyKey) || zeroKey(fingerprintKey) {
		return nil, ErrInvalidCommandKey
	}
	codec := new(CommandCodec)
	copy(codec.keyKey[:], keyKey)
	copy(codec.fingerprintKey[:], fingerprintKey)
	return codec, nil
}

func zeroKey(key []byte) bool {
	var result byte
	for _, b := range key {
		result |= b
	}
	return result == 0
}

func (c *CommandCodec) KeyDigest(accountID, commandKey string) ([32]byte, error) {
	id, err := ParseResourceID(accountID)
	if err != nil {
		return [32]byte{}, err
	}
	key, err := ParseCommandKey(commandKey)
	if err != nil {
		return [32]byte{}, err
	}
	mac := hmac.New(sha256.New, c.keyKey[:])
	mac.Write(append([]byte("HNUHOLE/POST-KEY/V1"), 0))
	mac.Write(id[:])
	mac.Write(key[:])
	var digest [32]byte
	copy(digest[:], mac.Sum(nil))
	return digest, nil
}

func (c *CommandCodec) IntentFingerprint(digest [32]byte) [32]byte {
	mac := hmac.New(sha256.New, c.fingerprintKey[:])
	mac.Write(append([]byte("HNUHOLE/POST-INTENT/V1"), 0))
	mac.Write(digest[:])
	var result [32]byte
	copy(result[:], mac.Sum(nil))
	return result
}

// NewShortCode 生成身份级 60 位随机编号，数据库唯一冲突须由调用方重试。
func NewShortCode() (string, error) {
	var random [8]byte
	if _, err := rand.Read(random[:]); err != nil {
		return "", err
	}
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(random[:])[:12], nil
}

func ValidShortCode(code string) bool {
	if len(code) != 12 {
		return false
	}
	for _, ch := range code {
		if !(ch >= 'A' && ch <= 'Z' || ch >= '2' && ch <= '7') {
			return false
		}
	}
	return true
}
