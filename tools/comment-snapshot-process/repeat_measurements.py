#!/usr/bin/env python3
"""Fixed three-cohort precision extension, retaining every individual result.

Reuse the exact first campaign binaries. Never average percentiles or select
passing cohorts: pool every raw latency for the same mode/path/backend.
The first campaign's independent functional and real-time proofs are required.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess

from exercise import percentile
from resource_watch import wait_quiet
from run import dump, source_digest


COUNTS = dict(initial=200, continuation=1000, replyPreview=300, replyExpanded=300)
PARITY = ['sourceDigest', 'apiBinarySHA256', 'totalCommentRows', 'concurrency',
          'requestPaceSeconds', 'seed', 'mode', 'configs', 'sameProcessContinuation',
          'observeReadTimings', 'httpElapsedClock', 'sharedAdmissionProfileSHA256',
          'localQueryCapacity', 'workerIntervalSeconds', 'cleanupIntervalSeconds',
          'runtimeNumericAndBooleanConfig']


def read_cohort(root, mode, expected):
    run = Path(json.loads((root/'process-latest.json').read_text())['run'])
    value = json.loads((run/'normalized-performance.json').read_text())
    assert value['mode'] == mode and not value['errors']
    assert value['scope'] == 'ACCEPTANCE'
    assert value['metadata']['sourceDigest'] == expected['sourceDigest']
    assert value['metadata']['apiBinarySHA256'] == expected['binaries']['api']
    assert value['sharedResourceEvidence']['result'] == 'PASS'
    assert set(value['stats']) == set(COUNTS)
    for kind, count in COUNTS.items():
        assert value['stats'][kind]['environmentResult'] == 'PASS'
        for backend in ['postgres', 'redis']:
            assert len(value['requests'][kind][backend]) == count
    return value, run/'normalized-performance.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--first-campaign', type=Path, required=True)
    parser.add_argument('--redis', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve(); source = args.source.resolve(); first = args.first_campaign.resolve()
    assert root.is_dir() and root.stat().st_mode & 0o077 == 0
    original = json.loads((first/'campaign-summary.json').read_text())
    for name, check in original['checks'].items():
        if not name.startswith('performance-'):
            assert check['result'] == 'PASS', ('first nonperformance check', name)
    for name in ['exercise', 'faults', 'admission', 'growth', 'rollback', 'drain',
                 'cross-process-and-restart', 'redis-real-time', 'compatibility-real-time']:
        assert original['checks'][name]['result'] == 'PASS'
    manifest = json.loads((first/'bin/binary-manifest.json').read_text())
    assert source_digest(source) == manifest['sourceDigest']
    harness = json.loads((first/'harness-manifest.json').read_text())
    for name, digest in harness.items():
        assert hashlib.sha256((source/name).read_bytes()).hexdigest() == digest, ('harness changed', name)
    for name, digest in manifest['binaries'].items():
        assert hashlib.sha256((first/'bin'/('process-'+name)).read_bytes()).hexdigest() == digest
    env = dict(os.environ, COMMENT_SNAPSHOT_BINARY_DIR=str(first/'bin'))
    result = dict(result='RUNNING', protocol='FIXED_THREE_COHORT_ALL_RAW_SAMPLES',
                  firstCampaign=str(first), sourceDigest=manifest['sourceDigest'],
                  apiBinarySHA256=manifest['binaries']['api'], cohortCount=3,
                  individualResults={}, pooled={}, noProductParameterChanges=True)
    cohorts = {mode: [] for mode in ['compatibility', 'steady']}
    try:
        for mode in cohorts:
            value, path = read_cohort(first/('performance-'+mode), mode, manifest)
            cohorts[mode].append(value)
            result['individualResults'][mode+'-1'] = dict(result=value['result'], path=str(path))
        for repetition in [2, 3]:
            for mode in cohorts:
                wait_quiet()
                assert source_digest(source) == manifest['sourceDigest']
                name = mode+'-'+str(repetition)
                child = root/name; child.mkdir(mode=0o700)
                for cache in ['go', 'go-build']:
                    (child/cache).symlink_to(root/cache, target_is_directory=True)
                with (root/(name+'.private.log')).open('wb') as stream:
                    completed = subprocess.run(['python3', str(source/'tools/comment-snapshot-process/normalized.py'),
                                                '--root', str(child), '--source', str(source),
                                                '--redis', str(args.redis), '--mode', mode],
                                               env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=4500)
                value, path = read_cohort(child, mode, manifest)
                assert completed.returncode in (0, 1)
                for key in PARITY:
                    assert value['metadata'][key] == cohorts[mode][0]['metadata'][key], (name, key)
                for kind in COUNTS:
                    assert value['stats'][kind]['occupancyAfter'] == cohorts[mode][0]['stats'][kind]['occupancyAfter']
                cohorts[mode].append(value)
                result['individualResults'][name] = dict(result=value['result'], path=str(path), returncode=completed.returncode)
                dump(root/'repeat-summary.json', result)
                print(name+' individual '+value['result']+' (retained)', flush=True)
        for mode, values in cohorts.items():
            assert len(values) == 3
            result['pooled'][mode] = {}
            for kind, count in COUNTS.items():
                stat = {}
                for backend in ['postgres', 'redis']:
                    samples = [r['latencyMs'] for value in values for r in value['requests'][kind][backend]]
                    assert len(samples) == 3*count
                    stat[backend] = dict(samples=len(samples), p50Ms=percentile(samples, .5),
                                         p95Ms=percentile(samples, .95), p99Ms=percentile(samples, .99),
                                         meanMs=statistics.mean(samples))
                stat['p95RegressionPercent'] = (stat['redis']['p95Ms']/stat['postgres']['p95Ms']-1)*100
                stat['result'] = 'PASS' if stat['p95RegressionPercent'] <= 5 else 'FAIL'
                result['pooled'][mode][kind] = stat
                print(mode+' '+kind+' pooled '+stat['result']+' '+str(round(stat['p95RegressionPercent'], 3))+'%', flush=True)
        result['result'] = 'PASS' if all(v['result'] == 'PASS' for values in result['pooled'].values() for v in values.values()) else 'FAIL'
        assert source_digest(source) == manifest['sourceDigest']
    except BaseException as error:
        result.update(result='FAIL', error=str(error))
        raise
    finally:
        dump(root/'repeat-summary.json', result)
    if result['result'] != 'PASS':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
