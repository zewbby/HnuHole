#!/usr/bin/env python3
"""Operate the owned debug-only Google FIDO probe; default prepare never opens UI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time

REPO = Path(__file__).resolve().parents[1]
HOST = Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
CACHE = HOST / 'google-direct-diagnostic'
ADB = 'D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe'
PHONE = '10CEAG17RY003M7'
LEGACY_PACKAGE = 'org.hnuhole.hnuhole_mobile.acceptance'
PACKAGE = LEGACY_PACKAGE
ACTIVITY = 'org.hnuhole.hnuhole_mobile.GoogleFidoDiagnosticActivity'
OWNER = 'HNUHOLE_GOOGLE_FIDO_DIAGNOSTIC_V1'
CERT = 'fd26b276cb170bf084a932d3b3919bd3aa44874395809968bdd74ddab87389dc'
BASE_APK = '7c0230c7df2cbcf1fc0074607bc621fe85395c3964308b092bc8e4f9df981f89'
MAIN_APK = 'ac66d81ffb760e17aca0770906b93c18b031bf8ffb9e0733974ef8b65abe5871'
IDENTITY_MODE = 'legacy'
ADMISSION = 'no_backup/google-fido-diagnostic-admission.json'
GOOGLE_REGISTRATION_ACTIVITY = 'com.google.android.gms/.auth.api.credentials.fido.registration.ui.RegistrationActivity'
DIAGNOSTIC_CORE = ('apps/mobile/android/app/src/debug/java/org/hnuhole/hnuhole_mobile/GoogleFidoDiagnosticActivity.java',
    'apps/mobile/android/app/src/debug/java/org/hnuhole/hnuhole_mobile/GoogleFidoDiagnosticPolicy.java',
    'apps/mobile/android/app/src/debug/AndroidManifest.xml',
    'apps/mobile/android/app/src/debug/res/values/passkey_associations.xml')
HOST_GUARD_SOURCES = ('tools/run-google-passkey-diagnostic.py', 'tools/tests/test_google_fido_diagnostic_runner.py')
HOST_TEST_COMMAND = ['python', '-m', 'unittest', 'discover', '-s', 'tools/tests', '-p', 'test_google_fido_diagnostic_runner.py', '-v']
REPORT_KEYS = {
    'schemaVersion', 'owner', 'runId', 'pid', 'phase', 'variant', 'applicationId',
    'apkSha256', 'prepareOnly', 'pendingIntentLaunched', 'keyguardSecure',
    'actualCSubmission', 'fixedCaseAcceptancePassed', 'stages',
    'uvPlatformAuthenticatorAvailable', 'stage', 'classification', 'finished',
    'nativeOutcomeUnknown',
}
STAGE_KEYS = {
    'stage', 'classification', 'pid', 'elapsedRealtimeMs', 'apiStatusCode',
    'exceptionClass', 'messageLength', 'messageSha256', 'errorEnum',
    'authenticatorErrorCode', 'activityResultCode', 'credentialResponsePresent',
}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def read_host_record(path, limit=4096):
    assert path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= limit
    value = read(path)
    assert isinstance(value, dict)
    return value


def configure_environment(args):
    """New-machine identities are explicit inputs, never taken from a manifest."""
    global HOST, CACHE, ADB, PHONE, PACKAGE, CERT, MAIN_APK, IDENTITY_MODE
    host, adb_path = Path(args.host), Path(args.adb)
    assert host.is_absolute() and adb_path.is_absolute() and adb_path.is_file()
    assert re.fullmatch(r'[A-Za-z0-9._:-]{1,128}', args.device)
    assert re.fullmatch(r'org\.hnuhole\.hnuhole_mobile\.acceptance(?:[0-9]{8})?', args.package)
    assert re.fullmatch(r'[a-f0-9]{64}', args.certificate_sha256)
    assert re.fullmatch(r'[a-f0-9]{64}', args.main_apk_sha256)
    HOST, CACHE = host, host / 'google-direct-diagnostic'
    ADB, PHONE, PACKAGE = str(adb_path), args.device, args.package
    CERT, MAIN_APK = args.certificate_sha256, args.main_apk_sha256
    IDENTITY_MODE = 'fresh' if PACKAGE != LEGACY_PACKAGE else 'legacy'


def write_new(path, value):
    assert not path.exists(), 'Preserve the original diagnostic record'
    with path.open('x', encoding='utf-8') as out:
        json.dump(value, out, ensure_ascii=False, indent=2)
        out.write('\n')
        out.flush()
        os.fsync(out.fileno())


class OperationLock:
    """OS-held lock is released even if the owned host process exits."""
    def __enter__(self):
        assert (HOST / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
        assert CACHE.resolve().is_relative_to(HOST.resolve()) and not CACHE.is_symlink()
        assert (CACHE / 'OWNER').read_text().strip() == OWNER
        path = CACHE / 'host-operation.lock'
        assert not path.is_symlink()
        self.file = path.open('a+b')
        try:
            # Reading byte zero before acquiring its Windows lock fails on overlap.
            if os.fstat(self.file.fileno()).st_size == 0:
                self.file.write(b'0')
                self.file.flush()
            self.file.seek(0)
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.file.close()
            raise RuntimeError('Another owned diagnostic operation is active')
        return self

    def __exit__(self, *unused):
        self.file.close()


def adb(*args, input_bytes=None, timeout=20):
    result = subprocess.run([ADB, '-s', PHONE, *args], input=input_bytes,
                            capture_output=True, timeout=timeout)
    assert result.returncode == 0, 'Owned device operation failed; no raw log exported'
    return result.stdout


def private_test(flag, path):
    """Only a clean exit-1 from toybox test establishes a negative result."""
    assert flag in ('-e', '-d', '-L')
    assert path == 'no_backup' or re.fullmatch(r'no_backup/google-fido-diagnostic-(?:admission|gfd-[a-f0-9]{32})\.json', path)
    result = subprocess.run([ADB, '-s', PHONE, 'shell', 'run-as', PACKAGE, 'test', flag, path],
                            capture_output=True, timeout=20)
    assert result.returncode in (0, 1) and result.stdout == b'' and result.stderr == b'', 'Private path probe failed; absence is not established'
    return result.returncode == 0


def ensure_private_directory():
    assert not private_test('-L', 'no_backup'), 'Preserve unexpected private directory symlink'
    if not private_test('-e', 'no_backup'):
        adb('shell', 'run-as', PACKAGE, 'mkdir', '-m', '700', 'no_backup')
    assert private_test('-d', 'no_backup') and not private_test('-L', 'no_backup'), 'Exact owned no_backup directory required'


def read_private(path):
    assert not private_test('-L', path), 'Private diagnostic file must not be a symlink'
    if not private_test('-e', path):
        return None
    return adb('shell', 'run-as', PACKAGE, 'cat', path)


def package_present(package):
    """An absent package is established by a successful, exact user-0 query."""
    raw = adb('shell', 'cmd', 'package', 'list', 'packages', '--user', '0', package).decode()
    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    assert all(re.fullmatch(r'package:[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+', line)
               for line in lines), 'Package enumeration failed; preserve device state'
    return 'package:' + package in lines


def installed_hash(package, allow_absent=False):
    if allow_absent and not package_present(package):
        return None
    path = adb('shell', 'pm', 'path', '--user', '0', package).decode().strip()
    assert re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk', path)
    return adb('shell', 'sha256sum', path[8:]).decode().split()[0]


def uid():
    value = adb('shell', 'cmd', 'package', 'list', 'packages', '-U', PACKAGE).decode()
    matches = [re.fullmatch(r'package:' + re.escape(PACKAGE) + r' uid:(\d+)', line.strip())
               for line in value.splitlines()]
    matches = [match for match in matches if match]
    assert len(matches) == 1, 'Exact owned package UID required'
    return int(matches[0][1])


def validate_host_guard_revision(manifest):
    """A derived host guard preserves every original APK/build assertion."""
    revision = manifest['hostGuardRevision']
    fields = {'schemaVersion', 'scope', 'baseManifestFile', 'baseManifestSha256',
        'originalLinuxManifestFile', 'originalLinuxManifestSha256',
        'changedSourceFilesSha256', 'validationFile', 'validationSha256'}
    assert set(revision) == fields and type(revision['schemaVersion']) is int and revision['schemaVersion'] == 1
    assert revision['scope'] == 'HOST_ONLY_NONCOMPILED_GUARD_REVISION'
    archived = {}
    for prefix in ('baseManifest', 'originalLinuxManifest', 'validation'):
        assert re.fullmatch(r'[A-Za-z0-9_-]+\.json', revision[prefix + 'File'])
        path = CACHE / revision[prefix + 'File']
        assert re.fullmatch(r'[a-f0-9]{64}', revision[prefix + 'Sha256']) and not path.is_symlink()
        assert sha256_file(path) == revision[prefix + 'Sha256']
        archived[prefix] = read_host_record(path, 65536)
    original = archived['baseManifest']
    assert 'hostGuardRevision' not in original, 'Preserve the original transferred build manifest'
    changes = revision['changedSourceFilesSha256']
    assert set(changes) == set(HOST_GUARD_SOURCES)
    assert set(manifest) == set(original) | {'hostGuardRevision'}
    assert set(manifest['sourceFilesSha256']) == set(original['sourceFilesSha256'])
    for key in original:
        if key != 'sourceFilesSha256':
            assert manifest[key] == original[key], 'Host revision must preserve APK/build identity, policy, staged sources and release claims'
    for source, digest in manifest['sourceFilesSha256'].items():
        if source in HOST_GUARD_SOURCES:
            assert digest == changes[source] == sha256_file(REPO / source)
        else:
            assert digest == original['sourceFilesSha256'][source], 'Only the two noncompiled host guard files may change'
    linux = archived['originalLinuxManifest']
    assert original['crossHostCopy']['sourceManifestSha256'] == revision['originalLinuxManifestSha256']
    assert linux['apkSha256'] == original['apkSha256']
    assert linux['sourceFilesSha256'] == original['sourceFilesSha256']
    validation = archived['validation']
    expected = {'schemaVersion', 'owner', 'scope', 'runnerSha256', 'testSourceSha256',
        'command', 'exitCode', 'testsPassed', 'result'}
    assert set(validation) == expected and type(validation['schemaVersion']) is int and validation['schemaVersion'] == 1
    assert validation['owner'] == OWNER and validation['scope'] == 'HOST_ONLY_NONCOMPILED_GUARD_VALIDATION'
    assert validation['runnerSha256'] == changes[HOST_GUARD_SOURCES[0]]
    assert validation['testSourceSha256'] == changes[HOST_GUARD_SOURCES[1]]
    assert validation['command'] == HOST_TEST_COMMAND and validation['result'] == 'PASS'
    assert type(validation['exitCode']) is int and validation['exitCode'] == 0
    assert type(validation['testsPassed']) is int and validation['testsPassed'] >= 24


def validate():
    assert (HOST / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    assert CACHE.resolve().is_relative_to(HOST.resolve()) and not CACHE.is_symlink()
    assert (CACHE / 'OWNER').read_text().strip() == OWNER
    manifest = read(CACHE / 'manifest.json')
    if 'hostGuardRevision' in manifest:
        validate_host_guard_revision(manifest)
    assert manifest['owner'] == OWNER and manifest['result'] == 'PASS'
    assert manifest['applicationId'] == PACKAGE and manifest['activity'] == ACTIVITY
    assert manifest['signingCertificateSha256'] == CERT and manifest['releaseExcluded'] is True
    if IDENTITY_MODE == 'fresh':
        assert manifest.get('identityMode') == 'fresh', 'Require explicitly built fresh identity'
    apk = Path(manifest['apkPath'])
    assert apk.resolve().is_relative_to(CACHE.resolve()) and not apk.is_symlink()
    assert sha256_file(apk) == manifest['apkSha256']
    assert manifest['sourceFilesSha256']
    for source, digest in manifest['sourceFilesSha256'].items():
        path = (REPO / source).resolve()
        assert path.is_relative_to(REPO) and path.is_file()
        assert sha256_file(path) == digest, 'Rebuild changed source'
    assert adb('get-state').strip() == b'device'
    assert installed_hash('org.hnuhole.hnuhole_mobile') == MAIN_APK
    if IDENTITY_MODE == 'fresh':
        assert installed_hash(LEGACY_PACKAGE) == BASE_APK, 'Preserve the original acceptance APK'
    current = installed_hash(PACKAGE, allow_absent=IDENTITY_MODE == 'fresh')
    allowed = (None, manifest['apkSha256']) if IDENTITY_MODE == 'fresh' else (BASE_APK, manifest['apkSha256'])
    assert current in allowed, 'Preserve unknown installed APK'
    return manifest, apk, current


def validate_report(report, run_id, manifest):
    required = REPORT_KEYS - {'uvPlatformAuthenticatorAvailable'}
    assert required <= set(report) <= REPORT_KEYS and type(report['schemaVersion']) is int and report['schemaVersion'] == 1
    assert report['runId'] == run_id and report['owner'] == OWNER and report['phase'] == 'ni-d02'
    assert report['variant'] == 'control' and report['applicationId'] == PACKAGE
    assert report['apkSha256'] == manifest['apkSha256']
    assert report['actualCSubmission'] is False and report['fixedCaseAcceptancePassed'] is False
    for key in ('prepareOnly', 'pendingIntentLaunched', 'keyguardSecure', 'finished', 'nativeOutcomeUnknown'):
        assert type(report[key]) is bool, 'Exact diagnostic boolean required'
    if 'uvPlatformAuthenticatorAvailable' in report:
        assert type(report['uvPlatformAuthenticatorAvailable']) is bool
    assert type(report['pid']) is int and report['pid'] > 0
    assert not (report['prepareOnly'] and report['pendingIntentLaunched'])
    assert report['pendingIntentLaunched'] or report['nativeOutcomeUnknown'] is False
    assert isinstance(report['stages'], list) and 1 <= len(report['stages']) <= 12
    for stage in report['stages']:
        assert {'stage', 'classification', 'pid', 'elapsedRealtimeMs'} <= set(stage) <= STAGE_KEYS
        assert stage['pid'] == report['pid'] and type(stage['elapsedRealtimeMs']) is int and stage['elapsedRealtimeMs'] >= 0
        for key, value in stage.items():
            assert value is None or (isinstance(value, (str, int, bool)) and len(str(value)) <= 180)
    last = report['stages'][-1]
    assert last['stage'] == report['stage'] and last['classification'] == report['classification']
    if report['pendingIntentLaunched'] and report['nativeOutcomeUnknown'] is False:
        assert report['finished'] is True, 'Only a decoded terminal native result resolves a launched run'
        if report['stage'] == 'REGISTER_UI_COMPLETED':
            assert last.get('credentialResponsePresent') is True and last.get('activityResultCode') == -1
        else:
            assert report['stage'] == 'REGISTER_UI_ERROR'
            assert isinstance(last.get('errorEnum'), str) and type(last.get('authenticatorErrorCode')) is int
    return report


def collect(run_id, manifest):
    raw = read_private(f'no_backup/google-fido-diagnostic-{run_id}.json')
    if raw is None:
        return None
    assert len(raw) < 20000
    report = json.loads(raw)
    return validate_report(report, run_id, manifest)


def record_prelaunch_abort(start, step, *, evidence_sha256=None, build_manifest_sha256=None,
                           historical_runner_sha256=None):
    """A separate host receipt never impersonates an Activity/native result."""
    assert step in ('ADMISSION_WRITE', 'ADMISSION_READBACK')
    run_id = start['runId']
    assert re.fullmatch(r'gfd-[a-f0-9]{32}', run_id)
    start_path = CACHE / (run_id + '-start.json')
    assert read_host_record(start_path) == start
    assert start['owner'] == OWNER and start['applicationId'] == PACKAGE
    assert start['signingCertificateSha256'] == CERT
    assert start['actualCSubmission'] is False and start['fixedCaseAcceptancePassed'] is False
    runner_sha = historical_runner_sha256 if evidence_sha256 else start['hostRunnerSha256']
    assert re.fullmatch(r'[a-f0-9]{64}', runner_sha)
    receipt = {'schemaVersion': 1, 'owner': OWNER, 'scope': 'HOST_PRE_LAUNCH_ABORT_ONLY',
        'result': 'ABORTED_BEFORE_AM_START', 'runId': run_id, 'applicationId': PACKAGE,
        'signingCertificateSha256': CERT, 'apkSha256': start['apkSha256'],
        'prepareOnly': start['prepareOnly'], 'nonceSha256': start['nonceSha256'],
        'startSha256': sha256_file(start_path), 'hostRunnerSha256': runner_sha,
        'failureStep': step, 'amStartInvoked': False, 'hostInvokedActivity': False,
        'actualCSubmission': False, 'fixedCaseAcceptancePassed': False,
        'evidenceSource': 'REVIEWED_HISTORICAL_HOST_FAILURE' if evidence_sha256 else 'HOST_CONTROL_FLOW_GUARD',
        'evidenceSha256': evidence_sha256, 'buildManifestSha256': build_manifest_sha256,
        'recordedAtUnix': int(time.time())}
    write_new(CACHE / (run_id + '-prelaunch-abort.json'), receipt)
    return receipt


def validate_prelaunch_abort(receipt, start):
    expected = {'schemaVersion', 'owner', 'scope', 'result', 'runId', 'applicationId',
        'signingCertificateSha256', 'apkSha256', 'prepareOnly', 'nonceSha256', 'startSha256',
        'hostRunnerSha256', 'failureStep', 'amStartInvoked', 'hostInvokedActivity',
        'actualCSubmission', 'fixedCaseAcceptancePassed', 'evidenceSource', 'evidenceSha256',
        'buildManifestSha256', 'recordedAtUnix'}
    assert set(receipt) == expected
    assert type(receipt['schemaVersion']) is int and receipt['schemaVersion'] == 1 and receipt['owner'] == OWNER
    assert receipt['scope'] == 'HOST_PRE_LAUNCH_ABORT_ONLY' and receipt['result'] == 'ABORTED_BEFORE_AM_START'
    for key in ('runId', 'applicationId', 'signingCertificateSha256', 'apkSha256', 'prepareOnly', 'nonceSha256'):
        assert receipt[key] == start[key]
    assert receipt['applicationId'] == PACKAGE and receipt['signingCertificateSha256'] == CERT
    assert type(receipt['prepareOnly']) is bool and type(start['prepareOnly']) is bool
    assert type(receipt['recordedAtUnix']) is int and receipt['recordedAtUnix'] >= 0
    for key in ('apkSha256', 'nonceSha256', 'startSha256', 'hostRunnerSha256'):
        assert re.fullmatch(r'[a-f0-9]{64}', receipt[key])
    assert receipt['startSha256'] == sha256_file(CACHE / (start['runId'] + '-start.json'))
    for key in ('amStartInvoked', 'hostInvokedActivity', 'actualCSubmission', 'fixedCaseAcceptancePassed'):
        assert receipt[key] is False
    assert receipt['failureStep'] in ('ADMISSION_WRITE', 'ADMISSION_READBACK')
    if receipt['evidenceSource'] == 'HOST_CONTROL_FLOW_GUARD':
        assert receipt['hostRunnerSha256'] == start['hostRunnerSha256']
        assert receipt['evidenceSha256'] is None and receipt['buildManifestSha256'] is None
    else:
        assert receipt['evidenceSource'] == 'REVIEWED_HISTORICAL_HOST_FAILURE'
        evidence_path = CACHE / (start['runId'] + '-host-prelaunch-evidence.json')
        assert not evidence_path.is_symlink() and sha256_file(evidence_path) == receipt['evidenceSha256']
        evidence = read_host_record(evidence_path)
        assert evidence['hostRunnerSha256'] == receipt['hostRunnerSha256']
        assert evidence['buildManifestSha256'] == receipt['buildManifestSha256']
        validate_historical_prelaunch_evidence(evidence, start)
    return receipt


def validate_historical_prelaunch_evidence(evidence, start):
    required = {'schemaVersion', 'owner', 'scope', 'runId', 'applicationId', 'signingCertificateSha256',
        'apkSha256', 'startSha256', 'hostRunnerSha256', 'failureStep', 'amStartInvoked',
        'failedCommand', 'buildManifestFile', 'buildManifestSha256'}
    assert set(evidence) == required and type(evidence['schemaVersion']) is int and evidence['schemaVersion'] == 1
    assert evidence['owner'] == OWNER and evidence['scope'] == 'REVIEWED_HOST_CONTROL_FLOW_FAILURE'
    for key in ('runId', 'applicationId', 'signingCertificateSha256', 'apkSha256'):
        assert evidence[key] == start[key]
    assert evidence['startSha256'] == sha256_file(CACHE / (start['runId'] + '-start.json'))
    assert evidence['amStartInvoked'] is False and evidence['failureStep'] == 'ADMISSION_WRITE'
    assert evidence['failedCommand'] == ['shell', 'run-as', PACKAGE, 'tee', ADMISSION]
    assert re.fullmatch(r'[A-Za-z0-9_-]+\.json', evidence['buildManifestFile'])
    build_path = CACHE / evidence['buildManifestFile']
    assert not build_path.is_symlink() and sha256_file(build_path) == evidence['buildManifestSha256']
    build = read_host_record(build_path, 65536)
    assert build['owner'] == OWNER and build['result'] == 'PASS'
    assert build['applicationId'] == PACKAGE and build['signingCertificateSha256'] == CERT
    assert build['apkSha256'] == start['apkSha256']
    assert build['sourceFilesSha256']['tools/run-google-passkey-diagnostic.py'] == evidence['hostRunnerSha256']
    return evidence


def reconcile_prelaunch_abort(run_id, evidence_sha256):
    assert run_id and re.fullmatch(r'gfd-[a-f0-9]{32}', run_id)
    assert evidence_sha256 and re.fullmatch(r'[a-f0-9]{64}', evidence_sha256)
    assert not (CACHE / (run_id + '-result.json')).exists(), 'Preserve actual Activity result'
    start = read_host_record(CACHE / (run_id + '-start.json'))
    evidence_path = CACHE / (run_id + '-host-prelaunch-evidence.json')
    assert not evidence_path.is_symlink() and sha256_file(evidence_path) == evidence_sha256
    evidence = validate_historical_prelaunch_evidence(read_host_record(evidence_path), start)
    receipt = record_prelaunch_abort(start, evidence['failureStep'], evidence_sha256=evidence_sha256,
        build_manifest_sha256=evidence['buildManifestSha256'], historical_runner_sha256=evidence['hostRunnerSha256'])
    validate_prelaunch_abort(receipt, start)
    print('RECORDED: exact reviewed host failure before am start; start retained, no device operation or acceptance result')


def validate_network_retry_evidence(evidence, start, result):
    required = {'schemaVersion', 'owner', 'scope', 'runId', 'applicationId', 'signingCertificateSha256',
        'apkSha256', 'startSha256', 'resultSha256', 'manifestFile', 'manifestSha256',
        'userRequestFile', 'userRequestSha256', 'networkChange', 'originalTaskIds', 'originalGoogleActivity', 'device'}
    assert set(evidence) == required and type(evidence['schemaVersion']) is int and evidence['schemaVersion'] == 1
    assert evidence['owner'] == OWNER and evidence['scope'] == 'USER_AUTHORIZED_DIAGNOSTIC_NETWORK_RETRY'
    assert IDENTITY_MODE == 'fresh' and evidence['device'] == PHONE
    for key in ('runId', 'applicationId', 'signingCertificateSha256', 'apkSha256'):
        assert evidence[key] == start[key]
    assert start['applicationId'] == PACKAGE and start['signingCertificateSha256'] == CERT
    assert start['owner'] == OWNER and start['identityMode'] == 'fresh'
    assert start['phase'] == 'ni-d02' and start['variant'] == 'control'
    assert start['prepareOnly'] is False and start['actualCSubmission'] is False and start['fixedCaseAcceptancePassed'] is False
    assert evidence['startSha256'] == sha256_file(CACHE / (start['runId'] + '-start.json'))
    assert evidence['resultSha256'] == sha256_file(CACHE / (start['runId'] + '-result.json'))
    assert evidence['networkChange'] == 'USER_ENABLED_VPN'
    assert evidence['originalGoogleActivity'] == GOOGLE_REGISTRATION_ACTIVITY
    assert isinstance(evidence['originalTaskIds'], list) and 1 <= len(evidence['originalTaskIds']) <= 4
    assert all(type(task) is int and task > 0 for task in evidence['originalTaskIds'])
    assert len(set(evidence['originalTaskIds'])) == len(evidence['originalTaskIds'])
    assert re.fullmatch(r'[A-Za-z0-9_-]+\.json', evidence['manifestFile'])
    manifest_path = CACHE / evidence['manifestFile']
    assert sha256_file(manifest_path) == evidence['manifestSha256']
    manifest = read_host_record(manifest_path, 65536)
    assert manifest['owner'] == OWNER and manifest['result'] == 'PASS'
    assert manifest['scope'] == 'FRESH_STANDALONE_DIAGNOSTIC_ONLY' and manifest['identityMode'] == 'fresh'
    assert manifest['actualCSubmission'] is False and manifest['fixedCaseAcceptancePassed'] is False
    assert manifest['applicationId'] == PACKAGE and manifest['signingCertificateSha256'] == CERT
    assert manifest['activity'] == ACTIVITY
    assert manifest['apkSha256'] == start['apkSha256']
    assert start['hostRunnerSha256'] == manifest['sourceFilesSha256']['tools/run-google-passkey-diagnostic.py'], 'Pin the original archived host revision that launched this exact run'
    for name in DIAGNOSTIC_CORE:
        assert sha256_file(REPO / name) == manifest['sourceFilesSha256'][name], 'Preserve exact original diagnostic APK core'
    assert re.fullmatch(r'[A-Za-z0-9_-]+\.txt', evidence['userRequestFile'])
    request_path = CACHE / evidence['userRequestFile']
    assert not request_path.is_symlink() and 0 < request_path.stat().st_size <= 2048
    assert sha256_file(request_path) == evidence['userRequestSha256']
    assert '你重试一下看行不行' in request_path.read_text(encoding='utf-8-sig'), 'Pin the direct human retry instruction'
    validate_report(result, start['runId'], manifest)
    assert result['finished'] is True and result['nativeOutcomeUnknown'] is True
    assert result['pendingIntentLaunched'] is True and result['prepareOnly'] is False
    assert result['stage'] == 'REGISTER_UI_STARTED_TIMEOUT' and result['classification'] == 'LOCAL_BOUNDED_TIMEOUT', 'Only the explicitly authorized bounded diagnostic timeout may retire'
    assert result['actualCSubmission'] is False and result['fixedCaseAcceptancePassed'] is False
    return manifest


def original_local_tasks_absent(snapshot, tasks):
    assert isinstance(snapshot, bytes) and 0 < len(snapshot) <= 1024 * 1024
    text = snapshot.decode('utf-8')
    assert 'ACTIVITY MANAGER ACTIVITIES' in text and ('Task{' in text or 'ActivityRecord{' in text), 'Valid bounded activity inventory required'
    assert not re.search(r'(?im)^\s*(?:error:|permission denial|exception|securityexception|can.t find service)', text), 'Failed task inventory cannot establish local termination'
    assert ACTIVITY not in text and 'GoogleFidoDiagnosticActivity' not in text, 'Original diagnostic Activity remains in local task state'
    assert 'auth.api.credentials.fido.registration.ui.RegistrationActivity' not in text, 'Google registration Activity remains in local task state'
    for task in tasks:
        assert not re.search(r'(?:#|taskId=|taskId:|task=)\s*' + str(task) + r'(?![0-9])', text), 'Original local task is still recorded'


def retire_diagnostic_only(run_id, evidence_sha256):
    """Explicit human authorization does not resolve an unknown native outcome."""
    assert run_id and re.fullmatch(r'gfd-[a-f0-9]{32}', run_id)
    assert evidence_sha256 and re.fullmatch(r'[a-f0-9]{64}', evidence_sha256)
    start = read_host_record(CACHE / (run_id + '-start.json'))
    result = read_host_record(CACHE / (run_id + '-result.json'), 20000)
    evidence_path = CACHE / (run_id + '-network-retry-evidence.json')
    assert sha256_file(evidence_path) == evidence_sha256
    evidence = read_host_record(evidence_path)
    manifest = validate_network_retry_evidence(evidence, start, result)
    assert adb('get-state').strip() == b'device'
    assert installed_hash(PACKAGE) == start['apkSha256'] and uid() == start['uid']
    assert installed_hash('org.hnuhole.hnuhole_mobile') == MAIN_APK == start['mainApkSha256']
    assert installed_hash(LEGACY_PACKAGE) == BASE_APK
    assert collect(run_id, manifest) == result, 'Preserve exact device-stored unknown result'
    assert read_private(ADMISSION) is None, 'Preserve a pending admission'
    snapshot = adb('shell', 'dumpsys', 'activity', 'activities')
    original_local_tasks_absent(snapshot, evidence['originalTaskIds'])
    receipt = {'schemaVersion': 1, 'owner': OWNER, 'scope': 'OPERATOR_RETIRED_DIAGNOSTIC_ONLY_UNKNOWN',
        'runId': run_id, 'applicationId': PACKAGE, 'signingCertificateSha256': CERT,
        'apkSha256': start['apkSha256'], 'startSha256': evidence['startSha256'],
        'resultSha256': evidence['resultSha256'], 'manifestSha256': evidence['manifestSha256'],
        'evidenceSha256': evidence_sha256, 'userRequestSha256': evidence['userRequestSha256'],
        'networkChange': evidence['networkChange'], 'originalTaskIds': evidence['originalTaskIds'],
        'localTaskSnapshotSha256': hashlib.sha256(snapshot).hexdigest(), 'originalLocalTasksAbsent': True,
        'historicalNativeOutcomeUnknown': True, 'credentialMayExist': True,
        'nativeOutcomeResolved': False, 'productUnknownChanged': False,
        'actualCSubmission': False, 'fixedCaseAcceptancePassed': False,
        'freshRetryBudget': 1, 'freshChallengeAndUserRequired': True,
        'hostRunnerSha256': sha256_file(Path(__file__)), 'recordedAtUnix': int(time.time())}
    write_new(CACHE / (run_id + '-diagnostic-retirement.json'), receipt)
    print('RETIRED_DIAGNOSTIC_ONLY: original native outcome remains UNKNOWN; one explicitly authorized fresh network retry, no C acceptance')
    return receipt


def validate_diagnostic_retirement(run_id, authorization_sha256):
    assert run_id and re.fullmatch(r'gfd-[a-f0-9]{32}', run_id)
    assert authorization_sha256 and re.fullmatch(r'[a-f0-9]{64}', authorization_sha256)
    path = CACHE / (run_id + '-diagnostic-retirement.json')
    assert sha256_file(path) == authorization_sha256
    receipt = read_host_record(path)
    expected = {'schemaVersion', 'owner', 'scope', 'runId', 'applicationId', 'signingCertificateSha256',
        'apkSha256', 'startSha256', 'resultSha256', 'manifestSha256', 'evidenceSha256',
        'userRequestSha256', 'networkChange', 'originalTaskIds', 'localTaskSnapshotSha256',
        'originalLocalTasksAbsent', 'historicalNativeOutcomeUnknown', 'credentialMayExist',
        'nativeOutcomeResolved', 'productUnknownChanged', 'actualCSubmission', 'fixedCaseAcceptancePassed',
        'freshRetryBudget', 'freshChallengeAndUserRequired', 'hostRunnerSha256', 'recordedAtUnix'}
    assert set(receipt) == expected and type(receipt['schemaVersion']) is int and receipt['schemaVersion'] == 1
    assert receipt['owner'] == OWNER and receipt['runId'] == run_id
    assert receipt['scope'] == 'OPERATOR_RETIRED_DIAGNOSTIC_ONLY_UNKNOWN'
    assert receipt['applicationId'] == PACKAGE and receipt['signingCertificateSha256'] == CERT
    assert type(receipt['recordedAtUnix']) is int and receipt['recordedAtUnix'] > 0
    for key in ('apkSha256', 'startSha256', 'resultSha256', 'manifestSha256', 'evidenceSha256',
                'userRequestSha256', 'localTaskSnapshotSha256', 'hostRunnerSha256'):
        assert re.fullmatch(r'[a-f0-9]{64}', receipt[key])
    assert receipt['hostRunnerSha256'] == sha256_file(Path(__file__)), 'Retirement is bound to the reviewed current host guard'
    for key in ('originalLocalTasksAbsent', 'historicalNativeOutcomeUnknown', 'credentialMayExist', 'freshChallengeAndUserRequired'):
        assert receipt[key] is True
    for key in ('nativeOutcomeResolved', 'productUnknownChanged', 'actualCSubmission', 'fixedCaseAcceptancePassed'):
        assert receipt[key] is False
    assert type(receipt['freshRetryBudget']) is int and receipt['freshRetryBudget'] == 1
    start = read_host_record(CACHE / (run_id + '-start.json'))
    result = read_host_record(CACHE / (run_id + '-result.json'), 20000)
    evidence_path = CACHE / (run_id + '-network-retry-evidence.json')
    assert sha256_file(evidence_path) == receipt['evidenceSha256']
    evidence = read_host_record(evidence_path)
    validate_network_retry_evidence(evidence, start, result)
    for key in ('apkSha256', 'startSha256', 'resultSha256', 'manifestSha256', 'userRequestSha256', 'networkChange', 'originalTaskIds'):
        assert receipt[key] == evidence[key]
    assert not (CACHE / (run_id + '-retry-reservation.json')).exists(), 'The one authorized fresh retry is already reserved'
    return receipt


def unresolved_runs():
    unresolved = []
    for path in CACHE.glob('gfd-*-start.json'):
        start = read(path)
        assert start['owner'] == OWNER and re.fullmatch(r'gfd-[0-9a-f]{32}', start['runId'])
        result_path = CACHE / (start['runId'] + '-result.json')
        if not result_path.exists():
            abort_path = CACHE / (start['runId'] + '-prelaunch-abort.json')
            if abort_path.exists():
                assert not abort_path.is_symlink()
                validate_prelaunch_abort(read_host_record(abort_path), start)
                continue
            unresolved.append(start['runId'])
            continue
        result = read(result_path)
        assert result['runId'] == start['runId'] and result['owner'] == OWNER
        assert result['apkSha256'] == start['apkSha256']
        if IDENTITY_MODE == 'fresh':
            assert start['applicationId'] == PACKAGE and start['signingCertificateSha256'] == CERT
        validate_report(result, start['runId'], start)
        assert result['prepareOnly'] is start['prepareOnly']
        if result.get('finished') is not True or result.get('nativeOutcomeUnknown') is not False:
            unresolved.append(start['runId'])
    return unresolved


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('preflight', 'update', 'prepare', 'launch', 'status', 'cleanup', 'reconcile-prelaunch-abort', 'retire-diagnostic-only'))
    parser.add_argument('--run-id')
    parser.add_argument('--evidence-sha256', help='Explicit reviewed historical host-prelaunch evidence file SHA-256')
    parser.add_argument('--retry-of', help='Exact retired standalone diagnostic run; a fresh run never replays its challenge')
    parser.add_argument('--authorization-sha256', help='Exact single-use diagnostic retirement receipt SHA-256')
    parser.add_argument('--host', default=str(HOST), help='Absolute owned Android matrix directory')
    parser.add_argument('--adb', default=ADB, help='Absolute existing adb executable')
    parser.add_argument('--device', default=PHONE, help='Exact authorized device serial')
    parser.add_argument('--package', default=PACKAGE, help='Exact owned acceptance package')
    parser.add_argument('--certificate-sha256', default=CERT, help='Explicit reviewed certificate SHA-256')
    parser.add_argument('--main-apk-sha256', default=MAIN_APK, help='Observed main APK baseline to preserve')
    return parser.parse_args(argv)


def run(args):
    if args.action == 'reconcile-prelaunch-abort':
        reconcile_prelaunch_abort(args.run_id, args.evidence_sha256)
        return
    if args.action == 'retire-diagnostic-only':
        retire_diagnostic_only(args.run_id, args.evidence_sha256)
        return
    manifest, apk, before = validate()
    retry_of = getattr(args, 'retry_of', None)
    authorization_sha256 = getattr(args, 'authorization_sha256', None)
    retirement = None
    if retry_of or authorization_sha256:
        assert retry_of and authorization_sha256 and args.action == 'launch', 'Retry authorization is only for one explicit fresh launch'
        retirement = validate_diagnostic_retirement(retry_of, authorization_sha256)
        assert manifest['scope'] == 'FRESH_STANDALONE_DIAGNOSTIC_ONLY' and manifest['apkSha256'] == retirement['apkSha256']
        original_local_tasks_absent(adb('shell', 'dumpsys', 'activity', 'activities'), retirement['originalTaskIds'])
        assert collect(retry_of, manifest) == read_host_record(CACHE / (retry_of + '-result.json'), 20000), 'Preserve current original native result before a fresh retry'
    if args.action in ('preflight', 'update', 'prepare', 'launch'):
        pending = unresolved_runs()
        assert not pending or (retirement is not None and pending == [retry_of]), 'Preserve unresolved diagnostic; inspect its exact result first'
    if args.action == 'preflight':
        print('READY: exact owned debug diagnostic APK/source/certificate; no device mutation')
        return
    if args.action == 'update':
        if before == manifest['apkSha256']:
            print('CURRENT: diagnostic already installed; no reinstall')
            return
        before_uid = None if before is None else uid()
        install_args = ['install', '--no-streaming', '-t']
        if before is not None:
            install_args.append('-r')
        result = adb(*install_args, str(apk), timeout=240)
        assert b'Success' in result, 'Update not installed; original data preserved'
        after_uid = uid()
        assert installed_hash(PACKAGE) == manifest['apkSha256']
        assert before_uid is None or after_uid == before_uid
        assert installed_hash('org.hnuhole.hnuhole_mobile') == MAIN_APK
        if IDENTITY_MODE == 'fresh':
            assert installed_hash(LEGACY_PACKAGE) == BASE_APK
        write_new(CACHE / ('update-' + manifest['apkSha256'][:12] + '.json'), {
            'owner': OWNER, 'scope': 'DIAGNOSTIC_INSTALL_ONLY_NOT_ACCEPTANCE', 'result': 'PASS',
            'device': PHONE, 'applicationId': PACKAGE, 'uidBefore': before_uid, 'uidAfter': after_uid,
            'previousApkSha256': before, 'apkSha256': manifest['apkSha256'],
            'mainApkSha256': MAIN_APK, 'uninstalled': False, 'clearedData': False,
            'identityMode': IDENTITY_MODE, 'freshInstall': before is None,
            'legacyAcceptanceApkSha256': BASE_APK if IDENTITY_MODE == 'fresh' else None,
        })
        print('PASS: owned diagnostic installed; existing UID/data and main APK preserved')
        return
    assert before == manifest['apkSha256'], 'Install reviewed diagnostic first'
    if args.action in ('status', 'cleanup'):
        assert args.run_id and re.fullmatch(r'gfd-[0-9a-f]{32}', args.run_id)
        report = collect(args.run_id, manifest)
        if report is None:
            print('PENDING: no admitted result yet')
            return
        start = read(CACHE / (args.run_id + '-start.json'))
        assert start['runId'] == args.run_id and start['owner'] == OWNER
        assert start['apkSha256'] == report['apkSha256']
        assert start['prepareOnly'] is report['prepareOnly']
        output = CACHE / (args.run_id + '-result.json')
        if report.get('finished') is True and not output.exists():
            write_new(output, report)
        if args.action == 'cleanup':
            assert report.get('finished') is True, 'Keep an active diagnostic'
            assert report.get('nativeOutcomeUnknown') is False, 'Preserve unresolved native result'
            raw = read_private(ADMISSION)
            if raw is not None:
                assert len(raw) <= 2048
                value = json.loads(raw)
                assert value['owner'] == OWNER and value['runId'] == args.run_id
                assert value['apkSha256'] == start['apkSha256']
                assert hashlib.sha256(value['nonce'].encode()).hexdigest() == start['nonceSha256']
                adb('shell', 'run-as', PACKAGE, 'rm', '-f', ADMISSION)
        print(json.dumps(report, ensure_ascii=False))
        return
    run_id = 'gfd-' + secrets.token_hex(16)
    nonce = secrets.token_hex(32)
    launch = args.action == 'launch'
    admission = dict(schemaVersion=1, owner=OWNER, phase='ni-d02', variant='control',
                     runId=run_id, nonce=nonce, apkSha256=manifest['apkSha256'],
                     launchPendingIntent=launch)
    ensure_private_directory()
    assert collect(run_id, manifest) is None
    assert not private_test('-L', ADMISSION), 'Preserve unexpected admission symlink'
    assert not private_test('-e', ADMISSION), 'Preserve any pending one-shot admission'
    start = {
        'owner': OWNER, 'runId': run_id, 'phase': 'ni-d02', 'variant': 'control',
        'applicationId': PACKAGE, 'signingCertificateSha256': CERT, 'identityMode': IDENTITY_MODE,
        'apkSha256': manifest['apkSha256'], 'mainApkSha256': MAIN_APK,
        'uid': uid(), 'prepareOnly': not launch, 'startedAtUnix': int(time.time()),
        'nonceSha256': hashlib.sha256(nonce.encode()).hexdigest(),
        'hostRunnerSha256': sha256_file(Path(__file__)),
        'actualCSubmission': False, 'fixedCaseAcceptancePassed': False,
    }
    if retirement is not None:
        # Re-read immediately before the irreversible one-use reservation. Earlier
        # checks must not allow a task/admission/native report that has reappeared.
        assert collect(retry_of, manifest) == read_host_record(CACHE / (retry_of + '-result.json'), 20000), 'Original device report changed before retry reservation'
        assert read_private(ADMISSION) is None, 'Preserve any admission before retry reservation'
        original_local_tasks_absent(adb('shell', 'dumpsys', 'activity', 'activities'), retirement['originalTaskIds'])
        reservation = {'schemaVersion': 1, 'owner': OWNER, 'scope': 'ONE_FRESH_DIAGNOSTIC_NETWORK_RETRY',
            'retiredRunId': retry_of, 'newRunId': run_id, 'authorizationSha256': authorization_sha256,
            'apkSha256': manifest['apkSha256'], 'freshChallengeAndUserRequired': True,
            'actualCSubmission': False, 'fixedCaseAcceptancePassed': False,
            'recordedAtUnix': int(time.time())}
        write_new(CACHE / (retry_of + '-retry-reservation.json'), reservation)
        start['retryOfRunId'] = retry_of
        start['retryAuthorizationSha256'] = authorization_sha256
    write_new(CACHE / (run_id + '-start.json'), start)
    step = 'ADMISSION_WRITE'
    try:
        adb('shell', 'run-as', PACKAGE, 'tee', ADMISSION,
            input_bytes=json.dumps(admission).encode())
        step = 'ADMISSION_READBACK'
        raw = read_private(ADMISSION)
        assert raw is not None and len(raw) <= 2048 and json.loads(raw) == admission, 'Exact private admission readback required'
    except Exception:
        record_prelaunch_abort(start, step)
        raise
    extras = ['--es', 'runId', run_id, '--es', 'nonce', nonce]
    if launch:
        extras += ['--ez', 'launchPendingIntent', 'true']
    adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/' + ACTIVITY, *extras)
    print('STARTED: ' + run_id + '; ' + ('EXPLICIT_GOOGLE_UI_DIAGNOSIS' if launch else 'PREPARE_ONLY_NO_AUTH_UI'), flush=True)
    previous = None
    deadline = time.monotonic() + (225 if launch else 75)
    while time.monotonic() < deadline:
        report = collect(run_id, manifest)
        if report and report != previous:
            previous = report
            print(json.dumps(report, ensure_ascii=False), flush=True)
        if report and report.get('finished') is True:
            write_new(CACHE / (run_id + '-result.json'), report)
            assert installed_hash('org.hnuhole.hnuhole_mobile') == MAIN_APK
            if IDENTITY_MODE == 'fresh':
                assert installed_hash(LEGACY_PACKAGE) == BASE_APK
            return
        time.sleep(2)
    print('BOUNDED_WAIT_ENDED: ' + run_id + '; retain original report and inspect status', flush=True)


if __name__ == '__main__':
    if not __debug__:
        raise RuntimeError('Run without Python optimization; admission checks are required')
    arguments = parse_args()
    configure_environment(arguments)
    with OperationLock():
        run(arguments)
