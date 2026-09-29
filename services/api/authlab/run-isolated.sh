#!/bin/sh
# Requires an existing Go and PostgreSQL toolchain; never installs system tools.
set -eu

for authlab_tool in go initdb pg_ctl psql; do
    command -v "$authlab_tool" >/dev/null 2>&1 || {
        echo "Missing tool: $authlab_tool" >&2
        exit 1
    }
done

AUTHLAB_RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-authlab.XXXXXX")
# pg_ctl's -o is parsed by a shell; accept only simple generated paths.
case "$AUTHLAB_RUN_DIR" in
    *[!A-Za-z0-9_./-]*) echo "Unsupported temporary path" >&2; exit 1 ;;
esac
chmod 700 "$AUTHLAB_RUN_DIR"
mkdir "$AUTHLAB_RUN_DIR/socket"
chmod 700 "$AUTHLAB_RUN_DIR/socket"
authlab_cleanup() {
    authlab_status=$?
    pg_ctl -D "$AUTHLAB_RUN_DIR/data" -m fast -w stop >/dev/null 2>&1 || true
    if [ "$authlab_status" -ne 0 ]; then
        tail -n 30 "$AUTHLAB_RUN_DIR/postgres.log" 2>/dev/null || true
    fi
    rm -rf "$AUTHLAB_RUN_DIR"
    exit "$authlab_status"
}
trap authlab_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

initdb -D "$AUTHLAB_RUN_DIR/data" -U authlab_admin -A trust --no-locale -E UTF8 >"$AUTHLAB_RUN_DIR/init.log" 2>&1
pg_ctl -D "$AUTHLAB_RUN_DIR/data" -l "$AUTHLAB_RUN_DIR/postgres.log" -w start \
    -o "-c listen_addresses='' -c unix_socket_directories='$AUTHLAB_RUN_DIR/socket' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=40" >/dev/null

psql -X -v ON_ERROR_STOP=1 -h "$AUTHLAB_RUN_DIR/socket" -U authlab_admin -d postgres >/dev/null <<'SQL'
CREATE ROLE hnuhole_c LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_v LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE hnuhole_c OWNER hnuhole_c;
CREATE DATABASE hnuhole_v OWNER hnuhole_v;
REVOKE CONNECT ON DATABASE hnuhole_c FROM PUBLIC;
REVOKE CONNECT ON DATABASE hnuhole_v FROM PUBLIC;
GRANT CONNECT ON DATABASE hnuhole_c TO hnuhole_c;
GRANT CONNECT ON DATABASE hnuhole_v TO hnuhole_v;
SQL

AUTHLAB_RUNTIME_TAG="hnuhole_authlab_$(date -u +%Y%m%d%H%M%S)"
AUTHLAB_C_DSN="postgresql://hnuhole_c@/hnuhole_c?host=$AUTHLAB_RUN_DIR/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_V_DSN="postgresql://hnuhole_v@/hnuhole_v?host=$AUTHLAB_RUN_DIR/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export AUTHLAB_C_DSN AUTHLAB_V_DSN AUTHLAB_RUNTIME_TAG
export AUTHLAB_ALLOW_SCHEMA_RESET=1
authlab_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$authlab_script_dir/.."
go test -race -count=1 -p 1 ./...
go vet ./...
