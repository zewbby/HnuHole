#!/usr/bin/env python3
"""Fault injection owns a separate Redis and a real additional cmd/api child."""
import argparse
import copy
import json
from pathlib import Path
import secrets
import socket
import time
import uuid

from exercise import attach
from run import Redis, dump, wait


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--redis', type=Path, required=True)
    args = parser.parse_args(); lab = attach(args.root, args.source)
    results = {'result':'RUNNING','actualAPICommandProcess':True,'separateFaultRedis':True,'checks':{}}
    with socket.socket() as s:
        s.bind(('127.0.0.1',0)); port=s.getsockname()[1]
    password = secrets.token_hex(32)
    lab.env['LD_LIBRARY_PATH']=str(args.redis.parent.parent/'lib/x86_64-linux-gnu')
    redisargs=[args.redis,'--bind','127.0.0.1','--port',port,'--save','','--appendonly','no','--maxmemory','128mb','--maxmemory-policy','noeviction','--requirepass',password,'--dir',lab.run]
    try:
        child=lab.spawn(redisargs,'fault-redis')
        client=Redis(port,password)
        def ready():
            try:return 'process_id:'+str(child.pid)+'\r\n' in client.call('INFO','server').decode()
            except OSError:return False
        wait(ready,'owned fault Redis')
        client.call('ACL','SETUSER','community_comment_snapshot_v2','on','>'+password,'~hnuhole:comment-snapshot:v2:dev:*',
                    '+get','+set','+setrange','+pexpiretime','+del','+exists','+pttl','+time','+info','+eval','+evalsha','+ping','+hello','+client|setname')
        for name in ['fault.password','fault-admin.password']:
            (lab.material/name).write_text(password);(lab.material/name).chmod(0o600)
        cfg=lab.cfg['comments']['snapshots'];cfg['redis'].update(address='127.0.0.1:'+str(port),passwordFile='fault.password',epoch=str(uuid.uuid4()))
        path=lab.material/'c-fault-init.json';dump(path,lab.cfg)
        lab.cmd([lab.root/'bin/process-commentsnapshotctl','-config',path,'-initialize-new-namespace','-operator-username','default','-operator-password-file','fault-admin.password'],'fault-initialize')
        process=lab.start_api('fault','127.0.0.4',int(lab.cfg['internalListen'].split(':')[-1]))
        token=lab.tokens[2]
        first,_,_=lab.request('127.0.0.4',lab.path,token=token)
        cursor=first['nextCursor']; route=lab.path+'&cursor='+cursor
        def code(path,status,want,request_token=token):
            body,ms,_=lab.request('127.0.0.4',path,token=request_token,want=status)
            assert body['error']['code']==want,body
            return ms
        code(route,400,'CURSOR_INVALID',lab.tokens[1]);results['checks']['crossAccount']=True
        tampered=cursor[:-1]+('A' if cursor[-1]!='A' else 'B')
        code(lab.path+'&cursor='+tampered,400,'CURSOR_INVALID');results['checks']['cursorMAC']=True
        code('/api/v1/posts/'+lab.post+'/comments/'+lab.roots[0]+'/replies?expanded=true&cursor='+cursor,400,'CURSOR_INVALID');results['checks']['cursorKind']=True
        original_generation=lab.sql("SELECT session_generation FROM c_auth.accounts WHERE account_id=(SELECT account_id FROM c_auth.sessions WHERE token_digest=decode('%s','hex'));"%__import__('hashlib').sha256(__import__('base64').urlsafe_b64decode(token+'=')).hexdigest())
        tokenhash=__import__('hashlib').sha256(__import__('base64').urlsafe_b64decode(token+'=')).hexdigest()
        account=lab.sql("SELECT account_id FROM c_auth.sessions WHERE token_digest=decode('%s','hex');"%tokenhash)
        lab.sql("UPDATE c_auth.accounts SET session_generation=session_generation+1 WHERE account_id='%s';"%account)
        # Production response distinguishes session replacement from cursor loss.
        body,_,_=lab.request('127.0.0.4',route,token=token,want=401)
        assert body['error']['code'] in ['SESSION_REPLACED','SESSION_INVALID']
        lab.sql("BEGIN;SET LOCAL session_replication_role=replica;UPDATE c_auth.accounts SET session_generation=%s WHERE account_id='%s';COMMIT;"%(original_generation,account))
        results['checks']['sessionGenerationRechecked']=True
        prefix=cfg['redis']['namespace'];epoch=cfg['redis']['epoch']
        import base64
        ident=str(uuid.UUID(bytes=base64.urlsafe_b64decode(first['snapshotId']+'==')))
        key=prefix+'data:'+epoch+':'+ident;payload=client.call('GET',key)
        count_sql="SELECT count(*) FROM c_comments.snapshots WHERE owner_account_id='%s';"%account
        count=lab.sql(count_sql)
        corrupt=payload[:-1]+bytes([payload[-1]^1]);client.call('SET',key,corrupt,'KEEPTTL')
        code(route,503,'COMMENT_SNAPSHOT_INTEGRITY');client.call('SET',key,payload,'KEEPTTL')
        results['checks']['payloadIntegrityNoFallback']=True
        client.call('CONFIG','SET','maxmemory',1)
        old,_,_=lab.request('127.0.0.4',route,token=token);assert old['snapshotId']==first['snapshotId']
        code(lab.path,503,'COMMENT_SNAPSHOT_CAPACITY')
        client.call('CONFIG','SET','maxmemory','128mb');results['checks']['actualOOMOldReadAndNewCapacity']=True
        client.call('DEL',key);code(route,400,'CURSOR_INVALID');results['checks']['dataLossIsInvalid']=True
        second,_,_=lab.request('127.0.0.4',lab.path,token=token)
        secondroute=lab.path+'&cursor='+second['nextCursor']
        client.call('DEL',prefix+'ledger:'+epoch);code(lab.path,503,'COMMENT_SNAPSHOT_INTEGRITY')
        old,_,_=lab.request('127.0.0.4',secondroute,token=token);assert old['snapshotId']==second['snapshotId']
        results['checks']['ledgerLossBlocksNewButKeepsImmutableOldRead']=True
        child.terminate();child.wait(timeout=10)
        ms=code(secondroute,503,'COMMENT_SNAPSHOT_UNAVAILABLE')
        assert ms<1000;results['checks']['transportFailureBoundedNoFallback']=True
        # Fresh process at the same owned address has lost its control state.
        child=lab.spawn(redisargs,'fault-redis-restart');wait(ready,'restarted owned Redis')
        client.call('ACL','SETUSER','community_comment_snapshot_v2','on','>'+password,'~hnuhole:comment-snapshot:v2:dev:*',
                    '+get','+set','+setrange','+pexpiretime','+del','+exists','+pttl','+time','+info','+eval','+evalsha','+ping','+hello','+client|setname')
        code(secondroute,503,'COMMENT_SNAPSHOT_INTEGRITY');code(lab.path,503,'COMMENT_SNAPSHOT_INTEGRITY')
        assert client.call('GET',prefix+'control') is None
        results['checks']['actualRedisRestartDoesNotAutoInitialize']=True
        assert lab.sql(count_sql)==count
        results['checks']['oldPostgresSnapshotCountUnchangedAcrossFailures']=True
        results['result']='PASS';results['faultTransportMilliseconds']=ms
        print('REAL API FAULTS PASS '+str(len(results['checks'])),flush=True)
    except BaseException as error:
        results.update(result='FAIL',error=str(error));raise
    finally:
        dump(lab.run/'api-faults.json',results)
        for p,stream,_ in reversed(lab.processes):
            if p.poll() is None:p.terminate()
            p.wait(timeout=20);stream.close()


if __name__=='__main__':
    main()
