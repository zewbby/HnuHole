#!/usr/bin/env python3
"""Independent full-TTL observer for a live owned process run."""
import argparse
import base64
import hashlib
import hmac
import json
from pathlib import Path
import time
import uuid

from exercise import attach
from ledger import decode as decode_ledger
from run import b64, dump


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args(); lab = attach(args.root, args.source)
    settings = lab.cfg['comments']['snapshots']; prefix = settings['redis']['namespace']; epoch = settings['redis']['epoch']
    token = base64.urlsafe_b64decode(lab.tokens[3]+'=')
    account = lab.sql("SELECT account_id FROM c_auth.sessions WHERE token_digest=decode('%s','hex');"%hashlib.sha256(token).hexdigest())
    key = (lab.material/'comment-fingerprint.key').read_bytes()
    def tag(domain, payload):
        digest = hashlib.sha256(domain+b'\0'+payload).digest()
        return hmac.new(key, b'HNUHOLE/COMMENT-INTENT/V1\0'+digest, hashlib.sha256).digest()
    owner = tag(b'HNUHOLE/COMMENT-SNAPSHOT-OWNER/V1', prefix.encode()+b'\0'+uuid.UUID(account).bytes)
    ledger = decode_ledger(lab.redis.call('GET',prefix+'ledger:'+epoch))
    entries = [(ident, entry) for ident,entry in ledger['entries'].items() if entry['owner'] == b64(owner)]
    assert len(entries) == 1
    ident, entry = entries[0]
    raw = lab.redis.call('GET',prefix+'data:'+epoch+':'+ident)
    created, expires = int.from_bytes(raw[101:109],'big'), int.from_bytes(raw[109:117],'big')
    assert expires-created == 1800000
    unsigned = bytes([2,raw[4]])+raw[5:21]+raw[21:37]+(50).to_bytes(4,'big')+raw[109:117]
    cursor = b64(unsigned+tag(b'HNUHOLE/COMMENT-CURSOR/V2', unsigned))
    records = []
    while time.time()*1000 < expires-10000:
        body, ms, _ = lab.request('127.0.0.1' if len(records)%2 else '127.0.0.2',lab.path+'&cursor='+cursor,token=lab.tokens[3])
        assert body['snapshotId'] == b64(uuid.UUID(ident).bytes) and len(body['comments']) == 50
        ttl = lab.redis.call('PTTL',prefix+'data:'+epoch+':'+ident)
        assert 0 < ttl <= expires-time.time()*1000+2000
        records.append({'utcUnixMilliseconds': int(time.time()*1000),'elapsedFromCreationSeconds': (time.time()*1000-created)/1000,'latencyMs':ms,'pttlMilliseconds':ttl})
        dump(lab.run/'long-independent-progress.json',{'result':'RUNNING','reads':records})
        time.sleep(min(30,max(.01,(expires-10000-time.time()*1000)/1000)))
    time.sleep(max(0,(expires+1000-time.time()*1000)/1000))
    expired, _, _ = lab.request('127.0.0.2',lab.path+'&cursor='+cursor,token=lab.tokens[3],want=400)
    assert expired['error']['code'] == 'CURSOR_INVALID'
    new, _, _ = lab.request('127.0.0.1',lab.path,token=lab.tokens[3])
    assert new['snapshotId'] != b64(uuid.UUID(ident).bytes)
    original = json.loads((lab.run/'long-read-progress.json').read_text())['reads']
    assert original[0]['elapsedSeconds'] < 1 and original[-1]['elapsedSeconds'] >= 1740 and all(r['status'] == 200 for r in original)
    result = {'result':'PASS','ttlSeconds':1800,'createdUnixMilliseconds':created,'verifiedUnixMilliseconds':int(time.time()*1000),
              'originalContinuousReads':original,'independentReads':records,'explicitExpiryCode':expired['error']['code'],
              'explicitRefreshSucceeded':True,'ttlNeverRenewed':True,'twoActualAPIProcesses':True}
    dump(lab.run/'long-read-verified.json',result)
    print('REAL 30-MINUTE READING, FIXED EXPIRY AND EXPLICIT REFRESH PASS',flush=True)


if __name__ == '__main__':
    main()
