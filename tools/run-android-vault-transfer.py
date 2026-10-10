"""Owned native ciphertext transfer/reinstall probe; never touches the main App.

The source may run the older write/read probe. The target must be an emulator
and receives the current probe APK. Only synthetic test ciphertext is copied;
AndroidKeyStore keys are never exported. This proves the native storage boundary,
not OEM migration or full App reinstallation.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import uuid

PACKAGE = 'org.hnuhole.authvault.test'
RUNNER = PACKAGE + '/androidx.test.runner.AndroidJUnitRunner'
TEST = 'org.hnuhole.authvault.AuthVaultProcessRestartTest'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', required=True)
    parser.add_argument('--source-device', required=True)
    parser.add_argument('--source-apk', type=Path, required=True)
    parser.add_argument('--target-emulator', required=True)
    parser.add_argument('--target-apk', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--allow-probe-reinstall', action='store_true')
    args = parser.parse_args()
    assert args.allow_probe_reinstall, 'Explicit owned emulator probe reinstall required'
    assert re.fullmatch(r'emulator-\d+', args.target_emulator)
    assert args.source_device != args.target_emulator
    work = args.work.resolve()
    assert (work / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    assert args.source_apk.resolve().parent == work
    assert args.target_apk.resolve().parent == work
    log = work / 'vault-transfer.private.log'
    log.write_bytes(b'')

    def adb(device, *command, data=None, absent_package=False):
        completed = subprocess.run([args.adb, '-s', device, *command], input=data,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   timeout=180, check=False)
        # Instrumentation is restricted to the test package. No user data logs.
        with log.open('ab') as output:
            output.write(completed.stderr)
        if absent_package and completed.returncode == 1 and not completed.stdout.strip() \
                and not completed.stderr.strip():
            return b''  # pm path uses exit 1 when this exact package is absent.
        assert completed.returncode == 0, 'Owned adb operation failed; see private log'
        return completed.stdout

    def installed_hash(device):
        path = adb(device, 'shell', 'pm', 'path', PACKAGE,
                   absent_package=True).decode().strip()
        match = re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)', path)
        if not match:
            assert not path, 'Unexpected split or package path'
            return None
        value = adb(device, 'shell', 'sha256sum', match[1]).decode().split()[0]
        assert re.fullmatch(r'[a-f0-9]{64}', value)
        return value

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def phase(device, name, namespace):
        assert re.fullmatch(r'native\.restart\.[A-Za-z0-9_.-]{1,80}', namespace)
        output = adb(device, 'shell', 'am', 'instrument', '-w', '-e', 'class', TEST,
                     '-e', 'vault_restart_phase', name, '-e', 'vault_restart_namespace',
                     namespace, RUNNER)
        with log.open('ab') as target:
            target.write(name.encode() + b'\n' + output)
        assert b'OK (1 test)' in output and b'FAILURES' not in output and \
            b'INSTRUMENTATION_FAILED' not in output, 'Native probe did not pass'

    def export_record(device, namespace):
        data = adb(device, 'exec-out', 'run-as', PACKAGE, 'cat',
                   'no_backup/' + namespace + '.auth')
        assert 29 <= len(data) <= 65565 and data[0] == 1
        return data

    def restore_record(device, namespace, data):
        # Windows adb shell stdin can truncate binary bytes. Sync a temporary
        # encrypted file, copy inside the owned UID, then verify exact bytes.
        temporary = work / (namespace + '.private.bin')
        remote = '/data/local/tmp/hnuhole-owned-vault-' + uuid.uuid4().hex + '.cipher'
        temporary.write_bytes(data)
        try:
            adb(device, 'push', str(temporary), remote)
            assert adb(device, 'shell', 'sha256sum', remote).decode().split()[0] == hashlib.sha256(data).hexdigest()
            adb(device, 'shell', 'run-as', PACKAGE, 'mkdir', '-p', 'no_backup')
            adb(device, 'shell', 'run-as', PACKAGE, 'cp', remote, 'no_backup/' + namespace + '.auth')
            assert export_record(device, namespace) == data
        finally:
            adb(device, 'shell', 'rm', '-f', remote)
            temporary.unlink()

    source_sha, target_sha = digest(args.source_apk), digest(args.target_apk)
    assert installed_hash(args.source_device) == source_sha, 'Source APK not owned'
    assert adb(args.target_emulator, 'shell', 'getprop', 'ro.kernel.qemu').strip() == b'1'
    assert adb(args.target_emulator, 'shell', 'getprop', 'sys.boot_completed').strip() == b'1'
    existing = installed_hash(args.target_emulator)
    assert existing is None or existing in {source_sha, target_sha}, 'Target APK not owned'
    output = adb(args.target_emulator, 'install', '--no-streaming', '-t', '-r',
                 str(args.target_apk.resolve()))
    assert b'Success' in output and installed_hash(args.target_emulator) == target_sha
    namespace = 'native.restart.' + uuid.uuid4().hex + '.transfer'
    source_written = False
    try:
        phase(args.source_device, 'write', namespace)
        source_written = True
        ciphertext = export_record(args.source_device, namespace)
        restore_record(args.target_emulator, namespace, ciphertext)
        phase(args.target_emulator, 'read-restored-without-device-key', namespace)
    finally:
        if source_written:
            phase(args.source_device, 'read', namespace)  # Removes only this record/key.
    namespace = 'native.restart.' + uuid.uuid4().hex + '.reinstall'
    phase(args.target_emulator, 'write', namespace)
    ciphertext = export_record(args.target_emulator, namespace)
    assert installed_hash(args.target_emulator) == target_sha
    # Exact reviewed APK + emulator check above; no main App or phone uninstall.
    assert b'Success' in adb(args.target_emulator, 'uninstall', PACKAGE)
    assert installed_hash(args.target_emulator) is None
    assert b'Success' in adb(args.target_emulator, 'install', '--no-streaming', '-t',
                             str(args.target_apk.resolve()))
    assert installed_hash(args.target_emulator) == target_sha
    phase(args.target_emulator, 'read-fresh-after-reinstall', namespace)
    restore_record(args.target_emulator, namespace, ciphertext)
    phase(args.target_emulator, 'read-restored-without-device-key', namespace)
    result = {
        'schemaVersion': 'hnuhole-native-vault-transfer/v1',
        'verifiedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'result': 'PASS', 'sourceApkSha256': source_sha, 'targetApkSha256': target_sha,
        'sourceModel': adb(args.source_device, 'shell', 'getprop', 'ro.product.model').decode().strip(),
        'targetModel': adb(args.target_emulator, 'shell', 'getprop', 'ro.product.model').decode().strip(),
        'targetIsEmulator': True, 'testPackage': PACKAGE,
        'copiedSyntheticCiphertextOnly': True, 'keysExported': False,
        'crossDeviceReadAndOverwriteRejected': True,
        'copiedBytesPreservedAndNoKeyCreated': True,
        'uninstallRemovedOwnedRecordAndKey': True,
        'restoredAfterReinstallReadAndOverwriteRejected': True,
        'sourceSyntheticRecordAndKeyRemoved': True,
        'mainAppUninstalled': False, 'fullAppMigrationPassed': False,
        'oemDeviceTransferPassed': False,
    }
    (work / 'vault-transfer-result.json').write_text(json.dumps(result, indent=2) + '\n')
    print('PASS: physical-to-emulator ciphertext rejected; owned emulator probe reinstall and restored-state rejection')


if __name__ == '__main__':
    main()
