#!/usr/bin/env python3
"""Real 30-minute PG -> Redis compatibility interval, not an accelerated clock."""
import argparse
import base64
import hashlib
import hmac
import json
from pathlib import Path
import time

from run import Lab, b64, dump, source_digest, elapsed_clock, host_clock, host_clock_summary


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,required=True);parser.add_argument('--source',type=Path,required=True);parser.add_argument('--redis',type=Path,required=True)
    args=parser.parse_args();parent=args.root.resolve();nested=parent/'compatibility';nested.mkdir(mode=0o700)
    for name in ['go','go-build']:(nested/name).symlink_to(parent/name,target_is_directory=True)
    args.root=nested;args.duration=1805;args.suite='reading';args.shared_admission='official';lab=Lab(args);result={'result':'RUNNING','actualWallInterval':True};renamed=False
    try:
        lab.setup()
        lab.a.terminate();lab.a.wait(timeout=20)
        lab.cfg['comments']['snapshots']['createBackend']='postgres'
        creator=lab.start_api('compatibility-pg-creator','127.0.0.1',int(lab.cfg['internalListen'].split(':')[-1]))
        pg,_,_=lab.request('127.0.0.1',lab.path,token=lab.tokens[2]);v2=pg['nextCursor']
        expires=int.from_bytes(base64.urlsafe_b64decode(v2+'==')[38:46],'big')
        identity=base64.urlsafe_b64decode(pg['snapshotId']+'==');unsigned=identity+(50).to_bytes(4,'big')
        digest=hashlib.sha256(b'HNUHOLE/COMMENT-CURSOR/V1\0'+unsigned).digest()
        tag=hmac.new((lab.material/'comment-fingerprint.key').read_bytes(),b'HNUHOLE/COMMENT-INTENT/V1\0'+digest,hashlib.sha256).digest()
        v1=b64(unsigned+tag)
        creator.terminate();creator.wait(timeout=20);stopped=elapsed_clock();stopped_mono=time.monotonic();stopped_unix=time.time();host_initial=host_clock()
        lab.cfg['comments']['snapshots']['createBackend']='redis'
        lab.a=lab.start_api('compatibility-redis-creator','127.0.0.1',int(lab.cfg['internalListen'].split(':')[-1]))
        records=[]
        def observe():
            mono=elapsed_clock();linux_mono=time.monotonic();utc=time.time();clock=lab.redis.call('TIME')
            return dict(elapsedAfterLastPGCreatorStoppedSeconds=mono-stopped,
                        utcUnixMilliseconds=round(utc*1000),redisUnixMilliseconds=int(clock[0])*1000+int(clock[1])//1000,
                        postgresUnixMilliseconds=int(lab.sql("SELECT floor(extract(epoch FROM clock_timestamp())*1000)::bigint;")),
                        utcMonotonicDriftSeconds=(utc-stopped_unix)-(linux_mono-stopped_mono),
                        utcRawDriftSeconds=(utc-stopped_unix)-(mono-stopped),
                        monotonicRawDriftSeconds=(linux_mono-stopped_mono)-(mono-stopped))
        initial=observe()
        while max(time.time()*1000,observe()['postgresUnixMilliseconds'])<expires-10000:
            for version,cursor in [('V1',v1),('V2',v2)]:
                body,ms,_=lab.request('127.0.0.1' if len(records)%2 else '127.0.0.2',lab.path+'&cursor='+cursor,token=lab.tokens[2])
                assert body['snapshotId']==pg['snapshotId'] and len(body['comments'])==50
                records.append({'version':version,'elapsedAfterLastPGCreatorStoppedSeconds':elapsed_clock()-stopped,'latencyMs':ms,'status':200,'observation':observe()})
            assert lab.sql('SELECT count(*) FROM c_comments.snapshots;')=='1'
            dump(parent/'compatibility-progress.json',{'result':'RUNNING','reads':records,'stoppedUnixSeconds':stopped_unix,'signedExpiryUnixMilliseconds':expires,'initial':initial})
            time.sleep(min(30,max(.01,(expires-10000-time.time()*1000)/1000)))
        while True:
            final=observe()
            if final['elapsedAfterLastPGCreatorStoppedSeconds']>=1801 and min(final['utcUnixMilliseconds'],final['postgresUnixMilliseconds'])>expires+1000:break
            time.sleep(2)
        drift=max(max(abs(o['utcRawDriftSeconds']),abs(o['monotonicRawDriftSeconds'])) for o in [initial,final]+[r['observation'] for r in records])
        host_final=host_clock();host_summary=host_clock_summary(host_initial,host_final)
        if host_summary is not None and (not host_summary['stable'] or host_summary['elapsedSeconds']<1800):drift=max(drift,3)
        if drift>2:raise RuntimeError('ENVIRONMENT_UNSTABLE: PG compatibility UTC/monotonic/raw/host clock stability failed')
        for cursor in [v1,v2]:
            expired,_,_=lab.request('127.0.0.1',lab.path+'&cursor='+cursor,token=lab.tokens[2],want=400)
            assert expired['error']['code']=='CURSOR_INVALID'
        # Only after the actual transition interval disable legacy reads.
        lab.cfg['comments']['snapshots']['readPostgres']=False
        off=lab.start_api('compatibility-pg-reads-off','127.0.0.12',int(lab.cfg['internalListen'].split(':')[-1]))
        lab.sql('ALTER TABLE c_comments.snapshots RENAME TO snapshots_after_full_transition;');renamed=True
        redis,_,_=lab.request('127.0.0.12',lab.path,token=lab.tokens[2])
        nextpage,_,_=lab.request('127.0.0.12',lab.path+'&cursor='+redis['nextCursor'],token=lab.tokens[2]);assert nextpage['snapshotId']==redis['snapshotId']
        root=redis['comments'][0]['id']
        reply,_,_=lab.request('127.0.0.12','/api/v1/posts/'+lab.post+'/comments/'+root+'/replies',token=lab.tokens[2]);assert len(reply['comments'])==2
        location,_,_=lab.request('127.0.0.12','/api/v1/posts/'+lab.post+'/comments/'+root+'/location',token=lab.tokens[2]);assert location['commentId']==root
        lab.sql('ALTER TABLE c_comments.snapshots_after_full_transition RENAME TO snapshots;');renamed=False
        lab.cfg['comments']['snapshots'].update(createBackend='postgres',readPostgres=True)
        back=lab.start_api('compatibility-explicit-pg-switchback','127.0.0.13',int(lab.cfg['internalListen'].split(':')[-1]))
        new,_,_=lab.request('127.0.0.13',lab.path,token=lab.tokens[2]);assert base64.urlsafe_b64decode(new['nextCursor']+'==')[1]&3==1
        existing,_,_=lab.request('127.0.0.13',lab.path+'&cursor='+redis['nextCursor'],token=lab.tokens[2]);assert existing['snapshotId']==redis['snapshotId']
        result.update(result='PASS',elapsedClock='CLOCK_MONOTONIC_RAW',hostClockInitial=host_initial,hostClockFinal=host_final,hostClockSummary=host_summary,signedExpiryUnixMilliseconds=expires,initial=initial,final=final,maximumClockDriftSeconds=drift,elapsedAfterLastPGCreatorStoppedSeconds=elapsed_clock()-stopped,reads=records,
                      pgCursorExpiresWithoutRenewal=True,pgV1AndV2ReadableThroughoutCompatibilityInterval=True,
                      noPostgresSnapshotCreationDuringTransition=True,oldTableWithdrawnAfterActualThirtyMinutes=True,
                      normalRedisReadsQuotaRepliesAndLocateWithRenamedOldTable=True,explicitPGSwitchbackKeepsRedisCursors=True,
                      apiBinarySHA256=hashlib.sha256((nested/'bin/process-api').read_bytes()).hexdigest(),
                      sourceDigest=source_digest(lab.source),sharedAdmissionMode='official-observe-profile',
                      fixture=str(lab.run),deployment=False)
        print('ACTUAL 30-MINUTE PG V1/V2 COMPATIBILITY, WITHDRAWAL AND SWITCHBACK PASS',flush=True)
    except BaseException as error:result.update(result='FAIL',error=str(error));raise
    finally:
        if renamed:lab.sql('ALTER TABLE c_comments.snapshots_after_full_transition RENAME TO snapshots;')
        dump(parent/'compatibility-summary.json',result);lab.cleanup()


if __name__=='__main__':main()
