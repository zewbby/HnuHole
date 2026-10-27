// Package commentsnapshot stores short-lived immutable comment ID orders.
// Authorization and the SQL transaction remain the caller's responsibility.
package commentsnapshot

import (
	"context"
	"errors"
	"net"
	"regexp"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
)

var (
	ErrInvalid     = errors.New("invalid comment snapshot")
	ErrUnavailable = errors.New("comment snapshot storage unavailable")
	ErrIntegrity   = errors.New("comment snapshot storage integrity")
	ErrCapacity    = errors.New("comment snapshot capacity")
	ErrTooLarge    = errors.New("comment snapshot too large")
	ErrRequest     = errors.New("invalid comment snapshot request")
)

type QuotaError struct{ RetryAfter int }

func (*QuotaError) Error() string { return "comment snapshot account quota" }

type RedisConfig struct {
	Address              string `json:"address"`
	Username             string `json:"username"`
	PasswordFile         string `json:"passwordFile"`
	Namespace            string `json:"namespace"`
	Epoch                string `json:"epoch"`
	DeadlineMilliseconds int    `json:"deadlineMilliseconds"`
	PoolSize             int    `json:"poolSize"`
}

type Config struct {
	CreateBackend string `json:"createBackend"`
	ReadPostgres  bool   `json:"readPostgres"`
	ReadRedis     bool   `json:"readRedis"`
	// PostgresCursorVersion 0 or 1 emits V1 during mixed-fleet rollout; 2
	// requires every reader to support V2. Existing V1 cursors stay V1.
	PostgresCursorVersion       int         `json:"postgresCursorVersion,omitempty"`
	TTLSeconds                  int         `json:"ttlSeconds"`
	MaxIDs                      int         `json:"maxIDs"`
	MaxPerAccount               int         `json:"maxPerAccount"`
	MaxSnapshotBytes            int         `json:"maxSnapshotBytes"`
	MaxModuleBytes              int64       `json:"maxModuleBytes"`
	MaxLedgerEntries            int         `json:"maxLedgerEntries"`
	MaxLedgerBytes              int         `json:"maxLedgerBytes"`
	LedgerFixedReserveBytes     int64       `json:"ledgerFixedReserveBytes"`
	OperationBudgetMilliseconds int         `json:"operationBudgetMilliseconds"`
	PrepareLeaseSeconds         int         `json:"prepareLeaseSeconds"`
	CleanupIntervalSeconds      int         `json:"cleanupIntervalSeconds"`
	CleanupBatchSize            int         `json:"cleanupBatchSize"`
	ClockSkewMilliseconds       int         `json:"clockSkewMilliseconds"`
	Redis                       RedisConfig `json:"redis"`
}

func DefaultConfig() Config {
	return Config{CreateBackend: "redis", ReadPostgres: true, ReadRedis: true, TTLSeconds: 1800, MaxIDs: 10000,
		MaxPerAccount: 1024, MaxSnapshotBytes: 196608, MaxModuleBytes: 67108864,
		MaxLedgerEntries: 8192, MaxLedgerBytes: 4194304, LedgerFixedReserveBytes: 12582912,
		OperationBudgetMilliseconds: 500, PrepareLeaseSeconds: 30, CleanupIntervalSeconds: 10,
		CleanupBatchSize: 64, ClockSkewMilliseconds: 2000,
		Redis: RedisConfig{DeadlineMilliseconds: 100, PoolSize: 8}}
}

// Validate accepts small internal fixture quotas. Runtime additionally calls
// ValidateRuntime to prohibit shipping those fixture settings as defaults.
func (c Config) Validate() error {
	if (c.CreateBackend != "postgres" && c.CreateBackend != "redis") || (c.CreateBackend == "postgres" && !c.ReadPostgres) || (c.CreateBackend == "redis" && !c.ReadRedis) || c.TTLSeconds != 1800 || c.MaxIDs != 10000 || c.MaxPerAccount < 1 || c.MaxPerAccount > 65536 || c.MaxSnapshotBytes < 153 || c.MaxSnapshotBytes > 1048576 || c.MaxLedgerEntries < 1 || c.MaxLedgerEntries > 8192 || c.MaxLedgerBytes < 1024 || c.MaxLedgerBytes > 4194304 || c.LedgerFixedReserveBytes < int64(2*c.MaxLedgerBytes) || c.MaxModuleBytes <= c.LedgerFixedReserveBytes || c.MaxModuleBytes > 1<<40 || c.OperationBudgetMilliseconds < 50 || c.OperationBudgetMilliseconds > 1000 || c.PrepareLeaseSeconds != 30 || c.CleanupIntervalSeconds < 1 || c.CleanupIntervalSeconds > 10 || c.CleanupBatchSize < 1 || c.CleanupBatchSize > 64 || c.ClockSkewMilliseconds < 0 || c.ClockSkewMilliseconds > 2000 {
		return errors.New("invalid bounded comment snapshot configuration")
	}
	if c.ReadRedis {
		if _, _, err := net.SplitHostPort(c.Redis.Address); err != nil {
			return errors.New("invalid comment snapshot address")
		}
		epoch, err := uuid.Parse(c.Redis.Epoch)
		if err != nil || epoch == uuid.Nil || epoch.String() != c.Redis.Epoch || !regexp.MustCompile(`^hnuhole:comment-snapshot:v2:[a-z][a-z0-9_-]{0,47}:$`).MatchString(c.Redis.Namespace) || c.Redis.DeadlineMilliseconds < 10 || c.Redis.DeadlineMilliseconds > 1000 || c.Redis.PoolSize < 1 || c.Redis.PoolSize > 64 {
			return errors.New("invalid isolated comment snapshot Redis configuration")
		}
	}
	if c.PostgresCursorVersion < 0 || c.PostgresCursorVersion > 2 {
		return errors.New("unsupported PostgreSQL cursor emission version")
	}
	return nil
}
func (c Config) ValidateRuntime() error {
	if err := c.Validate(); err != nil {
		return err
	}
	if c.MaxPerAccount < 501 || c.MaxLedgerEntries < 501 || c.MaxSnapshotBytes < 160153 {
		return errors.New("comment snapshot runtime cannot satisfy required reading capacity")
	}
	if c.ReadRedis {
		workers := min(8, c.Redis.PoolSize-1)
		if workers < 1 {
			return errors.New("snapshot cleanup needs a foreground pool slot")
		}
		batches := (c.MaxLedgerEntries + c.CleanupBatchSize - 1) / c.CleanupBatchSize
		waves := (batches + workers - 1) / workers
		if (waves+2)*c.Redis.DeadlineMilliseconds+500 >= 5000 {
			return errors.New("snapshot cleanup cannot meet bounded recovery envelope")
		}
	}
	return nil
}

type MAC func([32]byte) [32]byte

const (
	Postgres byte = 1
	Redis    byte = 2
)

type Scope struct {
	Owner [32]byte
	Post  uuid.UUID
	Root  uuid.UUID
	Kind  comments.OrderKind
	Sort  comments.SortMode
}

func (s Scope) Valid() bool {
	return s.Owner != ([32]byte{}) && s.Post != uuid.Nil && s.Sort.Valid() && ((s.Kind == comments.MainComments && s.Root == uuid.Nil) || (s.Kind == comments.Replies && s.Root != uuid.Nil && (s.Sort == "" || s.Sort == comments.Relevant)))
}
func NormalizeSort(s comments.SortMode) comments.SortMode {
	if s == "" {
		return comments.Relevant
	}
	return s
}

type Ref struct {
	Backend byte
	Epoch   uuid.UUID
	ID      uuid.UUID
	Expires time.Time
	Kind    comments.OrderKind
	Sort    comments.SortMode
}
type Snapshot struct {
	Ref     Ref
	Scope   Scope
	Created time.Time
	IDs     []uuid.UUID
}
type RequestIdentity struct {
	Key   string
	Scope string
}
type Prepared struct {
	Snapshot     Snapshot
	Token        string
	Digest       string
	NewlyCreated bool
	Payload      []byte
}

// Budget accounts only store-call time; the SQL gap does not consume it.
// The request context still bounds the complete handler.
type budget struct {
	mu        sync.Mutex
	remaining time.Duration
	elapsed   time.Duration
}
type budgetKey struct{}

func WithBudget(ctx context.Context, milliseconds int) context.Context {
	return context.WithValue(ctx, budgetKey{}, &budget{remaining: time.Duration(milliseconds) * time.Millisecond})
}
func bound(ctx context.Context, deadline time.Duration) (context.Context, func(), error) {
	b, _ := ctx.Value(budgetKey{}).(*budget)
	if b != nil {
		b.mu.Lock()
		if b.remaining < deadline {
			deadline = b.remaining
		}
		b.mu.Unlock()
	}
	if deadline <= 0 {
		return nil, nil, ErrUnavailable
	}
	started := time.Now()
	child, cancel := context.WithTimeout(ctx, deadline)
	return child, func() {
		cancel()
		if b != nil {
			b.mu.Lock()
			elapsed := time.Since(started)
			b.remaining -= elapsed
			b.elapsed += elapsed
			b.mu.Unlock()
		}
	}, nil
}

// BudgetElapsed is diagnostic client-side store time, including connection,
// queue and transport waits. It is not Redis server execution time.
func BudgetElapsed(ctx context.Context) time.Duration {
	b, _ := ctx.Value(budgetKey{}).(*budget)
	if b == nil {
		return 0
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.elapsed
}
