#!/usr/bin/env bash
# Host widget/file-store checks only; no SQL servers or device deployment.
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/.." && pwd)
TASK_ROOT=${F3_TASK_ROOT:-/tmp/hnuhole-community-flutter-f3-01a11f1a}
FLUTTER_ROOT=${F3_FLUTTER_ROOT:-/mnt/d/zewbbyTest/Hnuhole-env/linux/flutter}
OWNER=hnuhole-community-flutter-f3-01a11f1a
case "$TASK_ROOT" in /tmp/hnuhole-community-flutter-f3-*) ;; *) echo 'Unexpected task root' >&2; exit 2;; esac
if [[ -e "$TASK_ROOT" ]]; then
  [[ -f "$TASK_ROOT/.owner" && $(cat "$TASK_ROOT/.owner") == "$OWNER" ]] || { echo 'Unknown task root' >&2; exit 2; }
else
  mkdir -p "$TASK_ROOT"
  printf '%s' "$OWNER" > "$TASK_ROOT/.owner"
fi
mkdir -p "$TASK_ROOT/tmp"
export TMPDIR="$TASK_ROOT/tmp"
export PUB_CACHE="$TASK_ROOT/pub"
export PUB_HOSTED_URL=https://pub.dev
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PATH="$FLUTTER_ROOT/bin:$PATH"
mkdir -p "$TASK_ROOT/source/apps/mobile" "$TASK_ROOT/source/packages" "$TASK_ROOT/sqlite"
ln -sfn /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 "$TASK_ROOT/sqlite/libsqlite3.so"
export LD_LIBRARY_PATH="$TASK_ROOT/sqlite:${LD_LIBRARY_PATH:-}"
prepare() {
  rsync -a --exclude=.dart_tool --exclude=build --exclude=.gradle --exclude=local.properties --exclude=android/.cxx "$SOURCE/apps/mobile/" "$TASK_ROOT/source/apps/mobile/"
  for package in auth_vault auth_passkey post-protocol-vectors auth-protocol-vectors; do
    mkdir -p "$TASK_ROOT/source/packages/$package"
    rsync -a --exclude=.dart_tool --exclude=build --exclude=.gradle "$SOURCE/packages/$package/" "$TASK_ROOT/source/packages/$package/"
  done
  cd "$TASK_ROOT/source/apps/mobile"
  if ! flutter pub get --offline --enforce-lockfile > "$TASK_ROOT/pub-get.log" 2>&1; then
    flutter pub get --enforce-lockfile > "$TASK_ROOT/pub-get.log" 2>&1
  fi
}
case "${1:-test}" in
  prepare) prepare;;
  analyze) prepare; if ! flutter analyze --no-pub > "$TASK_ROOT/analyze.log" 2>&1; then cat "$TASK_ROOT/analyze.log"; exit 1; fi; cat "$TASK_ROOT/analyze.log";;
  test) prepare; shift || true; if ! flutter test --no-pub --reporter expanded "${@:-test}" > "$TASK_ROOT/tests.log" 2>&1; then tail -n 70 "$TASK_ROOT/tests.log"; exit 1; fi; tail -n 6 "$TASK_ROOT/tests.log";;
  machine) prepare; shift || true; flutter test --no-pub --machine "${@:-test}" > "$TASK_ROOT/tests-machine.jsonl" 2>&1;;
  format|format-check)
    mode=$1
    prepare
    files=(lib/main.dart lib/hnuhole_mobile.dart lib/src/config lib/src/posts
      lib/src/storage/post_store.dart lib/src/auth/auth_flows.dart
      lib/src/auth/auth_state_codec.dart test/post*.dart test/mobile_environment_test.dart)
    if [[ "$mode" == format-check ]]; then
      dart format --output=none --set-exit-if-changed "${files[@]}"
    else
      dart format "${files[@]}"
      for file in "${files[@]}"; do
        if [[ -d "$file" ]]; then rsync -a "$file/" "$SOURCE/apps/mobile/$file/";
        else cp "$file" "$SOURCE/apps/mobile/$file"; fi
      done
    fi;;
  *) echo 'Use prepare/analyze/test/machine/format/format-check' >&2; exit 2;;
esac
