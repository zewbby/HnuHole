package authprivacyhttp

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type e2eMail struct {
	mu    sync.Mutex
	codes map[string]string
	calls int
	pool  *pgxpool.Pool
}

func (m *e2eMail) SendOTP(ctx context.Context, operation [32]byte, email, code string) (authprivacy.MailOutcome, error) {
	var state string
	if err := m.pool.QueryRow(ctx, `SELECT state FROM v_auth.mail_outbox WHERE operation_id=$1`, operation[:]).Scan(&state); err != nil || state != "DISPATCHING" {
		return authprivacy.MailUnknown, fmt.Errorf("external mail called before durable dispatch")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.calls++
	m.codes[email] = code
	return authprivacy.MailSent, nil
}

func (m *e2eMail) code(email string) (string, int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.codes[email], m.calls
}

type e2ePKI struct {
	root  *x509.Certificate
	key   ed25519.PrivateKey
	roots *x509.CertPool
}

func e2eNewPKI(t *testing.T) *e2ePKI {
	t.Helper()
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	root := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "isolated-test-only"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageCRLSign}
	der, err := x509.CreateCertificate(rand.Reader, root, root, public, private)
	if err != nil {
		t.Fatal(err)
	}
	root, err = x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(root)
	return &e2ePKI{root: root, key: private, roots: roots}
}

func (p *e2ePKI) cert(t *testing.T, environment string, service Service) tls.Certificate {
	t.Helper()
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	uri, err := IdentityURI(environment, service)
	if err != nil {
		t.Fatal(err)
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 120))
	if err != nil {
		t.Fatal(err)
	}
	leaf := &x509.Certificate{SerialNumber: serial, Subject: pkix.Name{CommonName: "not-used-as-identity"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, DNSNames: []string{"localhost"}, URIs: []*url.URL{uri}}
	der, err := x509.CreateCertificate(rand.Reader, leaf, p.root, public, p.key)
	if err != nil {
		t.Fatal(err)
	}
	return tls.Certificate{Certificate: [][]byte{der, p.root.Raw}, PrivateKey: private}
}

func e2ePool(t *testing.T, role string) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("AUTHLAB_" + strings.ToUpper(role) + "_DSN")
	if dsn == "" {
		t.Skip("real PostgreSQL lab DSNs absent; HTTPS/database integration not executed")
	}
	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal("invalid lab DSN")
	}
	tag := os.Getenv("AUTHLAB_RUNTIME_TAG")
	if os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(tag, "hnuhole_authlab_") || config.ConnConfig.RuntimeParams["application_name"] != tag {
		t.Fatal("refusing non-isolated database reset")
	}
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	var database, user string
	var super bool
	var address *string
	if err = pool.QueryRow(context.Background(), `SELECT current_database(),current_user,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),inet_server_addr()::text`).Scan(&database, &user, &super, &address); err != nil {
		t.Fatal(err)
	}
	if database != "hnuhole_"+role || user != "hnuhole_"+role || super || address != nil {
		t.Fatal("expected private-socket disposable database and non-superuser role")
	}
	dir, schema := "community", "c_auth"
	if role == "v" {
		dir, schema = "verifier", "v_auth"
	}
	files, err := filepath.Glob(filepath.Join("..", "..", "authlab", "migrations", dir, "*.sql"))
	if err != nil || len(files) == 0 {
		t.Fatal("missing migrations")
	}
	tx, err := pool.Begin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	if _, err = tx.Exec(context.Background(), `DROP SCHEMA IF EXISTS `+schema+` CASCADE`); err != nil {
		t.Fatal(err)
	}
	for _, file := range files {
		sql, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = tx.Exec(context.Background(), string(sql)); err != nil {
			t.Fatalf("migration %s: %v", filepath.Base(file), err)
		}
	}
	if err = tx.Commit(context.Background()); err != nil {
		t.Fatal(err)
	}
	return pool
}

func e2eKey(t *testing.T) (result [32]byte) {
	t.Helper()
	if _, err := rand.Read(result[:]); err != nil {
		t.Fatal(err)
	}
	return result
}

func e2eInstallation(t *testing.T) (result [16]byte) {
	t.Helper()
	if _, err := rand.Read(result[:]); err != nil {
		t.Fatal(err)
	}
	return result
}

func e2eServer(t *testing.T, handler http.Handler, config *tls.Config) *httptest.Server {
	t.Helper()
	server := httptest.NewUnstartedServer(handler)
	server.TLS = config
	server.StartTLS()
	t.Cleanup(server.Close)
	return server
}

func e2eJSON(t *testing.T, client *http.Client, method, endpoint string, body any, headers map[string]string, status int) map[string]any {
	t.Helper()
	var input io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		input = bytes.NewReader(encoded)
	}
	request, err := http.NewRequest(method, endpoint, input)
	if err != nil {
		t.Fatal(err)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	for k, v := range headers {
		request.Header.Set(k, v)
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 8192))
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != status {
		t.Fatalf("%s: expected %d got %d: %s", request.URL.Path, status, response.StatusCode, data)
	}
	if response.Header.Get("Cache-Control") != "no-store" {
		t.Fatal("capability response can be cached")
	}
	var result map[string]any
	if err = json.Unmarshal(data, &result); err != nil {
		t.Fatal(err)
	}
	return result
}

// The real PostgreSQL/HTTPS flows are below; all addresses, keys and passwords
// are synthetic. No real mailbox, credential service or deployed API is used.

type e2eServices struct {
	c                *authprivacy.Community
	v                *authprivacy.VerifierStore
	eligibility      *authprivacy.Eligibility
	cp, vp           *pgxpool.Pool
	mail             *e2eMail
	cSigner          authprivacy.Signer
	enableCSigning   func()
	cPublic, vPublic *httptest.Server
	toV              *PeerClient
	toC              *PeerClient
	client           *http.Client
}

func e2eNewServices(t *testing.T) *e2eServices {
	t.Helper()
	s := &e2eServices{cp: e2ePool(t, "c"), vp: e2ePool(t, "v")}
	var trusted []protocol.TrustedKey
	var vPrivate, cPrivate ed25519.PrivateKey
	for _, scope := range []struct {
		purposes []protocol.Purpose
		target   *ed25519.PrivateKey
	}{
		{[]protocol.Purpose{protocol.PurposeRegister, protocol.PurposeRetireAuth}, &vPrivate},
		{[]protocol.Purpose{protocol.PurposeRetired, protocol.PurposeReleased}, &cPrivate},
	} {
		public, private, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		*scope.target = private
		var key protocol.PublicKey
		copy(key[:], public)
		for _, purpose := range scope.purposes {
			trusted = append(trusted, protocol.TrustedKey{Environment: "lab", Purpose: purpose, Epoch: 1, PublicKey: key})
		}
	}
	verifier, err := protocol.NewVerifier("lab", trusted)
	if err != nil {
		t.Fatal(err)
	}
	s.cSigner = func(_ context.Context, _ uint32, message []byte) ([]byte, error) {
		return ed25519.Sign(cPrivate, message), nil
	}
	var cSigningEnabled atomic.Bool
	s.enableCSigning = func() { cSigningEnabled.Store(true) }
	s.c, err = authprivacy.NewCommunityWithReceiptSigner(s.cp, verifier, 1, e2eKey(t), func(ctx context.Context, epoch uint32, message []byte) ([]byte, error) {
		if !cSigningEnabled.Load() {
			return nil, fmt.Errorf("synthetic signer temporarily unavailable")
		}
		return s.cSigner(ctx, epoch, message)
	})
	if err != nil {
		t.Fatal(err)
	}
	s.v, err = authprivacy.NewVerifierStore(s.vp, verifier, e2eKey(t))
	if err != nil {
		t.Fatal(err)
	}
	pki := e2eNewPKI(t)
	cCert, vCert := pki.cert(t, "lab", CommunityService), pki.cert(t, "lab", VerifierService)
	passwords, err := authprivacy.NewPasswordPreparer(1, []string{"PasswordPassword123!"})
	if err != nil {
		t.Fatal(err)
	}
	limits := func() NetworkLimits {
		return NetworkLimits{Key: e2eKey(t), MutationCapacity: 10000, QueryCapacity: 10000, Window: time.Minute, MaxEntries: 1024}
	}
	cPeer := PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}
	cEndpoints, err := NewCommunityEndpoints(CommunityOptions{Backend: s.c, Passwords: passwords, InternalPeer: cPeer, AllowedOrigins: []string{"https://app.invalid"}, Limits: limits()})
	if err != nil {
		t.Fatal(err)
	}
	cTLS, err := InternalTLSConfig(cCert, cPeer)
	if err != nil {
		t.Fatal(err)
	}
	cInternal := e2eServer(t, cEndpoints.Internal, cTLS)
	toC, err := NewPeerClient(PeerClientOptions{Origin: cInternal.URL, Environment: "lab", LocalService: VerifierService, PeerService: CommunityService, ClientCertificate: vCert, Roots: pki.roots, Timeout: 2 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(toC.CloseIdleConnections)
	s.toC = toC
	s.mail = &e2eMail{codes: make(map[string]string), pool: s.vp}
	vSigner := func(ctx context.Context, _ uint32, message []byte) ([]byte, error) {
		if bytes.HasPrefix(message, []byte("HNUHOLE/REGISTER/V2\x00")) {
			var committed bool
			if err := s.vp.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM v_auth.confirmation_sign_jobs WHERE reg_message=$1)`, message).Scan(&committed); err != nil || !committed {
				return nil, fmt.Errorf("signer called before durable registration job")
			}
		}
		return ed25519.Sign(vPrivate, message), nil
	}
	config := authprivacy.EligibilityConfig{OTPKey: e2eKey(t), OTPKeyVersion: 1, MailEncryptionKey: e2eKey(t), MailEncryptionKeyVersion: 1, RequestHMACKey: e2eKey(t), HMACKeyVersion: 1, LimitKey: e2eKey(t), RegistrationEpoch: 1, SendBudget: 20, VerifyBudget: 50}
	s.eligibility, err = authprivacy.NewEligibility(s.v, config, vSigner, s.mail, toC)
	if err != nil {
		t.Fatal(err)
	}
	vPeer := PeerIdentity{Environment: "lab", Service: CommunityService, Roots: pki.roots}
	vEndpoints, err := NewVerifierEndpoints(VerifierOptions{Eligibility: s.eligibility, Receipts: s.v, InternalPeer: vPeer, AllowedOrigins: []string{"https://app.invalid"}, Limits: limits()})
	if err != nil {
		t.Fatal(err)
	}
	vTLS, err := InternalTLSConfig(vCert, vPeer)
	if err != nil {
		t.Fatal(err)
	}
	vInternal := e2eServer(t, vEndpoints.Internal, vTLS)
	s.toV, err = NewPeerClient(PeerClientOptions{Origin: vInternal.URL, Environment: "lab", LocalService: CommunityService, PeerService: VerifierService, ClientCertificate: cCert, Roots: pki.roots, Timeout: 2 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.toV.CloseIdleConnections)
	cPublicTLS, err := PublicTLSConfig(cCert)
	if err != nil {
		t.Fatal(err)
	}
	vPublicTLS, err := PublicTLSConfig(vCert)
	if err != nil {
		t.Fatal(err)
	}
	s.cPublic, s.vPublic = e2eServer(t, cEndpoints.Public, cPublicTLS), e2eServer(t, vEndpoints.Public, vPublicTLS)
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pki.roots, MinVersion: tls.VersionTLS13}, Proxy: nil}
	s.client = &http.Client{Transport: transport, Timeout: 5 * time.Second}
	t.Cleanup(transport.CloseIdleConnections)
	return s
}

type e2eConfirmation struct {
	headers      map[string]string
	body         map[string]string
	key          [32]byte
	flow         string
	installation [16]byte
	bootstrap    ed25519.PrivateKey
	slot         protocol.SlotID
}

func (s *e2eServices) confirmation(t *testing.T, email string) e2eConfirmation {
	t.Helper()
	installation, key := e2eInstallation(t), e2eKey(t)
	headers := map[string]string{"V-Installation-ID": protocol.EncodeCanonicalBase64url(installation[:]), "Idempotency-Key": protocol.EncodeCanonicalBase64url(key[:])}
	requested := e2eJSON(t, s.client, http.MethodPost, s.vPublic.URL+"/api/v1/eligibility/otp-requests", map[string]string{"email": email}, headers, http.StatusAccepted)
	flow, ok := requested["flowId"].(string)
	if !ok {
		t.Fatal("request lost flow binding")
	}
	code, count := s.mail.code(email)
	if len(code) != 6 {
		t.Fatal("durable mail was not dispatched")
	}
	e2eJSON(t, s.client, http.MethodPost, s.vPublic.URL+"/api/v1/eligibility/otp-requests", map[string]string{"email": email}, headers, http.StatusAccepted)
	_, after := s.mail.code(email)
	if count != after {
		t.Fatal("same request resent mail")
	}
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	var pk protocol.PublicKey
	copy(pk[:], public)
	slot, err := protocol.DeriveSlot(pk)
	if err != nil {
		t.Fatal(err)
	}
	confirmationKey := e2eKey(t)
	body := map[string]string{"flowId": flow, "otp": code, "slotId": protocol.EncodeCanonicalBase64url(slot[:]), "bootstrapPublicKey": protocol.EncodeCanonicalBase64url(pk[:])}
	return e2eConfirmation{headers: map[string]string{"V-Installation-ID": headers["V-Installation-ID"], "Idempotency-Key": protocol.EncodeCanonicalBase64url(confirmationKey[:])}, body: body, key: confirmationKey, flow: flow, installation: installation, bootstrap: private, slot: slot}
}

func (s *e2eServices) submit(t *testing.T, confirmation e2eConfirmation, status int) map[string]any {
	t.Helper()
	return e2eJSON(t, s.client, http.MethodPost, s.vPublic.URL+"/api/v1/eligibility/otp-confirmations", confirmation.body, confirmation.headers, status)
}

func TestHTTPSPostgresEligibilityAndSignup(t *testing.T) {
	s := e2eNewServices(t)
	confirmation := s.confirmation(t, "synthetic-signup@hainanu.edu.cn")
	confirmed := s.submit(t, confirmation, http.StatusOK)
	encoded, ok := confirmed["registrationTicket"].(string)
	if !ok {
		t.Fatal("confirmation did not return ticket")
	}
	replay := s.submit(t, confirmation, http.StatusOK)
	if replay["registrationTicket"] != encoded {
		t.Fatal("same request changed original ticket")
	}
	queryHeaders := map[string]string{"V-Installation-ID": confirmation.headers["V-Installation-ID"], "OTP-Flow-ID": confirmation.flow, "Authorization": "OtpConfirmationResult " + confirmation.headers["Idempotency-Key"]}
	result := e2eJSON(t, s.client, http.MethodGet, s.vPublic.URL+"/api/v1/eligibility/otp-confirmation-result", nil, queryHeaders, http.StatusOK)
	if len(result) != 1 || result["state"] != "TICKET_AVAILABLE" {
		t.Fatal("confirmation result leaked ticket or identity")
	}
	installation := e2eInstallation(t)
	intent := e2eJSON(t, s.client, http.MethodPost, s.cPublic.URL+"/api/v1/auth/registration-intents", map[string]string{"registrationTicket": encoded, "username": "synthetic_user", "password": "a separate long community password", "installationId": protocol.EncodeCanonicalBase64url(installation[:])}, nil, http.StatusCreated)
	ticket, err := protocol.ParseRegistrationTicket(encoded)
	if err != nil {
		t.Fatal(err)
	}
	intentID, err := protocol.DecodeCanonicalBase64url(intent["intentId"].(string), 32)
	if err != nil {
		t.Fatal(err)
	}
	challengeBytes, err := protocol.DecodeCanonicalBase64url(intent["challenge"].(string), 32)
	if err != nil {
		t.Fatal(err)
	}
	var id protocol.IntentID
	var challenge protocol.Challenge
	copy(id[:], intentID)
	copy(challenge[:], challengeBytes)
	message := protocol.BootstrapMessageBytes(ticket, id, challenge)
	proof := protocol.EncodeCanonicalBase64url(ed25519.Sign(confirmation.bootstrap, message[:]))
	key := e2eKey(t)
	body := map[string]string{"intentId": intent["intentId"].(string), "bootstrapSignature": proof, "recoveryCodeConfirmation": intent["recoveryCode"].(string)}
	headers := map[string]string{"Idempotency-Key": protocol.EncodeCanonicalBase64url(key[:])}
	created := e2eJSON(t, s.client, http.MethodPost, s.cPublic.URL+"/api/v1/auth/registrations", body, headers, http.StatusCreated)
	if len(created) != 3 || created["accountId"] == nil || created["sessionToken"] == nil || created["expiresAt"] == nil {
		t.Fatal("signup response missing contract fields")
	}
	retried := e2eJSON(t, s.client, http.MethodPost, s.cPublic.URL+"/api/v1/auth/registrations", body, headers, http.StatusConflict)
	if retried["sessionToken"] != nil || retried["accountId"] != nil {
		t.Fatal("replayed signup regained authority")
	}
	var accounts, sessions int
	if err := s.cp.QueryRow(context.Background(), `SELECT (SELECT count(*) FROM c_auth.accounts),(SELECT count(*) FROM c_auth.sessions)`).Scan(&accounts, &sessions); err != nil || accounts != 1 || sessions != 1 {
		t.Fatalf("HTTP replay duplicated transaction: %v", err)
	}
}

func TestHTTPSPostgresRetirementPushAndOriginalContinuation(t *testing.T) {
	s := e2eNewServices(t)
	email := "synthetic-retirement@hainanu.edu.cn"
	old := s.confirmation(t, email)
	s.submit(t, old, http.StatusOK)
	// Move only the synthetic send-wait fixture; immutable OTP lifetime and the
	// database decision clock remain unchanged. Avoid a real 60-second sleep.
	if _, err := s.vp.Exec(context.Background(), `UPDATE v_auth.otp_email_state SET send_wait_until=clock_timestamp()-interval '1 second' WHERE email_exact=$1`, []byte(email)); err != nil {
		t.Fatal(err)
	}
	next := s.confirmation(t, email)
	pending := s.submit(t, next, http.StatusAccepted)
	if pending["state"] != "RETIREMENT_PENDING" {
		t.Fatal("retirement was not durably pending")
	}
	var originalBucket int64
	if err := s.vp.QueryRow(context.Background(), `SELECT admission_window FROM v_auth.otp_confirmations WHERE new_slot=$1`, next.slot[:]).Scan(&originalBucket); err != nil {
		t.Fatal(err)
	}
	var authorizationBytes []byte
	if err := s.vp.QueryRow(context.Background(), `SELECT retirement_authorization FROM v_auth.retire_pending WHERE old_slot=$1`, old.slot[:]).Scan(&authorizationBytes); err != nil {
		t.Fatal(err)
	}
	s.enableCSigning()
	if ready, err := s.c.SignReceipt(context.Background(), old.slot, s.cSigner); err != nil || !ready {
		t.Fatalf("C durable receipt not ready: %v", err)
	}
	var oldMessage, oldSignature []byte
	if err := s.cp.QueryRow(context.Background(), `SELECT receipt_message,signature FROM c_auth.receipt_outbox WHERE slot_id=$1`, old.slot[:]).Scan(&oldMessage, &oldSignature); err != nil {
		t.Fatal(err)
	}
	oldReceipt := protocol.EncodeCanonicalBase64url(append(append([]byte{}, oldMessage...), oldSignature...))
	// Push wins the race and deletes the temporary retirement row. The original
	// confirmation must still contain everything needed for safe continuation.
	if err := s.c.DeliverReceipt(context.Background(), old.slot, s.toV.ReceiveReceipt); err != nil {
		t.Fatal(err)
	}
	var temporary int
	if err := s.vp.QueryRow(context.Background(), `SELECT count(*) FROM v_auth.retire_pending`).Scan(&temporary); err != nil || temporary != 0 {
		t.Fatalf("push did not commit retirement: %v", err)
	}
	confirmed := s.submit(t, next, http.StatusOK)
	ticket, err := protocol.ParseRegistrationTicket(confirmed["registrationTicket"].(string))
	if err != nil || ticket.Slot != next.slot || int64(ticket.Window) != originalBucket {
		t.Fatalf("continuation changed original binding/bucket: %v", err)
	}
	s.submit(t, next, http.StatusOK)
	if err := s.toV.ReceiveReceipt(context.Background(), oldReceipt, protocol.PurposeRetired); err != nil {
		t.Fatal(err)
	}
	var current []byte
	if err := s.vp.QueryRow(context.Background(), `SELECT current_slot FROM v_auth.email_quota WHERE email_exact=$1`, []byte(email)).Scan(&current); err != nil || !bytes.Equal(current, next.slot[:]) {
		t.Fatalf("duplicate old receipt cleared new reservation: %v", err)
	}
	var consumed int
	if err := s.vp.QueryRow(context.Background(), `SELECT count(*) FROM v_auth.otp_flows WHERE state='CONSUMED'`).Scan(&consumed); err != nil || consumed != 2 {
		t.Fatalf("continuation consumed OTP again: %v", err)
	}
	var acked bool
	if err := s.cp.QueryRow(context.Background(), `SELECT receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=$1`, old.slot[:]).Scan(&acked); err != nil || !acked {
		t.Fatalf("mTLS receipt was not durably ACKed: %v", err)
	}
	if removed, err := s.c.CleanupAcknowledged(context.Background(), time.Now().Add(time.Minute)); err != nil || removed != 1 {
		t.Fatalf("ACKed delivery cleanup: %v", err)
	}
	reply, err := s.toC.RetireUnusedSlot(context.Background(), protocol.EncodeCanonicalBase64url(authorizationBytes))
	if err != nil || reply.Pending || reply.Receipt == "" {
		t.Fatalf("post-ACK read-only HTTPS re-sign unavailable: %v", err)
	}
	var recreated int
	if err := s.cp.QueryRow(context.Background(), `SELECT count(*) FROM c_auth.receipt_outbox`).Scan(&recreated); err != nil || recreated != 0 {
		t.Fatalf("read-only re-sign resurrected outbox: %v", err)
	}
}
