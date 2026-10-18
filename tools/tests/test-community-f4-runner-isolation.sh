#!/usr/bin/env bash
# Exercises orchestration with synthetic executables; no SDK, Go or PG starts.
set -euo pipefail
runner=$(cd "$(dirname "$0")/../.." && pwd)/tools/run-community-flutter-f4-linux.sh
fixture=$(mktemp -d /tmp/hnuhole-community-flutter-f4-audit-fixture.XXXXXX)
user_home=$(getent passwd "$(id -u)" | cut -d: -f6)
home_fixture=
printf '%s' 'community-f4-runner-audit' > "$fixture/.audit-owner"
cleanup() {
 case "$fixture" in /tmp/hnuhole-community-flutter-f4-audit-fixture.*) ;; *) exit 91;; esac
 [[ ! -L "$fixture" && $(realpath "$fixture") == "$fixture" && $(cat "$fixture/.audit-owner") == community-f4-runner-audit ]] || exit 92
 rm -rf -- "$fixture"
 if [[ -n "$home_fixture" ]]; then
  case "$home_fixture" in "$user_home"/hnuhole-community-flutter-f4-audit-fixture.*) ;; *) exit 97;; esac
  [[ ! -L "$home_fixture" && $(realpath "$home_fixture") == "$home_fixture" && $(cat "$home_fixture/.audit-owner") == community-f4-runner-audit ]] || exit 98
  rm -rf -- "$home_fixture"
 fi
}
trap cleanup EXIT
mkdir -p "$fixture/repo/tools" "$fixture/sdk/flutter/bin/cache" "$fixture/tools"
cp "$runner" "$fixture/repo/tools/runner.sh"
for directory in apps/mobile packages/auth_vault packages/auth_passkey packages/image_viewer packages/auth-protocol-vectors packages/post-protocol-vectors services/api infra/postgres; do
 mkdir -p "$fixture/repo/$directory"
done
mkdir -p "$fixture/repo/services/api/authlab"
printf '%s' 'synthetic-sdk-owner' > "$fixture/sdk/.owner"
printf '%s' 'synthetic-library' > "$fixture/sqlite.so"
printf '%s' 'synthetic-lock-preserved' > "$fixture/repo/apps/mobile/pubspec.lock"
cat > "$fixture/record.py" <<'PY'
import json, os, pathlib, sys
root = pathlib.Path(os.environ['F4_TASK_ROOT'])
expected = {'HOME':'home','TMPDIR':'tmp','GOTMPDIR':'tmp','PUB_CACHE':'pub','GOCACHE':'go-build','GOPATH':'go-path','GOMODCACHE':'go-mod','GRADLE_USER_HOME':'gradle','XDG_CONFIG_HOME':'xdg-config','XDG_CACHE_HOME':'xdg-cache','XDG_DATA_HOME':'xdg-data','XDG_RUNTIME_DIR':'xdg-runtime'}
for key, child in expected.items():
    assert os.environ[key] == str(root / child), key
for key in ('PGHOST','PGSERVICE','PGOPTIONS','AUTHRUNTIME_C_DSN','F4_MAIN_CONFIG'):
    assert key not in os.environ, key
for key, role in (('AUTHLAB_C_DSN','hnuhole_c'),('AUTHLAB_V_DSN','hnuhole_v'),('AUTHLAB_POSTS_RUNTIME_DSN','hnuhole_c_runtime')):
    if key in os.environ:
        value = os.environ[key]
        assert value.startswith('postgresql://'+role+'@/hnuhole_'), key
        assert '?host='+str(root / 'tmp')+'/hnuhole-' in value, key
        assert 'application_name=hnuhole_authlab_' in value, key
assert os.environ['PGPORT'] == '55439'
assert os.environ['GOTOOLCHAIN'] == 'local'
assert os.environ['GOFLAGS'] == '-mod=readonly'
assert os.environ['GOWORK'] == 'off'
if sys.argv[1:3] == ['go','test'] and './...' in sys.argv:
    assert '-timeout=20m' in sys.argv
if sys.argv[1] == 'pg_ctl' and 'start' in sys.argv:
    options = sys.argv[sys.argv.index('-o')+1]
    assert options.startswith('-p 55439 '), options
    assert "listen_addresses=''" in options, options
with open(os.environ['F4_AUDIT_LOG'], 'a') as out:
    out.write(json.dumps({'argv':sys.argv[1:], 'isolation':'PASS'})+'\n')
PY
cat > "$fixture/sdk/flutter/bin/flutter" <<'SH'
#!/usr/bin/env bash
exec python3 "$F4_AUDIT_RECORDER" flutter "$@"
SH
cat > "$fixture/tools/tool-stub" <<'SH'
#!/usr/bin/env bash
exec python3 "$F4_AUDIT_RECORDER" "${0##*/}" "$@"
SH
chmod +x "$fixture/sdk/flutter/bin/flutter" "$fixture/tools/tool-stub"
for tool in go initdb pg_ctl psql; do
 cp "$fixture/tools/tool-stub" "$fixture/tools/$tool"
done
for lower in run-mobile-isolated.sh run-isolated.sh run-post-schema-isolated.sh; do
 cp "$(dirname "$runner")/../services/api/authlab/$lower" "$fixture/repo/services/api/authlab/$lower"
done
export F4_TASK_ROOT="$fixture/task" F4_FLUTTER_ROOT="$fixture/sdk/flutter"
export F4_SDK_OWNER_VALUE=synthetic-sdk-owner F4_PG_PORT=55439
export F4_GO_BIN_DIR="$fixture/tools" F4_SQLITE_LIBRARY="$fixture/sqlite.so"
export F4_AUDIT_LOG="$fixture/calls.jsonl" F4_AUDIT_RECORDER="$fixture/record.py"
for stage in checks auth-regression integration server posts-privileges vet; do
 env PGHOST=unknown PGOPTIONS=foreign PGSERVICE=unknown AUTHLAB_C_DSN=synthetic-foreign AUTHLAB_V_DSN=synthetic-foreign AUTHLAB_POSTS_RUNTIME_DSN=synthetic-foreign AUTHRUNTIME_C_DSN=synthetic-foreign F4_MAIN_CONFIG=synthetic-foreign bash "$fixture/repo/tools/runner.sh" "$stage" > "$fixture/$stage.out"
 printf '%s\n' "PASS stage $stage with isolated environment and synthetic tools"
done
python3 - "$fixture/calls.jsonl" <<'PY'
import json, pathlib, sys
calls = [json.loads(line)['argv'] for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
starts = [argv for argv in calls if argv[0] == 'pg_ctl' and 'start' in argv]
assert len(starts) == 4, starts
print('PASS all four lower-runner invocations request private socket and explicit port 55439')
PY
for lower in run-mobile-isolated.sh run-isolated.sh run-post-schema-isolated.sh; do
 for invalid in '55439 -c listen_addresses=*' 00000 99999; do
  if env PGPORT="$invalid" bash "$fixture/repo/services/api/authlab/$lower" > "$fixture/reject.out" 2>&1; then exit 96; fi
  grep -q 'Invalid .*PGPORT' "$fixture/reject.out"
 done
done
printf '%s\n' 'PASS malformed and out-of-range lower-runner PGPORT rejected before tools start'
for invalid_timeout in 0 0m 31m unlimited; do
 if env PGPORT=55439 AUTHLAB_TEST_TIMEOUT="$invalid_timeout" bash "$fixture/repo/services/api/authlab/run-isolated.sh" > "$fixture/reject.out" 2>&1; then exit 101; fi
 grep -q 'Invalid auth lab test timeout' "$fixture/reject.out"
done
printf '%s\n' 'PASS unbounded and unsupported SQL test timeout rejected before tools start'
[[ $(cat "$fixture/repo/apps/mobile/pubspec.lock") == synthetic-lock-preserved ]]
printf '%s\n' 'PASS source lock preserved'
original_task_root=$F4_TASK_ROOT
home_fixture=$(mktemp -d "$user_home/hnuhole-community-flutter-f4-audit-fixture.XXXXXX")
printf '%s' 'community-f4-runner-audit' > "$home_fixture/.audit-owner"
export F4_TASK_ROOT="$home_fixture/task"
bash "$fixture/repo/tools/runner.sh" checks > "$fixture/home-checks.out"
printf '%s\n' 'PASS canonical marker-owned task under current account HOME with synthetic tools'
export F4_TASK_ROOT="$user_home/unrelated-community-f4-audit"
if bash "$fixture/repo/tools/runner.sh" prepare > "$fixture/reject.out" 2>&1; then exit 99; fi
grep -q 'Unexpected F4 root' "$fixture/reject.out"
printf '%s\n' 'PASS unrelated HOME directory rejected'
export F4_TASK_ROOT=$original_task_root
task_owner_before=$(cat "$original_task_root/.owner")
if F4_TASK_ROOT="$original_task_root/../outside-traversal" bash "$fixture/repo/tools/runner.sh" prepare > "$fixture/reject.out" 2>&1; then exit 100; fi
[[ ! -e "$fixture/outside-traversal" && ! -L "$fixture/outside-traversal" ]]
[[ $(cat "$original_task_root/.owner") == "$task_owner_before" ]]
printf '%s\n' 'PASS traversal rejected before directory creation and original task owner preserved'
printf '%s' invalid-owner > "$fixture/sdk/.owner"
if bash "$fixture/repo/tools/runner.sh" prepare > "$fixture/reject.out" 2>&1; then exit 93; fi
grep -q 'Unowned Flutter SDK rejected' "$fixture/reject.out"
printf '%s\n' 'PASS foreign SDK owner rejected before prepare'
printf '%s' synthetic-sdk-owner > "$fixture/sdk/.owner"
rmdir "$fixture/sdk/flutter/bin/cache"
mkdir "$fixture/shared-cache"
ln -s "$fixture/shared-cache" "$fixture/sdk/flutter/bin/cache"
if bash "$fixture/repo/tools/runner.sh" prepare > "$fixture/reject.out" 2>&1; then exit 94; fi
grep -q 'Linked or missing Flutter cache rejected' "$fixture/reject.out"
printf '%s\n' 'PASS linked shared SDK cache rejected before prepare'
rm "$fixture/sdk/flutter/bin/cache"
mkdir "$fixture/sdk/flutter/bin/cache"
printf '%s' foreign-task > "$fixture/task/.owner"
if bash "$fixture/repo/tools/runner.sh" prepare > "$fixture/reject.out" 2>&1; then exit 95; fi
grep -q 'Unowned F4 root' "$fixture/reject.out"
printf '%s\n' 'PASS foreign task root rejected'
printf '%s\n' 'PASS cleanup restricted to canonical marker-owned synthetic fixture'
