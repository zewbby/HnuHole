package authprivacyhttp

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

const rotationPrefix = "/api/v1/auth/recovery-code-rotations/"
const passkeyPrefix = "/api/v1/auth/passkeys/"

func isRotationConfirmationPath(path string) bool {
	if !strings.HasPrefix(path, rotationPrefix) || !strings.HasSuffix(path, "/confirmations") {
		return false
	}
	id := strings.TrimSuffix(strings.TrimPrefix(path, rotationPrefix), "/confirmations")
	return id != "" && !strings.Contains(id, "/")
}

func isPasskeyRemovalPath(path string) bool {
	if !strings.HasPrefix(path, passkeyPrefix) {
		return false
	}
	id := strings.TrimPrefix(path, passkeyPrefix)
	return id != "" && !strings.Contains(id, "/")
}

func isCredentialPath(path string) bool {
	switch path {
	case "/api/v1/auth/recovery-credentials", "/api/v1/auth/recovery-code-rotations", "/api/v1/auth/passkey-options",
		"/api/v1/auth/passkeys", "/api/v1/auth/passkey-removal-intents", "/api/v1/auth/passkey-reset-options", "/api/v1/auth/passkey-reset-intents":
		return true
	}
	return isRotationConfirmationPath(path) || isPasskeyRemovalPath(path)
}

func canonicalSized(value string, minimum, maximum int) bool {
	if len(value) > base64.RawURLEncoding.EncodedLen(maximum) {
		return false
	}
	raw, err := base64.RawURLEncoding.Strict().DecodeString(value)
	return err == nil && len(raw) >= minimum && len(raw) <= maximum && base64.RawURLEncoding.EncodeToString(raw) == value
}

func nestedObject(object map[string]any, field string, required, optional []string) (map[string]any, error) {
	child, ok := object[field].(map[string]any)
	if !ok || fields(child, required, optional) != nil {
		return nil, errMalformed
	}
	return child, nil
}

// These functions retain only the signed fields the authority validator needs.
// Optional transports are checked, then discarded rather than stored as device
// characteristics. parseObject has already rejected duplicates at every depth.
func registrationFields(object map[string]any) (authprivacy.RegistrationResponse, error) {
	var result authprivacy.RegistrationResponse
	credential, err := nestedObject(object, "webauthnAttestation", []string{"id", "rawId", "type", "response", "clientExtensionResults"}, nil)
	if err != nil {
		return result, err
	}
	response, err := nestedObject(credential, "response", []string{"clientDataJSON", "attestationObject"}, []string{"transports"})
	if err != nil {
		return result, err
	}
	if _, err = nestedObject(credential, "clientExtensionResults", nil, nil); err != nil {
		return result, err
	}
	result.ID, err = stringField(credential, "id")
	if err != nil || !canonicalSized(result.ID, 1, 1023) {
		return result, errMalformed
	}
	result.RawID, err = stringField(credential, "rawId")
	if err != nil || result.RawID != result.ID {
		return result, errMalformed
	}
	result.Type, err = stringField(credential, "type")
	if err != nil || result.Type != "public-key" {
		return result, errMalformed
	}
	result.ClientDataJSON, err = stringField(response, "clientDataJSON")
	if err != nil || !canonicalSized(result.ClientDataJSON, 1, 3072) {
		return result, errMalformed
	}
	result.AttestationObject, err = stringField(response, "attestationObject")
	if err != nil || !canonicalSized(result.AttestationObject, 1, 4096) {
		return result, errMalformed
	}
	if raw, present := response["transports"]; present {
		transports, ok := raw.([]any)
		if !ok || len(transports) > 5 {
			return result, errMalformed
		}
		seen := make(map[string]bool, len(transports))
		for _, item := range transports {
			value, ok := item.(string)
			if !ok || seen[value] {
				return result, errMalformed
			}
			switch value {
			case "usb", "nfc", "ble", "internal", "hybrid":
			default:
				return result, errMalformed
			}
			seen[value] = true
		}
	}
	return result, nil
}

func assertionFields(object map[string]any) (authprivacy.AssertionResponse, error) {
	var result authprivacy.AssertionResponse
	credential, err := nestedObject(object, "webauthnAssertion", []string{"id", "rawId", "type", "response", "clientExtensionResults"}, nil)
	if err != nil {
		return result, err
	}
	response, err := nestedObject(credential, "response", []string{"clientDataJSON", "authenticatorData", "signature", "userHandle"}, nil)
	if err != nil {
		return result, err
	}
	if _, err = nestedObject(credential, "clientExtensionResults", nil, nil); err != nil {
		return result, err
	}
	result.ID, err = stringField(credential, "id")
	if err != nil || !canonicalSized(result.ID, 1, 1023) {
		return result, errMalformed
	}
	result.RawID, err = stringField(credential, "rawId")
	if err != nil || result.RawID != result.ID {
		return result, errMalformed
	}
	result.Type, err = stringField(credential, "type")
	if err != nil || result.Type != "public-key" {
		return result, errMalformed
	}
	for _, field := range []struct {
		name             string
		value            *string
		minimum, maximum int
	}{
		{"clientDataJSON", &result.ClientDataJSON, 1, 3072},
		{"authenticatorData", &result.AuthenticatorData, 37, 2048},
		{"signature", &result.Signature, 8, 1024},
		{"userHandle", &result.UserHandle, 32, 32},
	} {
		*field.value, err = stringField(response, field.name)
		if err != nil || !canonicalSized(*field.value, field.minimum, field.maximum) {
			return result, errMalformed
		}
	}
	return result, nil
}

func (b *boundary) credentialExpiry(w http.ResponseWriter, expires time.Time) bool {
	if expires.IsZero() {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return false
	}
	w.Header().Set("Session-Expires-At", utc(expires))
	return true
}

func (b *boundary) communityCredentialPublic(w http.ResponseWriter, r *http.Request, backend authprivacy.CredentialBackend, passwords PasswordPreparer) {
	if backend == nil {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if r.URL.Path == "/api/v1/auth/passkey-reset-options" || r.URL.Path == "/api/v1/auth/passkey-reset-intents" {
		b.passkeyRecoveryPublic(w, r, backend)
		return
	}
	bearer, err := sessionCapability(r.Header, "Bearer")
	if err != nil {
		b.sessionCapabilityFailure(w, err)
		return
	}
	mutation := r.URL.Path == "/api/v1/auth/passkeys" || isRotationConfirmationPath(r.URL.Path) || isPasskeyRemovalPath(r.URL.Path)
	var key [32]byte
	if mutation {
		raw, err := headerBytes(r.Header, "Idempotency-Key", 32)
		if err != nil {
			b.bad(w, err)
			return
		}
		copy(key[:], raw)
	} else if hasHeader(r.Header, "Idempotency-Key") {
		b.bad(w, errMalformed)
		return
	}
	switch {
	case r.URL.Path == "/api/v1/auth/recovery-credentials":
		if noBodyOrQuery(r) != nil {
			b.bad(w, errMalformed)
			return
		}
		result, err := backend.GetRecoveryCredentials(r.Context(), bearer)
		if err != nil {
			b.credentialFailure(w, err)
			return
		}
		if !result.RecoveryCodeAvailable || len(result.Passkeys) > 10 {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		passkeys := make([]map[string]any, 0, len(result.Passkeys))
		seen := make(map[string]bool, len(result.Passkeys))
		for i, item := range result.Passkeys {
			if !canonicalSized(item.CredentialID, 1, 1023) || item.CreatedAt.IsZero() || seen[item.CredentialID] ||
				(item.BackedUp && !item.BackupEligible) || (i > 0 && (item.CreatedAt.Before(result.Passkeys[i-1].CreatedAt) ||
				(item.CreatedAt.Equal(result.Passkeys[i-1].CreatedAt) && item.CredentialID <= result.Passkeys[i-1].CredentialID))) {
				b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
				return
			}
			seen[item.CredentialID] = true
			passkeys = append(passkeys, map[string]any{"credentialId": item.CredentialID, "createdAt": utc(item.CreatedAt), "backupEligible": item.BackupEligible, "backedUp": item.BackedUp})
		}
		if b.credentialExpiry(w, result.SessionExpiresAt) {
			writeJSON(w, 200, map[string]any{"recoveryCodeAvailable": true, "passkeys": passkeys})
		}
	case isPasskeyRemovalPath(r.URL.Path):
		credentialID := strings.TrimPrefix(r.URL.Path, passkeyPrefix)
		intentRaw, err := headerBytes(r.Header, "Credential-Change-ID", 32)
		if err != nil || !canonicalSized(credentialID, 1, 1023) || noBodyOrQuery(r) != nil {
			b.bad(w, errMalformed)
			return
		}
		request := authprivacy.PasskeyRemoval{CredentialID: credentialID, IdempotencyKey: key}
		copy(request.IntentID[:], intentRaw)
		expires, err := backend.RemovePasskey(r.Context(), bearer, request)
		if err != nil {
			b.credentialFailure(w, err)
			return
		}
		if b.credentialExpiry(w, expires) {
			w.WriteHeader(204)
		}
	case isRotationConfirmationPath(r.URL.Path):
		rawID, err := protocol.DecodeCanonicalBase64url(strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, rotationPrefix), "/confirmations"), 32)
		if err != nil {
			b.bad(w, errMalformed)
			return
		}
		object, err := readRequestObject(r, 8192, []string{"newRecoveryCodeConfirmation"}, nil)
		if err != nil {
			b.bad(w, err)
			return
		}
		code, err := stringField(object, "newRecoveryCodeConfirmation")
		if err != nil || !validRecoveryCode(code, false) {
			b.bad(w, errMalformed)
			return
		}
		request := authprivacy.CodeRotationConfirmation{IdempotencyKey: key, NewRecoveryCodeConfirmation: code}
		copy(request.IntentID[:], rawID)
		expires, err := backend.ConfirmRecoveryCodeRotation(r.Context(), bearer, request)
		if err != nil {
			b.credentialFailure(w, err)
			return
		}
		if b.credentialExpiry(w, expires) {
			w.WriteHeader(204)
		}
	case r.URL.Path == "/api/v1/auth/passkeys":
		object, err := readRequestObject(r, 32768, []string{"challengeId", "webauthnAttestation"}, nil)
		if err != nil {
			b.bad(w, err)
			return
		}
		challenge, e1 := encoded32Field(object, "challengeId")
		response, e2 := registrationFields(object)
		if e1 != nil || e2 != nil {
			b.bad(w, errMalformed)
			return
		}
		expires, err := backend.RegisterPasskey(r.Context(), bearer, authprivacy.PasskeyRegistration{ChallengeID: challenge, IdempotencyKey: key, Response: response})
		if err != nil {
			b.credentialFailure(w, err)
			return
		}
		if b.credentialExpiry(w, expires) {
			w.WriteHeader(204)
		}
	default:
		b.passwordCredentialPublic(w, r, backend, passwords, bearer)
	}
}

func (b *boundary) passwordCredentialPublic(w http.ResponseWriter, r *http.Request, backend authprivacy.CredentialBackend, passwords PasswordPreparer, bearer [32]byte) {
	required, limit := []string{"password"}, int64(8192)
	if r.URL.Path == "/api/v1/auth/passkey-removal-intents" {
		required, limit = []string{"credentialId", "password"}, 32768
	}
	object, err := readRequestObject(r, limit, required, nil)
	if err != nil {
		b.bad(w, err)
		return
	}
	password, err := stringField(object, "password")
	if err != nil || !validPasswordInput(password) {
		b.bad(w, errMalformed)
		return
	}
	switch r.URL.Path {
	case "/api/v1/auth/recovery-code-rotations":
		result, err := backend.CreateRecoveryCodeRotation(r.Context(), bearer, password, passwords)
		if err != nil {
			b.credentialFailure(w, err)
			return
		}
		if result.ID == ([32]byte{}) || result.ExpiresAt.IsZero() || !validRecoveryCode(result.NewRecoveryCode, true) {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		if b.credentialExpiry(w, result.SessionExpiresAt) {
			writeJSON(w, 201, map[string]string{"rotationIntentId": protocol.EncodeCanonicalBase64url(result.ID[:]), "expiresAt": utc(result.ExpiresAt), "newRecoveryCode": result.NewRecoveryCode})
		}
	case "/api/v1/auth/passkey-options":
		result, err := backend.CreatePasskeyOptions(r.Context(), bearer, password, passwords)
		if err != nil {
			b.credentialFailure(w, err)
			return
		}
		b.passkeyOptionsResponse(w, result, false)
	case "/api/v1/auth/passkey-removal-intents":
		credentialID, err := stringField(object, "credentialId")
		if err != nil || !canonicalSized(credentialID, 1, 1023) {
			b.bad(w, errMalformed)
			return
		}
		result, err := backend.CreatePasskeyRemovalIntent(r.Context(), bearer, password, credentialID, passwords)
		if err != nil {
			b.credentialFailure(w, err)
			return
		}
		if result.ID == ([32]byte{}) || result.ExpiresAt.IsZero() {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		if b.credentialExpiry(w, result.SessionExpiresAt) {
			writeJSON(w, 201, map[string]string{"removalIntentId": protocol.EncodeCanonicalBase64url(result.ID[:]), "expiresAt": utc(result.ExpiresAt)})
		}
	}
}

func (b *boundary) passkeyRecoveryPublic(w http.ResponseWriter, r *http.Request, backend authprivacy.CredentialBackend) {
	if hasHeader(r.Header, "Authorization") || hasHeader(r.Header, "Idempotency-Key") {
		b.bad(w, errMalformed)
		return
	}
	if r.URL.Path == "/api/v1/auth/passkey-reset-options" {
		if _, err := readRequestObject(r, 8192, nil, nil); err != nil {
			b.bad(w, err)
			return
		}
		result, err := backend.CreatePasskeyResetOptions(r.Context())
		if err != nil {
			b.credentialFailure(w, err)
			return
		}
		b.passkeyOptionsResponse(w, result, true)
		return
	}
	object, err := readRequestObject(r, 32768, []string{"challengeId", "webauthnAssertion"}, nil)
	if err != nil {
		b.bad(w, err)
		return
	}
	challenge, e1 := encoded32Field(object, "challengeId")
	response, e2 := assertionFields(object)
	if e1 != nil || e2 != nil {
		b.bad(w, errMalformed)
		return
	}
	result, err := backend.CreatePasskeyResetIntent(r.Context(), authprivacy.PasskeyResetProof{ChallengeID: challenge, Response: response})
	if err != nil {
		b.credentialFailure(w, err)
		return
	}
	if result.ID == ([32]byte{}) || result.ExpiresAt.IsZero() || !privateUsername.MatchString(result.Username) || !validRecoveryCode(result.NewRecoveryCode, true) {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	writeJSON(w, 201, map[string]string{"resetIntentId": protocol.EncodeCanonicalBase64url(result.ID[:]), "expiresAt": utc(result.ExpiresAt), "username": result.Username, "newRecoveryCode": result.NewRecoveryCode})
}

func (b *boundary) credentialFailure(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, authprivacy.ErrCredentialNotFound):
		b.fail(w, 404, "RESOURCE_NOT_FOUND", 0)
	case errors.Is(err, authprivacy.ErrCredentialIntentInvalid):
		b.fail(w, 409, "INTENT_INVALID", 0)
	case errors.Is(err, authprivacy.ErrCredentialIntentExpired):
		b.fail(w, 410, "INTENT_EXPIRED", 0)
	case errors.Is(err, authprivacy.ErrPasskeyLimit):
		b.fail(w, 409, "CREDENTIAL_LIMIT_REACHED", 0)
	case errors.Is(err, authprivacy.ErrWebAuthnValidation):
		b.fail(w, 422, "CHALLENGE_INVALID", 0)
	default:
		b.recoveryClosureFailure(w, err)
	}
}

// PublicKey is a typed boundary represented by a map for browser compatibility.
// Reparse a bounded copy and validate every property before exposing it. This
// prevents backend additions from leaking identifiers or widening RP policy.
func publicKeyOptions(value map[string]any, recovery bool) (map[string]any, error) {
	raw, err := json.Marshal(value)
	if err != nil || len(raw) > 32768 {
		return nil, errMalformed
	}
	object, err := parseObject(bytes.NewReader(raw), 32768)
	if err != nil {
		return nil, err
	}
	required := []string{"challenge", "rpId", "timeout", "userVerification"}
	if !recovery {
		required = []string{"challenge", "rp", "user", "pubKeyCredParams", "timeout", "excludeCredentials", "authenticatorSelection", "attestation"}
	}
	if fields(object, required, nil) != nil {
		return nil, errMalformed
	}
	challenge, err := stringField(object, "challenge")
	if err != nil || !canonicalSized(challenge, 32, 32) {
		return nil, errMalformed
	}
	if _, err = integerField(object, "timeout", 60000, 60000); err != nil {
		return nil, err
	}
	if recovery {
		rp, e1 := stringField(object, "rpId")
		uv, e2 := stringField(object, "userVerification")
		if e1 != nil || e2 != nil || rp == "" || len(rp) > 253 || uv != "required" {
			return nil, errMalformed
		}
		return map[string]any{"challenge": challenge, "rpId": rp, "timeout": 60000, "userVerification": "required"}, nil
	}
	rp, e1 := nestedObject(object, "rp", []string{"id", "name"}, nil)
	user, e2 := nestedObject(object, "user", []string{"id", "name", "displayName"}, nil)
	selection, e3 := nestedObject(object, "authenticatorSelection", []string{"residentKey", "requireResidentKey", "userVerification"}, nil)
	if e1 != nil || e2 != nil || e3 != nil {
		return nil, errMalformed
	}
	rpID, e1 := stringField(rp, "id")
	rpName, e2 := stringField(rp, "name")
	userID, e3 := stringField(user, "id")
	userName, e4 := stringField(user, "name")
	display, e5 := stringField(user, "displayName")
	resident, e6 := stringField(selection, "residentKey")
	uv, e7 := stringField(selection, "userVerification")
	requireResident, ok := selection["requireResidentKey"].(bool)
	attestation, e8 := stringField(object, "attestation")
	if e1 != nil || e2 != nil || e3 != nil || e4 != nil || e5 != nil || e6 != nil || e7 != nil || e8 != nil || rpID == "" || len(rpID) > 253 ||
		rpName != "Hnuhole" || !canonicalSized(userID, 32, 32) || userName != userID || display != "Hnuhole account" ||
		resident != "required" || uv != "required" || !ok || !requireResident || attestation != "none" {
		return nil, errMalformed
	}
	algorithms, ok := object["pubKeyCredParams"].([]any)
	if !ok || len(algorithms) != 1 {
		return nil, errMalformed
	}
	algorithm, ok := algorithms[0].(map[string]any)
	if !ok || fields(algorithm, []string{"type", "alg"}, nil) != nil {
		return nil, errMalformed
	}
	algType, err := stringField(algorithm, "type")
	if _, e := integerField(algorithm, "alg", -7, -7); e != nil || err != nil || algType != "public-key" {
		return nil, errMalformed
	}
	credentials, ok := object["excludeCredentials"].([]any)
	if !ok || len(credentials) > 10 {
		return nil, errMalformed
	}
	exclude := make([]map[string]string, 0, len(credentials))
	seen := make(map[string]bool, len(credentials))
	for _, raw := range credentials {
		item, ok := raw.(map[string]any)
		if !ok || fields(item, []string{"type", "id"}, nil) != nil {
			return nil, errMalformed
		}
		kind, e1 := stringField(item, "type")
		id, e2 := stringField(item, "id")
		if e1 != nil || e2 != nil || kind != "public-key" || !canonicalSized(id, 1, 1023) || seen[id] {
			return nil, errMalformed
		}
		seen[id] = true
		exclude = append(exclude, map[string]string{"type": "public-key", "id": id})
	}
	return map[string]any{"challenge": challenge, "timeout": 60000, "rp": map[string]string{"id": rpID, "name": "Hnuhole"},
		"user":             map[string]string{"id": userID, "name": userID, "displayName": "Hnuhole account"},
		"pubKeyCredParams": []map[string]any{{"type": "public-key", "alg": -7}}, "excludeCredentials": exclude,
		"authenticatorSelection": map[string]any{"residentKey": "required", "requireResidentKey": true, "userVerification": "required"}, "attestation": "none"}, nil
}

func (b *boundary) passkeyOptionsResponse(w http.ResponseWriter, result authprivacy.PasskeyOptions, recovery bool) {
	options, err := publicKeyOptions(result.PublicKey, recovery)
	if err != nil || result.ChallengeID == ([32]byte{}) || result.ExpiresAt.IsZero() || (recovery && !result.SessionExpiresAt.IsZero()) {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if !recovery && !b.credentialExpiry(w, result.SessionExpiresAt) {
		return
	}
	writeJSON(w, 200, map[string]any{"challengeId": protocol.EncodeCanonicalBase64url(result.ChallengeID[:]), "expiresAt": utc(result.ExpiresAt), "publicKey": options})
}
