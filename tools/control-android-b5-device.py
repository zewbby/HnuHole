"""Finite B5 operator for two physical Androids and an owned development C/V.

OEM transfer is performed by the actual OEM app, never emulated by this tool.
Native operations require explicit commands and retain unknown outcomes.
"""
import argparse
import datetime
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
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['inventory', 'install-source', 'launch-source', 'resume-source', 'source-login', 'observe-target', 'source-bind', 'collect-source', 'prepare-target-retry', 'target-recover', 'confirm-reset', 'verify-login', 'status'])
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--adb', required=True)
    p.add_argument('--source', required=True)
    p.add_argument('--target', required=True)
    p.add_argument('--environment', type=Path, required=True)
    p.add_argument('--retry-id', help='Distinct operator authorization label for an additional explicit retry')
    args = p.parse_args()
    root = args.work.resolve()
    environment = args.environment.resolve()
    assert (root/'OWNER').read_text().strip() == OWNER
    assert (environment/'OWNER').read_text().strip() == 'HNUHOLE_ALTERNATE_20261013_V1'
    assert args.source != args.target
    assert all(re.fullmatch(r'[A-Za-z0-9]{6,32}', s) for s in [args.source, args.target])

    def read(name):
        return json.loads((root/name).read_text(encoding='utf-8-sig'))

    def save(name, value):
        destination = root/name
        temporary = destination.with_suffix(destination.suffix+'.tmp')
        temporary.write_text(json.dumps(value, indent=2)+'\n', encoding='utf-8')
        temporary.replace(destination)

    def adb(device, *command, absent=False, timeout=30):
        r = subprocess.run([args.adb, '-s', device, *command], capture_output=True, timeout=timeout)
        if absent and r.returncode == 1 and not r.stdout.strip() and not r.stderr.strip():
            return b''
        assert r.returncode == 0, 'ADB failed; preserve state and inspect, no automatic retry'
        return r.stdout

    def sha(file):
        return hashlib.sha256(file.read_bytes()).hexdigest()

    def package(device):
        value = adb(device, 'shell', 'pm', 'path', '--user', '0', PACKAGE, absent=True).decode().strip()
        if not value:
            return None
        m = re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)', value)
        assert m, 'Unexpected package layout'
        digest = adb(device, 'shell', 'sha256sum', m[1]).decode().split()[0]
        assert re.fullmatch('[a-f0-9]{64}', digest)
        return dict(path=m[1], sha256=digest)

    def sql():
        witness = environment/'sql-witness.private.py'
        linux = '/mnt/'+witness.drive[0].lower()+'/'+witness.as_posix()[3:]
        x = subprocess.run(['wsl.exe', '-d', 'HnuHole-Ubuntu-24.04', '-u', 'hnuhole', '--', 'python3', linux], capture_output=True, text=True, timeout=30)
        assert x.returncode == 0, 'Read-only SQL witness failed'
        return json.loads(x.stdout)

    def guard(device):
        assert adb(device, 'get-state').strip() == b'device'
        assert adb(device, 'shell', 'getprop', 'ro.kernel.qemu').strip() != b'1'
        assert adb(device, 'shell', 'am', 'get-current-user').strip() == b'0'
        if (root/'inventory.json').exists():
            assert adb(device, 'shell', 'getprop', 'ro.product.model').decode().strip() == read('inventory.json')['devices'][device]['model']

    def state(device):
        value = json.loads(adb(device, 'exec-out', 'run-as', PACKAGE, 'cat', 'files/b5-status.json'))
        assert value['owner'] == OWNER
        assert value.get('fixtureProtocol') == 2, 'Private test inputs must use no_backup'
        assert int(adb(device, 'shell', 'pidof', PACKAGE).strip()) == value['pid']
        return value

    def require_no_credential_ui(device):
        activities = adb(device, 'shell', 'dumpsys', 'activity', 'activities').decode(errors='replace')
        active = [line for line in activities.splitlines() if 'topResumedActivity=' in line or 'mResumedActivity:' in line]
        known = ('credentials.fido', 'credentialmanager/', 'com.google.android.gms/.fido.',
                 'com.google.android.gms/.auth.api.credentials.', 'OctarineWebviewActivity')
        assert not any(token in line for line in active for token in known), 'Credential UI active; preserve operation'

    def launch(device):
        guard(device)
        expected_build = read('build-result.json') if device == args.source else read('oem-transfer-result.json')
        assert package(device)['sha256'] == expected_build['apkSha256']
        cfg = read('device-config.public.json')
        for key in ['AUTH_COMMUNITY_BASE_URL', 'AUTH_VERIFIER_BASE_URL', 'AUTH_DEVICE_MAILPIT_URL']:
            port = cfg[key].rsplit(':', 1)[1]
            assert port.isdecimal()
            adb(device, 'reverse', 'tcp:'+port, 'tcp:'+port)
        assert not (root/('launch-'+device+'.json')).exists(), 'Existing launch must be inspected, not overwritten'
        save('launch-'+device+'.json', dict(owner=OWNER, state='LAUNCH_PENDING'))
        adb(device, 'shell', 'am', 'start', '-n', PACKAGE+'/org.hnuhole.hnuhole_mobile.MainActivity', '--ez', 'hnuhole-device-driver', 'true', '--es', 'hnuhole-device-phase', 'ni-d02', '--es', 'hnuhole-device-variant', 'control')
        until = time.monotonic()+90
        while time.monotonic() < until:
            try:
                value = state(device)
                if value['state'] == 'READY':
                    save('launch-'+device+'.json', value)
                    return value
            except (AssertionError, ValueError):
                pass
            time.sleep(.5)
        raise RuntimeError('Launch did not become ready; preserve original launch')

    def account():
        source = root/'account.private.json'
        value = json.loads((source if source.exists() else environment/'account.private.json').read_text())
        return {k: value[k] for k in ['username', 'password', 'oldRecoveryCode', 'oldSessionToken', 'accountId']}

    def command(device, step, expected, **extra):
        guard(device)
        expected_build = read('build-result.json') if device == args.source else read('oem-transfer-result.json')
        assert package(device)['sha256'] == expected_build['apkSha256'], 'Device payload changed outside this stage'
        before = state(device)
        assert before['state'] == expected
        journal = 'command-'+step+'.json'
        assert not (root/journal).exists(), 'Previous command/unknown outcome must be retained'
        value = dict(owner=OWNER, pid=before['pid'], nonce=before['nonce'], sequence=before['sequence']+1, step=step, **extra)
        save(journal, dict(owner=OWNER, device=device, state='COMMAND_PENDING', step=step, pid=before['pid'], sequence=value['sequence'], sqlBefore=sql(), automaticRetryPermitted=False))
        local = root/'command.private.json'
        save(local.name, value)
        remote = '/data/local/tmp/hnuhole-b5-'+uuid.uuid4().hex+'.json'
        try:
            adb(device, 'push', str(local), remote)
            adb(device, 'shell', 'run-as', PACKAGE, 'mkdir', '-p', 'no_backup')
            adb(device, 'shell', 'run-as', PACKAGE, 'cp', remote, 'no_backup/b5-command.json')
        finally:
            adb(device, 'shell', 'rm', '-f', remote)
            local.unlink()
        return dict(state='COMMAND_SENT', step=step, device=device, sequence=value['sequence'])

    for device in [args.source, args.target]:
        guard(device)
    if args.action == 'inventory':
        assert not (root/'inventory.json').exists()
        devices = {}
        for device in [args.source, args.target]:
            devices[device] = {
                'model': adb(device, 'shell', 'getprop', 'ro.product.model').decode().strip(),
                'android': adb(device, 'shell', 'getprop', 'ro.build.version.release').decode().strip(),
                'isEmulator': False,
                'testPackage': package(device),
                'credentialService': adb(device, 'shell', 'settings', 'get', 'secure', 'credential_service').decode().strip(),
                'autofillService': adb(device, 'shell', 'settings', 'get', 'secure', 'autofill_service').decode().strip(),
            }
        assert devices[args.target]['testPackage'] is None, 'Target test package must initially be absent'
        save('inventory.json', dict(owner=OWNER, collectedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), source=args.source, target=args.target, devices=devices, sqlBefore=sql()))
        print(json.dumps(dict(state='INVENTORY_RECORDED', devices=devices)))
    elif args.action == 'install-source':
        original = read('inventory.json')['devices'][args.source]['testPackage']
        current = package(args.source)
        assert current == original
        assert original['sha256'] == 'bb252713ab57ea1f5878c10c78370395f1a1274bdd4b6949b24e5db5b456eb18', 'Unrecognized original approved test package'
        require_no_credential_ui(args.source)
        backup = root/'source-before.apk'
        assert not backup.exists() and not (root/'source-install.json').exists()
        adb(args.source, 'pull', original['path'], str(backup), timeout=120)
        assert sha(backup) == original['sha256']
        build = read('build-result.json')
        candidate = root/'b5-android-arm64.apk'
        assert build['result'] == 'PASS' and sha(candidate) == build['apkSha256']
        save('source-install.json', dict(owner=OWNER, state='INSTALL_PENDING', beforeSha256=original['sha256'], candidateSha256=build['apkSha256']))
        result = adb(args.source, 'install', '--no-streaming', '-t', '-r', str(candidate), timeout=180)
        assert b'Success' in result and package(args.source)['sha256'] == build['apkSha256']
        save('source-install.json', dict(owner=OWNER, state='INSTALLED', beforeSha256=original['sha256'], apkSha256=build['apkSha256']))
        print('INSTALLED: approved test package updated; original APK retained')
    elif args.action == 'launch-source':
        print(json.dumps(launch(args.source)))
    elif args.action == 'resume-source':
        # OEM tools can stop the source App. Only a pre-native accepted login
        # may be resumed; a pending/completed native operation is never reset.
        previous = json.loads(adb(args.source, 'exec-out', 'run-as', PACKAGE, 'cat', 'files/b5-status.json'))
        assert previous['owner'] == OWNER and previous.get('fixtureProtocol') == 2
        assert previous['state'] == 'SOURCE_AUTHENTICATED' and previous['createAttempts'] == previous['getAttempts'] == 0
        assert not (root/'command-source-bind.json').exists()
        assert not adb(args.source, 'shell', 'pidof', PACKAGE, absent=True).strip()
        assert sql() == dict(accounts=1, passkeys=0, activeSessions=1, activeResets=0)
        for name in ['launch-'+args.source+'.json', 'command-source-login.json']:
            old = root/name
            destination = root/(old.stem+'-before-oem-pid'+str(previous['pid'])+'.json')
            assert old.is_file() and not destination.exists()
            old.rename(destination)
        launch(args.source)
        print(json.dumps(command(args.source, 'source-login', 'READY', account=account())))
    elif args.action == 'source-login':
        print(json.dumps(command(args.source, 'source-login', 'READY', account=account())))
    elif args.action == 'observe-target':
        receipt = read('oem-transfer-result.json')
        assert receipt['owner'] == OWNER and receipt['actualOemTransferCompleted'] is True
        launch(args.target)
        print(json.dumps(command(args.target, 'target-observe', 'READY')))
    elif args.action == 'source-bind':
        assert sql() == dict(accounts=1, passkeys=0, activeSessions=1, activeResets=0)
        assert read('oem-transfer-result.json')['actualOemTransferCompleted'] is True
        assert state(args.target)['state'] == 'MIGRATION_EMPTY'
        print(json.dumps(command(args.source, 'source-bind', 'SOURCE_AUTHENTICATED')))
    elif args.action == 'collect-source':
        assert state(args.source)['state'] == 'SOURCE_BOUND'
        assert sql() == dict(accounts=1, passkeys=1, activeSessions=1, activeResets=0)
        value = json.loads(adb(args.source, 'exec-out', 'run-as', PACKAGE, 'cat', 'no_backup/b5-source.private.json'))
        assert value['owner'] == OWNER and value['username'] == account()['username']
        save('account.private.json', value)
        save('source-binding-result.json', dict(owner=OWNER, result='PASS', nativeCreationAttempts=1, actualProductCommit=True, sql=sql(), rawProofExported=False))
        print('PASS: native creation, product C commit and independent SQL')
    elif args.action == 'prepare-target-retry':
        # One explicit retry after provider preparation. Preserve the first
        # timeout and its journals; never reset data or replay a proof.
        if args.retry_id is None:
            plan_name = 'target-retry-plan.json'
            attempt = 1
        else:
            assert re.fullmatch(r'user-[a-z0-9-]{6,64}', args.retry_id)
            assert read('target-retry-plan.json')['state'] == 'PREPARED'
            plan_name = 'target-retry-'+args.retry_id+'.json'
            attempt = 1 + len(list(root.glob('target-retry-*.json')))
        assert not (root/plan_name).exists(), 'Authorization already consumed; do not automatically retry'
        previous = json.loads(adb(args.target, 'exec-out', 'run-as', PACKAGE, 'cat', 'files/b5-status.json'))
        native = json.loads(adb(args.target, 'exec-out', 'run-as', PACKAGE, 'cat', 'files/owned-acceptance-passkey.json'))
        assert previous['owner'] == OWNER and previous.get('fixtureProtocol') == 2
        assert previous['state'] == 'FAILED_OR_UNKNOWN' and previous['failedStep'] == 'target-recover'
        assert previous['createAttempts'] == 0 and previous['getAttempts'] == 1
        assert native['pid'] == previous['pid'] and native.get('nativeBegun') == native.get('nativeTimeout') == 1
        assert not native.get('nativeSucceeded', 0)
        assert sql() == dict(accounts=1, passkeys=1, activeSessions=1, activeResets=0)
        assert read('NI-X01-result.json')['result'] == 'PASS'
        assert read('source-binding-result.json')['result'] == 'PASS'
        assert package(args.target)['sha256'] == read('oem-transfer-result.json')['apkSha256']
        require_no_credential_ui(args.target)
        names = ['launch-'+args.target+'.json', 'command-target-observe.json', 'command-target-recover.json']
        suffix = f'.attempt{attempt:02}.json'
        assert all((root/name).is_file() and not (root/(Path(name).stem+suffix)).exists() for name in names)
        receipt_name = f'target-get-attempt{attempt:02}-result.json'
        if (root/receipt_name).exists():
            old_receipt = read(receipt_name)
            assert old_receipt['owner'] == OWNER and old_receipt['result'] == 'FAIL_NATIVE_TIMEOUT'
            recorded = old_receipt.get('previous') or old_receipt['devices']['target']['state']
            assert recorded == previous, 'Original timeout receipt must match this exact operation'
        else:
            save(receipt_name, dict(owner=OWNER, result='FAIL_NATIVE_TIMEOUT', previous=previous, native=native, sqlAfter=sql(), resetIntentCreated=False, userCancellationProven=False, rawProofExported=False))
        plan = dict(owner=OWNER, explicitRetryLimit=1, cumulativeGetAttempt=attempt+1, providerPreparation=True, originalFailurePreserved=True, dataReset=False, proofReplay=False, authorizationLabel=args.retry_id or 'initial-explicit-provider-retry')
        save(plan_name, dict(plan, state='PREPARING'))
        for name in names:
            (root/name).rename(root/(Path(name).stem+suffix))
        adb(args.target, 'shell', 'am', 'force-stop', PACKAGE)
        launch(args.target)
        result = command(args.target, 'target-observe', 'READY')
        save(plan_name, dict(plan, state='PREPARED'))
        print(json.dumps(result))
    elif args.action == 'target-recover':
        assert read('source-binding-result.json')['result'] == 'PASS'
        assert sql() == dict(accounts=1, passkeys=1, activeSessions=1, activeResets=0)
        print(json.dumps(command(args.target, 'target-recover', 'MIGRATION_EMPTY', account=account())))
    elif args.action == 'confirm-reset':
        assert sql() == dict(accounts=1, passkeys=1, activeSessions=1, activeResets=1)
        print(json.dumps(command(args.target, 'confirm-reset', 'RESET_INTENT_READY', syntheticRecoveryAcknowledged=True)))
    elif args.action == 'verify-login':
        assert sql() == dict(accounts=1, passkeys=0, activeSessions=0, activeResets=0)
        print(json.dumps(command(args.target, 'verify-login', 'RESET_COMMITTED_NO_SESSION')))
    else:
        values={}
        for device in [args.source, args.target]:
            try:
                values[device]=state(device)
            except (AssertionError, ValueError):
                values[device]={'state': 'B5_NOT_RUNNING'}
        print(json.dumps(dict(devices=values, sql=sql())))


if __name__ == '__main__':
    main()
