package authprivacyhttp

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

// Host substitutes here prove strict HTTP plumbing only. Original bytes, SQL
// and final Gate evidence live in TestRealHTTPSPostImages.../PostImages...SQL.
type imageHTTPBackend struct{ postHTTPBackend }

func (f *imageHTTPBackend) ReadPostImages(_ context.Context, _ [32]byte, post, content string) (authprivacy.PostResponse, error) {
	f.calls++
	if content != "" {
		return f.response(authprivacy.ImageBytes{Bytes: []byte("synthetic"), MIME: "image/gif"})
	}
	return f.response(postmedia.Group{PostID: post, Images: []postmedia.Image{}, AccessValidUntil: postHTTPTime.Add(time.Minute).Format(time.RFC3339Nano)})
}
func (f *imageHTTPBackend) ReadPostImageUploads(_ context.Context, _ [32]byte, task string, version int32) (authprivacy.PostResponse, error) {
	f.calls++
	return f.response(postmedia.UploadState{TaskID: task, PostID: postHTTPPost, AttemptVersion: version, Items: []postmedia.UploadItem{}})
}
func (f *imageHTTPBackend) IssuePostImageGrant(_ context.Context, _ [32]byte, task, media string, version int32) (authprivacy.PostResponse, error) {
	f.calls++
	return f.response(postmedia.Grant{TaskID: task, MediaID: media, AttemptVersion: version, UploadToken: httpTestEncoding(32, 1), ExpiresAt: postHTTPTime.Add(15 * time.Minute).Format(time.RFC3339Nano)})
}
func (f *imageHTTPBackend) UploadPostImage(_ context.Context, _ [32]byte, _, _ string, _ int32, _ []byte, _ string) (time.Time, error) {
	f.calls++
	return postHTTPTime, f.err
}

func newImageHTTP(t *testing.T) (*imageHTTPBackend, http.Handler) {
	t.Helper()
	pki := newHTTPTestPKI(t)
	community := &httpTestCommunity{}
	f := &imageHTTPBackend{}
	endpoints, e := NewCommunityEndpoints(CommunityOptions{Posts: f, Backend: community, Passwords: httpTestPasswords{backend: community}, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: httpTestLimits(), AllowedOrigins: []string{"https://client.example"}})
	if e != nil {
		t.Fatal(e)
	}
	return f, endpoints.Public
}

func TestPostImageHTTPStrictPathsCredentialsAndBodies(t *testing.T) {
	base := "/api/v1/posts/" + postHTTPPost + "/images"
	upload := "/api/v1/me/post-tasks/" + postHTTPTask + "/attempts/1/images/" + postHTTPIdentity
	cases := []struct {
		name, method, path, body, auth, mime, header string
		status                                       int
	}{
		{"no auth", "GET", base, "", "", "", "", 401},
		{"upload token cannot read", "GET", base, "", "Upload " + httpTestEncoding(32, 1), "", "", 401},
		{"read body", "GET", base, "{}", "Bearer " + httpTestEncoding(32, 1), "", "", 400},
		{"query token", "GET", base + "?token=secret", "", "Bearer " + httpTestEncoding(32, 1), "", "", 400},
		{"wrong verb", "POST", base, "", "Bearer " + httpTestEncoding(32, 1), "", "", 405},
		{"bad content id", "GET", base + "/garbage/original", "", "Bearer " + httpTestEncoding(32, 1), "", "", 400},
		{"range forbidden", "GET", base, "", "Bearer " + httpTestEncoding(32, 1), "", "Range", 400},
		{"validator input encoding", "PUT", upload + "/bytes", "image", "Upload " + httpTestEncoding(32, 1), "image/png", "Content-Encoding", 400},
		{"wrong scheme upload", "PUT", upload + "/bytes", "image", "Bearer " + httpTestEncoding(32, 1), "image/png", "", 401},
		{"svg denied", "PUT", upload + "/bytes", "<svg/>", "Upload " + httpTestEncoding(32, 1), "image/svg+xml", "", 415},
		{"mime params denied", "PUT", upload + "/bytes", "image", "Upload " + httpTestEncoding(32, 1), "image/png;charset=x", "", 415},
		{"grant body denied", "POST", upload + "/upload-grant", "{}", "Bearer " + httpTestEncoding(32, 1), "application/json", "", 400},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f, h := newImageHTTP(t)
			headers := http.Header{}
			if tc.auth != "" {
				headers.Set("Authorization", tc.auth)
			}
			if tc.mime != "" {
				headers.Set("Content-Type", tc.mime)
			}
			if tc.header != "" {
				headers.Set(tc.header, "x")
			}
			r := postHTTPRequest(h, tc.method, tc.path, tc.body, headers)
			if r.Code != tc.status || f.calls != 0 {
				t.Fatalf("status=%d want=%d calls=%d", r.Code, tc.status, f.calls)
			}
		})
	}
}

func TestPostImageHTTPManifestStrictnessAndResponseIsolation(t *testing.T) {
	item := `{"mediaId":"` + postHTTPIdentity + `","sha256":"` + strings.Repeat("a", 64) + `","mimeType":"image/png","byteLength":100,"width":3,"height":2}`
	for _, images := range []string{`[`, `null`, `{}`, `[` + item + `,` + item + `]`, `[` + strings.Replace(item, `"width":3`, `"width":3,"width":4`, 1) + `]`, `[` + strings.Replace(item, `"width":3`, `"width":3.5`, 1) + `]`, `[` + strings.Replace(item, `"width":3`, `"width":3,"extra":true`, 1) + `]`} {
		f, h := newImageHTTP(t)
		body := strings.TrimSuffix(postHTTPCreateBody(), "}") + `,"images":` + images + `}`
		response := postHTTPRequest(h, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 8), body, postHTTPHeaders(false))
		if response.Code != 400 || f.calls != 0 {
			t.Fatal("malformed image manifest reached backend")
		}
	}
	f, h := newImageHTTP(t)
	body := strings.TrimSuffix(postHTTPCreateBody(), "}") + `,"images":[` + item + `]}`
	response := postHTTPRequest(h, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 8), body, postHTTPHeaders(false))
	if response.Code != 202 || len(f.intent.Images) != 1 {
		t.Fatal("valid manifest not framed")
	}
	f.value = map[string]any{"account": "forbidden"}
	response = postHTTPRequest(h, "GET", "/api/v1/posts/"+postHTTPPost+"/images", "", postHTTPHeaders(false))
	if response.Code != 503 || strings.Contains(response.Body.String(), "forbidden") {
		t.Fatal("arbitrary backend data leaked")
	}
}
