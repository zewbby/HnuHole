package authprivacyruntime

import (
	"encoding/base64"
	"strings"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

func TestRuntimeWebAuthnPolicyIsExplicitAndIndependent(t *testing.T) {
	android := "android:apk-key-hash:" + base64.RawURLEncoding.EncodeToString([]byte(strings.Repeat("a", 32)))
	c := Config{PublicOrigin: "https://127.0.0.1:8443", AllowedOrigins: []string{"https://unrelated.example.test"}}
	if err := c.validateWebAuthn(authprivacyhttp.CommunityService); err != nil || c.WebAuthn != nil {
		t.Fatal("HTTP origins implicitly enabled Passkey authority")
	}
	c.WebAuthn = &authprivacy.WebAuthnConfig{RPID: "example.test", Origins: []string{"https://example.test"}, AndroidOrigins: []string{android}}
	if err := c.validateWebAuthn(authprivacyhttp.CommunityService); err != nil {
		t.Fatal(err)
	}
	if err := c.validateWebAuthn(authprivacyhttp.VerifierService); err == nil {
		t.Fatal("V accepted community Passkey authority")
	}
	c.WebAuthn.AndroidOrigins[0] = android + "="
	if err := c.validateWebAuthn(authprivacyhttp.CommunityService); err == nil {
		t.Fatal("noncanonical APK signing origin accepted")
	}
	c.WebAuthn.AndroidOrigins = []string{"https://example.test"}
	if err := c.validateWebAuthn(authprivacyhttp.CommunityService); err == nil {
		t.Fatal("native and HTTPS trust lists were mixed")
	}
	c.WebAuthn.AndroidOrigins = nil
	c.WebAuthn.Origins = []string{android}
	if err := c.validateWebAuthn(authprivacyhttp.CommunityService); err == nil {
		t.Fatal("Android identity accepted in HTTPS trust list")
	}
}
