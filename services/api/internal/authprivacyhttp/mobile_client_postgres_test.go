package authprivacyhttp

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

// TestMobileClientHTTPSPostgres is opt-in because it starts a Flutter subprocess.
// Its public C/V handlers, protocol, password processor, Gate, and databases are
// the same real boundaries used by the Go HTTPS/PostgreSQL integration tests.
// The private control server and trust root never appear in shipped mobile code.
func TestMobileClientHTTPSPostgres(t *testing.T) {
	flutter := os.Getenv("AUTHLAB_MOBILE_FLUTTER")
	if flutter == "" {
		t.Skip("mobile HTTPS/PostgreSQL runner not requested")
	}
	s := e2eNewServices(t)
	s.enableCSigning()
	// Dart's TLS ClientHello does not advertise Ed25519 certificates. Use a
	// standard ECDSA TLS chain, retaining TLS 1.3 and full hostname validation.
	// This leaves Ed25519 authorization artifacts and internal mTLS unchanged.
	publicTLS, err := PublicTLSConfig(mobileLabCertificate(t))
	if err != nil {
		t.Fatal(err)
	}
	s.cPublic = e2eServer(t, s.cPublic.Config.Handler, publicTLS)
	s.vPublic = e2eServer(t, s.vPublic.Config.Handler, publicTLS)
	var faultsMu sync.Mutex
	drops := make(map[string]bool)
	for _, server := range []*httptest.Server{s.cPublic, s.vPublic} {
		original := server.Config.Handler
		server.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			recorder := httptest.NewRecorder()
			original.ServeHTTP(recorder, r)
			faultsMu.Lock()
			drop := r.Method == http.MethodPost && drops[r.URL.Path]
			if drop {
				delete(drops, r.URL.Path)
			}
			faultsMu.Unlock()
			if drop {
				// The operation already finished through the real handler. Only its
				// response is lost, so reconciliation tests a committed unknown result.
				conn, _, err := w.(http.Hijacker).Hijack()
				if err != nil {
					t.Error("could not inject lost response")
					return
				}
				_ = conn.Close()
				return
			}
			for name, values := range recorder.Header() {
				w.Header()[name] = values
			}
			w.WriteHeader(recorder.Code)
			_, _ = w.Write(recorder.Body.Bytes())
		})
	}
	var controlToken [32]byte
	if _, err := rand.Read(controlToken[:]); err != nil {
		t.Fatal(err)
	}
	encodedToken := base64.RawURLEncoding.EncodeToString(controlToken[:])
	control := e2eServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if r.Header.Get("Authorization") != "LabControl "+encodedToken {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		var body map[string]string
		if err := json.NewDecoder(io.LimitReader(r.Body, 2048)).Decode(&body); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		var result any = map[string]bool{"ok": true}
		var err error
		switch r.URL.Path {
		case "/otp":
			code, calls := s.mail.code(body["email"])
			if code == "" {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			result = map[string]any{"code": code, "mailCalls": calls}
		case "/drop-next":
			allowed := map[string]bool{
				"/api/v1/auth/password-resets":     true,
				"/api/v1/account-closures":         true,
				"/api/v1/auth/session-revocations": true,
				"/api/v1/eligibility/otp-requests": true,
			}
			if !allowed[body["path"]] {
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			faultsMu.Lock()
			drops[body["path"]] = true
			faultsMu.Unlock()
		case "/freeze":
			err = s.gate.Freeze(r.Context(), "isolated mobile transport fault test")
		case "/recover":
			err = s.recoverC()
		case "/finalize":
			// This changes the signed trusted-clock fixture, never SQL deadlines.
			s.advanceC(7*24*time.Hour + time.Second)
			var count int64
			count, err = s.c.FinalizeDueClosures(r.Context(), 10)
			if err == nil && count != 1 {
				t.Error("expected exactly one due closure")
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
		case "/deliver-release":
			var raw []byte
			raw, err = protocol.DecodeCanonicalBase64url(body["slotId"], 32)
			if err == nil {
				var slot protocol.SlotID
				copy(slot[:], raw)
				var ready bool
				ready, err = s.c.SignReceipt(r.Context(), slot, s.cSigner)
				if err == nil && !ready {
					w.WriteHeader(http.StatusInternalServerError)
					return
				}
				if err == nil {
					err = s.c.DeliverReceipt(r.Context(), slot, s.toV.ReceiveReceipt)
				}
			}
		default:
			w.WriteHeader(http.StatusNotFound)
			return
		}
		if err != nil {
			t.Errorf("private fixture control %s failed: %v", r.URL.Path, err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(result)
	}), s.cPublic.TLS)
	dir := t.TempDir()
	root := s.cPublic.TLS.Certificates[0].Certificate[1]
	caPath := filepath.Join(dir, "test-ca.pem")
	if err := os.WriteFile(caPath, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: root}), 0600); err != nil {
		t.Fatal(err)
	}
	config, err := json.Marshal(map[string]string{
		"communityOrigin": s.cPublic.URL, "verifierOrigin": s.vPublic.URL,
		"controlOrigin": control.URL, "controlToken": encodedToken, "caPath": caPath,
	})
	if err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(dir, "mobile-fixture.json")
	if err := os.WriteFile(configPath, config, 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, flutter, "test", "--no-pub", "--reporter", "expanded", "integration/auth_public_https_postgres_test.dart")
	cmd.Dir = filepath.Join("..", "..", "..", "..", "apps", "mobile")
	cmd.Env = append(os.Environ(), "AUTHLAB_MOBILE_CONFIG="+configPath)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("mobile HTTPS/PostgreSQL integration failed: %v", err)
	}
}

func mobileLabCertificate(t *testing.T) tls.Certificate {
	t.Helper()
	rootKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	root := &x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "isolated-mobile-test-only"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour), IsCA: true,
		BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
	}
	rootDER, err := x509.CreateCertificate(rand.Reader, root, root, &rootKey.PublicKey, rootKey)
	if err != nil {
		t.Fatal(err)
	}
	leafKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	leaf := &x509.Certificate{
		SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "localhost"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour),
		KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, DNSNames: []string{"localhost"},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leaf, root, &leafKey.PublicKey, rootKey)
	if err != nil {
		t.Fatal(err)
	}
	return tls.Certificate{Certificate: [][]byte{leafDER, rootDER}, PrivateKey: leafKey}
}
