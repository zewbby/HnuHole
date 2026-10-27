#!/usr/bin/env python3
"""One fixed performance-gap case: compatibility continuation or steady expanded."""
import argparse
import base64
import hashlib
import hmac
import json
import random
import statistics
import time
import os
import secrets
import uuid
from pathlib import Path

from exercise import percentile
from growth import seed_post, add_roots
from performance import readers, reply_data
from ledger import decode as decode_ledger
from run import Lab, b64, dump, source_digest, elapsed_clock, host_clock, host_clock_summary
from resource_watch import evidence as resource_evidence, wait_quiet
from request_timing import observations, attach as attach_timings


def occupancy(lab):
    owner=lab.sql("SELECT owner_account_id FROM c_posts.posts WHERE post_id='%s';"%lab.post)
    templates=json.loads(lab.sql("""SELECT json_agg(x) FROM (
      SELECT '' AS root,array_agg(t.comment_id ORDER BY a.terminal_at DESC,t.comment_id) AS ids
      FROM c_comments.tasks t JOIN c_comments.attempts a USING(task_id) WHERE t.post_id='%s' AND t.root_comment_id IS NULL
      UNION ALL SELECT t.root_comment_id::text,array_agg(t.comment_id ORDER BY a.terminal_at,t.comment_id)
      FROM c_comments.tasks t JOIN c_comments.attempts a USING(task_id) WHERE t.post_id='%s' AND t.root_comment_id IS NOT NULL GROUP BY t.root_comment_id) x;"""%(lab.post,lab.post)))
    path=lab.run/'occupancy.private.json';dump(path,{'owner':owner,'post':lab.post,'templates':templates})
    lab.install_binary('snapshot-seed','./authlab/comment-snapshot-seed')
    env={**lab.env,'COMMENT_SNAPSHOT_OWNED_PROCESS_FIXTURE':'1'}
    lab.cmd([lab.root/'bin/process-snapshot-seed','--fixture-root',lab.run,'--config',lab.material/'c.json','--input',path],
            'occupancy-seed',env=env,timeout=180)
    return json.loads((lab.logs/'occupancy-seed.private.log').read_text())


def mirror_postgres(lab):
    """Equal logical occupancy for the two steady storage alternatives."""
    cfg=lab.cfg['comments']['snapshots'];prefix=cfg['redis']['namespace'];epoch=cfg['redis']['epoch']
    key=(lab.material/'comment-fingerprint.key').read_bytes();owners={}
    for token in lab.tokens:
        tokenhash=hashlib.sha256(base64.urlsafe_b64decode(token+'=')).hexdigest()
        account=lab.sql("SELECT account_id FROM c_auth.sessions WHERE token_digest=decode('%s','hex');"%tokenhash)
        digest=hashlib.sha256(b'HNUHOLE/COMMENT-SNAPSHOT-OWNER/V1\0'+prefix.encode()+b'\0'+uuid.UUID(account).bytes).digest()
        owners[b64(hmac.new(key,b'HNUHOLE/COMMENT-INTENT/V1\0'+digest,hashlib.sha256).digest())]=account
    ledger=decode_ledger(lab.redis.call('GET',prefix+'ledger:'+epoch));rows=[]
    for ident,e in ledger['entries'].items():
        assert e['state']=='active'
        payload=lab.redis.call('GET',prefix+'data:'+epoch+':'+ident);assert payload is not None
        post=str(uuid.UUID(bytes=payload[69:85]));root=uuid.UUID(bytes=payload[85:101]);n=int.from_bytes(payload[117:121],'big')
        ids=[str(uuid.UUID(bytes=payload[121+i*16:137+i*16])) for i in range(n)]
        rootsql='NULL' if root.int==0 else "'%s'"%root
        array='ARRAY['+','.join("'%s'"%v for v in ids)+']::uuid[]' if ids else 'ARRAY[]::uuid[]'
        rows.append("('%s','%s','%s',%s,%s,to_timestamp(%d/1000.0))"%(ident,owners[e['owner']],post,rootsql,array,e['expires']))
    lab.sql('INSERT INTO c_comments.snapshots(snapshot_id,owner_account_id,post_id,root_comment_id,comment_ids,expires_at) VALUES '+','.join(rows)+';')
    return len(rows)


def command_stats(redis):
    result={}
    for line in redis.call('INFO','commandstats').decode().splitlines():
        if not line.startswith(('cmdstat_eval:','cmdstat_evalsha:')):continue
        name,fields=line.split(':',1)
        result[name]={k:float(v) for item in fields.split(',') for k,v in [item.split('=',1)]}
    return result


def create_live_result(lab):
    """Create one durable LIVE result through the real login HTTP handler."""
    helper = Path(os.environ['COMMENT_SNAPSHOT_LOGIN_MATERIAL'])
    lab.cmd([helper], 'login-material')
    material = json.loads((lab.logs/'login-material.private.log').read_text())
    assert len(material['hash']) == 64 and len(material['salt']) == 32
    assert all(c in '0123456789abcdef' for c in material['hash']+material['salt'])
    lab.sql("BEGIN; SET LOCAL session_replication_role=replica; UPDATE c_auth.accounts SET password_hash=decode('%s','hex'),password_salt=decode('%s','hex') WHERE account_id='%s'; COMMIT;" % (material['hash'], material['salt'], lab.accounts[3]))
    conn = lab.tls_connection('127.0.0.1', 10)
    try:
        conn.request('POST', '/api/v1/auth/sessions', body=json.dumps(dict(username='snapshot_user_3', password=material['password'], installationId=b64(secrets.token_bytes(16)))),
                     headers={'Content-Type':'application/json', 'Origin':lab.cfg['publicOrigin'], 'Idempotency-Key':b64(secrets.token_bytes(32))})
        response = conn.getresponse(); body = json.loads(response.read())
        assert response.status == 201, 'real login fixture failed HTTP '+str(response.status)
        assert body.get('sessionToken') and body.get('accountId') == lab.accounts[3]
    finally:
        conn.close()
    return live_occupancy(lab)


def live_occupancy(lab):
    value = json.loads(lab.sql("SELECT json_build_object('liveCount',count(*),'unexpiredCount',count(*) FILTER (WHERE expires_at>clock_timestamp()),'mac32Count',count(*) FILTER (WHERE octet_length(request_hmac)=32),'sessionCreatedCount',count(*) FILTER (WHERE result_code='SESSION_CREATED')) FROM c_auth.request_results WHERE operation='SESSION_CREATE' AND state='LIVE';"))
    assert value == dict(liveCount=1, unexpiredCount=1, mac32Count=1, sessionCreatedCount=1), 'LIVE login occupancy changed'
    return value


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--redis',type=Path,required=True)
    p.add_argument('--target',choices=['compat-continuation','steady-expanded'],required=True)
    p.add_argument('--pace',type=float,default=.27)
    # Full request phase observations are required for both fixed cases.
    args=p.parse_args();args.diagnostic=False;args.observe_phases=True;args.mode='compatibility' if args.target=='compat-continuation' else 'steady';args.shared_admission='official';args.duration=1805;args.suite='reading'
    lab=Lab(args);result={'result':'RUNNING','scope':'SINGLE_PREDECLARED_PERFORMANCE_GAP','target':args.target,'mode':args.mode,'stats':{},'requests':{},'errors':[]}
    try:
        lab.setup()
        assert not args.diagnostic
        # Preserve the old dataset size without repeating the negative acceptance paths.
        negative=seed_post(lab,2);add_roots(lab,negative,10000)
        result['liveLoginResult']=create_live_result(lab)
        replypath=reply_data(lab)
        result['occupancySeed']=occupancy(lab)
        if args.mode=='steady':result['postgresMirroredSnapshots']=mirror_postgres(lab)
        tokens=readers(lab,3);lab.sql('ANALYZE;')
        assert int(lab.sql('SELECT count(*) FROM c_comments.tasks;')) == 11563
        # Exactly the two measured API processes remain, both with the same
        # authdev worker settings; no extra base API maintenance is hidden.
        for child in [lab.a,lab.b]:child.terminate();child.wait(timeout=20)
        cfg=json.loads(json.dumps(lab.cfg));lab.cfg['comments']['observeReadTimings']=args.diagnostic or args.observe_phases
        generation=0
        def start_pair(swap=False):
            nonlocal generation
            generation+=1
            ips={'postgres':'127.0.0.8' if not swap else '127.0.0.9','redis':'127.0.0.9' if not swap else '127.0.0.8'}
            processes=[]
            for name in ['postgres','redis']:
                s=lab.cfg['comments']['snapshots'];s.update(createBackend=name,readPostgres=True,readRedis=True)
                if args.mode=='steady':s.update(readPostgres=name=='postgres',readRedis=name=='redis')
                child=lab.start_api('normalized-'+name+'-generation'+str(generation),ips[name],int(lab.cfg['internalListen'].split(':')[-1]))
                processes.append(child)
            return ips,processes
        swap=False
        ips,processes=start_pair();lab.request_pace_seconds=args.pace
        cursors={}
        if args.target=='compat-continuation':
            for name in ['postgres','redis']:
                body,_,_=lab.request(ips[name],lab.path,token=tokens[0])
                cursors[name]=lab.path+'&cursor='+body['nextCursor']
        wait_quiet()
        start=time.monotonic();start_unix=time.time();start_raw=elapsed_clock();rng=random.Random(20261025)
        result['metadata']={'sourceDigest':source_digest(lab.source),'apiBinarySHA256':hashlib.sha256((lab.root/'bin/process-api').read_bytes()).hexdigest(),
            'runtime':lab.results['runtime'],
            'runtimeNumericAndBooleanConfig':{key:value for key,value in cfg.items() if isinstance(value,(int,float,bool))},
            'sharedAdmissionProfileSHA256':hashlib.sha256((lab.source/'infra/ratelimit/community-observe.example.json').read_bytes()).hexdigest(),
            'mode':args.mode,'sharedAdmission':lab.cfg['sharedRateLimit']['policy'],'localQueryCapacity':cfg['networkQueryCapacity'],
            'workerIntervalSeconds':cfg['workerIntervalSeconds'],'cleanupIntervalSeconds':cfg['comments']['snapshots']['cleanupIntervalSeconds'],
            'totalCommentRows':int(lab.sql('SELECT count(*) FROM c_comments.tasks;')),'mainRoots':500,'mainReplies':1000,'replyPerformanceRows':60,
            'httpElapsedClock':'CLOCK_MONOTONIC_RAW','concurrency':1,'requestPaceSeconds':args.pace,'seed':20261025,'order':'balanced shuffled blocks of20 pairs; one midpoint IP crossover in this fixed case',
            'measurementStartUnixSeconds':start_unix,'measurementStartRawSeconds':start_raw,
            'sameProcessContinuation':args.mode=='compatibility','observeReadTimings':args.diagnostic or args.observe_phases,
            'tcpNoDelay':True,'phaseElapsedClock':'CLOCK_MONOTONIC_RAW',
            'configs':{'postgres':{'createBackend':'postgres','readPostgres':True,'readRedis':args.mode=='compatibility'},'redis':{'createBackend':'redis','readPostgres':args.mode=='compatibility','readRedis':True}},
            'diagnosticResidual':'SQL/Gate/projection includes all transaction work outside snapshot Redis client calls; not pure SQL',
            'redisTiming':'client wall includes queue/transport; INFO commandstats reports server Lua aggregate, their difference is not pure queue time'}
        defaults=[('continuation',tokens[0],1000,50)] if args.target=='compat-continuation' else [('replyExpanded',tokens[2],300,50)]
        for kind,token,count,expected in defaults:
            path_host_initial=host_clock()
            live_before=live_occupancy(lab)
            if args.diagnostic:count=100
            warm=10 if args.diagnostic else 30
            paths={name:(lab.path if kind=='initial' else cursors[name] if kind=='continuation' else replypath+('&expanded=true' if kind=='replyExpanded' else '')) for name in ['postgres','redis']}
            records={'postgres':[],'redis':[]};result['requests'][kind]=records
            before=command_stats(lab.redis)
            for name in records:
                ip=ips['redis'] if kind=='continuation' and args.mode=='compatibility' else ips[name]
                for _ in range(warm):
                    body,_,_=lab.request(ip,paths[name],token=token);assert len(body['comments'])==expected
            orders=[]
            for i in range(0,count,20):
                block=[0,1]*10;rng.shuffle(block);orders+=block[:min(20,count-i)]
            for i,order in enumerate(orders):
                if i==count//2:
                    for child in processes:child.terminate();child.wait(timeout=20)
                    swap=not swap
                    ips,processes=start_pair(swap)
                    result.setdefault('liveOccupancyAtMidpoint',{})[kind]=live_occupancy(lab)
                    for name in records:
                        ip=ips['redis'] if kind=='continuation' and args.mode=='compatibility' else ips[name]
                        for _ in range(warm):
                            body,_,_=lab.request(ip,paths[name],token=token)
                            assert len(body['comments'])==expected
                for name in (['postgres','redis'] if order==0 else ['redis','postgres']):
                    ip=ips['redis'] if kind=='continuation' and args.mode=='compatibility' else ips[name]
                    try:
                        body,ms,headers=lab.request(ip,paths[name],token=token);assert len(body['comments'])==expected
                        records[name].append({'pair':i,'sentRelativeSeconds':lab.last_request_send_at-start,'latencyMs':ms,'requestId':{k.lower():v for k,v in headers.items()}.get('x-request-id'),'order':order,'generation':generation,'ip':ip,'clockOffsets':lab.last_request_clock_offsets})
                    except BaseException as error:result['errors'].append({'path':kind,'backend':name,'pair':i,'error':str(error)});raise
                if (i+1)%100==0:
                    dump(lab.root/'measurement-progress.json',{'target':args.target,'completedPairs':i+1,'plannedPairs':count,'run':str(lab.run)})
                    print('PROGRESS '+args.target+' '+str(i+1)+'/'+str(count),flush=True)
                    dump(lab.run/'normalized-performance.json',result)
            stat={name:{'samples':len(values),'p50Ms':percentile([x['latencyMs'] for x in values],.5),'p95Ms':percentile([x['latencyMs'] for x in values],.95),
                        'p99Ms':percentile([x['latencyMs'] for x in values],.99),'meanMs':statistics.mean(x['latencyMs'] for x in values)} for name,values in records.items()}
            stat['p95RegressionPercent']=(stat['redis']['p95Ms']/stat['postgres']['p95Ms']-1)*100
            stat['p95Criterion']='PASS' if stat['p95RegressionPercent']<=5 else 'FAIL'
            clocks=[r['clockOffsets'] for values in records.values() for r in values]
            variation={key:max(c[key] for c in clocks)-min(c[key] for c in clocks) for key in ['utcRawSeconds','monoRawSeconds']}
            stat['clockVariationSeconds']=variation
            stat['environmentResult']='PASS' if max(variation.values())<=2 else 'ENVIRONMENT_UNSTABLE'
            stat['result']='PASS' if stat['p95Criterion']=='PASS' and stat['environmentResult']=='PASS' else 'FAIL'
            stat['snapshotRedisCommandStats']={'before':before,'after':command_stats(lab.redis)}
            settings=cfg['comments']['snapshots']
            ledger=decode_ledger(lab.redis.call('GET',settings['redis']['namespace']+'ledger:'+settings['redis']['epoch']))
            stat['occupancyAfter']={'redisEntries':len(ledger['entries']),'postgresSnapshots':int(lab.sql('SELECT count(*) FROM c_comments.snapshots;'))}
            stat['liveOccupancyBefore']=live_before
            stat['liveOccupancyAfter']=live_occupancy(lab)
            stat['hostClockSummary']=host_clock_summary(path_host_initial,host_clock())
            if not stat['hostClockSummary']['stable']:stat['result']='FAIL';stat['environmentResult']='ENVIRONMENT_UNSTABLE'
            attach_timings(result['requests'],observations(lab.logs.glob('api-normalized-*.private.log')))
            stat['sharedResourceEvidence']=resource_evidence(start_raw,elapsed_clock())
            if stat['sharedResourceEvidence']['result']!='PASS':stat['result']='FAIL'
            result['stats'][kind]=stat;dump(lab.run/'normalized-performance.json',result)
            print(args.mode+' '+result['scope']+' '+kind+' '+stat['result']+' '+str(round(stat['p95RegressionPercent'],3))+'%',flush=True)
            if stat['result']!='PASS':
                result['stoppedAfter']=kind
                raise RuntimeError('first reply criterion/environment failure; no next path or retry')
        if args.observe_phases:
            attach_timings(result['requests'],observations(lab.logs.glob('api-normalized-*.private.log')))
        result['sharedResourceEvidence']=resource_evidence(start_raw,elapsed_clock())
        result['result']='PASS' if all(x['result']=='PASS' for x in result['stats'].values()) and result['sharedResourceEvidence']['result'] in ['PASS','NOT_CONFIGURED'] else 'FAIL'
    except BaseException as error:result.update(result='FAIL',error=str(error));raise
    finally:
        try:
            attach_timings(result['requests'],observations(lab.logs.glob('api-normalized-*.private.log')))
        except BaseException as observation_error:
            result['observationError']=str(observation_error)
        dump(lab.run/'normalized-performance.json',result);lab.cleanup()
    if not args.diagnostic and result['result']!='PASS':raise SystemExit(1)


if __name__=='__main__':main()
