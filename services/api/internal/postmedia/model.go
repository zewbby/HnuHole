// Package postmedia defines immutable post media contracts. It holds no account
// credentials, storage URLs, or viewer implementation.
package postmedia

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"

	"github.com/google/uuid"
)

const MaxImages = 9
const MaxBytes = 10 * 1024 * 1024
const MaxDimension = 16384
const MaxPixels = 12 * 1024 * 1024
const MaxAnimationPixels = 1024 * 1024
const MaxFramePixels = 16 * 1024 * 1024
const MaxFrames = 120

var ErrInvalid = errors.New("invalid image manifest or bytes")
var ErrUnavailable = errors.New("image validator unavailable")

// Selection is fixed at acceptance, in array order. IDs are random selection
// IDs, not filenames or content hashes. A changed byte requires a new attempt.
type Selection struct {
	MediaID    string `json:"mediaId"`
	SHA256     string `json:"sha256"`
	ByteLength int    `json:"byteLength"`
	MIME       string `json:"mimeType"`
	Width      int    `json:"width"`
	Height     int    `json:"height"`
}

func ValidID(s string) bool {
	id, e := uuid.Parse(s)
	return e == nil && id != uuid.Nil && id.String() == s
}

func ValidateManifest(items []Selection) error {
	if len(items) > MaxImages {
		return ErrInvalid
	}
	ids := map[string]bool{}
	for _, s := range items {
		digest, e := hex.DecodeString(s.SHA256)
		if !ValidID(s.MediaID) || ids[s.MediaID] || e != nil || len(digest) != 32 || strings.ToLower(s.SHA256) != s.SHA256 || s.ByteLength < 1 || s.ByteLength > MaxBytes || !ValidSize(s.Width, s.Height) {
			return ErrInvalid
		}
		switch s.MIME {
		case "image/jpeg", "image/png", "image/gif", "image/webp":
		default:
			return ErrInvalid
		}
		ids[s.MediaID] = true
	}
	return nil
}

func ValidSize(w, h int) bool {
	return w > 0 && h > 0 && w <= MaxDimension && h <= MaxDimension && int64(w)*int64(h) <= MaxPixels
}

// Metadata is computed from complete bytes, never trusted from a filename,
// client MIME, DecodeConfig alone, or a first animation frame.
type Metadata struct {
	MIME               string `json:"mimeType"`
	Width              int    `json:"width"`
	Height             int    `json:"height"`
	DisplayWidth       int    `json:"displayWidth"`
	DisplayHeight      int    `json:"displayHeight"`
	Frames             int    `json:"frames"`
	Animated           bool   `json:"animated"`
	SHA256             string `json:"sha256"`
	ByteLength         int    `json:"byteLength"`
	CycleDurationMS    int    `json:"cycleDurationMs"`
	MaxFrameDurationMS int    `json:"maxFrameDurationMs"`
}

func (m Metadata) Matches(s Selection, data []byte) bool {
	hash := sha256.Sum256(data)
	return ValidateManifest([]Selection{s}) == nil && len(data) == s.ByteLength && hex.EncodeToString(hash[:]) == s.SHA256 && m.SHA256 == s.SHA256 && m.ByteLength == s.ByteLength && m.MIME == s.MIME && m.Width == s.Width && m.Height == s.Height && ((m.DisplayWidth == m.Width && m.DisplayHeight == m.Height) || (m.DisplayWidth == m.Height && m.DisplayHeight == m.Width)) && m.Frames >= 1 && m.Frames <= MaxFrames && m.Animated == (m.Frames > 1) && (!m.Animated || int64(m.Width)*int64(m.Height) <= MaxAnimationPixels && int64(m.Width)*int64(m.Height)*int64(m.Frames) <= MaxFramePixels && m.CycleDurationMS >= 0 && m.CycleDurationMS <= 60_000 && m.MaxFrameDurationMS >= 0 && m.MaxFrameDurationMS <= 15_000)
}

type Source struct {
	Path       string `json:"path"`
	MIME       string `json:"mimeType"`
	ByteLength int    `json:"byteLength"`
}

type Image struct {
	MediaID          string `json:"mediaId"`
	ContentVersionID string `json:"contentVersionId"`
	Position         int    `json:"position"`
	Width            int    `json:"width"`
	Height           int    `json:"height"`
	PixelWidth       int    `json:"pixelWidth"`
	PixelHeight      int    `json:"pixelHeight"`
	Frames           int    `json:"frames"`
	Animated         bool   `json:"animated"`
	SaveAllowed      bool   `json:"saveAllowed"`
	Thumbnail        Source `json:"thumbnail"`
	Full             Source `json:"full"`
	Original         Source `json:"original"`
}

type Group struct {
	PostID string  `json:"postId"`
	Images []Image `json:"images"`
	// Lease is bounded by the session and 60 seconds, using C's trusted clock.
	AccessValidUntil string `json:"accessValidUntil"`
}

type UploadItem struct {
	Selection
	Position int  `json:"position"`
	Uploaded bool `json:"uploaded"`
}

type UploadState struct {
	TaskID         string       `json:"taskId"`
	PostID         string       `json:"postId"`
	AttemptVersion int32        `json:"attemptVersion"`
	Items          []UploadItem `json:"items"`
}

type Grant struct {
	TaskID         string `json:"taskId"`
	MediaID        string `json:"mediaId"`
	AttemptVersion int32  `json:"attemptVersion"`
	UploadToken    string `json:"uploadToken"`
	ExpiresAt      string `json:"expiresAt"`
}
