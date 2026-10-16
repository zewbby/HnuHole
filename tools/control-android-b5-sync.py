"""Bounded continuation of B5 through a genuinely synced Android passkey.

Keeps the successful original assertion/intent and the fixture failure. Never
replays a proof, resets SQL, performs OEM migration, or retries authentication.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import uuid

OWNER = 'HNUHOLE_B5_20261016_V1'
PACKAGE = 'org.hnuhole.hnuhole_mobile.acceptance20261012'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install-target', 'prepare-target', 'prepare-target-retry', 'target-recover', 'confirm-reset', 'verify-login', 'status'])
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--previous', type=Path, required=True)
    parser.add_argument('--environment', type=Path, required=True)
    parser.add_argument('--adb', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--target', required=True)
    args = parser.parse_args()
    root, previous, environment = [p.resolve() for p in [args.work, args.previous, args.environment]]
    assert args.source != args.target
    assert all(re.fullmatch(r'[A-Za-z0-9]{6,32}', d) for d in [args.source, args.target])
    assert all((p/'OWNER').read_text().strip() == OWNER for p in [root, previous])
    assert (root/'PURPOSE').read_text().strip() == 'SYNC_CONTINUATION_AFTER_CONFIRMED_NATIVE_SUCCESS_V1'
    assert (environment/'OWNER').read_text().strip() == 'HNUHOLE_ALTERNATE_20261013_V1'

    def read(name, base=root):
        return json.loads((base/name).read_text(encoding='utf-8-sig'))

    def save(name, value):
        path = root/name
        assert not path.exists(), 'Preserve every prior operation; no automatic retry'
        path.write_text(json.dumps(value, indent=2)+'\n', encoding='utf-8')

    def adb(device, *parts, timeout=30):
        value = subprocess.run([args.adb, '-s', device, *parts], capture_output=True, timeout=timeout)
        assert value.returncode == 0, 'ADB failed; preserve state'
        return value.stdout

    def sql():
        witness = environment/'sql-witness.private.py'
        linux = '/mnt/'+witness.drive[0].lower()+'/'+witness.as_posix()[3:]
        value = subprocess.run(['wsl.exe', '-d', 'HnuHole-Ubuntu-24.04', '-u', 'hnuhole', '--', 'python3', linux], capture_output=True, text=True, timeout=30)
        assert value.returncode == 0
        return json.loads(value.stdout)

    def apk(device):
        match = re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)', adb(device, 'shell', 'pm', 'path', '--user', '0', PACKAGE).decode().strip())
        assert match
        return adb(device, 'shell', 'sha256sum', match[1]).decode().split()[0]

    def state():
        value = json.loads(adb(args.target, 'exec-out', 'run-as', PACKAGE, 'cat', 'files/b5-status.json'))
        assert value['owner'] == OWNER and value['fixtureProtocol'] == 2
        assert int(adb(args.target, 'shell', 'pidof', PACKAGE)) == value['pid']
        return value

    def no_native_ui():
        active = [s for s in adb(args.target, 'shell', 'dumpsys', 'activity', 'activities').decode(errors='replace').splitlines() if 'topResumedActivity=' in s or 'mResumedActivity:' in s]
        assert not any(k in s for s in active for k in ['credentials.fido', 'credentialmanager/', 'com.google.android.gms/.fido.', 'com.google.android.gms/.auth.api.credentials.', 'OctarineWebviewActivity'])

    build = read('build-result.json')
    assert build['result'] == 'PASS'
    for role, device in [('source', args.source), ('target', args.target)]:
        assert adb(device, 'get-state').strip() == b'device'
        assert adb(device, 'shell', 'getprop', 'ro.kernel.qemu').strip() != b'1'
        assert adb(device, 'shell', 'am', 'get-current-user').strip() == b'0'
        assert adb(device, 'shell', 'getprop', 'ro.product.model').decode().strip() == read('inventory.json', previous)['devices'][device]['model']
    assert apk(args.source) == read('build-result.json', previous)['apkSha256']
    assert read('NI-X01-result.json', previous)['result'] == 'PASS'
    assert read('target-get-attempt05-result.json', previous)['result'] == 'NATIVE_AND_C_INTENT_PASS_FIXTURE_FAILURE'

    def command(step, expected, **extra):
        assert apk(args.target) == build['apkSha256']
        before = state()
        assert before['state'] == expected
        value = dict(owner=OWNER, pid=before['pid'], nonce=before['nonce'], sequence=before['sequence']+1, step=step, **extra)
        save('command-'+step+'.json', dict(owner=OWNER, state='COMMAND_SENT_OR_UNKNOWN', pid=before['pid'], step=step, sequence=value['sequence'], sqlBefore=sql(), automaticRetryPermitted=False))
        path = root/('input-'+uuid.uuid4().hex+'.private.json')
        remote = '/data/local/tmp/hnuhole-b5-sync-'+uuid.uuid4().hex+'.json'
        try:
            path.write_text(json.dumps(value), encoding='utf-8')
            adb(args.target, 'push', str(path), remote)
            adb(args.target, 'shell', 'run-as', PACKAGE, 'mkdir', '-p', 'no_backup')
            adb(args.target, 'shell', 'run-as', PACKAGE, 'cp', remote, 'no_backup/b5-command.json')
        finally:
            adb(args.target, 'shell', 'rm', '-f', remote)
            path.unlink(missing_ok=True)
        print(json.dumps(dict(state='COMMAND_SENT', step=step)))

    if args.action == 'install-target':
        assert apk(args.target) == read('oem-transfer-result.json', previous)['apkSha256']
        assert sql() == dict(accounts=1, passkeys=1, activeSessions=1, activeResets=1)
        no_native_ui()
        candidate = root/'b5-android-arm64.apk'
        assert hashlib.sha256(candidate.read_bytes()).hexdigest() == build['apkSha256']
        save('install-target.json', dict(owner=OWNER, result='INSTALL_PENDING_OR_UNKNOWN', oldApkSha256=apk(args.target), newApkSha256=build['apkSha256']))
        result = adb(args.target, 'install', '--no-streaming', '-t', '-r', str(candidate), timeout=180)
        assert b'Success' in result and apk(args.target) == build['apkSha256']
        save('install-target-completed.json', dict(owner=OWNER, result='PASS', apkSha256=build['apkSha256']))
        print('PASS: target fixture updated; product data and original server intent preserved')
    elif args.action in ['prepare-target', 'prepare-target-retry']:
        assert read('install-target-completed.json')['result'] == 'PASS'
        no_native_ui()
        if args.action == 'prepare-target-retry':
            assert not (root/'explicit-retry-after-unanswered-ui.json').exists(), 'One explicitly requested retry only'
            before = state()
            native = json.loads(adb(args.target, 'exec-out', 'run-as', PACKAGE, 'cat', 'files/owned-acceptance-passkey.json'))
            assert before['state'] == 'FAILED_OR_UNKNOWN' and before['failedStep'] == 'target-recover'
            assert before['getAttempts'] == 1 and before['createAttempts'] == 0
            assert native['pid'] == before['pid'] and native['nativeBegun'] == native['nativeErrored'] == 1
            assert not native.get('nativeSucceeded', 0)
            assert read('attempt06-native-result.json')['state'] == before
            assert sql() == dict(accounts=1, passkeys=1, activeSessions=1, activeResets=1)
            names = ['launch-target.json', 'command-target-observe.json', 'command-target-recover.json']
            assert all((root/n).is_file() and not (root/(Path(n).stem+'.attempt06.json')).exists() for n in names)
            save('explicit-retry-after-unanswered-ui.json', dict(owner=OWNER, userRequestedRetry=True, priorRequestNotConfirmedByUser=True, originalFailurePreserved=True, proofReplay=False, retryLimit=1))
            for name in names:
                (root/name).rename(root/(Path(name).stem+'.attempt06.json'))
        save('launch-target.json', dict(owner=OWNER, result='LAUNCH_PENDING_OR_UNKNOWN', sqlBefore=sql()))
        for key in ['AUTH_COMMUNITY_BASE_URL', 'AUTH_VERIFIER_BASE_URL', 'AUTH_DEVICE_MAILPIT_URL']:
            port = read('device-config.public.json')[key].rsplit(':', 1)[1]
            assert port.isdecimal()
            adb(args.target, 'reverse', 'tcp:'+port, 'tcp:'+port)
        adb(args.target, 'shell', 'am', 'force-stop', PACKAGE)
        adb(args.target, 'shell', 'am', 'start', '-n', PACKAGE+'/org.hnuhole.hnuhole_mobile.MainActivity', '--ez', 'hnuhole-device-driver', 'true', '--es', 'hnuhole-device-phase', 'ni-d02', '--es', 'hnuhole-device-variant', 'control')
        deadline = time.monotonic()+90
        while time.monotonic() < deadline:
            try:
                if state()['state'] == 'READY':
                    break
            except (AssertionError, ValueError):
                pass
            time.sleep(.5)
        else:
            raise RuntimeError('Launch did not become ready; preserve original state')
        command('target-observe', 'READY')
    elif args.action == 'target-recover':
        assert sql() == dict(accounts=1, passkeys=1, activeSessions=1, activeResets=1)
        account = read('account.private.json')
        command('target-recover', 'MIGRATION_EMPTY', account={k:account[k] for k in ['username', 'password', 'oldRecoveryCode', 'oldSessionToken', 'accountId']})
    elif args.action == 'confirm-reset':
        assert sql() == dict(accounts=1, passkeys=1, activeSessions=1, activeResets=1)
        command('confirm-reset', 'RESET_INTENT_READY', syntheticRecoveryAcknowledged=True)
    elif args.action == 'verify-login':
        assert sql() == dict(accounts=1, passkeys=0, activeSessions=0, activeResets=0)
        command('verify-login', 'RESET_COMMITTED_NO_SESSION')
    else:
        current = state()
        print(json.dumps(dict(device={k:v for k,v in current.items() if k != 'nonce'}, sql=sql())))


if __name__ == '__main__':
    main()
