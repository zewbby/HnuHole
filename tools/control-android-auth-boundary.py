"""Bounded host control/readback for the owned Android boundary development DB.

Never accepts a DSN or resets a schema. Gate mutations use the normal signed
development operator; SQL is read-only and exports counts/state only.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True)
    parser.add_argument('--action', choices=['freeze-v', 'recover-v', 'capture'], required=True)
    parser.add_argument('--label', choices=['takeover-complete', 'v-gate-request',
                        'v-gate-frozen-confirm', 'v-gate-old-confirm',
                        'otp-continuation-before', 'otp-continuation-request', 'otp-continuation-frozen',
                        'otp-continuation-cleaned', 'otp-continuation-resume'])
    args = parser.parse_args()
    root = Path(args.work).resolve(strict=True)
    assert not Path(args.work).is_symlink()
    assert root == Path('/var/tmp/hnuhole-android-live-boundary-20261006')
    assert (root / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    material = root / 'services/material'
    if args.action != 'capture':
        assert args.label is None
        subprocess.run([str(root / 'services/authdev'),
                        'freeze' if args.action == 'freeze-v' else 'recover',
                        '-operator', str(material / 'operator/v-operator.json')], check=True)
        print('PASS: owned verifier development Gate ' + args.action)
        return
    assert args.label is not None
    results = {}
    for party in ['c', 'v']:
        config = json.loads((material / (party + '.json')).read_text())
        parsed = urlsplit(config['databaseUrl'])
        assert parsed.hostname == '127.0.0.1' and parsed.password is None
        assert parsed.username == 'hnuhole_' + party + '_runtime'
        assert parsed.path == '/hnuhole_' + party
        environment = os.environ.copy()
        environment['PGPASSWORD'] = (material / config['databasePasswordFile']).read_text().strip()
        extra = ("'accounts',(SELECT count(*) FROM c_auth.accounts),"
                 "'activeSessions',(SELECT count(*) FROM c_auth.sessions WHERE revoked_at IS NULL),"
                 "'revokedSessions',(SELECT count(*) FROM c_auth.sessions WHERE revoked_at IS NOT NULL)"
                 if party == 'c' else
                 "'otpFlows',(SELECT count(*) FROM v_auth.otp_flows),"
                 "'confirmations',(SELECT count(*) FROM v_auth.otp_confirmations),"
                 "'ticketAvailable',(SELECT count(*) FROM v_auth.otp_confirmations WHERE state='TICKET_AVAILABLE'),"
                 "'reverifyRequired',(SELECT count(*) FROM v_auth.otp_confirmations WHERE state='REVERIFY_REQUIRED'),"
                 "'olderGenerationFlows',(SELECT count(*) FROM v_auth.otp_flows WHERE authorization_generation < (SELECT authorization_generation FROM v_auth.authorization_gate WHERE singleton_id=1)),"
                 "'unexpiredOlderGenerationFlows',(SELECT count(*) FROM v_auth.otp_flows WHERE expires_at > clock_timestamp() AND authorization_generation < (SELECT authorization_generation FROM v_auth.authorization_gate WHERE singleton_id=1)),"
                 "'sendBudgetEvents',(SELECT count(*) FROM v_auth.otp_budget_events WHERE kind='SEND'),"
                 "'otpExpiredResults',(SELECT count(*) FROM v_auth.request_results WHERE result_code='OTP_EXPIRED'),"
                 "'flowInvalidResults',(SELECT count(*) FROM v_auth.request_results WHERE result_code='OTP_FLOW_INVALID')")
        sql = ("SELECT json_build_object('gateState',gate_state,'gateGeneration',authorization_generation,"
               + extra + ') FROM ' + party + '_auth.authorization_gate WHERE singleton_id=1;')
        completed = subprocess.run(['/usr/lib/postgresql/16/bin/psql', '-X', '-At',
                                   '-v', 'ON_ERROR_STOP=1', config['databaseUrl'], '-c', sql],
                                  env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert completed.returncode == 0, 'Owned count query failed; no database diagnostics exported'
        results[party] = json.loads(completed.stdout)
    directory = root / 'boundary-evidence'
    directory.mkdir(mode=0o700, exist_ok=True)
    report = {'label': args.label, 'result': 'PASS', 'sqlReadOnly': True, 'counts': results}
    (directory / (args.label + '.json')).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
