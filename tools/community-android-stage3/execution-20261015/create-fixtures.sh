#!/usr/bin/env bash
set -euo pipefail
umask 077
source /mnt/e/HnuHole-community-f4-20261012/stage1-preparation-20261014/env.sh
work=/home/hnuhole/community-android-stage3-execution-20261015
out=/mnt/e/HnuHole-community-f4-20261012/stage3-execution-20261015
[[ $(cat "$work/.owner") == HNUHOLE_COMMUNITY_ANDROID_STAGE3_EXECUTION_20261015_V1 ]]
exec 9>"$F4_TASK_ROOT/community-build.lock";flock -n 9 || exit 2
export HOME=$work/home TMPDIR=$work/tmp PUB_CACHE=$F4_TASK_ROOT/pub
export XDG_CONFIG_HOME=$work/xdg-config XDG_CACHE_HOME=$work/xdg-cache XDG_DATA_HOME=$work/xdg-data
export LD_LIBRARY_PATH=$F4_TASK_ROOT/sqlite
export PATH=$F4_FLUTTER_ROOT/bin:$JAVA_HOME/bin:$PATH
python3 - "$work" <<'PY'
import json,secrets,sys
from pathlib import Path
w=Path(sys.argv[1]);f=w/'lab/fixture';assert not f.exists();f.mkdir(mode=0o700)
run=json.loads((w/'lab/lab.json').read_text())['runId'].split('-')[-1]
data={t:{'email':f'community-s3-{t}-{run}@hainanu.edu.cn','username':f's3{t[0]}_{run}','password':'Stage3-'+secrets.token_urlsafe(24)+'!9','status':'PREPARED_NOT_RUN'} for t in ('negative','positive')}
(f/'accounts.private.json').write_text(json.dumps(data));(f/'accounts.private.json').chmod(0o600)
PY
mkdir -p "$work/source/apps/mobile/integration"
cp "$out/owned_stage3_fixture_test.dart" "$work/source/apps/mobile/integration/owned_stage3_fixture_test.dart"
cd "$work/source/apps/mobile"
flutter test --no-pub --machine integration/owned_stage3_fixture_test.dart > "$out/logs/fixture-create.private.jsonl" 2> "$out/logs/fixture-create.private.stderr.log"
python3 - "$work" "$out" <<'PY'
import json,sys
from pathlib import Path
w,o=map(Path,sys.argv[1:]);f=json.loads((w/'lab/fixture/accounts.private.json').read_text());assert all(v['status']=='REGISTERED_REAL_AUTHFLOWS' for v in f.values())
r={'result':'PASS_OWNED_SYNTHETIC_FIXTURE_CREATION_ONLY','accounts':2,'realAuthFlows':True,'realCAndV':True,'originalFormalSqlAndGrants':True,'nativeStorageClaimed':False,'secretMaterialExported':False}
(o/'fixture-created.json').write_text(json.dumps(r,indent=2));print(json.dumps(r))
PY
