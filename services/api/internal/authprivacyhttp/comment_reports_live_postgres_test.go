package authprivacyhttp

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRealHTTPSCommentReportDartAndBrowserChainPostgres(t *testing.T) {
	probe := os.Getenv("MODERATION_PROBE")
	if probe == "" {
		t.Skip("owned compiled Dart probe absent; covered separately by real HTTPS/SQL test")
	}
	ctx := context.Background()
	python := os.Getenv("POST_MEDIA_PYTHON")
	if python == "" {
		t.Fatal("real media validator required")
	}
	script, _ := filepath.Abs("../../media/validate_image.py")
	source, e := os.ReadFile(script)
	if e != nil {
		t.Fatal(e)
	}
	hash := sha256.Sum256(source)
	validator, e := postmedia.NewProcessValidator(python, script, hex.EncodeToString(hash[:]))
	if e != nil {
		t.Fatal(e)
	}
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		c, e := c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: e2eKey(t), FingerprintKey: e2eKey(t)})
		if e != nil {
			t.Fatal(e)
		}
		c, e = c.WithPostImages(ctx, validator)
		if e != nil {
			t.Fatal(e)
		}
		v, e := c.WithModeration(ctx)
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
	owner, _ := e2ePrivacySignup(t, s, "mod_live_owner")
	reporter, _ := e2ePrivacySignup(t, s, "mod_live_reporter")
	reviewer, reviewerID := e2ePrivacySignup(t, s, "mod_live_reviewer")
	admin, adminID := e2ePrivacySignup(t, s, "mod_live_admin")
	for _, r := range []struct{ id, role string }{{reviewerID, "REVIEWER"}, {adminID, "ADMIN"}} {
		if _, e := s.cp.Exec(ctx, `INSERT INTO c_moderation.roles VALUES($1,$2)`, r.id, r.role); e != nil {
			t.Fatal(e)
		}
	}
	parent, _ := e2ePrivacySignup(t, s, "cr_live_parent")
	parentIdentity := postHTTPSIdentity(t, s, parent, "父帖身份", 70)
	channel := postHTTPSChannel(t, s, parent)
	identity := postHTTPSIdentity(t, s, owner, "联调发帖身份", 71)
	reportIdentity := postHTTPSIdentity(t, s, reporter, "联调举报身份", 72)
	create := func(key byte) string {
		r := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, key), parent, "", posts.CreatePostInput{ChannelID: channel, IdentityID: parentIdentity, Title: "真实治理联调", Body: "无真实用户的合成材料"}, 202)
		if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
			t.Fatal(e)
		}
		return r["postId"].(string)
	}
	post := create(73)
	createComment := func(root any, image any, key byte) (string, string) {
		task := uuid.NewString()
		input := map[string]any{"operation": "CREATE", "taskId": task, "postId": post, "identityId": identity, "rootCommentId": root, "targetCommentId": root, "body": "真实单图回复举报", "image": image}
		postHTTPSJSON(t, s, "PUT", "/api/v1/comment-commands/"+httpTestEncoding(16, key), owner, "", input, 202)
		return task, "/api/v1/me/comment-tasks/" + task
	}
	rootTask, rootPath := createComment(nil, nil, 75)
	if _, e = s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	rootComment := postHTTPSJSON(t, s, "GET", rootPath, owner, "", nil, 200)["publishedCommentId"].(string)
	_ = rootTask
	data, e := os.ReadFile(filepath.Join(os.Getenv("POST_MEDIA_FIXTURES"), "gif.bin"))
	if e != nil {
		t.Fatal(e)
	}
	meta, e := validator.Inspect(ctx, data)
	if e != nil {
		t.Fatal(e)
	}
	selection := postmedia.Selection{MediaID: uuid.NewString(), SHA256: meta.SHA256, ByteLength: meta.ByteLength, MIME: meta.MIME, Width: meta.Width, Height: meta.Height}
	task, path := createComment(rootComment, selection, 76)
	req, _ := http.NewRequest("PUT", s.cPublic.URL+path+"/attempts/1/image", bytes.NewReader(data))
	req.Header.Set("Authorization", "Bearer "+owner)
	req.Header.Set("Content-Type", meta.MIME)
	res, e := s.client.Do(req)
	if e != nil {
		t.Fatal(e)
	}
	io.Copy(io.Discard, res.Body)
	res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatal("real single image upload", res.StatusCode)
	}
	if _, e = s.c.PublishAcceptedComments(ctx, 100); e != nil {
		t.Fatal(e)
	}
	comment := postHTTPSJSON(t, s, "GET", path, owner, "", nil, 200)["publishedCommentId"].(string)
	_ = task
	row := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post+"/comments/"+comment, reporter, "", nil, 200)
	imagePath := "/api/v1/posts/" + post + "/comments/" + comment + "/images/" + row["image"].(map[string]any)["contentVersionId"].(string) + "/original"
	certificates := s.cPublic.TLS.Certificates[0].Certificate
	rootPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certificates[len(certificates)-1]})
	fixture := map[string]any{"url": s.cPublic.URL, "certificatePem": string(rootPEM), "ownerToken": owner, "reporterToken": reporter, "reporterIdentityId": reportIdentity, "postId": post, "commentId": comment, "ownerUsername": "mod_live_owner", "ownerPassword": "separate community privacy audit password"}
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
		browserFixture := map[string]any{"url": s.cPublic.URL, "reviewerUsername": "mod_live_reviewer", "reviewerPassword": "separate community privacy audit password", "caseId": caseID, "commentId": comment, "playwrightModule": os.Getenv("MODERATION_PLAYWRIGHT_MODULE"), "browserExecutable": os.Getenv("MODERATION_BROWSER"), "outputDirectory": os.Getenv("MODERATION_BROWSER_OUTPUT")}
		script := filepath.Join(sourceRoot, "apps", "admin", "test", "live-api-smoke.mjs")
		runLiveGovernanceProbe(t, node, browserFixture, "browser", liveProbePath(t, node, script))
	} else {
		postHTTPSJSON(t, s, "POST", "/api/v1/moderation/cases/"+caseID+"/decision", reviewer, "", map[string]any{"commandId": uuid.NewString(), "expectedVersion": 1, "action": "MUTE", "days": 3, "reason": "真实Dart链路限时禁言"}, 200)
	}
	var sanction string
	if e := s.cp.QueryRow(ctx, `SELECT sanction_id FROM c_moderation.sanctions WHERE case_id=$1`, caseID).Scan(&sanction); e != nil {
		t.Fatal(e)
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post, reporter, "", nil, 200)
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post+"/comments/"+comment, reporter, "", nil, 404)
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post+"/comments/"+rootComment, reporter, "", nil, 200)
	checkImage := func(status int) {
		req, _ := http.NewRequest("GET", s.cPublic.URL+imagePath, nil)
		req.Header.Set("Authorization", "Bearer "+reporter)
		r, e := s.client.Do(req)
		if e != nil {
			t.Fatal(e)
		}
		io.Copy(io.Discard, r.Body)
		r.Body.Close()
		if r.StatusCode != status {
			t.Fatal("moderated image visibility", r.StatusCode)
		}
	}
	checkImage(404)
	fixture["sanctionId"] = sanction
	appeal := runLiveGovernanceProbe(t, probe, fixture, "appeal")
	appealID := appeal["appealId"].(string)
	fixture["appealId"] = appealID
	postHTTPSJSON(t, s, "POST", "/api/v1/moderation/appeals/"+appealID+"/decision", admin, "", map[string]any{"commandId": uuid.NewString(), "expectedVersion": 1, "accept": true, "reason": "另一管理人员实际复核"}, 200)
	runLiveGovernanceProbe(t, probe, fixture, "result")
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post+"/comments/"+comment, reporter, "", nil, 200)
	checkImage(200)
	var audits int
	if e = s.cp.QueryRow(ctx, `SELECT count(*) FROM c_moderation.audit WHERE case_id=$1`, caseID).Scan(&audits); e != nil || audits < 2 {
		t.Fatal("real audit chain", e, audits)
	}
}
