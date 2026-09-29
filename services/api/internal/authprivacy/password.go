package authprivacy

import (
	"context"
	"crypto/rand"
	"errors"
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"
	"golang.org/x/text/unicode/norm"
)

var (
	ErrPasswordPolicy = errors.New("password policy rejected")
	ErrPasswordBusy   = errors.New("password worker capacity reached")
)

// PasswordPreparer implements the frozen version-1 profile. The caller loads a
// reviewed local common/breached-password list; it never sends passwords to an
// online checking service. Production list coverage and capacity still need
// operational calibration. The lab intentionally has no implicit empty list.
type PasswordPreparer struct {
	workers chan struct{}
	blocked map[string]struct{}
}

func NewPasswordPreparer(maxConcurrent int, blocklist []string) (*PasswordPreparer, error) {
	if maxConcurrent < 1 || maxConcurrent > 16 || len(blocklist) == 0 {
		return nil, errors.New("password preparer needs bounded workers and a blocklist")
	}
	p := &PasswordPreparer{workers: make(chan struct{}, maxConcurrent), blocked: make(map[string]struct{}, len(blocklist))}
	for _, password := range blocklist {
		if !utf8.ValidString(password) || password == "" || len(password) > 2048 {
			return nil, errors.New("invalid password blocklist entry")
		}
		p.blocked[strings.ToLower(norm.NFC.String(password))] = struct{}{}
	}
	return p, nil
}

// PreparePassword never queues unbounded expensive work and runs before SQL
// locks. Changing these parameters requires a new stored parameter version.
func (p *PasswordPreparer) PreparePassword(ctx context.Context, password, username string) (PasswordMaterial, error) {
	var material PasswordMaterial
	if err := ctx.Err(); err != nil {
		return material, err
	}
	if !utf8.ValidString(password) || len(password) > 2048 || utf8.RuneCountInString(password) > 512 {
		return material, ErrPasswordPolicy
	}
	canonical := norm.NFC.String(password)
	count := utf8.RuneCountInString(canonical)
	if count < 15 || count > 128 {
		return material, ErrPasswordPolicy
	}
	lower := strings.ToLower(canonical)
	if _, blocked := p.blocked[lower]; blocked || usernameRelated(lower, strings.ToLower(username)) {
		return material, ErrPasswordPolicy
	}
	select {
	case p.workers <- struct{}{}:
		defer func() { <-p.workers }()
	default:
		return material, ErrPasswordBusy
	}
	if _, err := rand.Read(material.Salt[:]); err != nil {
		return PasswordMaterial{}, err
	}
	input := []byte(canonical)
	defer clear(input)
	derived := argon2.IDKey(input, material.Salt[:], 3, 64*1024, 4, 32)
	copy(material.Hash[:], derived)
	clear(derived)
	if err := ctx.Err(); err != nil {
		return PasswordMaterial{}, err
	}
	material.ParametersVersion = 1
	return material, nil
}

// Reject the username alone/repeated or padded only with digits, punctuation,
// symbols and whitespace. A longer phrase that happens to mention a username
// is not treated as a weak password by this rule.
func usernameRelated(password, username string) bool {
	if username == "" || !strings.Contains(password, username) {
		return false
	}
	remainder := strings.ReplaceAll(password, username, "")
	return strings.IndexFunc(remainder, unicode.IsLetter) < 0
}
