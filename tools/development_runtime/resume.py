"""Resume an explicitly pinned, same-machine Linux development deployment.

The private manifest is installed by the environment owner; never discover a
release from directory mtimes or silently fall back to an older deployment.
"""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time


class ResumeError(Exception):
    pass


def require(ok, code):
    if not ok:
        raise ResumeError(code)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def private(path, directory=False):
    path = Path(path)
    require(path.is_absolute() and not path.is_symlink(), 'private-path')
    st = path.stat()
    require(st.st_uid == os.getuid() and st.st_mode & 0o077 == 0,
            'private-owner-mode')
    require(path.is_dir() if directory else path.is_file(), 'private-kind')


def load(path):
    private(Path(path).parent, True)
    private(path)
    d = json.loads(Path(path).read_text())
    require(d['format'] == 'DEVELOPMENT-RESUME/1', 'manifest-format')
    require(set(d['config']) == set(d['operators']) == {'c', 'v'}, 'parties')
    required = {d['adapter'], d['receipt'], d['deploymentState'],
                d['snapshotRedis']['config'], d['snapshotRedis']['acl'],
                *d['config'].values(), *d['operators'].values(),
                *(str(Path(d['bin']) / n) for n in ('community', 'verifier', 'authdev'))}
    require(required <= set(d['files']), 'manifest-coverage')
    required.update(d.get('dependencyFiles', []))
    for db in d.get('databases', []):
        required.update([db['pgctl'], db['postgres']])
    require(required <= set(d['files']), 'dependency-coverage')
    for p, digest in d['files'].items():
        require(Path(p).is_absolute() and sha(p) == digest, 'pinned-file-drift')
    receipt = json.loads(Path(d['receipt']).read_text())
    state = json.loads(Path(d['deploymentState']).read_text())
    require(receipt['source'] == state['sourceSha'] == d['source'], 'source-drift')
    require(receipt['result'] == 'PASS_ENABLED_DAILY_DEVELOPMENT' and
            state['phase'] == 'PASS_ENABLED', 'deployment-not-approved')
    for name in ('community', 'verifier', 'authdev'):
        require(sha(Path(d['bin']) / name) == receipt['binarySHA256'][name],
                'receipt-binary-drift')
    return d


def adapter(d):
    spec = importlib.util.spec_from_file_location('pinned_resume_adapter', d['adapter'])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.owned()
    verify_adapter_inputs(d, module)
    shared = module.state()
    require(shared['sourceSha'] == d['adapterState']['sourceSha'] and
            shared['phase'] == d['adapterState']['phase'], 'adapter-state-drift')
    require(str(module.ROOT) == d['adapterState']['root'], 'adapter-root-drift')
    return module


def verify_adapter_inputs(d, m):
    # The pinned adapter also reads these legacy-named inputs for SQL and
    # the two shared Redis instances. Their names do NOT select API versions.
    required = {str(m.REDIS)}
    configs = [*m.OLD_CONFIG.values(), *m.OLD_OP.values(),
               *map(Path, d['config'].values()), *map(Path, d['operators'].values())]
    for p in 'cv':
        directory = m.ROOT / ('redis-' + p)
        required.update(str(directory / n) for n in ('redis.conf', 'users.acl'))
        configs.append(directory / 'operator.json')
    def refs(value, base, key=''):
        if isinstance(value, dict):
            for k, v in value.items():
                if k not in ('evidenceFile', 'anchorFile'):
                    refs(v, base, k)
        elif isinstance(value, list):
            for v in value:
                refs(v, base, key)
        elif isinstance(value, str) and value and (key.endswith('File') or key.endswith('Files') or key in ('communityConfig', 'verifierConfig')):
            path = Path(os.path.abspath(base / value))
            required.add(str(path))
            if key in ('communityConfig', 'verifierConfig'):
                refs(json.loads(path.read_text()), path.parent)
    for config in configs:
        required.add(str(config))
        refs(json.loads(Path(config).read_text()), Path(config).parent)
    require(required <= set(d['files']), 'adapter-input-coverage')


def checkpoint(m):
    result = {}
    for p in 'cv':
        schema = int(m.sql(p, 'SELECT max(version_id) FROM public.goose_db_version WHERE is_applied'))
        gate = json.loads(m.sql(p, "SELECT json_build_object('state',gate_state,'generation',authorization_generation,'recoverEvents',(SELECT count(*) FROM " + p + "_auth.authorization_gate_audit WHERE event_kind='RECOVER')) FROM " + p + '_auth.authorization_gate'))
        require(gate['state'] == 'OPEN', 'gate-not-open')
        result[p] = dict(schema=schema, gate=gate)
    return result


def pg_start(m, d):
    for db in d['databases']:
        data = Path(db['data'])
        require(data.resolve() == data and (data / 'PG_VERSION').read_text().strip() == '16', 'database-path')
        status = subprocess.run([db['pgctl'], '-D', str(data), 'status'], capture_output=True).returncode
        if status == 0:
            pid = int((data / 'postmaster.pid').read_text().splitlines()[0])
            proc = m.proc(pid)
            require(Path('/proc', str(pid)).stat().st_uid == os.getuid() and
                    proc['binarySHA256'] == d['files'][db['postgres']] and
                    proc['args'][1:3] == ['-D', str(data)], 'database-process-drift')
        else:
            require(status == 3, 'database-status')
            import shlex
            m.run([db['pgctl'], '-D', str(data), '-l', db['log'], '-w', 'start',
                   '-o', shlex.join(db['options'])], 'pinned-database-resume')


def snapshot_redis(m, d, state_path):
    cfg = d['snapshotRedis']
    saved = json.loads(state_path.read_text()) if state_path.exists() else cfg['initialProcess']
    pidfile = Path(cfg['pidfile'])
    if pidfile.exists():
        pid = int(pidfile.read_text().strip())
        try:
            proc = m.proc(pid)
        except (FileNotFoundError, ProcessLookupError):
            proc = None
        if proc is not None:
            require(Path('/proc', str(pid)).stat().st_uid == os.getuid() and
                    all(proc[k] == saved[k] for k in ('pid', 'startTick', 'binarySHA256')) and
                    proc['binarySHA256'] == sha(m.REDIS) and m.owns_listen_port(pid, cfg['port']),
                    'snapshot-redis-process-drift')
            return
    m.free_port(cfg['port'])
    proc = m.spawn([m.REDIS, cfg['config']], 'pinned-snapshot-redis',
                   dict(m.ENV, LD_LIBRARY_PATH=str(m.LIBS)))
    m.private_json(state_path, proc)
    for _ in range(30):
        if m.owns_listen_port(proc['pid'], cfg['port']):
            return
        time.sleep(.1)
    raise ResumeError('snapshot-redis-not-listening')


def resume(d, manifest_path, m=None):
    m = m or adapter(d)
    # Validate all artifacts before any process starts, even if already running.
    commands = m.expected(Path(d['bin']), {p: Path(v) for p, v in d['config'].items()},
                          {p: Path(v) for p, v in d['operators'].items()})
    known = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != os.getuid():
                continue
            proc = m.proc(entry.name)
            if proc['args'] in commands:
                require(proc['binarySHA256'] == sha(proc['args'][0]), 'running-binary-drift')
                known.append(proc)
            elif proc['args'] in d['legacyCommands']:
                raise ResumeError('legacy-process-running')
        except (OSError, ProcessLookupError):
            pass
    require(len({tuple(p['args']) for p in known}) == len(known), 'duplicate-process')
    # A conflict on any API port is rejected before resuming dependencies.
    for command, port in zip(commands[2:], d['apiPorts']):
        found = [p for p in known if p['args'] == command]
        if found:
            require(m.owns_listen_port(found[0]['pid'], port), 'api-listener-drift')
        else:
            m.free_port(port)
    pg_start(m, d)
    before = checkpoint(m)
    require({p: before[p]['schema'] for p in 'cv'} == d['schema'], 'schema-drift')
    for p in 'cv':
        shared = m.state()
        if m.owned_redis(p, shared) is None:
            m.start_redis(p, shared, resuming=True)
    snapshot_redis(m, d, Path(manifest_path).parent / 'snapshot-process.private.json')
    # Resume must succeed synchronously for BOTH domains before any new API.
    for p in 'cv':
        m.run([Path(d['bin']) / 'authdev', 'resume', '-operator', d['operators'][p]],
              'pinned-gate-resume-' + p)
    started = []
    try:
        for command in commands:
            if not any(p['args'] == command for p in known):
                started.append(m.spawn(command, 'pinned-service-' + str(len(started))))
        ready = m.health({p: Path(v) for p, v in d['config'].items()})
        require(checkpoint(m) == before, 'authority-changed')
    except BaseException:
        # Never terminate a process from before this invocation. Keep original
        # databases/Redis/AOF intact; no restore/reset/recover fallback.
        if started:
            if any(p['args'] in commands[2:] for p in started):
                m.quiesce(started)
            else:
                m.stop(started)
        raise
    return dict(result='PASS', source=d['source'], schema=d['schema'], ready=ready,
                startedServices=len(started), authorityUnchanged=True, recoverInvoked=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    require(os.getuid() != 0, 'non-root-required')
    os.umask(0o077)
    private(Path(args.manifest).parent, True)
    require(not Path(str(Path(args.manifest).parent / '.resume.lock')).is_symlink(), 'lock-symlink')
    with open(str(Path(args.manifest).parent / '.resume.lock'), 'a') as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        d = load(args.manifest)
        m = adapter(d)
        result = dict(result='STATIC_DEPENDENCIES_VERIFIED_NOT_READINESS', source=d['source']) if args.check_only else resume(d, args.manifest, m)
        print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Do not expose private paths, DSNs or subprocess credential output.
        print('Development resume refused; inspect the private deployment logs.', flush=True)
        raise SystemExit(1)
