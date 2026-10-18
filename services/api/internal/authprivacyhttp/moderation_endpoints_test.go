package authprivacyhttp

import (
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestModerationStrictRoutesAndMaterials(t *testing.T) {
	id := "a811e9fa-7663-4182-88c4-465512194416"
	for _, path := range []string{"/api/v1/reports/" + id, "/api/v1/system-notifications/" + id, "/api/v1/moderation/cases/" + id + "/decision", "/api/v1/sanctions/" + id + "/appeals/" + id} {
		if _, e := parseModerationRoute(path); e != nil {
			t.Fatal(path)
		}
	}
	for _, body := range []string{`{"description":"a","description":"b","images":[]}`, `{"description":null,"images":[]}`, `{"description":"a","images":[{"mime":"image/png","base64":"AA==","filename":"secret"}]}`, `{"Description":"a","images":[]}`, `{"description":"\ud800","images":[]}`} {
		r := httptest.NewRequest("PUT", "https://example.invalid", strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		o, e := moderationObject(r, []string{"description", "images"}, nil)
		if e == nil {
			e = decodeModerationObject(o, new(struct {
				Description string `json:"description"`
			}))
		}
		if e == nil {
			t.Fatal("malformed material accepted")
		}
	}
	r := httptest.NewRequest("POST", "https://example.invalid/api/v1/system-notifications/"+id+"/read?identityId="+id, nil)
	if !allowsModerationQuery(r) {
		t.Fatal("read identity selection rejected by boundary")
	}
}
func TestModerationUIOnlyPublishesFourFiles(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"index.html", "styles.css", "app.mjs", "core.mjs", "README.md"} {
		if e := os.WriteFile(filepath.Join(dir, name), []byte("synthetic asset"), 0600); e != nil {
			t.Fatal(e)
		}
	}
	for _, path := range []string{"/admin", "/admin/", "/admin/styles.css", "/admin/app.mjs", "/admin/core.mjs"} {
		w := httptest.NewRecorder()
		serveModerationUI(w, httptest.NewRequest("GET", path, nil), dir)
		if w.Code != 200 || w.Header().Get("Cache-Control") != "no-store" || !strings.Contains(w.Header().Get("Content-Security-Policy"), "frame-ancestors 'none'") {
			t.Fatal("missing private static envelope")
		}
	}
	for _, path := range []string{"/admin/README.md", "/admin/../README.md", "/admin/test/core.test.mjs"} {
		w := httptest.NewRecorder()
		serveModerationUI(w, httptest.NewRequest("GET", path, nil), dir)
		if w.Code != 404 {
			t.Fatal("published unapproved asset")
		}
	}
}
