#!/usr/bin/env python3
"""Fixed B1/B2 host: signed Gate operations and count-only owned SQL/proxy snapshots."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import urlsplit

ROOT = Path('/var/tmp/hnuhole-android-live-batch-20261007')
PHASES = ('ni-l01', 'ni-l02', 'ni-l03', 'ni-l04', 'ni-u01', 'ni-u02', 'ni-u03',
          'ni-a01', 'ni-a02', 'ni-a03', 'ni-a04', 'ni-takeover')


def owned():
    assert ROOT.resolve() == ROOT and not ROOT.is_symlink()
    assert (ROOT / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    pid = int((ROOT / 'b1b2-proxy.pid').read_text())
    source = ROOT / 'repo/tools/android-auth-b1-b2-proxy.py'
    assert str(source).encode() in Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
    assert (ROOT / 'b1b2-proxy-source.sha256').read_text().strip() == hashlib.sha256(source.read_bytes()).hexdigest()


def sql_counts():
    project = 'hnuhole-device-hnuholeandroidlivebatch20261007'
    def run(args, env=None):
        result = subprocess.run(args, capture_output=True, text=True, env=env, timeout=20)
        assert result.returncode == 0, 'Owned host operation failed; private diagnostics suppressed'
        return result.stdout.strip()
    ids = run(['docker', 'ps', '-q', '--filter', 'label=com.docker.compose.project=' + project]).split()
    assert len(ids) == 3
    containers = json.loads(run(['docker', 'inspect', *ids]))
    material = ROOT / 'services/material'
    cfg = json.loads((material / 'c.json').read_text())
    url = urlsplit(cfg['databaseUrl'])
    assert url.hostname == '127.0.0.1' and url.password is None and url.username == 'hnuhole_c_runtime' and url.path == '/hnuhole_c'
    db = next(c for c in containers if c['Config']['Labels']['com.docker.compose.service'] == 'community-postgres')
    assert any(int(p['HostPort']) == url.port and p['HostIp'] == '127.0.0.1' for p in db['NetworkSettings']['Ports']['5432/tcp'])
    env = os.environ.copy()
    env['PGPASSWORD'] = (material / cfg['databasePasswordFile']).read_text().strip()
    query = """SELECT json_build_object(
      'gateState',gate_state,'generation',authorization_generation,
      'passkeys',(SELECT count(*) FROM c_auth.passkeys),
      'resetIntents',(SELECT count(*) FROM c_auth.reset_intents),
      'resetChallenges',(SELECT count(*) FROM c_auth.auth_challenges WHERE kind='RESET_PASSKEY'),
      'activeSessions',(SELECT count(*) FROM c_auth.sessions WHERE revoked_at IS NULL),
      'revokedSessions',(SELECT count(*) FROM c_auth.sessions WHERE revoked_at IS NOT NULL))
      FROM c_auth.authorization_gate WHERE singleton_id=1;"""
    return json.loads(run(['/usr/lib/postgresql/16/bin/psql', '-X', '-At', '-v',
                           'ON_ERROR_STOP=1', cfg['databaseUrl'], '-c', query], env))


def snapshot():
    proxy = json.loads((ROOT / 'b1b2-proxy-metrics.json').read_text())
    assert proxy['proofsStored'] is False
    return {'sql': sql_counts(), 'proxy': proxy}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'capture', 'freeze-c', 'recover-c', 'normal', 'status', 'reanchor-talkback'])
    parser.add_argument('--phase', choices=PHASES)
    args = parser.parse_args()
    owned()
    directory = ROOT / 'b1b2-evidence'
    directory.mkdir(mode=0o700, exist_ok=True)
    if args.action == 'reanchor-talkback':
        assert args.phase == 'ni-u03'
        anchor = directory / 'ni-u03-before.json'
        before = json.loads(anchor.read_text())
        after = snapshot()
        assert before['sql'] == after['sql']
        for counter in ('rotationSubmits', 'bindingSubmits', 'resetOptionRequests',
                        'resetIntentSubmits', 'droppedRotationReplies'):
            assert before['proxy'][counter] == after['proxy'][counter]
        prior_queries = after['proxy']['resultQueries'] - before['proxy']['resultQueries']
        assert prior_queries in (0, 1)
        historical = directory / 'ni-u03-before-prior-reconciliation.json'
        record = directory / 'ni-u03-prior-reconciliation.json'
        assert not historical.exists() and not record.exists()
        record.write_text(json.dumps({'result':'PASS', 'phase':args.phase,
            'scope':'OWNED_PRIOR_ORIGINAL_RESULT_RECONCILIATION_COUNTS_ONLY',
            'before':before, 'after':after, 'originalResultQueries':prior_queries,
            'alreadyReconciledInPriorRun':prior_queries == 0,
            'confirmationSubmits':0, 'proofsStored':False,
            'actualAppAcceptancePassed':False}, indent=2) + '\n')
        anchor.rename(historical)
        anchor.write_text(json.dumps(after, indent=2) + '\n')
        print('REANCHORED: prior original query recorded separately; no confirmation replay')
        return
    if args.action in ('freeze-c', 'recover-c'):
        operator = ROOT / 'services/material/operator/operator.json'
        assert operator.exists()
        result = subprocess.run([str(ROOT / 'services/authdev'),
                                 'freeze' if args.action == 'freeze-c' else 'recover',
                                 '-operator', str(operator)], capture_output=True, timeout=20)
        assert result.returncode == 0, 'Signed development Gate operation failed; private diagnostics suppressed'
        print(json.dumps({'signedOperatorOnly': True, 'action': args.action, 'sql': sql_counts()}))
        return
    if args.action in ('normal', 'prepare'):
        if args.action == 'prepare':
            assert args.phase
            anchor = directory / (args.phase + '-before.json')
            assert not anchor.exists(), 'Preserve prior attempt anchor; do not overwrite counters'
            anchor.write_text(json.dumps(snapshot(), indent=2) + '\n')
        mode = 'drop-rotation' if args.phase == 'ni-u03' else 'normal'
        temporary = ROOT / 'b1b2-proxy-mode.tmp'
        temporary.write_text(json.dumps({'mode': mode}) + '\n')
        temporary.replace(ROOT / 'b1b2-proxy-mode.json')
        print('READY: owned B1/B2 mode and immutable count anchor')
        return
    if args.action == 'status':
        print(json.dumps(snapshot()))
        return
    assert args.phase
    before = json.loads((directory / (args.phase + '-before.json')).read_text())
    after = snapshot()
    counters = ('bindingSubmits', 'rotationSubmits', 'resultQueries', 'resetOptionRequests',
                'resetIntentSubmits', 'droppedRotationReplies')
    delta = {k: after['proxy'][k] - before['proxy'][k] for k in counters}
    assert all(value >= 0 for value in delta.values())
    if args.phase in ('ni-l01', 'ni-l02', 'ni-l03', 'ni-l04', 'ni-u01', 'ni-u02', 'ni-u03', 'ni-a02', 'ni-takeover'):
        assert delta['bindingSubmits'] == 0
    if args.phase in ('ni-l01', 'ni-l02', 'ni-l03', 'ni-l04'):
        assert after['sql']['passkeys'] == before['sql']['passkeys']
    if args.phase == 'ni-u03':
        assert delta['rotationSubmits'] == delta['droppedRotationReplies'] == 1
        assert delta['resultQueries'] == 1
    if args.phase in ('ni-u01', 'ni-a02'):
        assert delta['resetOptionRequests'] == 1 and delta['resetIntentSubmits'] == 0
        assert after['sql']['resetIntents'] == before['sql']['resetIntents']
    if args.phase == 'ni-a02':
        assert after['sql']['gateState'] == 'FROZEN' and after['proxy']['lastResetOptionStatus'] == 503
        assert after['sql']['resetChallenges'] == before['sql']['resetChallenges']
    if args.phase in ('ni-a01', 'ni-a03', 'ni-a04'):
        assert delta['bindingSubmits'] == 1
        status = after['proxy']['lastBindingStatus']
        assert status == {'ni-a01': 503, 'ni-a03': 401, 'ni-a04': 204}[args.phase]
        assert after['sql']['passkeys'] - before['sql']['passkeys'] == (1 if args.phase == 'ni-a04' else 0)
    record = {'phase': args.phase, 'result': 'PASS', 'scope': 'OWNED_SQL_AND_PROXY_COUNTS_ONLY',
              'before': before, 'after': after, 'delta': delta, 'sqlReadOnly': True,
              'proofsStored': False, 'actualAppAcceptancePassed': False}
    destination = directory / (args.phase + '.json')
    assert not destination.exists(), 'Preserve accepted attempt evidence'
    destination.write_text(json.dumps(record, indent=2) + '\n')
    print('PASS: B1/B2 owned counts; actual App report still required')


if __name__ == '__main__': main()
