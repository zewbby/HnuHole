package authprivacyhttp

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

type unavailableSharedStore struct{ hash string }

func (s *unavailableSharedStore) Load(context.Context) (ratelimit.Namespace, error) {
	return ratelimit.Namespace{PolicyHash: s.hash, Generation: 1, RunID: strings.Repeat("a", 40), State: "READY"}, nil
}
func (s *unavailableSharedStore) Recover(context.Context, int64, string, time.Duration) (ratelimit.Namespace, error) {
	return ratelimit.Namespace{}, ratelimit.ErrUnavailable
}
func (s *unavailableSharedStore) Activate(context.Context, int64, string) (ratelimit.Namespace, error) {
	return ratelimit.Namespace{}, ratelimit.ErrUnavailable
}

type sharedResolverFixture struct {
	calls int
	err   error
}

func (s *sharedResolverFixture) ResolveSharedSubject(context.Context, [32]byte) (string, error) {
	s.calls++
	return strings.Repeat("b", 64), s.err
}

func TestSharedSourceControlClassificationExcludesMutationCommands(t *testing.T) {
	for _, v := range []struct {
		method, path string
		control      bool
	}{
		{"PUT", "/api/v1/dm/commands/id", false}, {"PUT", "/api/v1/post-commands/key", false}, {"PUT", "/api/v1/comment-commands/key", false},
		{"GET", "/api/v1/dm/commands/id", true}, {"GET", "/api/v1/post-commands/key", true}, {"POST", "/api/v1/dm/ack", true}, {"POST", "/api/v1/dm/read", true}, {"POST", "/api/v1/dm/commands/id/close", true}, {"GET", "/api/v1/channels", false},
	} {
		if got := sharedControl(httptest.NewRequest(v.method, "https://example.test"+v.path, nil)); got != v.control {
			t.Fatal("shared control method classification", v, got)
		}
	}
}

func TestSharedSourceEnforcedRedisFaultKeepsControlFallbackAndVerifiedWriteDistinction(t *testing.T) {
	// An intentionally unreachable loopback port, strict enforce rules, and an
	// explicit unit resolver. Real SQL/Gate cases live in the owned PG runner.
	config := ratelimit.TrialConfig("127.0.0.1:1", "http_fault_unit")
	config.DeadlineMilliseconds = 50
	for i := range config.Rules {
		config.Rules[i].Mode = ratelimit.Enforce
	}
	store := &unavailableSharedStore{}
	engine, err := ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	store.hash = engine.PolicyHash()
	defer engine.Close()
	resolver := &sharedResolverFixture{}
	b := &boundary{service: CommunityService, shared: &SharedLimits{Engine: engine, Key: [32]byte{1}, Resolver: resolver}}
	request := func(method, path string) (*httptest.ResponseRecorder, bool) {
		r := httptest.NewRequest(method, "https://example.test"+path, nil)
		r.RemoteAddr = "192.0.2.1:1234"
		r.Header.Set("Authorization", "Bearer "+httpTestEncoding(32, 3))
		w := httptest.NewRecorder()
		return w, b.sharedEntry(w, r)
	}
	for _, v := range []struct{ method, path string }{{"POST", "/api/v1/dm/ack"}, {"GET", "/api/v1/dm/commands/id"}} {
		w, ok := request(v.method, v.path)
		if !ok {
			t.Fatalf("control entry rejected before bounded local fallback: %d %s", w.Code, w.Body.String())
		}
	}
	before := engine.Metrics.Snapshot()["read.control"].Requests
	w, ok := request(http.MethodPut, "/api/v1/dm/commands/id")
	if ok || w.Code != 503 || !strings.Contains(w.Body.String(), "SHARED_RATE_UNAVAILABLE") {
		t.Fatal("validated write outage lost its recoverable code", w.Code, w.Body.String())
	}
	if engine.Metrics.Snapshot()["read.control"].Requests != before {
		t.Fatal("send PUT consumed the ACK/query budget")
	}
	resolver.err = authprivacy.ErrAuthorizationUnavailable
	w, ok = request(http.MethodPut, "/api/v1/dm/commands/id")
	if ok || w.Code != 503 || strings.Contains(w.Body.String(), "SHARED_RATE_UNAVAILABLE") {
		t.Fatal("unknown Gate state was treated as a quota-only failure", w.Code, w.Body.String())
	}
}

func TestSharedSourceLegacyQuotaUsesStrictCommentAndDM429(t *testing.T) {
	for _, path := range []string{"/api/v1/comment-commands/key", "/api/v1/dm/commands/id"} {
		t.Run(path, func(t *testing.T) {
			config := httpTestLimits()
			config.MutationCapacity = 1
			limiter, e := newNetworkLimiter(config, CommunityService)
			if e != nil {
				t.Fatal(e)
			}
			b := &boundary{service: CommunityService, limits: limiter}
			handler := b.wrap(false, func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) })
			request := func() *httptest.ResponseRecorder {
				r := httptest.NewRequest("PUT", "https://example.test"+path, nil)
				r.RemoteAddr = "192.0.2.77:123"
				r.TLS = &tls.ConnectionState{Version: tls.VersionTLS13, HandshakeComplete: true}
				w := httptest.NewRecorder()
				handler.ServeHTTP(w, r)
				return w
			}
			if w := request(); w.Code != 204 {
				t.Fatal("local budget fixture failed", w.Code)
			}
			w := request()
			if w.Code != 429 || w.Header().Get("Retry-After") == "" || w.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("legacy quota lost recoverable envelope", w.Code)
			}
			var body map[string]json.RawMessage
			if json.Unmarshal(w.Body.Bytes(), &body) != nil || len(body) != 2 || body["error"] == nil || body["requestId"] == nil {
				t.Fatal("legacy 429 changed strict outer envelope")
			}
			var requestID string
			if json.Unmarshal(body["requestId"], &requestID) != nil || requestID == "" || requestID != w.Header().Get("X-Request-ID") {
				t.Fatal("legacy 429 request identity disagrees with private envelope")
			}
			var public map[string]any
			if json.Unmarshal(body["error"], &public) != nil || len(public) != 2 || public["code"] != "RATE_LIMITED" {
				t.Fatal("strict clients cannot parse legacy 429")
			}
			if message, ok := public["message"].(string); !ok || message == "" {
				t.Fatal("legacy 429 message is absent or not text")
			}
			if _, exists := public["details"]; exists {
				t.Fatal("legacy 429 introduced noncontract retry details")
			}
			if w.Header().Get("Session-Expires-At") != "" || w.Header().Get("Server-Time") != "" {
				t.Fatal("legacy rejection carried unverified session metadata")
			}
		})
	}
}
