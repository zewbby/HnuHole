#!/usr/bin/env python3
"""Own one D-backed P5-D1 diagnostic, including build, clock guard and restore."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys

os.umask(0o077)
assert os.geteuid()==0
base=Path('/home/hnuhole/comment-snapshot-redis-20261024-8ed8f28')
disk=Path('/mnt/d/HnuHole-task-storage/comment-snapshot-redis-20261024')
mountpoint=base/'d-output-native';root=mountpoint/'p5d1-r1';source=root/'source'
original=base/'stage5-replies-only-r1/source';image=disk/'linux-private-output.ext4'
statefile=disk/'p5d1-r1-run.json';clock=Path('/sys/devices/system/clocksource/clocksource0/current_clocksource')
assert image.is_file()
preparation_correction=None
if statefile.exists():
    prior=json.loads(statefile.read_text())
    assert prior['status']=='UNRESOLVED' and prior['currentStep']=='prepare-overlay' and not prior['clockRepairAttempted'] and prior['storageUnmounted']
    preparation_correction=disk/'p5d1-r1-preparation-failure.json'
    assert not preparation_correction.exists();shutil.copyfile(statefile,preparation_correction)
state={'status':'PREPARING','pid':os.getpid(),'startedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'root':str(root),'originalSource':str(original),'source':str(source),'scope':'P5-D1_ONE_FIXED_60_PAIR_DIAGNOSTIC','productAcceptance':False,'steps':{},'clockRepairAttempted':False}

def save():statefile.write_text(json.dumps(state,indent=2)+'\n')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def cmd(args,timeout=20):return subprocess.run(args,check=True,timeout=timeout,capture_output=True,text=True).stdout.strip()
def system_state():return {'clockSource':clock.read_text().strip(),'timesyncdActive':cmd(['systemctl','is-active','systemd-timesyncd']),'timesyncdEnabled':cmd(['systemctl','is-enabled','systemd-timesyncd']),'bootID':Path('/proc/sys/kernel/random/boot_id').read_text().strip()}
def step(name,args,seconds,env,allow_failure=False,cwd=None):
    state['currentStep']=name;save();print('STEP '+name,flush=True)
    with (root/(name+'.private.log')).open('wb') as log:
        p=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True,cwd=cwd)
        try:code=p.wait(timeout=seconds)
        except BaseException:
            if p.poll() is None:
                os.killpg(p.pid,signal.SIGINT)
                try:p.wait(timeout=30)
                except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGTERM);p.wait(timeout=30)
            raise
    state['steps'][name]={'exitCode':code,'endedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat()};save()
    if code and not allow_failure:raise RuntimeError(name+' failed; private log retained')
    return code

activated=False;before=None;mounted=False;watch=None;watchlog=None
try:
    assert not os.path.ismount(mountpoint) and mountpoint.is_dir() and not list(mountpoint.iterdir())
    cmd(['mount','-o','loop,nodev,nosuid',str(image),str(mountpoint)]);mounted=True
    assert stat.S_IMODE(mountpoint.stat().st_mode)==0o700 and mountpoint.stat().st_uid==1000
    if root.exists():
        assert preparation_correction is not None
        retained=mountpoint/'p5d1-r1-incomplete-preparation'
        assert root.resolve().parent==retained.resolve().parent==mountpoint.resolve() and not retained.exists()
        root.rename(retained)
        state['preparationCorrection']={'priorRecord':str(preparation_correction),'retainedPartialDirectory':str(retained),'HTTPRequestsBeforeCorrection':0}
    root.mkdir(mode=0o700);os.chown(root,1000,1000)
    for name in ['tmp','python-cache','frozen-bin','harness','go-build','go','fixture']:
        q=root/name;q.mkdir(mode=0o700);os.chown(q,1000,1000)
    for name in ['p5d1_prepare.py','performance-gaps-r1-preflight.py','gaps_targeted.py']:
        q=root/'harness'/name;shutil.copyfile(disk/name,q);os.chmod(q,0o600);os.chown(q,1000,1000)
    env=dict(os.environ,PATH='/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:/mnt/e/Hnuhole-env/linux/bin:'+os.environ.get('PATH','/usr/bin:/bin'),
             PYTHONPYCACHEPREFIX=str(root/'python-cache'),TMPDIR=str(root/'tmp'),GOTMPDIR=str(root/'tmp'),GOCACHE=str(root/'go-build'),GOPATH=str(root/'go'),
             GOMODCACHE=str(root/'go/pkg/mod'),GOPROXY='file:///home/hnuhole/.cache/hnuhole/go-modules/pkg/mod/cache/download,off',GOTOOLCHAIN='local',GOFLAGS='-mod=readonly',GOWORK='off',GOMAXPROCS='2',
             LD_LIBRARY_PATH='/home/hnuhole/shared-rate-limit-20261024-8ed8f28/redis-runtime/usr/lib/x86_64-linux-gnu',
             COMMENT_SNAPSHOT_WINDOWS_CLOCK='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe',COMMENT_SNAPSHOT_RESOURCE_ROOT=str(root))
    step('prepare-overlay',['runuser','-u','hnuhole','--','python3',str(root/'harness/p5d1_prepare.py'),'--original',str(original),'--destination',str(source)],120,env)
    sys.pycache_prefix=str(root/'python-cache');sys.path.insert(0,str(source/'tools/comment-snapshot-process'))
    from run import source_digest
    assert source_digest(original)==source_digest(Path('/mnt/e/Hnuhole-env/source/HnuHole-comment-snapshot-redis'))=='4b0eef09c8ea55598b1f04828835926dcf4c8af91e268008b7ded8a924fc2807'
    api=source/'services/api'
    modified=['internal/commentsnapshot/redis.go','internal/commentsnapshot/p5d1_diagnostic.go','internal/commentsnapshot/p5d1_diagnostic_test.go','internal/readtiming/readtiming.go','internal/authprivacy/community_comment_snapshots.go']
    step('gofmt',['runuser','-u','hnuhole','--','gofmt','-w']+[str(api/n) for n in modified],30,env)
    step('build-vet',['runuser','-u','hnuhole','--','go','vet','./internal/commentsnapshot','./internal/readtiming','./internal/authprivacy'],300,env,cwd=api)
    redis=Path('/home/hnuhole/shared-rate-limit-20261024-8ed8f28/redis-runtime/usr/bin/redis-server')
    testenv=dict(env,COMMENT_SNAPSHOT_REDIS_SERVER=str(redis))
    tests='TestP5D1Envelope|TestRealRedisPublishedNonceQuotaAndFixedExpiry|TestRealRedisPartialWriteRemainsChargedUntilCompensation|TestRealRedisAbortingFenceAndExpiredPendingRecovery|TestRealRedisPackedLedgerRejectsCorruptPeerBeforeReuse'
    step('focused-real-redis-tests',['runuser','-u','hnuhole','--','go','test','-race','-count=1','-v','./internal/commentsnapshot','-run',tests],300,testenv,cwd=api)
    step('focused-timing-tests',['runuser','-u','hnuhole','--','go','test','-race','-count=1','./internal/readtiming'],120,env,cwd=api)
    binaries={}
    for name,target in [('api','./cmd/api'),('authdev','./cmd/authdev'),('commentsnapshotctl','./cmd/commentsnapshotctl'),('ratelimitctl','./cmd/ratelimitctl'),('snapshot-seed','./authlab/comment-snapshot-seed')]:
        dest=root/'frozen-bin'/('process-'+name)
        step('build-'+name,['runuser','-u','hnuhole','--','go','build','-o',str(dest),target],180,env,cwd=api);binaries[name]=sha(dest)
    shutil.copyfile(base/'stage5-replies-only-r1/bin/login-material',root/'frozen-bin/login-material');os.chmod(root/'frozen-bin/login-material',0o700);os.chown(root/'frozen-bin/login-material',1000,1000)
    digest=source_digest(source)
    manifest={'sourceDigest':digest,'binaries':binaries};(root/'frozen-bin/binary-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');os.chown(root/'frozen-bin/binary-manifest.json',1000,1000)
    protocol={'id':'P5-D1','scope':'ONE_FIXED_STEADY_EXPANDED_DIAGNOSTIC','productAcceptance':False,'pairs':60,'measuredRequests':120,'warmupRequests':120,'seed':20261025,'midpointPair':30,'scanShareThreshold':.70,'requiredRequestFraction':.80,'requiredHits':48,'fullValidationUnchanged':True,'normalWorker':True,'realLIVE':True,'originalSourceDigest':source_digest(original),'sourceDigest':digest,'binaries':binaries,'driverSHA256':sha(root/'harness/p5d1_driver.py'),'clockRepair':'one conditional repair under existing human authorization; restore finally','sampling':'No retries, no replacement, no extra samples; protocol frozen before HTTP'}
    (root/'protocol.json').write_text(json.dumps(protocol,indent=2)+'\n');shutil.copyfile(root/'protocol.json',disk/'p5d1-r1-protocol.json');shutil.copyfile(root/'observation-overlay.json',disk/'p5d1-r1-observation-overlay.json')
    frozen={str(p.relative_to(source)):sha(p) for p in source.rglob('*') if p.is_file()}
    (root/'frozen-manifest.json').write_text(json.dumps({'files':frozen,'protocolSHA256':sha(root/'protocol.json'),'manifest':manifest},indent=2)+'\n')
    env.update(COMMENT_SNAPSHOT_BINARY_DIR=str(root/'frozen-bin'),COMMENT_SNAPSHOT_LOGIN_MATERIAL=str(root/'frozen-bin/login-material'),PYTHONPATH=str(source/'tools/comment-snapshot-process'))
    before=system_state();state.update(originalSystemState=before,sourceDigest=digest,apiBinarySHA256=binaries['api']);save()
    code=step('initial-clock-preflight',['runuser','-u','hnuhole','--','python3',str(root/'harness/performance-gaps-r1-preflight.py'),'--output',str(root/'initial-clock-preflight.json'),'--source',str(source),'--settle','0'],400,env,True)
    initial=json.loads((root/'initial-clock-preflight.json').read_text());state['initialClockPreflight']=initial['result'];save()
    if code:
        assert initial['result']=='ENVIRONMENT_UNSTABLE'
        sensitive_names={'go','compile','link','wrk','wrk2','hey','ab','k6','stress','stress-ng','redis-benchmark','pgbench','fio','sysbench'}
        timing_scripts={'normalized.py','performance.py','campaign.py','fixed_revalidation.py','replies_targeted.py','gaps_targeted.py','p5d1_driver.py','transport_probe.py'}
        inventories=[]
        for attempt in range(121):
            sensitive=[]
            for p in Path('/proc').iterdir():
                if not p.name.isdigit() or int(p.name)==os.getpid():continue
                try:
                    name=(p/'comm').read_text().strip();exe=Path(os.readlink(p/'exe')).name;args=(p/'cmdline').read_bytes().split(b'\0')
                    if name in sensitive_names or exe.endswith('.test') or any(Path(a.decode(errors='replace')).name in timing_scripts for a in args):sensitive.append({'pid':int(p.name),'name':name})
                except OSError:pass
            inventories.append({'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sensitiveProcesses':sensitive})
            if not sensitive:break
            if attempt==120:raise RuntimeError('no safe clock switch window; others untouched')
            import time;time.sleep(5)
        (root/'clock-switch-inventory.json').write_text(json.dumps(inventories,indent=2)+'\n')
        assert system_state()==before and before['clockSource']=='tsc' and before['timesyncdActive']=='active'
        activated=True;state['clockRepairAttempted']=True;save();cmd(['systemctl','stop','systemd-timesyncd']);clock.write_text('hyperv_clocksource_tsc_page\n');assert clock.read_text().strip()=='hyperv_clocksource_tsc_page'
        step('repaired-clock-preflight',['runuser','-u','hnuhole','--','python3',str(root/'harness/performance-gaps-r1-preflight.py'),'--output',str(root/'repaired-clock-preflight.json'),'--source',str(source),'--settle','60'],500,env)
    assert source_digest(source)==digest and all(sha(source/n)==h for n,h in frozen.items())
    watchlog=(root/'resource-watch.private.log').open('wb');watch=subprocess.Popen(['runuser','-u','hnuhole','--','python3',str(source/'tools/comment-snapshot-process/resource_watch.py'),'--root',str(root),'--own-source',str(base)],env=env,stdout=watchlog,stderr=subprocess.STDOUT)
    step('steady-expanded-diagnostic',['runuser','-u','hnuhole','--','python3',str(root/'harness/p5d1_driver.py'),'--root',str(root/'fixture'),'--source',str(source),'--redis',str(redis),'--target','steady-expanded'],1200,env)
    fixture=Path(json.loads((root/'fixture/process-latest.json').read_text())['run']);raw=fixture/'normalized-performance.json';value=json.loads(raw.read_text());shutil.copyfile(raw,disk/'p5d1-r1-raw.json')
    assert value['result']=='COMPLETE' and not value.get('errors') and not value.get('error')
    state.update(status='COMPLETE_DIAGNOSTIC_ONLY',diagnosis=value['stats']['replyExpanded']['diagnosis'],rawSHA256=sha(raw),rawExport=str(disk/'p5d1-r1-raw.json'))
except BaseException as error:
    state.update(status='UNRESOLVED',error=str(error));print('P5D1_UNRESOLVED '+str(error),flush=True)
finally:
    if watch is not None:
        (root/'resource-watch.stop').touch()
        try:watch.wait(timeout=20)
        except subprocess.TimeoutExpired:watch.terminate();watch.wait(timeout=10)
    if watchlog is not None:watchlog.close()
    if activated:
        try:
            assert before['bootID']==Path('/proc/sys/kernel/random/boot_id').read_text().strip();clock.write_text(before['clockSource']+'\n');cmd(['systemctl','start','systemd-timesyncd']);assert system_state()==before;state.update(restored=True,restoredSystemState=system_state())
        except BaseException as error:state.update(restored=False,restoreError=str(error),status='UNRESOLVED_RESTORE_REQUIRED')
    elif before is not None:
        try:assert system_state()==before;state.update(restored=True,restoredSystemState=system_state())
        except BaseException as error:state.update(restored=False,restoreError=str(error))
    try:
        if root.exists():
            for name in ['initial-clock-preflight.json','repaired-clock-preflight.json','protocol.json','frozen-manifest.json','clock-switch-inventory.json','observation-overlay.json']:
                if (root/name).exists():shutil.copyfile(root/name,disk/('p5d1-r1-'+name))
            latest=root/'fixture/process-latest.json'
            if latest.exists():
                fixture=Path(json.loads(latest.read_text())['run']);raw=fixture/'normalized-performance.json'
                if raw.exists():shutil.copyfile(raw,disk/'p5d1-r1-raw.json')
            owned=[]
            for p in Path('/proc').iterdir():
                if not p.name.isdigit() or int(p.name)==os.getpid():continue
                try:
                    cwd=Path(os.readlink(p/'cwd'));exe=Path(os.readlink(p/'exe')).name
                    if cwd.is_relative_to(root):owned.append({'pid':int(p.name),'exe':exe})
                except OSError:pass
            state['ownedRuntimeRemaining']=owned;assert not owned,'owned runtime remains; refuse unmount'
        if mounted:cmd(['umount',str(mountpoint)],30);state['storageUnmounted']=not os.path.ismount(mountpoint)
    except BaseException as error:state.update(storageCleanupError=str(error),storageUnmounted=False)
    state['endedAtUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat();save();print(json.dumps(state),flush=True)
if state['status']!='COMPLETE_DIAGNOSTIC_ONLY' or not state.get('restored') or not state.get('storageUnmounted'):raise SystemExit(1)
