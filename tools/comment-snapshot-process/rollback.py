#!/usr/bin/env python3
"""Actual V1/V2 compatibility, old-table withdrawal and explicit PG switchback."""
import argparse
import base64
import hashlib
import hmac
import json
from pathlib import Path
import time
import uuid

from exercise import attach
from run import b64, dump


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,required=True);parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--wait-for-performance',action='store_true')
    args=parser.parse_args();lab=attach(args.root,args.source);result={'result':'RUNNING','checks':{}};renamed=False
    try:
        if args.wait_for_performance:
            deadline=time.monotonic()+1500
            while time.monotonic()<deadline:
                path=lab.run/'performance-final.json'
                if path.exists() and json.loads(path.read_text()).get('result')!='RUNNING':break
                time.sleep(2)
            else:raise RuntimeError('performance did not finish before withdrawal test')
        cfg=lab.cfg['comments']['snapshots'];cfg['createBackend']='postgres'
        pg=lab.start_api('rollback-pg','127.0.0.11',int(lab.cfg['internalListen'].split(':')[-1]))
        page,_,_=lab.request('127.0.0.11',lab.path,token=lab.tokens[2]);v2=page['nextCursor']
        raw=base64.urlsafe_b64decode(v2+'==');assert raw[1]&3==1
        identity=base64.urlsafe_b64decode(page['snapshotId']+'==');unsigned=identity+(50).to_bytes(4,'big')
        digest=hashlib.sha256(b'HNUHOLE/COMMENT-CURSOR/V1\0'+unsigned).digest()
        tag=hmac.new((lab.material/'comment-fingerprint.key').read_bytes(),b'HNUHOLE/COMMENT-INTENT/V1\0'+digest,hashlib.sha256).digest()
        v1=b64(unsigned+tag)
        for cursor in [v1,v2]:
            old,_,_=lab.request('127.0.0.1',lab.path+'&cursor='+cursor,token=lab.tokens[2]);assert old['snapshotId']==page['snapshotId']
        result['checks']['redisCreationFleetReadsPGV1AndV2']=True
        cfg.update(createBackend='redis',readPostgres=False)
        redis=lab.start_api('rollback-old-table-off','127.0.0.12',int(lab.cfg['internalListen'].split(':')[-1]))
        for cursor in [v1,v2]:
            invalid,_,_=lab.request('127.0.0.12',lab.path+'&cursor='+cursor,token=lab.tokens[2],want=400);assert invalid['error']['code']=='CURSOR_INVALID'
        result['checks']['explicitDisableRejectsPGSource']=True
        lab.sql('ALTER TABLE c_comments.snapshots RENAME TO snapshots_withdrawn_owned;');renamed=True
        first,_,_=lab.request('127.0.0.12',lab.path,token=lab.tokens[2])
        following,_,_=lab.request('127.0.0.12',lab.path+'&cursor='+first['nextCursor'],token=lab.tokens[2]);assert following['snapshotId']==first['snapshotId']
        root=first['comments'][0]['id']
        replies,_,_=lab.request('127.0.0.12','/api/v1/posts/'+lab.post+'/comments/'+root+'/replies',token=lab.tokens[2]);assert len(replies['comments'])==2
        located,_,_=lab.request('127.0.0.12','/api/v1/posts/'+lab.post+'/comments/'+root+'/location',token=lab.tokens[2]);assert located['commentId']==root
        result['checks']['renamedOldTableNotUsedByNewReadQuotaContinuationReplyOrLocate']=True
        lab.sql('ALTER TABLE c_comments.snapshots_withdrawn_owned RENAME TO snapshots;');renamed=False
        switched,_,_=lab.request('127.0.0.11',lab.path,token=lab.tokens[2])
        switchedraw=base64.urlsafe_b64decode(switched['nextCursor']+'==');assert switchedraw[1]&3==1
        stillredis,_,_=lab.request('127.0.0.11',lab.path+'&cursor='+first['nextCursor'],token=lab.tokens[2]);assert stillredis['snapshotId']==first['snapshotId']
        result['checks']['explicitPGCreationSwitchbackKeepsRedisCursorsReadable']=True
        result.update(result='PASS',apiPids=[pg.pid,redis.pid],fixedPGCursorWindowSeconds=1800,
                      apiBinarySHA256=hashlib.sha256((lab.root/'bin/process-api').read_bytes()).hexdigest(),
                      scope='actual process switch paths, not a deployed fleet or a timed production rollout')
        print('REAL V1/V2 / OLD TABLE WITHDRAWAL / EXPLICIT PG SWITCHBACK PASS',flush=True)
    except BaseException as error:result.update(result='FAIL',error=str(error));raise
    finally:
        if renamed:lab.sql('ALTER TABLE c_comments.snapshots_withdrawn_owned RENAME TO snapshots;')
        dump(lab.run/'api-rollback.json',result)
        for child,stream,_ in reversed(lab.processes):
            if child.poll() is None:child.terminate()
            child.wait(timeout=20);stream.close()


if __name__=='__main__':main()
