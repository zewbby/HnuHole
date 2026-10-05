#!/bin/sh
# Actual C/V cmd processes, formal Goose migrations, separate non-owner runtime
# credentials and real Mailpit. Requires existing tools AND cached images/modules.
set -eu
umask 077
for runtime_tool in go goose docker psql pg_dump python3 curl cmp; do
 command -v "$runtime_tool" >/dev/null 2>&1 || { echo "Missing tool: $runtime_tool" >&2; exit 1; }
done
# Do not silently download an image, Go toolchain, dependency or Goose.
docker image inspect postgres:16.6-alpine >/dev/null 2>&1 || { echo 'Required cached image postgres:16.6-alpine absent' >&2; exit 1; }
docker image inspect axllent/mailpit:v1.21.8 >/dev/null 2>&1 || { echo 'Required cached image axllent/mailpit:v1.21.8 absent' >&2; exit 1; }
goose -version 2>&1 | python3 -c 'import sys; assert "v3.22.1" in sys.stdin.read(), "Goose v3.22.1 is required"'
runtime_api_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_repo_dir=$(CDPATH= cd -- "$runtime_api_dir/../.." && pwd)
runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-runtime.XXXXXX")
case "$runtime_dir" in *[!A-Za-z0-9_./-]*) echo 'Unsupported temporary path' >&2; exit 1 ;; esac
chmod 700 "$runtime_dir"
runtime_project="hnuhole-runtime-$(basename "$runtime_dir" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
runtime_compose="$runtime_repo_dir/infra/docker-compose.yml"
runtime_c_pid=;runtime_v_pid=;runtime_evidence_pid=;runtime_v_evidence_pid=
runtime_cleanup() {
 runtime_status=$?
 trap - EXIT INT TERM HUP
 for runtime_pid in "$runtime_evidence_pid" "$runtime_v_evidence_pid" "$runtime_c_pid" "$runtime_v_pid"; do
  if [ -n "$runtime_pid" ]; then kill "$runtime_pid" 2>/dev/null || true; wait "$runtime_pid" 2>/dev/null || true; fi
 done
 if [ "$runtime_status" -ne 0 ]; then
  docker compose -p "$runtime_project" -f "$runtime_compose" logs --no-color --tail 25 >"$runtime_dir/docker-failure.log" 2>/dev/null || true
  python3 - "$runtime_dir/docker-failure.log" <<'PY'
import os,pathlib,sys
path=pathlib.Path(sys.argv[1])
text=path.read_text(errors='replace')
for name in ('c.log','v.log'):
 service_log=path.parent/name
 if service_log.is_file(): text += '\n'+service_log.read_text(errors='replace')[-4096:]
for key in ('C_ADMIN_PASSWORD','C_MIGRATOR_PASSWORD','C_RUNTIME_PASSWORD','C_RECOVERY_PASSWORD','V_ADMIN_PASSWORD','V_MIGRATOR_PASSWORD','V_RUNTIME_PASSWORD','V_RECOVERY_PASSWORD'):
 value=os.environ.get(key)
 if value: text=text.replace(value,'[REDACTED]')
for line in text.splitlines():
 if any(term in line.lower() for term in ('error','fatal','denied','init-auth','not found','unbound','syntax','failed','absent','rejected')):
  print(line,file=sys.stderr)
PY
 fi
 # This project name was uniquely allocated by THIS invocation only.
 docker compose -p "$runtime_project" -f "$runtime_compose" down -v --remove-orphans >/dev/null 2>&1 || true
 rm -rf "$runtime_dir"
 exit "$runtime_status"
}
trap runtime_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
runtime_ports=$(python3 - <<'PY'
import socket
sockets=[]
try:
 for _ in range(8):
  sock=socket.socket();sock.bind(('127.0.0.1',0));sockets.append(sock)
 print(' '.join(str(sock.getsockname()[1]) for sock in sockets))
finally:
 for sock in sockets:sock.close()
PY
)
set -- $runtime_ports
C_DATABASE_PORT=$1;V_DATABASE_PORT=$2;MAILPIT_SMTP_PORT=$3;MAILPIT_HTTP_PORT=$4
runtime_c_port=$5;runtime_v_port=$6;runtime_ci_port=$7;runtime_vi_port=$8
export C_DATABASE_PORT V_DATABASE_PORT MAILPIT_SMTP_PORT MAILPIT_HTTP_PORT
AUTHRUNTIME_ISOLATED=1
AUTHRUNTIME_TAG="hnuhole_runtime_$(basename "$runtime_dir" | tr -cd 'a-zA-Z0-9')"
AUTHRUNTIME_C_DSN="postgres://hnuhole_c_runtime@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable&application_name=$AUTHRUNTIME_TAG"
runtime_v_dsn="postgres://hnuhole_v_runtime@127.0.0.1:$V_DATABASE_PORT/hnuhole_v?sslmode=disable&application_name=$AUTHRUNTIME_TAG"
export AUTHRUNTIME_ISOLATED AUTHRUNTIME_TAG AUTHRUNTIME_C_DSN
cd "$runtime_api_dir"
GOTOOLCHAIN=local GOPROXY=off go build -o "$runtime_dir/authdev" ./cmd/authdev
GOTOOLCHAIN=local GOPROXY=off go build -o "$runtime_dir/community" ./cmd/api
GOTOOLCHAIN=local GOPROXY=off go build -o "$runtime_dir/verifier" ./cmd/verifier
GOTOOLCHAIN=local GOPROXY=off go build -o "$runtime_dir/probe" ./cmd/runtimeprobe
"$runtime_dir/authdev" init -dir "$runtime_dir/material" \
 -community-port "$runtime_c_port" -verifier-port "$runtime_v_port" \
 -community-internal-port "$runtime_ci_port" -verifier-internal-port "$runtime_vi_port" \
 -smtp-port "$MAILPIT_SMTP_PORT" -community-dsn "$AUTHRUNTIME_C_DSN" -verifier-dsn "$runtime_v_dsn" \
 -recovery-dsn "postgres://hnuhole_c_recovery@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable" \
 -verifier-recovery-dsn "postgres://hnuhole_v_recovery@127.0.0.1:$V_DATABASE_PORT/hnuhole_v?sslmode=disable"
runtime_material="$runtime_dir/material"
C_ADMIN_PASSWORD=$(cat "$runtime_material/operator/db-c-admin.password")
C_MIGRATOR_PASSWORD=$(cat "$runtime_material/operator/db-c-migrator.password")
C_RUNTIME_PASSWORD=$(cat "$runtime_material/db-c-runtime.password")
C_RECOVERY_PASSWORD=$(cat "$runtime_material/operator/db-c-recovery.password")
V_ADMIN_PASSWORD=$(cat "$runtime_material/operator/db-v-admin.password")
V_MIGRATOR_PASSWORD=$(cat "$runtime_material/operator/db-v-migrator.password")
V_RUNTIME_PASSWORD=$(cat "$runtime_material/db-v-runtime.password")
V_RECOVERY_PASSWORD=$(cat "$runtime_material/operator/db-v-recovery.password")
export C_ADMIN_PASSWORD C_MIGRATOR_PASSWORD C_RUNTIME_PASSWORD C_RECOVERY_PASSWORD V_ADMIN_PASSWORD V_MIGRATOR_PASSWORD V_RUNTIME_PASSWORD V_RECOVERY_PASSWORD
docker compose -p "$runtime_project" -f "$runtime_compose" up -d --pull never --wait >/dev/null
if "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/schema-negative.log" 2>&1; then echo 'Missing schema startup unexpectedly accepted' >&2; exit 1; fi
runtime_c_migrator="postgres://hnuhole_c_migrator@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable&options=-c%20role%3Dhnuhole_c_owner"
runtime_v_migrator="postgres://hnuhole_v_migrator@127.0.0.1:$V_DATABASE_PORT/hnuhole_v?sslmode=disable&options=-c%20role%3Dhnuhole_v_owner"
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_c_migrator" up-to 10 >/dev/null
# Apply the existing grants except the three not-yet-created B02 tables so the
# startup negative actually exercises version 10, rather than absent grants.
python3 - "$runtime_repo_dir/infra/postgres/grant-community.sql" "$runtime_dir/grant-pre-identity.sql" <<'PY'
import pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text('\n'.join(line for line in source.splitlines()
 if not any(table in line for table in ('public.identity_account_state','public.community_identities','public.identity_change_receipts')))+'\n')
PY
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -f "$runtime_dir/grant-pre-identity.sql" >/dev/null
if "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/identity-version-negative.log" 2>&1; then echo 'Pre-identity schema startup unexpectedly accepted' >&2; exit 1; fi
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_c_migrator" up-to 11 >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -f "$runtime_repo_dir/infra/postgres/grant-community.sql" >/dev/null
if "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/identity-close-version-negative.log" 2>&1; then echo 'Pre-account-closure schema startup unexpectedly accepted' >&2; exit 1; fi
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_c_migrator" up >/dev/null
# V version 3 existed without an independent Gate. Apply only its historical
# grants so the negative proves the actual 3 -> 4 startup requirement.
PGPASSWORD=$V_MIGRATOR_PASSWORD goose -dir verifier-migrations postgres "$runtime_v_migrator" up-to 3 >/dev/null
python3 - "$runtime_repo_dir/infra/postgres/grant-verifier.sql" "$runtime_dir/grant-pre-v-gate.sql" <<'PY'
import pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(';\n'.join(statement for statement in source.split(';')
 if not any(term in statement for term in ('authorization_gate','hnuhole_v_recovery')))+';\n')
PY
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -f "$runtime_dir/grant-pre-v-gate.sql" >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" >/dev/null <<'SQL'
BEGIN;
INSERT INTO v_auth.used_slots(slot_id) VALUES(decode(repeat('ab',32),'hex'));
INSERT INTO v_auth.email_quota(email_exact,current_slot,bootstrap_public_key)
VALUES(convert_to('runtime-upgrade@hainanu.edu.cn','UTF8'),decode(repeat('ab',32),'hex'),decode(repeat('cd',32),'hex'));
COMMIT;
SQL
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -c '\copy (SELECT * FROM v_auth.email_quota ORDER BY email_exact) TO STDOUT CSV' >"$runtime_dir/v-quota-before.csv"
if "$runtime_dir/verifier" -config "$runtime_material/v.json" >"$runtime_dir/v-gate-version-negative.log" 2>&1; then echo 'V pre-Gate schema startup unexpectedly accepted' >&2; exit 1; fi
PGPASSWORD=$V_MIGRATOR_PASSWORD goose -dir verifier-migrations postgres "$runtime_v_migrator" up >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -c '\copy (SELECT * FROM v_auth.email_quota ORDER BY email_exact) TO STDOUT CSV' >"$runtime_dir/v-quota-after.csv"
cmp "$runtime_dir/v-quota-before.csv" "$runtime_dir/v-quota-after.csv"
# Second invocation must be a no-op, preserving seed identities.
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_c_migrator" up >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD goose -dir verifier-migrations postgres "$runtime_v_migrator" up >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -f "$runtime_repo_dir/infra/postgres/grant-community.sql" >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -f "$runtime_repo_dir/infra/postgres/grant-verifier.sql" >/dev/null
# AC03: audit actual runtime/recovery/business roles in each private cluster.
for runtime_privacy_party in c v; do
 if [ "$runtime_privacy_party" = c ]; then runtime_privacy_service=community-postgres; runtime_privacy_binary=community; else runtime_privacy_service=verifier-postgres; runtime_privacy_binary=verifier; fi
 docker compose -p "$runtime_project" -f "$runtime_compose" exec -T "$runtime_privacy_service" psql -X -v ON_ERROR_STOP=1 -v party="$runtime_privacy_party" -U "hnuhole_${runtime_privacy_party}_admin" -d "hnuhole_$runtime_privacy_party" < "$runtime_api_dir/authlab/privacy-role-audit.sql" >/dev/null
 # A role override changes the effective pool settings despite the fixed
 # server command line. Ordinary API startup must reject it, not repair it.
 docker compose -p "$runtime_project" -f "$runtime_compose" exec -T "$runtime_privacy_service" psql -X -v ON_ERROR_STOP=1 -U "hnuhole_${runtime_privacy_party}_admin" -d "hnuhole_$runtime_privacy_party" -c "ALTER ROLE hnuhole_${runtime_privacy_party}_runtime SET log_duration=on" >/dev/null
 if "$runtime_dir/$runtime_privacy_binary" -config "$runtime_material/$runtime_privacy_party.json" >"$runtime_dir/privacy-$runtime_privacy_party-settings-negative.log" 2>&1; then echo 'Unsafe database diagnostics unexpectedly accepted' >&2; exit 1; fi
 docker compose -p "$runtime_project" -f "$runtime_compose" exec -T "$runtime_privacy_service" psql -X -v ON_ERROR_STOP=1 -U "hnuhole_${runtime_privacy_party}_admin" -d "hnuhole_$runtime_privacy_party" -c "ALTER ROLE hnuhole_${runtime_privacy_party}_runtime RESET log_duration" >/dev/null
 done
python3 "$runtime_api_dir/authlab/privacy-diagnostics-canary.py" create "$runtime_dir"
for runtime_privacy_party in c v; do
 if [ "$runtime_privacy_party" = c ]; then runtime_privacy_service=community-postgres; else runtime_privacy_service=verifier-postgres; fi
 # Explicit safe positive control proves the captured server log is real.
 docker compose -p "$runtime_project" -f "$runtime_compose" exec -T "$runtime_privacy_service" psql -X -v ON_ERROR_STOP=1 -U "hnuhole_${runtime_privacy_party}_admin" -d "hnuhole_$runtime_privacy_party" <<'PRIVACY_SQL' >/dev/null
SET log_min_messages=log;
DO $$ BEGIN RAISE LOG 'AC03_RUNTIME_LOG_CONTROL'; END $$;
PRIVACY_SQL
 docker compose -p "$runtime_project" -f "$runtime_compose" exec -T "$runtime_privacy_service" psql -X -U "hnuhole_${runtime_privacy_party}_admin" -d "hnuhole_$runtime_privacy_party" < "$runtime_dir/privacy-canary.sql" >"$runtime_dir/privacy-$runtime_privacy_party-client.private" 2>&1
 done
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -c 'ALTER TRIGGER identity_account_shape_from_account ON c_auth.accounts RENAME TO identity_account_shape_temporarily_absent' >/dev/null
if "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/identity-close-trigger-missing-negative.log" 2>&1; then echo 'Missing closure shape trigger unexpectedly accepted' >&2; exit 1; fi
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -c 'ALTER TRIGGER identity_account_shape_temporarily_absent ON c_auth.accounts RENAME TO identity_account_shape_from_account' >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -c 'ALTER TABLE c_auth.accounts DISABLE TRIGGER identity_account_shape_from_account' >/dev/null
if "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/identity-close-trigger-disabled-negative.log" 2>&1; then echo 'Disabled closure shape trigger unexpectedly accepted' >&2; exit 1; fi
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -c 'ALTER TABLE c_auth.accounts ENABLE TRIGGER identity_account_shape_from_account' >/dev/null
# The V runtime needs the evidence/freeze columns and must never inherit the
# recovery role or acquire authority to advance its authorization generation.
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -c 'REVOKE UPDATE(evidence_version) ON v_auth.authorization_gate FROM hnuhole_v_runtime' >/dev/null
if "$runtime_dir/verifier" -config "$runtime_material/v.json" >"$runtime_dir/v-gate-dml-negative.log" 2>&1; then echo 'Missing V Gate column privilege unexpectedly accepted' >&2; exit 1; fi
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -c 'GRANT UPDATE(evidence_version,authorization_generation) ON v_auth.authorization_gate TO hnuhole_v_runtime' >/dev/null
if "$runtime_dir/verifier" -config "$runtime_material/v.json" >"$runtime_dir/v-gate-recovery-column-negative.log" 2>&1; then echo 'V API recovery column unexpectedly accepted' >&2; exit 1; fi
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -c 'REVOKE UPDATE(authorization_generation) ON v_auth.authorization_gate FROM hnuhole_v_runtime' >/dev/null
PGPASSWORD=$V_ADMIN_PASSWORD psql -X -v ON_ERROR_STOP=1 "postgres://hnuhole_v_admin@127.0.0.1:$V_DATABASE_PORT/hnuhole_v?sslmode=disable" -c 'GRANT hnuhole_v_recovery TO hnuhole_v_runtime WITH INHERIT FALSE' >/dev/null
if "$runtime_dir/verifier" -config "$runtime_material/v.json" >"$runtime_dir/v-gate-recovery-member-negative.log" 2>&1; then echo 'V API recovery role unexpectedly accepted' >&2; exit 1; fi
PGPASSWORD=$V_ADMIN_PASSWORD psql -X -v ON_ERROR_STOP=1 "postgres://hnuhole_v_admin@127.0.0.1:$V_DATABASE_PORT/hnuhole_v?sslmode=disable" -c 'REVOKE hnuhole_v_recovery FROM hnuhole_v_runtime' >/dev/null
# Each negative is restored before the next case; no weakened grants persist.
for runtime_identity_table in community_identities identity_account_state identity_change_receipts; do
 PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -c "ALTER TABLE public.$runtime_identity_table RENAME TO identity_temporarily_absent" >/dev/null
 if "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/identity-table-negative.log" 2>&1; then echo 'Missing identity table startup unexpectedly accepted' >&2; exit 1; fi
 PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -c "ALTER TABLE public.identity_temporarily_absent RENAME TO $runtime_identity_table" >/dev/null
 for runtime_identity_privilege in SELECT INSERT UPDATE; do
  if [ "$runtime_identity_table" = identity_change_receipts ] && [ "$runtime_identity_privilege" = UPDATE ]; then continue; fi
  PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -c "REVOKE $runtime_identity_privilege ON public.$runtime_identity_table FROM hnuhole_c_runtime" >/dev/null
  if "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/identity-dml-negative.log" 2>&1; then echo 'Missing identity DML startup unexpectedly accepted' >&2; exit 1; fi
  PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -c "GRANT $runtime_identity_privilege ON public.$runtime_identity_table TO hnuhole_c_runtime" >/dev/null
 done
done
# PG16 NOINHERIT membership still permits SET ROLE: startup must reject it.
PGPASSWORD=$C_ADMIN_PASSWORD psql -X -v ON_ERROR_STOP=1 "postgres://hnuhole_c_admin@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable" -c 'GRANT hnuhole_c_owner TO hnuhole_c_runtime WITH INHERIT FALSE' >/dev/null
if "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/owner-member-negative.log" 2>&1; then echo 'NOINHERIT owner member startup unexpectedly accepted' >&2; exit 1; fi
PGPASSWORD=$C_ADMIN_PASSWORD psql -X -v ON_ERROR_STOP=1 "postgres://hnuhole_c_admin@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable" -c 'REVOKE hnuhole_c_owner FROM hnuhole_c_runtime' >/dev/null
PGPASSWORD=$C_RUNTIME_PASSWORD psql -X -v ON_ERROR_STOP=1 "$AUTHRUNTIME_C_DSN" >/dev/null <<'SQL'
DO $$ BEGIN
 IF current_user <> 'hnuhole_c_runtime' OR pg_has_role(current_user,'hnuhole_c_owner','MEMBER')
  OR has_schema_privilege(current_user,'c_auth','CREATE') OR has_database_privilege(current_user,current_database(),'CREATE,TEMP') THEN RAISE EXCEPTION 'runtime privilege boundary'; END IF;
 IF (SELECT count(*) FROM public.channels)<>7 THEN RAISE EXCEPTION 'seven channels absent'; END IF;
 BEGIN PERFORM 1 FROM public.sessions; RAISE EXCEPTION 'legacy read unexpectedly allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN CREATE TABLE c_auth.runtime_ddl_forbidden(i int); RAISE EXCEPTION 'DDL unexpectedly allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE c_auth.authorization_gate SET gate_state='OPEN',authorization_generation=1,evidence_version=1,evidence_issued_at=clock_timestamp(),evidence_valid_until=clock_timestamp()+interval '1 minute',freeze_reason=NULL WHERE singleton_id=1; RAISE EXCEPTION 'API recovery unexpectedly allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
BEGIN;
INSERT INTO c_auth.authorization_gate_audit(event_kind,authorization_generation,evidence_version,actor,reason,operation_id,recorded_at)
VALUES('FREEZE',0,0,'runtime-permission-test','test','runtime-sequence-test',clock_timestamp());
ROLLBACK;
SQL
PGPASSWORD=$V_RUNTIME_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_dsn" >/dev/null <<'SQL'
DO $$ BEGIN
 IF current_user <> 'hnuhole_v_runtime' OR pg_has_role(current_user,'hnuhole_v_owner','MEMBER')
  OR has_schema_privilege(current_user,'v_auth','CREATE') OR has_database_privilege(current_user,current_database(),'CREATE,TEMP') THEN RAISE EXCEPTION 'runtime privilege boundary'; END IF;
 BEGIN CREATE TABLE v_auth.runtime_ddl_forbidden(i int); RAISE EXCEPTION 'DDL unexpectedly allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF pg_has_role(current_user,'hnuhole_v_recovery','MEMBER') THEN RAISE EXCEPTION 'API recovery membership'; END IF;
 BEGIN UPDATE v_auth.authorization_gate SET gate_state='OPEN',authorization_generation=1,evidence_version=1,evidence_issued_at=clock_timestamp(),evidence_valid_until=clock_timestamp()+interval '1 minute',freeze_reason=NULL WHERE singleton_id=1; RAISE EXCEPTION 'V API recovery unexpectedly allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
BEGIN;
INSERT INTO v_auth.authorization_gate_audit(event_kind,authorization_generation,evidence_version,actor,reason,operation_id,recorded_at)
VALUES('FREEZE',0,0,'runtime-permission-test','test','v-runtime-sequence-test',clock_timestamp());
ROLLBACK;
SQL
PGPASSWORD=$C_ADMIN_PASSWORD psql -X -v ON_ERROR_STOP=1 "postgres://hnuhole_c_admin@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable" >/dev/null <<'SQL'
SET ROLE hnuhole_business;
DO $$ BEGIN
 PERFORM 1 FROM public.channels;
 BEGIN PERFORM 1 FROM c_auth.accounts; RAISE EXCEPTION 'business auth read unexpectedly allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SQL
if PGPASSWORD=$V_RUNTIME_PASSWORD psql -X "postgres://hnuhole_v_runtime@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable" -c 'SELECT 1' >/dev/null 2>&1; then echo 'Cross-party access unexpectedly accepted' >&2; exit 1; fi
# Upgrade verification uses a separately named one-shot database owned by the
# migration owner. Preserve every seed field and UUID across the auth additions.
PGPASSWORD=$C_ADMIN_PASSWORD psql -X -v ON_ERROR_STOP=1 "postgres://hnuhole_c_admin@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable" -c 'CREATE DATABASE hnuhole_upgrade OWNER hnuhole_c_owner' >/dev/null
runtime_upgrade="postgres://hnuhole_c_migrator@127.0.0.1:$C_DATABASE_PORT/hnuhole_upgrade?sslmode=disable&options=-c%20role%3Dhnuhole_c_owner"
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_upgrade" up-to 2 >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c '\copy (SELECT * FROM public.channels ORDER BY id) TO STDOUT CSV' >"$runtime_dir/channels-before.csv"
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_upgrade" up-to 10 >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" >/dev/null <<'SQL'
INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version)
VALUES('00000000-0000-4000-8000-000000000010','654321','upgrade_fixture',decode(repeat('ab',32),'hex'),decode(repeat('cd',16),'hex'),1);
SQL
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c '\copy (SELECT * FROM c_auth.accounts ORDER BY account_id) TO STDOUT CSV' >"$runtime_dir/accounts-before.csv"
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_upgrade" up-to 11 >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c '\copy (SELECT * FROM c_auth.accounts ORDER BY account_id) TO STDOUT CSV' >"$runtime_dir/accounts-after.csv"
cmp "$runtime_dir/accounts-before.csv" "$runtime_dir/accounts-after.csv"
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" >/dev/null <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM public.community_identities)<>0 OR (SELECT count(*) FROM public.identity_account_state)<>0
  OR (SELECT count(*) FROM public.identity_change_receipts)<>0 THEN RAISE EXCEPTION 'upgrade fabricated identities'; END IF;
END $$;
SQL
# Upgrade 11 -> 12 preserves ACTIVE/PENDING profiles and permanent records.
# Schema 11 permits legacy CLOSED accounts with live profiles; these must be
# erased using the prior trusted Gate checkpoint, without rewriting tombstones.
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" >/dev/null <<'SQL'
BEGIN;
-- An explicit synthetic prior checkpoint, never a real time-source claim.
UPDATE c_auth.authorization_gate SET trusted_high_watermark=TIMESTAMPTZ '2026-10-04T00:00:00Z' WHERE singleton_id=1;
INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version,state)
VALUES('00000000-0000-4000-8000-000000000011','654322','upgrade_pending',decode(repeat('ab',32),'hex'),decode(repeat('cd',16),'hex'),1,'PENDING_CLOSE'),
 ('00000000-0000-4000-8000-000000000012','654323',NULL,NULL,NULL,NULL,'CLOSED');
INSERT INTO public.identity_account_state(account_id,created_count,last_created_at)
SELECT account_id,2,trusted_high_watermark-interval '1 day' FROM c_auth.accounts CROSS JOIN c_auth.authorization_gate;
INSERT INTO public.community_identities(identity_id,account_id,nickname,avatar,is_original,created_at,deleted_at)
SELECT v.identity_id::uuid,v.account_id::uuid,
 CASE WHEN v.original THEN '升级保留' ELSE NULL END,CASE WHEN v.original THEN 'default-v1' ELSE NULL END,v.original,
 g.trusted_high_watermark-CASE WHEN v.original THEN interval '2 days' ELSE interval '1 day' END,
 CASE WHEN v.original THEN NULL ELSE g.trusted_high_watermark-interval '12 hours' END
FROM (VALUES
 ('10000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-000000000010',true),
 ('20000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-000000000010',false),
 ('10000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000011',true),
 ('20000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000011',false),
 ('10000000-0000-4000-8000-000000000012','00000000-0000-4000-8000-000000000012',true),
 ('20000000-0000-4000-8000-000000000012','00000000-0000-4000-8000-000000000012',false)
) AS v(identity_id,account_id,original) CROSS JOIN c_auth.authorization_gate g;
INSERT INTO public.identity_change_receipts(account_id,change_key_digest,intent_fingerprint,state,operation,identity_id,committed_at)
SELECT account_id,decode(repeat(CASE WHEN is_original THEN 'ab' ELSE 'cd' END,32),'hex'),decode(repeat('ef',32),'hex'),'COMMITTED',
 CASE WHEN is_original THEN 'CREATE' ELSE 'DELETE' END,identity_id,COALESCE(deleted_at,created_at) FROM public.community_identities;
COMMIT;
SQL
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c "\copy (SELECT * FROM public.community_identities WHERE account_id<>'00000000-0000-4000-8000-000000000012'::uuid OR deleted_at IS NOT NULL ORDER BY identity_id) TO STDOUT CSV" >"$runtime_dir/identity-close-profiles-before.csv"
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c '\copy (SELECT * FROM public.identity_account_state ORDER BY account_id) TO STDOUT CSV' >"$runtime_dir/identity-close-counters-before.csv"
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c '\copy (SELECT * FROM public.identity_change_receipts ORDER BY account_id,change_key_digest) TO STDOUT CSV' >"$runtime_dir/identity-close-receipts-before.csv"
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_upgrade" up >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c "\copy (SELECT * FROM public.community_identities WHERE identity_id<>'10000000-0000-4000-8000-000000000012'::uuid ORDER BY identity_id) TO STDOUT CSV" >"$runtime_dir/identity-close-profiles-after.csv"
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c '\copy (SELECT * FROM public.identity_account_state ORDER BY account_id) TO STDOUT CSV' >"$runtime_dir/identity-close-counters-after.csv"
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c '\copy (SELECT * FROM public.identity_change_receipts ORDER BY account_id,change_key_digest) TO STDOUT CSV' >"$runtime_dir/identity-close-receipts-after.csv"
cmp "$runtime_dir/identity-close-profiles-before.csv" "$runtime_dir/identity-close-profiles-after.csv"
cmp "$runtime_dir/identity-close-counters-before.csv" "$runtime_dir/identity-close-counters-after.csv"
cmp "$runtime_dir/identity-close-receipts-before.csv" "$runtime_dir/identity-close-receipts-after.csv"
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" >/dev/null <<'SQL'
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.community_identities i JOIN c_auth.accounts a USING(account_id) WHERE a.state='CLOSED' AND i.deleted_at IS NULL)
  OR NOT EXISTS(SELECT 1 FROM public.community_identities i CROSS JOIN c_auth.authorization_gate g WHERE i.identity_id='10000000-0000-4000-8000-000000000012' AND i.nickname IS NULL AND i.avatar IS NULL AND i.last_renamed_at IS NULL AND i.deleted_at=g.trusted_high_watermark)
  THEN RAISE EXCEPTION 'legacy closed profile forward repair invalid'; END IF;
END $$;
SQL
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_upgrade" -c '\copy (SELECT * FROM public.channels ORDER BY id) TO STDOUT CSV' >"$runtime_dir/channels-after.csv"
cmp "$runtime_dir/channels-before.csv" "$runtime_dir/channels-after.csv"
# A deliberately failing COPY of the sole official 0003 Up belongs only to a
# separately named one-shot failure database. Goose must roll back every change.
PGPASSWORD=$C_ADMIN_PASSWORD psql -X -v ON_ERROR_STOP=1 "postgres://hnuhole_c_admin@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable" -c 'CREATE DATABASE hnuhole_migration_failure OWNER hnuhole_c_owner' >/dev/null
runtime_failure="postgres://hnuhole_c_migrator@127.0.0.1:$C_DATABASE_PORT/hnuhole_migration_failure?sslmode=disable&options=-c%20role%3Dhnuhole_c_owner"
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_failure" up-to 2 >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_failure" -c '\copy (SELECT * FROM public.channels ORDER BY id) TO STDOUT CSV' >"$runtime_dir/failure-before.csv"
mkdir "$runtime_dir/failure-migrations"
python3 - "$runtime_dir/failure-migrations" <<'PYCODE'
import pathlib,sys
source=pathlib.Path('migrations');dest=pathlib.Path(sys.argv[1])
for name in ('0001_sessions.sql','0002_channels.sql','0003_authprivacy.sql'):
 text=(source/name).read_text()
 if name.startswith('0003'):
  text=text.replace('-- +goose StatementEnd','SELECT 1/0;\n-- +goose StatementEnd',1)
 (dest/name).write_text(text)
PYCODE
if PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir "$runtime_dir/failure-migrations" postgres "$runtime_failure" up >"$runtime_dir/failure.log" 2>&1; then echo 'Deliberately failing migration unexpectedly committed' >&2; exit 1; fi
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_failure" >/dev/null <<'SQL'
DO $$ BEGIN
 IF to_regnamespace('c_auth') IS NOT NULL OR (SELECT MAX(version_id) FROM public.goose_db_version WHERE is_applied)<>2 THEN RAISE EXCEPTION 'failed migration was not atomic'; END IF;
END $$;
SQL
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_failure" -c '\copy (SELECT * FROM public.channels ORDER BY id) TO STDOUT CSV' >"$runtime_dir/failure-after.csv"
cmp "$runtime_dir/failure-before.csv" "$runtime_dir/failure-after.csv"
# Actual public HTTPS and mTLS servers start frozen. Ordinary API startup must
# not recover a Gate. Probe stores private state in its own marked directory.
mkdir "$runtime_dir/probe-state"
printf '%s' "$AUTHRUNTIME_TAG" >"$runtime_dir/probe-state/.runtime-tag"
runtime_start() {
 "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/c.log" 2>&1 & runtime_c_pid=$!
 "$runtime_dir/verifier" -config "$runtime_material/v.json" >"$runtime_dir/v.log" 2>&1 & runtime_v_pid=$!
}
runtime_stop() {
 kill "$runtime_c_pid" "$runtime_v_pid"
 wait "$runtime_c_pid"; wait "$runtime_v_pid"
 runtime_c_pid=;runtime_v_pid=
}
runtime_health() {
 runtime_attempt=0
 while [ "$runtime_attempt" -lt 50 ]; do
  if curl -fsS --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_c_port/health/live" >/dev/null && curl -fsS --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_v_port/health/live" >/dev/null; then return 0; fi
  runtime_attempt=$((runtime_attempt+1));sleep 1
 done
 echo 'Actual cmd health failed; private logs are removed by cleanup' >&2;return 1
}
runtime_probe() {
 PGPASSWORD=$C_RUNTIME_PASSWORD "$runtime_dir/probe" -phase "$1" \
 -community "https://127.0.0.1:$runtime_c_port" -verifier "https://127.0.0.1:$runtime_v_port" \
 -ca "$runtime_material/dev-ca.pem" -mailpit "http://127.0.0.1:$MAILPIT_HTTP_PORT" -state "$runtime_dir/probe-state/session.json"
}
runtime_start
runtime_health
runtime_privacy_c_status=$(curl -sS -o "$runtime_dir/privacy-c-response.private" -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" -H 'Content-Type: application/json' -H @"$runtime_dir/privacy-c-headers.private" --data-binary @"$runtime_dir/privacy-c-body.json" "https://127.0.0.1:$runtime_c_port/api/v1/auth/sessions")
runtime_privacy_v_status=$(curl -sS -o "$runtime_dir/privacy-v-response.private" -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" -H 'Content-Type: application/json' -H @"$runtime_dir/privacy-v-headers.private" --data-binary @"$runtime_dir/privacy-v-body.json" "https://127.0.0.1:$runtime_v_port/api/v1/eligibility/otp-requests")
test "$runtime_privacy_c_status" = 400
test "$runtime_privacy_v_status" = 400
runtime_ready=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_c_port/health/ready")
test "$runtime_ready" = 503
runtime_v_ready=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_v_port/health/ready")
test "$runtime_v_ready" = 503
runtime_origin_status=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" -H 'Origin: https://wrong-origin.invalid' "https://127.0.0.1:$runtime_c_port/api/v1/channels")
test "$runtime_origin_status" = 403
# Missing certificate, wrong workload certificate and a valid counterpart peer.
if curl -sS --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_ci_port/internal/v1/slot-retirements" >/dev/null 2>&1; then echo 'No-client-cert request unexpectedly allowed' >&2; exit 1; fi
if curl -sS --cacert "$runtime_material/dev-ca.pem" --cert "$runtime_material/c-internal.pem" --key "$runtime_material/c-internal.key" "https://127.0.0.1:$runtime_ci_port/internal/v1/slot-retirements" >/dev/null 2>&1; then echo 'Wrong peer request unexpectedly allowed' >&2; exit 1; fi
runtime_peer_status=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" --cert "$runtime_material/v-internal.pem" --key "$runtime_material/v-internal.key" "https://127.0.0.1:$runtime_ci_port/internal/v1/slot-retirements")
test "$runtime_peer_status" = 405
"$runtime_dir/authdev" recover -operator "$runtime_material/operator/operator.json"
"$runtime_dir/authdev" recover -operator "$runtime_material/operator/v-operator.json"
# A separate development operator renews evidence; stopping it lets TTL expire.
"$runtime_dir/authdev" watch -operator "$runtime_material/operator/operator.json" >"$runtime_dir/evidence.log" 2>&1 & runtime_evidence_pid=$!
"$runtime_dir/authdev" watch -operator "$runtime_material/operator/v-operator.json" >"$runtime_dir/v-evidence.log" 2>&1 & runtime_v_evidence_pid=$!
runtime_probe lifecycle
runtime_probe identities
runtime_probe threshold
runtime_stop
runtime_start
runtime_health
runtime_probe restart
# Stop V evidence renewal around each explicit recovery/snapshot rehearsal so
# it cannot race the operator. C continues independently throughout.
kill "$runtime_v_evidence_pid"
wait "$runtime_v_evidence_pid"
runtime_v_evidence_pid=
runtime_probe verifier-stage
PGPASSWORD=$V_MIGRATOR_PASSWORD pg_dump --schema=v_auth --no-owner --no-privileges "$runtime_v_migrator" >"$runtime_dir/v-old-snapshot.sql"
"$runtime_dir/authdev" freeze -operator "$runtime_material/operator/v-operator.json"
runtime_probe verifier-frozen
runtime_stop
runtime_start
runtime_health
runtime_probe verifier-frozen
"$runtime_dir/authdev" recover -operator "$runtime_material/operator/v-operator.json"
runtime_probe verifier-recovered
# Restore the actual previously OPEN V schema while preserving its newer
# out-of-database anchor. Only this invocation's disposable V database is used.
runtime_stop
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -c 'DROP SCHEMA v_auth CASCADE' >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -f "$runtime_dir/v-old-snapshot.sql" >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -f "$runtime_repo_dir/infra/postgres/grant-verifier.sql" >/dev/null
runtime_start
runtime_health
runtime_probe verifier-frozen
"$runtime_dir/authdev" recover -operator "$runtime_material/operator/v-operator.json"
runtime_probe verifier-recovered
"$runtime_dir/authdev" watch -operator "$runtime_material/operator/v-operator.json" >"$runtime_dir/v-evidence.log" 2>&1 & runtime_v_evidence_pid=$!
"$runtime_dir/authdev" freeze -operator "$runtime_material/operator/operator.json"
runtime_probe frozen
"$runtime_dir/authdev" recover -operator "$runtime_material/operator/operator.json"
runtime_probe recovered
# The already-due C fixture skips seven days. Advance only this invocation's
# old synthetic email's send interval as a fixture, preserving OTP lifetime and
# all Gate/monotonic triggers, before real same-email re-registration.
python3 - "$runtime_dir/probe-state/session.json" "$runtime_dir/return-send-interval.sql" <<'PY'
import json,pathlib,re,sys
email=json.loads(pathlib.Path(sys.argv[1]).read_text())['email']
assert re.fullmatch(r'runtime-[a-f0-9]{16}@hainanu\.edu\.cn',email)
pathlib.Path(sys.argv[2]).write_text("UPDATE v_auth.otp_email_state SET send_wait_until=clock_timestamp()-interval '1 second' WHERE email_exact=convert_to('"+email+"','UTF8');\n")
PY
PGPASSWORD=$V_RUNTIME_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_dsn" -f "$runtime_dir/return-send-interval.sql" >/dev/null
runtime_probe closure
# Stop the separately held source; short signed DEV evidence proves expiration
# without waiting five real minutes or introducing any public time override.
kill "$runtime_evidence_pid"
wait "$runtime_evidence_pid"
runtime_evidence_pid=
kill "$runtime_v_evidence_pid"
wait "$runtime_v_evidence_pid"
runtime_v_evidence_pid=
"$runtime_dir/authdev" issue -operator "$runtime_material/operator/v-operator.json" -valid-for 1s
sleep 2
runtime_v_expired_ready=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_v_port/health/ready")
test "$runtime_v_expired_ready" = 503
"$runtime_dir/authdev" issue -operator "$runtime_material/operator/operator.json" -valid-for 1s
sleep 2
runtime_expired_ready=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_c_port/health/ready")
test "$runtime_expired_ready" = 503
runtime_stop
docker compose -p "$runtime_project" -f "$runtime_compose" logs --no-color community-postgres >"$runtime_dir/privacy-pg-c.log"
docker compose -p "$runtime_project" -f "$runtime_compose" logs --no-color verifier-postgres >"$runtime_dir/privacy-pg-v.log"
python3 "$runtime_api_dir/authlab/privacy-diagnostics-canary.py" verify "$runtime_dir"
printf '%s\n' '{"privacyRoleMatrix":"passed","privacyUnsafeDatabaseDiagnosticsRejected":"passed","privacyRealProcessAndPostgresLogs":"passed","actualCmdLifecycle":"passed","formalMigrationAndRoles":"passed","upgradeChannelsPreserved":"passed","identityUpgrade10To11":"passed","identityClosureUpgrade11To12":"passed","identityLegacyClosedProfileRepair":"passed","identityClosureTriggerBoundary":"passed","identityMissingSchemaAndDml":"passed","identityCrudReceiptsAndRestart":"passed","identityClosureAndSameEmailNewAccount":"passed","inactiveProjectionPureContract":"passed","verifierGateUpgrade3To4":"passed","verifierGateFreezeRestartAndRecovery":"passed","verifierOldSnapshotBlocked":"passed","verifierOldGenerationOtpBlocked":"passed","verifierIndependentEvidenceExpiry":"passed","cleanup":"this invocation project and private directory only"}'
