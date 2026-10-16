package authprivacyhttp

import (
	"bytes"
	"crypto"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"net/url"
	"regexp"
	"time"
)

type Service string

const (
	CommunityService Service = "community"
	VerifierService  Service = "verifier"
)

var (
	errPeerAuthentication = errors.New("peer authentication failed")
	environmentPattern    = regexp.MustCompile(`^[a-z][a-z0-9-]{0,31}$`)
)

// PeerIdentity is an operator-owned trust policy, never constructed from a
// request, a forwarded certificate header, or the certificate's CommonName.
// RevokedSerials uses lowercase hexadecimal serials within the dedicated CA.
type PeerIdentity struct {
	Environment    string
	Service        Service
	Roots          *x509.CertPool
	RevokedSerials map[string]bool
}

func IdentityURI(environment string, service Service) (*url.URL, error) {
	if !environmentPattern.MatchString(environment) || (service != CommunityService && service != VerifierService) {
		return nil, errors.New("invalid workload identity")
	}
	return &url.URL{Scheme: "spiffe", Host: "hnuhole", Path: "/" + environment + "/" + string(service)}, nil
}

func copyIdentity(policy PeerIdentity) (PeerIdentity, error) {
	if _, err := IdentityURI(policy.Environment, policy.Service); err != nil || policy.Roots == nil || len(policy.Roots.Subjects()) == 0 {
		return PeerIdentity{}, errors.New("invalid peer trust configuration")
	}
	policy.Roots = policy.Roots.Clone()
	revoked := make(map[string]bool, len(policy.RevokedSerials))
	for serial, value := range policy.RevokedSerials {
		revoked[serial] = value
	}
	policy.RevokedSerials = revoked
	return policy, nil
}

func exactIdentity(leaf *x509.Certificate, environment string, service Service) bool {
	want, err := IdentityURI(environment, service)
	return err == nil && leaf != nil && len(leaf.URIs) == 1 && leaf.URIs[0].String() == want.String()
}

func (policy PeerIdentity) verify(state tls.ConnectionState, usage x509.ExtKeyUsage, hostname string) error {
	// VerifyConnection runs before Finished has completed the handshake. HTTP
	// handlers separately require HandshakeComplete; this helper is also used
	// inside that hook after normal chain verification has already succeeded.
	if state.Version != tls.VersionTLS13 || len(state.PeerCertificates) == 0 || len(state.VerifiedChains) == 0 {
		return errPeerAuthentication
	}
	leaf := state.PeerCertificates[0]
	if !exactIdentity(leaf, policy.Environment, policy.Service) {
		return errPeerAuthentication
	}
	// Recheck against this endpoint's CA, usage, current validity and revocation
	// policy. An injected TLS state with unverified certificates is insufficient.
	intermediates := x509.NewCertPool()
	for _, certificate := range state.PeerCertificates[1:] {
		intermediates.AddCert(certificate)
	}
	chains, err := leaf.Verify(x509.VerifyOptions{Roots: policy.Roots, Intermediates: intermediates, KeyUsages: []x509.ExtKeyUsage{usage}, CurrentTime: time.Now(), DNSName: hostname})
	if err != nil {
		return errPeerAuthentication
	}
	matched := false
	for _, chain := range state.VerifiedChains {
		if len(chain) > 0 && bytes.Equal(chain[0].Raw, leaf.Raw) {
			matched = true
		}
	}
	if !matched {
		return errPeerAuthentication
	}
	for _, chain := range chains {
		for _, certificate := range chain {
			if policy.RevokedSerials[certificate.SerialNumber.Text(16)] {
				return errPeerAuthentication
			}
		}
	}
	return nil
}

func certificateIdentity(certificate tls.Certificate, environment string, service Service, usage x509.ExtKeyUsage) error {
	if len(certificate.Certificate) == 0 || certificate.PrivateKey == nil {
		return errPeerAuthentication
	}
	leaf, err := x509.ParseCertificate(certificate.Certificate[0])
	if err != nil || !exactIdentity(leaf, environment, service) || time.Now().Before(leaf.NotBefore) || !time.Now().Before(leaf.NotAfter) {
		return errPeerAuthentication
	}
	allowed := false
	for _, value := range leaf.ExtKeyUsage {
		if value == usage {
			allowed = true
		}
	}
	if !allowed {
		return errPeerAuthentication
	}
	signer, ok := certificate.PrivateKey.(crypto.Signer)
	if !ok {
		return errPeerAuthentication
	}
	actual, err := x509.MarshalPKIXPublicKey(signer.Public())
	if err != nil {
		return errPeerAuthentication
	}
	expected, err := x509.MarshalPKIXPublicKey(leaf.PublicKey)
	if err != nil || !bytes.Equal(actual, expected) {
		return errPeerAuthentication
	}
	return nil
}

func opposite(service Service) Service {
	if service == CommunityService {
		return VerifierService
	}
	return CommunityService
}

// InternalTLSConfig is for the separate internal listener. Client certificates
// must pass normal x509 verification before the exact workload identity check.
func InternalTLSConfig(serverCertificate tls.Certificate, peer PeerIdentity) (*tls.Config, error) {
	policy, err := copyIdentity(peer)
	if err != nil {
		return nil, err
	}
	if err = certificateIdentity(serverCertificate, peer.Environment, opposite(peer.Service), x509.ExtKeyUsageServerAuth); err != nil {
		return nil, err
	}
	return &tls.Config{
		MinVersion:       tls.VersionTLS13,
		MaxVersion:       tls.VersionTLS13,
		Certificates:     []tls.Certificate{serverCertificate},
		ClientAuth:       tls.RequireAndVerifyClientCert,
		ClientCAs:        policy.Roots,
		VerifyConnection: func(state tls.ConnectionState) error { return policy.verify(state, x509.ExtKeyUsageClientAuth, "") },
	}, nil
}

// PublicTLSConfig does not require a client certificate. Public OTP and signup
// consumers establish ordinary server-authenticated HTTPS instead of mTLS.
func PublicTLSConfig(serverCertificate tls.Certificate) (*tls.Config, error) {
	if len(serverCertificate.Certificate) == 0 || serverCertificate.PrivateKey == nil {
		return nil, errors.New("invalid HTTPS certificate")
	}
	return &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{serverCertificate}}, nil
}
