"""Build/run a bounded shell DEX; never installs an APK or changes accessibility settings."""
import argparse
import hashlib
import json
import re
import subprocess
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV = Path('D:/zewbbyTest/Hnuhole-env')
MATRIX = Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
CACHE = MATRIX / 'diagnostics/talkback-ultra-v1'
OWNER = 'HNUHOLE_PUBLIC_TALKBACK_DIAGNOSTIC_V1'
DEVICE = '10CEAG17RY003M7'
PACKAGE = 'org.hnuhole.hnuhole_mobile'
ADB = ENV / 'android-sdk/platform-tools/adb.exe'
JAVAC = ENV / 'windows/jdk-17.0.20.1+1/bin/javac.exe'
ANDROID_JAR = ENV / 'android-sdk/platforms/android-36/android.jar'
D8 = ENV / 'android-sdk/build-tools/36.0.0/d8.bat'
SOURCE = Path(__file__).with_name('AndroidTalkBackDiagnostic.java')
ARTIFACT = CACHE / 'diagnostic.jar'


def command(arguments, *, timeout=30):
    result = subprocess.run([str(value) for value in arguments], capture_output=True,
                            timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'Owned diagnostic command failed, exit={result.returncode}')
    return result.stdout.decode('utf-8', 'replace').strip()


def adb(*arguments):
    return command([ADB, '-s', DEVICE, *arguments])


def require_owner():
    assert (MATRIX / 'OWNER').read_text(encoding='utf-8').strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    CACHE.mkdir(parents=True, exist_ok=True)
    marker = CACHE / 'OWNER'
    if marker.exists():
        assert marker.read_text(encoding='utf-8').strip() == OWNER
    else:
        assert not any(CACHE.iterdir()), 'Do not take ownership of an existing cache'
        marker.write_text(OWNER + '\n', encoding='utf-8')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    require_owner()
    classes = CACHE / 'classes'
    dex = CACHE / 'dex'
    classes.mkdir(exist_ok=True)
    dex.mkdir(exist_ok=True)
    command([JAVAC, '-encoding', 'UTF-8', '-source', '8', '-target', '8',
             '-bootclasspath', ANDROID_JAR, '-d', classes, SOURCE], timeout=60)
    class_files = sorted(classes.rglob('*.class'))
    assert class_files
    command([D8, '--min-api', '35', '--lib', ANDROID_JAR, '--output', dex,
             *class_files], timeout=60)
    with zipfile.ZipFile(ARTIFACT, 'w', compression=zipfile.ZIP_STORED) as archive:
        archive.write(dex / 'classes.dex', 'classes.dex')
    evidence = {'result': 'BUILD_PASS', 'sourceSha256': digest(SOURCE),
                'dexSha256': digest(dex / 'classes.dex'), 'jarSha256': digest(ARTIFACT),
                'artifact': str(ARTIFACT), 'deviceExecution': 'NOT_RUN',
                'productApkChanged': False, 'settingsChanged': False}
    (CACHE / 'build.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(evidence))


def require_app(expected_pid):
    assert adb('shell', 'pidof', PACKAGE) == str(expected_pid), 'Owned App PID changed'
    # run-as is allowed only for a debuggable application. No private files read.
    assert adb('shell', 'run-as', PACKAGE, '/system/bin/id', '-u').isdigit()


def execute(args):
    require_owner()
    assert ARTIFACT.is_file(), 'Run build first'
    manifest = json.loads((CACHE / 'build.json').read_text(encoding='utf-8'))
    assert manifest['sourceSha256'] == digest(SOURCE), 'Source changed; rebuild first'
    assert manifest['jarSha256'] == digest(ARTIFACT), 'Owned DEX artifact changed'
    require_app(args.pid)
    remote = '/data/local/tmp/hnuhole-talkback-diagnostic-' + uuid.uuid4().hex
    remote_owner = remote + '/OWNER'
    remote_jar = remote + '/diagnostic.jar'
    created = False
    marked = False
    try:
        adb('shell', 'mkdir', remote)
        created = True
        adb('push', CACHE / 'OWNER', remote_owner)
        marked = True
        adb('push', ARTIFACT, remote_jar)
        require_app(args.pid)
        result = subprocess.run([str(ADB), '-s', DEVICE, 'shell',
                                 'CLASSPATH=' + remote_jar, 'app_process', '/system/bin',
                                 'AndroidTalkBackDiagnostic', args.action, str(args.pid),
                                 str(args.observe_seconds)], capture_output=True,
                                timeout=args.observe_seconds + 30)
        records = []
        for line in result.stdout.decode('utf-8', 'replace').splitlines():
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue  # Do not print unknown shell output or arbitrary UI text.
            if isinstance(value, dict) and value.get('diagnosticOnly') is True:
                records.append(value)
                print(json.dumps(value, ensure_ascii=False))
        if not records:
            failure = (result.stderr + result.stdout).decode('utf-8', 'replace')
            print(json.dumps({'record': 'host_launch_failure', 'diagnosticOnly': True,
                              'exitCode': result.returncode,
                              'exceptionClasses': sorted(set(re.findall(
                                  r'\b(?:java|android|org)\.[A-Za-z0-9_.$]*(?:Exception|Error)\b', failure))),
                              'shellNotFound': 'not found' in failure,
                              'shellPermissionDenied': 'Permission denied' in failure,
                              'unknownOutputEmitted': False}))
            raise RuntimeError('Shell diagnostic produced no safe JSON records')
        assert records[-1].get('record') == 'disconnected' and records[-1].get('disconnected') is True
        require_app(args.pid)
        assert result.returncode == 0, 'Shell diagnostic rejected this run; inspect safe error stage/class'
    finally:
        if marked:
            assert adb('shell', 'cat', remote_owner).strip() == OWNER
            adb('shell', 'rm', remote_jar, remote_owner)
        if created:
            adb('shell', 'rmdir', remote)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['build', 'inspect', 'inspect-public', 'focus-error'])
    parser.add_argument('--pid', type=int)
    parser.add_argument('--observe-seconds', type=int, choices=range(0, 11), default=2)
    args = parser.parse_args()
    if args.action == 'build':
        build()
    else:
        assert args.pid is not None and 10 <= args.pid <= 9999999
        execute(args)


if __name__ == '__main__':
    main()
