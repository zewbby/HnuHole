#!/usr/bin/env python3
"""Verify owned unconfigured APKs and prepare a signature-only negative control."""
import argparse
import hashlib
import io
import json
import re
import shutil
import subprocess
import tarfile
import zipfile
from pathlib import Path

OWNER = 'HNUHOLE_COMMUNITY_ANDROID_STAGE3_V1'
PACKAGE = 'org.hnuhole.hnuhole_mobile.communityf5.passkey'


def sha(data): return hashlib.sha256(data).hexdigest()


def payload(apk):
    with zipfile.ZipFile(apk) as archive:
        return {n: sha(archive.read(n)) for n in archive.namelist()
                if not re.fullmatch(r'META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC)|SIG-[^/]+)', n, re.I)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['work', 'repo', 'output', 'build-tools', 'jdk']:
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--source-commit', required=True)
    args = parser.parse_args()
    work, repo, output, sdk, jdk = (p.resolve(strict=True) for p in (args.work, args.repo, args.output, args.build_tools, args.jdk))
    if (work / '.owner').read_text().strip() != OWNER or (output.parent / '.owner').read_text().strip() != OWNER:
        raise ValueError('owned work/output required')
    if (sdk.parents[2] / '.owner').read_text().strip() != 'community-android-stage1-20261014' or jdk.parent != sdk.parents[2]:
        raise ValueError('community-owned SDK and JDK only')
    fp = json.loads((repo / 'docs/design/community-android-stage2-source-fingerprint-20261015.json').read_text())
    if not re.fullmatch(r'[a-f0-9]{40}', args.source_commit):
        raise ValueError('fixed committed source SHA required')
    # Cross-host drvfs ownership differs. Scope this read-only Git exception to
    # the explicitly selected task repo/command; never edit global Git config.
    snapshot = tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git', '-c', 'safe.directory=' + str(repo), 'archive', args.source_commit], cwd=repo)), mode='r:')
    compared = 0
    changed = []
    phone_paths = {'tools/community-android-stage1/phone.py', 'tools/community-android-stage2/phone.py',
                   'tools/tests/test_community_android_stage1_phone.py', 'tools/tests/test_community_android_stage2_phone.py'}
    for item in fp['files']:
        path = item['path']
        member = snapshot.getmember(path)
        committed = member.linkname.encode() if member.issym() else snapshot.extractfile(member).read()
        # A parallel phone task owns these files. Inspect only the explicitly
        # committed snapshot, never its live uncommitted USB/key changes.
        original = committed.replace(b'\r\n', b'\n') if path in phone_paths else (repo / path).read_bytes().replace(b'\r\n', b'\n')
        if original != committed.replace(b'\r\n', b'\n'):
            raise ValueError('source differs from selected committed snapshot: ' + path)
        if sha(original) != item['sha256']: changed.append(path)
        if path.startswith(('apps/mobile/', 'packages/auth_vault/', 'packages/auth_passkey/', 'packages/auth-protocol-vectors/', 'packages/post-protocol-vectors/')):
            expected = original
            if path == 'apps/mobile/android/app/build.gradle.kts':
                expected = expected.replace(b'applicationId = "org.hnuhole.hnuhole_mobile"', ('applicationId = "' + PACKAGE + '.unassociated"').encode())
            if (work / 'source' / path).read_bytes().replace(b'\r\n', b'\n') != expected:
                raise ValueError('unexpected mirror overlay: ' + path)
            compared += 1
    apks = work / 'apks'
    control, missing, negative = [apks / name for name in ['control-unconfigured.apk', 'unassociated-unconfigured.apk', 'bad-signature-unconfigured.apk']]
    private = work / 'signing-negative'
    if not negative.exists():
        if private.exists():
            raise ValueError('partial negative-signature preparation exists; inspect before retry')
        private.mkdir(mode=0o700)
        subprocess.run([str(jdk / 'bin/keytool'), '-genkeypair', '-keystore', str(private / 'negative.jks'),
                        '-storepass', 'android', '-keypass', 'android', '-alias', 'negative', '-dname', 'CN=HnuHole Community Task3 Synthetic Negative',
                        '-keyalg', 'RSA', '-keysize', '2048', '-validity', '365'], check=True, capture_output=True)
        subprocess.run([str(sdk / 'apksigner'), 'sign', '--ks', str(private / 'negative.jks'), '--ks-key-alias', 'negative',
                        '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', str(negative), str(control)], check=True, capture_output=True)
    original_payload, changed_payload = payload(control), payload(negative)
    if original_payload != changed_payload:
        raise ValueError('negative APK differs beyond signing bytes')
    rows = {}
    for name, apk, package in [('control', control, PACKAGE), ('unassociated', missing, PACKAGE + '.unassociated'), ('badSignature', negative, PACKAGE)]:
        badging = subprocess.check_output([str(sdk / 'aapt'), 'dump', 'badging', str(apk)], text=True)
        if "package: name='" + package + "'" not in badging or "native-code: 'arm64-v8a'" not in badging or 'application-debuggable' not in badging:
            raise ValueError('Debug ARM64 package mismatch')
        verification = subprocess.check_output([str(sdk / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
        certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})', verification).group(1)
        with zipfile.ZipFile(apk) as archive:
            prefix = work / 'source/apps/mobile/build/app/intermediates'
            merged = prefix / 'merged_native_libs/debug/mergeDebugNativeLibs/out/lib/arm64-v8a/libsqlite3.so'
            stripped = prefix / 'stripped_native_libs/debug/stripDebugDebugSymbols/out/lib/arm64-v8a/libsqlite3.so'
            if sha(merged.read_bytes()) != '0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161' or sha(archive.read('lib/arm64-v8a/libsqlite3.so')) != sha(stripped.read_bytes()):
                raise ValueError('pinned SQLite mismatch')
        shutil.copyfile(apk, output / apk.name)
        rows[name] = {'applicationId': package, 'certificateSha256': certificate,
                      'sha256': sha(apk.read_bytes()), 'sizeBytes': apk.stat().st_size,
                      'signatureVerified': True, 'deviceReady': False}
    if rows['control']['certificateSha256'] != rows['unassociated']['certificateSha256'] or rows['control']['certificateSha256'] == rows['badSignature']['certificateSha256']:
        raise ValueError('contrast signatures mismatch')
    for path in [repo.parent / 'stage1-preparation-20261014/device-window/artifact-proof.json', repo.parent / 'stage2-preparation-20261015/device-window/artifact-proof.json']:
        previous = json.loads(path.read_text())
        if rows['control']['certificateSha256'] in {v['certificateSha256'] for v in previous['apks'].values()}:
            raise ValueError('task3 signing identity must be new')
    if set(changed) != phone_paths:
        raise ValueError('review any new parallel changes before updating source baseline')
    report = {'owner': OWNER, 'sourceCommit': args.source_commit,
              'productSourceCommit': 'b5accf36b90e27829b6d039cd58a5b9c189a3da8',
              'result': 'PASS_UNCONFIGURED_BUILD_AND_SIGNATURE_CONTRAST_ONLY',
              'apks': rows, 'badSignaturePayloadEqualsControl': True, 'comparedNonSignatureEntries': len(original_payload),
              'task1And2InputsUnchanged': 452, 'parallelGuardCommit': 'e0c128033682923d519ea99546d72503b085a99e',
              'parallelGuardFilesChangedSinceTask2': changed, 'mirrorInputsCompared': compared,
              'phoneGuardInputsReadFromCommittedSnapshotOnly': True,
              'mirrorOverlay': 'applicationId only; no RP, trust or association config applied',
              'associationApplied': False, 'inheritsHistoricalDebugResourceOnly': True,
              'newTask3DebugSigningCertificate': True, 'needsApprovedRPAndOwnFreshLabRebuild': True,
              'systemPasskeyPositiveResult': 'NOT_RUN', 'deviceUsed': False, 'adbInvoked': False,
              'globalConfigurationChanged': False, 'sharedSdkInvoked': False}
    (output / 'baseline-proof.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'result': report['result'], 'comparedNonSignatureEntries': len(original_payload), 'mirrorInputs': compared, 'deviceUsed': False}))


if __name__ == '__main__':
    main()
