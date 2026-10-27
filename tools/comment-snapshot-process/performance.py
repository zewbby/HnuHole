#!/usr/bin/env python3
"""Matched final-code API performance; raw observations and errors retained."""
import argparse
import base64
import copy
import hashlib
import json
from pathlib import Path
import secrets
import statistics
import time
import uuid

from exercise import attach, percentile
from growth import seed_post
from run import b64, dump


def readers(lab, count):
    generation=lab.sql('SELECT authorization_generation FROM c_auth.authorization_gate;')
    number=int(lab.sql('SELECT max(platform_number::integer) FROM c_auth.accounts;'))+1
    tokens=[];sql=['BEGIN;SET LOCAL session_replication_role=replica;']
    for i in range(count):
        account=str(uuid.uuid4());raw=secrets.token_bytes(32);tokens.append(b64(raw))
        tokenhash=hashlib.sha256(raw).hexdigest();revoke=hashlib.sha256(b'HNUHOLE/SESSION-REVOKE/V1\0'+raw).digest()
        revokehash=hashlib.sha256(b'HNUHOLE/REVOKE-STORAGE/V1\0'+revoke).hexdigest()
        sql += ["INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('%s','%06d','perf_%s',decode('%s','hex'),decode('%s','hex'),1);"%(account,number+i,secrets.token_hex(8),secrets.token_hex(32),secrets.token_hex(16)),
                "INSERT INTO c_auth.account_restrictions(account_id) VALUES('%s');"%account,
                "INSERT INTO c_auth.sessions(token_digest,revoke_digest,account_id,installation_id,session_generation,created_at,last_activity_at,expires_at,authorization_generation) VALUES(decode('%s','hex'),decode('%s','hex'),'%s',decode('%s','hex'),1,now(),now(),now()+interval '30 days',%s);"%(tokenhash,revokehash,account,secrets.token_hex(16),generation)]
    lab.sql('\n'.join(sql+['COMMIT;']))
    return tokens


def reply_data(lab):
    post=seed_post(lab,1)
    root=lab.sql("SELECT comment_id FROM c_comments.tasks WHERE post_id='%s';"%post)
    lab.sql("""BEGIN;SET LOCAL session_replication_role=replica;
      CREATE TEMP TABLE perf_reply_rows ON COMMIT DROP AS SELECT gen_random_uuid() task,gen_random_uuid() comment FROM generate_series(1,60);
      INSERT INTO c_comments.tasks(task_id,comment_id,owner_account_id,post_id,identity_id,root_comment_id,target_comment_id)
        SELECT g.task,g.comment,p.owner_account_id,p.post_id,p.identity_id,'%s','%s' FROM perf_reply_rows g CROSS JOIN c_posts.publication_tasks p WHERE p.post_id='%s';
      INSERT INTO c_comments.attempts(task_id,version,state,accepted_at,accepted_stop_generation,terminal_at,body)
        SELECT task,1,'PUBLISHED',now(),0,now(),'synthetic reply performance' FROM perf_reply_rows;
      COMMIT;"""%(root,root,post))
    return '/api/v1/posts/'+post+'/comments/'+root+'/replies?limit=50'


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,required=True);parser.add_argument('--source',type=Path,required=True)
    args=parser.parse_args();lab=attach(args.root,args.source);result={'result':'RUNNING','rawMilliseconds':{},'stats':{},'errors':[]}
    try:
        token_main,token_preview,token_expanded=readers(lab,3)
        replies=reply_data(lab)
        lab.sql('ANALYZE;')
        lab.cfg['workerIntervalSeconds']=60
        r=lab.start_api('performance-final-redis','127.0.0.8',int(lab.cfg['internalListen'].split(':')[-1]))
        lab.cfg['comments']['snapshots']['createBackend']='postgres'
        p=lab.start_api('performance-final-postgres','127.0.0.9',int(lab.cfg['internalListen'].split(':')[-1]))
        lab.cfg['comments']['snapshots']['createBackend']='redis'
        cursors={}
        for name,ip in [('postgres','127.0.0.9'),('redis','127.0.0.8')]:
            first,_,_=lab.request(ip,lab.path,token=token_main)
            cursors[name]=lab.path+'&cursor='+first['nextCursor']
        total_rows=lab.sql('SELECT count(*) FROM c_comments.tasks;')
        result['metadata']={'apiBinarySHA256':hashlib.sha256((lab.root/'bin/process-api').read_bytes()).hexdigest(),
                            'apiPids':{'postgres':p.pid,'redis':r.pid},'concurrency':1,'warmupPerBackendPerCase':30,
                            'mainDataset':{'roots':500,'replies':1000,'limit':50},'replyDataset':{'roots':1,'replies':60,'preview':5,'expanded':50},
                            'totalCommentsIncludingNegativeFixtures':int(total_rows),'sampling':'per-request AB/BA alternating pairs, all samples retained',
                            'continuationComparedOnSameAPIProcess':True,'httpTiming':'from request send to complete JSON body, TLS connection established before timer',
                            'workerIntervalSeconds':60,'backgroundOriginalReadingProcesses':2,'sameSQLClusterAndAuthorizationAndKeys':True,
                            'snapshotsConfig':lab.cfg['comments']['snapshots'],'sqlPool':'runtime defaults, same on both',
                            'activeNamespacesAreDedicatedRedisInstances':True}
        cases=[('initial',token_main,200,50),('continuation',token_main,1000,50),('replyPreview',token_preview,300,5),('replyExpanded',token_expanded,300,50)]
        for kind,token,count,expected in cases:
            paths={name:(lab.path if kind=='initial' else cursors[name] if kind=='continuation' else replies+('&expanded=true' if kind=='replyExpanded' else '')) for name in ['postgres','redis']}
            ips={'postgres':'127.0.0.8' if kind=='continuation' else '127.0.0.9','redis':'127.0.0.8'}
            samples={'postgres':[],'redis':[]}
            for name in samples:
                for _ in range(30):
                    body,_,_=lab.request(ips[name],paths[name],token=token)
                    assert len(body['comments'])==expected
            for i in range(count):
                order=['postgres','redis'] if i%2 else ['redis','postgres']
                for name in order:
                    try:
                        body,ms,_=lab.request(ips[name],paths[name],token=token)
                        assert len(body['comments'])==expected
                        samples[name].append(ms)
                    except BaseException as error:
                        result['errors'].append({'case':kind,'backend':name,'sample':i,'error':str(error)});raise
            stats={name:{'samples':len(vals),'p50Ms':percentile(vals,.5),'p95Ms':percentile(vals,.95),'p99Ms':percentile(vals,.99),'meanMs':statistics.mean(vals)} for name,vals in samples.items()}
            stats['p95RegressionPercent']=(stats['redis']['p95Ms']/stats['postgres']['p95Ms']-1)*100
            stats['result']='PASS' if stats['p95RegressionPercent']<=5 else 'FAIL'
            result['stats'][kind]=stats;result['rawMilliseconds'][kind]=samples
            dump(lab.run/'performance-final.json',result)
            print('FINAL PERFORMANCE '+kind+' '+stats['result']+' regression='+str(round(stats['p95RegressionPercent'],3))+'%',flush=True)
        result['result']='PASS' if all(s['result']=='PASS' for s in result['stats'].values()) else 'FAIL'
    except BaseException as error:result.update(result='FAIL',error=str(error));raise
    finally:
        dump(lab.run/'performance-final.json',result)
        for child,stream,_ in reversed(lab.processes):
            if child.poll() is None:child.terminate()
            child.wait(timeout=20);stream.close()
    if result['result'] != 'PASS':
        raise SystemExit(1)


if __name__=='__main__':main()
