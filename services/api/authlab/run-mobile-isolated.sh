#!/bin/sh
# Test-only Flutter -> public HTTPS C/V -> private disposable PostgreSQL.
# Toolchains must already exist. No deployed service or system setting is used.
set -eu

for mobilelab_tool in go initdb pg_ctl psql; do
    command -v "$mobilelab_tool" >/dev/null 2>&1 || {
        echo "Missing tool: $mobilelab_tool" >&2
        exit 1
    }
done
: "${AUTHLAB_MOBILE_FLUTTER:?Set AUTHLAB_MOBILE_FLUTTER to the Flutter executable}"
test -x "$AUTHLAB_MOBILE_FLUTTER" || {
    echo "Flutter executable is unavailable" >&2
    exit 1
}
MOBILELAB_RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-mobilelab.XXXXXX")
case "$MOBILELAB_RUN_DIR" in
    *[!A-Za-z0-9_./-]*) echo "Unsupported temporary path" >&2; exit 1 ;;
esac
chmod 700 "$MOBILELAB_RUN_DIR"
mkdir "$MOBILELAB_RUN_DIR/socket"
chmod 700 "$MOBILELAB_RUN_DIR/socket"
mobilelab_cleanup() {
    mobilelab_status=$?
    pg_ctl -D "$MOBILELAB_RUN_DIR/data" -m fast -w stop >/dev/null 2>&1 || true
    if [ "$mobilelab_status" -ne 0 ]; then
        tail -n 20 "$MOBILELAB_RUN_DIR/postgres.log" 2>/dev/null || true
    fi
    rm -rf "$MOBILELAB_RUN_DIR"
    exit "$mobilelab_status"
}
trap mobilelab_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

initdb -D "$MOBILELAB_RUN_DIR/data" -U authlab_admin -A trust --no-locale -E UTF8 >"$MOBILELAB_RUN_DIR/init.log" 2>&1
pg_ctl -D "$MOBILELAB_RUN_DIR/data" -l "$MOBILELAB_RUN_DIR/postgres.log" -w start \
    -o "-c listen_addresses='' -c unix_socket_directories='$MOBILELAB_RUN_DIR/socket' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=40" >/dev/null
psql -X -v ON_ERROR_STOP=1 -h "$MOBILELAB_RUN_DIR/socket" -U authlab_admin -d postgres >/dev/null <<'SQL'
CREATE ROLE hnuhole_c LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_v LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE hnuhole_c OWNER hnuhole_c;
CREATE DATABASE hnuhole_v OWNER hnuhole_v;
REVOKE CONNECT ON DATABASE hnuhole_c FROM PUBLIC;
REVOKE CONNECT ON DATABASE hnuhole_v FROM PUBLIC;
GRANT CONNECT ON DATABASE hnuhole_c TO hnuhole_c;
GRANT CONNECT ON DATABASE hnuhole_v TO hnuhole_v;
SQL
AUTHLAB_RUNTIME_TAG="hnuhole_authlab_mobile_$(date -u +%Y%m%d%H%M%S)"
AUTHLAB_C_DSN="postgresql://hnuhole_c@/hnuhole_c?host=$MOBILELAB_RUN_DIR/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_V_DSN="postgresql://hnuhole_v@/hnuhole_v?host=$MOBILELAB_RUN_DIR/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export AUTHLAB_C_DSN AUTHLAB_V_DSN AUTHLAB_RUNTIME_TAG
export AUTHLAB_ALLOW_SCHEMA_RESET=1 CI=true FLUTTER_SUPPRESS_ANALYTICS=true
mobilelab_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$mobilelab_script_dir/.."
go test -race -count=1 -p 1 -timeout 8m -v -run '^TestMobileClientHTTPSPostgres$' ./internal/authprivacyhttp
