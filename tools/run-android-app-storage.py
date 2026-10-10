#!/usr/bin/env python3
"""Full owned Android App process/reinstall/ciphertext-restore acceptance.

This runner operates only the explicitly owned emulator and synthetic boundary
configuration. It never exports keys or plaintext product authentication state.
"""
import argparse
import base64
import datetime
import hashlib
import json
import re
import subprocess
import uuid
from pathlib import Path

PACKAGE = 'org.hnuhole.hnuhole_mobile'
DEVICE = 'emulator-5554'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--apk', required=True, type=Path)
    parser.add_argument('--resume-restore', action='store_true')
    args = parser.parse_args()
    work = args.work.resolve(strict=True)
    assert work == Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix').resolve()
    assert (work / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    apk = args.apk.resolve(strict=True)
    assert apk.parent == work and apk.name == 'storage.apk'
    driver = work / 'emulator-driver/apps/mobile'
    assert (driver / '.device-app-owner').read_text().strip() == DEVICE + '|hnuhole-android-live-matrix-20261006'
    config_path = work / 'boundary-device-config.json'
    config = json.loads(config_path.read_text())
    assert config['AUTH_MATRIX_ACCOUNT_RUN_ID'] == 'hnuhole-android-live-boundary-20261006'
    adb_path = 'D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe'
    log = work / 'app-storage-host.private.log'
    repo = Path(__file__).resolve().parents[1]
    sha = hashlib.sha256(apk.read_bytes()).hexdigest()
    reports = []

    def adb(*arguments, data=None, absent=False):
        result = subprocess.run([adb_path, '-s', DEVICE, *arguments], input=data,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if absent and result.returncode == 1 and not result.stdout.strip() and not result.stderr.strip():
            return b''
        with log.open('ab') as out:
            out.write(result.stderr)
        assert result.returncode == 0, 'Owned adb operation failed; diagnostics are local'
        return result.stdout

    def installed_hash():
        value = adb('shell', 'pm', 'path', PACKAGE, absent=True).decode().strip()
        match = re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)', value)
        if not match:
            assert not value
            return None
        return adb('shell', 'sha256sum', match[1]).decode().split()[0]

    def phase(name):
        command = ['pwsh', '-NoProfile', '-File', str(repo / 'tools/run-android-live-device.ps1'),
                   '-DeviceId', DEVICE, '-Apk', str(apk), '-ConfigFile', str(config_path),
                   '-DriverWorkspace', str(driver), '-PubCache', str(work.parent / 'pub-windows'),
                   '-StoragePhases', name]
        with (work / (name + '.private.log')).open('wb') as out:
            completed = subprocess.run(command, stdout=out, stderr=subprocess.STDOUT)
        assert completed.returncode == 0, 'Actual App phase failed: ' + name
        report = json.loads((driver / ('live-' + name + '.json')).read_text())
        assert report['phase'] == name and report['actualApp'] and report['nativeVault']
        reports.append({'id': name, 'result': 'PASS', 'exitCode': 0, 'apkSha256': sha, 'report': report})
        (work / 'app-storage-checkpoint.json').write_text(json.dumps(reports, indent=2) + '\n')
        print('PASS: ' + name, flush=True)

    assert adb('shell', 'getprop', 'ro.kernel.qemu').strip() == b'1'
    assert adb('shell', 'getprop', 'sys.boot_completed').strip() == b'1'
    accepted_boundary = hashlib.sha256((work / 'boundary.apk').read_bytes()).hexdigest()
    assert installed_hash() in {accepted_boundary, sha}, 'Existing emulator App not owned'
    scope = 'hnuhole.isolated.auth.v1|' + config['AUTH_COMMUNITY_BASE_URL'] + '|' + config['AUTH_VERIFIER_BASE_URL']
    digest = base64.urlsafe_b64encode(hashlib.sha256(b'HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1\0' + scope.encode()).digest()).decode().rstrip('=')
    name = 'no_backup/hnuhole.auth.v1.' + digest + '.auth'
    cipher_path = work / 'app-storage-ciphertext.private.bin'
    if args.resume_restore:
        assert installed_hash() == sha
        reports.extend(json.loads((work / 'app-storage-checkpoint.json').read_text()))
        assert [r['id'] for r in reports] == ['storage-source', 'storage-restart', 'storage-fresh']
        assert all(r['result'] == 'PASS' and r['apkSha256'] == sha for r in reports)
        ciphertext = cipher_path.read_bytes()
    else:
        assert b'Success' in adb('install', '--no-streaming', '-t', '-r', str(apk))
        assert installed_hash() == sha
        phase('storage-source')
        phase('storage-restart')
        assert reports[0]['report']['pid'] != reports[1]['report']['pid']
        adb('shell', 'am', 'force-stop', PACKAGE)
        ciphertext = adb('exec-out', 'run-as', PACKAGE, 'cat', name)
        cipher_path.write_bytes(ciphertext)
        assert installed_hash() == sha
        assert b'Success' in adb('uninstall', PACKAGE)
        assert installed_hash() is None
        assert b'Success' in adb('install', '--no-streaming', '-t', str(apk))
        assert installed_hash() == sha
        phase('storage-fresh')
    assert 29 <= len(ciphertext) <= 65565 and ciphertext[0] == 1
    adb('shell', 'am', 'force-stop', PACKAGE)
    # Fresh App may create its own empty record/key. A second owned reinstall
    # removes that key before restoring only the old encrypted product record.
    assert b'Success' in adb('uninstall', PACKAGE)
    assert b'Success' in adb('install', '--no-streaming', '-t', str(apk))
    assert installed_hash() == sha
    # Windows adb shell stdin can truncate binary data. Push the encrypted
    # file through adb's binary sync protocol, then copy inside the owned UID.
    remote = '/data/local/tmp/hnuhole-owned-storage-' + uuid.uuid4().hex + '.cipher'
    try:
        adb('push', str(cipher_path), remote)
        assert adb('shell', 'sha256sum', remote).decode().split()[0] == hashlib.sha256(ciphertext).hexdigest()
        adb('shell', 'run-as', PACKAGE, 'mkdir', '-p', 'no_backup')
        adb('shell', 'run-as', PACKAGE, 'cp', remote, name)
    finally:
        adb('shell', 'rm', '-f', remote)
    restored = adb('exec-out', 'run-as', PACKAGE, 'cat', name)
    (work / 'app-storage-copy-check.json').write_text(json.dumps({'originalBytes': len(ciphertext),
        'restoredBytes': len(restored), 'bytesEqualBeforeAppStartup': restored == ciphertext}, indent=2) + '\n')
    assert restored == ciphertext, 'Host restore changed encrypted bytes before App startup'
    phase('storage-restored-no-key')
    adb('shell', 'am', 'force-stop', PACKAGE)
    assert adb('exec-out', 'run-as', PACKAGE, 'cat', name) == ciphertext
    result = {'schemaVersion': 'hnuhole-full-app-storage/v1', 'result': 'PASS',
              'verifiedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'device': DEVICE, 'targetIsEmulator': True, 'applicationId': PACKAGE,
              'apkSha256': sha, 'phases': reports, 'keysExported': False,
              'copiedProductCiphertextOnly': True, 'ciphertextBytesPreserved': True,
              'actualAppSessionAndDraftRestartPassed': True,
              'actualAppUninstallFreshStatePassed': True,
              'actualAppRestoredCiphertextMissingKeyPassed': True,
              'physicalPhoneUninstalled': False, 'oemDeviceTransferPassed': False,
              'scope': 'Owned emulator actual App; controlled ciphertext restore, not OEM migration.'}
    (work / 'app-storage-result.json').write_text(json.dumps(result, indent=2) + '\n')
    # Leave the reusable emulator App fresh after retaining the failed-key
    # evidence; remove only the exact restored synthetic product record.
    adb('shell', 'run-as', PACKAGE, 'rm', name)
    (work / 'app-storage-ciphertext.private.bin').unlink()
    print('PASS: full App storage restart/reinstall/restored-key rejection; phone unchanged')


if __name__ == '__main__':
    main()
