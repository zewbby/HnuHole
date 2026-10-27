"""One predeclared two-mode attempt; no retry, pooling or TTL rerun."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess

from resource_watch import wait_quiet
from run import dump, source_digest


def decompose(value):
    output = {}
    for kind, sources in value.get('requests', {}).items():
        output[kind] = {}
        for backend, rows in sources.items():
            if not rows or any('serverTiming' not in row for row in rows):
                continue
            cutoff = value['stats'][kind][backend]['p95Ms']
            output[kind][backend] = {}
            for label, selected in [('all', rows), ('p95Tail', [r for r in rows if r['latencyMs'] >= cutoff])]:
                names = sorted({key for r in selected for key in r['serverTiming']['stages']})
                output[kind][backend][label] = dict(samples=len(selected),
                    httpMeanMs=statistics.mean(r['latencyMs'] for r in selected),
                    serverMeanMs=statistics.mean(r['serverTiming']['elapsedMilliseconds'] for r in selected),
                    transportResidualMeanMs=statistics.mean(r['latencyMs']-r['serverTiming']['elapsedMilliseconds'] for r in selected),
                    stageMeanMs={name: statistics.mean(r['serverTiming']['stages'].get(name, {}).get('nanoseconds', 0)/1e6 for r in selected) for name in names})
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--binary-dir', type=Path, required=True)
    parser.add_argument('--redis', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve(); source = args.source.resolve()
    manifest = json.loads((args.binary_dir/'binary-manifest.json').read_text())
    assert source_digest(source) == manifest['sourceDigest']
    for name, digest in manifest['binaries'].items():
        assert hashlib.sha256((args.binary_dir/('process-'+name)).read_bytes()).hexdigest() == digest
    harness = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in sorted((source/'tools/comment-snapshot-process').glob('*.py'))}
    dump(root/'harness-manifest.json', harness)
    env = dict(os.environ, COMMENT_SNAPSHOT_BINARY_DIR=str(args.binary_dir))
    result = dict(result='RUNNING', scope='ONE_PREDECLARED_FORMAL_ATTEMPT',
                  sourceDigest=manifest['sourceDigest'], apiBinarySHA256=manifest['binaries']['api'], modes={})
    try:
        for mode in ['compatibility', 'steady']:
            wait_quiet()
            assert source_digest(source) == manifest['sourceDigest']
            assert all(hashlib.sha256((source/name).read_bytes()).hexdigest() == digest for name, digest in harness.items())
            child = root/mode; child.mkdir(mode=0o700)
            for cache in ['go', 'go-build']: (child/cache).symlink_to(root/cache, target_is_directory=True)
            with (root/(mode+'.private.log')).open('wb') as stream:
                run = subprocess.run(['python3', str(source/'tools/comment-snapshot-process/normalized.py'),
                    '--root', str(child), '--source', str(source), '--redis', str(args.redis),
                    '--mode', mode, '--observe-phases'], env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=4500)
            directory = Path(json.loads((child/'process-latest.json').read_text())['run'])
            raw = directory/'normalized-performance.json'; value = json.loads(raw.read_text())
            result['modes'][mode] = dict(result=value['result'], returncode=run.returncode,
                raw=str(raw), rawSHA256=hashlib.sha256(raw.read_bytes()).hexdigest(),
                stats=value.get('stats', {}), resourceEvidence=value.get('sharedResourceEvidence'),
                phaseDecomposition=decompose(value))
            dump(root/'targeted-summary.json', result)
            print(mode+' '+value['result'], flush=True)
            for kind, stat in value.get('stats', {}).items():
                print(mode+' '+kind+' '+stat['result']+' '+str(round(stat['p95RegressionPercent'], 3))+'%', flush=True)
            if value.get('error') or value.get('errors') or not value.get('sharedResourceEvidence') or value['sharedResourceEvidence']['result'] != 'PASS':
                raise RuntimeError('request/environment/observation failure; no automatic next cohort or retry')
            if any(stat['environmentResult'] != 'PASS' for stat in value['stats'].values()):
                raise RuntimeError('clock guard failure; no automatic next cohort or retry')
        result['result'] = 'PASS' if all(v['result'] == 'PASS' for v in result['modes'].values()) else 'FAIL'
    except BaseException as error:
        result.update(result='FAIL', error=str(error)); raise
    finally:
        dump(root/'targeted-summary.json', result)
    if result['result'] != 'PASS': raise SystemExit(1)


if __name__ == '__main__':
    main()
