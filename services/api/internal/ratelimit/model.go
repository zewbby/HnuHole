// Package ratelimit implements bounded, shared admission. Inputs are purpose-
// separated digests; HTTP credentials and business content never enter Redis.
package ratelimit

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"sync"
	"time"
)

type Mode string

const (
	Off     Mode = "off"
	Observe Mode = "observe"
	Enforce Mode = "enforce"
)

var (
	ErrPolicyMismatch = errors.New("shared admission policy does not match durable namespace")
	ErrUnavailable    = errors.New("shared admission unavailable")
	ErrLost           = errors.New("shared admission state lost")
	ErrCapacity       = errors.New("shared admission capacity exhausted")
	ErrConflict       = errors.New("shared admission fingerprint conflict")
	ErrStaleProof     = errors.New("shared admission proof belongs to a closed generation")
)

// Limits are integer units and milliseconds. A rule has either exact sliding
// windows or a fixed-point token bucket, never both.
type Window struct {
	Milliseconds int64 `json:"ms"`
	Limit        int64 `json:"limit"`
}
type Bucket struct {
	Capacity  int64 `json:"capacity"`
	PerSecond int64 `json:"perSecond"`
}
type Rule struct {
	Action  string   `json:"action"`
	Mode    Mode     `json:"mode"`
	Windows []Window `json:"windows,omitempty"`
	Bucket  *Bucket  `json:"bucket,omitempty"`
	Failure string   `json:"failure"` // reject, local-read, verified-db
}
type Charge struct {
	Action string `json:"action"`
	Cost   int64  `json:"cost"`
}
type Proof struct {
	ExpectedGeneration int64  `json:"expectedGeneration,omitempty"`
	Operation          string `json:"operation,omitempty"`
	Fingerprint        string `json:"fingerprint,omitempty"`
	Nonce              string `json:"nonce,omitempty"`
	Incarnation        string `json:"incarnation,omitempty"`
	Deadline           int64  `json:"deadline,omitempty"`
}
type Decision struct {
	Allowed     bool
	Replay      bool
	WouldDeny   bool
	RetryAfter  int
	Incarnation string
	Generation  int64
	Reserved    int64
}

// A durable store is deliberately outside Redis. Recovery atomically increments
// its generation once and persists a barrier before replacing an empty cache.
// Initial initialization is an explicit administrative operation.
type Namespace struct {
	PolicyHash     string
	RecoveryWindow time.Duration
	Evicted        int64 // transient observed Redis counter, committed in the sentinel
	Generation     int64
	RunID          string
	State          string
	BarrierUntil   time.Time
	DirtyUntil     *time.Time
}
type NamespaceStore interface {
	Load(context.Context) (Namespace, error)
	Recover(context.Context, int64, string, time.Duration) (Namespace, error)
	Activate(context.Context, int64, string) (Namespace, error)
}
type Metric struct {
	Requests, Allowed, Denied, WouldDeny, Errors, Fallbacks uint64
	Nanoseconds                                             uint64
}
type Metrics struct {
	mu      sync.Mutex
	actions map[string]Metric
}

func (m *Metrics) add(action, outcome string, elapsed time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.actions == nil {
		m.actions = make(map[string]Metric)
	}
	v := m.actions[action]
	v.Requests++
	v.Nanoseconds += uint64(elapsed)
	switch outcome {
	case "allow":
		v.Allowed++
	case "deny":
		v.Denied++
	case "would-deny":
		v.WouldDeny++
	case "error":
		v.Errors++
	case "fallback":
		v.Fallbacks++
	}
	m.actions[action] = v
}
func (m *Metrics) Snapshot() map[string]Metric {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make(map[string]Metric, len(m.actions))
	for k, v := range m.actions {
		out[k] = v
	}
	return out
}

// Digest has distinct domain, purpose and value frames. The value is never
// returned or retained, nor exposed as an observable metrics label.
func Digest(key [32]byte, domain, purpose, value string) string {
	h := hmac.New(sha256.New, key[:])
	h.Write([]byte("HNUHOLE/SHARED-LIMIT/V1\x00" + domain + "\x00" + purpose + "\x00" + value))
	return hex.EncodeToString(h.Sum(nil))
}
