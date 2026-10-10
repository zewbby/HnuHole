#!/bin/sh
# Owned development cluster for a full mobile App; never accepts an external DSN.
# Existing tools/images are required. Dependency acquisition is a separate step.
set -eu
umask 077
for device_tool in go goose docker psql python3 curl; do
 command -v "$device_tool" >/dev/null 2>&1 || { echo "Missing tool: $device_tool" >&2; exit 1; }
done
docker image inspect postgres:16.6-alpine >/dev/null
docker image inspect axllent/mailpit:v1.21.8 >/dev/null
device_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTH_DEVICE_WORK:?Use an owned private directory for this invocation}"
device_retain=${AUTH_DEVICE_RETAIN:-0}
case "$device_retain" in 0|1) ;; *) echo 'AUTH_DEVICE_RETAIN must be 0 or 1' >&2; exit 1 ;; esac
device_work=$(realpath "$AUTH_DEVICE_WORK")
test -d "$device_work"
test "$(cat "$device_work/OWNER")" = 'HNUHOLE_ANDROID_LIVE_DEV_V1'
test ! -e "$device_work/services"
device_dir="$device_work/services"
device_project="hnuhole-device-$(basename "$device_work" | tr -cd 'a-z0-9')"
device_compose="$device_repo/infra/docker-compose.yml"
# The directory marker does not establish ownership of an already existing
# Docker project. Refuse collisions before registering its cleanup trap.
test -z "$(docker ps -aq --filter "label=com.docker.compose.project=$device_project")"
test -z "$(docker volume ls -q --filter "label=com.docker.compose.project=$device_project")"
test -z "$(docker network ls -q --filter "label=com.docker.compose.project=$device_project")"
mkdir -m 700 "$device_dir"
device_children=
device_cleanup() {
 device_status=$?
 trap - EXIT INT TERM HUP
 if [ "$device_retain" = 1 ]; then
  test "$(cat "$device_work/OWNER")" = 'HNUHOLE_ANDROID_LIVE_DEV_V1'
  test "$(realpath "$device_dir")" = "$device_work/services"
  # Explicit retention keeps this owned project's DB, private materials,
  # services and evidence watchers available for later device phases. The PID
  # manifest below is local bookkeeping, never public acceptance evidence.
  echo 'RETAINED: owned device environment; no exit cleanup requested'
  exit "$device_status"
 fi
 for device_pid in $device_children; do
  kill "$device_pid" 2>/dev/null || true
 done
 for device_pid in $device_children; do wait "$device_pid" 2>/dev/null || true; done
 if [ "$device_status" -ne 0 ]; then
  # Private local diagnostics for startup repair, never a retained Git report.
  docker compose -p "$device_project" -f "$device_compose" logs --no-color > "$device_work/service-failure.log" 2>&1 || true
 fi
 docker compose -p "$device_project" -f "$device_compose" down -v --remove-orphans >/dev/null 2>&1 || true
 # Parent and marker belong to this run. Private material is never retained.
 test "$(cat "$device_work/OWNER")" = 'HNUHOLE_ANDROID_LIVE_DEV_V1'
 test "$(realpath "$device_dir")" = "$device_work/services"
 rm -rf "$device_dir"
 exit "$device_status"
}
trap device_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
device_ports=$(python3 - <<'PY'
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
set -- $device_ports
C_DATABASE_PORT=$1;V_DATABASE_PORT=$2;MAILPIT_SMTP_PORT=$3;MAILPIT_HTTP_PORT=$4
device_c_port=$5;device_v_port=$6;device_ci_port=$7;device_vi_port=$8
export C_DATABASE_PORT V_DATABASE_PORT MAILPIT_SMTP_PORT MAILPIT_HTTP_PORT
cd "$device_repo/services/api"
GOTOOLCHAIN=local GOPROXY=off go build -o "$device_dir/authdev" ./cmd/authdev
GOTOOLCHAIN=local GOPROXY=off go build -o "$device_dir/community" ./cmd/api
GOTOOLCHAIN=local GOPROXY=off go build -o "$device_dir/verifier" ./cmd/verifier
"$device_dir/authdev" init -dir "$device_dir/material" \
 -community-port "$device_c_port" -verifier-port "$device_v_port" \
 -community-internal-port "$device_ci_port" -verifier-internal-port "$device_vi_port" \
 -smtp-port "$MAILPIT_SMTP_PORT" \
 -community-dsn "postgres://hnuhole_c_runtime@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable" \
 -verifier-dsn "postgres://hnuhole_v_runtime@127.0.0.1:$V_DATABASE_PORT/hnuhole_v?sslmode=disable" \
 -recovery-dsn "postgres://hnuhole_c_recovery@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable" \
 -verifier-recovery-dsn "postgres://hnuhole_v_recovery@127.0.0.1:$V_DATABASE_PORT/hnuhole_v?sslmode=disable"
device_material="$device_dir/material"
for device_party in C V; do
 device_lower=$(printf '%s' "$device_party" | tr 'CV' 'cv')
 for device_role in ADMIN MIGRATOR RUNTIME RECOVERY; do
  device_role_lower=$(printf '%s' "$device_role" | tr 'A-Z' 'a-z')
  device_password_file="$device_material/operator/db-$device_lower-$device_role_lower.password"
  if [ "$device_role" = RUNTIME ]; then device_password_file="$device_material/db-$device_lower-runtime.password"; fi
  device_password=$(cat "$device_password_file")
  export "${device_party}_${device_role}_PASSWORD=$device_password"
 done
done
unset device_password
docker compose -p "$device_project" -f "$device_compose" up -d --pull never --wait >/dev/null
device_c_migrator="postgres://hnuhole_c_migrator@127.0.0.1:$C_DATABASE_PORT/hnuhole_c?sslmode=disable&options=-c%20role%3Dhnuhole_c_owner"
device_v_migrator="postgres://hnuhole_v_migrator@127.0.0.1:$V_DATABASE_PORT/hnuhole_v?sslmode=disable&options=-c%20role%3Dhnuhole_v_owner"
PGPASSWORD=$C_MIGRATOR_PASSWORD goose -dir migrations postgres "$device_c_migrator" up >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD goose -dir verifier-migrations postgres "$device_v_migrator" up >/dev/null
PGPASSWORD=$C_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$device_c_migrator" -f "$device_repo/infra/postgres/grant-community.sql" >/dev/null
PGPASSWORD=$V_MIGRATOR_PASSWORD psql -X -v ON_ERROR_STOP=1 "$device_v_migrator" -f "$device_repo/infra/postgres/grant-verifier.sql" >/dev/null
"$device_dir/community" -config "$device_material/c.json" >"$device_dir/c.log" 2>&1 &
device_children="$device_children $!"
"$device_dir/verifier" -config "$device_material/v.json" >"$device_dir/v.log" 2>&1 &
device_children="$device_children $!"
device_attempt=0
until curl -fsS --cacert "$device_material/dev-ca.pem" "https://127.0.0.1:$device_c_port/health/live" >/dev/null 2>&1 && \
 curl -fsS --cacert "$device_material/dev-ca.pem" "https://127.0.0.1:$device_v_port/health/live" >/dev/null 2>&1; do
 device_attempt=$((device_attempt+1));test "$device_attempt" -lt 45;sleep 1
done
"$device_dir/authdev" recover -operator "$device_material/operator/operator.json"
"$device_dir/authdev" recover -operator "$device_material/operator/v-operator.json"
"$device_dir/authdev" watch -operator "$device_material/operator/operator.json" >"$device_dir/c-evidence.log" 2>&1 &
device_children="$device_children $!"
"$device_dir/authdev" watch -operator "$device_material/operator/v-operator.json" >"$device_dir/v-evidence.log" 2>&1 &
device_children="$device_children $!"
curl -fsS --cacert "$device_material/dev-ca.pem" "https://127.0.0.1:$device_c_port/health/ready" >/dev/null
curl -fsS --cacert "$device_material/dev-ca.pem" "https://127.0.0.1:$device_v_port/health/ready" >/dev/null
printf '%s\n' "$device_children" > "$device_dir/owned-child-pids.txt"
python3 - "$device_material/dev-ca.pem" "$device_c_port" "$device_v_port" "$MAILPIT_HTTP_PORT" "$device_work/device-config.json" <<'PY'
import base64,json,pathlib,sys
ca,c,v,mail,target=sys.argv[1:]
pathlib.Path(target).write_text(json.dumps({
 'AUTH_COMMUNITY_BASE_URL':f'https://127.0.0.1:{c}',
 'AUTH_VERIFIER_BASE_URL':f'https://127.0.0.1:{v}',
 'AUTH_DEV_CA_BASE64':base64.b64encode(pathlib.Path(ca).read_bytes()).decode(),
 'AUTH_DEVICE_MAILPIT_URL':f'http://127.0.0.1:{mail}',
 'AUTH_DEVICE_RUN_ID':pathlib.Path(target).parent.name,
},indent=2)+'\n')
PY
echo 'READY: actual C/V, private disposable SQL, Mailpit and independent development Gates'
# By default exit cleans only this project. With explicit AUTH_DEVICE_RETAIN=1,
# exit preserves it and its child PID manifest for continued device work.
while :; do sleep 2; done
