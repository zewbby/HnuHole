package authprivacyhttp

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func isAdminPath(path string) bool { return path == "/admin" || strings.HasPrefix(path, "/admin/") }
func serveModerationUI(w http.ResponseWriter, r *http.Request, directory string) {
	if directory == "" || r.URL.RawPath != "" || r.URL.RawQuery != "" {
		http.NotFound(w, r)
		return
	}
	if r.Method != "GET" {
		w.Header().Set("Allow", "GET")
		w.WriteHeader(405)
		return
	}
	name, typ := "", ""
	switch r.URL.Path {
	case "/admin", "/admin/":
		name = "index.html"
		typ = "text/html; charset=utf-8"
	case "/admin/styles.css":
		name = "styles.css"
		typ = "text/css; charset=utf-8"
	case "/admin/app.mjs":
		name = "app.mjs"
		typ = "text/javascript; charset=utf-8"
	case "/admin/core.mjs":
		name = "core.mjs"
		typ = "text/javascript; charset=utf-8"
	default:
		http.NotFound(w, r)
		return
	}
	b, e := os.ReadFile(filepath.Join(directory, name))
	if e != nil || len(b) > 512*1024 {
		http.Error(w, "管理页面暂不可用", 503)
		return
	}
	w.Header().Set("Content-Type", typ)
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
	w.Header().Set("X-Frame-Options", "DENY")
	_, _ = w.Write(b)
}
