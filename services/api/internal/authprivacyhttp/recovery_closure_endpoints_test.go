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
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

// The fake controls authority results while these tests cross the real HTTPS,
// header parsing, JSON validation and response serialization boundary.
type httpTestRecoveryClosures struct {
	mu           sync.Mutex
	calls        int
	err          error
	intent       authprivacy.PasswordResetIntent
	resetState   string
	accepted     authprivacy.ClosureAccepted
	closureState authprivacy.ClosureStatus
	lastCode     string
	lastReset    authprivacy.PasswordResetRequest
	lastClosure  authprivacy.ClosureRequest
	lastKey      [32]byte
	lastID       [32]byte
	lastSecret   [32]byte
}

func (f *httpTestRecoveryClosures) CreateRecoveryCodeResetIntent(_ context.Context, code string) (authprivacy.PasswordResetIntent, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.lastCode = code
	return f.intent, f.err
}

func (f *httpTestRecoveryClosures) CommitPasswordReset(_ context.Context, request authprivacy.PasswordResetRequest, _ authprivacy.PasswordProcessor) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.lastReset = request
	return f.err
}

func (f *httpTestRecoveryClosures) GetPasswordResetResult(_ context.Context, key, id [32]byte) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.lastKey, f.lastID = key, id
	return f.resetState, f.err
}

func (f *httpTestRecoveryClosures) RequestAccountClosure(_ context.Context, request authprivacy.ClosureRequest, _ authprivacy.PasswordVerifier) (authprivacy.ClosureAccepted, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.lastClosure = request
	return f.accepted, f.err
}

func (f *httpTestRecoveryClosures) GetAccountClosureStatus(_ context.Context, id, secret [32]byte) (authprivacy.ClosureStatus, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.lastID, f.lastSecret = id, secret
	return f.closureState, f.err
}

func httpTestRecoveryCapability(value byte) [32]byte {
	var result [32]byte
	for i := range result {
		result[i] = value
	}
	return result
}

func newHTTPTestRecoveryClosures(t *testing.T) (*httpTestRecoveryClosures, *Endpoints, *httpTestPKI) {
	t.Helper()
	pki := newHTTPTestPKI(t)
	community := &httpTestCommunity{}
	due := time.Date(2026, 10, 7, 4, 5, 6, 0, time.UTC)
	backend := &httpTestRecoveryClosures{
		intent: authprivacy.PasswordResetIntent{ID: httpTestRecoveryCapability(6), ExpiresAt: due,
			Username: "private_user", NewRecoveryCode: httpTestCode()},
		resetState:   "COMMITTED",
		accepted:     authprivacy.ClosureAccepted{ID: httpTestRecoveryCapability(6), DueAt: due},
		closureState: authprivacy.ClosureStatus{State: "PENDING", DueAt: &due},
	}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{Backend: community, Recovery: backend, Closures: backend,
		Passwords:    httpTestPasswords{backend: community},
		InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: httpTestLimits()})
	if err != nil {
		t.Fatal(err)
	}
	return backend, endpoints, pki
}

func httpTestRecoveryHeaders(path string) map[string][]string {
	headers := make(map[string][]string)
	switch {
	case path == "/api/v1/auth/recovery-code-reset-intents":
		headers["Content-Type"] = []string{"application/json"}
	case path == "/api/v1/auth/password-resets":
		headers["Content-Type"] = []string{"application/json"}
		headers["Idempotency-Key"] = []string{httpTestEncoding(32, 7)}
	case path == "/api/v1/auth/password-reset-result":
		headers["Authorization"] = []string{"ResetResult " + httpTestEncoding(32, 7)}
		headers["Reset-Intent-ID"] = []string{httpTestEncoding(32, 6)}
	case path == "/api/v1/account-closures":
		headers["Content-Type"] = []string{"application/json"}
		headers["Authorization"] = []string{"Bearer " + httpTestEncoding(32, 8)}
	default:
		headers["Authorization"] = []string{"ClosureStatus " + httpTestEncoding(32, 9)}
	}
	return headers
}

func httpTestPasswordResetBody() string {
	return `{"resetIntentId":"` + httpTestEncoding(32, 6) + `","newPassword":"new private phrase","newRecoveryCodeConfirmation":"` + httpTestCode() + `"}`
}

func httpTestClosureBody() string {
	return `{"password":"current private phrase","closureId":"` + httpTestEncoding(32, 6) + `","statusDigest":"` + httpTestEncoding(32, 9) + `"}`
}

func TestRecoveryClosureHTTPRejectsDuplicateNullAndUnknownMutationFields(t *testing.T) {
	backend, endpoints, pki := newHTTPTestRecoveryClosures(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		name, path, body string
	}{
		{"recovery duplicate", "/api/v1/auth/recovery-code-reset-intents", `{"recoveryCode":"` + httpTestCode() + `","recoveryCode":"` + httpTestCode() + `"}`},
		{"recovery escaped duplicate", "/api/v1/auth/recovery-code-reset-intents", `{"recoveryCode":"` + httpTestCode() + `","\u0072ecoveryCode":"` + httpTestCode() + `"}`},
		{"recovery null", "/api/v1/auth/recovery-code-reset-intents", `{"recoveryCode":null}`},
		{"recovery unknown", "/api/v1/auth/recovery-code-reset-intents", `{"recoveryCode":"` + httpTestCode() + `","accountId":"private"}`},
		{"reset duplicate", "/api/v1/auth/password-resets", strings.TrimSuffix(httpTestPasswordResetBody(), "}") + `,"newPassword":"other phrase"}`},
		{"reset null", "/api/v1/auth/password-resets", strings.Replace(httpTestPasswordResetBody(), `"new private phrase"`, `null`, 1)},
		{"reset unknown", "/api/v1/auth/password-resets", strings.TrimSuffix(httpTestPasswordResetBody(), "}") + `,"username":"private_user"}`},
		{"closure duplicate", "/api/v1/account-closures", strings.TrimSuffix(httpTestClosureBody(), "}") + `,"closureId":"` + httpTestEncoding(32, 6) + `"}`},
		{"closure null", "/api/v1/account-closures", strings.Replace(httpTestClosureBody(), `"current private phrase"`, `null`, 1)},
		{"closure unknown", "/api/v1/account-closures", strings.TrimSuffix(httpTestClosureBody(), "}") + `,"accountId":"private"}`},
	} {
		t.Run(test.name, func(t *testing.T) {
			response, body, _ := doHTTPTest(t, client, "POST", server.URL+test.path, test.body, httpTestRecoveryHeaders(test.path))
			if response.StatusCode != 400 || body["error"].(map[string]any)["code"] != "MALFORMED_REQUEST" {
				t.Fatalf("ambiguous mutation accepted: status=%d body=%v", response.StatusCode, body)
			}
		})
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 0 {
		t.Fatal("invalid mutation reached authority backend")
	}
}

func TestRecoveryClosureHTTPRejectsMisScopedAndNoncanonicalCapabilities(t *testing.T) {
	backend, endpoints, pki := newHTTPTestRecoveryClosures(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	statusPath := "/api/v1/account-closures/" + httpTestEncoding(32, 6)
	for _, test := range []struct {
		name, method, path, body string
		change                   func(map[string][]string)
		status                   int
	}{
		{"recovery forbids authorization", "POST", "/api/v1/auth/recovery-code-reset-intents", `{"recoveryCode":"` + httpTestCode() + `"}`, func(h map[string][]string) { h["Authorization"] = []string{"Bearer " + httpTestEncoding(32, 8)} }, 400},
		{"recovery forbids idempotency", "POST", "/api/v1/auth/recovery-code-reset-intents", `{"recoveryCode":"` + httpTestCode() + `"}`, func(h map[string][]string) { h["Idempotency-Key"] = []string{httpTestEncoding(32, 7)} }, 400},
		{"reset forbids authorization", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), func(h map[string][]string) { h["Authorization"] = []string{"ResetResult " + httpTestEncoding(32, 7)} }, 400},
		{"reset missing key", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), func(h map[string][]string) { delete(h, "Idempotency-Key") }, 400},
		{"reset duplicate key", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), func(h map[string][]string) {
			h["Idempotency-Key"] = []string{httpTestEncoding(32, 7), httpTestEncoding(32, 7)}
		}, 400},
		{"reset padded key", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), func(h map[string][]string) { h["Idempotency-Key"] = []string{httpTestEncoding(32, 7) + "="} }, 400},
		{"reset short key", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), func(h map[string][]string) { h["Idempotency-Key"] = []string{httpTestEncoding(31, 7)} }, 400},
		{"reset padded intent", "POST", "/api/v1/auth/password-resets", strings.Replace(httpTestPasswordResetBody(), httpTestEncoding(32, 6), httpTestEncoding(32, 6)+"=", 1), nil, 400},
		{"reset short intent", "POST", "/api/v1/auth/password-resets", strings.Replace(httpTestPasswordResetBody(), httpTestEncoding(32, 6), httpTestEncoding(31, 6), 1), nil, 400},
		{"result wrong scheme", "GET", "/api/v1/auth/password-reset-result", "", func(h map[string][]string) { h["Authorization"] = []string{"Bearer " + httpTestEncoding(32, 7)} }, 401},
		{"result duplicate authorization", "GET", "/api/v1/auth/password-reset-result", "", func(h map[string][]string) {
			h["Authorization"] = []string{"ResetResult " + httpTestEncoding(32, 7), "ResetResult " + httpTestEncoding(32, 7)}
		}, 401},
		{"result missing intent", "GET", "/api/v1/auth/password-reset-result", "", func(h map[string][]string) { delete(h, "Reset-Intent-ID") }, 400},
		{"result duplicate intent", "GET", "/api/v1/auth/password-reset-result", "", func(h map[string][]string) {
			h["Reset-Intent-ID"] = []string{httpTestEncoding(32, 6), httpTestEncoding(32, 6)}
		}, 400},
		{"result padded intent", "GET", "/api/v1/auth/password-reset-result", "", func(h map[string][]string) { h["Reset-Intent-ID"] = []string{httpTestEncoding(32, 6) + "="} }, 400},
		{"closure missing bearer", "POST", "/api/v1/account-closures", httpTestClosureBody(), func(h map[string][]string) { delete(h, "Authorization") }, 401},
		{"closure wrong scheme", "POST", "/api/v1/account-closures", httpTestClosureBody(), func(h map[string][]string) { h["Authorization"] = []string{"ClosureStatus " + httpTestEncoding(32, 8)} }, 401},
		{"closure duplicate bearer", "POST", "/api/v1/account-closures", httpTestClosureBody(), func(h map[string][]string) {
			h["Authorization"] = []string{"Bearer " + httpTestEncoding(32, 8), "Bearer " + httpTestEncoding(32, 8)}
		}, 401},
		{"closure padded id", "POST", "/api/v1/account-closures", strings.Replace(httpTestClosureBody(), httpTestEncoding(32, 6), httpTestEncoding(32, 6)+"=", 1), nil, 400},
		{"closure short digest", "POST", "/api/v1/account-closures", strings.Replace(httpTestClosureBody(), httpTestEncoding(32, 9), httpTestEncoding(31, 9), 1), nil, 400},
		{"closure status wrong scheme", "GET", statusPath, "", func(h map[string][]string) { h["Authorization"] = []string{"Bearer " + httpTestEncoding(32, 9)} }, 401},
		{"closure status lowercase scheme", "GET", statusPath, "", func(h map[string][]string) { h["Authorization"] = []string{"closurestatus " + httpTestEncoding(32, 9)} }, 401},
		{"closure status padded secret", "GET", statusPath, "", func(h map[string][]string) {
			h["Authorization"] = []string{"ClosureStatus " + httpTestEncoding(32, 9) + "="}
		}, 400},
		{"closure status padded path", "GET", statusPath + "=", "", nil, 400},
		{"closure status short path", "GET", "/api/v1/account-closures/" + httpTestEncoding(31, 6), "", nil, 400},
	} {
		t.Run(test.name, func(t *testing.T) {
			headers := httpTestRecoveryHeaders(test.path)
			if test.change != nil {
				test.change(headers)
			}
			response, _, _ := doHTTPTest(t, client, test.method, server.URL+test.path, test.body, headers)
			if response.StatusCode != test.status {
				t.Fatalf("capability validation: got %d want %d", response.StatusCode, test.status)
			}
		})
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 0 {
		t.Fatal("mis-scoped or noncanonical capability reached authority backend")
	}
}

func TestRecoveryClosureHTTPRejectsUnexpectedBodiesQueriesAndKeys(t *testing.T) {
	backend, endpoints, pki := newHTTPTestRecoveryClosures(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	statusPath := "/api/v1/account-closures/" + httpTestEncoding(32, 6)
	for _, path := range []string{"/api/v1/auth/password-reset-result", statusPath} {
		for _, change := range []string{"body", "query", "empty query", "idempotency"} {
			t.Run(path+" "+change, func(t *testing.T) {
				headers := httpTestRecoveryHeaders(path)
				url, body := server.URL+path, ""
				switch change {
				case "body":
					body = `{}`
				case "query":
					url += "?accountId=private"
				case "empty query":
					url += "?"
				case "idempotency":
					headers["Idempotency-Key"] = []string{httpTestEncoding(32, 7)}
				}
				response, _, _ := doHTTPTest(t, client, "GET", url, body, headers)
				if response.StatusCode != 400 {
					t.Fatalf("unexpected GET input accepted: %d", response.StatusCode)
				}
			})
		}
	}
	headers := httpTestRecoveryHeaders("/api/v1/account-closures")
	headers["Idempotency-Key"] = []string{httpTestEncoding(32, 7)}
	response, _, _ := doHTTPTest(t, client, "POST", server.URL+"/api/v1/account-closures", httpTestClosureBody(), headers)
	if response.StatusCode != 400 {
		t.Fatal("closure unexpectedly accepted a submission idempotency key")
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 0 {
		t.Fatal("unexpected input reached authority backend")
	}
}

func TestRecoveryClosureHTTPSuccessResponsesAreMinimalAndScoped(t *testing.T) {
	backend, endpoints, pki := newHTTPTestRecoveryClosures(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	response, body, _ := doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/recovery-code-reset-intents",
		`{"recoveryCode":"`+httpTestCode()+`"}`, httpTestRecoveryHeaders("/api/v1/auth/recovery-code-reset-intents"))
	expectedIntent := map[string]any{"resetIntentId": httpTestEncoding(32, 6), "expiresAt": utc(backend.intent.ExpiresAt),
		"username": "private_user", "newRecoveryCode": httpTestCode()}
	if response.StatusCode != 201 || !reflect.DeepEqual(body, expectedIntent) || response.Header.Get("Session-Expires-At") != "" {
		t.Fatalf("recovery intent contract: status=%d body=%v", response.StatusCode, body)
	}
	response, _, raw := doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/password-resets", httpTestPasswordResetBody(),
		httpTestRecoveryHeaders("/api/v1/auth/password-resets"))
	if response.StatusCode != 204 || raw != "" || response.Header.Get("Session-Expires-At") != "" {
		t.Fatal("password reset did not return an empty non-session 204")
	}
	response, body, _ = doHTTPTest(t, client, "POST", server.URL+"/api/v1/account-closures", httpTestClosureBody(),
		httpTestRecoveryHeaders("/api/v1/account-closures"))
	expectedClosure := map[string]any{"closureId": httpTestEncoding(32, 6), "dueAt": utc(backend.accepted.DueAt)}
	if response.StatusCode != 202 || !reflect.DeepEqual(body, expectedClosure) || response.Header.Get("Session-Expires-At") != "" {
		t.Fatalf("closure acceptance contract: status=%d body=%v", response.StatusCode, body)
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.lastCode != httpTestCode() || backend.lastReset.IntentID != httpTestRecoveryCapability(6) ||
		backend.lastReset.IdempotencyKey != httpTestRecoveryCapability(7) || backend.lastReset.NewPassword != "new private phrase" ||
		backend.lastReset.NewRecoveryCodeConfirmation != httpTestCode() || backend.lastClosure.Bearer != httpTestRecoveryCapability(8) ||
		backend.lastClosure.ID != httpTestRecoveryCapability(6) || backend.lastClosure.StatusDigest != httpTestRecoveryCapability(9) ||
		backend.lastClosure.Password != "current private phrase" {
		t.Fatal("validated request fields were not preserved for authoritative verification")
	}
}

func TestPasswordResetResultHTTPOnlyReturnsDecisionState(t *testing.T) {
	backend, endpoints, pki := newHTTPTestRecoveryClosures(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		state  string
		status int
		retry  string
	}{{"COMMITTED", 200, ""}, {"NOT_COMMITTED", 200, ""}, {"PENDING", 202, "2"}} {
		t.Run(test.state, func(t *testing.T) {
			backend.mu.Lock()
			backend.resetState = test.state
			backend.mu.Unlock()
			response, body, _ := doHTTPTest(t, client, "GET", server.URL+"/api/v1/auth/password-reset-result", "",
				httpTestRecoveryHeaders("/api/v1/auth/password-reset-result"))
			if response.StatusCode != test.status || !reflect.DeepEqual(body, map[string]any{"state": test.state}) ||
				response.Header.Get("Retry-After") != test.retry || response.Header.Get("Session-Expires-At") != "" {
				t.Fatalf("reset result leaked or changed decision contract: status=%d body=%v", response.StatusCode, body)
			}
		})
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.lastKey != httpTestRecoveryCapability(7) || backend.lastID != httpTestRecoveryCapability(6) {
		t.Fatal("reset result capability was not bound to its intent header")
	}
}

func TestClosureStatusHTTPOnlyReturnsStateDeadlineAndReceipt(t *testing.T) {
	backend, endpoints, pki := newHTTPTestRecoveryClosures(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	due := backend.accepted.DueAt
	receipt, err := (protocol.Receipt{Purpose: protocol.PurposeReleased, Epoch: 1, Slot: protocol.SlotID{3}}).Encode()
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name     string
		status   authprivacy.ClosureStatus
		expected map[string]any
	}{
		{"pending", authprivacy.ClosureStatus{State: "PENDING", DueAt: &due}, map[string]any{"state": "PENDING", "dueAt": utc(due)}},
		{"finalizing", authprivacy.ClosureStatus{State: "FINALIZING", DueAt: &due}, map[string]any{"state": "FINALIZING", "dueAt": utc(due)}},
		{"cancelled", authprivacy.ClosureStatus{State: "CANCELLED"}, map[string]any{"state": "CANCELLED"}},
		{"awaiting release", authprivacy.ClosureStatus{State: "CLOSED_RELEASE_PENDING"}, map[string]any{"state": "CLOSED_RELEASE_PENDING"}},
		{"release awaiting acknowledgement", authprivacy.ClosureStatus{State: "CLOSED_RELEASE_PENDING", ReleaseReceipt: receipt}, map[string]any{"state": "CLOSED_RELEASE_PENDING", "releaseReceipt": receipt}},
		{"released", authprivacy.ClosureStatus{State: "RELEASED", ReleaseReceipt: receipt}, map[string]any{"state": "RELEASED", "releaseReceipt": receipt}},
	} {
		t.Run(test.name, func(t *testing.T) {
			backend.mu.Lock()
			backend.closureState = test.status
			backend.mu.Unlock()
			response, body, _ := doHTTPTest(t, client, "GET", server.URL+"/api/v1/account-closures/"+httpTestEncoding(32, 6), "",
				httpTestRecoveryHeaders("/api/v1/account-closures/status"))
			if response.StatusCode != 200 || !reflect.DeepEqual(body, test.expected) || response.Header.Get("Session-Expires-At") != "" {
				t.Fatalf("closure status contract: status=%d body=%v", response.StatusCode, body)
			}
		})
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.lastID != httpTestRecoveryCapability(6) || backend.lastSecret != httpTestRecoveryCapability(9) {
		t.Fatal("closure status capability was not bound to its canonical path ID")
	}
}

func TestRecoveryClosureHTTPAuthorityErrorsRemainSafe(t *testing.T) {
	backend, endpoints, pki := newHTTPTestRecoveryClosures(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		name, method, path, body, code string
		err                            error
		status                         int
	}{
		{"invalid proof", "POST", "/api/v1/auth/recovery-code-reset-intents", `{"recoveryCode":"` + httpTestCode() + `"}`, "AUTHENTICATION_FAILED", authprivacy.ErrRecoveryProofInvalid, 401},
		{"changed intent", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), "INTENT_INVALID", authprivacy.ErrResetIntentInvalid, 409},
		{"expired intent", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), "INTENT_EXPIRED", authprivacy.ErrResetIntentExpired, 410},
		{"password policy", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), "PASSWORD_POLICY_FAILED", authprivacy.ErrPasswordPolicy, 422},
		{"idempotency conflict", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), "IDEMPOTENCY_KEY_REUSED", authprivacy.ErrConflict, 409},
		{"expired result", "GET", "/api/v1/auth/password-reset-result", "", "RESULT_EXPIRED", authprivacy.ErrExpired, 410},
		{"unknown result", "GET", "/api/v1/auth/password-reset-result", "", "RESOURCE_NOT_FOUND", authprivacy.ErrResetResultNotFound, 404},
		{"frozen gate", "POST", "/api/v1/account-closures", httpTestClosureBody(), "SERVICE_UNAVAILABLE", authprivacy.ErrAuthorizationUnavailable, 503},
		{"invalid session", "POST", "/api/v1/account-closures", httpTestClosureBody(), "SESSION_INVALID", authprivacy.ErrSessionInvalid, 401},
		{"account unavailable", "POST", "/api/v1/account-closures", httpTestClosureBody(), "ACCOUNT_UNAVAILABLE", authprivacy.ErrAccountUnavailable, 403},
		{"unknown closure", "GET", "/api/v1/account-closures/" + httpTestEncoding(32, 6), "", "RESOURCE_NOT_FOUND", authprivacy.ErrClosureNotFound, 404},
		{"unexpected authority failure", "POST", "/api/v1/auth/password-resets", httpTestPasswordResetBody(), "SERVICE_UNAVAILABLE", errors.New("private authority fault"), 503},
	} {
		t.Run(test.name, func(t *testing.T) {
			backend.mu.Lock()
			backend.err = fmt.Errorf("%w: private_user secret-password database-secret", test.err)
			backend.mu.Unlock()
			response, body, raw := doHTTPTest(t, client, test.method, server.URL+test.path, test.body, httpTestRecoveryHeaders(test.path))
			public, ok := body["error"].(map[string]any)
			if response.StatusCode != test.status || !ok || public["code"] != test.code || len(body) != 2 || len(public) != 2 ||
				body["requestId"] != response.Header.Get("X-Request-ID") || strings.Contains(raw, "private_user") ||
				strings.Contains(raw, "secret-password") || strings.Contains(raw, "database-secret") {
				t.Fatalf("unsafe authority error mapping: status=%d body=%v", response.StatusCode, body)
			}
		})
	}
}

func TestRecoveryClosureHTTPRejectsImpossibleAuthorityResponses(t *testing.T) {
	backend, endpoints, pki := newHTTPTestRecoveryClosures(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, test := range []struct {
		name, method, path, body string
		change                   func()
	}{
		{"empty recovery capability", "POST", "/api/v1/auth/recovery-code-reset-intents", `{"recoveryCode":"` + httpTestCode() + `"}`, func() { backend.intent.ID = [32]byte{} }},
		{"reset unknown state", "GET", "/api/v1/auth/password-reset-result", "", func() { backend.resetState = "SECRET_STATE" }},
		{"closure mismatched id", "POST", "/api/v1/account-closures", httpTestClosureBody(), func() { backend.accepted.ID = httpTestRecoveryCapability(4) }},
		{"released missing receipt", "GET", "/api/v1/account-closures/" + httpTestEncoding(32, 6), "", func() { backend.closureState = authprivacy.ClosureStatus{State: "RELEASED"} }},
		{"pending missing deadline", "GET", "/api/v1/account-closures/" + httpTestEncoding(32, 6), "", func() { backend.closureState = authprivacy.ClosureStatus{State: "PENDING"} }},
		{"cancelled exposes deadline", "GET", "/api/v1/account-closures/" + httpTestEncoding(32, 6), "", func() {
			due := backend.accepted.DueAt
			backend.closureState = authprivacy.ClosureStatus{State: "CANCELLED", DueAt: &due}
		}},
		{"released malformed receipt", "GET", "/api/v1/account-closures/" + httpTestEncoding(32, 6), "", func() {
			backend.closureState = authprivacy.ClosureStatus{State: "RELEASED", ReleaseReceipt: "private-secret"}
		}},
	} {
		t.Run(test.name, func(t *testing.T) {
			backend.mu.Lock()
			test.change()
			backend.mu.Unlock()
			response, body, raw := doHTTPTest(t, client, test.method, server.URL+test.path, test.body, httpTestRecoveryHeaders(test.path))
			if response.StatusCode != 503 || body["error"].(map[string]any)["code"] != "SERVICE_UNAVAILABLE" ||
				strings.Contains(raw, "private-secret") || strings.Contains(raw, "SECRET_STATE") {
				t.Fatalf("impossible authority response was exposed: status=%d body=%v", response.StatusCode, body)
			}
		})
	}
}

func TestRecoveryClosureHTTPDoesNotExposeAdministrativeRoutes(t *testing.T) {
	backend, endpoints, pki := newHTTPTestRecoveryClosures(t)
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	for _, path := range []string{"/internal/v1/password-resets", "/internal/v1/account-closures", "/api/v1/account-closures/finalize"} {
		response, _, _ := doHTTPTest(t, client, "POST", server.URL+path, `{}`, map[string][]string{"Content-Type": {"application/json"}})
		if response.StatusCode != 404 && response.StatusCode != 405 {
			t.Fatalf("administrative route exposed: %s status=%d", path, response.StatusCode)
		}
	}
	serverCertificate := pki.issue(t, "lab", CommunityService, nil)
	internalTLS, err := InternalTLSConfig(serverCertificate, PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots})
	if err != nil {
		t.Fatal(err)
	}
	internalServer := startHTTPTestTLS(t, endpoints.Internal, internalTLS)
	peerCertificate := pki.issue(t, "lab", VerifierService, nil)
	internalClient := httpTestClient(pki.roots, &peerCertificate)
	for _, path := range []string{"/api/v1/auth/recovery-code-reset-intents", "/api/v1/auth/password-resets", "/api/v1/account-closures", "/internal/v1/password-resets", "/internal/v1/account-closures"} {
		response, _, _ := doHTTPTest(t, internalClient, "POST", internalServer.URL+path, `{}`, map[string][]string{"Content-Type": {"application/json"}})
		if response.StatusCode != 404 {
			t.Fatalf("internal handler exposed recovery or closure route: %s status=%d", path, response.StatusCode)
		}
	}
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if backend.calls != 0 {
		t.Fatal("administrative or internal route reached public authority backend")
	}
}
