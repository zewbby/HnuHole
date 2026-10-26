#!/usr/bin/env python3
"""Additional measurements against the live owned run, never an external DSN."""
import argparse
import base64
import copy
import datetime
import json
import math
import os
from pathlib import Path
import secrets
import ssl
import statistics
import time
import urllib.parse
import concurrent.futures

from ledger import decode as decode_ledger
from run import Lab, Redis, b64, dump, wait


def attach(root, source):
    root = root.resolve()
    run = Path(json.loads((root/'process-latest.json').read_text())['run']).resolve()
    assert run.parent == root and run.name.startswith('process-')
    assert run.stat().st_mode & 0o077 == 0
    lab = object.__new__(Lab)
    lab.root, lab.source, lab.run = root, source.resolve(), run
    lab.material, lab.logs = run/'material', run/'logs'
    lab.cfg = json.loads((lab.material/'c.json').read_text())
    query = urllib.parse.parse_qs(urllib.parse.urlparse(lab.cfg['databaseUrl']).query)
    lab.socket, lab.pgport = Path(query['host'][0]), int(query['port'][0])
    assert lab.socket.name.startswith('hnu-snapshot-') and lab.socket.parent == Path('/tmp')
    state = json.loads((run/'state.private.json').read_text())
    lab.tokens, lab.roots, lab.post = state['tokens'], state['roots'], state['post']
    lab.path = '/api/v1/posts/'+lab.post+'/comments?limit=50'
    lab.cport = int(lab.cfg['publicListen'].split(':')[-1])
    lab.trust = ssl.create_default_context(cafile=str(lab.material/'dev-ca.pem'))
    lab.redis = Redis(int(lab.cfg['comments']['snapshots']['redis']['address'].split(':')[-1]), (lab.material/'snapshot-admin.password').read_text())
    lab.processes = []; lab.results = {}
    lab.api = source/'services/api'
    lab.env = {**os.environ, 'PATH': '/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:/mnt/e/Hnuhole-env/linux/bin:'+os.environ.get('PATH','/usr/bin:/bin')}
    lab.env.update(GOPATH=str(root/'go'),GOCACHE=str(root/'go-build'),GOMODCACHE=str(root/'go/pkg/mod'),
                   GOPROXY=os.environ.get('GOPROXY','https://proxy.golang.org,direct'),GOTOOLCHAIN='local',GOFLAGS='-mod=readonly',GOWORK='off')
    assert lab.redis.call('CONFIG', 'GET', 'maxmemory-policy')[1] == b'noeviction'
    return lab


def percentile(values, pct):
    values = sorted(values)
    return values[max(0, math.ceil(len(values)*pct)-1)]


def capacity(lab, results):
    before = lab.redis.info()
    nonce = b64(secrets.token_bytes(16))
    page, _, _ = lab.request('127.0.0.1', lab.path, nonce=nonce)
    ids = [c['id'] for c in page['comments']]
    cursor = page['nextCursor']; pages = 1
    while cursor:
        page, _, _ = lab.request('127.0.0.2' if pages%2 else '127.0.0.1', lab.path+'&cursor='+cursor)
        ids += [c['id'] for c in page['comments']]; cursor = page['nextCursor']; pages += 1
    assert pages == 10 and len(ids) == len(set(ids)) == 500 and set(ids) == set(lab.roots)
    latencies = []
    for i, root in enumerate(ids):
        path = '/api/v1/posts/'+lab.post+'/comments/'+root+'/replies?limit=50'
        replies, ms, _ = lab.request('127.0.0.1' if i%2 else '127.0.0.2', path)
        assert len(replies['comments']) == 2
        latencies.append(ms)
        if (i+1)%100 == 0:
            print('REPLY SNAPSHOTS '+str(i+1), flush=True)
    cfg = lab.cfg['comments']['snapshots']; prefix = cfg['redis']['namespace']; epoch = cfg['redis']['epoch']
    ledgerkey = prefix+'ledger:'+epoch
    ledger = decode_ledger(lab.redis.call('GET', ledgerkey))
    entries = ledger['entries']
    after = lab.redis.info()
    data_memory = [lab.redis.call('MEMORY', 'USAGE', prefix+'data:'+epoch+':'+key) or 0 for key in entries]
    results['reading501'] = {'result': 'PASS', 'pages': pages, 'rootCount': len(ids), 'replySnapshots': 500,
                             'requiredSnapshotCount': 501, 'actualLedgerCount': len(entries),
                             'replyP95Ms': percentile(latencies,.95), 'redisBefore': before, 'redisAfter': after,
                             'ledgerMemoryBytes': lab.redis.call('MEMORY','USAGE',ledgerkey),
                             'dataMemoryTotalBytes': sum(data_memory), 'dataMemoryMaxBytes': max(data_memory),
                             'reservedBytes': cfg['ledgerFixedReserveBytes']+sum(e['cost'] for e in entries.values())}
    owner = max({e['owner'] for e in entries.values()}, key=lambda o: sum(e['owner'] == o for e in entries.values()))
    count = sum(e['owner'] == owner for e in entries.values())
    for i in range(cfg['maxPerAccount']-count):
        lab.request('127.0.0.1' if i%2 else '127.0.0.2', lab.path)
    def excess(i):
        body, _, headers = lab.request('127.0.0.1' if i%2 else '127.0.0.2', lab.path, want=429)
        assert body['error']['code'] == 'RATE_LIMITED' and int(headers['Retry-After']) > 0
        return int(headers['Retry-After'])
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        retry = list(pool.map(excess, range(32)))
    ledger = decode_ledger(lab.redis.call('GET', ledgerkey))
    assert sum(e['owner'] == owner for e in ledger['entries'].values()) == cfg['maxPerAccount']
    results['crossProcessQuota'] = {'result': 'PASS', 'accountQuota': cfg['maxPerAccount'], 'concurrentRejected': len(retry), 'minRetryAfter': min(retry)}
    dump(lab.run/'capacity-performance.json', results)
    print('501 CAPACITY AND SHARED QUOTA PASS', flush=True)


def performance(lab, results):
    # Both choices run exactly this migration code, data, grants, auth and SQL.
    # Only creation routing differs; R cursors remain readable on all instances.
    lab.cfg['comments']['snapshots']['createBackend'] = 'postgres'
    lab.pg_process = lab.start_api('pg-baseline', '127.0.0.3', int(lab.cfg['internalListen'].split(':')[-1]))
    lab.cfg['comments']['snapshots']['createBackend'] = 'redis'
    token = lab.tokens[1]
    paths = {}
    for name, ip in [('postgres','127.0.0.3'), ('redis','127.0.0.1')]:
        first, _, _ = lab.request(ip, lab.path, token=token)
        paths[name] = lab.path+'&cursor='+first['nextCursor']
    records = {'initial': {'postgres': [], 'redis': []}, 'continuation': {'postgres': [], 'redis': []}}
    for kind in records:
        for name, ip in [('postgres','127.0.0.3'), ('redis','127.0.0.1')]:
            path = lab.path if kind == 'initial' else paths[name]
            for _ in range(30):
                lab.request(ip, path, token=token)
        # Alternating AB/BA blocks reduce drift. Raw per-request timings retained.
        for block in range(10):
            order = [('postgres','127.0.0.3'), ('redis','127.0.0.1')]
            if block%2:
                order.reverse()
            for name, ip in order:
                path = lab.path if kind == 'initial' else paths[name]
                for _ in range(30):
                    _, ms, _ = lab.request(ip, path, token=token)
                    records[kind][name].append(ms)
        print('PERFORMANCE '+kind+' sampled', flush=True)
    stats = {}
    for kind, backends in records.items():
        stats[kind] = {name: {'samples': len(samples), 'p50Ms': percentile(samples,.5), 'p95Ms': percentile(samples,.95),
                              'p99Ms': percentile(samples,.99), 'meanMs': statistics.mean(samples)} for name,samples in backends.items()}
        stats[kind]['p95RegressionPercent'] = (stats[kind]['redis']['p95Ms']/stats[kind]['postgres']['p95Ms']-1)*100
        stats[kind]['result'] = 'PASS' if stats[kind]['p95RegressionPercent'] <= 5 else 'FAIL'
    results['performance'] = {'result': 'PASS' if all(v['result']=='PASS' for v in stats.values()) else 'FAIL', 'stats': stats,
                              'metadata': {'protocol': 'HTTPS verified private CA, persistent processes, new TLS connection per call excluded from timed region',
                                           'concurrency': 1, 'warmupPerBackendPerKind': 30, 'samplesPerBackendPerKind': 300,
                                           'mainLimit': 50, 'roots': 500, 'replies': 1000, 'sameAccount': True,
                                           'match': 'same owned DB/SQL/auth/keys, PG and Redis creation routing', 'alternatingABBA': True}, 'rawMilliseconds': records}
    dump(lab.run/'capacity-performance.json', results)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True);parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--capacity-only', action='store_true')
    parser.add_argument('--pace',type=float,default=.27)
    args=parser.parse_args();lab=attach(args.root,args.source);results={'result':'RUNNING'}
    # Each API sees fewer than 2 requests/second during the capacity sequence.
    lab.request_pace_seconds=args.pace
    try:
        capacity(lab, results)
        if not args.capacity_only:
            performance(lab,results)
        results['result']='PASS' if args.capacity_only or results['performance']['result']=='PASS' else 'FAIL'
    except BaseException as error:
        results.update(result='FAIL',error=str(error));raise
    finally:
        dump(lab.run/'capacity-performance.json',results)
        for p,stream,_ in reversed(lab.processes):
            if p.poll() is None:p.terminate()
            p.wait(timeout=20);stream.close()


if __name__=='__main__':
    main()
