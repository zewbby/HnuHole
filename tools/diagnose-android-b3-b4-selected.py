#!/usr/bin/env python3
"""One owned live-debug diagnosis; no acceptance claim or proof export."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import urllib.parse
import urllib.request

ROOT = Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
ADB = Path('D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe')
PHONE = '10CEAG17RY003M7'
PACKAGE = 'org.hnuhole.hnuhole_mobile'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare-attach', 'start', 'collect', 'end-attach'))
    args = parser.parse_args()
    assert ROOT.resolve() == ROOT.resolve(strict=True) and not ROOT.is_symlink()
    assert (ROOT/'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    evidence = ROOT/'b3b4-evidence'
    record = evidence/'v14-selected-response-diagnosis.json'
    attachment = evidence/'selected-vm-endpoint.private.json'

    def adb(*parts):
        r = subprocess.run([str(ADB), '-s', PHONE, *parts], capture_output=True,
                           text=True, encoding='utf-8', errors='replace', timeout=25)
        assert r.returncode == 0, 'Owned diagnostic command failed; private output not exported'
        return r.stdout.strip()

    if args.action == 'end-attach':
        value = json.loads(attachment.read_text())
        assert value['package'] == PACKAGE and value['port'].isdecimal()
        adb('forward', '--remove', 'tcp:'+value['port'])
        attachment.unlink()
        print('ENDED: only the diagnostic forwarding removed')
        return
    current_pid = int(adb('shell', 'pidof', PACKAGE))
    native = json.loads(adb('shell', 'run-as', PACKAGE, 'cat',
                            'files/owned-acceptance-passkey.json'))
    assert native['pid'] == current_pid
    if args.action == 'collect':
        value = json.loads(record.read_text())
        assert value['pid'] == current_pid
        value['nativeAfter'] = native
        value['diagnosisCompleted'] = sum(native.get(k, 0) for k in (
            'nativeSucceeded', 'nativeErrored', 'nativeCancelled')) > sum(
            value['nativeBefore'].get(k, 0) for k in (
                'nativeSucceeded', 'nativeErrored', 'nativeCancelled'))
        record.write_text(json.dumps(value, indent=2)+'\n')
        print(json.dumps(value))
        return
    assert not record.exists(), 'Keep the original diagnosis before any new attempt'
    version = json.loads((evidence/'ni-d05-main-version.json').read_text(encoding='utf-8-sig'))
    assert version['applicationId'] == PACKAGE
    installed = adb('shell', 'pm', 'path', PACKAGE)
    path = re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)', installed)
    assert path and adb('shell', 'sha256sum', path[1]).split()[0] == version['apkSha256']
    assert sum(native.get(k, 0) for k in ('nativeSucceeded', 'nativeErrored', 'nativeCancelled')) == native.get('nativeBegun', 0)
    # Read only this owned process's VM endpoint, keep its token in memory.
    private_log = adb('logcat', '-d', '--pid='+str(current_pid), '-s', 'flutter:I', '*:S')
    matches = re.findall(r'Dart VM service is listening on (http://127\.0\.0\.1:\d+/[A-Za-z0-9_=-]+/)', private_log)
    assert matches, 'Owned live VM endpoint unavailable; no restart or authentication replay'
    remote = urllib.parse.urlparse(matches[-1])
    port = adb('forward', 'tcp:0', 'tcp:'+str(remote.port))
    assert port.isdecimal()
    endpoint = 'http://127.0.0.1:'+port+remote.path
    if args.action == 'prepare-attach':
        assert not attachment.exists()
        attachment.write_text(json.dumps(dict(package=PACKAGE, pid=current_pid, port=port, endpoint=endpoint)))
        print('PREPARED: owned debugger forwarding; token stays private')
        return

    def rpc(method, **parameters):
        with urllib.request.urlopen(endpoint+method+'?'+urllib.parse.urlencode(parameters), timeout=25) as response:
            value = json.load(response)
        if 'error' in value:
            # Compiler diagnostics for our fixed expression, not App objects.
            (evidence/'selected-vm-compile.private.json').write_text(json.dumps(value['error']))
        assert 'error' not in value, 'Live-debug expression unavailable; private RPC output not exported'
        return value.get('result', value)

    try:
        vm = rpc('getVM')
        isolates = [v for v in vm['isolates'] if v['name'] == 'main']
        assert len(isolates) == 1
        isolate = rpc('getIsolate', isolateId=isolates[0]['id'])
        libraries = [v for v in isolate['libraries'] if v['uri'].endswith('/auth_android_b3_b4_device_test.dart')]
        assert len(libraries) == 1
        # Existing server credential ID and original C challenge stay in App
        # memory. We neither submit nor serialize the actual system proof.
        expression = """(() async {
          try {
            final scope = 'hnuhole.isolated.auth.v1|$_c|$_v';
            final namespace = AuthCrypto.domainDigest('HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1', utf8.encode(scope));
            final state = await AuthStore(FlutterAuthVault(namespace: 'hnuhole.auth.v1.$namespace'), scope: scope).read();
            final credentials = await _api().recoveryCredentials(state.session!.token);
            if (credentials.passkeys.isEmpty) return;
            final options = await _api().createPasskeyResetOptions();
            await _native.invokeMethod<String>('acceptanceGetSelected', {
              'publicKey': jsonEncode(options.publicKey),
              'credentialId': credentials.passkeys.last.credentialId,
            });
          } catch (_) {}
        })()"""
        result = rpc('evaluate', isolateId=isolate['id'], targetId=libraries[0]['id'], expression=expression)
        assert result['type'] == '@Instance', 'Live-debug expression did not start'
        value = dict(pid=current_pid, applicationId=PACKAGE, apkSha256=version['apkSha256'],
                     nativeBefore=native, diagnosisCompleted=False, rawProofStored=False,
                     proofSubmitted=False, fixedCaseAcceptancePassed=False,
                     scope='OWNED_LIVE_DEBUG_EXISTING_CREDENTIAL_RESPONSE_DIAGNOSIS_ONLY',
                     toolSourceSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
        record.write_text(json.dumps(value, indent=2)+'\n')
        print('STARTED: one live-debug selected response diagnosis; no full case accepted')
    finally:
        adb('forward', '--remove', 'tcp:'+port)


if __name__ == '__main__':
    main()
