#!/usr/bin/env python3
"""Fixed owned batch proxy modes and count-only phase evidence.

No account, token, OTP, native proof, SQL or private configuration is exported.
Changing the mode never replays an upstream request. Live setup is deliberately
separate from this tool's syntax/analysis acceptance.
"""
import argparse
import json
from pathlib import Path

ROOT = Path('/var/tmp/hnuhole-android-live-batch-20261007')
MODES = {
    'batch-passkey-drop': 'drop-binding',
    'batch-passkey-reconcile': 'normal',
    'batch-passkey-origin-reject': 'tamper-origin',
    'batch-passkey-rejected-reconcile': 'normal',
    'batch-passkey-route-cancel': 'normal',
    'batch-passkey-remove-existing': 'normal',
    'batch-passkey-timeout': 'normal',
    'batch-gate-session-recover': 'normal',
    'batch-passkey-ack-interrupted-success': 'normal',
}
KEYS = {'identitySubmits', 'bindingSubmits', 'droppedIdentityReplies',
        'droppedBindingReplies', 'heldBindings', 'resultQueries',
        'rejectedOrigins', 'lastBindingStatus', 'proofsStored'}


def read_counts():
    value = json.loads((ROOT / 'batch-proxy-metrics.json').read_text())
    assert set(value) == KEYS and value['proofsStored'] is False
    assert all(type(v) is int and v >= 0 for k, v in value.items() if k != 'proofsStored')
    return value


def write(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prepare', 'capture'])
    parser.add_argument('--phase', choices=list(MODES), required=True)
    args = parser.parse_args()
    assert ROOT.resolve() == ROOT and not ROOT.is_symlink()
    assert (ROOT / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    proxy_pid = int((ROOT / 'batch-proxy.pid').read_text())
    command = Path(f'/proc/{proxy_pid}/cmdline').read_bytes().split(b'\0')
    expected_script = ROOT / 'repo/tools/android-auth-batch-proxy.py'
    assert str(expected_script).encode() in command
    # The initialized proxy must use the current reviewed source. A stale
    # running process must be restarted explicitly before accepting evidence.
    assert (ROOT / 'batch-proxy-source.sha256').read_text().strip() == __import__(
        'hashlib').sha256(expected_script.read_bytes()).hexdigest()
    evidence = ROOT / 'batch-proxy-evidence'
    evidence.mkdir(exist_ok=True)
    anchor = evidence / f'{args.phase}-before.json'
    if args.action == 'prepare':
        assert not anchor.exists(), 'Retain an existing phase anchor; do not overwrite its counters'
        write(anchor, read_counts())
        write(ROOT / 'batch-proxy-mode.json', {'mode': MODES[args.phase]})
        print('READY: owned batch proxy mode and count-only anchor')
        return
    before, after = json.loads(anchor.read_text()), read_counts()
    delta = {k: after[k] - before[k] for k in KEYS - {'lastBindingStatus', 'proofsStored'}}
    assert all(v >= 0 for v in delta.values())
    if args.phase == 'batch-passkey-drop':
        assert delta['bindingSubmits'] == delta['droppedBindingReplies'] == 1
        assert after['lastBindingStatus'] == 204
    elif args.phase == 'batch-passkey-origin-reject':
        assert delta['bindingSubmits'] == delta['rejectedOrigins'] == 1
        assert after['lastBindingStatus'] == 422
    elif args.phase.endswith('reconcile'):
        assert delta['bindingSubmits'] == 0 and delta['resultQueries'] >= 1
    else:
        assert delta['bindingSubmits'] == 0
        if args.phase == 'batch-gate-session-recover':
            assert delta['resultQueries'] == 0
    write(evidence / f'{args.phase}.json', {
        'phase': args.phase, 'result': 'PASS', 'scope': 'PROXY_COUNTERS_ONLY',
        'delta': delta, 'lastBindingStatus': after['lastBindingStatus'],
        'proofsStored': False, 'actualAppAcceptancePassed': False,
    })
    print('PASS: owned proxy count boundary; actual App report required separately')


if __name__ == '__main__':
    main()
