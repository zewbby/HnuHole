package authprivacyhttp

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestRealHTTPSIdentityAvatarUploadCombinationAndDraftRecoveryPostgres(t *testing.T) {
	python := os.Getenv("POST_MEDIA_PYTHON")
	if python == "" {
		t.Skip("real image validator absent")
	}
	script := os.Getenv("POST_MEDIA_VALIDATOR")
	if script == "" {
		script, _ = filepath.Abs("../../media/validate_image.py")
	}
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
		c, e = c.WithPostImages(context.Background(), validator)
		if e != nil {
			t.Fatal(e)
		}
		return c
	})
	owner, _ := e2ePrivacySignup(t, s, "avatar_https_owner")
	reader, _ := e2ePrivacySignup(t, s, "avatar_https_reader")
	data, e := os.ReadFile(filepath.Join(os.Getenv("POST_MEDIA_FIXTURES"), "jpeg.bin"))
	if e != nil {
		t.Fatal(e)
	}
	request := func(method, token string, id uuid.UUID, payload []byte, status int) []byte {
		t.Helper()
		r, e := http.NewRequest(method, s.cPublic.URL+identityAvatarPath+id.String(), bytes.NewReader(payload))
		if e != nil {
			t.Fatal(e)
		}
		r.Header.Set("Authorization", "Bearer "+token)
		if method == "PUT" {
			r.Header.Set("Content-Type", "image/jpeg")
		}
		response, e := s.client.Do(r)
		if e != nil {
			t.Fatal(e)
		}
		defer response.Body.Close()
		raw, e := io.ReadAll(io.LimitReader(response.Body, postmedia.MaxThumbnailBytes+1))
		if e != nil || response.StatusCode != status {
			t.Fatalf("avatar %s got %d want %d", method, response.StatusCode, status)
		}
		if response.Header.Get("Cache-Control") != "no-store" {
			t.Fatal("avatar cache envelope")
		}
		if status == 200 && method == "GET" && (response.Header.Get("Content-Type") != "image/webp" || response.Header.Get("X-Content-Type-Options") != "nosniff" || response.Header.Get("Session-Expires-At") == "") {
			t.Fatal("avatar response boundary")
		}
		return raw
	}
	// Treat three successful PUT responses as lost to the caller. Each original
	// reference resolves, and explicit replacement releases the previous budget.
	var prior uuid.UUID
	for n := 0; n < 4; n++ {
		if prior != uuid.Nil {
			request("DELETE", owner, prior, nil, 204)
			request("PUT", owner, prior, data, 409)
		}
		prior = uuid.New()
		request("PUT", owner, prior, data, 200)
		if raw := request("GET", owner, prior, nil, 200); len(raw) < 12 || string(raw[8:12]) != "WEBP" {
			t.Fatal("could not recover lost PUT receipt")
		}
		request("GET", reader, prior, nil, 404)
	}
	ref := "avatar-v1:" + prior.String()
	created := e2eJSON(t, s.client, "POST", s.cPublic.URL+identitiesPath, map[string]string{"nickname": "蓝海风", "avatar": ref}, map[string]string{"Authorization": "Bearer " + owner, "Idempotency-Key": httpTestEncoding(16, 101)}, 200)
	id := created["identityId"].(string)
	request("GET", reader, prior, nil, 200)
	request("DELETE", owner, prior, nil, 409)
	next := uuid.New()
	request("PUT", owner, next, data, 200)
	patch := map[string]string{"nickname": "绿海风", "avatar": "avatar-v1:" + next.String()}
	headers := map[string]string{"Authorization": "Bearer " + owner, "Idempotency-Key": httpTestEncoding(16, 102)}
	changed := e2eJSON(t, s.client, "PATCH", s.cPublic.URL+identitiesPath+"/"+id, patch, headers, 200)
	if changed["operation"] != "RENAME" {
		t.Fatal("combined PATCH changed operation")
	}
	e2eJSON(t, s.client, "PATCH", s.cPublic.URL+identitiesPath+"/"+id, patch, headers, 200)
	conflict := e2eJSON(t, s.client, "PATCH", s.cPublic.URL+identitiesPath+"/"+id, map[string]string{"nickname": "绿海风", "avatar": "default-v1"}, headers, 409)
	if conflict["error"].(map[string]any)["code"] != "IDENTITY_CHANGE_CONFLICT" {
		t.Fatal("same key avatar change not rejected")
	}
	request("GET", reader, prior, nil, 404)
	e2eJSON(t, s.client, "PATCH", s.cPublic.URL+identitiesPath+"/"+id, map[string]string{"nickname": "再改名", "avatar": "default-v1"}, map[string]string{"Authorization": "Bearer " + owner, "Idempotency-Key": httpTestEncoding(16, 103)}, 409)
	e2eJSON(t, s.client, "PATCH", s.cPublic.URL+identitiesPath+"/"+id, map[string]string{"avatar": "default-v1"}, map[string]string{"Authorization": "Bearer " + owner, "Idempotency-Key": httpTestEncoding(16, 104)}, 200)
	request("GET", reader, next, nil, 404)
	directory := e2eJSON(t, s.client, "GET", s.cPublic.URL+identitiesPath, nil, map[string]string{"Authorization": "Bearer " + owner}, 200)
	if directory["createdCount"] != float64(1) {
		t.Fatal("avatar changed creation counter")
	}
	raw, _ := json.Marshal(directory)
	if bytes.Contains(raw, []byte("accountId")) {
		t.Fatal("avatar directory disclosed owner")
	}
}
