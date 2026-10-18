package authprivacy

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
)

func legacyRestrictionApply(t *testing.T, c *Community, owner *pgxpool.Pool, account uuid.UUID, action string, end *time.Time) error {
	t.Helper()
	var version int64
	if err := owner.QueryRow(context.Background(), `SELECT version FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&version); err != nil {
		t.Fatal(err)
	}
	if action == "BAN" {
		return c.ApplyAccountBan(context.Background(), account, version, end)
	}
	return c.ApplyAccountMute(context.Background(), account, version, end)
}

func legacyRestrictionRead(t *testing.T, owner *pgxpool.Pool, account uuid.UUID, action string) (*time.Time, int64) {
	t.Helper()
	var state string
	var end *time.Time
	var version int64
	if err := owner.QueryRow(context.Background(), `SELECT CASE WHEN $2='BAN' THEN ban_state ELSE mute_state END,CASE WHEN $2='BAN' THEN ban_ends_at ELSE mute_ends_at END,version FROM c_auth.account_restrictions WHERE account_id=$1`, account, action).Scan(&state, &end, &version); err != nil {
		t.Fatal(err)
	}
	if state != map[string]string{"BAN": "BANNED", "MUTE": "MUTED"}[action] {
		t.Fatalf("independent legacy restriction was cleared: %s", state)
	}
	return end, version
}

func legacyRestrictionEndEqual(a, b *time.Time) bool {
	return a == nil && b == nil || a != nil && b != nil && a.Equal(*b)
}

func legacyRestrictionRuntime(t *testing.T, l *lab) *Community {
	t.Helper()
	var hadTracker bool
	if err := l.cp.QueryRow(context.Background(), `SELECT to_regclass('public.goose_db_version') IS NOT NULL`).Scan(&hadTracker); err != nil {
		t.Fatal(err)
	}
	pool := moderationLifecycleRuntime(t, l)
	if !hadTracker {
		t.Cleanup(func() { mustExec(t, l.cp, `DROP TABLE IF EXISTS public.goose_db_version`) })
	}
	gate := *l.gate
	gate.pool = pool
	c := *l.c
	c.pool, c.gate, c.moderationEnabled = pool, &gate, false
	if err := CheckModerationLegacyRestrictionSchema(context.Background(), pool); err != nil {
		t.Fatal("minimal disabled-feature legacy grants rejected", err)
	}
	return &c
}

func TestModerationLegacyRestrictionInteroperabilityPostgres(t *testing.T) {
	for _, test := range []struct {
		name, action                                string
		legacyFirst, permanent, newForever, runtime bool
	}{
		{name: "old_mute_7_new_1", action: "MUTE", legacyFirst: true},
		{name: "new_mute_7_old_1", action: "MUTE"},
		{name: "old_ban_7_new_1", action: "BAN", legacyFirst: true},
		{name: "new_ban_7_old_1", action: "BAN"},
		{name: "old_permanent_mute", action: "MUTE", legacyFirst: true, permanent: true},
		{name: "old_permanent_ban", action: "BAN", legacyFirst: true, permanent: true},
		{name: "new_permanent_ban", action: "BAN", newForever: true},
		{name: "runtime_old_mute_7_new_1", action: "MUTE", legacyFirst: true, runtime: true},
		{name: "runtime_new_ban_7_old_1", action: "BAN", runtime: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			l := moderationLab(t)
			ctx := context.Background()
			f := moderationPost(t, l, "mod_legacy_owner")
			r := moderationActor(t, l, "mod_legacy_reporter", "")
			a := moderationActor(t, l, "mod_legacy_actor", "ADMIN")
			b := moderationActor(t, l, "mod_legacy_other", "ADMIN")
			_, report := moderationReport(t, l, r, nil, f.post, "OTHER")
			legacy := l.c
			if test.runtime {
				legacy = legacyRestrictionRuntime(t, l)
				grant, err := os.ReadFile("../../../../infra/postgres/grant-moderation.sql")
				if err != nil {
					t.Fatal(err)
				}
				mustExec(t, l.cp, string(grant))
				l.c, err = legacy.WithModeration(ctx)
				if err != nil {
					t.Fatal(err)
				}
			}
			d, err := l.gate.Snapshot(ctx)
			if err != nil {
				t.Fatal(err)
			}
			legacyDays, newDays := 1, 7
			if test.legacyFirst {
				legacyDays, newDays = 7, 1
			}
			at := d.TrustedAt.Add(time.Duration(legacyDays) * 24 * time.Hour)
			var legacyEnd *time.Time = &at
			if test.permanent {
				legacyEnd = nil
			}
			if test.newForever {
				newDays = 0
			}
			if test.legacyFirst {
				if err = legacyRestrictionApply(t, legacy, l.cp, f.account, test.action, legacyEnd); err != nil {
					t.Fatal(err)
				}
			}
			decision := moderationDecision(t, l, a, report.CaseID, test.action, newDays)
			sanction := decision.Sanctions[0]
			if !test.legacyFirst {
				if err = legacyRestrictionApply(t, legacy, l.cp, f.account, test.action, legacyEnd); err != nil {
					t.Fatal(err)
				}
			}
			var expected *time.Time
			if legacyEnd != nil && sanction.EndsAt != nil {
				expected = legacyEnd
				if sanction.EndsAt.After(*expected) {
					expected = sanction.EndsAt
				}
			}
			actual, version := legacyRestrictionRead(t, l.cp, f.account, test.action)
			if !legacyRestrictionEndEqual(actual, expected) {
				t.Fatal("legacy/new overlap shortened or concatenated the effective restriction")
			}
			// An invalid old end must fail before a longer/new permanent fact
			// can hide it, without changing either projection or legacy row.
			past := d.TrustedAt.Add(-time.Hour)
			if err = legacyRestrictionApply(t, legacy, l.cp, f.account, test.action, &past); !errors.Is(err, ErrIntentInvalid) {
				t.Fatal("past legacy end was hidden by the aggregate", err)
			}
			unchanged, nextVersion := legacyRestrictionRead(t, l.cp, f.account, test.action)
			if nextVersion != version || !legacyRestrictionEndEqual(unchanged, actual) {
				t.Fatal("rejected legacy request changed the restriction")
			}
			var stored *time.Time
			if err = l.cp.QueryRow(ctx, `SELECT CASE WHEN $2='BAN' THEN ban_ends_at ELSE mute_ends_at END FROM c_moderation.legacy_restrictions WHERE account_id=$1`, f.account, test.action).Scan(&stored); err != nil || !legacyRestrictionEndEqual(stored, legacyEnd) {
				t.Fatal("new projection or rejected command rewrote the independent legacy baseline", err)
			}
			if _, err = l.c.ExecuteModeration(ctx, b.SessionToken, "revoke", sanction.ID, moderation.Decision{CommandID: uuid.NewString(), Reason: "只撤销新案件处罚"}); err != nil {
				t.Fatal(err)
			}
			actual, _ = legacyRestrictionRead(t, l.cp, f.account, test.action)
			if !legacyRestrictionEndEqual(actual, legacyEnd) {
				t.Fatal("new sanction reversal changed the independent legacy baseline")
			}
		})
	}
}

func TestModerationLegacyRestrictionMinimalPrivilegesPostgres(t *testing.T) {
	l := moderationLab(t)
	f := moderationPost(t, l, "mod_legacy_grants")
	legacy := legacyRestrictionRuntime(t, l)
	ctx := context.Background()
	// This is a newly registered post-upgrade account: runtime needs a real
	// column-only INSERT, followed by ON CONFLICT UPDATE on the same baseline.
	d, err := l.gate.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	end := d.TrustedAt.Add(7 * 24 * time.Hour)
	for _, action := range []string{"MUTE", "BAN"} {
		if err = legacyRestrictionApply(t, legacy, l.cp, f.account, action, &end); err != nil {
			t.Fatal("minimal runtime could not insert/update the legacy baseline", err)
		}
	}
	mustExec(t, l.cp, `REVOKE SELECT(action) ON c_moderation.sanctions FROM hnuhole_c_runtime`)
	if err = CheckModerationLegacyRestrictionSchema(ctx, legacy.pool); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("missing aggregation read privilege passed startup", err)
	}
	mustExec(t, l.cp, `GRANT SELECT(action) ON c_moderation.sanctions TO hnuhole_c_runtime`)
	grant, err := os.ReadFile("../../../../infra/postgres/grant-moderation.sql")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, string(grant))
	for _, access := range []struct{ change, restore string }{
		{`REVOKE INSERT(mute_ends_at) ON c_moderation.legacy_restrictions FROM hnuhole_c_runtime`, `GRANT INSERT(mute_ends_at) ON c_moderation.legacy_restrictions TO hnuhole_c_runtime`},
		{`REVOKE UPDATE(ban_ends_at) ON c_moderation.legacy_restrictions FROM hnuhole_c_runtime`, `GRANT UPDATE(ban_ends_at) ON c_moderation.legacy_restrictions TO hnuhole_c_runtime`},
		{`GRANT UPDATE(account_id) ON c_moderation.legacy_restrictions TO hnuhole_c_runtime`, `REVOKE UPDATE(account_id) ON c_moderation.legacy_restrictions FROM hnuhole_c_runtime`},
		{`GRANT INSERT ON c_moderation.legacy_restrictions TO hnuhole_c_runtime`, `REVOKE INSERT ON c_moderation.legacy_restrictions FROM hnuhole_c_runtime`},
		{`GRANT DELETE ON c_moderation.legacy_restrictions TO hnuhole_c_runtime`, `REVOKE DELETE ON c_moderation.legacy_restrictions FROM hnuhole_c_runtime`},
	} {
		mustExec(t, l.cp, access.change)
		if err = CheckModerationLegacyRestrictionSchema(ctx, legacy.pool); !errors.Is(err, ErrAuthorizationUnavailable) {
			t.Fatalf("legacy checker accepted unsafe grant: %s: %v", access.change, err)
		}
		if _, err = legacy.WithModeration(ctx); !errors.Is(err, ErrAuthorizationUnavailable) {
			t.Fatalf("enabled moderation accepted unsafe legacy grant: %s: %v", access.change, err)
		}
		mustExec(t, l.cp, access.restore)
		mustExec(t, l.cp, string(grant))
		if _, err = legacy.WithModeration(ctx); err != nil {
			t.Fatal("exact legacy privileges did not recover", err)
		}
	}
}

func TestModerationLegacyRestrictionBefore0015Postgres(t *testing.T) {
	l := newPostLab(t)
	mustExec(t, l.cp, `DROP SCHEMA c_moderation CASCADE`)
	mustExec(t, l.cp, `ALTER TABLE c_posts.posts DROP COLUMN moderation_hidden`)
	mustExec(t, l.cp, `ALTER TABLE public.community_identities DROP COLUMN moderation_rename_required`)
	if err := CheckModerationLegacyRestrictionSchema(context.Background(), l.cp); err != nil {
		t.Fatal("0014 gained a moderation dependency", err)
	}
	owner := sessionTestAccount(t, l, "mod_legacy_0014")
	d, err := l.gate.Snapshot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, days := range []int{7, 1} {
		end := d.TrustedAt.Add(time.Duration(days) * 24 * time.Hour)
		if err = legacyRestrictionApply(t, l.c, l.cp, owner.AccountID, "MUTE", &end); err != nil {
			t.Fatal(err)
		}
		actual, _ := legacyRestrictionRead(t, l.cp, owner.AccountID, "MUTE")
		if !legacyRestrictionEndEqual(actual, &end) {
			t.Fatal("0014 trusted replacement semantics changed")
		}
	}
}
