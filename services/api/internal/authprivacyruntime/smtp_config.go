package authprivacyruntime

import (
	"errors"
	"strings"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

// Old dev configurations retain unauthenticated literal-loopback SMTP.
// External delivery is explicit; secrets never appear in the config JSON.
func (c Config) smtpProvider(timeout time.Duration) (*authprivacy.SMTPProvider, error) {
	config := authprivacy.SMTPConfig{Address: c.SMTPAddress, From: c.SMTPFrom, Timeout: timeout}
	switch c.SMTPMode {
	case "", "loopback":
		if c.SMTPUsername != "" || c.SMTPPasswordFile != "" {
			return nil, errors.New("loopback SMTP must not have credentials")
		}
		config.AllowInsecureLoopback = true
	case "tls", "starttls":
		if c.SMTPUsername == "" || c.SMTPPasswordFile == "" {
			return nil, errors.New("external SMTP requires username and a private password file")
		}
		raw, err := c.Read(c.SMTPPasswordFile, true, 512)
		if err != nil {
			return nil, errors.New("invalid SMTP credential material")
		}
		secret := strings.TrimSuffix(strings.TrimSuffix(string(raw), "\n"), "\r")
		if secret == "" || strings.ContainsAny(secret, "\r\n\x00") {
			return nil, errors.New("invalid SMTP credential material")
		}
		config.Username = c.SMTPUsername
		config.Password = secret
		config.ImplicitTLS = c.SMTPMode == "tls"
	default:
		return nil, errors.New("SMTP mode must be loopback, tls, or starttls")
	}
	return authprivacy.NewSMTPProvider(config)
}
