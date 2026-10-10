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
PACKAGE = 'org.hnuhole.hnuhole_mobile.acceptance'
ACTIVITY = 'org.hnuhole.hnuhole_mobile.GoogleFidoDiagnosticActivity'
OWNER = 'HNUHOLE_GOOGLE_FIDO_DIAGNOSTIC_V1'
CERT = 'fd26b276cb170bf084a932d3b3919bd3aa44874395809968bdd74ddab87389dc'
BASE_APK = '7c0230c7df2cbcf1fc0074607bc621fe85395c3964308b092bc8e4f9df981f89'
MAIN_APK = 'ac66d81ffb760e17aca0770906b93c18b031bf8ffb9e0733974ef8b65abe5871'
ADMISSION = 'no_backup/google-fido-diagnostic-admission.json'
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
        self.file.seek(0)
        if not self.file.read(1):
            self.file.write(b'0')
            self.file.flush()
        self.file.seek(0)
        try:
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


def adb(*args, input_bytes=None, timeout=20, allow_missing=False):
    result = subprocess.run([ADB, '-s', PHONE, *args], input=input_bytes,
                            capture_output=True, timeout=timeout)
    if allow_missing and result.returncode != 0:
        return None
    assert result.returncode == 0, 'Owned device operation failed; no raw log exported'
    return result.stdout


def installed_hash(package):
    path = adb('shell', 'pm', 'path', package).decode().strip()
    assert re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk', path)
    return adb('shell', 'sha256sum', path[8:]).decode().split()[0]


def uid():
    value = adb('shell', 'cmd', 'package', 'list', 'packages', '-U', PACKAGE).decode()
    matches = [re.fullmatch(r'package:' + re.escape(PACKAGE) + r' uid:(\d+)', line.strip())
               for line in value.splitlines()]
    matches = [match for match in matches if match]
    assert len(matches) == 1, 'Exact owned package UID required'
    return int(matches[0][1])


def validate():
    assert (HOST / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    assert CACHE.resolve().is_relative_to(HOST.resolve()) and not CACHE.is_symlink()
    assert (CACHE / 'OWNER').read_text().strip() == OWNER
    manifest = read(CACHE / 'manifest.json')
    assert manifest['owner'] == OWNER and manifest['result'] == 'PASS'
    assert manifest['applicationId'] == PACKAGE and manifest['activity'] == ACTIVITY
    assert manifest['signingCertificateSha256'] == CERT and manifest['releaseExcluded']
    apk = Path(manifest['apkPath'])
    assert apk.resolve().is_relative_to(CACHE.resolve()) and not apk.is_symlink()
    assert hashlib.sha256(apk.read_bytes()).hexdigest() == manifest['apkSha256']
    assert manifest['sourceFilesSha256']
    for source, digest in manifest['sourceFilesSha256'].items():
        path = (REPO / source).resolve()
        assert path.is_relative_to(REPO) and path.is_file()
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, 'Rebuild changed source'
    assert adb('get-state').strip() == b'device'
    assert installed_hash('org.hnuhole.hnuhole_mobile') == MAIN_APK
    current = installed_hash(PACKAGE)
    assert current in (BASE_APK, manifest['apkSha256']), 'Preserve unknown installed APK'
    return manifest, apk, current


def collect(run_id, manifest):
    raw = adb('shell', 'run-as', PACKAGE, 'cat',
              f'no_backup/google-fido-diagnostic-{run_id}.json', allow_missing=True)
    if raw is None:
        return None
    assert len(raw) < 20000
    report = json.loads(raw)
    assert set(report) <= REPORT_KEYS and report['runId'] == run_id
    assert report['owner'] == OWNER and report['phase'] == 'ni-d02'
    assert report['variant'] == 'control' and report['applicationId'] == PACKAGE
    assert report['apkSha256'] == manifest['apkSha256']
    assert report['actualCSubmission'] is False and report['fixedCaseAcceptancePassed'] is False
    assert isinstance(report['stages'], list) and len(report['stages']) <= 12
    for stage in report['stages']:
        assert set(stage) <= STAGE_KEYS
        for key, value in stage.items():
            assert value is None or (isinstance(value, (str, int, bool)) and len(str(value)) <= 180)
    return report


def unresolved_runs():
    unresolved = []
    for path in CACHE.glob('gfd-*-start.json'):
        start = read(path)
        assert start['owner'] == OWNER and re.fullmatch(r'gfd-[0-9a-f]{32}', start['runId'])
        result_path = CACHE / (start['runId'] + '-result.json')
        if not result_path.exists():
            unresolved.append(start['runId'])
            continue
        result = read(result_path)
        assert result['runId'] == start['runId'] and result['owner'] == OWNER
        assert result['apkSha256'] == start['apkSha256']
        if result.get('finished') is not True or result.get('nativeOutcomeUnknown') is not False:
            unresolved.append(start['runId'])
    return unresolved


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('preflight', 'update', 'prepare', 'launch', 'status', 'cleanup'))
    parser.add_argument('--run-id')
    args = parser.parse_args()
    manifest, apk, before = validate()
    if args.action in ('preflight', 'update', 'prepare', 'launch'):
        assert not unresolved_runs(), 'Preserve unresolved diagnostic; inspect its exact result first'
    if args.action == 'preflight':
        print('READY: exact owned debug diagnostic APK/source/certificate; no device mutation')
        return
    if args.action == 'update':
        if before == manifest['apkSha256']:
            print('CURRENT: diagnostic already installed; no reinstall')
            return
        before_uid = uid()
        result = adb('install', '--no-streaming', '-t', '-r', str(apk), timeout=240)
        assert b'Success' in result, 'Update not installed; original data preserved'
        assert installed_hash(PACKAGE) == manifest['apkSha256'] and uid() == before_uid
        assert installed_hash('org.hnuhole.hnuhole_mobile') == MAIN_APK
        write_new(CACHE / ('update-' + manifest['apkSha256'][:12] + '.json'), {
            'owner': OWNER, 'scope': 'DIAGNOSTIC_INSTALL_ONLY_NOT_ACCEPTANCE', 'result': 'PASS',
            'device': PHONE, 'applicationId': PACKAGE, 'uidBefore': before_uid, 'uidAfter': uid(),
            'previousApkSha256': before, 'apkSha256': manifest['apkSha256'],
            'mainApkSha256': MAIN_APK, 'uninstalled': False, 'clearedData': False,
        })
        print('PASS: same-signature diagnostic update; UID/data and main APK preserved')
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
        output = CACHE / (args.run_id + '-result.json')
        if report.get('finished') is True and not output.exists():
            write_new(output, report)
        if args.action == 'cleanup':
            assert report.get('finished') is True, 'Keep an active diagnostic'
            assert report.get('nativeOutcomeUnknown') is False, 'Preserve unresolved native result'
            raw = adb('shell', 'run-as', PACKAGE, 'cat', ADMISSION, allow_missing=True)
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
    assert collect(run_id, manifest) is None
    existing = adb('shell', 'run-as', PACKAGE, 'test', '-e', ADMISSION, allow_missing=True)
    assert existing is None, 'Preserve any pending one-shot admission'
    write_new(CACHE / (run_id + '-start.json'), {
        'owner': OWNER, 'runId': run_id, 'phase': 'ni-d02', 'variant': 'control',
        'apkSha256': manifest['apkSha256'], 'mainApkSha256': MAIN_APK,
        'uid': uid(), 'prepareOnly': not launch, 'startedAtUnix': int(time.time()),
        'nonceSha256': hashlib.sha256(nonce.encode()).hexdigest(),
        'actualCSubmission': False, 'fixedCaseAcceptancePassed': False,
    })
    adb('shell', 'run-as', PACKAGE, 'tee', ADMISSION,
        input_bytes=json.dumps(admission).encode())
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
            return
        time.sleep(2)
    print('BOUNDED_WAIT_ENDED: ' + run_id + '; retain original report and inspect status', flush=True)


if __name__ == '__main__':
    if not __debug__:
        raise RuntimeError('Run without Python optimization; admission checks are required')
    with OperationLock():
        run()
