package authprivacyhttp

import (
	"errors"
	"net"
	"net/http"
	"net/netip"
	"strings"
)

// TrustedSource accepts X-Forwarded-For only from an explicitly configured
// immediate proxy and removes trusted hops from right to left. Untrusted
// direct callers cannot influence identity with arbitrary forwarding headers.
func TrustedSource(r *http.Request, trusted []netip.Prefix) (string, error) {
	host, port, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return "", errMalformed
	}
	peer, err := netip.ParseAddr(host)
	if err != nil {
		return "", errMalformed
	}
	peer = peer.WithZone("").Unmap()
	isTrusted := func(ip netip.Addr) bool {
		for _, p := range trusted {
			if p.Contains(ip) {
				return true
			}
		}
		return false
	}
	if !isTrusted(peer) {
		return net.JoinHostPort(peer.String(), port), nil
	}
	values := r.Header.Values("X-Forwarded-For")
	if len(values) == 0 {
		return net.JoinHostPort(peer.String(), port), nil
	}
	if len(values) != 1 || len(values[0]) > 2048 {
		return "", errors.New("invalid trusted forwarding chain")
	}
	parts := strings.Split(values[0], ",")
	if len(parts) > 32 {
		return "", errors.New("trusted forwarding chain too long")
	}
	chain := make([]netip.Addr, len(parts))
	for i, s := range parts {
		ip, e := netip.ParseAddr(strings.TrimSpace(s))
		if e != nil || ip.Zone() != "" {
			return "", errMalformed
		}
		chain[i] = ip.Unmap()
	}
	for i := len(chain) - 1; i >= 0; i-- {
		if !isTrusted(peer) {
			break
		}
		peer = chain[i]
	}
	return net.JoinHostPort(peer.String(), port), nil
}
