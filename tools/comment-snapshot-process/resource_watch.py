"""Read-only shared-load evidence and a gate for local measurement cohorts.

No process arguments, credentials or controls of other tasks are collected.
Pressure invalidates a whole cohort; no individual sample is discarded.
"""
import argparse
import json
import os
from pathlib import Path
import time


POLICY = dict(cpuBusyPercent=65, ioWaitPercent=25, externalBuildCPUPercent=300,
              quietSeconds=20, staleSeconds=15, waitLimitSeconds=600)
BENCHMARKS = {'wrk', 'wrk2', 'hey', 'ab', 'k6', 'stress', 'stress-ng',
              'redis-benchmark', 'sysbench', 'pgbench', 'fio', 'iperf3'}


def raw_time():
    return time.clock_gettime(time.CLOCK_MONOTONIC_RAW)


def wait_quiet():
    directory = os.environ.get('COMMENT_SNAPSHOT_RESOURCE_ROOT')
    if not directory:
        return
    started = raw_time()
    quiet = None
    while raw_time() - started < POLICY['waitLimitSeconds']:
        try:
            state = json.loads((Path(directory) / 'resource-state.json').read_text())
            good = raw_time() - state['rawSeconds'] <= POLICY['staleSeconds'] and not state['pressure']
        except (OSError, ValueError, KeyError):
            good = False
        if good:
            if quiet is None:
                quiet = raw_time()
            if raw_time() - quiet >= POLICY['quietSeconds']:
                return
        else:
            quiet = None
        time.sleep(2)
    raise RuntimeError('shared host has no verified quiet sampling window')


def evidence(start, end):
    directory = os.environ.get('COMMENT_SNAPSHOT_RESOURCE_ROOT')
    if not directory:
        return dict(result='NOT_CONFIGURED')
    root = Path(directory)
    deadline = raw_time() + 15
    while raw_time() < deadline:
        state = json.loads((root / 'resource-state.json').read_text())
        if state['rawSeconds'] >= end:
            break
        time.sleep(1)
    if state['rawSeconds'] < end:
        return dict(result='FAIL', reason='resource watcher stopped before final sample')
    rows = []
    for line in (root / 'resource-observations.jsonl').read_text().splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue  # A concurrent final append is covered by the atomic state.
        if value['rawSeconds'] >= start and value['intervalStartRaw'] <= end:
            rows.append(value)
    bad = [r for r in rows if r['pressure']]
    return dict(result='PASS' if rows and not bad else 'FAIL', policy=POLICY,
                observations=len(rows), pressureObservations=bad,
                maxCPUPercent=max((r['cpuBusyPercent'] for r in rows), default=0),
                maxIOWaitPercent=max((r['ioWaitPercent'] for r in rows), default=0),
                log=str(root / 'resource-observations.jsonl'))


def watch(root, own_source):
    root = root.resolve()
    own_source = own_source.resolve()
    assert root.is_dir() and root.stat().st_mode & 0o077 == 0
    output = root / 'resource-observations.jsonl'
    assert not output.exists(), 'never overwrite resource evidence'
    tick = os.sysconf('SC_CLK_TCK')
    previous_cpu = None
    previous_process = {}
    previous_time = raw_time()
    with output.open('x') as stream:
        while not (root / 'resource-watch.stop').exists():
            now = raw_time()
            cpu = list(map(int, Path('/proc/stat').read_text().splitlines()[0].split()[1:9]))
            delta = [b-a for a,b in zip(previous_cpu, cpu)] if previous_cpu else [0]*8
            total = sum(delta)
            busy = 100*(total-delta[3]-delta[4])/total if total else 0
            io = 100*delta[4]/total if total else 0
            relevant = []
            current_process = {}
            external_build = 0
            benchmark = []
            for p in Path('/proc').iterdir():
                if not p.name.isdigit():
                    continue
                try:
                    name = (p/'comm').read_text().strip()
                    fields = (p/'stat').read_text().rsplit(')', 1)[1].split()
                    used = int(fields[11]) + int(fields[12])
                    uid = p.stat().st_uid
                    try:
                        cwd = Path(os.readlink(p/'cwd'))
                    except OSError:
                        cwd = None
                except (OSError, ValueError, IndexError):
                    continue
                current_process[p.name] = used
                percent = max(0, used-previous_process.get(p.name, used))/tick/max(.001, now-previous_time)*100
                ours = cwd is not None and cwd.is_relative_to(own_source)
                if not ours and name in BENCHMARKS:
                    benchmark.append(dict(pid=int(p.name), name=name))
                if not ours and name in {'go', 'compile', 'link'}:
                    external_build += percent
                if not ours and (name in BENCHMARKS or name in {'go', 'compile', 'link'} or percent >= 25):
                    relevant.append(dict(pid=int(p.name), uid=uid, name=name,
                                         cpuPercent=percent, cwd=str(cwd) if cwd else None))
            reasons = []
            if busy >= POLICY['cpuBusyPercent']: reasons.append('high aggregate CPU')
            if io >= POLICY['ioWaitPercent']: reasons.append('high aggregate IO wait')
            if external_build >= POLICY['externalBuildCPUPercent']: reasons.append('parallel high CPU build')
            if benchmark: reasons.append('external pressure tool active')
            row = dict(rawSeconds=now, intervalStartRaw=previous_time, utcSeconds=time.time(),
                       cpuBusyPercent=busy, ioWaitPercent=io, loadAverage=os.getloadavg(),
                       externalBuildCPUPercent=external_build, externalRelevant=relevant,
                       pressure=bool(reasons), reasons=reasons)
            stream.write(json.dumps(row)+'\n'); stream.flush()
            temporary = root/'resource-state.tmp'
            temporary.write_text(json.dumps(row)+'\n')
            temporary.replace(root/'resource-state.json')
            previous_cpu, previous_process, previous_time = cpu, current_process, now
            time.sleep(5)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--own-source', type=Path, required=True)
    options = parser.parse_args()
    watch(options.root, options.own_source)
