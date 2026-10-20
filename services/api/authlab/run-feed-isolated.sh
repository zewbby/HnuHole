#!/bin/sh
# Own disposable databases only; never accept an external DSN.
set -eu
[ "$(id -u)" -ne 0 ] || { echo 'Run feed fixture as a non-root task user' >&2; exit 2; }
umask 077
feed_port=${PGPORT:-55439}
case "$feed_port" in ''|*[!0-9]*|0*) echo 'Invalid PGPORT' >&2; exit 2 ;; esac
[ "${#feed_port}" -le 5 ] && [ "$feed_port" -ge 1024 ] && [ "$feed_port" -le 65535 ] || exit 2
for feed_tool in go initdb pg_ctl psql; do
    command -v "$feed_tool" >/dev/null 2>&1 || { echo "Missing tool: $feed_tool" >&2; exit 1; }
done
[ -n "${FEED_GOOSE:-}" ] && [ -x "$FEED_GOOSE" ] || { echo 'FEED_GOOSE must identify the pinned Goose v3.22.1' >&2; exit 2; }
"$FEED_GOOSE" -version | grep -q 'v3.22.1' || { echo 'Unexpected Goose version' >&2; exit 2; }
feed_dir=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-feed.XXXXXX")
case "$feed_dir" in *[!A-Za-z0-9_./-]*) echo 'Unsupported private fixture path' >&2; exit 2 ;; esac
mkdir "$feed_dir/socket"
feed_cleanup() {
    feed_status=$?
    pg_ctl -D "$feed_dir/data" -m fast -w stop >/dev/null 2>&1 || true
    rm -rf "$feed_dir"
    exit "$feed_status"
}
trap feed_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
initdb -D "$feed_dir/data" -U feed_admin -A trust --no-locale -E UTF8 >"$feed_dir/init.log" 2>&1
pg_ctl -D "$feed_dir/data" -l "$feed_dir/postgres.log" -w start \
    -o "-p $feed_port -c listen_addresses='' -c unix_socket_directories='$feed_dir/socket' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=40 -c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic -c log_error_verbosity=terse -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0 -c log_min_duration_statement=-1 -c log_min_duration_sample=-1 -c log_transaction_sample_rate=0 -c log_duration=off" >/dev/null
psql -X -v ON_ERROR_STOP=1 -p "$feed_port" -h "$feed_dir/socket" -U feed_admin -d postgres >/dev/null <<'SQL'
CREATE ROLE hnuhole_c LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_v LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_recovery NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_business NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE hnuhole_c OWNER hnuhole_c;
CREATE DATABASE hnuhole_v OWNER hnuhole_v;
CREATE DATABASE hnuhole_feed_fresh OWNER hnuhole_c;
CREATE DATABASE hnuhole_feed_upgrade OWNER hnuhole_c;
CREATE DATABASE hnuhole_feed_interactions OWNER hnuhole_c;
CREATE DATABASE hnuhole_feed_versions OWNER hnuhole_c;
REVOKE CONNECT ON DATABASE hnuhole_c,hnuhole_v,hnuhole_feed_fresh,hnuhole_feed_upgrade,hnuhole_feed_interactions,hnuhole_feed_versions FROM PUBLIC;
GRANT CONNECT ON DATABASE hnuhole_c TO hnuhole_c,hnuhole_c_runtime;
GRANT CONNECT ON DATABASE hnuhole_v TO hnuhole_v;
GRANT CONNECT ON DATABASE hnuhole_feed_fresh,hnuhole_feed_upgrade,hnuhole_feed_interactions,hnuhole_feed_versions TO hnuhole_c;
SQL
export PGPORT="$feed_port"
AUTHLAB_RUNTIME_TAG="hnuhole_authlab_feed_$(date -u +%Y%m%d%H%M%S)"
AUTHLAB_C_DSN="postgresql://hnuhole_c@/hnuhole_c?host=$feed_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_V_DSN="postgresql://hnuhole_v@/hnuhole_v?host=$feed_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_POSTS_RUNTIME_DSN="postgresql://hnuhole_c_runtime@/hnuhole_c?host=$feed_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
FEED_FRESH_DSN="postgresql://hnuhole_c@/hnuhole_feed_fresh?host=$feed_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
FEED_UPGRADE_DSN="postgresql://hnuhole_c@/hnuhole_feed_upgrade?host=$feed_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
FEED_INTERACTIONS_DSN="postgresql://hnuhole_c@/hnuhole_feed_interactions?host=$feed_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
FEED_VERSIONS_DSN="postgresql://hnuhole_c@/hnuhole_feed_versions?host=$feed_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_ALLOW_SCHEMA_RESET=1
export AUTHLAB_RUNTIME_TAG AUTHLAB_C_DSN AUTHLAB_V_DSN AUTHLAB_POSTS_RUNTIME_DSN AUTHLAB_ALLOW_SCHEMA_RESET FEED_FRESH_DSN FEED_UPGRADE_DSN FEED_INTERACTIONS_DSN FEED_VERSIONS_DSN
feed_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$feed_script_dir/.."
go test -race -count=1 -p 1 ./internal/authprivacy ./internal/authprivacyhttp ./internal/authprivacyruntime \
    -run "${FEED_TEST_PATTERN:-^(TestFeed|TestRealHTTPSFeed(Views|Interactions)|TestPostSchema|TestPostAtomic|TestPostCeiling|TestPostGate|TestPostFormalClosure|TestRealHTTPSPost(Acceptance|Stops)|TestModerationLifecycleCommonCStartup|TestCommentText(Transactions|FailureRetryAbandon|FrozenGate|RuntimeAndSQLGuards|UnavailablePost|ClosureCleanupWithFeatureDisabled|HTTPS|NullableBoundary)|TestCommentBusiness(MediaDeleteLikesNotices|HTTPS))}" -v
