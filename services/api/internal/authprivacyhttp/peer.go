package authprivacyhttp

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"mime"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

var ErrPeerResponse = errors.New("peer response not durably acknowledged")

type PeerClientOptions struct {
	Origin            string
	Environment       string
	LocalService      Service
	PeerService       Service
	ClientCertificate tls.Certificate
	Roots             *x509.CertPool
	RevokedSerials    map[string]bool
	Timeout           time.Duration
}

// PeerClient has no configurable transport, proxy, redirect callback or target
// per request. Caller data cannot change the fixed origin or TLS identity.
type PeerClient struct {
	origin string
	peer   Service
	client *http.Client
}

func NewPeerClient(options PeerClientOptions) (*PeerClient, error) {
	origin, err := fixedOrigin(options.Origin)
	if err != nil {
		return nil, err
	}
	policy, err := copyIdentity(PeerIdentity{Environment: options.Environment, Service: options.PeerService, Roots: options.Roots, RevokedSerials: options.RevokedSerials})
	if err != nil || options.LocalService != opposite(options.PeerService) {
		return nil, errors.New("invalid peer client identity")
	}
	if err = certificateIdentity(options.ClientCertificate, options.Environment, options.LocalService, x509.ExtKeyUsageClientAuth); err != nil {
		return nil, err
	}
	timeout := options.Timeout
	if timeout == 0 {
		timeout = 10 * time.Second
	}
	if timeout <= 0 || timeout > 60*time.Second {
		return nil, errors.New("invalid peer timeout")
	}
	hostname := origin.Hostname()
	transport := &http.Transport{
		Proxy:       nil,
		DialContext: (&net.Dialer{Timeout: timeout, KeepAlive: 30 * time.Second}).DialContext,
		TLSClientConfig: &tls.Config{
			MinVersion:   tls.VersionTLS13,
			MaxVersion:   tls.VersionTLS13,
			RootCAs:      policy.Roots,
			ServerName:   hostname,
			Certificates: []tls.Certificate{options.ClientCertificate},
			VerifyConnection: func(state tls.ConnectionState) error {
				return policy.verify(state, x509.ExtKeyUsageServerAuth, hostname)
			},
		},
		TLSHandshakeTimeout:    timeout,
		ResponseHeaderTimeout:  timeout,
		MaxResponseHeaderBytes: 8192,
		MaxConnsPerHost:        16,
		MaxIdleConnsPerHost:    4,
		DisableCompression:     true,
	}
	client := &http.Client{Transport: transport, Timeout: timeout, CheckRedirect: func(*http.Request, []*http.Request) error { return ErrPeerResponse }}
	return &PeerClient{origin: strings.TrimSuffix(origin.String(), "/"), peer: options.PeerService, client: client}, nil
}

func fixedOrigin(raw string) (*url.URL, error) {
	origin, err := url.Parse(raw)
	if err != nil || origin.Scheme != "https" || origin.Host == "" || origin.Hostname() == "" || origin.User != nil || origin.RawQuery != "" || origin.ForceQuery || origin.Fragment != "" || (origin.Path != "" && origin.Path != "/") || origin.RawPath != "" {
		return nil, errors.New("invalid fixed HTTPS origin")
	}
	if origin.Port() != "" {
		port, err := strconv.Atoi(origin.Port())
		if err != nil || port < 1 || port > 65535 {
			return nil, errors.New("invalid HTTPS port")
		}
	}
	return origin, nil
}

func (peer *PeerClient) CloseIdleConnections() { peer.client.CloseIdleConnections() }

func (peer *PeerClient) request(ctx context.Context, path string, body any) (int, map[string]any, http.Header, error) {
	encoded, err := json.Marshal(body)
	if err != nil {
		return 0, nil, nil, ErrPeerResponse
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, peer.origin+path, bytes.NewReader(encoded))
	if err != nil {
		return 0, nil, nil, ErrPeerResponse
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := peer.client.Do(request)
	if err != nil {
		return 0, nil, nil, ErrPeerResponse
	}
	defer response.Body.Close()
	cache, err := singleHeader(response.Header, "Cache-Control")
	if err != nil || cache != "no-store" || response.Header.Get("Content-Encoding") != "" {
		return 0, nil, nil, ErrPeerResponse
	}
	if _, err = headerBytes(response.Header, "X-Request-ID", 16); err != nil {
		return 0, nil, nil, ErrPeerResponse
	}
	contentType, err := singleHeader(response.Header, "Content-Type")
	if err != nil {
		return 0, nil, nil, ErrPeerResponse
	}
	mediaType, params, err := mime.ParseMediaType(contentType)
	if err != nil || mediaType != "application/json" || len(params) > 1 || (params["charset"] != "" && !strings.EqualFold(params["charset"], "utf-8")) {
		return 0, nil, nil, ErrPeerResponse
	}
	for name := range params {
		if name != "charset" {
			return 0, nil, nil, ErrPeerResponse
		}
	}
	object, err := parseObject(response.Body, 1024)
	if err != nil {
		return 0, nil, nil, ErrPeerResponse
	}
	return response.StatusCode, object, response.Header, nil
}

// RetireUnusedSlot returns an untrusted application receipt to V. V must still
// verify its signature and bind it to the durable retirement command before
// changing quota; mTLS alone never grants release authority.
func (peer *PeerClient) RetireUnusedSlot(ctx context.Context, encodedAuthorization string) (authprivacy.RetirementReply, error) {
	var result authprivacy.RetirementReply
	if peer.peer != CommunityService {
		return result, ErrPeerResponse
	}
	authorization, err := protocol.ParseRetirementAuthorization(encodedAuthorization)
	if err != nil {
		return result, ErrPeerResponse
	}
	status, object, header, err := peer.request(ctx, "/internal/v1/slot-retirements", map[string]string{"retirementAuthorization": encodedAuthorization})
	if err != nil {
		return result, err
	}
	switch status {
	case http.StatusOK:
		if fields(object, []string{"retirementReceipt"}, nil) != nil {
			return result, ErrPeerResponse
		}
		encoded, err := stringField(object, "retirementReceipt")
		if err != nil {
			return result, ErrPeerResponse
		}
		receipt, err := protocol.ParseReceipt(encoded, protocol.PurposeRetired)
		if err != nil || receipt.Slot != authorization.Slot {
			return result, ErrPeerResponse
		}
		result.Receipt = encoded
		return result, nil
	case http.StatusAccepted:
		if fields(object, []string{"state", "retryAfterSeconds"}, nil) != nil {
			return result, ErrPeerResponse
		}
		state, err := stringField(object, "state")
		if err != nil || state != "RECEIPT_PENDING" {
			return result, ErrPeerResponse
		}
		retry, err := integerField(object, "retryAfterSeconds", 1, 300)
		value, hErr := singleHeader(header, "Retry-After")
		if err != nil || hErr != nil || value != strconv.Itoa(retry) {
			return result, ErrPeerResponse
		}
		return authprivacy.RetirementReply{Pending: true, RetryAfterSeconds: retry}, nil
	case http.StatusConflict:
		if validPeerError(object, header, "SLOT_NOT_RETIRABLE") {
			return authprivacy.RetirementReply{SlotNotRetirable: true}, nil
		}
	}
	return result, ErrPeerResponse
}

// ReceiveReceipt implements authprivacy.ReceiptReceiver. A success is only the
// exact request's authenticated 200 {state:ACKNOWLEDGED}; pending, redirects,
// alternate bodies and network failures leave the C outbox unacknowledged.
func (peer *PeerClient) ReceiveReceipt(ctx context.Context, encoded string, purpose protocol.Purpose) error {
	if peer.peer != VerifierService {
		return ErrPeerResponse
	}
	if _, err := protocol.ParseReceipt(encoded, purpose); err != nil {
		return ErrPeerResponse
	}
	path, field := "", ""
	switch purpose {
	case protocol.PurposeRetired:
		path, field = "/internal/v1/slot-retirement-receipts", "retirementReceipt"
	case protocol.PurposeReleased:
		path, field = "/internal/v1/slot-releases", "releaseReceipt"
	default:
		return ErrPeerResponse
	}
	status, object, _, err := peer.request(ctx, path, map[string]string{field: encoded})
	if err != nil {
		return err
	}
	if status != http.StatusOK || fields(object, []string{"state"}, nil) != nil {
		return ErrPeerResponse
	}
	state, err := stringField(object, "state")
	if err != nil || state != "ACKNOWLEDGED" {
		return ErrPeerResponse
	}
	return nil
}

func validPeerError(object map[string]any, header http.Header, code string) bool {
	if fields(object, []string{"error", "requestId"}, nil) != nil {
		return false
	}
	requestID, err := stringField(object, "requestId")
	if err != nil {
		return false
	}
	headerID, err := singleHeader(header, "X-Request-ID")
	if err != nil || requestID != headerID {
		return false
	}
	detail, ok := object["error"].(map[string]any)
	if !ok || fields(detail, []string{"code", "message"}, []string{"details"}) != nil {
		return false
	}
	actual, err := stringField(detail, "code")
	if err != nil || actual != code {
		return false
	}
	message, err := stringField(detail, "message")
	if err != nil || len(message) < 1 || len(message) > 256 {
		return false
	}
	if value, found := detail["details"]; found {
		optional, ok := value.(map[string]any)
		if !ok || fields(optional, nil, []string{"retryAfterSeconds"}) != nil {
			return false
		}
		if _, found := optional["retryAfterSeconds"]; found {
			if _, err := integerField(optional, "retryAfterSeconds", 1, 300); err != nil {
				return false
			}
		}
	}
	return true
}

var _ authprivacy.RetirementPeer = (*PeerClient)(nil)
var _ authprivacy.ReceiptReceiver = (&PeerClient{}).ReceiveReceipt
