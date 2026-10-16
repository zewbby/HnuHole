package authprivacy

import (
	"errors"
	"time"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

const IdentityDefaultAvatar = "default-v1"

var (
	ErrIdentityInvalidName = errors.New("identity nickname invalid")
	ErrIdentityDuplicateName = errors.New("identity nickname already used by this account")
	ErrIdentityLimit = errors.New("identity limit reached")
	ErrIdentityCreateCooldown = errors.New("identity creation cooldown")
	ErrIdentityRenameCooldown = errors.New("identity rename cooldown")
	ErrIdentityLast = errors.New("last identity cannot be deleted")
	ErrIdentityNotFound = errors.New("own identity not found")
	ErrIdentityChangeConflict = errors.New("identity change key conflicts with its original intent")
)

// ValidateIdentityNickname normalizes canonically equivalent input before the
// case-sensitive, account-local uniqueness check. It accepts only the language
// scripts in MASK-NAME-01, decimal numbers, punctuation and their visible
// combining marks. Since emoji, selectors, joiners and other scripts are not
// accepted, the remaining grapheme boundaries are combining marks and Hangul.
func ValidateIdentityNickname(input string) (string, error) {
	if !utf8.ValidString(input) || len(input) > 512 {
		return "", ErrIdentityInvalidName
	}
	name := norm.NFC.String(input)
	count := 0
	var previous rune
	canMark := false
	for _, r := range name {
		if identityInvisible(r) || unicode.IsSpace(r) || unicode.IsControl(r) {
			return "", ErrIdentityInvalidName
		}
		if identityCombiningMark(r) {
			if !canMark {
				return "", ErrIdentityInvalidName
			}
			// GB6–GB8 require adjacent Hangul classes. An Extend attaches
			// to the preceding cluster but breaks L/V/T adjacency afterward.
			previous = 0
			continue
		}
		letter := identityLetter(r)
		punctuation := unicode.IsPunct(r) && r != '\u203c' && r != '\u2049' && r != '\u3030' && r != '\u303d'
		if !letter && !unicode.Is(unicode.Nd, r) && !punctuation {
			return "", ErrIdentityInvalidName
		}
		if !identityHangulContinuation(previous, r) {
			count++
		}
		if count > 12 {
			return "", ErrIdentityInvalidName
		}
		previous, canMark = r, letter
	}
	if count < 2 {
		return "", ErrIdentityInvalidName
	}
	return name, nil
}

func identityInvisible(r rune) bool {
	return unicode.Is(unicode.Cf, r) || unicode.Is(unicode.Co, r) ||
		unicode.Is(unicode.Cs, r) || r == '\u034f' || r == '\u115f' ||
		r == '\u1160' || r == '\u3164' || r == '\uffa0' ||
		(r >= '\ufe00' && r <= '\ufe0f') || (r >= 0xe0100 && r <= 0xe01ef)
}

func identityCombiningMark(r rune) bool {
	// Halfwidth voiced kana marks are letters in General_Category but
	// Extend in grapheme segmentation, and shared by Japanese scripts.
	if r == '\uff9e' || r == '\uff9f' {
		return true
	}
	return (unicode.Is(unicode.Mn, r) || unicode.Is(unicode.Mc, r)) &&
		((r >= 0x0300 && r <= 0x036f) || (r >= 0x1ab0 && r <= 0x1aff) ||
			(r >= 0x1dc0 && r <= 0x1dff) || (r >= 0xfe20 && r <= 0xfe2f) ||
			r == '\u3099' || r == '\u309a' || r == '\u302e' || r == '\u302f')
}

func identityLetter(r rune) bool {
	return unicode.IsLetter(r) &&
		(unicode.In(r, unicode.Latin, unicode.Han, unicode.Hiragana, unicode.Katakana, unicode.Hangul) ||
			r == '\u3006' || r == '\u30fc' || r == '\uff70' || (r >= '\u3031' && r <= '\u3035'))
}

func identityHangulClass(r rune) byte {
	switch {
	case (r >= 0x1100 && r <= 0x115f) || (r >= 0xa960 && r <= 0xa97c):
		return 'L'
	case (r >= 0x1160 && r <= 0x11a7) || (r >= 0xd7b0 && r <= 0xd7c6):
		return 'V'
	case (r >= 0x11a8 && r <= 0x11ff) || (r >= 0xd7cb && r <= 0xd7fb):
		return 'T'
	case r >= 0xac00 && r <= 0xd7a3:
		if (r-0xac00)%28 == 0 {
			return 'A' // LV
		}
		return 'B' // LVT
	default:
		return 0
	}
}

func identityHangulContinuation(previous, current rune) bool {
	a, b := identityHangulClass(previous), identityHangulClass(current)
	return (a == 'L' && (b == 'L' || b == 'V' || b == 'A' || b == 'B')) ||
		((a == 'A' || a == 'V') && (b == 'V' || b == 'T')) ||
		((a == 'B' || a == 'T') && b == 'T')
}

// Contemporary Asia/Shanghai dates use UTC+08:00. Explicit calendar arithmetic
// avoids host timezone and Go AddDate's overflow (Aug 31 -> Mar 3) at month ends.
func identityNextCreateAt(createdCount int64, lastCreatedAt *time.Time) *time.Time {
	if createdCount < 3 || lastCreatedAt == nil {
		return nil
	}
	zone := time.FixedZone("Asia/Shanghai", 8*60*60)
	local := lastCreatedAt.In(zone)
	first := time.Date(local.Year(), local.Month()+6, 1, local.Hour(), local.Minute(), local.Second(), local.Nanosecond(), zone)
	lastDay := time.Date(first.Year(), first.Month()+1, 0, 0, 0, 0, 0, zone).Day()
	day := local.Day()
	if day > lastDay {
		day = lastDay
	}
	result := time.Date(first.Year(), first.Month(), day, local.Hour(), local.Minute(), local.Second(), local.Nanosecond(), zone).UTC()
	return &result
}

func identityRenameAvailableAt(lastRenamedAt *time.Time) *time.Time {
	if lastRenamedAt == nil {
		return nil
	}
	result := lastRenamedAt.Add(30 * 24 * time.Hour).UTC()
	return &result
}
