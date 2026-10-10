"""Owned emulator App OTP continuation, with natural V expiry/cleanup.

Start sends one synthetic OTP and tests frozen V; finish requires at least ten
minutes of actual elapsed time and read-only proof of normal flow cleanup.
No SQL timestamps, user data, keys or API authority are fabricated or exported.
"""
import argparse
import datetime
import hashlib
import json
import re
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--stage', choices=['start', 'finish'], required=True)
    args = parser.parse_args()
    work = args.work.resolve(strict=True)
    assert work == Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix').resolve()
    assert (work / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    repo = Path(__file__).resolve().parents[1]
    driver = work / 'emulator-driver/apps/mobile'
    assert (driver / '.device-app-owner').read_text().strip() == 'emulator-5554|hnuhole-android-live-matrix-20261006'
    config = work / 'boundary-device-config.json'
    assert json.loads(config.read_text())['AUTH_MATRIX_ACCOUNT_RUN_ID'] == 'hnuhole-android-live-boundary-20261006'
    apk = work / 'otp-continuation.apk'
    sha = hashlib.sha256(apk.read_bytes()).hexdigest()
    checkpoint = work / 'otp-continuation-checkpoint.json'
    log = work / 'otp-continuation-host.private.log'

    def adb(*arguments):
        r = subprocess.run(['D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe',
                            '-s', 'emulator-5554', *arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with log.open('ab') as out: out.write(r.stderr)
        assert r.returncode == 0, 'Owned adb operation failed; diagnostics retained locally'
        return r.stdout

    def installed_hash():
        path = re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)',
                            adb('shell', 'pm', 'path', 'org.hnuhole.hnuhole_mobile').decode().strip())
        assert path
        return adb('shell', 'sha256sum', path[1]).decode().split()[0]

    def control(action, label=None):
        command = ['wsl', '-d', 'Ubuntu-24.04', '--', 'python3',
                   '/mnt/c/Users/Administrator/Documents/ChatGPT/HnuHole/tools/control-android-auth-boundary.py',
                   '--work', '/var/tmp/hnuhole-android-live-boundary-20261006', '--action', action]
        if label: command += ['--label', label]
        r = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert r.returncode == 0, 'Owned V control/readback failed'
        return json.loads(r.stdout) if label else None

    def phase(name):
        command = ['pwsh', '-NoProfile', '-File', str(repo / 'tools/run-android-live-device.ps1'),
                   '-DeviceId', 'emulator-5554', '-Apk', str(apk), '-ConfigFile', str(config),
                   '-DriverWorkspace', str(driver), '-PubCache', str(work.parent / 'pub-windows'),
                   '-OtpContinuationPhases', name]
        with (work / (name + '.private.log')).open('wb') as out:
            r = subprocess.run(command, stdout=out, stderr=subprocess.STDOUT)
        assert r.returncode == 0, 'Actual App continuation phase failed: ' + name
        report = json.loads((driver / ('live-' + name + '.json')).read_text())
        assert report['actualApp'] and report['actualCV'] and report['nativeVault'] and report['phase'] == name
        evidence['phases'].append({'id': name, 'result': 'PASS', 'apkSha256': sha, 'report': report})
        evidence['counts'][name] = control('capture', name)['counts']
        checkpoint.write_text(json.dumps(evidence, indent=2) + '\n')
        print('PASS: ' + name, flush=True)

    assert adb('shell', 'getprop', 'ro.kernel.qemu').strip() == b'1'
    assert adb('shell', 'getprop', 'sys.boot_completed').strip() == b'1'
    if args.stage == 'start':
        assert not checkpoint.exists(), 'Existing continuation operation must be resumed, not replaced'
        before = control('capture', 'otp-continuation-before')['counts']
        assert before['v']['gateState'] == 'OPEN' and before['v']['otpFlows'] == 0 and before['v']['confirmations'] == 0
        assert installed_hash() == hashlib.sha256((work / 'storage.apk').read_bytes()).hexdigest()
        assert b'Success' in adb('install', '--no-streaming', '-t', '-r', str(apk))
        assert installed_hash() == sha
        evidence = {'schemaVersion': 'hnuhole-android-otp-continuation/v1', 'result': 'NOT_RUN',
                    'apkSha256': sha, 'counts': {'before': before}, 'phases': [],
                    'sqlDeadlinesChanged': False, 'phonePackageChanged': False}
        phase('otp-continuation-request')
        evidence['requestedAtUTC'] = evidence['phases'][0]['report']['requestedAtUTC']
        checkpoint.write_text(json.dumps(evidence, indent=2) + '\n')
        frozen = False
        try:
            control('freeze-v'); frozen = True
            phase('otp-continuation-frozen')
        finally:
            if frozen: control('recover-v')
        assert evidence['counts']['otp-continuation-request']['v']['sendBudgetEvents'] == before['v']['sendBudgetEvents'] + 1
        assert evidence['counts']['otp-continuation-frozen']['v']['confirmations'] == 0
        print('READY: retained original operation; finish after natural ten-minute cleanup', flush=True)
        return
    evidence = json.loads(checkpoint.read_text())
    assert installed_hash() == evidence['apkSha256']
    assert [x['id'] for x in evidence['phases']] == ['otp-continuation-request', 'otp-continuation-frozen']
    elapsed = (datetime.datetime.now(datetime.timezone.utc) - datetime.datetime.fromisoformat(evidence['requestedAtUTC'])).total_seconds()
    assert elapsed >= 600, 'Natural flow expiry/retention window still active; keep the original operation'
    cleaned = control('capture', 'otp-continuation-cleaned')['counts']
    assert cleaned['v']['gateState'] == 'OPEN' and cleaned['v']['otpFlows'] == 0 and cleaned['v']['confirmations'] == 0
    assert cleaned['c'] == evidence['counts']['before']['c']
    if evidence['apkSha256'] != sha:
        original_apk = work / 'otp-continuation-start.apk'
        assert hashlib.sha256(original_apk.read_bytes()).hexdigest() == evidence['apkSha256']
        assert b'Success' in adb('install', '--no-streaming', '-t', '-r', str(apk))
        assert installed_hash() == sha
        evidence['startApkSha256'] = evidence['apkSha256']
        evidence['apkSha256'] = sha
    phase('otp-continuation-cleaned')
    assert evidence['counts']['otp-continuation-cleaned']['v']['sendBudgetEvents'] == evidence['counts']['otp-continuation-request']['v']['sendBudgetEvents']
    phase('otp-continuation-resume')
    final = evidence['counts']['otp-continuation-resume']
    assert final['c'] == evidence['counts']['before']['c']
    assert final['v']['confirmations'] == 1 and final['v']['ticketAvailable'] == 1
    assert final['v']['sendBudgetEvents'] == evidence['counts']['otp-continuation-request']['v']['sendBudgetEvents'] + 1
    assert len({x['report']['pid'] for x in evidence['phases']}) == 4
    evidence.update(result='PASS', elapsedSecondsBeforeCleanedPost=round(elapsed), normalCleanupObserved=True,
                    noExtraMailBeforeExplicitRequest=True, originalBootstrapRetained=True,
                    actualNewOtpTicketPassed=True, noCAccountSessionMutation=True)
    (work / 'otp-continuation-result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print('PASS: actual App normal-cleanup OTP continuation, native restart and same-bootstrap ticket', flush=True)


if __name__ == '__main__':
    main()
