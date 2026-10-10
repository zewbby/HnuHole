"""Observe this owned debug APK's onError callback without changing its result.

No heap enumeration, target method invocation, authentication, or raw messages.
Run only during an explicitly requested diagnostic ceremony, before its callback.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

REPO = Path(__file__).resolve().parents[2]
HOST = Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
ADB = 'D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe'
PHONE = '10CEAG17RY003M7'
PACKAGE = 'org.hnuhole.hnuhole_mobile.acceptance'
SOURCE = Path(__file__).with_name('NativeCallbackError.java')
CACHE = HOST / 'diagnostics/passkey-callback'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pid', type=int)
    p.add_argument('--compile-only', action='store_true')
    a = p.parse_args()
    assert (HOST / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    assert HOST.resolve() == HOST.resolve(strict=True) and not HOST.is_symlink()
    CACHE.mkdir(parents=True, exist_ok=True)
    assert not CACHE.is_symlink() and CACHE.resolve().is_relative_to(HOST.resolve())
    subprocess.run(['javac', '-d', str(CACHE), str(SOURCE)], check=True,
                   capture_output=True, timeout=30)
    if a.compile_only:
        print('PASS: callback observer compiles; no device operation performed')
        return
    assert a.pid and a.pid > 0

    def adb(*args):
        r = subprocess.run([ADB, '-s', PHONE, *args], capture_output=True,
                           text=True, encoding='utf-8', errors='replace', timeout=15)
        assert r.returncode == 0, 'Owned debug device operation failed'
        return r.stdout.strip()

    assert adb('shell', 'pidof', PACKAGE) == str(a.pid)
    manifest = json.loads((HOST / 'b3b4-evidence/builds.json').read_text())
    entry = next(x for x in manifest['apks'] if x['fileName'] == 'b3b4-acceptance.apk'
                 and x['applicationId'] == PACKAGE)
    installed = adb('shell', 'pm', 'path', PACKAGE)
    assert re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk', installed)
    assert adb('shell', 'sha256sum', installed[8:]).split()[0] == entry['apkSha256']
    out = HOST / f'b3b4-evidence/native-callback-{a.pid}.json'
    assert not out.exists(), 'Preserve the original diagnostic record'
    port = adb('forward', 'tcp:0', 'jdwp:' + str(a.pid))
    assert port.isdecimal()
    lines = []
    process = None
    try:
        process = subprocess.Popen(['java', '-cp', str(CACHE), 'NativeCallbackError', port],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            encoding='utf-8', errors='replace', cwd=REPO)
        try:
            for line in process.stdout:
                line = line.strip()
                assert len(lines) < 100 and len(line) < 2000, 'Bounded callback diagnostics required'
                lines.append(line)
                print(line, flush=True)
            assert process.wait(timeout=10) == 0, 'Callback observer failed'
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
        out.write_text(json.dumps({
            'scope': 'OWNED_CALLBACK_ERROR_DIAGNOSIS_ONLY_NOT_FUNCTIONAL_ACCEPTANCE',
            'pid': a.pid, 'apkSha256': entry['apkSha256'],
            'observerSha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
            'boundedDiagnostics': lines, 'rawMessagesStored': False,
            'rawProofStored': False, 'credentialsInspected': False,
            'heapEnumerated': False, 'targetMethodsInvoked': False,
            'originalCallbackModified': False,
        }, indent=2) + '\n')
    finally:
        adb('forward', '--remove', 'tcp:' + port)


if __name__ == '__main__':
    main()
