#!/usr/bin/env bash
set -euo pipefail
umask 077
source /mnt/e/HnuHole-community-f4-20261012/stage1-preparation-20261014/env.sh
work=/home/hnuhole/community-android-stage3-execution-20261015
out=/mnt/e/HnuHole-community-f4-20261012/stage3-execution-20261015
[[ $(cat "$work/.owner") == HNUHOLE_COMMUNITY_ANDROID_STAGE3_EXECUTION_20261015_V1 ]]
[[ -f "$out/device-window-ended.json" && ! -e "$out/post-reset-host.started" ]]
exec 9>"$F4_TASK_ROOT/community-build.lock";flock -n 9 || exit 2
touch "$out/post-reset-host.started"
export HOME=$work/home TMPDIR=$work/tmp PUB_CACHE=$F4_TASK_ROOT/pub
export XDG_CONFIG_HOME=$work/xdg-config XDG_CACHE_HOME=$work/xdg-cache XDG_DATA_HOME=$work/xdg-data
export LD_LIBRARY_PATH=$F4_TASK_ROOT/sqlite
export PATH=$F4_FLUTTER_ROOT/bin:$JAVA_HOME/bin:$PATH
cp "$out/owned_stage3_post_reset_test.dart" "$work/source/apps/mobile/integration/owned_stage3_post_reset_test.dart"
cd "$work/source/apps/mobile"
flutter test --no-pub --machine integration/owned_stage3_post_reset_test.dart > "$out/logs/post-reset-host.private.jsonl" 2> "$out/logs/post-reset-host.private.stderr.log"
echo 'Owned real-C old-password/old-code/old-session checks completed; no new login session created.'
