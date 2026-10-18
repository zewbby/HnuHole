package authprivacyhttp

import (
	"context"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type httpTestModerationAccess struct{ calls int }

func (s *httpTestModerationAccess) CreateModerationAccessSession(context.Context, authprivacy.ModerationAccessRequest, authprivacy.PasswordVerifier) (authprivacy.ModerationAccessResult, error) {
	s.calls++
	return authprivacy.ModerationAccessResult{SessionToken: [32]byte{9}, Subject: [32]byte{10}, ExpiresAt: time.Now().UTC().Add(time.Hour)}, nil
}
func (s *httpTestModerationAccess) RevokeModerationAccessSession(context.Context, [32]byte) error {
	s.calls++
	return nil
}

func TestModerationAccessHTTPBoundary(t *testing.T) {
	pki := newHTTPTestPKI(t)
	backend := &httpTestCommunity{}
	access := &httpTestModerationAccess{}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{Backend: backend, ModerationAccess: access, Passwords: httpTestPasswords{backend: backend}, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: httpTestLimits()})
	if err != nil {
		t.Fatal(err)
	}
	server, client := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	path := server.URL + "/api/v1/moderation-access/sessions"
	for _, body := range []string{`{"username":"test_user","password":"a","accountId":"injected"}`, `{"username":"test_user","username":"other_user","password":"a"}`} {
		response, _, _ := doHTTPTest(t, client, "POST", path, body, map[string][]string{"Content-Type": {"application/json"}})
		if response.StatusCode != 400 {
			t.Fatalf("ambiguous restricted login accepted: %d", response.StatusCode)
		}
	}
	response, _, _ := doHTTPTest(t, client, "GET", path, "", nil)
	if response.StatusCode != 405 {
		t.Fatalf("wrong method accepted: %d", response.StatusCode)
	}
	if access.calls != 0 {
		t.Fatal("invalid requests reached restricted login")
	}
	response, body, _ := doHTTPTest(t, client, "POST", path, `{"username":"test_user","password":"a"}`, map[string][]string{"Content-Type": {"application/json"}})
	wantSubject := [32]byte{10}
	if response.StatusCode != 201 || len(body) != 4 || body["scope"] != "MODERATION_SELF" || body["moderationSubject"] != protocol.EncodeCanonicalBase64url(wantSubject[:]) || body["accountId"] != nil || response.Header.Get("Session-Expires-At") == "" {
		t.Fatalf("restricted login contract leaked account or lacked scope: %d %+v", response.StatusCode, body)
	}
	response, _, _ = doHTTPTest(t, client, "POST", server.URL+"/api/v1/moderation-access/session-revocations", "", map[string][]string{"Authorization": {"Bearer " + httpTestEncoding(32, 9)}})
	if response.StatusCode != 204 || access.calls != 2 {
		t.Fatal("restricted logout contract failed")
	}
}
