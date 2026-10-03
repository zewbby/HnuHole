#!/bin/sh
# Actual C/V cmd processes, formal Goose migrations, separate non-owner runtime
# credentials and real Mailpit. Requires existing tools AND cached images/modules.
set -eu
umask 077
for runtime_tool in go goose docker psql python3 curl cmp; do
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
runtime_c_pid=;runtime_v_pid=;runtime_evidence_pid=
runtime_cleanup() {
 runtime_status=$?
 trap - EXIT INT TERM HUP
 for runtime_pid in "$runtime_evidence_pid" "$runtime_c_pid" "$runtime_v_pid"; do
  if [ -n "$runtime_pid" ]; then kill "$runtime_pid" 2>/dev/null || true; wait "$runtime_pid" 2>/dev/null || true; fi
 done
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
 -recovery-dsn "postgres://hnuhole_c_recovery@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable"
runtime_material="$runtime_dir/material"
C_ADMIN_PASSWORD=$(cat "$runtime_material/operator/db-c-admin.password")
C_MIGRATOR_PASSWORD=$(cat "$runtime_material/operator/db-c-migrator.password")
C_RUNTIME_PASSWORD=$(cat "$runtime_material/db-c-runtime.password")
C_RECOVERY_PASSWORD=$(cat "$runtime_material/operator/db-c-recovery.password")
V_ADMIN_PASSWORD=$(cat "$runtime_material/operator/db-v-admin.password")
V_MIGRATOR_PASSWORD=$(cat "$runtime_material/operator/db-v-migrator.password")
V_RUNTIME_PASSWORD=$(cat "$runtime_material/db-v-runtime.password")
export C_ADMIN_PASSWORD C_MIGRATOR_PASSWORD C_RUNTIME_PASSWORD C_RECOVERY_PASSWORD V_ADMIN_PASSWORD V_MIGRATOR_PASSWORD V_RUNTIME_PASSWORD
docker compose -p "$runtime_project" -f "$runtime_compose" up -d --pull never --wait >/dev/null
if "$runtime_dir/community" -config "$runtime_material/c.json" >"$runtime_dir/schema-negative.log" 2>&1; then echo 'Missing schema startup unexpectedly accepted' >&2; exit 1; fi
runtime_c_migrator="postgres://hnuhole_c_migrator@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable&options=-c%20role%3Dhnuhole_c_owner"
runtime_v_migrator="postgres://hnuhole_v_migrator@127.0.0.1:$V_DATABASE_PORT/hnuhole_v?sslmode=disable&options=-c%20role%3Dhnuhole_v_owner"
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_c_migrator" up >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD goose -dir verifier-migrations postgres "$runtime_v_migrator" up >/dev/null
# Second invocation must be a no-op, preserving seed identities.
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_c_migrator" up >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD goose -dir verifier-migrations postgres "$runtime_v_migrator" up >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_c_migrator" -f "$runtime_repo_dir/infra/postgres/grant-community.sql" >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$runtime_v_migrator" -f "$runtime_repo_dir/infra/postgres/grant-verifier.sql" >/dev/null
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
END $$;
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
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$runtime_upgrade" up >/dev/null
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
runtime_ready=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_c_port/health/ready")
test "$runtime_ready" = 503
runtime_origin_status=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" -H 'Origin: https://wrong-origin.invalid' "https://127.0.0.1:$runtime_c_port/api/v1/channels")
test "$runtime_origin_status" = 403
# Missing certificate, wrong workload certificate and a valid counterpart peer.
if curl -sS --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_ci_port/internal/v1/slot-retirements" >/dev/null 2>&1; then echo 'No-client-cert request unexpectedly allowed' >&2; exit 1; fi
if curl -sS --cacert "$runtime_material/dev-ca.pem" --cert "$runtime_material/c-internal.pem" --key "$runtime_material/c-internal.key" "https://127.0.0.1:$runtime_ci_port/internal/v1/slot-retirements" >/dev/null 2>&1; then echo 'Wrong peer request unexpectedly allowed' >&2; exit 1; fi
runtime_peer_status=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" --cert "$runtime_material/v-internal.pem" --key "$runtime_material/v-internal.key" "https://127.0.0.1:$runtime_ci_port/internal/v1/slot-retirements")
test "$runtime_peer_status" = 405
"$runtime_dir/authdev" recover -operator "$runtime_material/operator/operator.json"
# A separate development operator renews evidence; stopping it lets TTL expire.
"$runtime_dir/authdev" watch -operator "$runtime_material/operator/operator.json" >"$runtime_dir/evidence.log" 2>&1 & runtime_evidence_pid=$!
runtime_probe lifecycle
runtime_probe threshold
runtime_stop
runtime_start
runtime_health
runtime_probe restart
"$runtime_dir/authdev" freeze -operator "$runtime_material/operator/operator.json"
runtime_probe frozen
"$runtime_dir/authdev" recover -operator "$runtime_material/operator/operator.json"
runtime_probe recovered
runtime_probe closure
# Stop the separately held source; short signed DEV evidence proves expiration
# without waiting five real minutes or introducing any public time override.
kill "$runtime_evidence_pid"
wait "$runtime_evidence_pid"
runtime_evidence_pid=
"$runtime_dir/authdev" issue -operator "$runtime_material/operator/operator.json" -valid-for 1s
sleep 2
runtime_expired_ready=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$runtime_material/dev-ca.pem" "https://127.0.0.1:$runtime_c_port/health/ready")
test "$runtime_expired_ready" = 503
runtime_stop
printf '%s\n' '{"actualCmdLifecycle":"passed","formalMigrationAndRoles":"passed","upgradeChannelsPreserved":"passed","cleanup":"this invocation project and private directory only"}'
