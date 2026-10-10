#!/usr/bin/env python3
"""Control only the isolated formal-closure development clock and read SQL.

No DSN argument, DML, deadline edits, fake receipts or changes to host time.
Advancement stops owned processes, publishes correctly signed newer evidence,
then resumes the same ordinary business runtime and workers at the new clock.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import signal
import ssl
import subprocess
import time
from urllib.parse import urlsplit
import urllib.request

ROOT = Path('/var/tmp/hnuhole-android-live-closure-20261007')
PROJECT = 'hnuhole-device-hnuholeandroidliveclosure20261007'


def main():
    global ROOT, PROJECT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['capture', 'advance', 'verify-finalized'])
    parser.add_argument('--cycle', type=int, choices=list(range(12)), required=True)
    parser.add_argument('--work', choices=[str(ROOT), '/var/tmp/hnuhole-android-live-batch-20261007',
        '/var/tmp/hnuhole-android-live-b3-b4-20261009'], default=str(ROOT))
    args = parser.parse_args()
    ROOT = Path(args.work)
    assert args.cycle < 2 or ROOT == Path('/var/tmp/hnuhole-android-live-b3-b4-20261009')
    PROJECT = 'hnuhole-device-' + ''.join(c for c in ROOT.name if c.isalnum())
    assert ROOT.resolve() == ROOT and not ROOT.is_symlink()
    assert (ROOT / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    if args.cycle>=10:
        plan=json.loads((ROOT/'b3b4-evidence/discoverable-batch-20261010.json').read_text())
        assert plan['allowedClosureCycles']==[10,11] and plan['requireActualAssertionPreflight']
    elif args.cycle>=8:
        final_plan=json.loads((ROOT/'b3b4-evidence/final-batch-20261010.json').read_text())
        assert final_plan['allowedClosureCycles']==[8,9] and final_plan['userConfirmedUninstall']
    services = ROOT / 'services'
    material = services / 'material'
    configs = {party: json.loads((material / (party + '.json')).read_text()) for party in ['c', 'v']}
    env = os.environ.copy()

    def run(command):
        r = subprocess.run(command, capture_output=True, text=True, timeout=90)
        assert r.returncode == 0, 'Owned closure operation failed; no private diagnostics exported'
        return r.stdout.strip()

    containers = json.loads(run(['docker', 'inspect', *run(['docker', 'ps', '-q', '--filter',
        'label=com.docker.compose.project=' + PROJECT]).split()]))
    assert len(containers) == 3
    assert {x['Config']['Labels']['com.docker.compose.service'] for x in containers} == {
        'community-postgres', 'verifier-postgres', 'mailpit'}
    for party, service in [('c', 'community-postgres'), ('v', 'verifier-postgres')]:
        parsed = urlsplit(configs[party]['databaseUrl'])
        assert parsed.hostname == '127.0.0.1' and parsed.password is None
        assert parsed.username == 'hnuhole_' + party + '_runtime' and parsed.path == '/hnuhole_' + party
        container = next(x for x in containers if x['Config']['Labels']['com.docker.compose.service'] == service)
        assert any(int(p['HostPort']) == parsed.port and p['HostIp'] == '127.0.0.1'
            for p in container['NetworkSettings']['Ports']['5432/tcp'])
        assert all(m['Name'].startswith(PROJECT + '_') for m in container['Mounts'] if m['Type'] == 'volume')

    def sql(party, query):
        cfg = configs[party]
        env['PGPASSWORD'] = (material / cfg['databasePasswordFile']).read_text().strip()
        r = subprocess.run(['/usr/lib/postgresql/16/bin/psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1',
            cfg['databaseUrl'], '-c', query], env=env, capture_output=True, text=True, timeout=20)
        assert r.returncode == 0, 'Owned read-only query failed; private response suppressed'
        return r.stdout.strip()

    evidence = ROOT / 'closure-evidence'
    evidence.mkdir(mode=0o700, exist_ok=True)
    anchor = evidence / ('cycle-' + str(args.cycle) + '.private.json')
    if args.action == 'capture':
        # The immutable request stores the due date; the account's session at
        # request revocation has the final trusted transaction timestamp.
        rows = sql('c', "SELECT json_build_object('account',r.account_id,'id',encode(r.closure_id,'hex'),"
            "'due',r.due_at,'slot',(SELECT encode(slot_id,'hex') FROM c_auth.slot_ledger WHERE account_id=r.account_id AND state='ACTIVE'),'sevenDays',r.due_at=(SELECT max(revoked_at) FROM c_auth.sessions WHERE account_id=r.account_id)+interval '7 days',"
            "'generation',g.authorization_generation) FROM c_auth.closure_requests r CROSS JOIN c_auth.authorization_gate g "
            "WHERE r.state='PENDING' AND g.singleton_id=1;")
        assert len(rows.splitlines()) == 1
        pending = json.loads(rows)
        assert pending['sevenDays']
        profiles = int(sql('c', "SELECT count(*) FROM public.community_identities WHERE account_id='" + pending['account'] + "'::uuid AND deleted_at IS NULL;"))
        assert profiles == (3 if args.cycle in (1,4,6,9,11) else 0)
        assert not anchor.exists(), 'Preserve existing accepted cycle ownership'
        pending['profilesBefore'] = sql('c', "SELECT md5(coalesce(string_agg(row_to_json(i)::text,',' ORDER BY identity_id),'')) "
            "FROM public.community_identities i WHERE account_id='" + pending['account'] + "'::uuid;")
        pending['receiptsBefore'] = sql('c', "SELECT md5(coalesce(string_agg(row_to_json(i)::text,',' ORDER BY change_key_digest),'')) "
            "FROM public.identity_change_receipts i WHERE account_id='" + pending['account'] + "'::uuid;")
        anchor.write_text(json.dumps(pending) + '\n')
        report = {'result': 'PASS', 'cycle': args.cycle, 'sqlReadOnly': True,
            'immutableDeadlineExactlySevenDays': True, 'pendingClosureCount': 1,
            'activeIdentityCountBeforeDeadline': profiles,
            'simulatedClockOffsetSeconds': int((ROOT / 'clock-offset-ns').read_text()) // 10**9}
    else:
        pending = json.loads(anchor.read_text())
        if args.action == 'advance':
            current = sql('c', "SELECT due_at::text FROM c_auth.closure_requests WHERE closure_id=decode('" + pending['id'] + "','hex') AND state='PENDING';")
            due = datetime.datetime.fromisoformat(pending['due'])
            assert current and datetime.datetime.fromisoformat(current) == due
            assert int(sql('c', 'SELECT count(*) FROM c_auth.closure_requests WHERE state=\'PENDING\';')) == 1
            old = int((ROOT / 'clock-offset-ns').read_text())
            new = int((due.timestamp() + 2 - time.time()) * 10**9)
            maximum_days = (96 if args.cycle>=10 else (80 if args.cycle>=8 else 64)) if ROOT == Path('/var/tmp/hnuhole-android-live-b3-b4-20261009') else 16
            assert old < new <= maximum_days*24*3600*10**9
            # Verify every manifest PID belongs to one exact test binary/config.
            pids = list(map(int, (services / 'owned-child-pids.txt').read_text().split()))
            assert len(pids) == 4
            for proc in pids:
                command = Path('/proc') / str(proc) / 'cmdline'
                words = command.read_bytes().rstrip(b'\0').split(b'\0')
                assert words[0].decode() in {str(services / name) for name in ['community', 'verifier', 'authdev']}
                assert any(str(material).encode() in word for word in words)
            for proc in pids:
                os.kill(proc, signal.SIGTERM)
            for _ in range(100):
                if all(not Path('/proc', str(proc), 'cmdline').exists() or not Path('/proc', str(proc), 'cmdline').read_bytes() for proc in pids):
                    break
                time.sleep(.1)
            else:
                raise AssertionError('Owned services did not stop; clock unchanged')
            temp = ROOT / 'clock-offset-ns.next'
            temp.write_text(str(new) + '\n')
            temp.replace(ROOT / 'clock-offset-ns')
            for name in ['operator.json', 'v-operator.json']:
                run([str(services / 'authdev'), 'issue', '-operator', str(material / 'operator' / name)])
            children = []
            for name, cfg in [('community', 'c.json'), ('verifier', 'v.json'), ('authdev', 'operator/operator.json'), ('authdev', 'operator/v-operator.json')]:
                command = [str(services / name)]
                command += ['watch', '-operator', str(material / cfg)] if name == 'authdev' else ['-config', str(material / cfg)]
                if ROOT == Path('/var/tmp/hnuhole-android-live-b3-b4-20261009'):
                    label=name if name!='authdev' else ('c-watch' if cfg=='operator/operator.json' else 'v-watch')
                    manager=ROOT/'repo/tools/start-android-b3-b4-service.py'
                    assert manager.read_bytes()==Path('/mnt/c/Users/Administrator/Documents/ChatGPT/HnuHole/tools/start-android-b3-b4-service.py').read_bytes()
                    children.append(int(run(['python3',str(manager),label])))
                else:
                    with (ROOT / ('cycle-' + str(args.cycle) + '-' + cfg.replace('/', '-') + '.private.log')).open('ab') as log:
                        children.append(subprocess.Popen(command, stdout=log, stderr=log, start_new_session=True).pid)
            (services / 'owned-child-pids.txt').write_text(' '.join(map(str, children)) + '\n')
            cfg = json.loads((ROOT / 'device-config.json').read_text())
            context = ssl.create_default_context(cafile=str(material / 'dev-ca.pem'))
            recovered = []
            # A guarded shutdown may leave the independent anchor frozen. Reopen
            # only through the existing signed operator, never by SQL or a flag.
            for party, operator in [('c', 'operator.json'), ('v', 'v-operator.json')]:
                if sql(party, 'SELECT gate_state FROM ' + party + '_auth.authorization_gate WHERE singleton_id=1;') == 'FROZEN':
                    run([str(services / 'authdev'), 'recover', '-operator', str(material / 'operator' / operator)])
                    recovered.append(party)
            for _ in range(60):
                try:
                    for key in ['AUTH_COMMUNITY_BASE_URL', 'AUTH_VERIFIER_BASE_URL']:
                        with urllib.request.urlopen(cfg[key] + '/health/ready', context=context, timeout=2) as response:
                            assert response.status == 200
                    state = sql('c', "SELECT state FROM c_auth.accounts WHERE account_id='" + pending['account'] + "'::uuid;")
                    released = sql('c', "SELECT receipt_acknowledged FROM c_auth.slot_ledger WHERE slot_id=(SELECT slot_id FROM c_auth.closure_requests WHERE closure_id=decode('" + pending['id'] + "','hex'));")
                    if state == 'CLOSED' and released == 't': break
                except Exception:
                    pass
                time.sleep(1)
            else:
                raise AssertionError('Actual worker closure/release not accepted; environment retained')
        else:
            assert ROOT == Path('/var/tmp/hnuhole-android-live-b3-b4-20261009')
            captured=json.loads((evidence/(str(args.cycle)+'-capture.json')).read_text())
            assert captured['result']=='PASS' and captured['immutableDeadlineExactlySevenDays']
            assert sql('c', "SELECT state FROM c_auth.accounts WHERE account_id='"+pending['account']+"'::uuid;")=='CLOSED'
            assert sql('c', "SELECT l.receipt_acknowledged FROM c_auth.closure_requests r JOIN c_auth.slot_ledger l ON l.slot_id=r.slot_id WHERE closure_id=decode('"+pending['id']+"','hex');")=='t'
            new=int((ROOT/'clock-offset-ns').read_text());recovered=[]
        current_generation = int(sql('c', 'SELECT authorization_generation FROM c_auth.authorization_gate WHERE singleton_id=1;'))
        assert current_generation >= pending['generation']
        count = int(sql('c', "SELECT count(*) FROM public.community_identities WHERE account_id='" + pending['account'] + "'::uuid AND (deleted_at IS NULL OR nickname IS NOT NULL OR avatar IS NOT NULL OR last_renamed_at IS NOT NULL);"))
        assert count == 0
        receipts = sql('c', "SELECT md5(coalesce(string_agg(row_to_json(i)::text,',' ORDER BY change_key_digest),'')) FROM public.identity_change_receipts i WHERE account_id='" + pending['account'] + "'::uuid;")
        assert receipts == pending['receiptsBefore']
        assert int(sql('c', "SELECT count(*) FROM c_auth.recovery_codes WHERE account_id='" + pending['account'] + "'::uuid;")) == 0
        assert int(sql('c', "SELECT count(*) FROM c_auth.passkeys WHERE account_id='" + pending['account'] + "'::uuid;")) == 0
        assert sql('c', "SELECT username IS NULL AND password_hash IS NULL AND password_salt IS NULL FROM c_auth.accounts WHERE account_id='" + pending['account'] + "'::uuid;") == 't'
        if ROOT == Path('/var/tmp/hnuhole-android-live-b3-b4-20261009'):
            slot = pending.get('slot') or sql('c', "SELECT encode(slot_id,'hex') FROM c_auth.closure_requests WHERE closure_id=decode('"+pending['id']+"','hex');")
            assert len(slot) == 64 and all(c in '0123456789abcdef' for c in slot)
            assert int(sql('v', "SELECT count(*) FROM v_auth.email_quota WHERE current_slot=decode('" + slot + "','hex');")) == 0
        else:
            assert int(sql('v', 'SELECT count(*) FROM v_auth.email_quota;')) == 0
        report = {'result': 'PASS', 'cycle': args.cycle, 'sqlReadOnly': True,
            'clockScope': 'build-only Gate and signed development evidence',
            'realSevenDayWait': False, 'sqlDeadlineEdited': False, 'hostOrPhoneClockChanged': False,
            'finalizationVerifiedAfterInterruptedRunner': args.action=='verify-finalized',
            'ordinaryWorkersFinalizedAndReleased': True,
            'gateGenerationUnchanged': current_generation == pending['generation'],
            'normalSignedGateRecoveryAfterRestart': recovered,
            'identityProfilesErased': True, 'permanentIdentityReceiptsUnchanged': True,
            'recoveryCodesAndPasskeysAbsent': True, 'originalDeadlineUnchangedBeforeFinalization': True,
            'passwordAndUsernameErased': True, 'verifierExactEmailQuotaEmptyAfterAck': True,
            'simulatedClockOffsetSeconds': new // 10**9}
    (evidence / (str(args.cycle) + '-' + args.action + '.json')).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
