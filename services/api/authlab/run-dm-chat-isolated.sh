#!/bin/sh
# Owned private-socket P2 SQL fixture. No external DSN is accepted.
set -eu
umask 077
: "${POST_MEDIA_PYTHON:?existing pinned Pillow environment required}"
: "${COMMENT_TEXT_GOOSE:?existing goose executable required}"
export PATH="/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:$PATH"
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d /tmp/hnuhole-dm-p2.XXXXXX)
pg(){ if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }
cleanup(){ status=$?; pg pg_ctl -D "$work/data" -m fast -w stop >/dev/null 2>&1 || true; printf 'P2 fixture stopped: %s (logs retained)\n' "$work"; exit "$status"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
mkdir "$work/socket" "$work/fixtures"
if [ "$(id -u)" = 0 ]; then chown postgres:postgres "$work" "$work/socket"; fi
pg initdb -D "$work/data" -U dm_p2_admin -A trust --no-locale -E UTF8 >"$work/init.log" 2>&1
pg pg_ctl -D "$work/data" -l "$work/postgres.log" -w start -o "-c listen_addresses='' -c unix_socket_directories='$work/socket' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=50 -c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0" >/dev/null
psql -X -v ON_ERROR_STOP=1 -h "$work/socket" -U dm_p2_admin -d postgres >/dev/null <<'SQL'
CREATE ROLE hnuhole_c LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_v LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_c_recovery NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE hnuhole_business NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE hnuhole_c OWNER hnuhole_c;
CREATE DATABASE hnuhole_v OWNER hnuhole_v;
CREATE DATABASE hnuhole_comments_fresh OWNER hnuhole_c;
CREATE DATABASE hnuhole_comments_upgrade OWNER hnuhole_c;
REVOKE CONNECT ON DATABASE hnuhole_c FROM PUBLIC;
REVOKE CONNECT ON DATABASE hnuhole_v FROM PUBLIC;
GRANT CONNECT ON DATABASE hnuhole_c TO hnuhole_c,hnuhole_c_runtime;
GRANT CONNECT ON DATABASE hnuhole_v TO hnuhole_v;
SQL
export AUTHLAB_RUNTIME_TAG="hnuhole_authlab_dm_p2_$(date -u +%Y%m%d%H%M%S)"
export AUTHLAB_ALLOW_SCHEMA_RESET=1
export AUTHLAB_C_DSN="postgresql://hnuhole_c@/hnuhole_c?host=$work/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export AUTHLAB_V_DSN="postgresql://hnuhole_v@/hnuhole_v?host=$work/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export AUTHLAB_POSTS_RUNTIME_DSN="postgresql://hnuhole_c_runtime@/hnuhole_c?host=$work/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export COMMENT_TEXT_FRESH_DSN="postgresql://hnuhole_c@/hnuhole_comments_fresh?host=$work/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export COMMENT_TEXT_UPGRADE_DSN="postgresql://hnuhole_c@/hnuhole_comments_upgrade?host=$work/socket&application_name=$AUTHLAB_RUNTIME_TAG&sslmode=disable"
export POST_MEDIA_VALIDATOR="$work/validate_image.py"
export POST_MEDIA_FIXTURES="$work/fixtures"
cp "$root/media/validate_image.py" "$POST_MEDIA_VALIDATOR"
chmod 600 "$POST_MEDIA_VALIDATOR"
"$POST_MEDIA_PYTHON" - "$work" <<'PY'
import sys, pathlib, subprocess
from PIL import Image
p=pathlib.Path(sys.argv[1]); image=Image.new('RGB',(7,5),(31,173,88)); image.save(p/'fixtures/png.bin',format='PNG')
with (p/'fixtures/png.bin').open('rb') as source:
    r=subprocess.run([sys.executable,'-I','-B',str(p/'validate_image.py')],stdin=source,stdout=subprocess.PIPE,check=True)
(p/'fixtures/png.json').write_bytes(r.stdout)
PY
cd "$root"
go test -timeout=35m -race -count=1 -p 1 ./internal/authprivacy ./internal/authprivacyhttp -run "${DM_CHAT_TEST_PATTERN:-^(TestDMChat|TestDMFirstContact|TestDMReliableText|TestDMGoose)}" -v >"$work/tests.log" 2>&1 || { cat "$work/tests.log"; exit 1; }
cat "$work/tests.log"
