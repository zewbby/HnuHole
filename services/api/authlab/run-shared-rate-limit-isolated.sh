#!/bin/sh
# Owned shared-rate fixture: creates only its own PostgreSQL data/socket and Redis test children.
# No external DSN, migration of an existing database, devices or deployment.
set -eu
# Aggregate package budget on slower owned disks; never permit an unbounded test.
authlab_test_timeout=${AUTHLAB_TEST_TIMEOUT:-20m}
case "$authlab_test_timeout" in
    [1-9]m|1[0-9]m|2[0-9]m|30m) ;;
    *) echo "Invalid auth lab test timeout (allowed 1m through 30m)" >&2; exit 2 ;;
esac
authlab_pg_port=${SHARED_RATE_PG_PORT:-55491}
PGPORT=$authlab_pg_port
export PGPORT
HNULIMIT_REDIS_SERVER=${HNULIMIT_REDIS_SERVER:-$(command -v redis-server || true)}
[ -n "$HNULIMIT_REDIS_SERVER" ] && [ -x "$HNULIMIT_REDIS_SERVER" ] || { echo "Owned Redis binary required" >&2; exit 2; }
"$HNULIMIT_REDIS_SERVER" --version | grep -q "v=7\." || { echo "Redis7 required" >&2; exit 2; }
export HNULIMIT_REDIS_SERVER
HNULIMIT_GOOSE=${HNULIMIT_GOOSE:-$(command -v goose || true)}
[ -n "$HNULIMIT_GOOSE" ] && [ -x "$HNULIMIT_GOOSE" ] || { echo "Pinned Goose migrator required" >&2; exit 2; }
"$HNULIMIT_GOOSE" -version 2>&1 | grep -q 'v3.22.1' || { echo "Goose v3.22.1 required" >&2; exit 2; }
export HNULIMIT_GOOSE
case "$authlab_pg_port" in
    ''|*[!0-9]*|0*) echo "Invalid auth lab PGPORT" >&2; exit 2 ;;
esac
[ "${#authlab_pg_port}" -le 5 ] && [ "$authlab_pg_port" -ge 1024 ] && [ "$authlab_pg_port" -le 65535 ] || {
    echo "Invalid auth lab PGPORT" >&2; exit 2;
}

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
mkdir "$AUTHLAB_RUN_DIR/socket" "$AUTHLAB_RUN_DIR/socket_v"
chmod 700 "$AUTHLAB_RUN_DIR/socket" "$AUTHLAB_RUN_DIR/socket_v"
authlab_cleanup() {
    authlab_status=$?
    pg_ctl -D "$AUTHLAB_RUN_DIR/data" -m fast -w stop >/dev/null 2>&1 || true
    pg_ctl -D "$AUTHLAB_RUN_DIR/data_v" -m fast -w stop >/dev/null 2>&1 || true
    if [ "$authlab_status" -ne 0 ]; then
        tail -n 30 "$AUTHLAB_RUN_DIR/postgres.log" 2>/dev/null || true
        tail -n 30 "$AUTHLAB_RUN_DIR/verifier-postgres.log" 2>/dev/null || true
    fi
    rm -rf "$AUTHLAB_RUN_DIR"
    exit "$authlab_status"
}
trap authlab_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

initdb -D "$AUTHLAB_RUN_DIR/data" -U authlab_admin -A trust --no-locale -E UTF8 >"$AUTHLAB_RUN_DIR/init.log" 2>&1
pg_ctl -D "$AUTHLAB_RUN_DIR/data" -l "$AUTHLAB_RUN_DIR/postgres.log" -w start \
    -o "-p $authlab_pg_port -c listen_addresses='' -c unix_socket_directories='$AUTHLAB_RUN_DIR/socket' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=40 -c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic -c log_error_verbosity=terse -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0 -c log_min_duration_statement=-1 -c log_min_duration_sample=-1 -c log_transaction_sample_rate=0 -c log_duration=off" >/dev/null

# Separate clusters preserve the original C/V credential-domain audit.
initdb -D "$AUTHLAB_RUN_DIR/data_v" -U authlab_admin -A trust --no-locale -E UTF8 >"$AUTHLAB_RUN_DIR/init-v.log" 2>&1
pg_ctl -D "$AUTHLAB_RUN_DIR/data_v" -l "$AUTHLAB_RUN_DIR/verifier-postgres.log" -w start \
    -o "-p $authlab_pg_port -c listen_addresses='' -c unix_socket_directories='$AUTHLAB_RUN_DIR/socket_v' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=30 -c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic -c log_error_verbosity=terse -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0 -c log_min_duration_statement=-1 -c log_min_duration_sample=-1 -c log_transaction_sample_rate=0 -c log_duration=off" >/dev/null
psql -X -v ON_ERROR_STOP=1 -h "$AUTHLAB_RUN_DIR/socket" -U authlab_admin -d postgres >/dev/null <<'SQL'
CREATE ROLE hnuhole_c LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_recovery NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_business NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE hnuhole_c OWNER hnuhole_c;
CREATE DATABASE hnuhole_limit_init_c OWNER hnuhole_c;
REVOKE ALL ON DATABASE hnuhole_c FROM PUBLIC;
REVOKE ALL ON DATABASE hnuhole_limit_init_c FROM PUBLIC;
GRANT CONNECT ON DATABASE hnuhole_c TO hnuhole_c,hnuhole_c_runtime;
GRANT CONNECT ON DATABASE hnuhole_limit_init_c TO hnuhole_c;
SQL
psql -X -v ON_ERROR_STOP=1 -h "$AUTHLAB_RUN_DIR/socket_v" -U authlab_admin -d postgres >/dev/null <<'SQL'
CREATE ROLE hnuhole_v LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_v_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_v_recovery NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE hnuhole_v OWNER hnuhole_v;
CREATE DATABASE hnuhole_limit_init_v OWNER hnuhole_v;
REVOKE ALL ON DATABASE hnuhole_v FROM PUBLIC;
REVOKE ALL ON DATABASE hnuhole_limit_init_v FROM PUBLIC;
GRANT CONNECT ON DATABASE hnuhole_v TO hnuhole_v,hnuhole_v_runtime;
GRANT CONNECT ON DATABASE hnuhole_limit_init_v TO hnuhole_v;
SQL

AUTHLAB_RUNTIME_TAG="hnuhole_authlab_$(date -u +%Y%m%d%H%M%S)"
AUTHLAB_C_DSN="postgresql://hnuhole_c@/hnuhole_c?host=$AUTHLAB_RUN_DIR/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_V_DSN="postgresql://hnuhole_v@/hnuhole_v?host=$AUTHLAB_RUN_DIR/socket_v&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_POSTS_RUNTIME_DSN="postgresql://hnuhole_c_runtime@/hnuhole_c?host=$AUTHLAB_RUN_DIR/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_RATE_CTL_C_DSN="postgresql://hnuhole_c@/hnuhole_limit_init_c?host=$AUTHLAB_RUN_DIR/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_RATE_CTL_V_DSN="postgresql://hnuhole_v@/hnuhole_limit_init_v?host=$AUTHLAB_RUN_DIR/socket_v&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_V_RUNTIME_DSN="postgresql://hnuhole_v_runtime@/hnuhole_v?host=$AUTHLAB_RUN_DIR/socket_v&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export AUTHLAB_V_RUNTIME_DSN
export AUTHLAB_C_DSN AUTHLAB_V_DSN AUTHLAB_POSTS_RUNTIME_DSN AUTHLAB_RUNTIME_TAG AUTHLAB_RATE_CTL_C_DSN AUTHLAB_RATE_CTL_V_DSN
AUTHLAB_POSTGRES_LOG="$AUTHLAB_RUN_DIR/postgres.log"
export AUTHLAB_POSTGRES_LOG
export AUTHLAB_ALLOW_SCHEMA_RESET=1
authlab_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$authlab_script_dir/.."
POST_MEDIA_PYTHON=${POST_MEDIA_PYTHON:-$(command -v python3 || true)}
[ -n "$POST_MEDIA_PYTHON" ] && [ -x "$POST_MEDIA_PYTHON" ] || { echo "Pinned Pillow Python runtime required" >&2; exit 2; }
"$POST_MEDIA_PYTHON" -c 'import PIL; assert PIL.__version__ == "12.3.0"' || { echo "Pinned Pillow12.3.0 required" >&2; exit 2; }
POST_MEDIA_VALIDATOR="$AUTHLAB_RUN_DIR/validate_image.py"
cp "$authlab_script_dir/../media/validate_image.py" "$POST_MEDIA_VALIDATOR"
chmod 600 "$POST_MEDIA_VALIDATOR"
POST_MEDIA_FIXTURES="$AUTHLAB_RUN_DIR/media"
"$POST_MEDIA_PYTHON" "$authlab_script_dir/../media/test_validator.py" --fixtures "$POST_MEDIA_FIXTURES"
export POST_MEDIA_PYTHON POST_MEDIA_VALIDATOR POST_MEDIA_FIXTURES
# Explicit device mode owns the same disposable dual-cluster infrastructure,
# but runs only the long-lived opt-in fixture until its private .stop marker.
case "${SHARED_RATE_DEVICE:-0}" in
  0) [ -z "${SHARED_RATE_DEVICE_FIXTURE:-}" ] || { echo "Device fixture requires explicit SHARED_RATE_DEVICE=1" >&2; exit 2; } ;;
  1) : "${SHARED_RATE_DEVICE_FIXTURE:?private device fixture path required}"
     export SHARED_RATE_DEVICE_FIXTURE
     go test -mod=readonly -race -count=1 -timeout=30m ./internal/authprivacyhttp -run '^TestSharedRateDevicePostgres$' -v
     exit 0 ;;
  *) echo "SHARED_RATE_DEVICE must be unset or 1" >&2; exit 2 ;;
esac

go test -mod=readonly -race -count=1 -timeout="$authlab_test_timeout" ./internal/ratelimit -v
go test -mod=readonly -race -count=1 -timeout="$authlab_test_timeout" ./internal/authprivacyhttp -run '^TestShared(Source|Rate)' -v
go test -mod=readonly -race -count=1 -timeout="$authlab_test_timeout" -p 1 ./internal/authprivacy -run '^TestSharedRate' -v
go test -mod=readonly -count=1 ./cmd/ratelimitctl -v
go build -mod=readonly ./cmd/authdev ./cmd/ratelimitctl
go vet -mod=readonly ./internal/ratelimit ./internal/authprivacy ./internal/authprivacyhttp ./internal/authprivacyruntime
