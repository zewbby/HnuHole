#!/usr/bin/env bash
# Build unconfigured review candidates only. No RP/security setting is applied.
set -euo pipefail
umask 077
: "${PASSKEY_ROOT:?new owned task3 root}" "${PASSKEY_REPO:?source repository}"
: "${F4_TASK_ROOT:?community-owned cache root}" "${F4_FLUTTER_ROOT:?exclusive SDK}"
: "${F4_SDK_OWNER_VALUE:?SDK owner}" "${JAVA_HOME:?owned JDK}" "${ANDROID_HOME:?owned SDK}"
: "${PASSKEY_SQLITE_ASSET:?pinned existing ARM64 SQLite}"
[[ $(realpath "$PASSKEY_ROOT") == "$PASSKEY_ROOT" && ! -L "$PASSKEY_ROOT" && $(cat "$PASSKEY_ROOT/.owner") == HNUHOLE_COMMUNITY_ANDROID_STAGE3_V1 ]] || exit 2
[[ $(cat "$F4_TASK_ROOT/.owner") == "hnuhole-community-flutter-f4-01a11f1a-20261010|$PASSKEY_REPO" ]] || exit 2
[[ $(cat "$(dirname "$F4_FLUTTER_ROOT")/.owner") == "$F4_SDK_OWNER_VALUE" ]] || exit 2
for owned in "$F4_FLUTTER_ROOT" "$F4_FLUTTER_ROOT/bin/cache" "$JAVA_HOME" "$ANDROID_HOME"; do
 [[ ! -L "$owned" && $(realpath "$owned") == "$owned" && "$owned" == "$(dirname "$F4_FLUTTER_ROOT")/"* ]] || exit 2
done
exec 9>"$F4_TASK_ROOT/community-build.lock"
flock -n 9 || { echo 'Another community build is active; defer.' >&2; exit 2; }
for directory in home tmp android-user xdg-config xdg-cache xdg-data logs apks; do
 [[ ! -L "$PASSKEY_ROOT/$directory" ]] || exit 2
 mkdir -p "$PASSKEY_ROOT/$directory"
done
export HOME=$PASSKEY_ROOT/home TMPDIR=$PASSKEY_ROOT/tmp PUB_CACHE=$F4_TASK_ROOT/pub GRADLE_USER_HOME=$F4_TASK_ROOT/gradle
export XDG_CONFIG_HOME=$PASSKEY_ROOT/xdg-config XDG_CACHE_HOME=$PASSKEY_ROOT/xdg-cache XDG_DATA_HOME=$PASSKEY_ROOT/xdg-data
export JAVA_TOOL_OPTIONS="-Duser.home=$PASSKEY_ROOT/home"
export ANDROID_SDK_ROOT=$ANDROID_HOME ANDROID_USER_HOME=$PASSKEY_ROOT/android-user
export ANDROID_EMULATOR_HOME=$PASSKEY_ROOT/android-user ANDROID_AVD_HOME=$PASSKEY_ROOT/android-user/avd
export GRADLE_OPTS="-Dorg.gradle.jvmargs='-Xmx2g -XX:MaxMetaspaceSize=1g -XX:ReservedCodeCacheSize=256m' -Dorg.gradle.workers.max=2 -Dorg.gradle.daemon=false"
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true PYTHONDONTWRITEBYTECODE=1
export PATH=$F4_FLUTTER_ROOT/bin:$JAVA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$F4_TASK_ROOT/sqlite${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
mirror=$PASSKEY_ROOT/source
[[ ! -e "$mirror" && ! -L "$mirror" ]] || { echo 'Preserve existing candidate; do not overwrite.' >&2; exit 2; }
mkdir -m 700 "$mirror"
for directory in apps/mobile packages/auth_vault packages/auth_passkey packages/auth-protocol-vectors packages/post-protocol-vectors; do
 mkdir -p "$mirror/$directory"
 rsync -a --exclude=.dart_tool --exclude=build --exclude=.gradle --exclude=local.properties --exclude=.cxx "$PASSKEY_REPO/$directory/" "$mirror/$directory/"
done
python3 - "$mirror" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])/'apps/mobile/android/app/build.gradle.kts';s=p.read_text();old='applicationId = "org.hnuhole.hnuhole_mobile"';assert s.count(old)==1
p.write_text(s.replace(old,'applicationId = "org.hnuhole.hnuhole_mobile.communityf5.passkey"'))
PY
cd "$mirror/apps/mobile"
flutter pub get --offline --enforce-lockfile > "$PASSKEY_ROOT/logs/pub.log" 2>&1
flutter analyze --no-pub > "$PASSKEY_ROOT/logs/analyze.log" 2>&1
cache=.dart_tool/hooks_runner/shared/sqlite3/build/download-0c2d3bfc
mkdir -p "$cache"
[[ $(sha256sum "$PASSKEY_SQLITE_ASSET" | cut -d' ' -f1) == 0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161 ]] || exit 2
cp "$PASSKEY_SQLITE_ASSET" "$cache/libsqlite3.so"
flutter build apk --debug --no-pub --target-platform android-arm64 --target lib/main.dart > "$PASSKEY_ROOT/logs/control-build.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$PASSKEY_ROOT/apks/control-unconfigured.apk"
python3 - "$mirror" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])/'apps/mobile/android/app/build.gradle.kts';s=p.read_text();old='applicationId = "org.hnuhole.hnuhole_mobile.communityf5.passkey"';assert s.count(old)==1
p.write_text(s.replace(old,'applicationId = "org.hnuhole.hnuhole_mobile.communityf5.passkey.unassociated"'))
PY
flutter build apk --debug --no-pub --target-platform android-arm64 --target lib/main.dart > "$PASSKEY_ROOT/logs/unassociated-build.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$PASSKEY_ROOT/apks/unassociated-unconfigured.apk"
cmp "$PASSKEY_REPO/apps/mobile/pubspec.lock" pubspec.lock
# The library package intentionally has no tracked lockfile. Compile/run its
# tests using the already locked mobile dependency graph; do not resolve again.
flutter test --no-pub --machine ../../packages/auth_passkey/test/native_passkey_client_test.dart > "$PASSKEY_ROOT/logs/passkey-dart-tests.jsonl" 2>&1
mkdir "$PASSKEY_ROOT/jvm-classes"
javac -d "$PASSKEY_ROOT/jvm-classes" "$PASSKEY_REPO/apps/mobile/android/app/src/debug/java/org/hnuhole/hnuhole_mobile/GoogleFidoDiagnosticPolicy.java" "$PASSKEY_REPO/tools/android-passkey-diagnostic/GoogleFidoDiagnosticPolicyTest.java"
java -cp "$PASSKEY_ROOT/jvm-classes" org.hnuhole.hnuhole_mobile.GoogleFidoDiagnosticPolicyTest > "$PASSKEY_ROOT/logs/jvm-policy.log" 2>&1
echo 'PASS: review baseline and unassociated Debug APKs, Passkey Dart tests, JVM policy. RP association NOT_CONFIGURED; device NOT_RUN.'
