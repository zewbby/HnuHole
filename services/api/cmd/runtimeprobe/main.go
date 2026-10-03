// runtimeprobe exercises actual development C/V processes. It never installs
// tools, bypasses TLS verification, prints credentials, or controls production.
package main

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/mail"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/channels"
)

type probe struct {
	c, v, mailpit string
	https, local  *http.Client
	statePath     string
}
type state struct {
	Username           string    `json:"username"`
	Password           string    `json:"password"`
	Token              string    `json:"token"`
	ExpiresAt          time.Time `json:"expiresAt"`
	IdentityID         string    `json:"identityId,omitempty"`
	IdentityReceiptKey string    `json:"identityReceiptKey,omitempty"`
}

func main() {
	c := flag.String("community", "", "C public origin")
	v := flag.String("verifier", "", "V public origin")
	ca := flag.String("ca", "", "development trust root PEM")
	mailpit := flag.String("mailpit", "", "isolated Mailpit loopback origin")
	statePath := flag.String("state", "", "private disposable state file")
	phase := flag.String("phase", "lifecycle", "lifecycle, identities, threshold, restart, frozen, recovered, closure")
	flag.Parse()
	if os.Getenv("AUTHRUNTIME_ISOLATED") != "1" || flag.NArg() != 0 {
		die(errors.New("runtimeprobe requires explicitly isolated development runner"))
	}
	if !localOrigin(*c, "https") || !localOrigin(*v, "https") || *c == *v || !localOrigin(*mailpit, "http") || !filepath.IsAbs(*statePath) {
		die(errors.New("probe origins and private state path are invalid"))
	}
	dir, err := os.Stat(filepath.Dir(*statePath))
	if err != nil || !dir.IsDir() || dir.Mode().Perm()&0077 != 0 {
		die(errors.New("probe state directory must be private"))
	}
	root, err := os.ReadFile(*ca)
	if err != nil {
		die(errors.New("cannot load development trust root"))
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(root) {
		die(errors.New("invalid development trust root"))
	}
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}, Proxy: nil}
	defer transport.CloseIdleConnections()
	localTransport := &http.Transport{Proxy: nil}
	defer localTransport.CloseIdleConnections()
	redirects := func(*http.Request, []*http.Request) error { return errors.New("probe redirects are forbidden") }
	p := probe{c: *c, v: *v, mailpit: *mailpit, statePath: *statePath,
		https: &http.Client{Transport: transport, Timeout: 10 * time.Second, CheckRedirect: redirects},
		local: &http.Client{Transport: localTransport, Timeout: 5 * time.Second, CheckRedirect: redirects}}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	if err := p.run(ctx, *phase); err != nil {
		die(err)
	}
	// Small evidence contains no account, mailbox, token, password or OTP.
	_ = json.NewEncoder(os.Stdout).Encode(map[string]string{"phase": *phase, "result": "passed"})
}
func die(err error) { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
func localOrigin(raw, scheme string) bool {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != scheme || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") || u.Port() == "" {
		return false
	}
	ip := net.ParseIP(u.Hostname())
	return ip != nil && ip.IsLoopback()
}
func randomCapability(n int) (string, error) {
	b := make([]byte, n)
	_, err := rand.Read(b)
	return protocol.EncodeCanonicalBase64url(b), err
}
func field(body map[string]any, name string) (string, error) {
	s, ok := body[name].(string)
	if !ok || s == "" {
		return "", errors.New("probe response missing required scalar")
	}
	return s, nil
}
func (p *probe) request(ctx context.Context, method, origin, path string, body any, headers map[string]string, want int) (map[string]any, http.Header, error) {
	var input io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, nil, err
		}
		input = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, strings.TrimSuffix(origin, "/")+path, input)
	if err != nil {
		return nil, nil, errors.New("cannot create probe request")
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for key, value := range headers {
		req.Header.Set(key, value)
	}
	response, err := p.https.Do(req)
	if err != nil {
		return nil, nil, errors.New("probe HTTPS transport failed")
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 32769))
	if err != nil || len(data) > 32768 {
		return nil, nil, errors.New("probe response exceeded bound")
	}
	if response.StatusCode != want || response.Header.Get("Cache-Control") != "no-store" || response.Header.Get("X-Request-ID") == "" {
		return nil, nil, fmt.Errorf("probe %s %s expected %d got %d or missing privacy headers", method, path, want, response.StatusCode)
	}
	result := make(map[string]any)
	if want == 204 {
		if len(data) != 0 {
			return nil, nil, errors.New("204 response contained body")
		}
		return result, response.Header, nil
	}
	if json.Unmarshal(data, &result) != nil {
		return nil, nil, errors.New("probe response was not JSON")
	}
	return result, response.Header, nil
}
func (p *probe) directory(ctx context.Context, token string, want int) (time.Time, error) {
	body, headers, err := p.request(ctx, "GET", p.c, "/api/v1/channels", nil, map[string]string{"Authorization": "Bearer " + token}, want)
	if err != nil {
		return time.Time{}, err
	}
	if want != 200 {
		if _, ok := body["channels"]; ok {
			return time.Time{}, errors.New("failed directory disclosed data")
		}
		return time.Time{}, nil
	}
	expires, err := time.Parse(time.RFC3339Nano, headers.Get("Session-Expires-At"))
	if err != nil || !strings.HasSuffix(headers.Get("Session-Expires-At"), "Z") || expires.Before(time.Now()) {
		return time.Time{}, errors.New("invalid committed directory expiry")
	}
	raw, ok := body["channels"].([]any)
	if !ok || len(body) != 1 || len(raw) != 7 {
		return time.Time{}, errors.New("directory shape invalid")
	}
	records := make([]channels.Channel, len(raw))
	for i, item := range raw {
		m, ok := item.(map[string]any)
		if !ok || len(m) != 5 {
			return time.Time{}, errors.New("directory record exposed extra fields")
		}
		wire, err := json.Marshal(m)
		if err != nil {
			return time.Time{}, err
		}
		var public struct {
			ID               string `json:"id"`
			Code             string `json:"code"`
			Name             string `json:"name"`
			InitiallyVisible bool   `json:"initiallyVisible"`
			DisplayOrder     int    `json:"displayOrder"`
		}
		if json.Unmarshal(wire, &public) != nil {
			return time.Time{}, errors.New("directory record invalid")
		}
		if err = records[i].ID.UnmarshalText([]byte(public.ID)); err != nil {
			return time.Time{}, errors.New("directory UUID invalid")
		}
		records[i].Code, records[i].Name, records[i].InitiallyVisible, records[i].DisplayOrder = public.Code, public.Name, public.InitiallyVisible, public.DisplayOrder
	}
	if channels.ValidateCatalog(records) != nil {
		return time.Time{}, errors.New("directory failed complete catalog validation")
	}
	return expires, nil
}
func (p *probe) login(ctx context.Context, s state) (state, error) {
	key, err := randomCapability(32)
	if err != nil {
		return s, err
	}
	installation, err := randomCapability(16)
	if err != nil {
		return s, err
	}
	body, _, err := p.request(ctx, "POST", p.c, "/api/v1/auth/sessions", map[string]string{"username": s.Username, "password": s.Password, "installationId": installation}, map[string]string{"Idempotency-Key": key}, 201)
	if err != nil {
		return s, err
	}
	s.Token, err = field(body, "sessionToken")
	if err != nil {
		return s, err
	}
	s.ExpiresAt, err = p.directory(ctx, s.Token, 200)
	return s, err
}
func (p *probe) save(s state) error {
	raw, err := json.Marshal(s)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(p.statePath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if errors.Is(err, os.ErrExist) {
		info, statErr := os.Lstat(p.statePath)
		if statErr != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 {
			return errors.New("unsafe existing probe state")
		}
		f, err = os.OpenFile(p.statePath, os.O_WRONLY|os.O_TRUNC, 0600)
	}
	if err != nil {
		return errors.New("cannot save private probe state")
	}
	defer f.Close()
	if _, err = f.Write(raw); err != nil {
		return err
	}
	return f.Sync()
}
func (p *probe) load() (state, error) {
	var s state
	info, err := os.Lstat(p.statePath)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() > 4096 {
		return s, errors.New("unsafe probe state")
	}
	raw, err := os.ReadFile(p.statePath)
	if err != nil || json.Unmarshal(raw, &s) != nil || s.Username == "" || s.Password == "" || s.Token == "" {
		return s, errors.New("probe state invalid")
	}
	return s, nil
}
func (p *probe) run(ctx context.Context, phase string) error {
	if phase == "lifecycle" {
		s, err := p.lifecycle(ctx)
		if err != nil {
			return err
		}
		return p.save(s)
	}
	s, err := p.load()
	if err != nil {
		return err
	}
	switch phase {
	case "identities":
		if err = p.identities(ctx, &s); err != nil {
			return err
		}
		return p.save(s)
	case "threshold":
		return p.threshold(ctx, s)
	case "closure":
		return p.closure(ctx, s)
	case "restart":
		_, _, err = p.request(ctx, "GET", p.c, "/api/v1/auth/session", nil, map[string]string{"Authorization": "Bearer " + s.Token}, 200)
		if err != nil {
			return err
		}
		expiry, err := p.directory(ctx, s.Token, 200)
		if err == nil && !expiry.Equal(s.ExpiresAt) {
			return errors.New("restart changed non-threshold session expiry")
		}
		if err != nil {
			return err
		}
		return p.identitySnapshot(ctx, s)
	case "frozen":
		if _, err = p.directory(ctx, s.Token, 503); err != nil {
			return err
		}
		_, _, err = p.request(ctx, "GET", p.c, identitiesPath, nil, map[string]string{"Authorization": "Bearer " + s.Token}, 503)
		return err
	case "recovered":
		if _, err = p.directory(ctx, s.Token, 401); err != nil {
			return err
		}
		if _, _, err = p.request(ctx, "GET", p.c, identitiesPath, nil, map[string]string{"Authorization": "Bearer " + s.Token}, 401); err != nil {
			return err
		}
		s, err = p.login(ctx, s)
		if err != nil {
			return err
		}
		if err = p.identitySnapshot(ctx, s); err != nil {
			return err
		}
		return p.save(s)
	default:
		return errors.New("unknown probe phase")
	}
}
func (p *probe) lifecycle(ctx context.Context) (state, error) {
	var s state
	suffix, err := randomCapability(8)
	if err != nil {
		return s, err
	}
	// Username stays within the server's private username grammar.
	sum := sha256.Sum256([]byte(suffix))
	s.Username = fmt.Sprintf("probe_%x", sum[:6])
	s.Password = "isolated runtime independent long password 2026!"
	email := fmt.Sprintf("runtime-%x@hainanu.edu.cn", sum[:8])
	installation, err := randomCapability(16)
	if err != nil {
		return s, err
	}
	key, err := randomCapability(32)
	if err != nil {
		return s, err
	}
	otpRequest, _, err := p.request(ctx, "POST", p.v, "/api/v1/eligibility/otp-requests", map[string]string{"email": email}, map[string]string{"Idempotency-Key": key, "V-Installation-ID": installation}, 202)
	if err != nil {
		return s, err
	}
	flow, err := field(otpRequest, "flowId")
	if err != nil {
		return s, err
	}
	code, err := p.otp(ctx, email)
	if err != nil {
		return s, err
	}
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return s, err
	}
	var bootstrap protocol.PublicKey
	copy(bootstrap[:], public)
	slot, err := protocol.DeriveSlot(bootstrap)
	if err != nil {
		return s, err
	}
	confirmKey, err := randomCapability(32)
	if err != nil {
		return s, err
	}
	confirmed, _, err := p.request(ctx, "POST", p.v, "/api/v1/eligibility/otp-confirmations", map[string]string{"flowId": flow, "otp": code, "slotId": protocol.EncodeCanonicalBase64url(slot[:]), "bootstrapPublicKey": protocol.EncodeCanonicalBase64url(public)}, map[string]string{"Idempotency-Key": confirmKey, "V-Installation-ID": installation}, 200)
	if err != nil {
		return s, err
	}
	ticketText, err := field(confirmed, "registrationTicket")
	if err != nil {
		return s, err
	}
	cInstallation, err := randomCapability(16)
	if err != nil {
		return s, err
	}
	intent, _, err := p.request(ctx, "POST", p.c, "/api/v1/auth/registration-intents", map[string]string{"registrationTicket": ticketText, "username": s.Username, "password": s.Password, "installationId": cInstallation}, nil, 201)
	if err != nil {
		return s, err
	}
	idText, err := field(intent, "intentId")
	if err != nil {
		return s, err
	}
	challengeText, err := field(intent, "challenge")
	if err != nil {
		return s, err
	}
	recoveryCode, err := field(intent, "recoveryCode")
	if err != nil {
		return s, err
	}
	idBytes, err := protocol.DecodeCanonicalBase64url(idText, 32)
	if err != nil {
		return s, errors.New("intent id invalid")
	}
	challengeBytes, err := protocol.DecodeCanonicalBase64url(challengeText, 32)
	if err != nil {
		return s, errors.New("challenge invalid")
	}
	ticket, err := protocol.ParseRegistrationTicket(ticketText)
	if err != nil {
		return s, errors.New("ticket invalid")
	}
	var id protocol.IntentID
	copy(id[:], idBytes)
	var challenge protocol.Challenge
	copy(challenge[:], challengeBytes)
	proof := protocol.BootstrapMessageBytes(ticket, id, challenge)
	signupKey, err := randomCapability(32)
	if err != nil {
		return s, err
	}
	registered, _, err := p.request(ctx, "POST", p.c, "/api/v1/auth/registrations", map[string]string{"intentId": idText, "bootstrapSignature": protocol.EncodeCanonicalBase64url(ed25519.Sign(private, proof[:])), "recoveryCodeConfirmation": recoveryCode}, map[string]string{"Idempotency-Key": signupKey}, 201)
	if err != nil {
		return s, err
	}
	s.Token, err = field(registered, "sessionToken")
	if err != nil {
		return s, err
	}
	s.ExpiresAt, err = p.directory(ctx, s.Token, 200)
	if err != nil {
		return s, err
	}
	oldToken := s.Token
	s, err = p.login(ctx, s)
	if err != nil {
		return s, err
	}
	if _, err = p.directory(ctx, oldToken, 401); err != nil {
		return s, err
	}
	tokenBytes, err := protocol.DecodeCanonicalBase64url(s.Token, 32)
	if err != nil {
		return s, errors.New("session token invalid")
	}
	revoke := sha256.Sum256(append([]byte("HNUHOLE/SESSION-REVOKE/V1\x00"), tokenBytes...))
	if _, _, err = p.request(ctx, "POST", p.c, "/api/v1/auth/session-revocations", nil, map[string]string{"Authorization": "SessionRevoke " + protocol.EncodeCanonicalBase64url(revoke[:])}, 204); err != nil {
		return s, err
	}
	if _, err = p.directory(ctx, s.Token, 401); err != nil {
		return s, err
	}
	s, err = p.login(ctx, s)
	if err != nil {
		return s, err
	}
	beforeReset := s.Token
	reset, _, err := p.request(ctx, "POST", p.c, "/api/v1/auth/recovery-code-reset-intents", map[string]string{"recoveryCode": recoveryCode}, nil, 201)
	if err != nil {
		return s, err
	}
	resetID, err := field(reset, "resetIntentId")
	if err != nil {
		return s, err
	}
	newCode, err := field(reset, "newRecoveryCode")
	if err != nil {
		return s, err
	}
	resetKey, err := randomCapability(32)
	if err != nil {
		return s, err
	}
	s.Password = "isolated runtime changed independent password 2026!"
	if _, _, err = p.request(ctx, "POST", p.c, "/api/v1/auth/password-resets", map[string]string{"resetIntentId": resetID, "newPassword": s.Password, "newRecoveryCodeConfirmation": newCode}, map[string]string{"Idempotency-Key": resetKey}, 204); err != nil {
		return s, err
	}
	if _, err = p.directory(ctx, beforeReset, 401); err != nil {
		return s, err
	}
	return p.login(ctx, s)
}
func (p *probe) otp(ctx context.Context, email string) (string, error) {
	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()
	timeout := time.NewTimer(30 * time.Second)
	defer timeout.Stop()
	pattern := regexp.MustCompile(`Your Hnuhole campus verification code is ([0-9]{6})\.`)
	for {
		req, err := http.NewRequestWithContext(ctx, "GET", strings.TrimSuffix(p.mailpit, "/")+"/api/v1/message/latest/raw", nil)
		if err != nil {
			return "", errors.New("Mailpit request invalid")
		}
		response, err := p.local.Do(req)
		if err == nil {
			raw, readErr := io.ReadAll(io.LimitReader(response.Body, 16385))
			response.Body.Close()
			if response.StatusCode == 200 && readErr == nil && len(raw) <= 16384 {
				message, parseErr := mail.ReadMessage(bytes.NewReader(raw))
				if parseErr == nil {
					to, parseErr := mail.ParseAddress(message.Header.Get("To"))
					if parseErr == nil && to.Address == email {
						body, bodyErr := io.ReadAll(io.LimitReader(message.Body, 4096))
						match := pattern.FindSubmatch(body)
						if bodyErr == nil && len(match) == 2 {
							return string(match[1]), nil
						}
					}
				}
			}
		}
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case <-timeout.C:
			return "", errors.New("real SMTP OTP was not delivered within bound")
		case <-ticker.C:
		}
	}
}

// fixturePool refuses any connection without the isolated runner's matching
// application marker and private directory marker. Fixtures touch only this
// probe's synthetic account; they never run DDL or weaken database constraints.
func (p *probe) fixturePool(ctx context.Context) (*pgxpool.Pool, error) {
	tag := os.Getenv("AUTHRUNTIME_TAG")
	config, err := pgxpool.ParseConfig(os.Getenv("AUTHRUNTIME_C_DSN"))
	marker, markerErr := os.ReadFile(filepath.Join(filepath.Dir(p.statePath), ".runtime-tag"))
	if err != nil || markerErr != nil || !strings.HasPrefix(tag, "hnuhole_runtime_") || len(tag) < 24 || strings.TrimSpace(string(marker)) != tag ||
		config.ConnConfig.RuntimeParams["application_name"] != tag || config.ConnConfig.Database != "hnuhole_c" || !strings.HasSuffix(config.ConnConfig.User, "_runtime") {
		return nil, errors.New("refusing unmarked runtime fixture database")
	}
	ip := net.ParseIP(config.ConnConfig.Host)
	if ip == nil || !ip.IsLoopback() {
		return nil, errors.New("fixture database must use literal loopback")
	}
	config.MaxConns = 2
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, errors.New("cannot open fixture runtime connection")
	}
	var restricted bool
	err = pool.QueryRow(ctx, `SELECT NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication)
        AND NOT EXISTS(SELECT 1 FROM pg_class WHERE relnamespace='c_auth'::regnamespace AND relowner=(SELECT oid FROM pg_roles WHERE rolname=current_user))
        FROM pg_roles WHERE rolname=current_user`).Scan(&restricted)
	if err != nil || !restricted {
		pool.Close()
		return nil, errors.New("fixture connection is not a restricted runtime role")
	}
	return pool, nil
}
func (p *probe) threshold(ctx context.Context, s state) error {
	pool, err := p.fixturePool(ctx)
	if err != nil {
		return err
	}
	defer pool.Close()
	token, err := protocol.DecodeCanonicalBase64url(s.Token, 32)
	if err != nil {
		return errors.New("invalid fixture token")
	}
	hash := sha256.Sum256(token)
	command, err := pool.Exec(ctx, `UPDATE c_auth.sessions s SET expires_at=clock_timestamp()+interval '6 days'
        FROM c_auth.accounts a WHERE s.token_digest=$1 AND s.account_id=a.account_id AND a.username=$2
        AND a.state='ACTIVE' AND s.revoked_at IS NULL`, hash[:], s.Username)
	if err != nil || command.RowsAffected() != 1 {
		return errors.New("cannot prepare synthetic threshold fixture")
	}
	expiry, err := p.directory(ctx, s.Token, 200)
	if err != nil {
		return err
	}
	if expiry.Before(time.Now().Add(29*24*time.Hour)) || expiry.After(time.Now().Add(31*24*time.Hour)) {
		return errors.New("threshold directory did not renew to final time plus thirty days")
	}
	var stored time.Time
	if err = pool.QueryRow(ctx, `SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1`, hash[:]).Scan(&stored); err != nil || !stored.Equal(expiry) {
		return errors.New("directory header did not match committed server expiry")
	}
	again, err := p.directory(ctx, s.Token, 200)
	if err != nil {
		return err
	}
	if !again.Equal(expiry) {
		return errors.New("non-threshold directory accumulated renewal days")
	}
	s.ExpiresAt = expiry
	return p.save(s)
}
func (p *probe) closure(ctx context.Context, s state) error {
	pool, err := p.fixturePool(ctx)
	if err != nil {
		return err
	}
	defer pool.Close()
	id, err := randomCapability(32)
	if err != nil {
		return err
	}
	secretText, err := randomCapability(32)
	if err != nil {
		return err
	}
	secret, err := protocol.DecodeCanonicalBase64url(secretText, 32)
	if err != nil {
		return err
	}
	statusDigest := sha256.Sum256(append([]byte("HNUHOLE/CLOSE-STATUS/V1\x00"), secret...))
	accepted, _, err := p.request(ctx, "POST", p.c, "/api/v1/account-closures", map[string]string{"closureId": id, "password": s.Password, "statusDigest": protocol.EncodeCanonicalBase64url(statusDigest[:])}, map[string]string{"Authorization": "Bearer " + s.Token}, 202)
	if err != nil {
		return err
	}
	dueText, err := field(accepted, "dueAt")
	if err != nil {
		return err
	}
	due, err := time.Parse(time.RFC3339Nano, dueText)
	if err != nil || due.Before(time.Now().Add(6*24*time.Hour)) || due.After(time.Now().Add(8*24*time.Hour)) {
		return errors.New("real closure did not establish seven-day deadline")
	}
	if _, err = p.directory(ctx, s.Token, 401); err != nil {
		return err
	}
	s, err = p.login(ctx, s)
	if err != nil {
		return err
	}
	status, _, err := p.request(ctx, "GET", p.c, "/api/v1/account-closures/"+id, nil, map[string]string{"Authorization": "ClosureStatus " + secretText}, 200)
	if err != nil || status["state"] != "CANCELLED" {
		return errors.New("active password login did not cancel pending closure")
	}
	// A separate already-due synthetic request exercises the deadline worker
	// without waiting seven days or modifying the real request's immutable due.
	fixtureID, err := randomCapability(32)
	if err != nil {
		return err
	}
	fixtureBytes, err := protocol.DecodeCanonicalBase64url(fixtureID, 32)
	if err != nil {
		return err
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return errors.New("cannot create due closure fixture")
	}
	defer tx.Rollback(ctx)
	var account string
	var generation int64
	err = tx.QueryRow(ctx, `UPDATE c_auth.accounts SET state='PENDING_CLOSE',closure_generation=closure_generation+1,
        session_generation=session_generation+1 WHERE username=$1 AND state='ACTIVE' RETURNING account_id::text,closure_generation`, s.Username).Scan(&account, &generation)
	if err != nil {
		return errors.New("cannot set synthetic pending closure")
	}
	if _, err = tx.Exec(ctx, `UPDATE c_auth.sessions SET revoked_at=clock_timestamp(),revocation_reason='CLOSURE'
        WHERE account_id=$1::uuid AND revoked_at IS NULL`, account); err != nil {
		return errors.New("cannot revoke synthetic closure sessions")
	}
	if _, err = tx.Exec(ctx, `INSERT INTO c_auth.closure_requests(closure_id,account_id,status_digest,request_generation,due_at,state)
        VALUES($1,$2::uuid,$3,$4,clock_timestamp()-interval '1 second','PENDING')`, fixtureBytes, account, statusDigest[:], generation); err != nil {
		return errors.New("cannot insert synthetic due closure")
	}
	if err = tx.Commit(ctx); err != nil {
		return errors.New("cannot commit due closure fixture")
	}
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	timeout := time.NewTimer(30 * time.Second)
	defer timeout.Stop()
	for {
		status, _, err = p.request(ctx, "GET", p.c, "/api/v1/account-closures/"+fixtureID, nil, map[string]string{"Authorization": "ClosureStatus " + secretText}, 200)
		if err == nil && status["state"] == "RELEASED" {
			var acknowledged bool
			err = pool.QueryRow(ctx, `SELECT l.receipt_acknowledged AND r.released_at IS NOT NULL
                FROM c_auth.closure_requests r JOIN c_auth.slot_ledger l USING(slot_id) WHERE r.closure_id=$1`, fixtureBytes).Scan(&acknowledged)
			if err != nil || !acknowledged {
				return errors.New("release response preceded durable local ACK")
			}
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-timeout.C:
			return errors.New("due closure worker did not persist V release ACK")
		case <-ticker.C:
		}
	}
}
