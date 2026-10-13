#!/usr/bin/env bash
# Current frontend + committed backend; owned host caches/PG only, no device use.
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/.." && pwd)
: "${F4_TASK_ROOT:?Set F4_TASK_ROOT to this task's new private /tmp directory}"
: "${F4_FLUTTER_ROOT:?Set F4_FLUTTER_ROOT to this task's independent Flutter SDK copy}"
TASK_ROOT=$F4_TASK_ROOT
USER_TASK_HOME=$(getent passwd "$(id -u)" | cut -d: -f6)
[[ -d "$USER_TASK_HOME" && $(realpath "$USER_TASK_HOME") == "$USER_TASK_HOME" ]] || { echo 'Noncanonical user home' >&2; exit 2; }
OWNER=hnuhole-community-flutter-f4-01a11f1a-20261010
FLUTTER_ROOT=$F4_FLUTTER_ROOT
: "${F4_SDK_OWNER_VALUE:?Set F4_SDK_OWNER_VALUE to the dedicated SDK ownership marker}"
SDK_OWNER_FILE=${F4_SDK_OWNER_FILE:-$(dirname "$FLUTTER_ROOT")/.owner}
GO_BIN_DIR=${F4_GO_BIN_DIR:-/usr/lib/go-1.22/bin}
POSTGRES_BIN_DIR=${F4_PG_BIN_DIR:-/usr/lib/postgresql/16/bin}
SQLITE_LIBRARY=${F4_SQLITE_LIBRARY:-/usr/lib/x86_64-linux-gnu/libsqlite3.so.0}
POSTGRES_PORT=${F4_PG_PORT:-55432}
[[ $POSTGRES_PORT =~ ^[1-9][0-9]{3,4}$ && $POSTGRES_PORT -ge 1024 && $POSTGRES_PORT -le 65535 ]] || { echo 'Invalid F4 PG port' >&2; exit 2; }
[[ ! -L "$FLUTTER_ROOT" && -x "$FLUTTER_ROOT/bin/flutter" && $(realpath "$FLUTTER_ROOT") == "$FLUTTER_ROOT" ]] || { echo 'Noncanonical or unavailable Flutter SDK' >&2; exit 2; }
[[ ! -L "$SDK_OWNER_FILE" && -f "$SDK_OWNER_FILE" && $(cat "$SDK_OWNER_FILE") == "$F4_SDK_OWNER_VALUE" ]] || { echo 'Unowned Flutter SDK rejected' >&2; exit 2; }
[[ -d "$FLUTTER_ROOT/bin/cache" && $(realpath "$FLUTTER_ROOT/bin/cache") == "$FLUTTER_ROOT/bin/cache" && -z $(find "$FLUTTER_ROOT/bin/cache" -type l -print -quit) ]] || { echo 'Linked or missing Flutter cache rejected' >&2; exit 2; }
[[ -f "$SQLITE_LIBRARY" ]] || { echo 'SQLite shared library unavailable' >&2; exit 2; }
case "$TASK_ROOT" in /tmp/hnuhole-community-flutter-f4-*|"$USER_TASK_HOME"/hnuhole-community-flutter-f4-*) ;; *) echo 'Unexpected F4 root' >&2;exit 2;; esac
[[ ! -L "$TASK_ROOT" ]] || { echo 'Linked F4 root rejected' >&2; exit 2; }
# Reject traversal and linked ancestors before mkdir or ownership-marker writes.
[[ $(realpath -m "$TASK_ROOT") == "$TASK_ROOT" ]] || { echo 'Noncanonical F4 root' >&2; exit 2; }
if [[ -e "$TASK_ROOT" ]]; then
 [[ -f "$TASK_ROOT/.owner" && $(cat "$TASK_ROOT/.owner") == "$OWNER|$SOURCE" ]] || { echo 'Unowned F4 root' >&2;exit 2; }
else
 mkdir -m 700 "$TASK_ROOT";printf '%s' "$OWNER|$SOURCE" > "$TASK_ROOT/.owner"
fi
[[ $(realpath "$TASK_ROOT") == "$TASK_ROOT" ]] || { echo 'Noncanonical F4 root' >&2;exit 2; }
for directory in tmp source sqlite home pub go-build go-path go-mod gradle xdg-config xdg-cache xdg-data xdg-runtime; do
 [[ ! -L "$TASK_ROOT/$directory" ]] || { echo 'Linked F4 child rejected' >&2; exit 2; }
 mkdir -p "$TASK_ROOT/$directory"
done
chmod 700 "$TASK_ROOT/home" "$TASK_ROOT/xdg-runtime"
# Do not inherit a database address, fixture opt-in or client config from another
# session. The lower runners generate fresh private-socket DSNs themselves.
for inherited in ${!PG@} ${!AUTHLAB_@} ${!AUTHRUNTIME_@} ${!F4_MAIN_@}; do
 unset "$inherited"
done
unset F4_EVIDENCE_DIR
export HOME=$TASK_ROOT/home TMPDIR=$TASK_ROOT/tmp GOTMPDIR=$TASK_ROOT/tmp PUB_CACHE=$TASK_ROOT/pub GOCACHE=$TASK_ROOT/go-build
export XDG_CONFIG_HOME=$TASK_ROOT/xdg-config XDG_CACHE_HOME=$TASK_ROOT/xdg-cache XDG_DATA_HOME=$TASK_ROOT/xdg-data XDG_RUNTIME_DIR=$TASK_ROOT/xdg-runtime
export GOPATH=$TASK_ROOT/go-path GOMODCACHE=$TASK_ROOT/go-mod GRADLE_USER_HOME=$TASK_ROOT/gradle
export GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOWORK=off PGPORT=$POSTGRES_PORT
export PUB_HOSTED_URL=https://pub.dev GOPROXY=https://goproxy.cn,direct
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PATH=$FLUTTER_ROOT/bin:$GO_BIN_DIR:$POSTGRES_BIN_DIR:$PATH
export LD_LIBRARY_PATH=$TASK_ROOT/sqlite${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true
ln -sfn "$SQLITE_LIBRARY" "$TASK_ROOT/sqlite/libsqlite3.so"
prepare() {
 for directory in apps/mobile packages/auth_vault packages/auth_passkey packages/auth-protocol-vectors packages/post-protocol-vectors services/api infra/postgres; do
  mkdir -p "$TASK_ROOT/source/$directory"
  rsync -a --exclude=.dart_tool --exclude=build --exclude=.gradle --exclude=local.properties --exclude=.cxx --exclude=__pycache__ "$SOURCE/$directory/" "$TASK_ROOT/source/$directory/"
 done
 python3 - "$TASK_ROOT/source" <<'PYLF'
import sys
from pathlib import Path
for p in Path(sys.argv[1]).rglob('*.sh'):
 p.write_bytes(p.read_bytes().replace(b'\r\n',b'\n'))
PYLF
 cd "$TASK_ROOT/source/apps/mobile"
 if ! flutter pub get --offline --enforce-lockfile > "$TASK_ROOT/pub-get.log" 2>&1;then flutter pub get --enforce-lockfile > "$TASK_ROOT/pub-get.log" 2>&1;fi
}
case "${1:-}" in
 prepare) prepare;;
 format)
  prepare
  dart format lib/main.dart lib/src/identity/settings_screen.dart integration/f4_main_https_postgres_test.dart
  cp lib/main.dart "$SOURCE/apps/mobile/lib/main.dart"
  cp lib/src/identity/settings_screen.dart "$SOURCE/apps/mobile/lib/src/identity/settings_screen.dart"
  cp integration/f4_main_https_postgres_test.dart "$SOURCE/apps/mobile/integration/f4_main_https_postgres_test.dart"
  cd "$TASK_ROOT/source/services/api"
  gofmt -w internal/authprivacyhttp/f4_main_mobile_postgres_test.go
  cp internal/authprivacyhttp/f4_main_mobile_postgres_test.go "$SOURCE/services/api/internal/authprivacyhttp/f4_main_mobile_postgres_test.go";;
 checks)
  prepare
  flutter analyze --no-pub > "$TASK_ROOT/analyze.log" 2>&1 || { cat "$TASK_ROOT/analyze.log";exit 1; }
  cat "$TASK_ROOT/analyze.log"
  flutter test --no-pub --machine test > "$TASK_ROOT/mobile-tests.jsonl" 2>&1 || { tail -n 25 "$TASK_ROOT/mobile-tests.jsonl";exit 1; }
  echo 'Mobile machine run completed';;
 integration|auth-regression)
  mode=$1;prepare;cd "$TASK_ROOT/source/services/api"
  export AUTHLAB_MOBILE_FLUTTER=$FLUTTER_ROOT/bin/flutter
  if [[ $mode == integration ]];then
   export F4_MAIN_FLUTTER=$AUTHLAB_MOBILE_FLUTTER F4_EVIDENCE_DIR=$TASK_ROOT
   export AUTHLAB_MOBILE_TEST_PATTERN='^TestF4MainAppHTTPSPostgres$'
  else unset AUTHLAB_MOBILE_TEST_PATTERN F4_MAIN_FLUTTER;fi
  bash authlab/run-mobile-isolated.sh > "$TASK_ROOT/$mode.log" 2>&1 || { tail -n 60 "$TASK_ROOT/$mode.log";exit 1; }
  tail -n 10 "$TASK_ROOT/$mode.log";;
 server)
  prepare;cd "$TASK_ROOT/source/services/api"
  env -u AUTHLAB_MOBILE_FLUTTER -u F4_MAIN_FLUTTER bash authlab/run-isolated.sh > "$TASK_ROOT/server.log" 2>&1 || { tail -n 40 "$TASK_ROOT/server.log";exit 1; }
  tail -n 16 "$TASK_ROOT/server.log";;
 posts-privileges)
  prepare;cd "$TASK_ROOT/source/services/api"
  bash authlab/run-post-schema-isolated.sh > "$TASK_ROOT/posts-privileges.log" 2>&1 || { tail -n 40 "$TASK_ROOT/posts-privileges.log";exit 1; }
  tail -n 16 "$TASK_ROOT/posts-privileges.log";;
 vet)
  prepare;cd "$TASK_ROOT/source/services/api"
  go vet ./... > "$TASK_ROOT/vet.log" 2>&1 || { cat "$TASK_ROOT/vet.log";exit 1; }
  echo 'Final Go vet completed';;
 *) echo 'Use prepare/format/checks/integration/auth-regression/server/posts-privileges/vet' >&2;exit 2;;
esac
