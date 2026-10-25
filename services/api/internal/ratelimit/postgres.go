package ratelimit

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresNamespaceStore struct {
	pool  *pgxpool.Pool
	table string
}

func NewPostgresNamespaceStore(pool *pgxpool.Pool, service string) (*PostgresNamespaceStore, error) {
	if pool == nil || service != "community" && service != "verifier" {
		return nil, ErrUnavailable
	}
	schema := "c_rate_limit"
	if service == "verifier" {
		schema = "v_rate_limit"
	}
	return &PostgresNamespaceStore{pool, schema + ".namespace"}, nil
}
func (s *PostgresNamespaceStore) Load(ctx context.Context) (n Namespace, err error) {
	var window int64
	err = s.pool.QueryRow(ctx, `SELECT generation,run_id,state,barrier_until,dirty_until,policy_hash,recovery_window_ms FROM `+s.table+` WHERE singleton_id=1`).Scan(&n.Generation, &n.RunID, &n.State, &n.BarrierUntil, &n.DirtyUntil, &n.PolicyHash, &window)
	n.RecoveryWindow = time.Duration(window) * time.Millisecond
	if err != nil {
		err = ErrUnavailable
	}
	return
}
func (s *PostgresNamespaceStore) Recover(ctx context.Context, expected int64, run string, window time.Duration) (Namespace, error) {
	if run == "" || window <= 0 || window > 24*time.Hour {
		return Namespace{}, ErrUnavailable
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Namespace{}, ErrUnavailable
	}
	defer tx.Rollback(ctx)
	// Acquire the namespace row before evaluating the barrier start. UPDATE
	// expressions can otherwise be evaluated before waiting for a SHARE lock.
	var generation int64
	if err = tx.QueryRow(ctx, `SELECT generation FROM `+s.table+` WHERE singleton_id=1 FOR UPDATE`).Scan(&generation); err != nil {
		return Namespace{}, ErrUnavailable
	}
	if generation == expected {
		_, err = tx.Exec(ctx, `UPDATE `+s.table+` SET generation=CASE WHEN state='READY' OR run_id<>$1 THEN generation+1 ELSE generation END,run_id=$1,state='RECOVERING',barrier_until=GREATEST(barrier_until,COALESCE(dirty_until,clock_timestamp()),clock_timestamp()+($2::bigint*interval '1 millisecond')) WHERE singleton_id=1 AND generation=$3`, run, window.Milliseconds(), expected)
		if err != nil {
			return Namespace{}, ErrUnavailable
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return Namespace{}, ErrUnavailable
	}
	return s.Load(ctx)
}
func (s *PostgresNamespaceStore) Activate(ctx context.Context, generation int64, run string) (Namespace, error) {
	_, err := s.pool.Exec(ctx, `UPDATE `+s.table+` SET state='READY',dirty_until=NULL WHERE singleton_id=1 AND generation=$1 AND run_id=$2 AND state='RECOVERING' AND barrier_until<=clock_timestamp()`, generation, run)
	if err != nil {
		return Namespace{}, ErrUnavailable
	}
	n, err := s.Load(ctx)
	if err != nil || n.State != "READY" || n.Generation != generation || n.RunID != run {
		return n, ErrUnavailable
	}
	return n, nil
}

// Initialize requires the migration owner's INSERT privilege. Runtime roles
// receive no INSERT or DELETE privilege on namespace metadata.
func (s *PostgresNamespaceStore) Initialize(ctx context.Context, run, policyHash string, window time.Duration) (Namespace, error) {
	if len(run) != 40 || len(policyHash) != 64 || window < time.Millisecond || window > 24*time.Hour {
		return Namespace{}, ErrUnavailable
	}
	tag, err := s.pool.Exec(ctx, `INSERT INTO `+s.table+`(singleton_id,generation,run_id,state,barrier_until,policy_hash,recovery_window_ms) VALUES(1,1,$1,'READY',clock_timestamp(),$2,$3) ON CONFLICT DO NOTHING`, run, policyHash, window.Milliseconds())
	if err != nil || tag.RowsAffected() != 1 {
		return Namespace{}, fmt.Errorf("namespace already exists or cannot initialize")
	}
	return s.Load(ctx)
}

type verifiedDBFallbackKey struct{}
type verifiedDBFallback struct {
	policyHash string
	generation int64
	window     time.Duration
}

// WithVerifiedDBFallback is called only by a trusted boundary for actions with
// a verified final SQL limit. The final transaction must call MarkDBFallback.
func (c *Controller) WithVerifiedDBFallback(ctx context.Context) (context.Context, error) {
	n, err := c.store.Load(ctx)
	if err != nil || n.State != "READY" || n.Generation < 1 || n.PolicyHash != c.policyHash {
		return ctx, ErrUnavailable
	}
	return context.WithValue(ctx, verifiedDBFallbackKey{}, verifiedDBFallback{c.policyHash, n.Generation, c.recoveryWindow}), nil
}
func MarkDBFallback(ctx context.Context, tx pgx.Tx, service string) error {
	proof, ok := ctx.Value(verifiedDBFallbackKey{}).(verifiedDBFallback)
	if !ok {
		return nil
	}
	schema := "v_rate_limit"
	if service != "verifier" {
		return ErrUnavailable
	}
	var generation int64
	var state, policyHash string
	if err := tx.QueryRow(ctx, `SELECT generation,state,policy_hash FROM `+schema+`.namespace WHERE singleton_id=1 FOR UPDATE`).Scan(&generation, &state, &policyHash); err != nil || state != "READY" || generation != proof.generation || policyHash != proof.policyHash {
		return ErrUnavailable
	}
	_, err := tx.Exec(ctx, `UPDATE `+schema+`.namespace SET dirty_until=GREATEST(COALESCE(dirty_until,clock_timestamp()),clock_timestamp()+($1::bigint*interval '1 millisecond')) WHERE singleton_id=1`, proof.window.Milliseconds())
	if err != nil {
		return ErrUnavailable
	}
	return nil
}

// Reconfigure is operator-only. The exclusive row lock drains final business
// transactions before sampling now; old and new effective windows both apply.
func (s *PostgresNamespaceStore) Reconfigure(ctx context.Context, expected int64, run, hash string, window time.Duration) (Namespace, error) {
	if len(run) != 40 || len(hash) != 64 || window < time.Millisecond || window > 24*time.Hour {
		return Namespace{}, ErrUnavailable
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Namespace{}, ErrUnavailable
	}
	defer tx.Rollback(ctx)
	var generation, oldWindow int64
	if err = tx.QueryRow(ctx, `SELECT generation,recovery_window_ms FROM `+s.table+` WHERE singleton_id=1 FOR UPDATE`).Scan(&generation, &oldWindow); err != nil {
		return Namespace{}, ErrUnavailable
	}
	if generation != expected {
		return Namespace{}, ErrUnavailable
	}
	_, err = tx.Exec(ctx, `UPDATE `+s.table+` SET generation=generation+1,run_id=$1,policy_hash=$2,recovery_window_ms=$3,state='RECOVERING',barrier_until=GREATEST(barrier_until,COALESCE(dirty_until,clock_timestamp()),clock_timestamp()+(GREATEST($3::bigint,$4::bigint)*interval '1 millisecond')) WHERE singleton_id=1`, run, hash, window.Milliseconds(), oldWindow)
	if err != nil {
		return Namespace{}, ErrUnavailable
	}
	if err = tx.Commit(ctx); err != nil {
		return Namespace{}, ErrUnavailable
	}
	return s.Load(ctx)
}

type policyFenceKey struct{}

func (c *Controller) WithPolicyFence(ctx context.Context) context.Context {
	return context.WithValue(ctx, policyFenceKey{}, c.policyHash)
}

// RequirePolicyFence is used only at the final SQL mutation, after body reads
// and external validation. It never nests a metadata connection or Gate tx.
func RequirePolicyFence(ctx context.Context, tx pgx.Tx, service string) error {
	expected, ok := ctx.Value(policyFenceKey{}).(string)
	if !ok {
		return nil
	}
	schema := "c_rate_limit"
	if service == "verifier" {
		schema = "v_rate_limit"
	} else if service != "community" {
		return ErrUnavailable
	}
	var actual string
	if err := tx.QueryRow(ctx, `SELECT policy_hash FROM `+schema+`.namespace WHERE singleton_id=1 FOR SHARE`).Scan(&actual); err != nil {
		return ErrUnavailable
	}
	if actual != expected {
		return ErrPolicyMismatch
	}
	return nil
}
