#!/usr/bin/env bash
# Build only. Never invokes adb, a device task, SDK manager, or a database.
set -euo pipefail
umask 077
: "${STORAGE_ROOT:?owned new stage2 root}" "${STORAGE_REPO:?source repository}"
: "${F4_TASK_ROOT:?existing task-owned cache root}" "${F4_FLUTTER_ROOT:?exclusive SDK}"
: "${F4_SDK_OWNER_VALUE:?exclusive SDK marker}" "${JAVA_HOME:?owned JDK}" "${ANDROID_HOME:?owned Android SDK}"
: "${STORAGE_SQLITE_ASSET:?pinned ARM64 SQLite input}"
[[ $(realpath "$STORAGE_ROOT") == "$STORAGE_ROOT" && ! -L "$STORAGE_ROOT" ]] || exit 2
[[ $(cat "$STORAGE_ROOT/.owner") == HNUHOLE_COMMUNITY_ANDROID_STAGE2_V1 ]] || exit 2
[[ $(cat "$F4_TASK_ROOT/.owner") == "hnuhole-community-flutter-f4-01a11f1a-20261010|$STORAGE_REPO" ]] || exit 2
[[ $(cat "$(dirname "$F4_FLUTTER_ROOT")/.owner") == "$F4_SDK_OWNER_VALUE" ]] || exit 2
for owned in "$F4_FLUTTER_ROOT" "$F4_FLUTTER_ROOT/bin/cache" "$JAVA_HOME" "$ANDROID_HOME"; do
 [[ ! -L "$owned" && $(realpath "$owned") == "$owned" && "$owned" == "$(dirname "$F4_FLUTTER_ROOT")/"* ]] || exit 2
done
exec 9>"$F4_TASK_ROOT/community-build.lock"
flock -n 9 || { echo 'Another community build owns the cache; defer.' >&2; exit 2; }
for directory in home tmp android-user xdg-config xdg-cache xdg-data logs apks; do
 [[ ! -L "$STORAGE_ROOT/$directory" ]] || exit 2
 mkdir -p "$STORAGE_ROOT/$directory"
done
export HOME=$STORAGE_ROOT/home TMPDIR=$STORAGE_ROOT/tmp
export PUB_CACHE=$F4_TASK_ROOT/pub GRADLE_USER_HOME=$F4_TASK_ROOT/gradle
export XDG_CONFIG_HOME=$STORAGE_ROOT/xdg-config XDG_CACHE_HOME=$STORAGE_ROOT/xdg-cache XDG_DATA_HOME=$STORAGE_ROOT/xdg-data
export JAVA_TOOL_OPTIONS="-Duser.home=$STORAGE_ROOT/home"
export ANDROID_SDK_ROOT=$ANDROID_HOME ANDROID_USER_HOME=$STORAGE_ROOT/android-user
export ANDROID_EMULATOR_HOME=$STORAGE_ROOT/android-user ANDROID_AVD_HOME=$STORAGE_ROOT/android-user/avd
export GRADLE_OPTS="-Dorg.gradle.jvmargs='-Xmx2g -XX:MaxMetaspaceSize=1g -XX:ReservedCodeCacheSize=256m' -Dorg.gradle.workers.max=2 -Dorg.gradle.daemon=false"
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true PYTHONDONTWRITEBYTECODE=1
export PATH=$F4_FLUTTER_ROOT/bin:$JAVA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$F4_TASK_ROOT/sqlite${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
mirror=$STORAGE_ROOT/source
[[ ! -e "$mirror" && ! -L "$mirror" ]] || { echo 'Build mirror exists; inspect it before rebuilding.' >&2; exit 2; }
mkdir -m 700 "$mirror"
for directory in apps/mobile packages/auth_vault packages/auth_passkey packages/auth-protocol-vectors packages/post-protocol-vectors; do
 mkdir -p "$mirror/$directory"
 rsync -a --exclude=.dart_tool --exclude=build --exclude=.gradle --exclude=local.properties --exclude=.cxx "$STORAGE_REPO/$directory/" "$mirror/$directory/"
done
python3 - "$mirror" "$STORAGE_ROOT" <<'PY'
import json,secrets,sys
from pathlib import Path
mirror,root=map(Path,sys.argv[1:])
p=mirror/'apps/mobile/android/app/build.gradle.kts';s=p.read_text();old='applicationId = "org.hnuhole.hnuhole_mobile"';assert s.count(old)==1
p.write_text(s.replace(old,'applicationId = "org.hnuhole.hnuhole_mobile.communityf5.storage"'))
if (root/'test-maven').is_dir():
 p=mirror/'apps/mobile/android/build.gradle.kts';s=p.read_text();old='repositories {';assert old in s
 p.write_text(s.replace(old,old+'\n        maven { url = uri("'+str(root/'test-maven')+'") }',1))
for name,package in [('auth_vault','org.hnuhole.communityf5.storage.vault.test'),('auth_passkey','org.hnuhole.communityf5.storage.passkey.test')]:
 p=mirror/'packages'/name/'android/build.gradle.kts';s=p.read_text()
 old='testNamespace = "org.hnuhole.'+('authvault' if name=='auth_vault' else 'authpasskey')+'.test"';assert s.count(old)==1
 s=s.replace(old,'testNamespace = "'+package+'"')
 assert s.count('minSdk = 23')==1
 p.write_text(s.replace('minSdk = 23','minSdk = 23\n        testApplicationId = "'+package+'"'))
run='community-storage-'+secrets.token_hex(8)
(root/'build-config.json').write_text(json.dumps({'COMMUNITY_STORAGE_RUN_ID':run})+'\n')
PY
cd "$mirror/apps/mobile"
flutter pub get --offline --enforce-lockfile > "$STORAGE_ROOT/logs/pub.log" 2>&1
dart format integration_test/community_android_storage_test.dart > "$STORAGE_ROOT/logs/format.log" 2>&1
cp integration_test/community_android_storage_test.dart "$STORAGE_REPO/apps/mobile/integration_test/community_android_storage_test.dart"
flutter analyze --no-pub > "$STORAGE_ROOT/logs/analyze.log" 2>&1
flutter test --no-pub --machine test > "$STORAGE_ROOT/logs/mobile-tests.jsonl" 2>&1
cache=.dart_tool/hooks_runner/shared/sqlite3/build/download-0c2d3bfc
mkdir -p "$cache"
[[ $(sha256sum "$STORAGE_SQLITE_ASSET" | cut -d' ' -f1) == 0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161 ]] || exit 2
cp "$STORAGE_SQLITE_ASSET" "$cache/libsqlite3.so"
flutter build apk --debug --no-pub --target-platform android-arm64 --target integration_test/community_android_storage_test.dart --dart-define-from-file="$STORAGE_ROOT/build-config.json" > "$STORAGE_ROOT/logs/app-build.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$STORAGE_ROOT/apks/storage.apk"
cd android
./gradlew --offline --no-daemon --max-workers=2 :hnuhole_auth_vault:assembleDebugAndroidTest :hnuhole_auth_passkey:assembleDebugAndroidTest > "$STORAGE_ROOT/logs/instrumentation-build.log" 2>&1
cd ..
for pair in 'hnuhole_auth_vault vault' 'hnuhole_auth_passkey passkey'; do
 read -r module name <<< "$pair"
 mapfile -t candidates < <(find "build/$module/outputs/apk/androidTest" -name '*-debug-androidTest.apk' -type f)
 [[ ${#candidates[@]} == 1 ]] || exit 2
 cp "${candidates[0]}" "$STORAGE_ROOT/apks/$name.apk"
done
cmp "$STORAGE_REPO/apps/mobile/pubspec.lock" pubspec.lock
echo 'Stage2 analyzer/mobile and three isolated Debug APK builds completed. Device tests NOT_RUN.'
