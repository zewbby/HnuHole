#!/bin/sh
# 仅创建本次临时 PostgreSQL 私有 socket fixture；不接收外部 DSN，不安装工具。
set -eu
umask 077
comment_text_pg_port=${PGPORT:-55463}
PGPORT=$comment_text_pg_port
export PGPORT
case "$comment_text_pg_port" in
    ''|*[!0-9]*|0*) echo "Invalid comment text PGPORT" >&2; exit 2 ;;
esac
[ "${#comment_text_pg_port}" -le 5 ] && [ "$comment_text_pg_port" -ge 1024 ] && [ "$comment_text_pg_port" -le 65535 ] || {
    echo "Invalid comment text PGPORT" >&2; exit 2;
}
for comment_text_tool in go goose initdb pg_ctl psql; do
    command -v "$comment_text_tool" >/dev/null 2>&1 || { echo "Missing tool: $comment_text_tool" >&2; exit 1; }
done
goose -version 2>&1 | python3 -c 'import sys; assert "v3.22.1" in sys.stdin.read(), "Goose v3.22.1 required"'
comment_text_dir=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-comment-text.XXXXXX")
case "$comment_text_dir" in *[!A-Za-z0-9_./-]*) echo 'Unsupported temporary path' >&2; exit 1 ;; esac
comment_text_socket=$(mktemp -d /tmp/hnuhole-comment-text-socket.XXXXXX)
comment_text_cleanup() {
    comment_text_status=$?
    pg_ctl -D "$comment_text_dir/data" -m fast -w stop >/dev/null 2>&1 || true
    rm -rf "$comment_text_dir" "$comment_text_socket"
    exit "$comment_text_status"
}
trap comment_text_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
initdb -D "$comment_text_dir/data" -U comment_text_admin -A trust --no-locale -E UTF8 >"$comment_text_dir/init.log" 2>&1
pg_ctl -D "$comment_text_dir/data" -l "$comment_text_dir/postgres.log" -w start \
    -o "-p $comment_text_pg_port -c listen_addresses='' -c unix_socket_directories='$comment_text_socket' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=40 -c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic -c log_error_verbosity=terse -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0 -c log_min_duration_statement=-1 -c log_min_duration_sample=-1 -c log_transaction_sample_rate=0 -c log_duration=off" >/dev/null || { tail -n 15 "$comment_text_dir/postgres.log"; exit 1; }
psql -X -v ON_ERROR_STOP=1 -h "$comment_text_socket" -U comment_text_admin -d postgres >/dev/null <<'SQL'
CREATE ROLE hnuhole_c LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_v LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_recovery NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_business NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE hnuhole_c OWNER hnuhole_c;
CREATE DATABASE hnuhole_v OWNER hnuhole_v;
CREATE DATABASE hnuhole_comments_upgrade OWNER hnuhole_c;
CREATE DATABASE hnuhole_comments_fresh OWNER hnuhole_c;
CREATE DATABASE hnuhole_moderation_upgrade OWNER hnuhole_c;
REVOKE CONNECT ON DATABASE hnuhole_c FROM PUBLIC;
REVOKE CONNECT ON DATABASE hnuhole_v FROM PUBLIC;
REVOKE CONNECT ON DATABASE hnuhole_comments_upgrade,hnuhole_comments_fresh FROM PUBLIC;
REVOKE CONNECT ON DATABASE hnuhole_moderation_upgrade FROM PUBLIC;
GRANT CONNECT ON DATABASE hnuhole_moderation_upgrade TO hnuhole_c;
GRANT CONNECT ON DATABASE hnuhole_comments_upgrade,hnuhole_comments_fresh TO hnuhole_c;
GRANT CONNECT ON DATABASE hnuhole_c TO hnuhole_c,hnuhole_c_runtime;
GRANT CONNECT ON DATABASE hnuhole_v TO hnuhole_v;
SQL
AUTHLAB_RUNTIME_TAG="hnuhole_authlab_comment_text_$(date -u +%Y%m%d%H%M%S)"
AUTHLAB_C_DSN="postgresql://hnuhole_c@/hnuhole_c?host=$comment_text_socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_V_DSN="postgresql://hnuhole_v@/hnuhole_v?host=$comment_text_socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_POSTS_RUNTIME_DSN="postgresql://hnuhole_c_runtime@/hnuhole_c?host=$comment_text_socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_ALLOW_SCHEMA_RESET=1
export AUTHLAB_RUNTIME_TAG AUTHLAB_C_DSN AUTHLAB_V_DSN AUTHLAB_POSTS_RUNTIME_DSN AUTHLAB_ALLOW_SCHEMA_RESET
COMMENT_TEXT_GOOSE=$(command -v goose)
COMMENT_TEXT_UPGRADE_DSN="postgresql://hnuhole_c@/hnuhole_comments_upgrade?host=$comment_text_socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
COMMENT_TEXT_FRESH_DSN="postgresql://hnuhole_c@/hnuhole_comments_fresh?host=$comment_text_socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export COMMENT_TEXT_GOOSE COMMENT_TEXT_UPGRADE_DSN COMMENT_TEXT_FRESH_DSN
MODERATION_GOOSE=$COMMENT_TEXT_GOOSE
MODERATION_UPGRADE_DSN="postgresql://hnuhole_c@/hnuhole_moderation_upgrade?host=$comment_text_socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export MODERATION_GOOSE MODERATION_UPGRADE_DSN
comment_text_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$comment_text_script_dir/.."
go test -race -count=1 -p 1 ./internal/authprivacy ./internal/authprivacyhttp -run "${COMMENT_TEST_PATTERN:-^(TestCommentText|TestCommentBusiness|TestModerationGooseUpgradeAndDownRefusalPostgres$|TestPostSchemaFixedOwnershipAndTerminalStatePostgres$|TestPostSchemaModerationCleanupPrivilegesWithoutFeaturePostgres$|TestPostSchemaModerationAccountClosureWithoutFeaturePostgres$)}" -v
