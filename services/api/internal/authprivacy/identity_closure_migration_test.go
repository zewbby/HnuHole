package authprivacy

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// Reconstruct only the old version-11 constraint inside the protected reset
// fixture. This never runs against an externally supplied production database.
func identityClosureVersion11(t *testing.T, l *lab) {
	t.Helper()
	source, err := os.ReadFile("../../migrations/0011_identity_management.sql")
	if err != nil {
		t.Fatal(err)
	}
	text := string(source)
	start := strings.Index(text, "CREATE FUNCTION public.check_identity_account_shape()")
	if start < 0 {
		t.Fatal("version-11 identity shape function absent")
	}
	end := strings.Index(text[start:], "$$;")
	if end < 0 {
		t.Fatal("version-11 identity shape function incomplete")
	}
	function := strings.Replace(text[start:start+end+3], "CREATE FUNCTION", "CREATE OR REPLACE FUNCTION", 1)
	mustExec(t, l.cp, `DROP TRIGGER identity_account_shape_from_account ON c_auth.accounts`)
	mustExec(t, l.cp, function)
}

func identityClosureMigration(t *testing.T, l *lab) error {
	t.Helper()
	source, err := os.ReadFile("../../migrations/0012_identity_account_closure.sql")
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	tx, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, strings.SplitN(string(source), "-- +goose Down", 2)[0]); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func identityClosureLegacyRows(t *testing.T, l *lab, created time.Time) {
	t.Helper()
	ctx := context.Background()
	tx, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	for _, statement := range []string{
		`INSERT INTO c_auth.accounts(account_id,platform_number,state) VALUES('00000000-0000-4000-8000-000000000012','900012','CLOSED')`,
		`INSERT INTO public.identity_account_state(account_id,created_count,last_created_at) VALUES('00000000-0000-4000-8000-000000000012',2,$1)`,
		`INSERT INTO public.community_identities(identity_id,account_id,nickname,avatar,is_original,created_at,last_renamed_at) VALUES('00000000-0000-4000-8000-000000001201','00000000-0000-4000-8000-000000000012','旧昵称','default-v1',true,$1,$1)`,
		`INSERT INTO public.community_identities(identity_id,account_id,is_original,created_at,deleted_at) VALUES('00000000-0000-4000-8000-000000001202','00000000-0000-4000-8000-000000000012',false,$1,$1)`,
		`INSERT INTO public.identity_change_receipts(account_id,change_key_digest,intent_fingerprint,state,operation,identity_id,committed_at) VALUES('00000000-0000-4000-8000-000000000012',decode(repeat('ac',32),'hex'),decode(repeat('cd',32),'hex'),'COMMITTED','CREATE','00000000-0000-4000-8000-000000001201',$1)`,
	} {
		if strings.Contains(statement, "$1") {
			_, err = tx.Exec(ctx, statement, created)
		} else {
			_, err = tx.Exec(ctx, statement)
		}
		if err != nil {
			t.Fatal(err)
		}
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
}

func identityClosurePreservedHistory(t *testing.T, l *lab) string {
	t.Helper()
	var result string
	err := l.cp.QueryRow(context.Background(), `SELECT jsonb_build_object(
 'counter',(SELECT to_jsonb(s) FROM public.identity_account_state s WHERE account_id='00000000-0000-4000-8000-000000000012'),
 'oldDeleted',(SELECT to_jsonb(i) FROM public.community_identities i WHERE identity_id='00000000-0000-4000-8000-000000001202'),
 'receipt',(SELECT to_jsonb(r) FROM public.identity_change_receipts r WHERE account_id='00000000-0000-4000-8000-000000000012'))::text`).Scan(&result)
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func TestIdentityClosureMigrationRepairsLegacyProfilesPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	identityClosureVersion11(t, l)
	identityClosureLegacyRows(t, l, control.clock.now().Add(-time.Hour))
	before := identityClosurePreservedHistory(t, l)
	var watermark time.Time
	if err := l.cp.QueryRow(context.Background(), `SELECT trusted_high_watermark FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&watermark); err != nil {
		t.Fatal(err)
	}
	if err := identityClosureMigration(t, l); err != nil {
		t.Fatal(err)
	}
	if before != identityClosurePreservedHistory(t, l) {
		t.Fatal("upgrade rewrote permanent identity history")
	}
	if count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE identity_id='00000000-0000-4000-8000-000000001201' AND nickname IS NULL AND avatar IS NULL AND last_renamed_at IS NULL AND deleted_at=$1`, watermark) != 1 {
		t.Fatal("legacy closed profile was not erased at the persisted trusted repair marker")
	}
}

func TestIdentityClosureMigrationRejectsInsufficientTrustedWatermarkPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	identityClosureVersion11(t, l)
	identityClosureLegacyRows(t, l, control.clock.now().Add(time.Hour))
	before := identityClosurePreservedHistory(t, l)
	err := identityClosureMigration(t, l)
	var postgresError *pgconn.PgError
	if !errors.As(err, &postgresError) || postgresError.Code != "23514" {
		t.Fatalf("insufficient watermark did not reject atomic upgrade: %v", err)
	}
	if before != identityClosurePreservedHistory(t, l) || count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE identity_id='00000000-0000-4000-8000-000000001201' AND nickname='旧昵称' AND deleted_at IS NULL`) != 1 {
		t.Fatal("failed upgrade partially rewrote legacy profiles/history")
	}
	if count(t, l.cp, `SELECT count(*) FROM pg_trigger WHERE tgrelid='c_auth.accounts'::regclass AND tgname='identity_account_shape_from_account'`) != 0 {
		t.Fatal("failed upgrade leaked its new constraint")
	}
}

func TestIdentityClosureConstraintRejectsUnsupportedIsolationPostgres(t *testing.T) {
	l := newLab(t)
	owner := sessionTestAccount(t, l, "identity_close_isolation")
	first := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "首身份")
	identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "次身份")
	for _, isolation := range []pgx.TxIsoLevel{pgx.RepeatableRead, pgx.Serializable} {
		t.Run(string(isolation), func(t *testing.T) {
			ctx := context.Background()
			tx, err := l.cp.BeginTx(ctx, pgx.TxOptions{IsoLevel: isolation})
			if err != nil {
				t.Fatal(err)
			}
			defer tx.Rollback(ctx)
			_, err = tx.Exec(ctx, `UPDATE public.community_identities SET nickname=NULL,avatar=NULL,last_renamed_at=NULL,deleted_at=created_at WHERE identity_id=$1`, first.IdentityID)
			if err != nil {
				t.Fatal(err)
			}
			err = tx.Commit(ctx)
			var postgresError *pgconn.PgError
			if !errors.As(err, &postgresError) || postgresError.Code != "23514" {
				t.Fatalf("unsupported identity DML isolation committed: %v", err)
			}
		})
	}
	if count(t, l.cp, `SELECT count(*) FROM public.community_identities WHERE account_id=$1 AND deleted_at IS NULL`, owner.AccountID) != 2 {
		t.Fatal("unsupported isolation changed an identity")
	}
}
