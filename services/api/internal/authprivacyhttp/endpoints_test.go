package authprivacyhttp

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/base32"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type httpTestEligibility struct {
	mu                                                                  sync.Mutex
	requestCalls, queryCalls, confirmationCalls, confirmationQueryCalls int
	lastRequest                                                         authprivacy.OTPRequest
	lastConfirmation                                                    authprivacy.ConfirmOTPRequest
	requestResult                                                       authprivacy.OTPRequestResult
	queryResult                                                         authprivacy.OTPRequestResult
	confirmationResult                                                  authprivacy.ConfirmationResult
	requestError                                                        error
}

func (f *httpTestEligibility) RequestOTP(_ context.Context, request authprivacy.OTPRequest) (authprivacy.OTPRequestResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.requestCalls++
	f.lastRequest = request
	return f.requestResult, f.requestError
}
func (f *httpTestEligibility) GetOTPRequestResult(context.Context, [32]byte, [16]byte) (authprivacy.OTPRequestResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.queryCalls++
	return f.queryResult, nil
}
func (f *httpTestEligibility) ConfirmOTP(_ context.Context, request authprivacy.ConfirmOTPRequest) (authprivacy.ConfirmationResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.confirmationCalls++
	f.lastConfirmation = request
	return f.confirmationResult, nil
}
func (f *httpTestEligibility) GetOTPConfirmationResult(context.Context, [32]byte, [32]byte, [16]byte) (authprivacy.ConfirmationResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.confirmationQueryCalls++
	return f.confirmationResult, nil
}

type httpTestReceipts struct {
	mu      sync.Mutex
	calls   int
	encoded string
	purpose protocol.Purpose
	err     error
}

func (f *httpTestReceipts) ProcessReceipt(_ context.Context, encoded string, purpose protocol.Purpose) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.encoded = encoded
	f.purpose = purpose
	return f.err
}

type httpTestCommunity struct {
	mu            sync.Mutex
	events        []string
	validateError error
	intent        authprivacy.SignupIntent
	result        authprivacy.SignupResult
	retirement    authprivacy.RetirementReply
	retireCalls   int
	commitError   error
}

func (f *httpTestCommunity) ValidateSignupTicket(context.Context, string) (authprivacy.AuthorizationDecision, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.events = append(f.events, "validate")
	return authprivacy.AuthorizationDecision{TrustedAt: time.Now(), Generation: 1}, f.validateError
}
func (f *httpTestCommunity) CreateSignupIntent(context.Context, string, string, authprivacy.PasswordMaterial, [16]byte, uint64) (authprivacy.SignupIntent, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.events = append(f.events, "intent")
	return f.intent, nil
}
func (f *httpTestCommunity) CommitSignup(context.Context, authprivacy.SignupRequest) (authprivacy.SignupResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.events = append(f.events, "commit")
	return f.result, f.commitError
}
func (f *httpTestCommunity) RetireUnusedSlot(context.Context, string) (authprivacy.RetirementReply, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.retireCalls++
	return f.retirement, nil
}

type httpTestPasswords struct {
	backend *httpTestCommunity
	err     error
}

func (f httpTestPasswords) PreparePassword(context.Context, string, string) (authprivacy.PasswordMaterial, error) {
	f.backend.mu.Lock()
	defer f.backend.mu.Unlock()
	f.backend.events = append(f.backend.events, "password")
	return authprivacy.PasswordMaterial{Hash: [32]byte{2}, Salt: [16]byte{3}, ParametersVersion: 1}, f.err
}

func (f httpTestPasswords) VerifyPassword(context.Context, string, authprivacy.PasswordMaterial) (bool, error) {
	return false, f.err
}

func httpTestLimits() NetworkLimits {
	return NetworkLimits{Key: [32]byte{99}, MutationCapacity: 10000, QueryCapacity: 10000, Window: time.Minute, MaxEntries: 100}
}
func httpTestEncoding(size int, value byte) string {
	return protocol.EncodeCanonicalBase64url(bytes.Repeat([]byte{value}, size))
}
func httpTestCode() string {
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(bytes.Repeat([]byte{4}, 16))
}

func newHTTPTestVerifier(t *testing.T, limits NetworkLimits) (*httpTestEligibility, *httpTestReceipts, *Endpoints, *httpTestPKI) {
	t.Helper()
	pki := newHTTPTestPKI(t)
	backend := &httpTestEligibility{requestResult: authprivacy.OTPRequestResult{State: "ACCEPTED", FlowID: [32]byte{1}, RetryAfterSeconds: 60}, queryResult: authprivacy.OTPRequestResult{State: "PENDING", PollAfterSeconds: 2}}
	receipts := &httpTestReceipts{}
	endpoints, err := NewVerifierEndpoints(VerifierOptions{Eligibility: backend, Receipts: receipts, InternalPeer: PeerIdentity{Environment: "lab", Service: CommunityService, Roots: pki.roots}, Limits: limits})
	if err != nil {
		t.Fatal(err)
	}
	return backend, receipts, endpoints, pki
}

func newHTTPTestCommunity(t *testing.T) (*httpTestCommunity, *Endpoints, *httpTestPKI) {
	t.Helper()
	pki := newHTTPTestPKI(t)
	backend := &httpTestCommunity{intent: authprivacy.SignupIntent{ID: protocol.IntentID{1}, Challenge: protocol.Challenge{2}, ExpiresAt: time.Now().Add(10 * time.Minute), RecoveryCode: httpTestCode()}, result: authprivacy.SignupResult{Created: true, AccountID: uuid.New(), ExpiresAt: time.Now().Add(30 * 24 * time.Hour), SessionToken: [32]byte{3}, RevokeSecret: [32]byte{4}}}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{Backend: backend, Passwords: httpTestPasswords{backend: backend}, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: httpTestLimits()})
	if err != nil {
		t.Fatal(err)
	}
	return backend, endpoints, pki
}

func httpTestPublicServer(t *testing.T, handler http.Handler, pki *httpTestPKI, service Service) (*httptest.Server, *http.Client) {
	t.Helper()
	certificate := pki.issue(t, "lab", service, nil)
	config, err := PublicTLSConfig(certificate)
	if err != nil {
		t.Fatal(err)
	}
	return startHTTPTestTLS(t, handler, config), httpTestClient(pki.roots, nil)
}

func doHTTPTest(t *testing.T, client *http.Client, method, url, body string, headers map[string][]string) (*http.Response, map[string]any, string) {
	t.Helper()
	request, err := http.NewRequest(method, url, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	for key, values := range headers {
		for _, value := range values {
			request.Header.Add(key, value)
		}
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	data, err := io.ReadAll(response.Body)
	response.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if response.Header.Get("Cache-Control") != "no-store" {
		t.Fatal("response cacheable")
	}
	if _, err := protocol.DecodeCanonicalBase64url(response.Header.Get("X-Request-ID"), 16); err != nil {
		t.Fatal("invalid independent request ID")
	}
	var object map[string]any
	if len(data) > 0 {
		if err := json.Unmarshal(data, &object); err != nil {
			t.Fatalf("bad JSON: %s", data)
		}
	}
	return response, object, string(data)
}

func httpTestVHeaders() map[string][]string {
	return map[string][]string{"Content-Type": {"application/json"}, "V-Installation-ID": {httpTestEncoding(16, 1)}, "Idempotency-Key": {httpTestEncoding(32, 2)}}
}

func TestPublicVerifierRejectsMalformedJSONHeadersAndQueriesBeforeBackend(t *testing.T) {
	backend, _, endpoints, pki := newHTTPTestVerifier(t, httpTestLimits())
	server, client := httpTestPublicServer(t, endpoints.Public, pki, VerifierService)
	for _, body := range []string{`{"email":"a@hainanu.edu.cn","email":"b@hainanu.edu.cn"}`, `{"email":"a@hainanu.edu.cn","\u0065mail":"b@hainanu.edu.cn"}`, `{"Email":"a@hainanu.edu.cn"}`, `{"email":null}`, `{"email":1}`, `{"email":[]}`, `{"email":"a@hainanu.edu.cn","accountId":"x"}`, `{"email":"a@hainanu.edu.cn"} {}`, `{"email":"` + strings.Repeat("x", 1024) + `"}`, "{\"email\":\"\xff\"}"} {
		response, _, _ := doHTTPTest(t, client, "POST", server.URL+"/api/v1/eligibility/otp-requests", body, httpTestVHeaders())
		if response.StatusCode != 400 {
			t.Fatalf("accepted %s status %s", body, response.Status)
		}
	}
	for _, change := range []func(map[string][]string){
		func(h map[string][]string) {
			h["Idempotency-Key"] = []string{httpTestEncoding(32, 2), httpTestEncoding(32, 3)}
		},
		func(h map[string][]string) { h["V-Installation-ID"] = []string{httpTestEncoding(16, 1) + "="} },
		func(h map[string][]string) { h["Authorization"] = []string{"Bearer " + httpTestEncoding(32, 4)} },
		func(h map[string][]string) { h["Content-Type"] = []string{"text/plain"} },
	} {
		headers := httpTestVHeaders()
		change(headers)
		response, _, _ := doHTTPTest(t, client, "POST", server.URL+"/api/v1/eligibility/otp-requests", `{"email":"a@hainanu.edu.cn"}`, headers)
		if response.StatusCode != 400 {
			t.Fatal(response.Status)
		}
	}
	response, _, _ := doHTTPTest(t, client, "POST", server.URL+"/api/v1/eligibility/otp-requests?email=private", `{"email":"a@hainanu.edu.cn"}`, httpTestVHeaders())
	if response.StatusCode != 400 {
		t.Fatal(response.Status)
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.requestCalls != 0 {
		t.Fatal("malformed request reached application")
	}
}

func TestVerifierCapabilitiesDoNotReturnTicketsOrShareRequestIDs(t *testing.T) {
	backend, _, endpoints, pki := newHTTPTestVerifier(t, httpTestLimits())
	server, client := httpTestPublicServer(t, endpoints.Public, pki, VerifierService)
	headers := httpTestVHeaders()
	headers["X-Request-ID"] = []string{httpTestEncoding(16, 50)}
	headers["traceparent"] = []string{"private-cross-party-trace"}
	response, _, body := doHTTPTest(t, client, "POST", server.URL+"/api/v1/eligibility/otp-requests", `{"email":"Exact+Alias@hainanu.edu.cn"}`, headers)
	if response.StatusCode != 202 || response.Header.Get("X-Request-ID") == headers["X-Request-ID"][0] || strings.Contains(body, "Exact") {
		t.Fatal("leaked identity or reused request ID")
	}
	backend.mu.Lock()
	if backend.lastRequest.Email != "Exact+Alias@hainanu.edu.cn" {
		t.Fatal("changed exact email")
	}
	backend.confirmationResult = authprivacy.ConfirmationResult{State: "TICKET_AVAILABLE", RegistrationTicket: "must-not-be-disclosed-by-get"}
	backend.mu.Unlock()
	queryHeaders := map[string][]string{"V-Installation-ID": {httpTestEncoding(16, 1)}, "Authorization": {"OtpConfirmationResult " + httpTestEncoding(32, 2)}, "OTP-Flow-ID": {httpTestEncoding(32, 3)}}
	response, object, body := doHTTPTest(t, client, "GET", server.URL+"/api/v1/eligibility/otp-confirmation-result", "", queryHeaders)
	if response.StatusCode != 200 || object["state"] != "TICKET_AVAILABLE" || strings.Contains(body, "must-not") || len(object) != 1 {
		t.Fatal("query disclosed ticket authority")
	}
	for _, wrong := range []string{"Bearer " + httpTestEncoding(32, 2), "OtpRequestResult " + httpTestEncoding(32, 2), "OtpConfirmationResult " + httpTestEncoding(32, 2) + "="} {
		queryHeaders["Authorization"] = []string{wrong}
		response, _, _ := doHTTPTest(t, client, "GET", server.URL+"/api/v1/eligibility/otp-confirmation-result", "", queryHeaders)
		if response.StatusCode != 401 {
			t.Fatal(response.Status)
		}
	}
	queryHeaders["Authorization"] = []string{"OtpConfirmationResult " + httpTestEncoding(32, 2)}
	response, _, _ = doHTTPTest(t, client, "GET", server.URL+"/api/v1/eligibility/otp-confirmation-result?token=x", "", queryHeaders)
	if response.StatusCode != 400 {
		t.Fatal(response.Status)
	}
}

func TestVerifierNetworkBudgetCannotBeResetByForwardedAddressOrInstallation(t *testing.T) {
	limits := httpTestLimits()
	limits.MutationCapacity = 1
	limits.QueryCapacity = 1
	_, _, endpoints, pki := newHTTPTestVerifier(t, limits)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, VerifierService)
	headers := httpTestVHeaders()
	headers["X-Forwarded-For"] = []string{"192.0.2.1"}
	response, _, _ := doHTTPTest(t, client, "POST", server.URL+"/api/v1/eligibility/otp-requests", `{"email":"a@hainanu.edu.cn"}`, headers)
	if response.StatusCode != 202 {
		t.Fatal(response.Status)
	}
	headers["X-Forwarded-For"] = []string{"192.0.2.2"}
	headers["V-Installation-ID"] = []string{httpTestEncoding(16, 9)}
	headers["Idempotency-Key"] = []string{httpTestEncoding(32, 9)}
	response, _, _ = doHTTPTest(t, client, "POST", server.URL+"/api/v1/eligibility/otp-requests", `{"email":"b@hainanu.edu.cn"}`, headers)
	if response.StatusCode != 429 || response.Header.Get("Retry-After") == "" {
		t.Fatal("forged headers reset network budget")
	}
	query := map[string][]string{"V-Installation-ID": {httpTestEncoding(16, 1)}, "Authorization": {"OtpRequestResult " + httpTestEncoding(32, 2)}}
	response, _, _ = doHTTPTest(t, client, "GET", server.URL+"/api/v1/eligibility/otp-request-result", "", query)
	if response.StatusCode != 202 {
		t.Fatal("mutation budget consumed query budget")
	}
	response, _, _ = doHTTPTest(t, client, "GET", server.URL+"/api/v1/eligibility/otp-request-result", "", query)
	if response.StatusCode != 429 {
		t.Fatal("query rate unlimited")
	}
}

func TestVerifierConfirmationChecksBootstrapSlotBindingAndPending(t *testing.T) {
	backend, _, endpoints, pki := newHTTPTestVerifier(t, httpTestLimits())
	server, client := httpTestPublicServer(t, endpoints.Public, pki, VerifierService)
	public, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	var key protocol.PublicKey
	copy(key[:], public)
	slot, err := protocol.DeriveSlot(key)
	if err != nil {
		t.Fatal(err)
	}
	object := map[string]string{"flowId": httpTestEncoding(32, 3), "otp": "123456", "slotId": protocol.EncodeCanonicalBase64url(slot[:]), "bootstrapPublicKey": protocol.EncodeCanonicalBase64url(key[:])}
	backend.confirmationResult = authprivacy.ConfirmationResult{State: "CONFIRMATION_PENDING", RetryAfterSeconds: 3}
	raw, _ := json.Marshal(object)
	response, result, _ := doHTTPTest(t, client, "POST", server.URL+"/api/v1/eligibility/otp-confirmations", string(raw), httpTestVHeaders())
	if response.StatusCode != 202 || result["state"] != "CONFIRMATION_PENDING" || response.Header.Get("Retry-After") != "3" {
		t.Fatal(response.Status)
	}
	object["slotId"] = httpTestEncoding(32, 9)
	raw, _ = json.Marshal(object)
	response, _, _ = doHTTPTest(t, client, "POST", server.URL+"/api/v1/eligibility/otp-confirmations", string(raw), httpTestVHeaders())
	if response.StatusCode != 422 {
		t.Fatal("wrong slot admitted")
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.confirmationCalls != 1 {
		t.Fatal("wrong binding reached backend")
	}
}

func httpTestIntentBody() string {
	ticket := protocol.SignedTicket{Ticket: protocol.Ticket{Epoch: 1, Window: 1, Slot: protocol.SlotID{1}, BootstrapKey: protocol.PublicKey{2}}}
	raw, _ := json.Marshal(map[string]string{"registrationTicket": ticket.Encode(), "username": "private_user", "password": "a long independent secret", "installationId": httpTestEncoding(16, 9)})
	return string(raw)
}

func TestCommunityValidatesTicketBeforePasswordAndDoesNotExposeReplaySecrets(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCommunity(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	headers := map[string][]string{"Content-Type": {"application/json"}}
	response, object, _ := doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/registration-intents", httpTestIntentBody(), headers)
	if response.StatusCode != 201 || object["recoveryCode"] != httpTestCode() || object["expiresAt"] == nil {
		t.Fatal(response.Status)
	}
	backend.mu.Lock()
	events := strings.Join(backend.events, ",")
	backend.mu.Unlock()
	if events != "validate,password,intent" {
		t.Fatalf("unsafe KDF ordering: %s", events)
	}
	registration, _ := json.Marshal(map[string]string{"intentId": httpTestEncoding(32, 1), "bootstrapSignature": httpTestEncoding(64, 2), "recoveryCodeConfirmation": httpTestCode()})
	headers["Idempotency-Key"] = []string{httpTestEncoding(32, 3)}
	response, object, _ = doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/registrations", string(registration), headers)
	if response.StatusCode != 201 || object["sessionToken"] == nil || object["accountId"] == nil || response.Header.Get("Session-Expires-At") != object["expiresAt"] {
		t.Fatal("missing required session output")
	}
	backend.mu.Lock()
	backend.result.Replay = true
	backend.mu.Unlock()
	response, object, body := doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/registrations", string(registration), headers)
	if response.StatusCode != 409 || strings.Contains(body, "sessionToken") || strings.Contains(body, "recoveryCode") || object["error"].(map[string]any)["code"] != "REGISTRATION_COMMITTED_LOGIN_REQUIRED" {
		t.Fatal("idempotency replay issued authority")
	}
}

func TestCommunityRejectsInvalidTicketBeforeKDFAndHidesBackendDetails(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCommunity(t)
	backend.validateError = protocol.ErrSignature
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	headers := map[string][]string{"Content-Type": {"application/json"}}
	response, _, _ := doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/registration-intents", httpTestIntentBody(), headers)
	if response.StatusCode != 422 {
		t.Fatal(response.Status)
	}
	backend.mu.Lock()
	if strings.Join(backend.events, ",") != "validate" {
		t.Fatal("invalid ticket invoked KDF")
	}
	backend.validateError = errors.New("private@hainanu.edu.cn secret database detail")
	backend.mu.Unlock()
	response, _, body := doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/registration-intents", httpTestIntentBody(), headers)
	if response.StatusCode != 503 || strings.Contains(body, "private@") || strings.Contains(body, "database") {
		t.Fatal("backend error leaked")
	}
	response, _, _ = doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/registration-intents", `{"large":"`+strings.Repeat("x", 8192)+`"}`, headers)
	if response.StatusCode != 413 {
		t.Fatal("oversize body not bounded")
	}
	headers["Content-Type"] = []string{"text/plain"}
	response, _, _ = doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/registration-intents", httpTestIntentBody(), headers)
	if response.StatusCode != 415 {
		t.Fatal(response.Status)
	}
}

func TestInternalHandlersRejectForwardedOrUnverifiedCertificateMetadata(t *testing.T) {
	_, receipts, endpoints, pki := newHTTPTestVerifier(t, httpTestLimits())
	certificate := pki.issue(t, "lab", CommunityService, nil)
	receipt := protocol.Receipt{Purpose: protocol.PurposeReleased, Slot: protocol.SlotID{1}, Epoch: 1}
	encoded, err := receipt.Encode()
	if err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(map[string]string{"releaseReceipt": encoded})
	for _, state := range []*tls.ConnectionState{nil, {HandshakeComplete: true, Version: tls.VersionTLS13, PeerCertificates: []*x509.Certificate{certificate.Leaf}}} {
		request := httptest.NewRequest("POST", "https://verifier.lab/internal/v1/slot-releases", bytes.NewReader(body))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("X-SSL-Client-Cert", "forged")
		request.Header.Set("X-Forwarded-Client-Cert", "forged")
		request.TLS = state
		writer := httptest.NewRecorder()
		endpoints.Internal.ServeHTTP(writer, request)
		if writer.Code != 401 || writer.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("certificate header bypass")
		}
	}
	receipts.mu.Lock()
	defer receipts.mu.Unlock()
	if receipts.calls != 0 {
		t.Fatal("unverified caller reached receipt processor")
	}
}

func TestPublicHandlersDoNotExposeInternalOrOtherAuthRoutes(t *testing.T) {
	_, endpoints, pki := newHTTPTestCommunity(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, path := range []string{"/internal/v1/slot-retirements", "/api/v1/auth/recovery-code-reset-intents"} {
		response, _, _ := doHTTPTest(t, client, "POST", server.URL+path, `{}`, map[string][]string{"Content-Type": {"application/json"}})
		if response.StatusCode != 404 {
			t.Fatal("unimplemented route exposed")
		}
	}
}
