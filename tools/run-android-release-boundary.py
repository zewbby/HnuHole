#!/usr/bin/env python3
"""Installed release probe for native driver and explicit development trust."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

PACKAGE = 'org.hnuhole.hnuhole_mobile'
DEVICE = 'emulator-5554'


def admit_work(work, environment_root, b6, fixed_b3_b4=False):
    work = work.resolve(strict=True)
    if b6:
        assert not fixed_b3_b4
        assert work.parent == environment_root.resolve(strict=True)
        assert re.fullmatch(r'b6-\d{8}', work.name)
        date = work.name[3:]
        owner = 'HNUHOLE_B6_SINGLE_ANDROID_' + date + '_V1'
        assert (work / 'OWNER').read_text().strip() == owner
        emulator = json.loads((work / 'emulator-owner.json').read_text())
        assert emulator['owner'] == owner and emulator['device'] == DEVICE
        assert emulator['avd'] == 'hnuhole-' + work.name
        assert emulator['newOwnedAVD'] is True and emulator['existingAVDDataCopied'] is False
        return emulator
    else:
        assert work == Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix').resolve()
        assert (work / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
        assert (work / 'emulator-driver/apps/mobile/.device-app-owner').read_text().strip() == DEVICE + '|hnuhole-android-live-matrix-20261006'
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--fixed-b3-b4', action='store_true')
    parser.add_argument('--b6-owned-emulator', action='store_true')
    parser.add_argument('--environment-root', type=Path,
                        default=Path('D:/zewbbyTest/Hnuhole-env'))
    args = parser.parse_args()
    work = args.work.resolve(strict=True)
    emulator = admit_work(work, args.environment_root, args.b6_owned_emulator, args.fixed_b3_b4)
    sdk = args.environment_root / 'android-sdk'
    adb_path = sdk / 'platform-tools/adb.exe'
    release = work / 'release-guard.apk'
    sha = hashlib.sha256(release.read_bytes()).hexdigest()
    accepted_names = (['debug-standard-x64.apk'] if args.b6_owned_emulator else
                      ['storage.apk', 'boundary.apk', 'phone-batch.apk',
                       'phone-b1b2.apk', 'phone-b1b2-v4.apk'])
    accepted_debug = {hashlib.sha256((work / name).read_bytes()).hexdigest(): work / name
                      for name in accepted_names
                      if (work / name).exists()}
    aapt = sorted((sdk / 'build-tools').glob('*/aapt2.exe'))[-1]
    manifest = subprocess.check_output([str(aapt), 'dump', 'xmltree', str(release), '--file', 'AndroidManifest.xml']).decode()
    assert 'org.hnuhole.hnuhole_mobile' in manifest
    debuggable = re.search(r'android:debuggable[^\n]*', manifest)
    assert debuggable is None or re.search(r'(?:0x0|false)\s*$', debuggable[0])
    assert 'asset_statements' not in manifest
    assert 'GoogleFidoDiagnosticActivity' not in manifest

    def adb(*args, allow_error=False):
        result = subprocess.run([str(adb_path), '-s', DEVICE, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if not allow_error:
            assert result.returncode == 0, 'Owned release probe operation failed'
        return result

    def installed_hash():
        path = adb('shell', 'pm', 'path', PACKAGE).stdout.decode().strip()
        assert re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk', path)
        return adb('shell', 'sha256sum', path[len('package:'):]).stdout.decode().split()[0]

    assert adb('shell', 'getprop', 'ro.kernel.qemu').stdout.strip() == b'1'
    if args.b6_owned_emulator:
        assert adb('emu', 'avd', 'name').stdout.decode().splitlines()[0] == emulator['avd']
    original_sha = installed_hash()
    assert original_sha in accepted_debug, 'Existing emulator App not owned'
    restore = accepted_debug[original_sha]
    try:
        assert b'Success' in adb('install', '--no-streaming', '-t', '-r', str(release)).stdout
        assert installed_hash() == sha
        adb('shell', 'am', 'force-stop', PACKAGE)
        adb('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity', '--ez', 'hnuhole-device-driver', 'true', '--es', 'hnuhole-device-phase', 'ni-d02' if args.fixed_b3_b4 else 'ni-l04')
        result = None
        pid = None
        for _ in range(45):
            process = adb('shell', 'pidof', PACKAGE, allow_error=True).stdout.decode().strip()
            if process.isdigit():
                pid = int(process)
                logs = adb('logcat', '-d', '--pid=' + process, '-s', 'flutter:I').stdout.decode(errors='replace')
                match = re.search(r'HNUHOLE_RELEASE_BOUNDARY (\{[^\n]+\})', logs)
                if match:
                    result = json.loads(match[1])
                    break
            time.sleep(1)
        assert result and result['result'] == 'PASS'
        expected = {'actualReleaseMode', 'nativeOwnedDriverUnavailable', 'explicitOwnedTestTrustPresent',
            'developmentCaRejected', 'developmentRpRejected', 'normalHttpClientAvailable',
            'acceptanceLifecycleUnavailable', 'acceptanceRecreateUnavailable',
            'acceptanceStateUnavailable', 'acceptanceLateCallbackUnavailable',
            'acceptanceGetSelectedUnavailable', 'acceptanceCreationLabelUnavailable'}
        if args.fixed_b3_b4 or args.b6_owned_emulator:
            expected.add('variantUnavailable')
        assert set(result['checks']) == expected
        assert all(value is True for value in result['checks'].values())
        run_as = adb('shell', 'run-as', PACKAGE, 'true', allow_error=True)
        assert run_as.returncode != 0 and b'not debuggable' in run_as.stderr
        report = {'schemaVersion': 'hnuhole-release-boundary/v1', 'result': 'PASS',
                  'verifiedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'apkSha256': sha, 'pid': pid, 'device': DEVICE, 'targetIsEmulator': True,
                  'manifestDebuggable': False, 'debugAssetAssociationAbsent': True,
                  'runAsDeniedForRelease': True, 'checks': result['checks'],
                  'originalEmulatorApkSha256': original_sha,
                  'scope': 'Dedicated real release probe with owned test signing; no production App distribution approval.'}
    finally:
        adb('shell', 'am', 'force-stop', PACKAGE)
        assert b'Success' in adb('install', '--no-streaming', '-t', '-r', str(restore)).stdout
        assert installed_hash() == hashlib.sha256(restore.read_bytes()).hexdigest()
    report['originalOwnedDebugApkRestored'] = True
    report['googleFidoDiagnosticActivityAbsent'] = True
    target=work / ('b6-release-boundary-result.json' if args.b6_owned_emulator else
                   'b3b4-release-boundary-result.json' if args.fixed_b3_b4 else 'b1b2-release-boundary-result.json')
    if args.fixed_b3_b4 or args.b6_owned_emulator:
        assert not target.exists(), 'Retain original current release proof'
    target.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: installed release native driver disabled and explicit development CA/RP rejected; owned debug APK restored')


if __name__ == '__main__':
    main()
