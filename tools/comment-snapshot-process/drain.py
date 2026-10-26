#!/usr/bin/env python3
"""Explicit operator drain against the campaign's owned final fixture."""
import argparse
import json
from pathlib import Path

from exercise import attach
from ledger import decode
from run import dump


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--source',type=Path,required=True)
    args=parser.parse_args();lab=attach(args.root,args.source)
    owner=json.loads((lab.run/'fixture-owner.json').read_text())
    assert 'process_id:'+str(owner['snapshotRedisPid'])+'\r\n' in lab.redis.call('INFO','server').decode()
    result={'result':'RUNNING','checks':{}}
    try:
        first,_,_=lab.request('127.0.0.1',lab.path,token=lab.tokens[3])
        cfg=lab.cfg['comments']['snapshots']['redis'];prefix=cfg['namespace']
        key=prefix+'ledger:'+cfg['epoch']
        before=set(decode(lab.redis.call('GET',key))['entries'])
        for index in range(2):
            lab.cmd([lab.root/'bin/process-commentsnapshotctl','-config',lab.material/'c.json','-drain',
                     '-operator-username','default','-operator-password-file','snapshot-admin.password'],
                    'explicit-drain-'+str(index))
        assert json.loads(lab.redis.call('GET',prefix+'control'))['state']=='DRAINING'
        old,_,_=lab.request('127.0.0.2',lab.path+'&cursor='+first['nextCursor'],token=lab.tokens[3])
        assert old['snapshotId']==first['snapshotId']
        failed,_,_=lab.request('127.0.0.2',lab.path,token=lab.tokens[3],want=503)
        assert failed['error']['code']=='COMMENT_SNAPSHOT_UNAVAILABLE'
        after=set(decode(lab.redis.call('GET',key))['entries'])
        assert after.issubset(before)  # background expiry may legitimately remove old entries
        result.update(result='PASS',entriesBefore=len(before),entriesAfter=len(after),checks=dict(operatorCLIIdempotent=True,oldCursorReadable=True,
                                               newPreparationBlocked=True,noNewReservation=True))
        print('EXPLICIT OPERATOR DRAIN PASS',flush=True)
    finally:
        dump(lab.run/'api-drain.json',result)


if __name__=='__main__':main()
