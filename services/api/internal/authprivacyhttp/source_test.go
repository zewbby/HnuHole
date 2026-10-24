package authprivacyhttp

import (
	"net/http/httptest"
	"net/netip"
	"testing"
)

func TestSharedSourceTrustedChainAndForgedHeaders(t *testing.T) {
	trusted := []netip.Prefix{netip.MustParsePrefix("10.0.0.0/8"), netip.MustParsePrefix("2001:db8:1::/48")}
	for _, tc := range []struct{ remote, chain, want string }{
		{"192.0.2.10:123", "203.0.113.42", "192.0.2.10:123"},
		{"10.0.0.1:123", "203.0.113.42, 10.0.0.2", "203.0.113.42:123"},
		{"10.0.0.1:123", "198.51.100.4, 203.0.113.42", "203.0.113.42:123"},
		{"[2001:db8:1::1]:123", "2001:db8:2::5", "[2001:db8:2::5]:123"},
	} {
		r := httptest.NewRequest("GET", "https://example.test/", nil)
		r.RemoteAddr = tc.remote
		r.Header.Set("X-Forwarded-For", tc.chain)
		got, err := TrustedSource(r, trusted)
		if err != nil || got != tc.want {
			t.Fatalf("trusted chain %q: %s %v", tc.remote, got, err)
		}
	}
	r := httptest.NewRequest("GET", "https://example.test/", nil)
	r.RemoteAddr = "10.0.0.1:123"
	r.Header.Add("X-Forwarded-For", "192.0.2.1")
	r.Header.Add("X-Forwarded-For", "198.51.100.1")
	if _, err := TrustedSource(r, trusted); err == nil {
		t.Fatal("duplicate trusted header accepted")
	}
}
