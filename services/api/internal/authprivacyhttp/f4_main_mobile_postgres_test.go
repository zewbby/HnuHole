package authprivacyhttp

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// Host-only: production root/routes + Dart adapters/controllers + real TLS
// handlers/Gates/PG and file SQLite. Native vaults are explicitly substituted.
func TestF4MainAppHTTPSPostgres(t *testing.T) {
	flutter := os.Getenv("F4_MAIN_FLUTTER")
	if flutter == "" {
		t.Skip("requires the owned F4 Linux runner")
	}
	s := e2eNewServices(t)
	s.enableCSigning()
	tlsConfig, err := PublicTLSConfig(mobileLabCertificate(t))
	if err != nil {
		t.Fatal(err)
	}
	s.cPublic = e2eServer(t, s.cPublic.Config.Handler, tlsConfig)
	s.vPublic = e2eServer(t, s.vPublic.Config.Handler, tlsConfig)
	var mu sync.Mutex
	holdQuery := true
	armCreate, armDelete := false, false
	creates, deletes, dropped, queryDrops := 0, 0, 0, 0
	original := s.cPublic.Config.Handler
	s.cPublic.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		held := holdQuery && r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/post-commands/")
		if held {
			queryDrops++
		}
		mu.Unlock()
		if held {
			c, _, e := w.(http.Hijacker).Hijack()
			if e != nil {
				t.Error("query fault failed")
				return
			}
			_ = c.Close()
			return
		}
		recorded := httptest.NewRecorder()
		original.ServeHTTP(recorded, r)
		isCreate := r.Method == http.MethodPut && strings.HasPrefix(r.URL.Path, "/api/v1/post-commands/")
		isDelete := r.Method == http.MethodPost && strings.HasSuffix(r.URL.Path, "/delete")
		mu.Lock()
		if isCreate {
			creates++
		}
		if isDelete {
			deletes++
		}
		drop := recorded.Code < 300 && ((isCreate && armCreate) || (isDelete && armDelete))
		if drop {
			dropped++
			if isCreate {
				armCreate = false
			}
			if isDelete {
				armDelete = false
			}
		}
		mu.Unlock()
		if drop {
			c, _, e := w.(http.Hijacker).Hijack()
			if e != nil {
				t.Error("committed response fault failed")
				return
			}
			_ = c.Close()
			return
		}
		for key, values := range recorded.Header() {
			w.Header()[key] = values
		}
		w.WriteHeader(recorded.Code)
		_, _ = w.Write(recorded.Body.Bytes())
	})
	var secret [32]byte
	if _, err = rand.Read(secret[:]); err != nil {
		t.Fatal(err)
	}
	token := base64.RawURLEncoding.EncodeToString(secret[:])
	control := e2eServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if r.Method != http.MethodPost || r.Header.Get("Authorization") != "LabControl "+token {
			w.WriteHeader(403)
			return
		}
		var body map[string]string
		if json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&body) != nil {
			w.WriteHeader(400)
			return
		}
		var result any = map[string]bool{"ok": true}
		var controlErr error
		switch r.URL.Path {
		case "/otp":
			code, calls := s.mail.code(body["email"])
			if code == "" {
				w.WriteHeader(404)
				return
			}
			result = map[string]any{"code": code, "mailCalls": calls}
		case "/drop-create":
			mu.Lock()
			armCreate = true
			mu.Unlock()
		case "/drop-delete":
			mu.Lock()
			armDelete = true
			mu.Unlock()
		case "/publish":
			_, controlErr = s.c.PublishAcceptedPosts(r.Context(), 100)
		case "/freeze":
			controlErr = s.gate.Freeze(r.Context(), "isolated F4 root test")
		case "/recover":
			controlErr = s.recoverC()
		case "/finalize":
			s.advanceC(7*24*time.Hour + time.Second)
			var finalized int64
			finalized, controlErr = s.c.FinalizeDueClosures(r.Context(), 10)
			if controlErr == nil && finalized != 1 {
				controlErr = fmt.Errorf("expected one owned closure")
			}
		case "/stats":
			mu.Lock()
			result = map[string]int{"creates": creates, "deletes": deletes, "dropped": dropped, "queryDrops": queryDrops}
			mu.Unlock()
		default:
			w.WriteHeader(404)
			return
		}
		if controlErr != nil {
			t.Errorf("F4 control %s failed", r.URL.Path)
			w.WriteHeader(500)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(result)
	}), s.cPublic.TLS)
	dir := t.TempDir()
	ca := filepath.Join(dir, "ca.pem")
	if err = os.WriteFile(ca, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: s.cPublic.TLS.Certificates[0].Certificate[1]}), 0600); err != nil {
		t.Fatal(err)
	}
	cfg, err := json.Marshal(map[string]string{"communityOrigin": s.cPublic.URL, "verifierOrigin": s.vPublic.URL, "controlOrigin": control.URL, "controlToken": token, "caPath": ca, "runDir": dir})
	if err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(dir, "config.json")
	if err = os.WriteFile(configPath, cfg, 0600); err != nil {
		t.Fatal(err)
	}
	for _, phase := range []string{"write", "read"} {
		if phase == "read" {
			mu.Lock()
			holdQuery = false
			mu.Unlock()
		}
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		cmd := exec.CommandContext(ctx, flutter, "test", "--no-pub", "--reporter", "expanded", "integration/f4_main_https_postgres_test.dart")
		cmd.Dir = filepath.Join("..", "..", "..", "..", "apps", "mobile")
		cmd.Env = append(os.Environ(), "F4_MAIN_CONFIG="+configPath, "F4_MAIN_PHASE="+phase)
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		runErr := cmd.Run()
		cancel()
		if runErr != nil {
			t.Fatalf("F4 production root %s failed: %v", phase, runErr)
		}
	}
	checkpoints := map[string]bool{}
	for _, phase := range []string{"write", "read"} {
		raw, readErr := os.ReadFile(filepath.Join(dir, "checks-"+phase+".json"))
		if readErr != nil {
			t.Fatal("missing completed main phase checks")
		}
		var checks map[string]bool
		if json.Unmarshal(raw, &checks) != nil {
			t.Fatal("invalid completed main phase checks")
		}
		for id, passed := range checks {
			checkpoints[id] = passed
		}
	}
	for _, id := range []string{"F4-H01", "F4-H02", "F4-H03", "F4-H04", "F4-H05", "F4-H06", "F4-H07", "F4-H08"} {
		if !checkpoints[id] {
			t.Fatalf("missing F4 checkpoint %s", id)
		}
	}
	var count, deleted, bindings, tasks int
	for _, q := range []struct {
		query  string
		target *int
	}{{"SELECT count(*) FROM c_posts.posts", &count}, {"SELECT count(*) FROM c_posts.posts WHERE visibility='DELETED'", &deleted}, {"SELECT count(*) FROM c_posts.post_identity_bindings", &bindings}, {"SELECT count(*) FROM c_posts.publication_tasks", &tasks}} {
		if err = s.cp.QueryRow(context.Background(), q.query).Scan(q.target); err != nil {
			t.Fatal("F4 independent SQL assertion failed")
		}
	}
	mu.Lock()
	counts := map[string]int{"creates": creates, "deletes": deletes, "committedResponseDrops": dropped, "queryDrops": queryDrops, "posts": count, "deletedPosts": deleted, "bindings": bindings, "tasks": tasks}
	mu.Unlock()
	if count != 1 || deleted != 1 || bindings != 1 || tasks != 1 || creates != 1 || deletes != 1 || dropped != 2 || queryDrops < 1 {
		t.Fatalf("F4 unexpected bounded counts: %v", counts)
	}
	evidence := map[string]any{"result": "PASS", "checkpoints": checkpoints, "counts": counts, "hostFlutterProcesses": 2, "assembly": "production HnuholeApp root; actual TLS C/V handlers, independent PG, file SQLite; host vault substitutes", "finalAuthenticationCandidate": nil, "finalF4Result": "BLOCKED_DEPENDENCY"}
	if output := os.Getenv("F4_EVIDENCE_DIR"); output != "" {
		data, _ := json.MarshalIndent(evidence, "", "  ")
		if err = os.WriteFile(filepath.Join(output, "main-https-summary.json"), append(data, '\n'), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Logf("F4 current pinned-baseline main/root scoped PASS: %v", counts)
}
