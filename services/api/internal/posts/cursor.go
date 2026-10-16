package posts

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"io"
	"time"
)

const (
	CursorChannel = "channel"
	CursorOwn     = "own"
	CursorTask    = "task"
	CursorTTL     = 30 * time.Minute
)

type CursorPosition struct {
	Scope       string    `json:"scope"`
	AccountID   string    `json:"accountId"`
	ChannelID   string    `json:"channelId"`
	Ceiling     int64     `json:"ceiling"`
	LastAt      time.Time `json:"lastAt"`
	LastOrdinal int64     `json:"lastOrdinal"`
	LastID      string    `json:"lastId"`
	Limit       int       `json:"limit"`
	ExpiresAt   time.Time `json:"expiresAt"`
}

type CursorCodec struct {
	aead cipher.AEAD
	aad  []byte
}

func NewCursorCodec(key []byte, environment string) (*CursorCodec, error) {
	if len(key) != 32 || zeroKey(key) || len(environment) < 1 || len(environment) > 512 {
		return nil, ErrCursorInvalid
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, ErrCursorInvalid
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, ErrCursorInvalid
	}
	aad := append([]byte("HNUHOLE/POST-CURSOR/V1"), 0)
	aad = binary.BigEndian.AppendUint32(aad, uint32(len(environment)))
	aad = append(aad, environment...)
	return &CursorCodec{aead: aead, aad: aad}, nil
}

// Encode 加密全部定位字段；外部只见版本、随机 nonce 和认证密文。
func (c *CursorCodec) Encode(position CursorPosition) (string, error) {
	if !validPosition(position) {
		return "", ErrCursorInvalid
	}
	position.LastAt = position.LastAt.UTC()
	position.ExpiresAt = position.ExpiresAt.UTC()
	plaintext, err := json.Marshal(position)
	if err != nil {
		return "", ErrCursorInvalid
	}
	raw := make([]byte, 1+c.aead.NonceSize())
	raw[0] = 1
	if _, err := io.ReadFull(rand.Reader, raw[1:]); err != nil {
		return "", err
	}
	raw = c.aead.Seal(raw, raw[1:], plaintext, c.aad)
	token := base64.RawURLEncoding.EncodeToString(raw)
	if len(token) > 1024 {
		return "", ErrCursorInvalid
	}
	return token, nil
}

// Decode 的 expected 只使用账号、scope、channel、limit，其他字段不参与绑定。
// 可信截止时间必须取最终授权事务的 TrustedAt；cursor 本身不授访问权。
func (c *CursorCodec) Decode(token string, expected CursorPosition, trustedAt time.Time) (CursorPosition, error) {
	if len(token) < 1 || len(token) > 1024 || trustedAt.IsZero() {
		return CursorPosition{}, ErrCursorInvalid
	}
	raw, err := base64.RawURLEncoding.Strict().DecodeString(token)
	nonceLength := c.aead.NonceSize()
	if err != nil || len(raw) < 1+nonceLength+c.aead.Overhead() || raw[0] != 1 || base64.RawURLEncoding.EncodeToString(raw) != token {
		return CursorPosition{}, ErrCursorInvalid
	}
	plaintext, err := c.aead.Open(nil, raw[1:1+nonceLength], raw[1+nonceLength:], c.aad)
	if err != nil {
		return CursorPosition{}, ErrCursorInvalid
	}
	var position CursorPosition
	if json.Unmarshal(plaintext, &position) != nil || !validPosition(position) || position.Scope != expected.Scope || position.AccountID != expected.AccountID || position.ChannelID != expected.ChannelID || position.Limit != expected.Limit || !trustedAt.Before(position.ExpiresAt) || position.ExpiresAt.After(trustedAt.Add(CursorTTL)) {
		return CursorPosition{}, ErrCursorInvalid
	}
	return position, nil
}

func validPosition(position CursorPosition) bool {
	if !validID(position.AccountID) || position.Limit < 1 || position.Limit > 50 || position.Ceiling < 0 || position.LastAt.IsZero() || position.ExpiresAt.IsZero() {
		return false
	}
	switch position.Scope {
	case CursorChannel:
		return validID(position.ChannelID) && position.LastOrdinal > 0 && position.LastOrdinal <= position.Ceiling && position.LastID == ""
	case CursorOwn:
		return position.ChannelID == "" && position.LastOrdinal > 0 && position.LastOrdinal <= position.Ceiling && position.LastID == ""
	case CursorTask:
		return position.ChannelID == "" && position.LastOrdinal == 0 && validID(position.LastID)
	default:
		return false
	}
}
