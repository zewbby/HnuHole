#!/usr/bin/env python3
"""Independently recompute the predeclared diagnostic, never P95 acceptance."""
import collections
import datetime
import hashlib
import json
import math
from pathlib import Path
import statistics

disk=Path('/mnt/d/HnuHole-task-storage/comment-snapshot-redis-20261024')
repo=Path('/mnt/e/Hnuhole-env/source/HnuHole-comment-snapshot-redis')
def read(name):return json.loads((disk/name).read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def summary(values):
    values=sorted(values)
    return {'n':len(values),'mean':statistics.mean(values),'median':statistics.median(values),'p95Informational':values[math.ceil(.95*len(values))-1],'min':values[0],'max':values[-1]}
state=read('p5d1-r1-run.json');raw=read('p5d1-r1-raw.json');protocol=read('p5d1-r1-protocol.json')
assert state['status']=='COMPLETE_DIAGNOSTIC_ONLY' and state['restored'] and state['storageUnmounted'] and state['ownedRuntimeRemaining']==[]
assert raw['result']=='COMPLETE' and raw['errors']==[] and not raw.get('error')
assert protocol['pairs']==60 and protocol['requiredHits']==48 and protocol['scanShareThreshold']==.7 and protocol['requiredRequestFraction']==.8
rows=raw['requests']['replyExpanded'];assert set(rows)=={'postgres','redis'}
ids=[];fractions=[];lua={name:[] for name in ['get','validate','construct','set','script']};entry_ranges={op:[] for op in ['prepare','publish']}
for backend,values in rows.items():
    assert len(values)==60 and [x['pair'] for x in values]==list(range(60))
    for row in values:
        ids.append(row['requestId']);stages=row['serverTiming']['stages'];assert len(stages)<64
        if backend=='postgres':assert stages['comments.pg_snapshot_write']['calls']==1
        else:
            total={name:0 for name in lua}
            for op in ['prepare','publish']:
                for name in lua:
                    v=stages['comments.lua_'+op+'_'+name];assert v['calls']==1 and v['nanoseconds']>=0;total[name]+=v['nanoseconds']
                assert stages['comments.lua_'+op+'_script']['nanoseconds']<=stages['comments.redis_'+op+'_script_call']['nanoseconds']
                entry_ranges[op].append(stages['comments.lua_'+op+'_entries']['calls'])
            assert 0<sum(total[n] for n in ['get','validate','construct','set'])<=total['script']
            fraction=total['validate']/total['script'];assert fraction==row['diagnosticLua']['validationFraction'];fractions.append(fraction)
            for name,value in total.items():lua[name].append(value/1e6)
assert len(set(ids))==120 and sum(v['order']==0 for v in rows['redis'])==30
assert collections.Counter(v['generation'] for v in rows['redis'])=={1:30,2:30}
hits=sum(x>=.70 for x in fractions);verdict='SUPPORTED' if hits>=48 else 'REFUTED'
assert raw['stats']['replyExpanded']['diagnosis']['hits']==hits and raw['stats']['replyExpanded']['diagnosis']['hypothesis']==verdict
assert raw['stats']['replyExpanded']['p95Criterion']=='NOT_EVALUATED_DIAGNOSTIC'
def stages(backend,key):return [r['serverTiming']['stages'].get(key,{}).get('nanoseconds',0)/1e6 for r in rows[backend]]
by_backend={b:{key:summary(stages(b,key)) for key in ['subject.total','comments.total','subject.gate_row_lock','comments.gate_row_lock','subject.gate_abort','comments.gate_abort','comments.comment_projection','comments.pg_snapshot_write','comments.redis_prepare','comments.redis_publish','comments.redis_rpc','comments.redis_prepare_script_call','comments.redis_publish_script_call']} for b in rows}
residual=[r['latencyMs']-r['serverTiming']['elapsedMilliseconds'] for r in rows['redis']]
rpc_script=[stages('redis','comments.redis_prepare_script_call')[i]+stages('redis','comments.redis_publish_script_call')[i]-lua['script'][i] for i in range(60)]
assert min(rpc_script)>=0
artifacts={name:{'path':str(disk/name),'sha256':sha(disk/name)} for name in ['p5d1-r1-raw.json','p5d1-r1-run.json','p5d1-r1-protocol.json','p5d1-r1-static-verification.json','p5d1-r1-observation-overlay.json','p5d1-r1-frozen-manifest.json','p5d1-r1-initial-clock-preflight.json']}
for name in ['p5d1-r1-repaired-clock-preflight.json','p5d1-r1-clock-switch-inventory.json','p5d1-r1-preparation-failure.json']:
    if (disk/name).exists():artifacts[name]={'path':str(disk/name),'sha256':sha(disk/name)}
evidence={'task':'COMMENT-SNAPSHOT-REDIS-01','id':'P5-D1','model':'gpt-6.1-sol','reasoningEffort':'high','updatedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'COMPLETE_DIAGNOSTIC_ONLY','phase5Complete':False,'phase6Started':False,'productSourceDigest':'4b0eef09c8ea55598b1f04828835926dcf4c8af91e268008b7ded8a924fc2807','diagnosticSourceDigest':state['sourceDigest'],'diagnosticAPISHA256':state['apiBinarySHA256'],'hypothesis':{'verdict':verdict,'hits':hits,'requests':60,'requiredHits':48,'fractionThreshold':.7,'requestFraction':hits/60,'fractionDistribution':summary(fractions)},'combinedLuaMs':{k:summary(v) for k,v in lua.items()},'byBackendStageMs':by_backend,'entries':{k:{'min':min(v),'max':max(v)} for k,v in entry_ranges.items()},'redisRPCMinusScriptMs':summary(rpc_script),'redisHTTPMinusServerMs':summary(residual),'measuredRequests':120,'warmupRequests':120,'measuredHTTPErrorCount':0,'uniqueMeasuredRequestIDs':len(set(ids)),'environment':raw['stats']['replyExpanded'],'restoration':{'restored':state['restored'],'system':state['restoredSystemState'],'storageUnmounted':True,'ownedRuntimeRemaining':[]},'productCodeChanged':False,'productPerformanceAcceptance':'NOT_RUN_OLD_PLUS_7.5716285574_PERCENT_FAIL_RETAINED','artifacts':artifacts,'completionNotification':'PENDING'}
target=repo/'docs/design/comment-snapshot-redis/stage-5-p5d1-execution-evidence.json'
assert not target.exists();target.write_text(json.dumps(evidence,indent=2)+'\n');(disk/'p5d1-r1-evidence.json').write_bytes(target.read_bytes())
print(json.dumps({'hypothesis':evidence['hypothesis'],'combinedLuaMs':evidence['combinedLuaMs'],'rpcMinusScriptMs':evidence['redisRPCMinusScriptMs'],'pgWrite':by_backend['postgres']['comments.pg_snapshot_write'],'productAcceptance':'NOT_RUN'}))
