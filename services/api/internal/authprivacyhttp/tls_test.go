package authprivacyhttp

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

type httpTestPKI struct {
	root    *x509.Certificate
	private ed25519.PrivateKey
	roots   *x509.CertPool
	serial  int64
}

func newHTTPTestPKI(t *testing.T) *httpTestPKI {
	t.Helper()
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "disposable test CA"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(24 * time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageCRLSign}
	raw, err := x509.CreateCertificate(rand.Reader, template, template, public, private)
	if err != nil {
		t.Fatal(err)
	}
	root, err := x509.ParseCertificate(raw)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(root)
	return &httpTestPKI{root: root, private: private, roots: roots, serial: 2}
}

func (pki *httpTestPKI) issue(t *testing.T, environment string, service Service, modify func(*x509.Certificate)) tls.Certificate {
	t.Helper()
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	identity, err := IdentityURI(environment, service)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(pki.serial), Subject: pkix.Name{CommonName: string(service)}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth, x509.ExtKeyUsageServerAuth}, URIs: []*url.URL{identity}, DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}}
	pki.serial++
	if modify != nil {
		modify(template)
	}
	raw, err := x509.CreateCertificate(rand.Reader, template, pki.root, public, pki.private)
	if err != nil {
		t.Fatal(err)
	}
	leaf, err := x509.ParseCertificate(raw)
	if err != nil {
		t.Fatal(err)
	}
	return tls.Certificate{Certificate: [][]byte{raw, pki.root.Raw}, PrivateKey: private, Leaf: leaf}
}

func startHTTPTestTLS(t *testing.T, handler http.Handler, config *tls.Config) *httptest.Server {
	t.Helper()
	server := httptest.NewUnstartedServer(handler)
	server.Config.ErrorLog = log.New(io.Discard, "", 0)
	server.Config.ReadHeaderTimeout = 2 * time.Second
	server.Config.ReadTimeout = 5 * time.Second
	server.TLS = config
	server.StartTLS()
	t.Cleanup(server.Close)
	return server
}

func httpTestClient(roots *x509.CertPool, certificate *tls.Certificate) *http.Client {
	config := &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS13}
	if certificate != nil {
		config.Certificates = []tls.Certificate{*certificate}
	}
	return &http.Client{Transport: &http.Transport{TLSClientConfig: config, Proxy: nil}, Timeout: 5 * time.Second}
}

func TestMTLSRequiresActualVerifiedCertificateAndExactEnvironmentIdentity(t *testing.T) {
	pki := newHTTPTestPKI(t)
	serverCertificate := pki.issue(t, "lab", VerifierService, nil)
	clientCertificate := pki.issue(t, "lab", CommunityService, nil)
	policy := PeerIdentity{Environment: "lab", Service: CommunityService, Roots: pki.roots}
	config, err := InternalTLSConfig(serverCertificate, policy)
	if err != nil {
		t.Fatal(err)
	}
	server := startHTTPTestTLS(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.TLS == nil || policy.verify(*r.TLS, x509.ExtKeyUsageClientAuth, "") != nil {
			http.Error(w, "denied", 401)
			return
		}
		w.WriteHeader(204)
	}), config)
	client := httpTestClient(pki.roots, &clientCertificate)
	response, err := client.Get(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 204 {
		t.Fatal(response.Status)
	}
	wrongEnvironment := pki.issue(t, "staging", CommunityService, nil)
	wrongService := pki.issue(t, "lab", VerifierService, nil)
	cnOnly := pki.issue(t, "lab", CommunityService, func(c *x509.Certificate) { c.URIs = nil })
	otherCA := newHTTPTestPKI(t)
	wrongCA := otherCA.issue(t, "lab", CommunityService, nil)
	for _, certificate := range []*tls.Certificate{nil, &wrongEnvironment, &wrongService, &cnOnly, &wrongCA} {
		client := httpTestClient(pki.roots, certificate)
		if response, err := client.Get(server.URL); err == nil {
			response.Body.Close()
			t.Fatal("accepted missing/wrong environment/role/CA/CN-only certificate")
		}
	}
	state := tls.ConnectionState{HandshakeComplete: true, Version: tls.VersionTLS13, PeerCertificates: []*x509.Certificate{clientCertificate.Leaf}}
	if policy.verify(state, x509.ExtKeyUsageClientAuth, "") == nil {
		t.Fatal("accepted injected unverified TLS state")
	}
	state.VerifiedChains = [][]*x509.Certificate{{clientCertificate.Leaf, pki.root}}
	state.Version = tls.VersionTLS12
	if policy.verify(state, x509.ExtKeyUsageClientAuth, "") == nil {
		t.Fatal("accepted old TLS version")
	}
}

func TestMTLSRevocationAndClientConfigurationFailClosed(t *testing.T) {
	pki := newHTTPTestPKI(t)
	serverCertificate := pki.issue(t, "lab", VerifierService, nil)
	clientCertificate := pki.issue(t, "lab", CommunityService, nil)
	policy := PeerIdentity{Environment: "lab", Service: CommunityService, Roots: pki.roots, RevokedSerials: map[string]bool{clientCertificate.Leaf.SerialNumber.Text(16): true}}
	config, err := InternalTLSConfig(serverCertificate, policy)
	if err != nil {
		t.Fatal(err)
	}
	server := startHTTPTestTLS(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }), config)
	if response, err := httpTestClient(pki.roots, &clientCertificate).Get(server.URL); err == nil {
		response.Body.Close()
		t.Fatal("accepted revoked peer")
	}
	wrongEnvironment := pki.issue(t, "staging", CommunityService, nil)
	options := PeerClientOptions{Origin: server.URL, Environment: "lab", LocalService: CommunityService, PeerService: VerifierService, ClientCertificate: wrongEnvironment, Roots: pki.roots}
	if _, err := NewPeerClient(options); err == nil {
		t.Fatal("allowed wrong-environment client identity")
	}
	options.ClientCertificate = clientCertificate
	for _, origin := range []string{"http://localhost", "https://name/path", "https://name/?query=1", "https://user:secret@name", "https://name/#fragment"} {
		options.Origin = origin
		if _, err := NewPeerClient(options); err == nil {
			t.Fatalf("allowed origin %s", origin)
		}
	}
}

func TestPublicHTTPSRequiresNoClientCertificate(t *testing.T) {
	pki := newHTTPTestPKI(t)
	certificate := pki.issue(t, "lab", VerifierService, nil)
	config, err := PublicTLSConfig(certificate)
	if err != nil {
		t.Fatal(err)
	}
	server := startHTTPTestTLS(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if len(r.TLS.PeerCertificates) != 0 {
			t.Error("unexpected mTLS client")
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		_, _ = w.Write([]byte("ok"))
	}), config)
	response, err := httpTestClient(pki.roots, nil).Get(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	data, _ := io.ReadAll(response.Body)
	if strings.TrimSpace(string(data)) != "ok" {
		t.Fatal(string(data))
	}
}
