package authprivacyhttp

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/fxamacker/cbor/v2"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

func e2eCredentialSignup(t *testing.T, s *e2eServices) (string, string) {
	t.Helper()
	confirmation := s.confirmation(t, "synthetic-credentials@hainanu.edu.cn")
	confirmed := s.submit(t, confirmation, 200)
	ticketText := confirmed["registrationTicket"].(string)
	installation := e2eInstallation(t)
	intent := e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/registration-intents", map[string]string{
		"registrationTicket": ticketText, "username": "credential_user", "password": "independent credential management password", "installationId": protocol.EncodeCanonicalBase64url(installation[:]),
	}, nil, 201)
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
	created := e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/registrations", map[string]string{
		"intentId": intent["intentId"].(string), "bootstrapSignature": protocol.EncodeCanonicalBase64url(ed25519.Sign(confirmation.bootstrap, message[:])),
		"recoveryCodeConfirmation": intent["recoveryCode"].(string),
	}, map[string]string{"Idempotency-Key": protocol.EncodeCanonicalBase64url(key[:])}, 201)
	return created["sessionToken"].(string), intent["recoveryCode"].(string)
}

// Unlike fake-authority HTTP tests, these assertions cross HTTPS, the published
// JSON shape, real WebAuthn cryptography, the Safety Gate and PostgreSQL commit.
func e2eCredential204(t *testing.T, s *e2eServices, method, path string, body any, headers map[string]string) {
	t.Helper()
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(encoded)
	}
	request, err := http.NewRequest(method, s.cPublic.URL+path, reader)
	if err != nil {
		t.Fatal(err)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	for name, value := range headers {
		request.Header.Set(name, value)
	}
	response, err := s.client.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	raw, err := io.ReadAll(response.Body)
	if err != nil || response.StatusCode != 204 || len(raw) != 0 || response.Header.Get("Cache-Control") != "no-store" {
		t.Fatalf("credential commit %s returned %d %s, err=%v", path, response.StatusCode, raw, err)
	}
	if _, err := time.Parse(time.RFC3339Nano, response.Header.Get("Session-Expires-At")); err != nil {
		t.Fatal("credential commit did not expose authoritative session expiry")
	}
}

func e2ePasskeyAttestation(t *testing.T, options map[string]any, key *ecdsa.PrivateKey, credential []byte) map[string]any {
	t.Helper()
	publicKey := options["publicKey"].(map[string]any)
	clientData, err := json.Marshal(map[string]any{"type": "webauthn.create", "challenge": publicKey["challenge"], "origin": "https://client.hnuhole.test"})
	if err != nil {
		t.Fatal(err)
	}
	cose, err := cbor.Marshal(map[int]any{1: 2, 3: -7, -1: 1, -2: key.X.FillBytes(make([]byte, 32)), -3: key.Y.FillBytes(make([]byte, 32))})
	if err != nil {
		t.Fatal(err)
	}
	rpHash := sha256.Sum256([]byte("hnuhole.test"))
	authData := append([]byte(nil), rpHash[:]...)
	authData = append(authData, 0x45, 0, 0, 0, 1) // UP, UV, attested credential data, count=1.
	authData = append(authData, make([]byte, 16)...)
	authData = binary.BigEndian.AppendUint16(authData, uint16(len(credential)))
	authData = append(authData, credential...)
	authData = append(authData, cose...)
	attestation, err := cbor.Marshal(map[string]any{"fmt": "none", "attStmt": map[string]any{}, "authData": authData})
	if err != nil {
		t.Fatal(err)
	}
	id := protocol.EncodeCanonicalBase64url(credential)
	return map[string]any{"challengeId": options["challengeId"], "webauthnAttestation": map[string]any{
		"id": id, "rawId": id, "type": "public-key", "clientExtensionResults": map[string]any{},
		"response": map[string]any{"clientDataJSON": protocol.EncodeCanonicalBase64url(clientData), "attestationObject": protocol.EncodeCanonicalBase64url(attestation), "transports": []string{"internal"}},
	}}
}

func e2ePasskeyAssertion(t *testing.T, options map[string]any, key *ecdsa.PrivateKey, credential []byte, userHandle string, count uint32) map[string]any {
	t.Helper()
	clientData, err := json.Marshal(map[string]any{"type": "webauthn.get", "challenge": options["publicKey"].(map[string]any)["challenge"], "origin": "https://client.hnuhole.test"})
	if err != nil {
		t.Fatal(err)
	}
	rpHash := sha256.Sum256([]byte("hnuhole.test"))
	authData := append([]byte(nil), rpHash[:]...)
	authData = append(authData, 0x05) // UP + UV, no extensions or attested data.
	authData = binary.BigEndian.AppendUint32(authData, count)
	clientHash := sha256.Sum256(clientData)
	messageHash := sha256.Sum256(append(append([]byte(nil), authData...), clientHash[:]...))
	signature, err := ecdsa.SignASN1(rand.Reader, key, messageHash[:])
	if err != nil {
		t.Fatal(err)
	}
	id := protocol.EncodeCanonicalBase64url(credential)
	return map[string]any{"challengeId": options["challengeId"], "webauthnAssertion": map[string]any{
		"id": id, "rawId": id, "type": "public-key", "clientExtensionResults": map[string]any{},
		"response": map[string]any{"clientDataJSON": protocol.EncodeCanonicalBase64url(clientData), "authenticatorData": protocol.EncodeCanonicalBase64url(authData),
			"signature": protocol.EncodeCanonicalBase64url(signature), "userHandle": userHandle},
	}}
}

func TestHTTPSPostgresRecoveryCredentialManagement(t *testing.T) {
	s := e2eNewServices(t)
	token, oldCode := e2eCredentialSignup(t, s)
	bearer := map[string]string{"Authorization": "Bearer " + token}
	password := map[string]string{"password": "independent credential management password"}
	list := e2eJSON(t, s.client, "GET", s.cPublic.URL+"/api/v1/auth/recovery-credentials", nil, bearer, 200)
	if list["recoveryCodeAvailable"] != true || len(list["passkeys"].([]any)) != 0 {
		t.Fatal("new account lacks mandatory recovery code or has unexpected Passkeys")
	}
	rotation := e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/recovery-code-rotations", password, bearer, 201)
	e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/recovery-code-reset-intents", map[string]string{"recoveryCode": oldCode}, nil, 201)
	rotationKey := e2eKey(t)
	rotationHeaders := map[string]string{"Authorization": bearer["Authorization"], "Idempotency-Key": protocol.EncodeCanonicalBase64url(rotationKey[:])}
	confirmation := map[string]string{"newRecoveryCodeConfirmation": rotation["newRecoveryCode"].(string)}
	rotationPath := rotationPrefix + rotation["rotationIntentId"].(string) + "/confirmations"
	e2eCredential204(t, s, "POST", rotationPath, confirmation, rotationHeaders)
	e2eCredential204(t, s, "POST", rotationPath, confirmation, rotationHeaders)
	e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/recovery-code-reset-intents", map[string]string{"recoveryCode": oldCode}, nil, 401)
	e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/recovery-code-reset-intents", map[string]string{"recoveryCode": rotation["newRecoveryCode"].(string)}, nil, 201)
	e2eJSON(t, s.client, "GET", s.cPublic.URL+"/api/v1/auth/session", nil, bearer, 200)
	options := e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/passkey-options", password, bearer, 200)
	userHandle := options["publicKey"].(map[string]any)["user"].(map[string]any)["id"].(string)
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	credential := e2eKey(t)
	attestation := e2ePasskeyAttestation(t, options, key, credential[:])
	registrationKey := e2eKey(t)
	registrationHeaders := map[string]string{"Authorization": bearer["Authorization"], "Idempotency-Key": protocol.EncodeCanonicalBase64url(registrationKey[:])}
	e2eCredential204(t, s, "POST", "/api/v1/auth/passkeys", attestation, registrationHeaders)
	e2eCredential204(t, s, "POST", "/api/v1/auth/passkeys", attestation, registrationHeaders)
	list = e2eJSON(t, s.client, "GET", s.cPublic.URL+"/api/v1/auth/recovery-credentials", nil, bearer, 200)
	passkeys := list["passkeys"].([]any)
	if len(passkeys) != 1 || passkeys[0].(map[string]any)["credentialId"] != protocol.EncodeCanonicalBase64url(credential[:]) || len(passkeys[0].(map[string]any)) != 4 {
		t.Fatal("binding lost or leaked credential metadata")
	}
	resetOptions := e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/passkey-reset-options", map[string]any{}, nil, 200)
	assertion := e2ePasskeyAssertion(t, resetOptions, key, credential[:], userHandle, 2)
	reset := e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/passkey-reset-intents", assertion, nil, 201)
	if len(reset) != 4 || reset["username"] != "credential_user" || reset["sessionToken"] != nil {
		t.Fatal("Passkey recovery did not restrict authority to reset capability")
	}
	e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/passkey-reset-intents", assertion, nil, 401)
	removal := e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/passkey-removal-intents", map[string]string{"password": password["password"], "credentialId": protocol.EncodeCanonicalBase64url(credential[:])}, bearer, 201)
	removalKey := e2eKey(t)
	removalHeaders := map[string]string{"Authorization": bearer["Authorization"], "Idempotency-Key": protocol.EncodeCanonicalBase64url(removalKey[:]), "Credential-Change-ID": removal["removalIntentId"].(string)}
	removalPath := passkeyPrefix + protocol.EncodeCanonicalBase64url(credential[:])
	e2eCredential204(t, s, "DELETE", removalPath, nil, removalHeaders)
	e2eCredential204(t, s, "DELETE", removalPath, nil, removalHeaders)
	newKey := e2eKey(t)
	removalHeaders["Idempotency-Key"] = protocol.EncodeCanonicalBase64url(newKey[:])
	e2eJSON(t, s.client, "DELETE", s.cPublic.URL+removalPath, nil, removalHeaders, 404)
	resetKey := e2eKey(t)
	e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/password-resets", map[string]string{"resetIntentId": reset["resetIntentId"].(string), "newPassword": "independent reset after removal phrase", "newRecoveryCodeConfirmation": reset["newRecoveryCode"].(string)}, map[string]string{"Idempotency-Key": protocol.EncodeCanonicalBase64url(resetKey[:])}, 409)
	list = e2eJSON(t, s.client, "GET", s.cPublic.URL+"/api/v1/auth/recovery-credentials", nil, bearer, 200)
	if list["recoveryCodeAvailable"] != true || len(list["passkeys"].([]any)) != 0 {
		t.Fatal("Passkey removal deleted mandatory recovery code or retained key")
	}
	resetOptions = e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/passkey-reset-options", map[string]any{}, nil, 200)
	e2eJSON(t, s.client, "POST", s.cPublic.URL+"/api/v1/auth/passkey-reset-intents", e2ePasskeyAssertion(t, resetOptions, key, credential[:], userHandle, 3), nil, 401)
	var active, version int
	if err := s.cp.QueryRow(context.Background(), `SELECT credential_version,(SELECT count(*) FROM c_auth.sessions WHERE account_id=a.account_id AND revoked_at IS NULL) FROM c_auth.accounts a WHERE username='credential_user'`).Scan(&version, &active); err != nil || version != 4 || active != 1 {
		t.Fatalf("credential changes altered sessions or versions: version=%d active=%d err=%v", version, active, err)
	}
	e2eJSON(t, s.client, "GET", s.cPublic.URL+"/api/v1/auth/session", nil, bearer, 200)
}
