package authprivacyhttp

import (
	"context"
	"crypto/sha256"
	"errors"
	"reflect"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

// Private R05 assertions inspect SQL; no profile, receipt or account snapshot
// is exposed by a shipped endpoint or returned by the fixture control API.
type mobileClosureProfile struct {
	ID               uuid.UUID
	Nickname, Avatar *string
	Original         bool
	Created          time.Time
	Renamed, Deleted *time.Time
}

type mobileClosureSnapshot struct {
	Account           uuid.UUID
	Counter, Receipts string
	Profiles          []mobileClosureProfile
}

func readMobileClosure(ctx context.Context, pool *pgxpool.Pool, account uuid.UUID) (mobileClosureSnapshot, error) {
	s := mobileClosureSnapshot{Account: account}
	err := pool.QueryRow(ctx, `SELECT COALESCE((SELECT to_jsonb(s)::text FROM public.identity_account_state s WHERE account_id=$1),'null'),COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY change_key_digest)::text FROM public.identity_change_receipts r WHERE account_id=$1),'[]')`, account).Scan(&s.Counter, &s.Receipts)
	if err != nil {
		return s, errors.New("cannot read mobile closure permanence")
	}
	rows, err := pool.Query(ctx, `SELECT identity_id,nickname,avatar,is_original,created_at,last_renamed_at,deleted_at FROM public.community_identities WHERE account_id=$1 ORDER BY identity_id`, account)
	if err != nil {
		return s, errors.New("cannot read mobile closure profiles")
	}
	defer rows.Close()
	for rows.Next() {
		var p mobileClosureProfile
		if err = rows.Scan(&p.ID, &p.Nickname, &p.Avatar, &p.Original, &p.Created, &p.Renamed, &p.Deleted); err != nil {
			return s, errors.New("invalid mobile closure profile")
		}
		s.Profiles = append(s.Profiles, p)
	}
	if rows.Err() != nil {
		return s, errors.New("cannot finish mobile closure profiles")
	}
	return s, nil
}

func captureMobileClosure(ctx context.Context, pool *pgxpool.Pool, token string) (mobileClosureSnapshot, error) {
	var s mobileClosureSnapshot
	raw, err := protocol.DecodeCanonicalBase64url(token, 32)
	if err != nil {
		return s, errors.New("invalid mobile closure token")
	}
	digest := sha256.Sum256(raw)
	var account uuid.UUID
	if pool.QueryRow(ctx, `SELECT account_id FROM c_auth.sessions WHERE token_digest=$1 AND revoked_at IS NULL`, digest[:]).Scan(&account) != nil {
		return s, errors.New("mobile closure session absent")
	}
	s, err = readMobileClosure(ctx, pool, account)
	if err != nil {
		return s, err
	}
	active, deleted := 0, 0
	for _, p := range s.Profiles {
		if p.Deleted == nil {
			active++
		} else {
			deleted++
		}
	}
	if active != 2 || deleted != 1 || s.Counter == "null" || s.Receipts == "[]" {
		return s, errors.New("mobile closure fixture lacks active/deleted identities or permanent history")
	}
	return s, nil
}

func (s mobileClosureSnapshot) unchanged(ctx context.Context, pool *pgxpool.Pool, want string) error {
	if s.Account == uuid.Nil || (want != "ACTIVE" && want != "PENDING_CLOSE") {
		return errors.New("invalid mobile closure checkpoint")
	}
	var state string
	if pool.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1`, s.Account).Scan(&state) != nil || state != want {
		return errors.New("mobile closure account state differs")
	}
	after, err := readMobileClosure(ctx, pool, s.Account)
	if err != nil {
		return err
	}
	if !reflect.DeepEqual(s, after) {
		return errors.New("pending/cancelled mobile closure changed identity history")
	}
	return nil
}

func (s mobileClosureSnapshot) finalized(ctx context.Context, pool *pgxpool.Pool, closure string) error {
	if s.Account == uuid.Nil {
		return errors.New("mobile closure snapshot absent")
	}
	raw, err := protocol.DecodeCanonicalBase64url(closure, 32)
	if err != nil {
		return errors.New("invalid mobile closure ID")
	}
	var state string
	if pool.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1`, s.Account).Scan(&state) != nil || state != "CLOSED" {
		return errors.New("mobile closed account absent")
	}
	var terminal time.Time
	if pool.QueryRow(ctx, `SELECT terminal_at FROM c_auth.closure_requests WHERE closure_id=$1 AND state='CLOSED_RELEASE_PENDING'`, raw).Scan(&terminal) != nil {
		return errors.New("mobile formal closure absent")
	}
	after, err := readMobileClosure(ctx, pool, s.Account)
	if err != nil {
		return err
	}
	if s.Counter != after.Counter || s.Receipts != after.Receipts || len(s.Profiles) != len(after.Profiles) {
		return errors.New("mobile closure changed permanent counters/receipts")
	}
	for i, before := range s.Profiles {
		p := after.Profiles[i]
		if before.ID != p.ID || before.Original != p.Original || !before.Created.Equal(p.Created) {
			return errors.New("mobile closure changed identity origin")
		}
		if before.Deleted != nil {
			if !reflect.DeepEqual(before, p) {
				return errors.New("mobile closure rewrote prior tombstone")
			}
		} else if p.Deleted == nil || !p.Deleted.Equal(terminal) || p.Nickname != nil || p.Avatar != nil || p.Renamed != nil {
			return errors.New("mobile closure did not erase active profile atomically")
		}
	}
	return nil
}

func (s mobileClosureSnapshot) newAccount(ctx context.Context, pool *pgxpool.Pool, text, closure string) error {
	account, err := uuid.Parse(text)
	if err != nil || account == s.Account || s.Account == uuid.Nil {
		return errors.New("mobile return did not create independent account")
	}
	after, err := readMobileClosure(ctx, pool, account)
	if err != nil {
		return err
	}
	var count int
	if pool.QueryRow(ctx, `SELECT created_count FROM public.identity_account_state WHERE account_id=$1`, account).Scan(&count) != nil || count != 1 || len(after.Profiles) != 1 || !after.Profiles[0].Original || after.Profiles[0].Deleted != nil {
		return errors.New("mobile return inherited identity quota/history")
	}
	for _, old := range s.Profiles {
		if after.Profiles[0].ID == old.ID {
			return errors.New("mobile return reused old identity")
		}
	}
	return s.finalized(ctx, pool, closure)
}
