package authprivacyhttp

import (
	"context"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func liveProbePath(t *testing.T, program, path string) string {
	t.Helper()
	if !strings.HasSuffix(strings.ToLower(program), ".exe") {
		return path
	}
	out, e := exec.Command("wslpath", "-w", path).Output()
	if e != nil {
		t.Fatal("unable to map owned test fixture")
	}
	return strings.TrimSpace(string(out))
}
func runLiveGovernanceProbe(t *testing.T, program string, fixture map[string]any, phase string, extraArgs ...string) map[string]any {
	t.Helper()
	root := os.Getenv("MODERATION_LIVE_FIXTURE_ROOT")
	if root == "" {
		root = t.TempDir()
	} else {
		if e := os.MkdirAll(root, 0700); e != nil {
			t.Fatal(e)
		}
	}
	dir, e := os.MkdirTemp(root, "probe-")
	if e != nil {
		t.Fatal(e)
	}
	input, output := filepath.Join(dir, "fixture.json"), filepath.Join(dir, "result.json")
	t.Cleanup(func() { _ = os.Remove(input); _ = os.Remove(output); _ = os.Remove(dir) })
	b, e := json.Marshal(fixture)
	if e != nil || os.WriteFile(input, b, 0600) != nil {
		t.Fatal("unable to prepare private synthetic fixture")
	}
	args := append([]string{}, extraArgs...)
	args = append(args, liveProbePath(t, program, input))
	if phase != "browser" {
		args = append(args, phase)
	}
	args = append(args, liveProbePath(t, program, output))
	ctx, cancel := context.WithTimeout(context.Background(), 55*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, program, args...)
	log, e := command.CombinedOutput()
	data, readErr := os.ReadFile(output)
	var result map[string]any
	decodeErr := json.Unmarshal(data, &result)
	if e != nil || readErr != nil || decodeErr != nil || result["status"] == "FAIL" {
		t.Fatalf("live %s failed (safe probe result): %s %s", phase, strings.TrimSpace(string(log)), data)
	}
	t.Logf("live %s: %s", phase, strings.TrimSpace(string(log)))
	return result
}
func TestRealHTTPSModerationDartAndBrowserChainPostgres(t *testing.T) {
	probe := os.Getenv("MODERATION_PROBE")
	if probe == "" {
		t.Skip("owned compiled Dart probe absent; covered separately by real HTTPS/SQL test")
	}
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		v, e := c.WithModeration(context.Background())
		if e != nil {
			t.Fatal(e)
		}
		return v
	})
	// Use the existing mobile test PKI (P-256) supported by Dart's TLS stack.
	// The probe still verifies this exact private CA and loopback SAN; no TLS bypass.
	certificate := mobileLabCertificate(t)
	tlsConfig, e := PublicTLSConfig(certificate)
	if e != nil {
		t.Fatal(e)
	}
	s.cPublic = e2eServer(t, s.cPublic.Config.Handler, tlsConfig)
	transport := s.client.Transport.(*http.Transport).Clone()
	transport.TLSClientConfig = transport.TLSClientConfig.Clone()
	transport.TLSClientConfig.RootCAs = transport.TLSClientConfig.RootCAs.Clone()
	root, e := x509.ParseCertificate(certificate.Certificate[1])
	if e != nil {
		t.Fatal(e)
	}
	transport.TLSClientConfig.RootCAs.AddCert(root)
	s.client.Transport = transport
	t.Cleanup(transport.CloseIdleConnections)
	ctx := context.Background()
	owner, ownerID := e2ePrivacySignup(t, s, "mod_live_owner")
	reporter, _ := e2ePrivacySignup(t, s, "mod_live_reporter")
	reviewer, reviewerID := e2ePrivacySignup(t, s, "mod_live_reviewer")
	admin, adminID := e2ePrivacySignup(t, s, "mod_live_admin")
	for _, r := range []struct{ id, role string }{{reviewerID, "REVIEWER"}, {adminID, "ADMIN"}} {
		if _, e := s.cp.Exec(ctx, `INSERT INTO c_moderation.roles VALUES($1,$2)`, r.id, r.role); e != nil {
			t.Fatal(e)
		}
	}
	channel := postHTTPSChannel(t, s, owner)
	identity := postHTTPSIdentity(t, s, owner, "联调发帖身份", 71)
	reportIdentity := postHTTPSIdentity(t, s, reporter, "联调举报身份", 72)
	create := func(key byte) string {
		r := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, key), owner, "", posts.CreatePostInput{ChannelID: channel, IdentityID: identity, Title: "真实治理联调", Body: "无真实用户的合成材料"}, 202)
		if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
			t.Fatal(e)
		}
		return r["postId"].(string)
	}
	post := create(73)
	certificates := s.cPublic.TLS.Certificates[0].Certificate
	rootPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certificates[len(certificates)-1]})
	fixture := map[string]any{"url": s.cPublic.URL, "certificatePem": string(rootPEM), "ownerToken": owner, "reporterToken": reporter, "reporterIdentityId": reportIdentity, "postId": post, "ownerUsername": "mod_live_owner", "ownerPassword": "separate-community-privacy-audit-password"}
	report := runLiveGovernanceProbe(t, probe, fixture, "report")
	caseID := report["caseId"].(string)
	if node := os.Getenv("MODERATION_NODE"); node != "" {
		sourceRoot, e := filepath.Abs("../../../..")
		if e != nil {
			t.Fatal(e)
		}
		passwords, e := authprivacy.NewPasswordPreparer(1, []string{"PasswordPassword123!"})
		if e != nil {
			t.Fatal(e)
		}
		pki := e2eNewPKI(t)
		endpoints, e := NewCommunityEndpoints(CommunityOptions{Backend: s.c, Passwords: passwords, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, AllowedOrigins: []string{s.cPublic.URL}, Limits: NetworkLimits{Key: e2eKey(t), MutationCapacity: 10000, QueryCapacity: 10000, Window: time.Minute, MaxEntries: 1024}, AdminDirectory: filepath.Join(sourceRoot, "apps", "admin")})
		if e != nil {
			t.Fatal(e)
		}
		s.cPublic.Config.Handler = endpoints.Public
		browserFixture := map[string]any{"url": s.cPublic.URL, "reviewerUsername": "mod_live_reviewer", "reviewerPassword": "separate-community-privacy-audit-password", "caseId": caseID, "playwrightModule": os.Getenv("MODERATION_PLAYWRIGHT_MODULE"), "browserExecutable": os.Getenv("MODERATION_BROWSER"), "outputDirectory": os.Getenv("MODERATION_BROWSER_OUTPUT")}
		script := filepath.Join(sourceRoot, "apps", "admin", "test", "live-api-smoke.mjs")
		runLiveGovernanceProbe(t, node, browserFixture, "browser", liveProbePath(t, node, script))
	} else {
		postHTTPSJSON(t, s, "POST", "/api/v1/moderation/cases/"+caseID+"/decision", reviewer, "", map[string]any{"commandId": uuid.NewString(), "expectedVersion": 1, "action": "MUTE", "days": 3, "reason": "真实Dart链路限时禁言"}, 200)
	}
	var sanction string
	if e := s.cp.QueryRow(ctx, `SELECT sanction_id FROM c_moderation.sanctions WHERE case_id=$1`, caseID).Scan(&sanction); e != nil {
		t.Fatal(e)
	}
	fixture["sanctionId"] = sanction
	appeal := runLiveGovernanceProbe(t, probe, fixture, "appeal")
	appealID := appeal["appealId"].(string)
	fixture["appealId"] = appealID
	postHTTPSJSON(t, s, "POST", "/api/v1/moderation/appeals/"+appealID+"/decision", admin, "", map[string]any{"commandId": uuid.NewString(), "expectedVersion": 1, "accept": true, "reason": "另一管理人员实际复核"}, 200)
	runLiveGovernanceProbe(t, probe, fixture, "result")
	// A distinct post creates a distinct fact; ban cannot reuse the prior ended case.
	second := create(74)
	key := uuid.NewString()
	r := postHTTPSJSON(t, s, "PUT", "/api/v1/reports/"+key, reporter, "", map[string]any{"postId": second, "reason": "OTHER", "description": "第二独立事实", "images": []any{}}, 200)
	secondCase := r["report"].(map[string]any)["caseId"].(string)
	result := postHTTPSJSON(t, s, "POST", "/api/v1/moderation/cases/"+secondCase+"/decision", admin, "", map[string]any{"commandId": uuid.NewString(), "expectedVersion": 1, "action": "BAN", "days": 1, "reason": "合成限时封禁"}, 200)
	ban := result["sanctions"].([]any)[0].(map[string]any)["id"].(string)
	limited := e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/moderation-access/sessions", map[string]any{"username": "mod_live_owner", "password": "separate-community-privacy-audit-password"}, nil, 201)
	newAppeal := postHTTPSJSON(t, s, "PUT", "/api/v1/sanctions/"+ban+"/appeals/"+uuid.NewString(), limited["sessionToken"].(string), "", map[string]any{"description": "封禁账号仍可申诉", "images": []any{}}, 200)
	fixture["sanctionId"] = ban
	fixture["appealId"] = newAppeal["id"]
	fixture["postId"] = second
	runLiveGovernanceProbe(t, probe, fixture, "limited")
	var auditCount int
	if e := s.cp.QueryRow(ctx, `SELECT count(*) FROM c_moderation.audit WHERE target_number=(SELECT platform_number FROM c_auth.accounts WHERE account_id=$1)`, ownerID).Scan(&auditCount); e != nil || auditCount < 3 {
		t.Fatal("real chain audit missing", e)
	}
}
