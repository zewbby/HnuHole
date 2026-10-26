package authprivacyhttp

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/netip"
	"strings"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

type verifiedSharedSubjectKey struct{}

type SharedSubjectResolver interface {
	ResolveSharedSubject(context.Context, [32]byte) (string, error)
}
type SharedLimits struct {
	Engine         *ratelimit.Controller
	Key            [32]byte
	TrustedProxies []netip.Prefix
	Resolver       SharedSubjectResolver
	local          ratelimit.LocalRead
}

func (b *boundary) strictLimitPath(path string) bool {
	return isPostPath(path) || isCommentPath(path) || isDMPath(path) || isInboxPath(path)
}
func (b *boundary) sharedFailure(w http.ResponseWriter, r *http.Request, err error) {
	var limited *ratelimit.Limited
	if errors.As(err, &limited) {
		if b.strictLimitPath(r.URL.Path) {
			b.postFail(w, 429, "RATE_LIMITED", limited.RetryAfter)
		} else {
			b.fail(w, 429, "RATE_LIMITED", limited.RetryAfter)
		}
		return
	}
	if errors.Is(err, ratelimit.ErrUnavailable) || errors.Is(err, ratelimit.ErrLost) || errors.Is(err, ratelimit.ErrCapacity) || errors.Is(err, ratelimit.ErrPolicyMismatch) {
		code := "SERVICE_UNAVAILABLE"
		if r.Context().Value(verifiedSharedSubjectKey{}) == true {
			code = "SHARED_RATE_UNAVAILABLE"
		}
		if b.strictLimitPath(r.URL.Path) {
			b.postFail(w, 503, code, 0)
		} else {
			b.fail(w, 503, code, 0)
		}
		return
	}
	if b.strictLimitPath(r.URL.Path) {
		b.postFailure(w, err)
	} else {
		b.sessionFailure(w, err)
	}
}
func (b *boundary) sharedAdmit(ctx context.Context, subject, action string) error {
	if b.shared == nil {
		return nil
	}
	decision, err := b.shared.Engine.Admit(ctx, subject, []ratelimit.Charge{{Action: action, Cost: 1}}, ratelimit.Proof{})
	if errors.Is(err, ratelimit.ErrPolicyMismatch) {
		return err
	}
	if err != nil {
		r, ok := b.shared.Engine.Rule(action)
		if ok && r.Failure == "local-read" {
			if action == "entry.query" {
				decision, err = b.shared.local.AdmitWithBudget(subject+":"+action, 10000, 166)
			} else {
				decision, err = b.shared.local.Admit(subject + ":" + action)
			}
			b.shared.Engine.RecordFallback(action)
		}
	}
	if err != nil {
		return err
	}
	if !decision.Allowed {
		return &ratelimit.Limited{RetryAfter: decision.RetryAfter}
	}
	return nil
}
func (b *boundary) sourceSubject(r *http.Request, purpose, value string) (string, error) {
	network, err := canonicalNetwork(r.RemoteAddr)
	if err != nil {
		return "", err
	}
	return ratelimit.Digest(b.shared.Key, string(b.service), purpose, network+"\x00"+value), nil
}
func sharedControl(r *http.Request) bool {
	if r.Method == http.MethodPost && (strings.HasSuffix(r.URL.Path, "/ack") || strings.HasSuffix(r.URL.Path, "/read") || strings.HasPrefix(r.URL.Path, "/api/v1/dm/commands/") && strings.HasSuffix(r.URL.Path, "/close")) {
		return true
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		return false
	}
	return strings.Contains(r.URL.Path, "/commands/") || strings.Contains(r.URL.Path, "-commands/") || strings.Contains(r.URL.Path, "/me/post-tasks/") || strings.Contains(r.URL.Path, "/me/comment-tasks/")
}
func (b *boundary) sharedEntry(w http.ResponseWriter, r *http.Request) bool {
	if b.shared == nil {
		return true
	}
	subject, err := b.sourceSubject(r, "source", "")
	if err != nil {
		b.bad(w, err)
		return false
	}
	action := "entry.mutation"
	if r.Method == http.MethodGet || r.Method == http.MethodHead || sharedControl(r) {
		action = "entry.query"
	}
	err = b.sharedAdmit(r.Context(), subject, action)
	if err != nil {
		var limited *ratelimit.Limited
		if !errors.As(err, &limited) && b.service == CommunityService && b.shared.Resolver != nil {
			bearer, parseErr := sessionCapability(r.Header, "Bearer")
			if parseErr == nil {
				local, localErr := b.shared.local.AdmitWithBudget(subject+":entry-emergency", 10000, 166)
				if localErr != nil {
					b.sharedFailure(w, r, localErr)
					return false
				}
				if !local.Allowed {
					b.sharedFailure(w, r, &ratelimit.Limited{RetryAfter: local.RetryAfter})
					return false
				}
				_, authErr := b.shared.Resolver.ResolveSharedSubject(r.Context(), bearer)
				if authErr != nil {
					b.sharedFailure(w, r, authErr)
					return false
				}
				r = r.WithContext(context.WithValue(r.Context(), verifiedSharedSubjectKey{}, true))
				dbAction := ""
				if strings.HasPrefix(r.URL.Path, "/api/v1/post-commands/") {
					dbAction = "post.create"
				}
				if strings.HasPrefix(r.URL.Path, "/api/v1/comment-commands/") {
					dbAction = "comment.publish"
				}
				if dbAction != "" && b.shared.Engine.CanDBFallback(r.Context()) {
					if rule, ok := b.shared.Engine.Rule(dbAction); ok && rule.Failure == "verified-db" {
						b.shared.Engine.RecordFallback(dbAction)
						err = nil
					}
				}
			}
		}
		if err != nil && b.service == VerifierService && r.Method == http.MethodPost && (strings.HasSuffix(r.URL.Path, "/otp-requests") || strings.HasSuffix(r.URL.Path, "/otp-confirmations")) {
			otpAction := "otp.request"
			if strings.HasSuffix(r.URL.Path, "/otp-confirmations") {
				otpAction = "otp.verify"
			}
			var limited *ratelimit.Limited
			if rule, ok := b.shared.Engine.Rule(otpAction); ok && rule.Failure == "verified-db" && !errors.As(err, &limited) {
				local, e := b.shared.local.AdmitWithBudget(subject+":entry-emergency", 10000, 166)
				if e == nil && local.Allowed {
					var ctx context.Context
					ctx, e = b.shared.Engine.WithVerifiedDBFallback(r.Context())
					if e == nil {
						*r = *r.WithContext(ctx)
						err = nil
					}
				}
			}
		}
		if err != nil {
			b.sharedFailure(w, r, err)
			return false
		}
	}
	if b.service == VerifierService && r.Method == http.MethodPost && (strings.HasSuffix(r.URL.Path, "/otp-requests") || strings.HasSuffix(r.URL.Path, "/otp-confirmations")) {
		*r = *r.WithContext(b.shared.Engine.WithPolicyFence(r.Context()))
		action = "otp.request"
		if strings.HasSuffix(r.URL.Path, "/otp-confirmations") {
			action = "otp.verify"
		}
		if err = b.sharedAdmit(r.Context(), subject, action); err != nil {
			var limited *ratelimit.Limited
			if rule, ok := b.shared.Engine.Rule(action); ok && rule.Failure == "verified-db" && !errors.As(err, &limited) {
				var ctx context.Context
				ctx, err = b.shared.Engine.WithVerifiedDBFallback(r.Context())
				if err == nil {
					*r = *r.WithContext(ctx)
					b.shared.Engine.RecordFallback(action)
				}
			}
			if err != nil {
				b.sharedFailure(w, r, err)
				return false
			}
		}
	}
	control := sharedControl(r)
	if b.service == CommunityService && b.shared.Resolver != nil && (r.Method == http.MethodGet || control) {
		bearer, e := sessionCapability(r.Header, "Bearer")
		if e == nil {
			subject, e = b.shared.Resolver.ResolveSharedSubject(r.Context(), bearer)
			if e != nil {
				b.sharedFailure(w, r, e)
				return false
			}
			r = r.WithContext(context.WithValue(r.Context(), verifiedSharedSubjectKey{}, true))
			action = "read.account"
			if control {
				action = "read.control"
			}
			if e = b.sharedAdmit(r.Context(), subject, action); e != nil {
				b.sharedFailure(w, r, e)
				return false
			}
		}
	}
	return true
}

func (b *boundary) sharedLogin(w http.ResponseWriter, r *http.Request, identifier string) bool {
	if b.shared == nil {
		return true
	}
	ip, err := b.sourceSubject(r, "source", "")
	if err == nil {
		err = b.sharedAdmit(r.Context(), ip, "login.ip")
	}
	if err == nil && identifier != "" {
		var subject string
		subject, err = b.sourceSubject(r, "login-source", identifier)
		if err == nil {
			err = b.sharedAdmit(r.Context(), subject, "login.source")
		}
		if err == nil {
			var d ratelimit.Decision
			d, err = b.shared.Engine.Check(r.Context(), subject, []ratelimit.Charge{{Action: "login.failure", Cost: 1}})
			if err == nil && !d.Allowed {
				err = &ratelimit.Limited{RetryAfter: d.RetryAfter}
			}
		}
	}
	if err != nil {
		b.sharedFailure(w, r, err)
		return false
	}
	return true
}
func (b *boundary) sharedLoginResult(r *http.Request, identifier string, err error) {
	if b.shared == nil || identifier == "" {
		return
	}
	subject, e := b.sourceSubject(r, "login-source", identifier)
	if e != nil {
		return
	}
	if errors.Is(err, authprivacy.ErrAuthenticationFailed) {
		_, _ = b.shared.Engine.Admit(r.Context(), subject, []ratelimit.Charge{{Action: "login.failure", Cost: 1}}, ratelimit.Proof{})
	} else if err == nil {
		_ = b.shared.Engine.ResetAction(r.Context(), subject, "login.failure")
	}
}

func (b *boundary) readSharedBody(w http.ResponseWriter, r *http.Request, subject string, maximum int64) ([]byte, bool) {
	if b.shared == nil {
		data, err := io.ReadAll(io.LimitReader(r.Body, maximum+1))
		if err != nil {
			b.postBad(w, errMalformed)
			return nil, false
		}
		return data, true
	}
	if b.shared.Engine.TransferEnforced() {
		if err := http.NewResponseController(w).SetReadDeadline(time.Now().Add(b.shared.Engine.ReadWindow())); err != nil {
			b.sharedFailure(w, r.WithContext(context.WithValue(r.Context(), verifiedSharedSubjectKey{}, true)), ratelimit.ErrUnavailable)
			return nil, false
		}
	}
	*r = *r.WithContext(b.shared.Engine.WithPolicyFence(r.Context()))
	data, err := b.shared.Engine.ReadBody(r.Context(), subject, r.Body, maximum, r.ContentLength)
	if err != nil {
		b.sharedFailure(w, r.WithContext(context.WithValue(r.Context(), verifiedSharedSubjectKey{}, true)), err)
		return nil, false
	}
	return data, true
}
