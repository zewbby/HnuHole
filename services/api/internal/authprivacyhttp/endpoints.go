// Package authprivacyhttp contains isolated V/C HTTP boundaries. Its public and
// internal handlers are separate and share the C/V development runtime boundary.
package authprivacyhttp

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/base32"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type EligibilityBackend interface {
	RequestOTP(context.Context, authprivacy.OTPRequest) (authprivacy.OTPRequestResult, error)
	GetOTPRequestResult(context.Context, [32]byte, [16]byte) (authprivacy.OTPRequestResult, error)
	ConfirmOTP(context.Context, authprivacy.ConfirmOTPRequest) (authprivacy.ConfirmationResult, error)
	GetOTPConfirmationResult(context.Context, [32]byte, [32]byte, [16]byte) (authprivacy.ConfirmationResult, error)
}

type ReceiptProcessor interface {
	ProcessReceipt(context.Context, string, protocol.Purpose) error
}

type CommunityBackend interface {
	ValidateSignupTicket(context.Context, string) (authprivacy.AuthorizationDecision, error)
	CreateSignupIntent(context.Context, string, string, authprivacy.PasswordMaterial, [16]byte, uint64) (authprivacy.SignupIntent, error)
	CommitSignup(context.Context, authprivacy.SignupRequest) (authprivacy.SignupResult, error)
	RetireUnusedSlot(context.Context, string) (authprivacy.RetirementReply, error)
}

type SessionBackend interface {
	CreateSession(context.Context, authprivacy.SessionCreateRequest, authprivacy.PasswordVerifier) (authprivacy.SessionCreateResult, error)
	GetCurrentSession(context.Context, [32]byte) (authprivacy.SessionView, error)
	RenewCurrentSession(context.Context, [32]byte) (time.Time, error)
	GetDevices(context.Context, [32]byte) (authprivacy.SessionView, error)
	RevokeSession(context.Context, [32]byte) error
}

type RecoveryBackend interface {
	CreateRecoveryCodeResetIntent(context.Context, string) (authprivacy.PasswordResetIntent, error)
	CommitPasswordReset(context.Context, authprivacy.PasswordResetRequest, authprivacy.PasswordProcessor) error
	GetPasswordResetResult(context.Context, [32]byte, [32]byte) (string, error)
}

type ClosureBackend interface {
	RequestAccountClosure(context.Context, authprivacy.ClosureRequest, authprivacy.PasswordVerifier) (authprivacy.ClosureAccepted, error)
	GetAccountClosureStatus(context.Context, [32]byte, [32]byte) (authprivacy.ClosureStatus, error)
}

type PasswordPreparer interface {
	PreparePassword(context.Context, string, string) (authprivacy.PasswordMaterial, error)
	authprivacy.PasswordVerifier
}

type Endpoints struct {
	Public   http.Handler
	Internal http.Handler
}

type VerifierOptions struct {
	Eligibility    EligibilityBackend
	Receipts       ReceiptProcessor
	InternalPeer   PeerIdentity
	AllowedOrigins []string
	Limits         NetworkLimits
}

type ChannelBackend interface {
    ListAuthorizedChannels(context.Context, [32]byte) (authprivacy.ChannelDirectory, error)
}

type CommunityOptions struct {
    Channels       ChannelBackend
    Identities     IdentityBackend
	Backend        CommunityBackend
	Sessions       SessionBackend
	Recovery       RecoveryBackend
	Closures       ClosureBackend
	Credentials    authprivacy.CredentialBackend
	Passwords      PasswordPreparer
	InternalPeer   PeerIdentity
	AllowedOrigins []string
	Limits         NetworkLimits
}

type errorBody struct {
	Error     publicError `json:"error"`
	RequestID string      `json:"requestId"`
}
type publicError struct {
	Code    string        `json:"code"`
	Message string        `json:"message"`
	Details *errorDetails `json:"details,omitempty"`
}
type errorDetails struct {
	RetryAfterSeconds int `json:"retryAfterSeconds"`
}
type boundary struct {
	service Service
	peer    PeerIdentity
	origins map[string]bool
	limits  *networkLimiter
}

func NewVerifierEndpoints(options VerifierOptions) (*Endpoints, error) {
	if options.Eligibility == nil || options.Receipts == nil || options.InternalPeer.Service != CommunityService {
		return nil, errors.New("invalid verifier HTTP dependencies")
	}
	b, err := newBoundary(VerifierService, options.InternalPeer, options.AllowedOrigins, options.Limits)
	if err != nil {
		return nil, err
	}
	return &Endpoints{
		Public:   b.wrap(false, func(w http.ResponseWriter, r *http.Request) { b.verifierPublic(w, r, options.Eligibility) }),
		Internal: b.wrap(true, func(w http.ResponseWriter, r *http.Request) { b.verifierInternal(w, r, options.Receipts) }),
	}, nil
}

func NewCommunityEndpoints(options CommunityOptions) (*Endpoints, error) {
	if options.Backend == nil || options.Passwords == nil || options.InternalPeer.Service != VerifierService {
		return nil, errors.New("invalid community HTTP dependencies")
	}
	b, err := newBoundary(CommunityService, options.InternalPeer, options.AllowedOrigins, options.Limits)
	if err != nil {
		return nil, err
	}
	if options.Channels == nil {
		options.Channels, _ = options.Backend.(ChannelBackend)
	}
	if options.Identities == nil {
		options.Identities, _ = options.Backend.(IdentityBackend)
	}
	if options.Sessions == nil {
		options.Sessions, _ = options.Backend.(SessionBackend)
	}
	if options.Recovery == nil {
		options.Recovery, _ = options.Backend.(RecoveryBackend)
	}
	if options.Closures == nil {
		options.Closures, _ = options.Backend.(ClosureBackend)
	}
	if options.Credentials == nil {
		options.Credentials, _ = options.Backend.(authprivacy.CredentialBackend)
	}
	return &Endpoints{
		Public: b.wrap(false, func(w http.ResponseWriter, r *http.Request) {
            if isIdentityPath(r.URL.Path) {
                b.communityIdentitiesPublic(w, r, options.Identities)
                return
            }
            if r.URL.Path == "/api/v1/channels" {
                b.communityChannelsPublic(w, r, options.Channels)
                return
            }
			b.communityPublic(w, r, options.Backend, options.Sessions, options.Recovery, options.Closures, options.Credentials, options.Passwords)
		}),
		Internal: b.wrap(true, func(w http.ResponseWriter, r *http.Request) { b.communityInternal(w, r, options.Backend) }),
	}, nil
}

func newBoundary(service Service, identity PeerIdentity, origins []string, limits NetworkLimits) (*boundary, error) {
	peer, err := copyIdentity(identity)
	if err != nil {
		return nil, err
	}
	limiter, err := newNetworkLimiter(limits, service)
	if err != nil {
		return nil, err
	}
	if len(origins) > 32 {
		return nil, errors.New("too many client origins")
	}
	allowed := make(map[string]bool, len(origins))
	for _, raw := range origins {
		origin, err := fixedOrigin(raw)
		if err != nil {
			return nil, err
		}
		allowed[strings.TrimSuffix(origin.String(), "/")] = true
	}
	return &boundary{service: service, peer: peer, origins: allowed, limits: limiter}, nil
}

func (b *boundary) wrap(internal bool, next http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		var requestID [16]byte
		if _, err := rand.Read(requestID[:]); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("X-Request-ID", protocol.EncodeCanonicalBase64url(requestID[:]))
		r = r.Clone(r.Context())
		r.Header = r.Header.Clone()
		for name := range r.Header {
			if strings.EqualFold(name, "X-Request-ID") || strings.EqualFold(name, "X-Correlation-ID") || strings.EqualFold(name, "X-Client-ID") || strings.EqualFold(name, "traceparent") || strings.EqualFold(name, "tracestate") || strings.EqualFold(name, "baggage") {
				delete(r.Header, name)
			}
		}
		if internal {
			if r.TLS == nil || !r.TLS.HandshakeComplete || b.peer.verify(*r.TLS, x509.ExtKeyUsageClientAuth, "") != nil {
				b.fail(w, 401, "AUTHENTICATION_FAILED", 0)
				return
			}
			if hasHeader(r.Header, "Authorization") || hasHeader(r.Header, "Idempotency-Key") || hasHeader(r.Header, "V-Installation-ID") || hasHeader(r.Header, "OTP-Flow-ID") || hasHeader(r.Header, "Origin") || hasHeader(r.Header, "Reset-Intent-ID") || hasHeader(r.Header, "Credential-Change-ID") {
				b.bad(w, errMalformed)
				return
			}
		} else {
			if r.TLS == nil || !r.TLS.HandshakeComplete || r.TLS.Version < tls.VersionTLS12 {
				b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
				return
			}
			retry, err := b.limits.allow(r.RemoteAddr, r.Method == http.MethodGet)
			if err != nil {
				b.bad(w, err)
				return
			}
			if retry > 0 {
				b.fail(w, 429, "RATE_LIMITED", retry)
				return
			}
			if hasHeader(r.Header, "Origin") {
				origin, err := singleHeader(r.Header, "Origin")
				if err != nil || !b.origins[origin] {
					b.fail(w, 403, "AUTHENTICATION_FAILED", 0)
					return
				}
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Access-Control-Expose-Headers", "Session-Expires-At, X-Request-ID, Retry-After")
				w.Header().Set("Vary", "Origin")
			}
		}
		if r.URL.RawQuery != "" || r.URL.ForceQuery {
			b.bad(w, errMalformed)
			return
		}
		// CORS preflight is limited to documented public paths and headers.
		if !internal && r.Method == http.MethodOptions {
			b.preflight(w, r)
			return
		}
		next(w, r)
	})
}

func (b *boundary) preflight(w http.ResponseWriter, r *http.Request) {
	if !hasHeader(r.Header, "Origin") || noBodyOrQuery(r) != nil {
		b.bad(w, errMalformed)
		return
	}
	method, err := singleHeader(r.Header, "Access-Control-Request-Method")
	if err != nil || !publicMethodAllowed(b.service, r.URL.Path, method) {
		b.bad(w, errMalformed)
		return
	}
	requested := r.Header.Get("Access-Control-Request-Headers")
	allowed := map[string]bool{"content-type": true, "idempotency-key": true}
	if b.service == VerifierService {
		allowed["v-installation-id"] = true
		allowed["otp-flow-id"] = true
		allowed["authorization"] = true
	} else {
		allowed["authorization"] = true
		allowed["reset-intent-id"] = true
		if isPasskeyRemovalPath(r.URL.Path) || r.URL.Path == "/api/v1/auth/credential-change-result" {
			allowed["credential-change-id"] = true
		}
	}
	for _, name := range strings.Split(requested, ",") {
		if name = strings.ToLower(strings.TrimSpace(name)); name != "" && !allowed[name] {
			b.bad(w, errMalformed)
			return
		}
	}
	w.Header().Set("Access-Control-Allow-Methods", method)
	w.Header().Set("Access-Control-Allow-Headers", requested)
	w.WriteHeader(http.StatusNoContent)
}

func publicMethodAllowed(service Service, path, method string) bool {
    if service == CommunityService && isIdentityPath(path) {
        if path == "/api/v1/identities" { return method == http.MethodGet || method == http.MethodPost }
        if path == "/api/v1/identity-change-result" { return method == http.MethodGet }
        if _, err := identityPathID(path); err == nil { return method == http.MethodPatch || method == http.MethodDelete }
        return false
    }
    return method != "" && method == publicMethod(service, path)
}

func publicMethod(service Service, path string) string {
	if service == VerifierService {
		switch path {
		case "/api/v1/eligibility/otp-requests", "/api/v1/eligibility/otp-confirmations":
			return http.MethodPost
		case "/api/v1/eligibility/otp-request-result", "/api/v1/eligibility/otp-confirmation-result":
			return http.MethodGet
		}
	} else {
		switch path {
		case "/api/v1/auth/registration-intents", "/api/v1/auth/registrations",
			"/api/v1/auth/sessions", "/api/v1/auth/session-renewals",
			"/api/v1/auth/session-revocations", "/api/v1/auth/recovery-code-reset-intents",
			"/api/v1/auth/password-resets", "/api/v1/account-closures",
			"/api/v1/auth/recovery-code-rotations", "/api/v1/auth/passkey-options",
			"/api/v1/auth/passkeys", "/api/v1/auth/passkey-removal-intents",
			"/api/v1/auth/passkey-reset-options", "/api/v1/auth/passkey-reset-intents":
			return http.MethodPost
		case "/api/v1/channels", "/api/v1/auth/session", "/api/v1/auth/devices", "/api/v1/auth/password-reset-result", "/api/v1/auth/recovery-credentials", "/api/v1/auth/credential-change-result":
			return http.MethodGet
		}
		if isRotationConfirmationPath(path) {
			return http.MethodPost
		}
		if isPasskeyRemovalPath(path) {
			return http.MethodDelete
		}
		if strings.HasPrefix(path, "/api/v1/account-closures/") &&
			!strings.Contains(strings.TrimPrefix(path, "/api/v1/account-closures/"), "/") {
			return http.MethodGet
		}
	}
	return ""
}

func (b *boundary) fail(w http.ResponseWriter, status int, code string, retry int) {
	value := errorBody{Error: publicError{Code: code, Message: "请求未能完成，请按原操作核对或重试。"}, RequestID: w.Header().Get("X-Request-ID")}
	if retry > 0 {
		value.Error.Details = &errorDetails{RetryAfterSeconds: retry}
		w.Header().Set("Retry-After", strconv.Itoa(retry))
	}
	writeJSON(w, status, value)
}

func (b *boundary) bad(w http.ResponseWriter, err error) {
	status, code := 400, "REQUEST_INVALID"
	if b.service == CommunityService {
		code = "MALFORMED_REQUEST"
		if errors.Is(err, errTooLarge) {
			status, code = 413, "PAYLOAD_TOO_LARGE"
		}
		if errors.Is(err, errMediaType) {
			status, code = 415, "UNSUPPORTED_MEDIA_TYPE"
		}
	}
	b.fail(w, status, code, 0)
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	// All response shapes here contain only fixed scalar fields and cannot fail
	// encoding; no backend error or whole backend struct is serialized.
	encoded, err := json.Marshal(body)
	if err != nil {
		w.WriteHeader(503)
		return
	}
	w.WriteHeader(status)
	_, _ = w.Write(append(encoded, '\n'))
}

func (b *boundary) verifierPublic(w http.ResponseWriter, r *http.Request, backend EligibilityBackend) {
	if hasHeader(r.Header, "Credential-Change-ID") {
		b.bad(w, errMalformed)
		return
	}
	method := publicMethod(VerifierService, r.URL.Path)
	if method == "" {
		b.fail(w, 404, "REQUEST_INVALID", 0)
		return
	}
	if r.Method != method {
		w.Header().Set("Allow", method)
		b.fail(w, 405, "REQUEST_INVALID", 0)
		return
	}
	installationRaw, err := headerBytes(r.Header, "V-Installation-ID", 16)
	if err != nil {
		b.bad(w, err)
		return
	}
	var installation [16]byte
	copy(installation[:], installationRaw)
	if method == http.MethodGet {
		if noBodyOrQuery(r) != nil || hasHeader(r.Header, "Idempotency-Key") {
			b.bad(w, errMalformed)
			return
		}
		if r.URL.Path == "/api/v1/eligibility/otp-request-result" {
			if hasHeader(r.Header, "OTP-Flow-ID") {
				b.bad(w, errMalformed)
				return
			}
			key, err := capability(r.Header, "OtpRequestResult")
			if err != nil {
				b.fail(w, 401, "AUTHENTICATION_FAILED", 0)
				return
			}
			result, err := backend.GetOTPRequestResult(r.Context(), key, installation)
			if err != nil {
				b.eligibilityFailure(w, err)
				return
			}
			b.otpRequestResult(w, result, true)
			return
		}
		key, err := capability(r.Header, "OtpConfirmationResult")
		if err != nil {
			b.fail(w, 401, "AUTHENTICATION_FAILED", 0)
			return
		}
		flowRaw, err := headerBytes(r.Header, "OTP-Flow-ID", 32)
		if err != nil {
			b.bad(w, err)
			return
		}
		var flow [32]byte
		copy(flow[:], flowRaw)
		result, err := backend.GetOTPConfirmationResult(r.Context(), key, flow, installation)
		if err != nil {
			b.eligibilityFailure(w, err)
			return
		}
		b.confirmationResult(w, result, true)
		return
	}
	if hasHeader(r.Header, "Authorization") || hasHeader(r.Header, "OTP-Flow-ID") {
		b.bad(w, errMalformed)
		return
	}
	keyRaw, err := headerBytes(r.Header, "Idempotency-Key", 32)
	if err != nil {
		b.bad(w, err)
		return
	}
	var key [32]byte
	copy(key[:], keyRaw)
	if r.URL.Path == "/api/v1/eligibility/otp-requests" {
		object, err := readRequestObject(r, 1024, []string{"email"}, nil)
		if err != nil {
			b.bad(w, err)
			return
		}
		email, err := stringField(object, "email")
		if err != nil {
			b.bad(w, err)
			return
		}
		result, err := backend.RequestOTP(r.Context(), authprivacy.OTPRequest{Key: key, InstallationID: installation, Email: email})
		if err != nil {
			b.eligibilityFailure(w, err)
			return
		}
		b.otpRequestResult(w, result, false)
		return
	}
	object, err := readRequestObject(r, 4096, []string{"flowId", "otp", "slotId", "bootstrapPublicKey"}, []string{"releaseReceipt"})
	if err != nil {
		b.bad(w, err)
		return
	}
	request := authprivacy.ConfirmOTPRequest{Key: key, InstallationID: installation}
	flow, e1 := stringField(object, "flowId")
	slot, e2 := stringField(object, "slotId")
	publicKey, e3 := stringField(object, "bootstrapPublicKey")
	request.OTP, err = stringField(object, "otp")
	if e1 != nil || e2 != nil || e3 != nil || err != nil || !otpPattern.MatchString(request.OTP) {
		b.bad(w, errMalformed)
		return
	}
	flowBytes, e1 := protocol.DecodeCanonicalBase64url(flow, 32)
	slotBytes, e2 := protocol.DecodeCanonicalBase64url(slot, 32)
	keyBytes, e3 := protocol.DecodeCanonicalBase64url(publicKey, 32)
	if e1 != nil || e2 != nil || e3 != nil {
		b.bad(w, errMalformed)
		return
	}
	copy(request.FlowID[:], flowBytes)
	copy(request.SlotID[:], slotBytes)
	copy(request.BootstrapPublicKey[:], keyBytes)
	derived, err := protocol.DeriveSlot(request.BootstrapPublicKey)
	if err != nil {
		b.fail(w, 422, "BOOTSTRAP_KEY_INVALID", 0)
		return
	}
	if derived != request.SlotID {
		b.fail(w, 422, "SLOT_BINDING_INVALID", 0)
		return
	}
	if _, found := object["releaseReceipt"]; found {
		request.ReleaseReceipt, err = stringField(object, "releaseReceipt")
		if err != nil {
			b.bad(w, err)
			return
		}
		if _, err = protocol.ParseReceipt(request.ReleaseReceipt, protocol.PurposeReleased); err != nil {
			b.fail(w, 422, "RELEASE_RECEIPT_INVALID", 0)
			return
		}
	}
	result, err := backend.ConfirmOTP(r.Context(), request)
	if err != nil {
		b.eligibilityFailure(w, err)
		return
	}
	b.confirmationResult(w, result, false)
}

func (b *boundary) otpRequestResult(w http.ResponseWriter, result authprivacy.OTPRequestResult, query bool) {
	if result.RetryAfterSeconds < 0 || result.RetryAfterSeconds > 60 {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if !query {
		if result.State != "ACCEPTED" || result.FlowID == ([32]byte{}) {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		writeJSON(w, 202, map[string]any{"flowId": protocol.EncodeCanonicalBase64url(result.FlowID[:]), "retryAfterSeconds": result.RetryAfterSeconds})
		return
	}
	switch result.State {
	case "ACCEPTED":
		if result.FlowID == ([32]byte{}) {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		writeJSON(w, 200, map[string]any{"state": result.State, "flowId": protocol.EncodeCanonicalBase64url(result.FlowID[:]), "retryAfterSeconds": result.RetryAfterSeconds})
	case "NOT_SENT":
		writeJSON(w, 200, map[string]any{"state": result.State, "retryAfterSeconds": result.RetryAfterSeconds})
	case "PENDING":
		b.pending(w, result.State, result.PollAfterSeconds)
	default:
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
	}
}

func (b *boundary) confirmationResult(w http.ResponseWriter, result authprivacy.ConfirmationResult, query bool) {
	if result.State == "CONFIRMATION_PENDING" || result.State == "RETIREMENT_PENDING" || (query && result.State == "PENDING") {
		b.pending(w, result.State, result.RetryAfterSeconds)
		return
	}
	if query {
		if result.State != "TICKET_AVAILABLE" && result.State != "REVERIFY_REQUIRED" && result.State != "NOT_COMMITTED" {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		writeJSON(w, 200, map[string]string{"state": result.State})
		return
	}
	if result.State == "REVERIFY_REQUIRED" {
		b.fail(w, 422, "REVERIFY_REQUIRED", 0)
		return
	}
	if result.State != "TICKET_AVAILABLE" {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if _, err := protocol.ParseRegistrationTicket(result.RegistrationTicket); err != nil {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	writeJSON(w, 200, map[string]string{"registrationTicket": result.RegistrationTicket})
}

func (b *boundary) pending(w http.ResponseWriter, state string, retry int) {
	if retry < 1 || retry > 300 {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Retry-After", strconv.Itoa(retry))
	writeJSON(w, 202, map[string]any{"state": state, "retryAfterSeconds": retry})
}

func (b *boundary) eligibilityFailure(w http.ResponseWriter, err error) {
	if errors.Is(err, authprivacy.ErrExpired) {
		b.fail(w, 410, "RESULT_EXPIRED", 0)
		return
	}
	if errors.Is(err, authprivacy.ErrConflict) {
		b.fail(w, 409, "IDEMPOTENCY_KEY_REUSED", 0)
		return
	}
	var public *authprivacy.EligibilityError
	if errors.As(err, &public) {
		status := 422
		switch public.Code {
		case "REQUEST_INVALID":
			status = 400
		case "AUTHENTICATION_FAILED":
			status = 401
		case "IDEMPOTENCY_KEY_REUSED", "ELIGIBILITY_RESERVED":
			status = 409
		case "RESULT_EXPIRED":
			status = 410
		case "RATE_LIMITED":
			status = 429
		case "SERVICE_UNAVAILABLE":
			status = 503
		case "EMAIL_INVALID", "OTP_INVALID", "OTP_EXPIRED", "OTP_REPLACED", "OTP_FLOW_INVALID", "BOOTSTRAP_KEY_INVALID", "SLOT_BINDING_INVALID", "RELEASE_RECEIPT_INVALID", "REVERIFY_REQUIRED":
		default:
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		retry := 0
		if status == 429 && public.RetryAfterSeconds > 0 && public.RetryAfterSeconds <= 999999 {
			retry = public.RetryAfterSeconds
		}
		b.fail(w, status, public.Code, retry)
		return
	}
	b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
}

func (b *boundary) verifierInternal(w http.ResponseWriter, r *http.Request, backend ReceiptProcessor) {
	purpose, field := protocol.Purpose(""), ""
	switch r.URL.Path {
	case "/internal/v1/slot-releases":
		purpose, field = protocol.PurposeReleased, "releaseReceipt"
	case "/internal/v1/slot-retirement-receipts":
		purpose, field = protocol.PurposeRetired, "retirementReceipt"
	default:
		b.fail(w, 404, "REQUEST_INVALID", 0)
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		b.fail(w, 405, "REQUEST_INVALID", 0)
		return
	}
	object, err := readRequestObject(r, 1024, []string{field}, nil)
	if err != nil {
		b.bad(w, err)
		return
	}
	encoded, err := stringField(object, field)
	if err != nil {
		b.bad(w, err)
		return
	}
	invalid, reconciliation := "RETIREMENT_RECEIPT_INVALID", "RETIREMENT_RECONCILIATION_REQUIRED"
	if purpose == protocol.PurposeReleased {
		invalid, reconciliation = "RELEASE_RECEIPT_INVALID", "RELEASE_RECONCILIATION_REQUIRED"
	}
	if _, err = protocol.ParseReceipt(encoded, purpose); err != nil {
		b.fail(w, 422, invalid, 0)
		return
	}
	if err = backend.ProcessReceipt(r.Context(), encoded, purpose); err != nil {
		if errors.Is(err, authprivacy.ErrReconciliation) {
			b.fail(w, 409, reconciliation, 0)
			return
		}
		if protocolError(err) {
			b.fail(w, 422, invalid, 0)
			return
		}
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	writeJSON(w, 200, map[string]string{"state": "ACKNOWLEDGED"})
}

var otpPattern = regexp.MustCompile(`^[0-9]{6}$`)

var privateUsername = regexp.MustCompile(`^[a-z][a-z0-9_]{5,23}$`)

func (b *boundary) communityPublic(w http.ResponseWriter, r *http.Request, backend CommunityBackend, sessions SessionBackend, recovery RecoveryBackend, closures ClosureBackend, credentials authprivacy.CredentialBackend, passwords PasswordPreparer) {
	method := publicMethod(CommunityService, r.URL.Path)
	if method == "" {
		b.fail(w, 404, "RESOURCE_NOT_FOUND", 0)
		return
	}
	if r.Method != method {
		w.Header().Set("Allow", method)
		b.fail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	if hasHeader(r.Header, "V-Installation-ID") || hasHeader(r.Header, "OTP-Flow-ID") {
		b.bad(w, errMalformed)
		return
	}
	if hasHeader(r.Header, "Reset-Intent-ID") && r.URL.Path != "/api/v1/auth/password-reset-result" {
		b.bad(w, errMalformed)
		return
	}
	if hasHeader(r.Header, "Credential-Change-ID") && !isPasskeyRemovalPath(r.URL.Path) && r.URL.Path != "/api/v1/auth/credential-change-result" {
		b.bad(w, errMalformed)
		return
	}
	if isCredentialPath(r.URL.Path) {
		b.communityCredentialPublic(w, r, credentials, passwords)
		return
	}
	if r.URL.Path == "/api/v1/auth/recovery-code-reset-intents" || r.URL.Path == "/api/v1/auth/password-resets" || r.URL.Path == "/api/v1/auth/password-reset-result" {
		b.communityRecoveryPublic(w, r, recovery, passwords)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/api/v1/account-closures") {
		b.communityClosurePublic(w, r, closures, passwords)
		return
	}
	if r.URL.Path != "/api/v1/auth/registration-intents" && r.URL.Path != "/api/v1/auth/registrations" {
		b.communitySessionPublic(w, r, sessions, passwords)
		return
	}
	if hasHeader(r.Header, "Authorization") {
		b.bad(w, errMalformed)
		return
	}
	if r.URL.Path == "/api/v1/auth/registration-intents" {
		if hasHeader(r.Header, "Idempotency-Key") {
			b.bad(w, errMalformed)
			return
		}
		object, err := readRequestObject(r, 8192, []string{"registrationTicket", "username", "password", "installationId"}, nil)
		if err != nil {
			b.bad(w, err)
			return
		}
		ticket, e1 := stringField(object, "registrationTicket")
		username, e2 := stringField(object, "username")
		password, e3 := stringField(object, "password")
		installationValue, e4 := stringField(object, "installationId")
		if e1 != nil || e2 != nil || e3 != nil || e4 != nil || !privateUsername.MatchString(username) || len(password) < 1 || len(password) > 2048 || utf8.RuneCountInString(password) > 512 {
			b.bad(w, errMalformed)
			return
		}
		installationBytes, err := protocol.DecodeCanonicalBase64url(installationValue, 16)
		if err != nil {
			b.bad(w, err)
			return
		}
		if _, err = protocol.DecodeCanonicalBase64url(ticket, protocol.RegistrationTicketLength); err != nil {
			b.bad(w, err)
			return
		}
		decision, err := backend.ValidateSignupTicket(r.Context(), ticket)
		if err != nil {
			b.communityFailure(w, err, false)
			return
		}
		if decision.Generation == 0 || decision.TrustedAt.IsZero() {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		material, err := passwords.PreparePassword(r.Context(), password, username)
		if err != nil {
			b.communityFailure(w, err, false)
			return
		}
		var installation [16]byte
		copy(installation[:], installationBytes)
		result, err := backend.CreateSignupIntent(r.Context(), ticket, username, material, installation, decision.Generation)
		if err != nil {
			b.communityFailure(w, err, false)
			return
		}
		if result.ID == (protocol.IntentID{}) || result.Challenge == (protocol.Challenge{}) || result.ExpiresAt.IsZero() || !validRecoveryCode(result.RecoveryCode, true) {
			b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
			return
		}
		writeJSON(w, 201, map[string]string{"intentId": protocol.EncodeCanonicalBase64url(result.ID[:]), "challenge": protocol.EncodeCanonicalBase64url(result.Challenge[:]), "expiresAt": utc(result.ExpiresAt), "recoveryCode": result.RecoveryCode})
		return
	}
	keyRaw, err := headerBytes(r.Header, "Idempotency-Key", 32)
	if err != nil {
		b.bad(w, err)
		return
	}
	object, err := readRequestObject(r, 8192, []string{"intentId", "bootstrapSignature", "recoveryCodeConfirmation"}, nil)
	if err != nil {
		b.bad(w, err)
		return
	}
	intent, e1 := stringField(object, "intentId")
	proof, e2 := stringField(object, "bootstrapSignature")
	code, e3 := stringField(object, "recoveryCodeConfirmation")
	if e1 != nil || e2 != nil || e3 != nil || !validRecoveryCode(code, false) {
		b.bad(w, errMalformed)
		return
	}
	intentBytes, err := protocol.DecodeCanonicalBase64url(intent, 32)
	if err != nil {
		b.bad(w, err)
		return
	}
	if _, err = protocol.DecodeCanonicalBase64url(proof, 64); err != nil {
		b.bad(w, err)
		return
	}
	request := authprivacy.SignupRequest{Proof: proof, RecoveryCode: code}
	copy(request.IntentID[:], intentBytes)
	copy(request.IdempotencyKey[:], keyRaw)
	result, err := backend.CommitSignup(r.Context(), request)
	if err != nil {
		b.communityFailure(w, err, true)
		return
	}
	if result.Replay {
		b.fail(w, 409, "REGISTRATION_COMMITTED_LOGIN_REQUIRED", 0)
		return
	}
	if !result.Created || result.AccountID.String() == "00000000-0000-0000-0000-000000000000" || result.ExpiresAt.IsZero() || result.SessionToken == ([32]byte{}) {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	w.Header().Set("Session-Expires-At", utc(result.ExpiresAt))
	writeJSON(w, 201, map[string]string{"accountId": result.AccountID.String(), "sessionToken": protocol.EncodeCanonicalBase64url(result.SessionToken[:]), "expiresAt": utc(result.ExpiresAt)})
}

func utc(at time.Time) string { return at.UTC().Format(time.RFC3339Nano) }

func validRecoveryCode(value string, output bool) bool {
	if len(value) < 26 || len(value) > 64 {
		return false
	}
	for _, r := range value {
		if !(r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || r >= '2' && r <= '7' || r == ' ' || r == '-') {
			return false
		}
	}
	normal := strings.ToUpper(strings.NewReplacer("-", "", " ", "").Replace(value))
	if output && normal != value {
		return false
	}
	encoding := base32.StdEncoding.WithPadding(base32.NoPadding)
	raw, err := encoding.DecodeString(normal)
	return err == nil && len(raw) == 16 && encoding.EncodeToString(raw) == normal
}

func (b *boundary) communityFailure(w http.ResponseWriter, err error, commit bool) {
	switch {
	case errors.Is(err, authprivacy.ErrAuthorizationUnavailable):
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
	case errors.Is(err, authprivacy.ErrExpired):
		b.fail(w, 410, "RESULT_EXPIRED", 0)
	case errors.Is(err, authprivacy.ErrConflict):
		b.fail(w, 409, "IDEMPOTENCY_KEY_REUSED", 0)
	case errors.Is(err, authprivacy.ErrUsernameTaken):
		b.fail(w, 409, "USERNAME_UNAVAILABLE", 0)
	case errors.Is(err, authprivacy.ErrSlotUnavailable):
		b.fail(w, 409, "SLOT_UNAVAILABLE", 0)
	case errors.Is(err, authprivacy.ErrIntentInvalid):
		b.fail(w, 422, "INTENT_INVALID", 0)
	case errors.Is(err, authprivacy.ErrPasswordPolicy):
		b.fail(w, 422, "PASSWORD_POLICY_FAILED", 0)
	case errors.Is(err, authprivacy.ErrPasswordBusy):
		b.fail(w, 429, "RATE_LIMITED", 1)
	case errors.Is(err, protocol.ErrTicketExpired):
		b.fail(w, 422, "REGISTRATION_TICKET_EXPIRED", 0)
	case errors.Is(err, protocol.ErrTicketNotYetValid):
		b.fail(w, 422, "REGISTRATION_TICKET_NOT_YET_VALID", 0)
	case errors.Is(err, protocol.ErrKeyConfiguration), errors.Is(err, protocol.ErrTimeInvalid):
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
	case protocolError(err):
		code := "REGISTRATION_TICKET_INVALID"
		if commit && (errors.Is(err, protocol.ErrSignature) || errors.Is(err, protocol.ErrPoint)) {
			code = "CHALLENGE_INVALID"
		}
		b.fail(w, 422, code, 0)
	default:
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
	}
}

func protocolError(err error) bool {
	return errors.Is(err, protocol.ErrEncoding) || errors.Is(err, protocol.ErrLength) || errors.Is(err, protocol.ErrPurpose) || errors.Is(err, protocol.ErrPoint) || errors.Is(err, protocol.ErrSignature) || errors.Is(err, protocol.ErrSlotBinding) || errors.Is(err, protocol.ErrKeyUntrusted) || errors.Is(err, protocol.ErrKeyRevoked) || errors.Is(err, protocol.ErrKeyEnvironment)
}

func (b *boundary) communityInternal(w http.ResponseWriter, r *http.Request, backend CommunityBackend) {
	if r.URL.Path != "/internal/v1/slot-retirements" {
		b.fail(w, 404, "RESOURCE_NOT_FOUND", 0)
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		b.fail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	object, err := readRequestObject(r, 8192, []string{"retirementAuthorization"}, nil)
	if err != nil {
		b.bad(w, err)
		return
	}
	encoded, err := stringField(object, "retirementAuthorization")
	if err != nil {
		b.bad(w, err)
		return
	}
	authorization, err := protocol.ParseRetirementAuthorization(encoded)
	if err != nil {
		b.bad(w, err)
		return
	}
	result, err := backend.RetireUnusedSlot(r.Context(), encoded)
	if err != nil {
		if errors.Is(err, authprivacy.ErrSlotUnavailable) {
			b.fail(w, 409, "SLOT_NOT_RETIRABLE", 0)
			return
		}
		if protocolError(err) {
			b.fail(w, 401, "AUTHENTICATION_FAILED", 0)
			return
		}
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if result.SlotNotRetirable {
		b.fail(w, 409, "SLOT_NOT_RETIRABLE", 0)
		return
	}
	if result.Pending {
		b.pending(w, "RECEIPT_PENDING", result.RetryAfterSeconds)
		return
	}
	receipt, err := protocol.ParseReceipt(result.Receipt, protocol.PurposeRetired)
	if err != nil || receipt.Slot != authorization.Slot {
		b.fail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	writeJSON(w, 200, map[string]string{"retirementReceipt": result.Receipt})
}
