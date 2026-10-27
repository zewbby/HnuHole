#!/usr/bin/env python3
"""Two real API children with real SQL admission metadata and separate Redis."""
import argparse
import copy
import json
from pathlib import Path
import secrets
import socket
import time
import urllib.parse
import uuid

from exercise import attach
from run import Lab, Redis, dump, wait, source_digest
import hashlib


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--redis',type=Path,required=True)
    args=parser.parse_args();parent=attach(args.root,args.source)
    # This deliberately strict two-event fault policy needs its own SQL
    # namespace metadata. Never replace the official measurement policy.
    nested=parent.root/('admission-isolation-'+secrets.token_hex(3));nested.mkdir(mode=0o700)
    for name in ['go','go-build']:(nested/name).symlink_to(parent.root/name,target_is_directory=True)
    args.root=nested;args.shared_admission='none';lab=Lab(args)
    results={'result':'RUNNING','actualAPICommandProcesses':2,'realPostgresAdmissionMetadata':True,'separateRedisProcesses':True}
    try:
        lab.setup()
        for child in [lab.a,lab.b]:child.terminate();child.wait(timeout=20)
        lab.install_binary('ratelimitctl','./cmd/ratelimitctl')
        clients=[]
        for kind,username in [('snap','community_comment_snapshot_v2'),('admission','community_ratelimit')]:
            with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
            password=secrets.token_hex(32)
            child=lab.spawn([args.redis,'--bind','127.0.0.1','--port',port,'--save','','--appendonly','no','--maxmemory','128mb',
                             '--maxmemory-policy','noeviction','--requirepass',password,'--dir',lab.run],'isolation-'+kind)
            client=Redis(port,password)
            def ready():
                try:return 'process_id:'+str(child.pid)+'\r\n' in client.call('INFO','server').decode()
                except OSError:return False
            wait(ready,'owned isolation '+kind)
            prefix='hnuhole:comment-snapshot:v2:dev:*' if kind=='snap' else 'hnuhole:community_dev:*'
            commands=['+get','+set','+setrange','+pexpiretime','+del','+exists','+pttl','+time','+info','+eval','+evalsha','+ping','+hello','+client|setname'] if kind=='snap' else ['+type','+get','+set','+pttl','+time','+zscore','+zcard','+zadd','+zremrangebyscore','+pexpire','+eval','+info','+ping','+hello','+client|setname']
            client.call('ACL','SETUSER',username,'on','>'+password,'~'+prefix,*commands)
            client.call('ACL','SETUSER','community_ratelimit_operator','on','>'+password,'~hnuhole:community_dev:*','+@all')
            for suffix in ['runtime','admin']:
                p=lab.material/(kind+'-'+suffix+'.password');p.write_text(password);p.chmod(0o600)
            clients.append((client,port,child.pid))
        snap,sp,snapPid=clients[0];admission,ap,admissionPid=clients[1]
        cfg=lab.cfg['comments']['snapshots'];cfg['redis'].update(address='127.0.0.1:'+str(sp),passwordFile='snap-runtime.password',epoch=str(uuid.uuid4()))
        snapshot_init=lab.material/'isolation-snapshot.json';dump(snapshot_init,lab.cfg)
        lab.cmd([lab.root/'bin/process-commentsnapshotctl','-config',snapshot_init,'-initialize-new-namespace',
                 '-operator-username','default','-operator-password-file','snap-admin.password'],'isolation-init-snapshot')
        shared=json.loads((lab.source/'infra/ratelimit/community-observe.example.json').read_text())['sharedRateLimit']
        policy=shared['policy'];policy.update(address='127.0.0.1:'+str(ap))
        for rule in policy['rules']:
            rule['mode']='off'
            if rule['action']=='read.account':
                rule.update(mode='enforce',windows=[{'ms':60000,'limit':2}]);rule.pop('bucket',None)
            if rule['action']=='entry.query':rule['mode']='enforce'
        shared.update(keyFile='isolation-admission.key',passwordFile='admission-runtime.password',trustedProxies=[])
        key=lab.material/'isolation-admission.key';key.write_bytes(secrets.token_bytes(32));key.chmod(0o600)
        operator_policy=copy.deepcopy(policy);operator_policy['username']='community_ratelimit_operator'
        database=lab.cfg['databaseUrl'].replace('hnuhole_c_runtime@','hnuhole_c_migrator@')+'&options='+urllib.parse.quote('-c role=hnuhole_c_owner')
        operator={'service':'community','databaseUrl':database,'databasePasswordFile':'operator/db-c-migrator.password',
                  'redisPasswordFile':'admission-admin.password','subjectKeyFile':'isolation-admission.key','policy':operator_policy}
        op=lab.material/'isolation-admission-operator.json';dump(op,operator)
        lab.cmd([lab.root/'bin/process-ratelimitctl','-config',op,'-initialize-new-namespace'],'isolation-init-admission')
        lab.cfg['sharedRateLimit']=shared
        a=lab.start_api('admission-a','127.0.0.5',int(lab.cfg['internalListen'].split(':')[-1]))
        b=lab.start_api('admission-b','127.0.0.6',int(lab.cfg['internalListen'].split(':')[-1]))
        first,_,_=lab.request('127.0.0.5',lab.path,token=lab.tokens[2])
        # The first initial read consumed one account event. OOM cannot erase it.
        generation=lab.sql('SELECT generation FROM c_rate_limit.namespace;')
        memory_before=admission.info()
        snap.call('CONFIG','SET','maxmemory',1)
        old,_,_=lab.request('127.0.0.6',lab.path+'&cursor='+first['nextCursor'],token=lab.tokens[2])
        assert old['snapshotId']==first['snapshotId']
        denied,_,headers=lab.request('127.0.0.5',lab.path+'&cursor='+first['nextCursor'],token=lab.tokens[2],want=429)
        assert denied['error']['code']=='RATE_LIMITED' and int(headers['Retry-After'])>0
        for ip in ['127.0.0.5','127.0.0.6']:
            failure,_,_=lab.request(ip,lab.path,token=lab.tokens[1],want=503)
            assert failure['error']['code']=='COMMENT_SNAPSHOT_CAPACITY'
        denied,_,_=lab.request('127.0.0.6',lab.path,token=lab.tokens[1],want=429)
        assert denied['error']['code']=='RATE_LIMITED'
        assert lab.sql('SELECT generation FROM c_rate_limit.namespace;')==generation
        assert admission.call('CONFIG','GET','maxmemory')[1]==b'134217728'
        results.update(result='PASS',snapshotRedisPid=snapPid,admissionRedisPid=admissionPid,apiPids=[a.pid,b.pid],
                       persistentAccountChargeSurvivesSnapshotOOM=True,crossProcessRateEnforcement=True,
                       snapshotCapacityResponsesDoNotResetAdmission=True,namespaceGenerationUnchanged=True,
                       admissionMemoryBefore=memory_before,admissionMemoryAfter=admission.info())
        results.update(sourceDigest=source_digest(lab.source),apiBinarySHA256=hashlib.sha256((lab.root/'bin/process-api').read_bytes()).hexdigest(),
                       isolatedSQLFixture=True,policyScope='Two-event enforcement fault scenario only; not the performance baseline')
        print('TWO REAL APIS / SQL / SEPARATE REDIS OOM ADMISSION ISOLATION PASS',flush=True)
    except BaseException as error:
        results.update(result='FAIL',error=str(error));raise
    finally:
        dump(lab.run/'api-admission-isolation.json',results)
        dump(parent.run/'api-admission-isolation.json',results)
        lab.cleanup()


if __name__=='__main__':main()
