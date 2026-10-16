#!/usr/bin/env python3
"""Host-only phase control for an owned disposable Android fault cluster."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import urlsplit

PHASES = ('write', 'unknown', 'reconcile', 'frozen', 'recovered', 'offline-logout', 'drain')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True)
    parser.add_argument('--phase', choices=PHASES, required=True)
    parser.add_argument('--capture', action='store_true')
    args = parser.parse_args()
    work = Path(args.work).resolve(strict=True)
    assert not Path(args.work).is_symlink()
    assert work.parent == Path('/var/tmp') and work.name.startswith('hnuhole-android-live-faults-')
    assert (work / 'OWNER').read_text() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    assert (work / 'services').is_dir()
    if args.capture:
        material = work / 'services/material'
        config = json.loads((material / 'c.json').read_text())
        database = urlsplit(config['databaseUrl'])
        assert database.hostname == '127.0.0.1' and database.username == 'hnuhole_c_runtime'
        assert database.path == '/hnuhole_c' and database.password is None
        environment = os.environ.copy()
        environment['PGPASSWORD'] = (material / config['databasePasswordFile']).read_text().strip()
        sql = """SELECT json_build_object(
          'accounts',(SELECT count(*) FROM c_auth.accounts),
          'activeIdentities',(SELECT count(*) FROM public.community_identities WHERE deleted_at IS NULL),
          'committedCreates',(SELECT count(*) FROM public.identity_change_receipts WHERE state='COMMITTED' AND operation='CREATE'),
          'committedRenames',(SELECT count(*) FROM public.identity_change_receipts WHERE state='COMMITTED' AND operation='RENAME'),
          'frozenMutationProfiles',(SELECT count(*) FROM public.community_identities WHERE nickname='冻结应拒绝'),
          'activeSessions',(SELECT count(*) FROM c_auth.sessions WHERE revoked_at IS NULL),
          'revokedSessions',(SELECT count(*) FROM c_auth.sessions WHERE revoked_at IS NOT NULL),
          'gateState',(SELECT gate_state FROM c_auth.authorization_gate WHERE singleton_id=1),
          'gateGeneration',(SELECT authorization_generation FROM c_auth.authorization_gate WHERE singleton_id=1));"""
        raw = subprocess.check_output(['/usr/lib/postgresql/16/bin/psql', '-X', '-At',
            '-v', 'ON_ERROR_STOP=1', config['databaseUrl'], '-c', sql], env=environment, text=True)
        evidence = {'phase': args.phase, 'sql': json.loads(raw),
                    'proxy': json.loads((work / 'proxy-metrics.json').read_text())}
        directory = work / 'phase-evidence'
        directory.mkdir(mode=0o700, exist_ok=True)
        (directory / (args.phase + '.json')).write_text(json.dumps(evidence, indent=2) + '\n')
        print(f'PASS: read-only SQL and proxy evidence captured for {args.phase}', flush=True)
        return
    mode = {'unknown': 'drop-create-response', 'offline-logout': 'block-revocation'}.get(args.phase, 'normal')
    temporary = work / 'proxy-mode.tmp'
    temporary.write_text(json.dumps({'mode': mode}) + '\n')
    os.replace(temporary, work / 'proxy-mode.json')
    if args.phase in ('frozen', 'recovered'):
        command = 'freeze' if args.phase == 'frozen' else 'recover'
        subprocess.run([str(work / 'services/authdev'), command, '-operator',
                        str(work / 'services/material/operator/operator.json')], check=True)
    print(f'READY: owned phase {args.phase}; mode {mode}', flush=True)


if __name__ == '__main__':
    main()
