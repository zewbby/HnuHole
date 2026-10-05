package authprivacyhttp

import (
	"errors"
	"net/http"
	"strings"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

// This exercises the production HTTP boundary and peer transport in both
// directions. The small handlers substitute business work, not TLS or headers.
func TestPrivacyBoundaryDoesNotJoinPublicAndPeerDiagnostics(t *testing.T) {
	for _, source := range []Service{CommunityService, VerifierService} {
		t.Run(string(source), func(t *testing.T) {
			pki := newHTTPTestPKI(t)
			target := opposite(source)
			publicBoundary, err := newBoundary(source, PeerIdentity{Environment: "lab", Service: target, Roots: pki.roots}, nil, httpTestLimits())
			if err != nil {
				t.Fatal(err)
			}
			internalBoundary, err := newBoundary(target, PeerIdentity{Environment: "lab", Service: source, Roots: pki.roots}, nil, httpTestLimits())
			if err != nil {
				t.Fatal(err)
			}
			peerIDs := make(chan string, 2)
			path, field := "/internal/v1/slot-releases", "releaseReceipt"
			material := httpTestReceipt(t, protocol.PurposeReleased, protocol.SlotID{3})
			if target == CommunityService {
				path, field = "/internal/v1/slot-retirements", "retirementAuthorization"
				material = protocol.Authorization{Epoch: 1, Slot: protocol.SlotID{3}}.Encode()
			}
			peer := newHTTPTestPeer(t, pki, target, internalBoundary.wrap(true, func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost || r.URL.Path != path {
					t.Error("peer command changed route")
				}
				for _, name := range []string{"Authorization", "Idempotency-Key", "V-Installation-ID", "OTP-Flow-ID", "X-Request-ID", "X-Correlation-ID", "X-Client-ID", "Traceparent", "Tracestate", "Baggage", "X-Forwarded-For", "Forwarded"} {
					if hasHeader(r.Header, name) {
						t.Errorf("peer received client linkage header %s", name)
					}
				}
				body, err := parseObject(r.Body, 1024)
				if err != nil || fields(body, []string{field}, nil) != nil || body[field] != material {
					t.Error("peer received nonminimal command")
				}
				peerIDs <- w.Header().Get("X-Request-ID")
				if target == VerifierService {
					writeJSON(w, 200, struct {
						State string `json:"state"`
					}{"ACKNOWLEDGED"})
				} else {
					writeJSON(w, 200, struct {
						Receipt string `json:"retirementReceipt"`
					}{httpTestReceipt(t, protocol.PurposeRetired, protocol.SlotID{3})})
				}
			}))
			public, client := httpTestPublicServer(t, publicBoundary.wrap(false, func(w http.ResponseWriter, r *http.Request) {
				for _, name := range []string{"X-Request-ID", "X-Correlation-ID", "X-Client-ID", "Traceparent", "Tracestate", "Baggage"} {
					if hasHeader(r.Header, name) {
						t.Errorf("application retained linkage header %s", name)
					}
				}
				var err error
				if target == VerifierService {
					err = peer.ReceiveReceipt(r.Context(), material, protocol.PurposeReleased)
				} else {
					_, err = peer.RetireUnusedSlot(r.Context(), material)
				}
				if err != nil {
					publicBoundary.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
					return
				}
				writeJSON(w, 200, struct {
					State string `json:"state"`
				}{"COMPLETED"})
			}), pki, source)
			inbound := httpTestEncoding(16, 88)
			headers := map[string][]string{
				"X-Request-ID": {inbound}, "X-Correlation-ID": {"same-client-correlation"}, "X-Client-ID": {"same-client-identifier"},
				"Traceparent": {"00-0123456789abcdef0123456789abcdef-0123456789abcdef-01"}, "Tracestate": {"vendor=private"}, "Baggage": {"email=private"},
				"Authorization": {"Bearer " + httpTestEncoding(32, 9)}, "Idempotency-Key": {httpTestEncoding(32, 10)}, "V-Installation-ID": {httpTestEncoding(16, 11)},
				"X-Forwarded-For": {"192.0.2.45"}, "Forwarded": {"for=192.0.2.45"},
			}
			seen := map[string]bool{inbound: true}
			for i := 0; i < 2; i++ {
				response, body, raw := doHTTPTest(t, client, http.MethodPost, public.URL+"/privacy-test", "", headers)
				if response.StatusCode != 200 || len(body) != 1 || body["state"] != "COMPLETED" {
					t.Fatal("public peer round trip failed")
				}
				for _, id := range []string{response.Header.Get("X-Request-ID"), <-peerIDs} {
					if _, err := protocol.DecodeCanonicalBase64url(id, 16); err != nil || seen[id] {
						t.Fatal("diagnostic ID joined a client, peer, or earlier request")
					}
					seen[id] = true
				}
				if strings.Contains(raw, material) || strings.Contains(raw, "private") {
					t.Fatal("peer or trace material returned publicly")
				}
			}
		})
	}
}

func TestPrivacyBoundaryErrorsNeverEchoSensitiveInputs(t *testing.T) {
	for _, service := range []Service{CommunityService, VerifierService} {
		t.Run(string(service), func(t *testing.T) {
			pki := newHTTPTestPKI(t)
			var endpoints *Endpoints
			var err error
			path, body := "/api/v1/eligibility/otp-requests", `{"email":"private-canary@hainanu.edu.cn"}`
			headers := httpTestVHeaders()
			canary := "private-canary@hainanu.edu.cn raw-database-password private-slot-owner"
			if service == VerifierService {
				eligibility := &httpTestEligibility{requestError: errors.New(canary)}
				endpoints, err = NewVerifierEndpoints(VerifierOptions{Eligibility: eligibility, Receipts: &httpTestReceipts{}, InternalPeer: PeerIdentity{Environment: "lab", Service: CommunityService, Roots: pki.roots}, Limits: httpTestLimits()})
			} else {
				backend := &httpTestCommunity{validateError: errors.New(canary)}
				endpoints, err = NewCommunityEndpoints(CommunityOptions{Backend: backend, Passwords: httpTestPasswords{backend: backend}, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: httpTestLimits()})
				path = "/api/v1/auth/registration-intents"
				body = `{"registrationTicket":"` + httpTestEncoding(protocol.RegistrationTicketLength, 55) + `","username":"private_user","password":"private-password-canary","installationId":"` + httpTestEncoding(16, 1) + `"}`
				headers = map[string][]string{"Content-Type": {"application/json"}}
			}
			if err != nil {
				t.Fatal(err)
			}
			server, client := httpTestPublicServer(t, endpoints.Public, pki, service)
			headers["X-Request-ID"] = []string{httpTestEncoding(16, 99)}
			for _, request := range []struct {
				path, body string
				status     int
			}{
				{path, body, http.StatusServiceUnavailable},
				{path + "?email=private-query-canary", body, http.StatusBadRequest},
				{path, `{"accountId":"private-account-canary"}`, http.StatusBadRequest},
			} {
				response, object, raw := doHTTPTest(t, client, http.MethodPost, server.URL+request.path, request.body, headers)
				problem, ok := object["error"].(map[string]any)
				if response.StatusCode != request.status || len(object) != 2 || !ok || len(problem) != 2 || object["requestId"] != response.Header.Get("X-Request-ID") || object["requestId"] == headers["X-Request-ID"][0] {
					t.Fatal("error boundary or independent ID changed")
				}
				for _, secret := range []string{"private-", "raw-database-password", "slot-owner"} {
					if strings.Contains(raw, secret) {
						t.Fatal("sensitive input or backend error appeared in error JSON")
					}
				}
			}
		})
	}
}
