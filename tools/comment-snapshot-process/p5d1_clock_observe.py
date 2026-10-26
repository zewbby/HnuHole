#!/usr/bin/env python3
"""One 45-second, no-HTTP, read-only QPC witness of guest clock read paths."""
import base64
import ctypes
import datetime
import json
import os
from pathlib import Path
import platform
import selectors
import statistics
import subprocess
import time

out=Path('/mnt/d/HnuHole-task-storage/comment-snapshot-redis-20261024/p5d1-clock-review-observation.json')
assert not out.exists() and platform.machine()=='x86_64'
os.umask(0o077)
libc=ctypes.CDLL(None,use_errno=True)
class Pair(ctypes.Structure):
    _fields_=[('sec',ctypes.c_long),('fraction',ctypes.c_long)]
def syscall_clock(clock):
    v=Pair();result=libc.syscall(ctypes.c_long(228),ctypes.c_int(clock),ctypes.byref(v))
    if result!=0:raise OSError(ctypes.get_errno(),'clock_gettime syscall')
    return v.sec*1000000000+v.fraction
def gettimeofday():
    v=Pair()
    if libc.gettimeofday(ctypes.byref(v),None)!=0:raise OSError(ctypes.get_errno(),'gettimeofday')
    return v.sec*1000000000+v.fraction*1000
readers={
 'python_raw':lambda:time.clock_gettime_ns(time.CLOCK_MONOTONIC_RAW),
 'python_monotonic':time.monotonic_ns,
 'python_realtime':time.time_ns,
 'syscall_raw':lambda:syscall_clock(4),
 'syscall_monotonic':lambda:syscall_clock(1),
 'syscall_realtime':lambda:syscall_clock(0),
 'libc_gettimeofday':gettimeofday,
}
def clocks(reverse=False):return {name:readers[name]() for name in (reversed(readers) if reverse else readers)}
def state():return {'bootID':Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'clockSource':Path('/sys/devices/system/clocksource/clocksource0/current_clocksource').read_text().strip(),'timesyncdActive':subprocess.check_output(['systemctl','is-active','systemd-timesyncd'],text=True).strip(),'timesyncdEnabled':subprocess.check_output(['systemctl','is-enabled','systemd-timesyncd'],text=True).strip()}
ps=r'''$ErrorActionPreference='Stop'
[Console]::Out.WriteLine('READY')
[Console]::Out.Flush()
while (($clockProbeLine = [Console]::ReadLine()) -ne $null) {
  $clockProbeBefore=[Diagnostics.Stopwatch]::GetTimestamp()
  $clockProbeUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $clockProbeAfter=[Diagnostics.Stopwatch]::GetTimestamp()
  [Console]::Out.WriteLine(('{0},{1},{2},{3},{4}' -f $clockProbeLine,$clockProbeBefore,$clockProbeAfter,[Diagnostics.Stopwatch]::Frequency,$clockProbeUtc))
  [Console]::Out.Flush()
}
'''
result={'scope':'ONE_SHORT_SYNCHRONOUS_CLOCK_OBSERVATION_NO_HTTP','plannedQPCSeconds':45,'nominalSpacingSeconds':.1,'maxSamples':600,'classificationDriftSeconds':.2,'couplingBracketTargetSeconds':.01,'startedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'originalSystemState':state(),'pythonClockImplementations':{k:vars(time.get_clock_info(k)) for k in ['monotonic','time']},'rows':[],'HTTPRequests':0,'systemChanges':False}
proc=None
try:
    encoded=base64.b64encode(ps.encode('utf-16-le')).decode()
    proc=subprocess.Popen(['/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-WindowStyle','Hidden','-EncodedCommand',encoded],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    selector=selectors.DefaultSelector();selector.register(proc.stdout,selectors.EVENT_READ)
    def line():
        if not selector.select(5):raise TimeoutError('persistent QPC witness timeout')
        value=proc.stdout.readline()
        if not value:raise RuntimeError('QPC witness exited')
        return value.decode('ascii').strip()
    assert line()=='READY'
    next_progress=15
    for sequence in range(600):
        before=clocks();proc.stdin.write((str(sequence)+'\n').encode());proc.stdin.flush();values=line();after=clocks(True)
        seq,q0,q1,freq,utc_ms=map(int,values.split(','));assert seq==sequence and freq>0 and q1>=q0
        row={'sequence':sequence,'beforeNS':before,'afterNS':after,'qpcBeforeUTC':q0,'qpcAfterUTC':q1,'frequency':freq,'hostUTCMilliseconds':utc_ms};result['rows'].append(row)
        first=result['rows'][0];assert freq==first['frequency']
        elapsed=(q0-first['qpcBeforeUTC'])/freq
        if elapsed>=next_progress:print('CLOCK_OBSERVATION '+str(round(elapsed,3))+' QPC seconds',flush=True);next_progress+=15
        if elapsed>=45:break
        time.sleep(.1)
    else:raise RuntimeError('predeclared sample cap reached')
    first=result['rows'][0];last=result['rows'][-1]
    qduration=(last['qpcBeforeUTC']-first['qpcBeforeUTC'])/first['frequency']
    summaries={}
    for name in readers:
        widths=[(r['afterNS'][name]-r['beforeNS'][name])/1e9 for r in result['rows']]
        violations=[]
        for r in result['rows']:
            q=(r['qpcBeforeUTC']-first['qpcBeforeUTC'])/first['frequency']
            lower=(r['beforeNS'][name]-first['afterNS'][name])/1e9
            upper=(r['afterNS'][name]-first['beforeNS'][name])/1e9
            violations.append(max(lower-q,q-upper,0))
        lower=(last['beforeNS'][name]-first['afterNS'][name])/1e9;upper=(last['afterNS'][name]-first['beforeNS'][name])/1e9
        summaries[name]={'durationIntervalSeconds':[lower,upper],'qpcElapsedSeconds':qduration,'maximumIntervalExclusionSeconds':max(violations),'maximumBracketSeconds':max(widths),'medianBracketSeconds':statistics.median(widths),'negativeBrackets':sum(v<0 for v in widths),'withinOriginalPoint2Criterion':max(violations)<=.2 and min(widths)>=0,'tightCouplingTargetMet':max(widths)<=.01 and min(widths)>=0}
    result.update(result='OBSERVED',qpcElapsedSeconds=qduration,clockSummaries=summaries,hostUTCElapsedSeconds=(last['hostUTCMilliseconds']-first['hostUTCMilliseconds'])/1000)
except BaseException as error:
    result.update(result='UNRESOLVED',error=str(error))
finally:
    if proc is not None:
        proc.stdin.close()
        try:proc.wait(timeout=5)
        except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=5)
        result['witnessExitCode']=proc.returncode
    result['finalSystemState']=state();result['systemStateUnchanged']=result['originalSystemState']==result['finalSystemState'];result['endedAtUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    out.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['rows','pythonClockImplementations']},indent=2),flush=True)
if result['result']!='OBSERVED' or not result['systemStateUnchanged']:raise SystemExit(1)
