package authprivacyhttp

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

type httpTestSessions struct {
	calls int
	view  authprivacy.SessionView
}

func (s *httpTestSessions) CreateSession(context.Context, authprivacy.SessionCreateRequest, authprivacy.PasswordVerifier) (authprivacy.SessionCreateResult, error) {
	s.calls++
	return authprivacy.SessionCreateResult{AccountID: s.view.AccountID, SessionToken: [32]byte{5}, ExpiresAt: s.view.ExpiresAt}, nil
}
func (s *httpTestSessions) GetCurrentSession(context.Context, [32]byte) (authprivacy.SessionView, error) {
	s.calls++
	return s.view, nil
}
func (s *httpTestSessions) RenewCurrentSession(context.Context, [32]byte) (time.Time, error) {
	s.calls++
	return s.view.ExpiresAt, nil
}
func (s *httpTestSessions) GetDevices(context.Context, [32]byte) (authprivacy.SessionView, error) {
	s.calls++
	return s.view, nil
}
func (s *httpTestSessions) RevokeSession(context.Context, [32]byte) error {
	s.calls++
	return nil
}

func TestSessionHTTPRejectsAmbiguousCapabilitiesAndBodies(t *testing.T) {
	pki := newHTTPTestPKI(t)
	backend := &httpTestCommunity{}
	sessions := &httpTestSessions{view: authprivacy.SessionView{
		AccountID: uuid.New(), Username: "fake_user", SignedInAt: time.Now().UTC(), ExpiresAt: time.Now().Add(30 * 24 * time.Hour),
	}}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{Backend: backend, Sessions: sessions,
		Passwords:    httpTestPasswords{backend: backend},
		InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: httpTestLimits()})
	if err != nil {
		t.Fatal(err)
	}
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	key := httpTestEncoding(32, 7)
	token := httpTestEncoding(32, 8)
	installation := httpTestEncoding(16, 9)
	for _, test := range []struct {
		method, path, body string
		headers            map[string][]string
		status             int
	}{
		{"POST", "/api/v1/auth/sessions", `{"username":"fake_user","username":"other_user","password":"valid phrase","installationId":"` + installation + `"}`, map[string][]string{"Content-Type": {"application/json"}, "Idempotency-Key": {key}}, 400},
		{"POST", "/api/v1/auth/sessions", `{"username":"fake_user","password":"valid phrase","installationId":"` + installation + `"}`, map[string][]string{"Content-Type": {"application/json"}, "Idempotency-Key": {key}, "Authorization": {"Bearer " + token}}, 400},
		{"GET", "/api/v1/auth/session", "", map[string][]string{"Authorization": {"Bearer " + token, "Bearer " + token}}, 401},
		{"GET", "/api/v1/auth/session", "", map[string][]string{"Authorization": {"Bearer " + token + "="}}, 400},
		{"POST", "/api/v1/auth/session-renewals", `{}`, map[string][]string{"Authorization": {"Bearer " + token}}, 400},
		{"POST", "/api/v1/auth/session-revocations", "", map[string][]string{"Authorization": {"Bearer " + token}}, 401},
		{"GET", "/api/v1/auth/devices?include=all", "", map[string][]string{"Authorization": {"Bearer " + token}}, 400},
	} {
		response, _, _ := doHTTPTest(t, client, test.method, server.URL+test.path, test.body, test.headers)
		if response.StatusCode != test.status {
			t.Fatalf("%s %s: got %d want %d", test.method, test.path, response.StatusCode, test.status)
		}
	}
	if sessions.calls != 0 {
		t.Fatal("malformed requests reached the session backend")
	}
	response, body, _ := doHTTPTest(t, client, "GET", server.URL+"/api/v1/auth/session", "", map[string][]string{"Authorization": {"Bearer " + token}})
	if response.StatusCode != http.StatusOK || body["username"] != "fake_user" || response.Header.Get("Session-Expires-At") == "" {
		t.Fatal("valid bearer response did not match the session contract")
	}
	response, _, raw := doHTTPTest(t, client, "POST", server.URL+"/api/v1/auth/session-revocations", "", map[string][]string{"Authorization": {"SessionRevoke " + token}})
	if response.StatusCode != http.StatusNoContent || raw != "" {
		t.Fatal("valid revocation did not return empty 204")
	}
}
