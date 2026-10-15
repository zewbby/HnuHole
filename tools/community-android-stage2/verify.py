#!/usr/bin/env python3
"""Verify/export owned APKs and source evidence without loading or calling ADB."""
import argparse
import hashlib
import json
import re
import shutil
import socket
import subprocess
import zipfile
from pathlib import Path

OWNER = 'HNUHOLE_COMMUNITY_ANDROID_STAGE2_V1'
PACKAGES = {'storage': 'org.hnuhole.hnuhole_mobile.communityf5.storage',
            'vault': 'org.hnuhole.communityf5.storage.vault.test',
            'passkey': 'org.hnuhole.communityf5.storage.passkey.test'}
PINNED = '0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ['work', 'repo', 'output', 'windows-output', 'build-tools', 'stage1-window']:
        parser.add_argument('--' + flag, required=True)
    args = parser.parse_args()
    work, repo, output, sdk, stage1 = (Path(v).resolve(strict=True) for v in (args.work, args.repo, args.output, args.build_tools, args.stage1_window))
    if (work / '.owner').read_text().strip() != OWNER or (output.parent / '.owner').read_text().strip() != OWNER:
        raise ValueError('owned work and output required')
    if (sdk.parents[2] / '.owner').read_text().strip() != 'community-android-stage1-20261014':
        raise ValueError('community-owned build tools required')
    if (stage1 / '.owner').read_text().strip() != 'HNUHOLE_COMMUNITY_ANDROID_STAGE1_V1':
        raise ValueError('task-1 source for public ADB files required')
    if (output / 'device-state.json').exists():
        raise ValueError('do not replace artifacts after a device run started')
    base = json.loads((repo / 'docs/design/community-android-stage1-source-fingerprint-20261015.json').read_text())
    entries = {f['path']: f['sha256'] for f in base['files']}
    for path, expected in entries.items():
        if sha((repo / path).read_bytes().replace(b'\r\n', b'\n')) != expected:
            raise ValueError('task-1 input changed: ' + path)
    new = ['apps/mobile/integration_test/community_android_storage_test.dart',
           'tools/community-android-stage2/build.sh', 'tools/community-android-stage2/phone.py',
           'tools/community-android-stage2/import-test-dependencies.py', 'tools/community-android-stage2/verify.py',
           'tools/tests/test_community_android_stage2_phone.py']
    entries.update({path: sha((repo / path).read_bytes().replace(b'\r\n', b'\n')) for path in new})
    files = [{'path': p, 'sha256': h} for p, h in sorted(entries.items())]
    fp = {'recordedOn': '2026-10-15', 'taskStartHEAD': 'd686d6582d74de1d0b578815d879be33d14b5695',
          'productSourceCommit': 'b5accf36b90e27829b6d039cd58a5b9c189a3da8',
          'fixedAuthenticationCommit': 'd859cb05c772cdf8d8b75e439a2bfedf0414dd46',
          'task1InputsUnchanged': True, 'task1InputCount': len(base['files']),
          'hashBasis': base['hashBasis'], 'aggregateRule': base['aggregateRule'],
          'fileCount': len(files), 'sha256': sha(json.dumps(files, ensure_ascii=False, separators=(',', ':')).encode()), 'files': files}
    mirror = work / 'source'
    compared = 0
    for item in files:
        path = item['path']
        if not path.startswith(('apps/mobile/', 'packages/auth_vault/', 'packages/auth_passkey/', 'packages/auth-protocol-vectors/', 'packages/post-protocol-vectors/')):
            continue
        expected = (repo / path).read_bytes().replace(b'\r\n', b'\n')
        if path == 'apps/mobile/android/app/build.gradle.kts':
            expected = expected.replace(b'applicationId = "org.hnuhole.hnuhole_mobile"', b'applicationId = "' + PACKAGES['storage'].encode() + b'"')
        elif path in ('packages/auth_vault/android/build.gradle.kts', 'packages/auth_passkey/android/build.gradle.kts'):
            name = 'vault' if 'auth_vault/' in path else 'passkey'
            previous = 'org.hnuhole.authvault.test' if name == 'vault' else 'org.hnuhole.authpasskey.test'
            expected = expected.replace(('testNamespace = "' + previous + '"').encode(), ('testNamespace = "' + PACKAGES[name] + '"').encode())
            expected = expected.replace(b'minSdk = 23', ('minSdk = 23\n        testApplicationId = "' + PACKAGES[name] + '"').encode())
        elif path == 'apps/mobile/android/build.gradle.kts' and (work / 'test-maven').is_dir():
            expected = expected.replace(b'repositories {', ('repositories {\n        maven { url = uri("' + str(work / 'test-maven') + '") }').encode(), 1)
        if (mirror / path).read_bytes().replace(b'\r\n', b'\n') != expected:
            raise ValueError('build mirror differs beyond explicit isolation overlays: ' + path)
        compared += 1
    rows = {}
    native = [
        ('vault', 'org/hnuhole/authvault/AndroidBusinessStorageTest', 7),
        ('vault', 'org/hnuhole/authvault/AndroidAuthVaultTest', 16),
        ('passkey', 'org/hnuhole/authpasskey/PasskeyCodecTest', 9),
        ('passkey', 'org/hnuhole/authpasskey/PasskeyAcceptanceErrorsTest', 3),
    ]
    for name, package in PACKAGES.items():
        apk = work / 'apks' / (name + '.apk')
        badging = subprocess.check_output([str(sdk / 'aapt'), 'dump', 'badging', str(apk)], text=True)
        if "package: name='" + package + "'" not in badging:
            raise ValueError('APK package mismatch')
        signature = subprocess.check_output([str(sdk / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
        certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([a-f0-9]{64})', signature).group(1)
        manifest = subprocess.check_output([str(sdk / 'aapt'), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'], text=True)
        if name != 'storage':
            if 'androidx.test.runner.AndroidJUnitRunner' not in manifest or 'android:targetPackage' not in manifest or manifest.count('"' + package + '"') < 2:
                raise ValueError('self-targeting isolated instrumentation runner mismatch')
        else:
            if "native-code: 'arm64-v8a'" not in badging or 'application-debuggable' not in badging:
                raise ValueError('owned Debug ARM64 app required')
            for attribute in ['allowBackup', 'fullBackupContent']:
                if not re.search(r'android:' + attribute + r'\([^\n]+\)=\(type 0x12\)0x0', manifest):
                    raise ValueError('product backup exclusion missing')
            rules = subprocess.check_output([str(sdk / 'aapt'), 'dump', 'xmltree', str(apk), 'res/xml/auth_data_extraction_rules.xml'], text=True)
            if rules.count('E: exclude') != 18:
                raise ValueError('compiled backup/transfer exclusions missing')
        with zipfile.ZipFile(apk) as archive:
            dex = b''.join(archive.read(p) for p in archive.namelist() if re.fullmatch(r'classes\d*\.dex', p))
            for module, test_class, count in native:
                if name != module:
                    continue
                if ('L' + test_class + ';').encode() not in dex:
                    raise ValueError('selected test class absent from DEX')
                directory = 'auth_vault' if module == 'vault' else 'auth_passkey'
                source = repo / 'packages' / directory / 'android/src/androidTest/kotlin' / (test_class + '.kt')
                if len(re.findall(r'@Test\s+fun\s+', source.read_text())) != count:
                    raise ValueError('native source count changed; update selection explicitly')
            if name == 'vault' and b'Lorg/hnuhole/authvault/AuthVaultProcessRestartTest;' not in dex:
                raise ValueError('cross-process auth probe absent')
            if name == 'storage':
                prefix = mirror / 'apps/mobile/build/app/intermediates'
                merged = prefix / 'merged_native_libs/debug/mergeDebugNativeLibs/out/lib/arm64-v8a/libsqlite3.so'
                stripped = prefix / 'stripped_native_libs/debug/stripDebugDebugSymbols/out/lib/arm64-v8a/libsqlite3.so'
                if sha(merged.read_bytes()) != PINNED or sha(archive.read('lib/arm64-v8a/libsqlite3.so')) != sha(stripped.read_bytes()):
                    raise ValueError('pinned SQLite/packaged ABI mismatch')
        shutil.copyfile(apk, output / apk.name)
        rows[name] = {'applicationId': package, 'sha256': sha(apk.read_bytes()), 'sizeBytes': apk.stat().st_size,
                      'certificateSha256': certificate, 'signatureVerified': True,
                      'path': args.windows_output.rstrip('/\\') + '/' + apk.name}
    certificates = {row['certificateSha256'] for row in rows.values()}
    stage1_manifest = json.loads((stage1 / 'manifest.json').read_text())
    stage1_proof = json.loads((stage1 / 'artifact-proof.json').read_text())
    if len(certificates) != 1 or certificates == {stage1_proof['apks']['acceptance']['certificateSha256']}:
        raise ValueError('one new task-2 signature distinct from task 1 required')
    adb_dir = output / 'adb'
    adb_dir.mkdir(exist_ok=True)
    for name, expected in stage1_manifest['adbFiles'].items():
        original = stage1 / 'adb' / name
        if sha(original.read_bytes()) != expected:
            raise ValueError('task-1 public ADB hash changed')
        shutil.copyfile(original, adb_dir / name)
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0)); port = listener.getsockname()[1]
    if port in (5037, stage1_manifest['adbServerPort']):
        raise ValueError('ADB port conflict; choose another unoccupied port')
    run = json.loads((work / 'build-config.json').read_text())['COMMUNITY_STORAGE_RUN_ID']
    manifest = {'owner': OWNER, 'runId': run, 'sourceFingerprint': fp['sha256'],
                'adb': args.windows_output.rstrip('/\\') + '/adb/adb.exe', 'adbFiles': stage1_manifest['adbFiles'],
                'adbServerPort': port, 'apks': rows, 'deviceWindowGranted': False, 'adbInvoked': False,
                'needsBackend': False, 'createsRealCredentials': False}
    proof = {'result': 'PASS_SOURCE_BUILD_MANIFEST_SIGNATURE_ONLY', 'sourceFingerprint': fp['sha256'],
             'comparedMirrorInputs': compared, 'task1All450InputsUnchanged': True,
             'overlays': ['app applicationId', 'two testNamespace/testApplicationId pairs', 'owned local public Maven repository'],
             'apks': rows, 'nativeSuiteSourceCounts': [7, 16, 9, 3], 'nativeSuiteDeviceResult': 'NOT_RUN',
             'newDebugCertificateDistinctFromTask1': True, 'productBackupAndTransferExclusionsCompiled': True,
             'sqlitePinnedInputSha256': PINNED, 'adbInvoked': False, 'deviceUsed': False,
             'sharedSdkInvoked': False, 'task1SdkCacheReusedSequentially': True, 'databasesUsed': False}
    for path, value in [(output / 'manifest.json', manifest), (output / 'artifact-proof.json', proof),
                        (repo / 'docs/design/community-android-stage2-source-fingerprint-20261015.json', fp)]:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    (output / '.owner').write_text(OWNER)
    home = output / 'adb-home'; home.mkdir(exist_ok=True); (home / '.owner').write_text(OWNER)
    print(json.dumps({'result': proof['result'], 'sourceFiles': len(files), 'mirrorInputs': compared,
                      'apkCount': len(rows), 'nativeDeviceTests': 'NOT_RUN', 'adbInvoked': False}))


if __name__ == '__main__':
    main()
