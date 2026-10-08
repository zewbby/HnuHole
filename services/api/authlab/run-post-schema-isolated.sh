#!/bin/sh
# 仅创建本次临时 PostgreSQL 私有 socket fixture；不接收外部 DSN，不安装工具。
set -eu
umask 077
for post_schema_tool in go initdb pg_ctl psql; do
    command -v "$post_schema_tool" >/dev/null 2>&1 || { echo "Missing tool: $post_schema_tool" >&2; exit 1; }
done
post_schema_dir=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-post-schema.XXXXXX")
case "$post_schema_dir" in *[!A-Za-z0-9_./-]*) echo 'Unsupported temporary path' >&2; exit 1 ;; esac
mkdir "$post_schema_dir/socket"
post_schema_cleanup() {
    post_schema_status=$?
    pg_ctl -D "$post_schema_dir/data" -m fast -w stop >/dev/null 2>&1 || true
    rm -rf "$post_schema_dir"
    exit "$post_schema_status"
}
trap post_schema_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
initdb -D "$post_schema_dir/data" -U post_schema_admin -A trust --no-locale -E UTF8 >"$post_schema_dir/init.log" 2>&1
pg_ctl -D "$post_schema_dir/data" -l "$post_schema_dir/postgres.log" -w start \
    -o "-c listen_addresses='' -c unix_socket_directories='$post_schema_dir/socket' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=40 -c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic -c log_error_verbosity=terse -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0 -c log_min_duration_statement=-1 -c log_min_duration_sample=-1 -c log_transaction_sample_rate=0 -c log_duration=off" >/dev/null
psql -X -v ON_ERROR_STOP=1 -h "$post_schema_dir/socket" -U post_schema_admin -d postgres >/dev/null <<'SQL'
CREATE ROLE hnuhole_c LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_v LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_recovery NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_business NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE hnuhole_c OWNER hnuhole_c;
CREATE DATABASE hnuhole_v OWNER hnuhole_v;
REVOKE CONNECT ON DATABASE hnuhole_c FROM PUBLIC;
REVOKE CONNECT ON DATABASE hnuhole_v FROM PUBLIC;
GRANT CONNECT ON DATABASE hnuhole_c TO hnuhole_c,hnuhole_c_runtime;
GRANT CONNECT ON DATABASE hnuhole_v TO hnuhole_v;
SQL
AUTHLAB_RUNTIME_TAG="hnuhole_authlab_post_schema_$(date -u +%Y%m%d%H%M%S)"
AUTHLAB_C_DSN="postgresql://hnuhole_c@/hnuhole_c?host=$post_schema_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_V_DSN="postgresql://hnuhole_v@/hnuhole_v?host=$post_schema_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_POSTS_RUNTIME_DSN="postgresql://hnuhole_c_runtime@/hnuhole_c?host=$post_schema_dir/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
AUTHLAB_ALLOW_SCHEMA_RESET=1
export AUTHLAB_RUNTIME_TAG AUTHLAB_C_DSN AUTHLAB_V_DSN AUTHLAB_POSTS_RUNTIME_DSN AUTHLAB_ALLOW_SCHEMA_RESET
post_schema_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$post_schema_script_dir/.."
go test -race -count=1 -p 1 ./internal/authprivacy -run '^TestPostSchema' -v
