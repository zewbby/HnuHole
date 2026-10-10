#!/usr/bin/env bash
# Current frontend + committed backend; owned host caches/PG only, no device use.
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/.." && pwd)
TASK_ROOT=${F4_TASK_ROOT:-/tmp/hnuhole-community-flutter-f4-01a11f1a-20261010}
OWNER=hnuhole-community-flutter-f4-01a11f1a-20261010
FLUTTER_ROOT=${F4_FLUTTER_ROOT:-/mnt/d/zewbbyTest/Hnuhole-env/linux/flutter}
case "$TASK_ROOT" in /tmp/hnuhole-community-flutter-f4-*) ;; *) echo 'Unexpected F4 root' >&2;exit 2;; esac
[[ ! -L "$TASK_ROOT" ]] || { echo 'Linked F4 root rejected' >&2; exit 2; }
if [[ -e "$TASK_ROOT" ]]; then
 [[ -f "$TASK_ROOT/.owner" && $(cat "$TASK_ROOT/.owner") == "$OWNER|$SOURCE" ]] || { echo 'Unowned F4 root' >&2;exit 2; }
else
 mkdir -m 700 "$TASK_ROOT";printf '%s' "$OWNER|$SOURCE" > "$TASK_ROOT/.owner"
fi
[[ $(realpath "$TASK_ROOT") == "$TASK_ROOT" ]] || { echo 'Noncanonical F4 root' >&2;exit 2; }
mkdir -p "$TASK_ROOT/tmp" "$TASK_ROOT/source" "$TASK_ROOT/sqlite"
export TMPDIR=$TASK_ROOT/tmp PUB_CACHE=$TASK_ROOT/pub GOCACHE=$TASK_ROOT/go-build
export PUB_HOSTED_URL=https://pub.dev GOPROXY=https://goproxy.cn,direct
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PATH=$FLUTTER_ROOT/bin:/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:$PATH
export LD_LIBRARY_PATH=$TASK_ROOT/sqlite${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true
ln -sfn /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 "$TASK_ROOT/sqlite/libsqlite3.so"
prepare() {
 for directory in apps/mobile packages/auth_vault packages/auth_passkey packages/auth-protocol-vectors packages/post-protocol-vectors services/api; do
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
 *) echo 'Use prepare/format/checks/integration/auth-regression/server' >&2;exit 2;;
esac
