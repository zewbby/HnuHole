package authprivacyhttp

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func writeHTTPTestPeer(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Request-ID", httpTestEncoding(16, 77))
	w.WriteHeader(status)
	_, _ = w.Write([]byte(body))
}

func httpTestReceipt(t *testing.T, purpose protocol.Purpose, slot protocol.SlotID) string {
	t.Helper()
	receipt := protocol.Receipt{Purpose: purpose, Epoch: 1, Slot: slot}
	encoded, err := receipt.Encode()
	if err != nil {
		t.Fatal(err)
	}
	return encoded
}

func newHTTPTestPeer(t *testing.T, pki *httpTestPKI, service Service, handler http.Handler) *PeerClient {
	t.Helper()
	serverCert := pki.issue(t, "lab", service, nil)
	clientCert := pki.issue(t, "lab", opposite(service), nil)
	config, err := InternalTLSConfig(serverCert, PeerIdentity{Environment: "lab", Service: opposite(service), Roots: pki.roots})
	if err != nil {
		t.Fatal(err)
	}
	server := startHTTPTestTLS(t, handler, config)
	peer, err := NewPeerClient(PeerClientOptions{Origin: server.URL, Environment: "lab", LocalService: opposite(service), PeerService: service, ClientCertificate: clientCert, Roots: pki.roots})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(peer.CloseIdleConnections)
	return peer
}

func TestReceiptClientAcceptsOnlyExactRequestAuthenticated200ACK(t *testing.T) {
	encoded := httpTestReceipt(t, protocol.PurposeReleased, protocol.SlotID{3})
	for _, test := range []struct {
		name     string
		status   int
		body     string
		change   func(http.ResponseWriter)
		accepted bool
	}{
		{"durable-ack", 200, `{"state":"ACKNOWLEDGED"}`, nil, true},
		{"pending-not-ack", 202, `{"state":"ACKNOWLEDGED"}`, nil, false},
		{"wrong-state", 200, `{"state":"PENDING"}`, nil, false},
		{"unknown-field", 200, `{"state":"ACKNOWLEDGED","slotId":"x"}`, nil, false},
		{"duplicate-key", 200, `{"state":"PENDING","state":"ACKNOWLEDGED"}`, nil, false},
		{"null", 200, `{"state":null}`, nil, false},
		{"trailing", 200, `{"state":"ACKNOWLEDGED"} {}`, nil, false},
		{"oversize", 200, `{"state":"` + strings.Repeat("X", 1024) + `"}`, nil, false},
		{"cacheable", 200, `{"state":"ACKNOWLEDGED"}`, func(w http.ResponseWriter) { w.Header().Set("Cache-Control", "public") }, false},
		{"missing-request-id", 200, `{"state":"ACKNOWLEDGED"}`, func(w http.ResponseWriter) { w.Header().Del("X-Request-ID") }, false},
		{"bad-request-id", 200, `{"state":"ACKNOWLEDGED"}`, func(w http.ResponseWriter) { w.Header().Set("X-Request-ID", "raw-cross-party-id") }, false},
		{"wrong-content-type", 200, `{"state":"ACKNOWLEDGED"}`, func(w http.ResponseWriter) { w.Header().Set("Content-Type", "text/plain") }, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			pki := newHTTPTestPKI(t)
			var calls atomic.Int32
			peer := newHTTPTestPeer(t, pki, VerifierService, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				if r.URL.Path != "/internal/v1/slot-releases" || r.Method != "POST" {
					t.Error("wrong fixed receipt route")
				}
				for _, name := range []string{"Authorization", "Idempotency-Key", "X-Request-ID", "traceparent", "V-Installation-ID"} {
					if hasHeader(r.Header, name) {
						t.Errorf("forwarded linkage header %s", name)
					}
				}
				object, err := parseObject(r.Body, 1024)
				if err != nil || fields(object, []string{"releaseReceipt"}, nil) != nil || object["releaseReceipt"] != encoded {
					t.Error("changed receipt request")
				}
				w.Header().Set("Cache-Control", "no-store")
				w.Header().Set("Content-Type", "application/json")
				w.Header().Set("X-Request-ID", httpTestEncoding(16, 77))
				if test.change != nil {
					test.change(w)
				}
				w.WriteHeader(test.status)
				_, _ = w.Write([]byte(test.body))
			}))
			err := peer.ReceiveReceipt(context.Background(), encoded, protocol.PurposeReleased)
			if (err == nil) != test.accepted {
				t.Fatalf("ACK=%v error=%v", test.accepted, err)
			}
			if calls.Load() != 1 {
				t.Fatal("unexpected retry or missing request")
			}
		})
	}
}

func TestReceiptClientUsesCorrectPurposeRouteAndNeverFollowsRedirect(t *testing.T) {
	pki := newHTTPTestPKI(t)
	var unexpected atomic.Int32
	peer := newHTTPTestPeer(t, pki, VerifierService, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/redirect-target" {
			unexpected.Add(1)
			writeHTTPTestPeer(w, 200, `{"state":"ACKNOWLEDGED"}`)
			return
		}
		if r.URL.Path != "/internal/v1/slot-retirement-receipts" {
			t.Error("wrong retirement receipt route")
		}
		object, err := parseObject(r.Body, 1024)
		if err != nil || fields(object, []string{"retirementReceipt"}, nil) != nil {
			t.Error("wrong purpose body")
		}
		w.Header().Set("Location", "/redirect-target")
		writeHTTPTestPeer(w, 307, `{"state":"ACKNOWLEDGED"}`)
	}))
	encoded := httpTestReceipt(t, protocol.PurposeRetired, protocol.SlotID{3})
	if err := peer.ReceiveReceipt(context.Background(), encoded, protocol.PurposeRetired); err == nil {
		t.Fatal("redirect acknowledged")
	}
	if unexpected.Load() != 0 {
		t.Fatal("followed internal redirect")
	}
	if err := peer.ReceiveReceipt(context.Background(), encoded, protocol.PurposeReleased); err == nil {
		t.Fatal("mismatched purpose sent")
	}
}

func TestRetirementClientBindsReceiptToAuthorizationAndPendingRetry(t *testing.T) {
	authorization := protocol.Authorization{Epoch: 1, Slot: protocol.SlotID{4}}.Encode()
	rightReceipt := httpTestReceipt(t, protocol.PurposeRetired, protocol.SlotID{4})
	wrongReceipt := httpTestReceipt(t, protocol.PurposeRetired, protocol.SlotID{9})
	for _, test := range []struct {
		name     string
		status   int
		body     string
		retry    string
		expected authprivacy.RetirementReply
		reject   bool
	}{
		{"right-receipt", 200, `{"retirementReceipt":"` + rightReceipt + `"}`, "", authprivacy.RetirementReply{Receipt: rightReceipt}, false},
		{"wrong-slot", 200, `{"retirementReceipt":"` + wrongReceipt + `"}`, "", authprivacy.RetirementReply{}, true},
		{"pending", 202, `{"state":"RECEIPT_PENDING","retryAfterSeconds":5}`, "5", authprivacy.RetirementReply{Pending: true, RetryAfterSeconds: 5}, false},
		{"inconsistent-retry", 202, `{"state":"RECEIPT_PENDING","retryAfterSeconds":5}`, "6", authprivacy.RetirementReply{}, true},
		{"wrong-pending", 202, `{"state":"ACKNOWLEDGED","retryAfterSeconds":5}`, "5", authprivacy.RetirementReply{}, true},
		{"not-retirable", 409, `{"error":{"code":"SLOT_NOT_RETIRABLE","message":"Unavailable"},"requestId":"` + httpTestEncoding(16, 77) + `"}`, "", authprivacy.RetirementReply{SlotNotRetirable: true}, false},
		{"other-conflict", 409, `{"error":{"code":"IDEMPOTENCY_KEY_REUSED","message":"Unavailable"},"requestId":"` + httpTestEncoding(16, 77) + `"}`, "", authprivacy.RetirementReply{}, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			pki := newHTTPTestPKI(t)
			peer := newHTTPTestPeer(t, pki, CommunityService, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/internal/v1/slot-retirements" {
					t.Error("wrong fixed retirement route")
				}
				object, err := parseObject(r.Body, 1024)
				if err != nil || fields(object, []string{"retirementAuthorization"}, nil) != nil || object["retirementAuthorization"] != authorization {
					t.Error("changed authorization")
				}
				if test.retry != "" {
					w.Header().Set("Retry-After", test.retry)
				}
				writeHTTPTestPeer(w, test.status, test.body)
			}))
			result, err := peer.RetireUnusedSlot(context.Background(), authorization)
			if test.reject {
				if err == nil {
					t.Fatal("accepted mismatched peer response")
				}
				return
			}
			if err != nil || result != test.expected {
				t.Fatalf("result %+v err %v", result, err)
			}
		})
	}
}

func TestPeerClientRejectsWrongServerHostnameEnvironmentAndTLSVersion(t *testing.T) {
	pki := newHTTPTestPKI(t)
	clientCert := pki.issue(t, "lab", VerifierService, nil)
	for _, test := range []struct {
		name        string
		environment string
		modify      func(*x509.Certificate)
		max         uint16
	}{
		{"hostname", "lab", func(c *x509.Certificate) { c.IPAddresses = nil; c.DNSNames = []string{"different-host.invalid"} }, tls.VersionTLS13},
		{"environment", "staging", nil, tls.VersionTLS13},
		{"cn-only", "lab", func(c *x509.Certificate) { c.URIs = nil }, tls.VersionTLS13},
		{"tls12", "lab", nil, tls.VersionTLS12},
	} {
		t.Run(test.name, func(t *testing.T) {
			certificate := pki.issue(t, test.environment, CommunityService, test.modify)
			var calls atomic.Int32
			server := startHTTPTestTLS(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				writeHTTPTestPeer(w, 200, `{"retirementReceipt":"x"}`)
			}), &tls.Config{MinVersion: test.max, MaxVersion: test.max, Certificates: []tls.Certificate{certificate}, ClientAuth: tls.RequireAndVerifyClientCert, ClientCAs: pki.roots})
			peer, err := NewPeerClient(PeerClientOptions{Origin: server.URL, Environment: "lab", LocalService: VerifierService, PeerService: CommunityService, ClientCertificate: clientCert, Roots: pki.roots})
			if err != nil {
				t.Fatal(err)
			}
			defer peer.CloseIdleConnections()
			if _, err := peer.RetireUnusedSlot(context.Background(), protocol.Authorization{Epoch: 1, Slot: protocol.SlotID{1}}.Encode()); err == nil {
				t.Fatal("accepted wrong server identity/version")
			}
			if calls.Load() != 0 {
				t.Fatal("sent authorization to untrusted server")
			}
		})
	}
}

func TestActualMTLSHandlersAcknowledgeOnlyDurableMatchingReceiptCommand(t *testing.T) {
	_, receipts, endpoints, pki := newHTTPTestVerifier(t, httpTestLimits())
	serverCert := pki.issue(t, "lab", VerifierService, nil)
	clientCert := pki.issue(t, "lab", CommunityService, nil)
	config, err := InternalTLSConfig(serverCert, PeerIdentity{Environment: "lab", Service: CommunityService, Roots: pki.roots})
	if err != nil {
		t.Fatal(err)
	}
	server := startHTTPTestTLS(t, endpoints.Internal, config)
	peer, err := NewPeerClient(PeerClientOptions{Origin: server.URL, Environment: "lab", LocalService: CommunityService, PeerService: VerifierService, ClientCertificate: clientCert, Roots: pki.roots})
	if err != nil {
		t.Fatal(err)
	}
	defer peer.CloseIdleConnections()
	encoded := httpTestReceipt(t, protocol.PurposeRetired, protocol.SlotID{5})
	if err := peer.ReceiveReceipt(context.Background(), encoded, protocol.PurposeRetired); err != nil {
		t.Fatal(err)
	}
	receipts.mu.Lock()
	if receipts.calls != 1 || receipts.encoded != encoded || receipts.purpose != protocol.PurposeRetired {
		t.Fatal("different command acknowledged")
	}
	receipts.err = authprivacy.ErrReconciliation
	receipts.mu.Unlock()
	if err := peer.ReceiveReceipt(context.Background(), encoded, protocol.PurposeRetired); err == nil {
		t.Fatal("uncommitted reconciliation error acknowledged")
	}
	receipts.mu.Lock()
	receipts.err = protocol.ErrSignature
	receipts.mu.Unlock()
	if err := peer.ReceiveReceipt(context.Background(), encoded, protocol.PurposeRetired); err == nil {
		t.Fatal("invalid application signature acknowledged under mTLS")
	}
}

func TestActualCommunityRetirementPendingAndFixedReceiptResponse(t *testing.T) {
	backend, endpoints, pki := newHTTPTestCommunity(t)
	backend.retirement = authprivacy.RetirementReply{Pending: true, RetryAfterSeconds: 5}
	serverCert := pki.issue(t, "lab", CommunityService, nil)
	clientCert := pki.issue(t, "lab", VerifierService, nil)
	config, err := InternalTLSConfig(serverCert, PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots})
	if err != nil {
		t.Fatal(err)
	}
	server := startHTTPTestTLS(t, endpoints.Internal, config)
	peer, err := NewPeerClient(PeerClientOptions{Origin: server.URL, Environment: "lab", LocalService: VerifierService, PeerService: CommunityService, ClientCertificate: clientCert, Roots: pki.roots})
	if err != nil {
		t.Fatal(err)
	}
	defer peer.CloseIdleConnections()
	authorization := protocol.Authorization{Epoch: 1, Slot: protocol.SlotID{8}}.Encode()
	result, err := peer.RetireUnusedSlot(context.Background(), authorization)
	if err != nil || !result.Pending || result.RetryAfterSeconds != 5 {
		t.Fatalf("pending result %+v %v", result, err)
	}
	encoded := httpTestReceipt(t, protocol.PurposeRetired, protocol.SlotID{8})
	backend.mu.Lock()
	backend.retirement = authprivacy.RetirementReply{Receipt: encoded}
	backend.mu.Unlock()
	result, err = peer.RetireUnusedSlot(context.Background(), authorization)
	if err != nil || result.Receipt != encoded {
		t.Fatalf("receipt %+v %v", result, err)
	}
	backend.mu.Lock()
	backend.retirement = authprivacy.RetirementReply{SlotNotRetirable: true}
	backend.mu.Unlock()
	result, err = peer.RetireUnusedSlot(context.Background(), authorization)
	if err != nil || !result.SlotNotRetirable {
		t.Fatalf("rejection %+v %v", result, err)
	}
	// The public listener has no route that can invoke retirement even with a
	// forwarded certificate string or application authorization material.
	publicServer, publicClient := httpTestPublicServer(t, endpoints.Public, pki, CommunityService)
	body, _ := json.Marshal(map[string]string{"retirementAuthorization": authorization})
	response, _, _ := doHTTPTest(t, publicClient, "POST", publicServer.URL+"/internal/v1/slot-retirements", string(body), map[string][]string{"Content-Type": {"application/json"}, "X-Forwarded-Client-Cert": {"forged"}})
	if response.StatusCode != 404 {
		t.Fatal("public internal exposure")
	}
}
