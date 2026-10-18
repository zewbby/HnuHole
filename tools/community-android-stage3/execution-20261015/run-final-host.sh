#!/usr/bin/env bash
set -euo pipefail
umask 077
source /mnt/e/HnuHole-community-f4-20261012/stage1-preparation-20261014/env.sh
repo=/mnt/e/HnuHole-community-f4-20261012/repo
out=/mnt/e/HnuHole-community-f4-20261012/stage3-execution-20261015
[[ $(cat "$out/.owner") == HNUHOLE_COMMUNITY_ANDROID_STAGE3_EXECUTION_20261015_V1 ]]
[[ $(cat "$F4_TASK_ROOT/.owner") == "hnuhole-community-flutter-f4-01a11f1a-20261010|$repo" ]]
[[ $(cat "$(dirname "$F4_FLUTTER_ROOT")/.owner") == community-android-stage1-20261014 ]]
[[ -f "$out/device-window-ended.json" && ! -e "$out/final-host.started" ]]
[[ $(git -c safe.directory="$repo" -C "$repo" rev-parse HEAD) == 9dda242b21694af1c4c33f11784958851c805fc4 ]]
exec 9>"$F4_TASK_ROOT/community-build.lock";flock -n 9 || { echo 'Community SDK busy; defer';exit 2; }
touch "$out/final-host.started"
mkdir -p "$out/logs/final-host"
for stage in checks auth-regression integration server posts-privileges auth-runtime vet;do
 started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
 set +e
 bash "$repo/tools/run-community-flutter-f4-linux.sh" "$stage" > "$out/logs/final-host/$stage.console.log" 2>&1
 result=$?
 set -e
 printf '%s\t%s\t%s\t%s\n' "$stage" "$started" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$result" >> "$out/logs/final-host/commands.tsv"
 if [[ $stage == checks ]];then cp "$F4_TASK_ROOT/mobile-tests.jsonl" "$out/logs/final-host/mobile-tests.jsonl";cp "$F4_TASK_ROOT/analyze.log" "$out/logs/final-host/analyze.log";else cp "$F4_TASK_ROOT/$stage.log" "$out/logs/final-host/$stage.log";fi
 echo "$stage exit=$result"
 [[ $result -eq 0 ]] || { tail -n 15 "$out/logs/final-host/$stage.console.log";exit "$result"; }
done
echo 'All seven final host stages completed.'
