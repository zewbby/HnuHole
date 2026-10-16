package authprivacyhttp

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

type httpTestCredentials struct {
	mu                     sync.Mutex
	calls                  int
	err                    error
	credentials            authprivacy.RecoveryCredentials
	rotation               authprivacy.CodeRotationIntent
	options, resetOptions  authprivacy.PasskeyOptions
	removal                authprivacy.PasskeyRemovalIntent
	reset                  authprivacy.PasswordResetIntent
	expires                time.Time
	bearer                 [32]byte
	password, credentialID string
	confirmation           authprivacy.CodeRotationConfirmation
	registration           authprivacy.PasskeyRegistration
	remove                 authprivacy.PasskeyRemoval
	proof                  authprivacy.PasskeyResetProof
	changeResult           authprivacy.CredentialChangeResult
	resultID, resultKey    [32]byte
}

func (f *httpTestCredentials) GetCredentialChangeResult(_ context.Context, bearer, id, key [32]byte) (authprivacy.CredentialChangeResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.bearer, f.resultID, f.resultKey = bearer, id, key
	return f.changeResult, f.err
}

func (f *httpTestCredentials) GetRecoveryCredentials(_ context.Context, bearer [32]byte) (authprivacy.RecoveryCredentials, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.bearer = bearer
	return f.credentials, f.err
}
func (f *httpTestCredentials) CreateRecoveryCodeRotation(_ context.Context, bearer [32]byte, password string, _ authprivacy.PasswordVerifier) (authprivacy.CodeRotationIntent, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.bearer, f.password = bearer, password
	return f.rotation, f.err
}
func (f *httpTestCredentials) ConfirmRecoveryCodeRotation(_ context.Context, bearer [32]byte, request authprivacy.CodeRotationConfirmation) (time.Time, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.bearer, f.confirmation = bearer, request
	return f.expires, f.err
}
func (f *httpTestCredentials) CreatePasskeyOptions(_ context.Context, bearer [32]byte, password string, _ authprivacy.PasswordVerifier) (authprivacy.PasskeyOptions, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.bearer, f.password = bearer, password
	return f.options, f.err
}
func (f *httpTestCredentials) RegisterPasskey(_ context.Context, bearer [32]byte, request authprivacy.PasskeyRegistration) (time.Time, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.bearer, f.registration = bearer, request
	return f.expires, f.err
}
func (f *httpTestCredentials) CreatePasskeyRemovalIntent(_ context.Context, bearer [32]byte, password, credentialID string, _ authprivacy.PasswordVerifier) (authprivacy.PasskeyRemovalIntent, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.bearer, f.credentialID, f.password = bearer, credentialID, password
	return f.removal, f.err
}
func (f *httpTestCredentials) RemovePasskey(_ context.Context, bearer [32]byte, request authprivacy.PasskeyRemoval) (time.Time, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.bearer, f.remove = bearer, request
	return f.expires, f.err
}
func (f *httpTestCredentials) CreatePasskeyResetOptions(context.Context) (authprivacy.PasskeyOptions, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	return f.resetOptions, f.err
}
func (f *httpTestCredentials) CreatePasskeyResetIntent(_ context.Context, proof authprivacy.PasskeyResetProof) (authprivacy.PasswordResetIntent, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.proof = proof
	return f.reset, f.err
}

func httpTestCreationOptions() map[string]any {
	return map[string]any{
		"challenge": httpTestEncoding(32, 4), "rp": map[string]string{"id": "auth.hnuhole.test", "name": "Hnuhole"},
		"user":             map[string]string{"id": httpTestEncoding(32, 3), "name": httpTestEncoding(32, 3), "displayName": "Hnuhole account"},
		"pubKeyCredParams": []map[string]any{{"type": "public-key", "alg": -7}}, "timeout": 60000,
		"excludeCredentials": []map[string]string{}, "attestation": "none",
		"authenticatorSelection": map[string]any{"residentKey": "required", "requireResidentKey": true, "userVerification": "required"},
	}
}

func newHTTPTestCredentials(t *testing.T) (*httpTestCredentials, *Endpoints, *httpTestPKI) {
	t.Helper()
	pki, community := newHTTPTestPKI(t), &httpTestCommunity{}
	expires := time.Date(2026, 10, 30, 4, 5, 6, 0, time.UTC)
	intentExpiry := time.Date(2026, 9, 30, 4, 10, 6, 0, time.UTC)
	backend := &httpTestCredentials{
		credentials:  authprivacy.RecoveryCredentials{RecoveryCodeAvailable: true, Passkeys: []authprivacy.PasskeySummary{{CredentialID: httpTestEncoding(16, 1), CreatedAt: intentExpiry, BackupEligible: true, BackedUp: true}}, SessionExpiresAt: expires},
		rotation:     authprivacy.CodeRotationIntent{ID: httpTestRecoveryCapability(6), ExpiresAt: intentExpiry, NewRecoveryCode: httpTestCode(), SessionExpiresAt: expires},
		options:      authprivacy.PasskeyOptions{ChallengeID: httpTestRecoveryCapability(6), ExpiresAt: intentExpiry, PublicKey: httpTestCreationOptions(), SessionExpiresAt: expires},
		resetOptions: authprivacy.PasskeyOptions{ChallengeID: httpTestRecoveryCapability(6), ExpiresAt: intentExpiry, PublicKey: map[string]any{"challenge": httpTestEncoding(32, 4), "rpId": "auth.hnuhole.test", "timeout": 60000, "userVerification": "required"}},
		removal:      authprivacy.PasskeyRemovalIntent{ID: httpTestRecoveryCapability(6), ExpiresAt: intentExpiry, SessionExpiresAt: expires},
		reset:        authprivacy.PasswordResetIntent{ID: httpTestRecoveryCapability(6), ExpiresAt: intentExpiry, Username: "private_user", NewRecoveryCode: httpTestCode()},
		expires:      expires,
	}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{Backend: community, Credentials: backend, Passwords: httpTestPasswords{backend: community},
		InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: httpTestLimits(), AllowedOrigins: []string{"https://client.hnuhole.test"}})
	if err != nil {
		t.Fatal(err)
	}
	return backend, endpoints, pki
}

func httpTestCredentialHeaders(path string) map[string][]string {
	headers := map[string][]string{"Content-Type": {"application/json"}}
	if path != "/api/v1/auth/passkey-reset-options" && path != "/api/v1/auth/passkey-reset-intents" {
		headers["Authorization"] = []string{"Bearer " + httpTestEncoding(32, 8)}
	}
	if path == "/api/v1/auth/passkeys" || path == "/api/v1/auth/credential-change-result" || isRotationConfirmationPath(path) || isPasskeyRemovalPath(path) {
		headers["Idempotency-Key"] = []string{httpTestEncoding(32, 7)}
	}
	if isPasskeyRemovalPath(path) || path == "/api/v1/auth/credential-change-result" {
		headers["Credential-Change-ID"] = []string{httpTestEncoding(32, 6)}
	}
	return headers
}

func TestCredentialChangeResultHTTPNoSecretShapeAndCapabilityBindings(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCredentials(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	path := "/api/v1/auth/credential-change-result"
	for _, state := range []string{"PENDING", "COMMITTED", "NOT_COMMITTED"} {
		backend.mu.Lock()
		backend.changeResult = authprivacy.CredentialChangeResult{State: state, SessionExpiresAt: backend.expires}
		backend.mu.Unlock()
		response, body, _ := doHTTPTest(t, client, "GET", server.URL+path, "", httpTestCredentialHeaders(path))
		if response.StatusCode != 200 || !reflect.DeepEqual(body, map[string]any{"state": state}) || response.Header.Get("Session-Expires-At") != utc(backend.expires) || response.Header.Get("Cache-Control") != "no-store" {
			t.Fatalf("result response disclosed or lost fields: %d %v", response.StatusCode, body)
		}
	}
	backend.mu.Lock()
	if backend.resultID != httpTestRecoveryCapability(6) || backend.resultKey != httpTestRecoveryCapability(7) || backend.bearer != httpTestRecoveryCapability(8) || backend.calls != 3 {
		t.Fatal("original key/intent/session were not bound")
	}
	backend.mu.Unlock()
	for _, tc := range []struct {
		err error
		status int
	}{
		{authprivacy.ErrAuthorizationUnavailable, 503}, {authprivacy.ErrSessionInvalid, 401},
		{authprivacy.ErrSessionReplaced, 401}, {authprivacy.ErrCredentialIntentInvalid, 409},
		{authprivacy.ErrConflict, 409}, {authprivacy.ErrExpired, 410},
	} {
		backend.mu.Lock()
		backend.err = tc.err
		backend.mu.Unlock()
		response, body, _ := doHTTPTest(t, client, "GET", server.URL+path, "", httpTestCredentialHeaders(path))
		if response.StatusCode != tc.status || response.Header.Get("Session-Expires-At") != "" || len(body) != 2 || body["state"] != nil {
			t.Fatalf("failed query disclosed a conclusion: %d %v", response.StatusCode, body)
		}
	}
}

func TestCredentialChangeResultHTTPRejectsMalformedAndMixedAuthority(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCredentials(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	path := "/api/v1/auth/credential-change-result"
	for _, tc := range []struct {
		name, method, suffix, body string
		change func(map[string][]string)
		status int
	}{
		{"missing-id", "GET", "", "", func(h map[string][]string) { delete(h, "Credential-Change-ID") }, 400},
		{"missing-key", "GET", "", "", func(h map[string][]string) { delete(h, "Idempotency-Key") }, 400},
		{"duplicate-id", "GET", "", "", func(h map[string][]string) { h["Credential-Change-ID"] = []string{httpTestEncoding(32, 6), httpTestEncoding(32, 6)} }, 400},
		{"duplicate-key", "GET", "", "", func(h map[string][]string) { h["Idempotency-Key"] = []string{httpTestEncoding(32, 7), httpTestEncoding(32, 7)} }, 400},
		{"padded-key", "GET", "", "", func(h map[string][]string) { h["Idempotency-Key"] = []string{httpTestEncoding(32, 7) + "="} }, 400},
		{"wrong-capability", "GET", "", "", func(h map[string][]string) { h["Authorization"] = []string{"SessionRevoke " + httpTestEncoding(32, 8)} }, 401},
		{"mixed-reset", "GET", "", "", func(h map[string][]string) { h["Reset-Intent-ID"] = []string{httpTestEncoding(32, 6)} }, 400},
		{"mixed-verifier", "GET", "", "", func(h map[string][]string) { h["V-Installation-ID"] = []string{httpTestEncoding(16, 6)} }, 400},
		{"query", "GET", "?id=ignored", "", nil, 400},
		{"body", "GET", "", "{}", nil, 400},
		{"method", "POST", "", "", nil, 405},
	} {
		t.Run(tc.name, func(t *testing.T) {
			headers := httpTestCredentialHeaders(path)
			if tc.change != nil { tc.change(headers) }
			response, _, _ := doHTTPTest(t, client, tc.method, server.URL+path+tc.suffix, tc.body, headers)
			if response.StatusCode != tc.status { t.Fatalf("malformed result query status=%d want=%d", response.StatusCode, tc.status) }
		})
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 0 { t.Fatal("malformed query reached credential authority") }
}

func httpTestAttestationBody() string {
	return `{"challengeId":"` + httpTestEncoding(32, 6) + `","webauthnAttestation":{"id":"` + httpTestEncoding(16, 1) + `","rawId":"` + httpTestEncoding(16, 1) + `","type":"public-key","response":{"clientDataJSON":"` + httpTestEncoding(2, 1) + `","attestationObject":"` + httpTestEncoding(2, 2) + `","transports":["internal","hybrid"]},"clientExtensionResults":{}}}`
}
func httpTestAssertionBody() string {
	return `{"challengeId":"` + httpTestEncoding(32, 6) + `","webauthnAssertion":{"id":"` + httpTestEncoding(16, 1) + `","rawId":"` + httpTestEncoding(16, 1) + `","type":"public-key","response":{"clientDataJSON":"` + httpTestEncoding(2, 1) + `","authenticatorData":"` + httpTestEncoding(37, 2) + `","signature":"` + httpTestEncoding(8, 3) + `","userHandle":"` + httpTestEncoding(32, 4) + `"},"clientExtensionResults":{}}}`
}
func httpTestRotationPath() string {
	return rotationPrefix + httpTestEncoding(32, 6) + "/confirmations"
}
func httpTestRemovalPath() string { return passkeyPrefix + httpTestEncoding(16, 1) }

func TestCredentialHTTPSuccessResponsesAndProofBindings(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCredentials(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		method, path, body string
		status             int
		keys               []string
		session            bool
	}{
		{"GET", "/api/v1/auth/recovery-credentials", "", 200, []string{"recoveryCodeAvailable", "passkeys"}, true},
		{"POST", "/api/v1/auth/recovery-code-rotations", `{"password":"current private phrase"}`, 201, []string{"rotationIntentId", "expiresAt", "newRecoveryCode"}, true},
		{"POST", httpTestRotationPath(), `{"newRecoveryCodeConfirmation":"` + httpTestCode() + `"}`, 204, nil, true},
		{"POST", "/api/v1/auth/passkey-options", `{"password":"current private phrase"}`, 200, []string{"challengeId", "expiresAt", "publicKey"}, true},
		{"POST", "/api/v1/auth/passkeys", httpTestAttestationBody(), 204, nil, true},
		{"POST", "/api/v1/auth/passkey-removal-intents", `{"password":"current private phrase","credentialId":"` + httpTestEncoding(16, 1) + `"}`, 201, []string{"removalIntentId", "expiresAt"}, true},
		{"DELETE", httpTestRemovalPath(), "", 204, nil, true},
		{"POST", "/api/v1/auth/passkey-reset-options", `{}`, 200, []string{"challengeId", "expiresAt", "publicKey"}, false},
		{"POST", "/api/v1/auth/passkey-reset-intents", httpTestAssertionBody(), 201, []string{"resetIntentId", "expiresAt", "username", "newRecoveryCode"}, false},
	} {
		t.Run(test.path, func(t *testing.T) {
			response, body, raw := doHTTPTest(t, client, test.method, server.URL+test.path, test.body, httpTestCredentialHeaders(test.path))
			if response.StatusCode != test.status || len(body) != len(test.keys) {
				t.Fatalf("response contract: status=%d body=%v", response.StatusCode, body)
			}
			for _, key := range test.keys {
				if _, ok := body[key]; !ok {
					t.Fatalf("missing %s in %v", key, body)
				}
			}
			if test.status == 204 && raw != "" {
				t.Fatalf("204 replay leaked response: %s", raw)
			}
			expectedExpiry := ""
			if test.session {
				expectedExpiry = utc(backend.expires)
			}
			if response.Header.Get("Session-Expires-At") != expectedExpiry {
				t.Fatal("management did not expose renewal or recovery exposed session")
			}
			if test.path == "/api/v1/auth/recovery-credentials" {
				expected := map[string]any{"recoveryCodeAvailable": true, "passkeys": []any{map[string]any{"credentialId": httpTestEncoding(16, 1), "createdAt": utc(backend.rotation.ExpiresAt), "backupEligible": true, "backedUp": true}}}
				if !reflect.DeepEqual(body, expected) {
					t.Fatalf("credential list leaked or lost fields: %v", body)
				}
			}
			if test.path == "/api/v1/auth/passkey-reset-options" {
				options := body["publicKey"].(map[string]any)
				if len(options) != 4 || options["rpId"] != "auth.hnuhole.test" || options["userVerification"] != "required" {
					t.Fatal("recovery options not discoverable fixed policy")
				}
			}
		})
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 9 || backend.bearer != httpTestRecoveryCapability(8) || backend.password != "current private phrase" ||
		backend.confirmation.IntentID != httpTestRecoveryCapability(6) || backend.confirmation.IdempotencyKey != httpTestRecoveryCapability(7) ||
		backend.registration.ChallengeID != httpTestRecoveryCapability(6) || backend.registration.IdempotencyKey != httpTestRecoveryCapability(7) ||
		backend.registration.Response.ID != httpTestEncoding(16, 1) || backend.remove.IntentID != httpTestRecoveryCapability(6) ||
		backend.remove.IdempotencyKey != httpTestRecoveryCapability(7) || backend.remove.CredentialID != httpTestEncoding(16, 1) ||
		backend.proof.ChallengeID != httpTestRecoveryCapability(6) || backend.proof.Response.UserHandle != httpTestEncoding(32, 4) {
		t.Fatal("validated proof or session bindings changed before authority")
	}
}

func TestCredentialHTTPRejectsAmbiguousNestedProofs(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCredentials(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct{ name, path, body string }{
		{"duplicate password", "/api/v1/auth/passkey-options", `{"password":"phrase","password":"other"}`},
		{"null password", "/api/v1/auth/recovery-code-rotations", `{"password":null}`},
		{"unknown rotation", "/api/v1/auth/recovery-code-rotations", `{"password":"phrase","username":"private_user"}`},
		{"removal unknown", "/api/v1/auth/passkey-removal-intents", `{"password":"phrase","credentialId":"` + httpTestEncoding(16, 1) + `","accountId":"secret"}`},
		{"reset nonempty", "/api/v1/auth/passkey-reset-options", `{"credentialId":"` + httpTestEncoding(16, 1) + `"}`},
		{"reset not object", "/api/v1/auth/passkey-reset-options", `[]`},
		{"nested duplicate", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `"type":"public-key"`, `"type":"public-key","type":"public-key"`, 1)},
		{"nested escaped duplicate", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `"type":"public-key"`, `"type":"public-key","\u0074ype":"public-key"`, 1)},
		{"unknown credential field", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `"type":"public-key"`, `"type":"public-key","username":"private_user"`, 1)},
		{"unknown response field", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `"transports":`, `"AAGUID":"hardware","transports":`, 1)},
		{"extensions rejected", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `"clientExtensionResults":{}`, `"clientExtensionResults":{"credProps":{"rk":true}}`, 1)},
		{"extension null", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `"clientExtensionResults":{}`, `"clientExtensionResults":null`, 1)},
		{"transport duplicate", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `["internal","hybrid"]`, `["internal","internal"]`, 1)},
		{"transport invalid", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `["internal","hybrid"]`, `["unknown"]`, 1)},
		{"transport type", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `["internal","hybrid"]`, `"internal"`, 1)},
		{"transport null", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `["internal","hybrid"]`, `null`, 1)},
		{"ID mismatch", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `"rawId":"`+httpTestEncoding(16, 1), `"rawId":"`+httpTestEncoding(16, 2), 1)},
		{"padded proof", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `"clientDataJSON":"`+httpTestEncoding(2, 1)+`"`, `"clientDataJSON":"`+httpTestEncoding(2, 1)+`="`, 1)},
		{"wrong credential type", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), `"type":"public-key"`, `"type":"password"`, 1)},
		{"short authData", "/api/v1/auth/passkey-reset-intents", strings.Replace(httpTestAssertionBody(), httpTestEncoding(37, 2), httpTestEncoding(36, 2), 1)},
		{"short signature", "/api/v1/auth/passkey-reset-intents", strings.Replace(httpTestAssertionBody(), httpTestEncoding(8, 3), httpTestEncoding(7, 3), 1)},
		{"missing handle", "/api/v1/auth/passkey-reset-intents", strings.Replace(httpTestAssertionBody(), `,"userHandle":"`+httpTestEncoding(32, 4)+`"`, "", 1)},
		{"null handle", "/api/v1/auth/passkey-reset-intents", strings.Replace(httpTestAssertionBody(), `"userHandle":"`+httpTestEncoding(32, 4)+`"`, `"userHandle":null`, 1)},
		{"assertion extension", "/api/v1/auth/passkey-reset-intents", strings.Replace(httpTestAssertionBody(), `"clientExtensionResults":{}`, `"clientExtensionResults":{"appid":true}`, 1)},
		{"assertion response duplicate", "/api/v1/auth/passkey-reset-intents", strings.Replace(httpTestAssertionBody(), `"response":{`, `"response":{"signature":"`+httpTestEncoding(8, 3)+`",`, 1)},
	} {
		t.Run(test.name, func(t *testing.T) {
			response, body, _ := doHTTPTest(t, client, "POST", server.URL+test.path, test.body, httpTestCredentialHeaders(test.path))
			if response.StatusCode != 400 || body["error"].(map[string]any)["code"] != "MALFORMED_REQUEST" {
				t.Fatalf("ambiguous proof accepted: status=%d body=%v", response.StatusCode, body)
			}
		})
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 0 {
		t.Fatal("malformed proof reached credential authority")
	}
}

func TestCredentialHTTPRejectsMisScopedHeadersAndNoncanonicalIDs(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCredentials(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		name, method, path, body string
		change                   func(map[string][]string)
		status                   int
	}{
		{"list key forbidden", "GET", "/api/v1/auth/recovery-credentials", "", func(h map[string][]string) { h["Idempotency-Key"] = []string{httpTestEncoding(32, 7)} }, 400},
		{"list body", "GET", "/api/v1/auth/recovery-credentials", `{}`, nil, 400},
		{"missing bearer", "POST", "/api/v1/auth/passkey-options", `{"password":"phrase"}`, func(h map[string][]string) { delete(h, "Authorization") }, 401},
		{"wrong scheme", "POST", "/api/v1/auth/passkey-options", `{"password":"phrase"}`, func(h map[string][]string) { h["Authorization"] = []string{"SessionRevoke " + httpTestEncoding(32, 8)} }, 401},
		{"padded bearer", "GET", "/api/v1/auth/recovery-credentials", "", func(h map[string][]string) { h["Authorization"] = []string{"Bearer " + httpTestEncoding(32, 8) + "="} }, 400},
		{"option idempotency forbidden", "POST", "/api/v1/auth/passkey-options", `{"password":"phrase"}`, func(h map[string][]string) { h["Idempotency-Key"] = []string{httpTestEncoding(32, 7)} }, 400},
		{"reset bearer forbidden", "POST", "/api/v1/auth/passkey-reset-options", `{}`, func(h map[string][]string) { h["Authorization"] = []string{"Bearer " + httpTestEncoding(32, 8)} }, 400},
		{"reset key forbidden", "POST", "/api/v1/auth/passkey-reset-intents", httpTestAssertionBody(), func(h map[string][]string) { h["Idempotency-Key"] = []string{httpTestEncoding(32, 7)} }, 400},
		{"missing commit key", "POST", "/api/v1/auth/passkeys", httpTestAttestationBody(), func(h map[string][]string) { delete(h, "Idempotency-Key") }, 400},
		{"duplicate commit key", "POST", "/api/v1/auth/passkeys", httpTestAttestationBody(), func(h map[string][]string) {
			h["Idempotency-Key"] = []string{httpTestEncoding(32, 7), httpTestEncoding(32, 7)}
		}, 400},
		{"missing change ID", "DELETE", httpTestRemovalPath(), "", func(h map[string][]string) { delete(h, "Credential-Change-ID") }, 400},
		{"duplicate change ID", "DELETE", httpTestRemovalPath(), "", func(h map[string][]string) {
			h["Credential-Change-ID"] = []string{httpTestEncoding(32, 6), httpTestEncoding(32, 6)}
		}, 400},
		{"padded change ID", "DELETE", httpTestRemovalPath(), "", func(h map[string][]string) { h["Credential-Change-ID"] = []string{httpTestEncoding(32, 6) + "="} }, 400},
		{"delete body forbidden", "DELETE", httpTestRemovalPath(), `{}`, nil, 400},
		{"change ID on legacy session", "GET", "/api/v1/auth/session", "", func(h map[string][]string) { h["Credential-Change-ID"] = []string{httpTestEncoding(32, 6)} }, 400},
		{"change ID on registration", "POST", "/api/v1/auth/registration-intents", `{}`, func(h map[string][]string) { h["Credential-Change-ID"] = []string{httpTestEncoding(32, 6)} }, 400},
		{"reset ID on credential", "POST", "/api/v1/auth/passkeys", httpTestAttestationBody(), func(h map[string][]string) { h["Reset-Intent-ID"] = []string{httpTestEncoding(32, 6)} }, 400},
		{"V ID on credential", "GET", "/api/v1/auth/recovery-credentials", "", func(h map[string][]string) { h["V-Installation-ID"] = []string{httpTestEncoding(16, 4)} }, 400},
		{"invalid delete path", "DELETE", passkeyPrefix + httpTestEncoding(16, 1) + "=", "", nil, 400},
		{"invalid rotation path", "POST", rotationPrefix + httpTestEncoding(31, 6) + "/confirmations", `{"newRecoveryCodeConfirmation":"` + httpTestCode() + `"}`, nil, 400},
		{"query forbidden", "GET", "/api/v1/auth/recovery-credentials?accountId=secret", "", nil, 400},
	} {
		t.Run(test.name, func(t *testing.T) {
			headers := httpTestCredentialHeaders(test.path)
			if test.change != nil {
				test.change(headers)
			}
			response, _, _ := doHTTPTest(t, client, test.method, server.URL+test.path, test.body, headers)
			if response.StatusCode != test.status {
				t.Fatalf("unexpected header or identifier accepted: %d", response.StatusCode)
			}
		})
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 0 {
		t.Fatal("malformed capabilities reached authority")
	}
}

func TestCredentialHTTPProofAndMediaBounds(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCredentials(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		name, path, body, media string
		status                  int
	}{
		{"creation body bound", "/api/v1/auth/passkeys", strings.Repeat(" ", 32769), "application/json", 413},
		{"assertion body bound", "/api/v1/auth/passkey-reset-intents", strings.Repeat(" ", 32769), "application/json", 413},
		{"password body bound", "/api/v1/auth/passkey-options", strings.Repeat(" ", 8193), "application/json", 413},
		{"wrong media", "/api/v1/auth/passkey-reset-options", `{}`, "text/plain", 415},
		{"clientData bound", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), httpTestEncoding(2, 1), httpTestEncoding(3073, 1), 1), "application/json", 400},
		{"attestation bound", "/api/v1/auth/passkeys", strings.Replace(httpTestAttestationBody(), httpTestEncoding(2, 2), httpTestEncoding(4097, 2), 1), "application/json", 400},
		{"credential bound", "/api/v1/auth/passkeys", strings.ReplaceAll(httpTestAttestationBody(), httpTestEncoding(16, 1), httpTestEncoding(1024, 1)), "application/json", 400},
		{"authenticatorData bound", "/api/v1/auth/passkey-reset-intents", strings.Replace(httpTestAssertionBody(), httpTestEncoding(37, 2), httpTestEncoding(2049, 2), 1), "application/json", 400},
	} {
		t.Run(test.name, func(t *testing.T) {
			headers := httpTestCredentialHeaders(test.path)
			headers["Content-Type"] = []string{test.media}
			response, _, _ := doHTTPTest(t, client, "POST", server.URL+test.path, test.body, headers)
			if response.StatusCode != test.status {
				t.Fatalf("proof boundary status=%d want=%d", response.StatusCode, test.status)
			}
		})
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 0 {
		t.Fatal("unbounded or misencoded request reached authority")
	}
}

func TestCredentialHTTPAuthorityErrorsArePublishedAndPrivate(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCredentials(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		err    error
		status int
		code   string
	}{
		{authprivacy.ErrCredentialNotFound, 404, "RESOURCE_NOT_FOUND"},
		{authprivacy.ErrCredentialIntentInvalid, 409, "INTENT_INVALID"},
		{authprivacy.ErrCredentialIntentExpired, 410, "INTENT_EXPIRED"},
		{authprivacy.ErrPasskeyLimit, 409, "CREDENTIAL_LIMIT_REACHED"},
		{authprivacy.ErrWebAuthnValidation, 422, "CHALLENGE_INVALID"},
		{authprivacy.ErrRecoveryProofInvalid, 401, "AUTHENTICATION_FAILED"},
		{authprivacy.ErrCredentialStateChanged, 409, "CREDENTIAL_STATE_CHANGED"},
		{authprivacy.ErrConflict, 409, "IDEMPOTENCY_KEY_REUSED"},
		{authprivacy.ErrExpired, 410, "RESULT_EXPIRED"},
		{authprivacy.ErrAuthorizationUnavailable, 503, "SERVICE_UNAVAILABLE"},
		{authprivacy.ErrSessionReplaced, 401, "session_replaced"},
		{authprivacy.ErrPasswordBusy, 429, "RATE_LIMITED"},
		{errors.New("unknown private fault"), 503, "SERVICE_UNAVAILABLE"},
	} {
		t.Run(test.code, func(t *testing.T) {
			backend.mu.Lock()
			backend.err = fmt.Errorf("%w: database-secret private_user", test.err)
			backend.mu.Unlock()
			response, body, raw := doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/passkeys", httpTestAttestationBody(), httpTestCredentialHeaders("/api/v1/auth/passkeys"))
			public := body["error"].(map[string]any)
			if response.StatusCode != test.status || public["code"] != test.code || body["requestId"] != response.Header.Get("X-Request-ID") ||
				strings.Contains(raw, "database-secret") || strings.Contains(raw, "private_user") || response.Header.Get("Session-Expires-At") != "" {
				t.Fatalf("unsafe error mapping: status=%d body=%v", response.StatusCode, body)
			}
		})
	}
}

func TestCredentialHTTPRejectsImpossibleAuthorityOptionsAndList(t *testing.T) {
	for _, test := range []struct {
		name, path, body string
		change           func(*httpTestCredentials)
	}{
		{"recovery code absent", "/api/v1/auth/recovery-credentials", "", func(f *httpTestCredentials) { f.credentials.RecoveryCodeAvailable = false }},
		{"bad backup flags", "/api/v1/auth/recovery-credentials", "", func(f *httpTestCredentials) { f.credentials.Passkeys[0].BackupEligible = false }},
		{"unordered credentials", "/api/v1/auth/recovery-credentials", "", func(f *httpTestCredentials) {
			item := f.credentials.Passkeys[0]
			item.CredentialID = httpTestEncoding(16, 2)
			item.CreatedAt = item.CreatedAt.Add(-time.Second)
			f.credentials.Passkeys = append(f.credentials.Passkeys, item)
		}},
		{"creation account name", "/api/v1/auth/passkey-options", `{"password":"phrase"}`, func(f *httpTestCredentials) { f.options.PublicKey["user"].(map[string]string)["name"] = "private_user" }},
		{"creation attestation", "/api/v1/auth/passkey-options", `{"password":"phrase"}`, func(f *httpTestCredentials) { f.options.PublicKey["attestation"] = "direct" }},
		{"creation extensions", "/api/v1/auth/passkey-options", `{"password":"phrase"}`, func(f *httpTestCredentials) { f.options.PublicKey["extensions"] = map[string]any{"credProps": true} }},
		{"creation user verification", "/api/v1/auth/passkey-options", `{"password":"phrase"}`, func(f *httpTestCredentials) {
			f.options.PublicKey["authenticatorSelection"].(map[string]any)["userVerification"] = "preferred"
		}},
		{"creation unknown algorithm", "/api/v1/auth/passkey-options", `{"password":"phrase"}`, func(f *httpTestCredentials) {
			f.options.PublicKey["pubKeyCredParams"] = []map[string]any{{"type": "public-key", "alg": -257}}
		}},
		{"creation missing session expiry", "/api/v1/auth/passkey-options", `{"password":"phrase"}`, func(f *httpTestCredentials) { f.options.SessionExpiresAt = time.Time{} }},
		{"recovery allow list", "/api/v1/auth/passkey-reset-options", `{}`, func(f *httpTestCredentials) { f.resetOptions.PublicKey["allowCredentials"] = []any{} }},
		{"recovery session leakage", "/api/v1/auth/passkey-reset-options", `{}`, func(f *httpTestCredentials) { f.resetOptions.SessionExpiresAt = f.expires }},
	} {
		t.Run(test.name, func(t *testing.T) {
			backend, endpoints, pki := newHTTPTestCredentials(t)
			backend.mu.Lock()
			test.change(backend)
			backend.mu.Unlock()
			server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
			method := "POST"
			if test.path == "/api/v1/auth/recovery-credentials" {
				method = "GET"
			}
			response, body, raw := doHTTPTest(t, client, method, server.URL+test.path, test.body, httpTestCredentialHeaders(test.path))
			if response.StatusCode != 503 || body["error"].(map[string]any)["code"] != "SERVICE_UNAVAILABLE" || strings.Contains(raw, "private_user") || response.Header.Get("Session-Expires-At") != "" {
				t.Fatalf("unsafe authority response: %d %v", response.StatusCode, body)
			}
		})
	}
}

func TestCredentialHTTPCORSChangeHeaderIsRestrictedToRemovalAndResult(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCredentials(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		path, method string
		status       int
	}{
		{httpTestRemovalPath(), "DELETE", 204},
		{"/api/v1/auth/credential-change-result", "GET", 204},
		{"/api/v1/auth/passkeys", "POST", 400},
		{"/api/v1/auth/session", "GET", 400},
	} {
		response, _, _ := doHTTPTest(t, client, "OPTIONS", server.URL+test.path, "", map[string][]string{
			"Origin": {"https://client.hnuhole.test"}, "Access-Control-Request-Method": {test.method},
			"Access-Control-Request-Headers": {"authorization, idempotency-key, credential-change-id"},
		})
		if response.StatusCode != test.status {
			t.Fatalf("mis-scoped CORS header: %s status=%d", test.path, response.StatusCode)
		}
		if test.status == 204 && (response.Header.Get("Access-Control-Allow-Methods") != test.method || response.Header.Get("Access-Control-Allow-Origin") != "https://client.hnuhole.test") {
			t.Fatal("preflight did not expose fixed allowed origin/method")
		}
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 0 {
		t.Fatal("preflight reached authority")
	}
}

func TestCredentialHTTPUsesIndependentNetworkBudgetsBeforeAuthority(t *testing.T) {
	backend, _, pki := newHTTPTestCredentials(t)
	community := &httpTestCommunity{}
	limits := httpTestLimits()
	limits.MutationCapacity, limits.QueryCapacity = 1, 1
	endpoints, err := NewCommunityEndpoints(CommunityOptions{Backend: community, Credentials: backend, Passwords: httpTestPasswords{backend: community},
		InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: limits})
	if err != nil {
		t.Fatal(err)
	}
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		method, path, body string
		status             int
	}{
		{"POST", "/api/v1/auth/passkey-reset-options", `{}`, 200},
		{"POST", "/api/v1/auth/passkey-reset-options", `{}`, 429},
		{"GET", "/api/v1/auth/recovery-credentials", "", 200},
		{"GET", "/api/v1/auth/recovery-credentials", "", 429},
	} {
		response, body, _ := doHTTPTest(t, client, test.method, server.URL+test.path, test.body, httpTestCredentialHeaders(test.path))
		if response.StatusCode != test.status {
			t.Fatalf("independent budget: got=%d want=%d", response.StatusCode, test.status)
		}
		if test.status == 429 && (body["error"].(map[string]any)["code"] != "RATE_LIMITED" || response.Header.Get("Retry-After") == "" || response.Header.Get("Session-Expires-At") != "") {
			t.Fatal("network limit did not fail before session authorization")
		}
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 2 {
		t.Fatal("rate-limited request reached authority")
	}
}

type httpTestAutomaticCredentials struct {
	*httpTestCommunity
	*httpTestCredentials
}

func TestCredentialHTTPUsesBackendCredentialInterfaceByDefault(t *testing.T) {
	backend, _, pki := newHTTPTestCredentials(t)
	community := &httpTestCommunity{}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{Backend: &httpTestAutomaticCredentials{community, backend},
		Passwords: httpTestPasswords{backend: community}, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: httpTestLimits()})
	if err != nil {
		t.Fatal(err)
	}
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	response, _, _ := doHTTPTest(t, client, "GET", server.URL+"/api/v1/auth/recovery-credentials", "", httpTestCredentialHeaders("/api/v1/auth/recovery-credentials"))
	if response.StatusCode != 200 {
		t.Fatal("default Community interface did not wire credential service")
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 1 {
		t.Fatal("default credential interface not called")
	}
}
