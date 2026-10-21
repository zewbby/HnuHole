package authprivacyruntime

import (
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSMTPRuntimeOptInAndPrivateCredentials(t *testing.T) {
	directory := t.TempDir()
	secret := filepath.Join(directory, "qq.secret")
	if err := os.WriteFile(secret, []byte("abcdefghijklmnop\n"), 0600); err != nil {
		t.Fatal(err)
	}
	candidate := Config{base: directory, SMTPAddress: "smtp.qq.com:465", SMTPFrom: "fixture@qq.com", SMTPMode: "tls", SMTPUsername: "fixture@qq.com", SMTPPasswordFile: "qq.secret"}
	if _, err := candidate.smtpProvider(time.Second); err != nil {
		t.Fatal("valid implicit TLS configuration rejected")
	}
	candidate.SMTPMode = "starttls"
	if _, err := candidate.smtpProvider(time.Second); err != nil {
		t.Fatal("valid STARTTLS configuration rejected")
	}
	for _, mode := range []string{"", "loopback", "plain", "ssl-typo"} {
		bad := candidate
		bad.SMTPMode = mode
		if _, err := bad.smtpProvider(time.Second); err == nil {
			t.Fatalf("unexpected SMTP mode accepted: %q", mode)
		}
	}
	if err := candidate.Validate(authprivacyhttp.CommunityService); err == nil || !strings.Contains(err.Error(), "only to V") {
		t.Fatal("C accepted SMTP credentials")
	}
	if err := os.Chmod(secret, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := candidate.smtpProvider(time.Second); err == nil {
		t.Fatal("public secret file accepted")
	}
	if err := os.Chmod(secret, 0600); err != nil {
		t.Fatal(err)
	}
	for _, content := range []string{"", "\n", "first\nsecond", "secret\x00injection"} {
		if err := os.WriteFile(secret, []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := candidate.smtpProvider(time.Second); err == nil {
			t.Fatal("invalid secret file accepted")
		}
	}
	if err := os.WriteFile(secret, []byte("abcdefghijklmnop"), 0600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(directory, "alias.secret")
	if err := os.Symlink(secret, link); err != nil {
		t.Fatal(err)
	}
	candidate.SMTPPasswordFile = link
	if _, err := candidate.smtpProvider(time.Second); err == nil {
		t.Fatal("symlink secret file accepted")
	}
}

func TestSMTPLegacyModeRemainsLocalAndUnauthenticated(t *testing.T) {
	candidate := Config{SMTPAddress: "127.0.0.1:2525", SMTPFrom: "otp@verifier.test"}
	if _, err := candidate.smtpProvider(time.Second); err != nil {
		t.Fatal("legacy Mailpit configuration broken")
	}
	candidate.SMTPAddress = "smtp.qq.com:465"
	if _, err := candidate.smtpProvider(time.Second); err == nil {
		t.Fatal("legacy mode enabled external plaintext delivery")
	}
	candidate.SMTPMode = "tls"
	if _, err := candidate.smtpProvider(time.Second); err == nil {
		t.Fatal("TLS mode without credentials accepted")
	}
}
