package authprivacy

import (
	"context"
	"crypto/ed25519"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const authorizationSkew = 5 * time.Second
const authorizationEvidenceTTL = 5 * time.Minute

var ErrAuthorizationUnavailable = errors.New("authorization safety gate unavailable")

// AuthorizationDecision is valid only for its operation and generation.
// Callers must recheck at the final transaction boundary before trusting it.
type AuthorizationDecision struct {
	TrustedAt  time.Time
	Generation uint64
}

type AuthorizationGate interface {
	Snapshot(context.Context) (AuthorizationDecision, error)
	RecheckForCommit(context.Context, pgx.Tx, uint64) (AuthorizationDecision, error)
	CommitAuthorized(context.Context, pgx.Tx, uint64, ...func(AuthorizationDecision) error) (AuthorizationDecision, error)
	Abort(context.Context, pgx.Tx) error
}

type AuthorizationGateConfig struct {
	Pool                *pgxpool.Pool
	Domain              string
	Evidence            AuthorizationEvidenceProvider
	EvidencePublicKey   ed25519.PublicKey
	RecoveryPublicKey   ed25519.PublicKey
	BreakGlassPublicKey ed25519.PublicKey
	Anchor              *FileAuthorizationAnchorStore
	Clock               func() time.Time
}

type PostgresAuthorizationGate struct {
	pool                *pgxpool.Pool
	domain              string
	evidence            AuthorizationEvidenceProvider
	evidencePublicKey   ed25519.PublicKey
	recoveryPublicKey   ed25519.PublicKey
	breakGlassPublicKey ed25519.PublicKey
	anchor              *FileAuthorizationAnchorStore
	clock               func() time.Time
}

func NewPostgresAuthorizationGate(c AuthorizationGateConfig) (*PostgresAuthorizationGate, error) {
	if c.Pool == nil || c.Domain == "" || len(c.Domain) > 128 || c.Evidence == nil || c.Anchor == nil ||
		len(c.EvidencePublicKey) != ed25519.PublicKeySize || len(c.RecoveryPublicKey) != ed25519.PublicKeySize ||
		len(c.BreakGlassPublicKey) != ed25519.PublicKeySize || c.Clock == nil {
		return nil, errors.New("invalid authorization gate configuration")
	}
	return &PostgresAuthorizationGate{
		pool: c.Pool, domain: c.Domain, evidence: c.Evidence,
		evidencePublicKey:   append(ed25519.PublicKey(nil), c.EvidencePublicKey...),
		recoveryPublicKey:   append(ed25519.PublicKey(nil), c.RecoveryPublicKey...),
		breakGlassPublicKey: append(ed25519.PublicKey(nil), c.BreakGlassPublicKey...),
		anchor:              c.Anchor, clock: c.Clock,
	}, nil
}

type gateRow struct {
	state      string
	generation int64
	highwater  time.Time
	version    int64
}

func readGateRow(ctx context.Context, tx pgx.Tx) (gateRow, error) {
	var r gateRow
	err := tx.QueryRow(ctx, `SELECT gate_state,authorization_generation,trusted_high_watermark,evidence_version
		FROM c_auth.authorization_gate WHERE singleton_id=1 FOR UPDATE`).Scan(&r.state, &r.generation, &r.highwater, &r.version)
	return r, err
}

func (g *PostgresAuthorizationGate) verifyEvidence(s SignedAuthorizationEvidence, at time.Time, key ed25519.PublicKey) (AuthorizationEvidence, error) {
	e := s.Evidence
	message, err := json.Marshal(e)
	if err != nil || !ed25519.Verify(key, message, s.Signature) || e.Domain != g.domain ||
		e.Version == 0 || e.Generation == 0 || e.Version > math.MaxInt64 || e.Generation > math.MaxInt64 ||
		e.IssuedAt.IsZero() || e.TrustedAt.IsZero() || e.ValidUntil.IsZero() ||
		!e.ValidUntil.After(e.IssuedAt) || e.ValidUntil.Sub(e.IssuedAt) > authorizationEvidenceTTL ||
		e.TrustedAt.Before(e.IssuedAt) || e.TrustedAt.After(e.ValidUntil) ||
		e.TrustedAt.After(at.Add(authorizationSkew)) || e.IssuedAt.After(at.Add(authorizationSkew)) ||
		at.After(e.ValidUntil) {
		return AuthorizationEvidence{}, ErrAuthorizationUnavailable
	}
	return e, nil
}

// inspect runs while the database gate row and external file lock are held.
// A restored database row is accepted only if it matches the independent
// checkpoint exactly; a fresh evidence version may then advance both.
func (g *PostgresAuthorizationGate) inspect(ctx context.Context, row gateRow, anchor authorizationAnchor, exists bool) (AuthorizationDecision, AuthorizationEvidence, bool, string) {
	if row.state != "OPEN" || row.generation <= 0 || row.version <= 0 {
		return AuthorizationDecision{}, AuthorizationEvidence{}, false, "FROZEN"
	}
	if !exists || anchor.Domain != g.domain || anchor.Frozen ||
		anchor.Generation != uint64(row.generation) || anchor.Version != uint64(row.version) ||
		!anchor.Highwater.Equal(row.highwater) {
		return AuthorizationDecision{}, AuthorizationEvidence{}, false, "SNAPSHOT_OR_ANCHOR_MISMATCH"
	}
	now := g.clock().UTC()
	if now.Before(row.highwater.Add(-authorizationSkew)) {
		return AuthorizationDecision{}, AuthorizationEvidence{}, false, "TIME_ROLLBACK"
	}
	signed, err := g.evidence.Current(ctx)
	key := g.evidencePublicKey
	offline := false
	if err != nil {
		if anchor.OfflineEvidence == nil {
			return AuthorizationDecision{}, AuthorizationEvidence{}, false, "EVIDENCE_UNAVAILABLE"
		}
		signed, key, offline = *anchor.OfflineEvidence, g.breakGlassPublicKey, true
	}
	e, err := g.verifyEvidence(signed, now, key)
	if err != nil || e.Generation != uint64(row.generation) || e.Version < uint64(row.version) {
		return AuthorizationDecision{}, AuthorizationEvidence{}, false, "EVIDENCE_INVALID_OR_EXPIRED"
	}
	at := now
	if at.Before(row.highwater) {
		at = row.highwater
	}
	if at.Before(e.TrustedAt) {
		at = e.TrustedAt
	}
	if at.After(e.ValidUntil) {
		return AuthorizationDecision{}, AuthorizationEvidence{}, false, "EVIDENCE_EXPIRED"
	}
	return AuthorizationDecision{TrustedAt: at, Generation: uint64(row.generation)}, e, offline, ""
}

func (g *PostgresAuthorizationGate) Snapshot(ctx context.Context) (AuthorizationDecision, error) {
	tx, err := begin(ctx, g.pool)
	if err != nil {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	defer tx.Rollback(ctx)
	row, err := readGateRow(ctx, tx)
	if err != nil {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	var decision AuthorizationDecision
	var reason string
	err = g.anchor.withLocked(func(a *authorizationAnchor, exists bool) error {
		var e AuthorizationEvidence
		var offline bool
		decision, e, offline, reason = g.inspect(ctx, row, *a, exists)
		if reason != "" {
			if exists && !a.Frozen {
				a.Frozen = true
				if err := g.anchor.writeLocked(*a); err != nil {
					return err
				}
			}
			return nil
		}
		updated := *a
		updated.Highwater = decision.TrustedAt
		updated.Version = e.Version
		if !offline {
			updated.OfflineEvidence = nil
		}
		if err := g.anchor.writeLocked(updated); err != nil {
			reason = "ANCHOR_WRITE_FAILURE"
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE c_auth.authorization_gate SET trusted_high_watermark=$1,
			evidence_version=$2,evidence_issued_at=$3,evidence_valid_until=$4
			WHERE singleton_id=1`, decision.TrustedAt, int64(e.Version), e.IssuedAt, e.ValidUntil)
		return err
	})
	if err != nil {
		_ = tx.Rollback(ctx)
		fallback, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = g.persistExternalFreeze(fallback)
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	if reason != "" {
		if row.state == "OPEN" {
			if err = freezeGateRow(ctx, tx, row, reason, g.clock().UTC()); err != nil {
				return AuthorizationDecision{}, ErrAuthorizationUnavailable
			}
		}
		if err = tx.Commit(ctx); err != nil {
			return AuthorizationDecision{}, ErrAuthorizationUnavailable
		}
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	if err = tx.Commit(ctx); err != nil {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	return decision, nil
}

func freezeGateRow(ctx context.Context, tx pgx.Tx, row gateRow, reason string, at time.Time) error {
	if row.state == "FROZEN" {
		return nil
	}
	if _, err := tx.Exec(ctx, `UPDATE c_auth.authorization_gate SET gate_state='FROZEN',freeze_reason=$1,frozen_at=$2 WHERE singleton_id=1`, reason, at); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `INSERT INTO c_auth.authorization_gate_audit(event_kind,authorization_generation,evidence_version,actor,reason,operation_id,recorded_at)
		VALUES('FREEZE',$1,$2,'authorization-gate',$3,$4,$5)`, row.generation, row.version, reason, uuid.NewString(), at)
	return err
}

// RecheckForCommit locks the shared row until its caller commits or aborts.
// It intentionally does not advance the external checkpoint: ordinary
// validation errors following a read-only recheck must not force recovery.
func (g *PostgresAuthorizationGate) RecheckForCommit(ctx context.Context, tx pgx.Tx, expected uint64) (AuthorizationDecision, error) {
	row, err := readGateRow(ctx, tx)
	if err != nil {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	if expected == 0 || row.generation < 0 || uint64(row.generation) != expected {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	var decision AuthorizationDecision
	var reason string
	err = g.anchor.withLocked(func(a *authorizationAnchor, exists bool) error {
		decision, _, _, reason = g.inspect(ctx, row, *a, exists)
		if reason != "" && exists && !a.Frozen {
			a.Frozen = true
			return g.anchor.writeLocked(*a)
		}
		return nil
	})
	if err != nil || reason != "" {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	return decision, nil
}

// CommitAuthorized is the final authority point. Validation and any final
// timestamp writes run after locking the gate, then the independent checkpoint
// is durably advanced before the SQL commit. If SQL fails, the next request
// detects the ahead checkpoint and requires explicit recovery.
func (g *PostgresAuthorizationGate) CommitAuthorized(ctx context.Context, tx pgx.Tx, expected uint64, validate ...func(AuthorizationDecision) error) (AuthorizationDecision, error) {
	row, err := readGateRow(ctx, tx)
	if err != nil || expected == 0 || row.generation < 0 || uint64(row.generation) != expected {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	var decision AuthorizationDecision
	var reason string
	err = g.anchor.withLocked(func(a *authorizationAnchor, exists bool) error {
		var e AuthorizationEvidence
		var offline bool
		decision, e, offline, reason = g.inspect(ctx, row, *a, exists)
		if reason != "" {
			if exists && !a.Frozen {
				a.Frozen = true
				return g.anchor.writeLocked(*a)
			}
			return nil
		}
		for _, check := range validate {
			if check == nil {
				return errors.New("nil final authorization validation")
			}
			if err := check(decision); err != nil {
				return err
			}
		}
		updated := *a
		updated.Highwater = decision.TrustedAt
		updated.Version = e.Version
		if !offline {
			updated.OfflineEvidence = nil
		}
		if err := g.anchor.writeLocked(updated); err != nil {
			reason = "ANCHOR_WRITE_FAILURE"
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE c_auth.authorization_gate SET trusted_high_watermark=$1,
			evidence_version=$2,evidence_issued_at=$3,evidence_valid_until=$4 WHERE singleton_id=1`,
			decision.TrustedAt, int64(e.Version), e.IssuedAt, e.ValidUntil)
		return err
	})
	if err != nil {
		return AuthorizationDecision{}, err
	}
	if reason != "" {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	if err = tx.Commit(ctx); err != nil {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	return decision, nil
}

// Abort must be called after every failed authorization transaction, even
// when the request context was cancelled. It persists an external freeze in a
// separate transaction so the business rollback cannot erase it.
func (g *PostgresAuthorizationGate) Abort(_ context.Context, tx pgx.Tx) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := tx.Rollback(ctx); err != nil && !errors.Is(err, pgx.ErrTxClosed) {
		return err
	}
	return g.persistExternalFreeze(ctx)
}

func (g *PostgresAuthorizationGate) persistExternalFreeze(ctx context.Context) error {
	tx, err := begin(ctx, g.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer tx.Rollback(ctx)
	row, err := readGateRow(ctx, tx)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	var frozen bool
	err = g.anchor.withLocked(func(a *authorizationAnchor, exists bool) error {
		frozen = !exists || a.Frozen || a.Domain != g.domain ||
			a.Generation != uint64(row.generation) || a.Version != uint64(row.version) ||
			!a.Highwater.Equal(row.highwater)
		return nil
	})
	if err != nil {
		frozen = true
	}
	if !frozen {
		return tx.Commit(ctx)
	}
	if err = freezeGateRow(ctx, tx, row, "INDEPENDENT_ANCHOR_FROZEN", g.clock().UTC()); err != nil {
		return ErrAuthorizationUnavailable
	}
	return tx.Commit(ctx)
}

// Freeze is an explicit security event. Only Recover can reopen the gate.
func (g *PostgresAuthorizationGate) Freeze(ctx context.Context, reason string) error {
	if reason == "" || len(reason) > 160 {
		return errors.New("invalid freeze reason")
	}
	tx, err := begin(ctx, g.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer tx.Rollback(ctx)
	row, err := readGateRow(ctx, tx)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	if err = g.anchor.withLocked(func(a *authorizationAnchor, exists bool) error {
		if exists && !a.Frozen {
			a.Frozen = true
			return g.anchor.writeLocked(*a)
		}
		return nil
	}); err != nil {
		return ErrAuthorizationUnavailable
	}
	if err = freezeGateRow(ctx, tx, row, reason, g.clock().UTC()); err != nil {
		return ErrAuthorizationUnavailable
	}
	return tx.Commit(ctx)
}

type AuthorizationRecoveryMode string

const (
	AuthorizationRecoveryNormal     AuthorizationRecoveryMode = "NORMAL"
	AuthorizationRecoveryBreakGlass AuthorizationRecoveryMode = "BREAK_GLASS"
)

type AuthorizationRecoveryRequest struct {
	Role        string                      `json:"role"`
	Actor       string                      `json:"actor"`
	Reason      string                      `json:"reason"`
	OperationID string                      `json:"operationId"`
	Mode        AuthorizationRecoveryMode   `json:"mode"`
	Evidence    SignedAuthorizationEvidence `json:"evidence"`
	Signature   []byte                      `json:"signature"`
}

func recoveryMessage(r AuthorizationRecoveryRequest) ([]byte, error) {
	r.Signature = nil
	return json.Marshal(r)
}

func SignAuthorizationRecovery(key ed25519.PrivateKey, r AuthorizationRecoveryRequest) (AuthorizationRecoveryRequest, error) {
	if len(key) != ed25519.PrivateKeySize {
		return AuthorizationRecoveryRequest{}, errors.New("invalid recovery signer")
	}
	message, err := recoveryMessage(r)
	if err != nil {
		return AuthorizationRecoveryRequest{}, err
	}
	r.Signature = ed25519.Sign(key, message)
	return r, nil
}

// Recover requires an offline signed role command. The ordinary API instance
// has only public recovery keys. Break-glass uses a distinct pre-held key and
// a signed offline sample when the online evidence provider is unavailable.
func (g *PostgresAuthorizationGate) Recover(ctx context.Context, request AuthorizationRecoveryRequest) error {
	if request.Role != "authorization-recovery" || request.Actor == "" || request.Reason == "" ||
		request.OperationID == "" || len(request.Actor) > 128 || len(request.Reason) > 256 || len(request.OperationID) > 128 {
		return ErrAuthorizationUnavailable
	}
	key, evidenceKey := g.recoveryPublicKey, g.evidencePublicKey
	if request.Mode == AuthorizationRecoveryBreakGlass {
		key, evidenceKey = g.breakGlassPublicKey, g.breakGlassPublicKey
	} else if request.Mode != AuthorizationRecoveryNormal {
		return ErrAuthorizationUnavailable
	}
	message, err := recoveryMessage(request)
	if err != nil || !ed25519.Verify(key, message, request.Signature) {
		return ErrAuthorizationUnavailable
	}
	now := g.clock().UTC()
	e, err := g.verifyEvidence(request.Evidence, now, evidenceKey)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	if request.Mode == AuthorizationRecoveryNormal {
		current, err := g.evidence.Current(ctx)
		if err != nil || !equalSignedAuthorizationEvidence(current, request.Evidence) {
			return ErrAuthorizationUnavailable
		}
	}
	tx, err := begin(ctx, g.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer tx.Rollback(ctx)
	row, err := readGateRow(ctx, tx)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	err = g.anchor.withLocked(func(a *authorizationAnchor, exists bool) error {
		if !exists && row.generation != 0 && request.Mode != AuthorizationRecoveryBreakGlass {
			return ErrAuthorizationUnavailable
		}
		generation, version, highwater := uint64(row.generation), uint64(row.version), row.highwater
		if exists {
			if a.Domain != g.domain {
				return ErrAuthorizationUnavailable
			}
			if a.Generation > generation {
				generation = a.Generation
			}
			if a.Version > version {
				version = a.Version
			}
			if a.Highwater.After(highwater) {
				highwater = a.Highwater
			}
		}
		if e.Generation != generation+1 || e.Version <= version || e.TrustedAt.Before(highwater.Add(-authorizationSkew)) {
			return ErrAuthorizationUnavailable
		}
		if row.state == "OPEN" {
			if err := freezeGateRow(ctx, tx, row, "RECOVERY_REQUIRES_FENCE", now); err != nil {
				return err
			}
		}
		if _, err := tx.Exec(ctx, `INSERT INTO c_auth.authorization_gate_audit
			(event_kind,authorization_generation,evidence_version,actor,reason,operation_id,mode,recorded_at)
			VALUES('RECOVER',$1,$2,$3,$4,$5,$6,$7)`, int64(e.Generation), int64(e.Version), request.Actor,
			request.Reason, request.OperationID, string(request.Mode), now); err != nil {
			return err
		}
		newHighwater := now
		if e.TrustedAt.After(newHighwater) {
			newHighwater = e.TrustedAt
		}
		if highwater.After(newHighwater) {
			newHighwater = highwater
		}
		updated := authorizationAnchor{Domain: g.domain, Generation: e.Generation, Version: e.Version, Highwater: newHighwater}
		if request.Mode == AuthorizationRecoveryBreakGlass {
			proof := request.Evidence
			updated.OfflineEvidence = &proof
		}
		if err := g.anchor.writeLocked(updated); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE c_auth.authorization_gate SET gate_state='OPEN',authorization_generation=$1,
			trusted_high_watermark=$2,evidence_version=$3,evidence_issued_at=$4,evidence_valid_until=$5,
			freeze_reason=NULL,opened_at=$6 WHERE singleton_id=1`, int64(e.Generation), newHighwater,
			int64(e.Version), e.IssuedAt, e.ValidUntil, now)
		return err
	})
	if err != nil {
		return fmt.Errorf("recovery rejected: %w", ErrAuthorizationUnavailable)
	}
	if err = tx.Commit(ctx); err != nil {
		return ErrAuthorizationUnavailable
	}
	return nil
}
