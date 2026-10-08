package posts

import (
	"unicode/utf8"

	"github.com/clipperhouse/uax29/v2/graphemes"
)

const (
	UnicodeVersion   = "16.0.0"
	MaxTitleClusters = 15
	MaxBodyClusters  = 3000
	MaxTitleBytes    = 4096
	MaxBodyBytes     = 65536
	MaxRequestBytes  = 256 * 1024
)

// CountGraphemes 使用冻结的 Unicode 16 规则，不做 trim 或正规化。
func CountGraphemes(text string) (int, error) {
	if !utf8.ValidString(text) {
		return 0, ErrContentInvalid
	}
	iterator := graphemes.FromString(text)
	count := 0
	for iterator.Next() {
		count++
	}
	return count, nil
}

func ValidateContent(title, body string) error {
	if len(title) > MaxTitleBytes || len(body) > MaxBodyBytes {
		return ErrPayloadTooLarge
	}
	if err := validateField(title, MaxTitleClusters); err != nil {
		return err
	}
	return validateField(body, MaxBodyClusters)
}

func validateField(text string, limit int) error {
	if !utf8.ValidString(text) {
		return ErrContentInvalid
	}
	hasVisible := false
	for _, scalar := range text {
		if ((scalar < 0x20 || scalar >= 0x7f && scalar <= 0x9f) && scalar != '\t' && scalar != '\r' && scalar != '\n') || scalar >= 0xd800 && scalar <= 0xdfff {
			return ErrContentInvalid
		}
		if !unicode16WhiteSpace(scalar) && !unicode16DefaultIgnorable(scalar) {
			hasVisible = true
		}
	}
	if !hasVisible {
		return ErrContentInvalid
	}
	iterator := graphemes.FromString(text)
	count := 0
	for iterator.Next() {
		count++
		if count > limit {
			return ErrContentInvalid
		}
	}
	return nil
}
