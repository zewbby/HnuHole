package authprivacyhttp

import (
	"crypto/ed25519"
	"net/http"
	"reflect"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func e2ePrivacySignup(t *testing.T, s *e2eServices, name string) (token, account string) {
	t.Helper()
	confirmation := s.confirmation(t, name+"@hainanu.edu.cn")
	confirmed := s.submit(t, confirmation, http.StatusOK)
	ticketText := confirmed["registrationTicket"].(string)
	installation := e2eInstallation(t)
	intent := e2eJSON(t, s.client, http.MethodPost, s.cPublic.URL+"/api/v1/auth/registration-intents", map[string]string{
		"registrationTicket": ticketText, "username": name, "password": "separate community privacy audit password", "installationId": protocol.EncodeCanonicalBase64url(installation[:]),
	}, nil, http.StatusCreated)
	ticket, err := protocol.ParseRegistrationTicket(ticketText)
	if err != nil {
		t.Fatal(err)
	}
	rawID, err := protocol.DecodeCanonicalBase64url(intent["intentId"].(string), 32)
	if err != nil {
		t.Fatal(err)
	}
	rawChallenge, err := protocol.DecodeCanonicalBase64url(intent["challenge"].(string), 32)
	if err != nil {
		t.Fatal(err)
	}
	var id protocol.IntentID
	var challenge protocol.Challenge
	copy(id[:], rawID)
	copy(challenge[:], rawChallenge)
	message := protocol.BootstrapMessageBytes(ticket, id, challenge)
	key := e2eKey(t)
	created := e2eJSON(t, s.client, http.MethodPost, s.cPublic.URL+"/api/v1/auth/registrations", map[string]string{
		"intentId": intent["intentId"].(string), "bootstrapSignature": protocol.EncodeCanonicalBase64url(ed25519.Sign(confirmation.bootstrap, message[:])),
		"recoveryCodeConfirmation": intent["recoveryCode"].(string),
	}, map[string]string{"Idempotency-Key": protocol.EncodeCanonicalBase64url(key[:])}, http.StatusCreated)
	return created["sessionToken"].(string), created["accountId"].(string)
}

func TestRealHTTPSIdentityPrivacyIsAccountScopedPostgres(t *testing.T) {
	s := e2eNewServices(t)
	tokenA, accountA := e2ePrivacySignup(t, s, "privacy_user_a")
	tokenB, accountB := e2ePrivacySignup(t, s, "privacy_user_b")
	if accountA == accountB || tokenA == tokenB {
		t.Fatal("two registrations did not create independent accounts")
	}
	create := func(token, nickname string, key byte) map[string]any {
		t.Helper()
		return e2eJSON(t, s.client, http.MethodPost, s.cPublic.URL+identitiesPath, map[string]string{"nickname": nickname}, map[string]string{"Authorization": "Bearer " + token, "Idempotency-Key": httpTestEncoding(16, key)}, 200)
	}
	ownedA := create(tokenA, "甲海风", 41)
	ownedB := create(tokenB, "乙海风", 51)
	secondB := create(tokenB, "乙南风", 52)
	idB := ownedB["identityId"].(string)
	list := func(token string) map[string]any {
		t.Helper()
		return e2eJSON(t, s.client, http.MethodGet, s.cPublic.URL+identitiesPath, nil, map[string]string{"Authorization": "Bearer " + token}, 200)
	}
	assertDirectory := func(directory map[string]any, count int, ids []string) {
		t.Helper()
		items, ok := directory["identities"].([]any)
		if !ok || len(directory) != 4 || len(items) != count || directory["createdCount"] != float64(count) {
			t.Fatal("private identity directory shape changed")
		}
		for _, value := range items {
			item, ok := value.(map[string]any)
			if !ok || len(item) != 6 || item["accountId"] != nil || item["slotId"] != nil || item["username"] != nil {
				t.Fatal("identity directory disclosed account linkage")
			}
			found := false
			for _, id := range ids {
				if item["id"] == id {
					found = true
				}
			}
			if !found {
				t.Fatal("identity from another account appeared in private directory")
			}
		}
	}
	initialB := list(tokenB)
	assertDirectory(list(tokenA), 1, []string{ownedA["identityId"].(string)})
	assertDirectory(initialB, 2, []string{idB, secondB["identityId"].(string)})
	// A cannot distinguish an existing foreign receipt from an absent key. B
	// can still see its own immutable receipt using that same key.
	readReceipt := func(token string, key byte) map[string]any {
		t.Helper()
		return e2eJSON(t, s.client, http.MethodGet, s.cPublic.URL+identityResultPath, nil, map[string]string{"Authorization": "Bearer " + token, "Idempotency-Key": httpTestEncoding(16, key)}, 200)
	}
	foreignReceipt, absentReceipt := readReceipt(tokenA, 51), readReceipt(tokenA, 61)
	if len(foreignReceipt) != 4 || foreignReceipt["state"] != "NOT_FOUND" || !reflect.DeepEqual(foreignReceipt, absentReceipt) {
		t.Fatal("foreign receipt revealed cross-account history")
	}
	if ownReceipt := readReceipt(tokenB, 51); ownReceipt["state"] != "COMMITTED" || ownReceipt["identityId"] != idB {
		t.Fatal("receipt ownership test lost its positive control")
	}
	for i, method := range []string{http.MethodPatch, http.MethodDelete} {
		var knownError map[string]any
		for j, target := range []string{idB, uuid.New().String()} {
			key := byte(70 + i*2 + j)
			input := ""
			if method == http.MethodPatch {
				input = `{"nickname":"越权改名"}`
			}
			response, object, raw := doHTTPTest(t, s.client, method, s.cPublic.URL+identitiesPath+"/"+target, input, map[string][]string{"Authorization": {"Bearer " + tokenA}, "Idempotency-Key": {httpTestEncoding(16, key)}, "Content-Type": {"application/json"}})
			if response.StatusCode != 404 || response.Header.Get("Session-Expires-At") != "" || object["error"].(map[string]any)["code"] != "IDENTITY_NOT_FOUND" {
				t.Fatal("foreign identity did not share the absent-resource error")
			}
			for _, secret := range []string{idB, accountA, accountB, "乙海风", "乙南风"} {
				if strings.Contains(raw, secret) {
					t.Fatal("resource error disclosed identity ownership")
				}
			}
			delete(object, "requestId")
			if j == 0 {
				knownError = object
			} else if !reflect.DeepEqual(knownError, object) {
				t.Fatal("known foreign and absent identity errors differ")
			}
			if receipt := readReceipt(tokenA, key); receipt["state"] != "REJECTED" || receipt["errorCode"] != "IDENTITY_NOT_FOUND" || receipt["identityId"] != nil {
				t.Fatal("foreign mutation result disclosed or authorized the target")
			}
		}
	}
	// There is no UUID lookup route and no caller-supplied account selector.
	for _, target := range []string{idB, uuid.New().String()} {
		response, _, _ := doHTTPTest(t, s.client, http.MethodGet, s.cPublic.URL+identitiesPath+"/"+target, "", map[string][]string{"Authorization": {"Bearer " + tokenA}})
		if response.StatusCode != http.StatusMethodNotAllowed {
			t.Fatal("arbitrary UUID became a private lookup")
		}
	}
	response, directory, _ := doHTTPTest(t, s.client, http.MethodGet, s.cPublic.URL+identitiesPath, "", map[string][]string{"Authorization": {"Bearer " + tokenA}, "X-Account-ID": {accountB}})
	if response.StatusCode != 200 {
		t.Fatal("owner directory positive control failed")
	}
	assertDirectory(directory, 1, []string{ownedA["identityId"].(string)})
	for _, field := range []string{"accountId", "slotId", "identityId", "isOriginal"} {
		response, _, _ := doHTTPTest(t, s.client, http.MethodPost, s.cPublic.URL+identitiesPath, `{"nickname":"拒绝注入","`+field+`":"`+accountB+`"}`, map[string][]string{"Authorization": {"Bearer " + tokenA}, "Idempotency-Key": {httpTestEncoding(16, 90)}, "Content-Type": {"application/json"}})
		if response.StatusCode != 400 {
			t.Fatal("undocumented ownership field was accepted")
		}
	}
	for _, target := range []struct {
		path   string
		status int
	}{
		{identitiesPath + "?accountId=" + accountB, 400},
		{"/api/v1/accounts/" + accountB + "/identities", 404},
	} {
		response, _, _ := doHTTPTest(t, s.client, http.MethodGet, s.cPublic.URL+target.path, "", map[string][]string{"Authorization": {"Bearer " + tokenA}})
		if response.StatusCode != target.status {
			t.Fatal("account selector route was accepted")
		}
	}
	for _, path := range []string{identitiesPath, identityResultPath} {
		response, _, _ := doHTTPTest(t, s.client, http.MethodGet, s.cPublic.URL+path, "", map[string][]string{"Idempotency-Key": {httpTestEncoding(16, 51)}})
		if response.StatusCode != 401 {
			t.Fatal("private identity surface was accessible without a session")
		}
	}
	finalB := list(tokenB)
	// serverTime advances on each authoritative read; profile/counter/receipt
	// history must not be affected by another account's attempts.
	delete(initialB, "serverTime")
	delete(finalB, "serverTime")
	if !reflect.DeepEqual(initialB, finalB) {
		t.Fatal("foreign identity attempt changed the owner's profiles or cumulative quota")
	}
	assertDirectory(list(tokenA), 1, []string{ownedA["identityId"].(string)})
}
