#!/usr/bin/env python3
"""Owned B1/B2 device witnesses; no screenshots, speech, secrets or raw proofs."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
ADB = Path('D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe')
APP = 'org.hnuhole.hnuhole_mobile'
PHONE = '10CEAG17RY003M7'
EMULATOR = 'emulator-5554'
LINUX = '/var/tmp/hnuhole-android-live-batch-20261007'
PHASES = ('ni-l01', 'ni-l02', 'ni-l03', 'ni-l04', 'ni-u01', 'ni-u02', 'ni-u03',
          'ni-a01', 'ni-a02', 'ni-a03', 'ni-a04', 'ni-takeover')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'watch', 'restore', 'stage'))
    parser.add_argument('--phase', required=True, choices=PHASES)
    parser.add_argument('--device', required=True, choices=(PHONE, EMULATOR))
    parser.add_argument('--pid', type=int)
    parser.add_argument('--runner-pid', type=int)
    args = parser.parse_args()
    device, phase = args.device, args.phase
    assert (ROOT / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    assert (phase in ('ni-u01', 'ni-takeover')) == (device == EMULATOR)
    driver = ROOT / ('driver' if device == PHONE else 'emulator-driver') / 'apps/mobile'
    assert (driver / '.device-app-owner').read_text() == device + '|hnuhole-android-live-matrix-20261006'

    def adb(*parts, optional=False):
        result = subprocess.run([str(ADB), '-s', device, *parts], capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=25)
        assert optional or result.returncode == 0, 'Owned device operation failed; diagnostics suppressed'
        return result.stdout.strip()

    installed = adb('shell', 'pm', 'path', APP)
    assert re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk', installed)
    installed_hash = adb('shell', 'sha256sum', installed.removeprefix('package:')).split()[0]
    evidence = ROOT / 'b1b2-evidence'
    evidence.mkdir(exist_ok=True)
    baseline = evidence / (phase + '-device-baseline.json')
    reviewed_hash = hashlib.sha256((ROOT / 'phone-b1b2.apk').read_bytes()).hexdigest()
    if args.action == 'restore' and baseline.exists():
        assert installed_hash == json.loads(baseline.read_text())['apkSha256']
    else:
        assert installed_hash == reviewed_hash

    def settings(namespace, key): return adb('shell', 'settings', 'get', namespace, key)
    def put(namespace, key, value):
        assert re.fullmatch(r'[A-Za-z0-9._/:+-]+', value)
        return adb('shell', 'settings', 'delete', namespace, key) if value == 'null' else adb(
            'shell', 'settings', 'put', namespace, key, "'" + value + "'")
    def private(name):
        value = adb('shell', 'run-as', APP, 'cat', 'files/' + name, optional=True)
        try: return json.loads(value)
        except (ValueError, TypeError): return {}
    def stage():
        current = private('owned-device-driver-stage.json')
        return current if current.get('pid') == args.pid else {}
    def counters(name):
        value = private(name)
        assert value.get('pid') == args.pid, 'Device lifecycle counter PID mismatch'
        return value
    def top():
        raw = adb('shell', 'dumpsys', 'activity', 'activities')
        match = re.search(r'topResumedActivity=[^\n]*? ([A-Za-z0-9._]+/[A-Za-z0-9._]+)', raw)
        return match[1] if match else ''
    def provider(): return top() == 'com.vivo.credentialmanager/.CredentialSelectorActivity'
    def front():
        adb('shell', 'am', 'start', '--activity-reorder-to-front', '-n', APP + '/.MainActivity')
    def ack(name, **fields):
        record = {'pid': args.pid, 'stage': name, 'phase': phase, 'observed': True, **fields}
        result = subprocess.run([str(ADB), '-s', device, 'shell', 'run-as', APP, 'tee',
                                 'files/' + name.replace('-', '_') + '.json'],
                                input=json.dumps(record), capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, 'Owned device acknowledgement unavailable'
    def sql_control(action):
        result = subprocess.run(['wsl', '-d', 'Ubuntu-24.04', '--', 'python3',
                                 LINUX + '/repo/tools/control-android-b1-b2.py', action],
                                capture_output=True, text=True, timeout=45)
        assert result.returncode == 0, 'Owned signed Gate operation unavailable'
        return json.loads(result.stdout)
    def talkback():
        spec = importlib.util.spec_from_file_location('owned_talkback', Path(__file__).with_name('control-android-talkback.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.snapshot()

    if args.action == 'stage':
        args.pid = int(adb('shell', 'pidof', APP))
        current = stage()
        print(json.dumps({'phase': phase, 'pid': args.pid, 'stage': current.get('stage'),
                          'actualOwnedProviderForeground': provider()}))
        return
    if args.action == 'prepare':
        assert not baseline.exists(), 'Retain original device baseline and failed attempts'
        value = {'phase': phase, 'device': device, 'apkSha256': installed_hash}
        if phase == 'ni-l01':
            value.update(accelerometer_rotation=settings('system', 'accelerometer_rotation'),
                         user_rotation=settings('system', 'user_rotation'), font_scale=settings('system', 'font_scale'))
        if phase == 'ni-u02':
            value.update(font_scale=settings('system', 'font_scale'), size=adb('shell', 'wm', 'size'))
        if phase == 'ni-u03': value.update(talkback=talkback())
        if phase == 'ni-u01':
            assert adb('shell', 'getprop', 'ro.kernel.qemu') == '1'
            value['ownedEmulator'] = True
            value['credential_service'] = settings('secure', 'credential_service')
            value['credential_service_primary'] = settings('secure', 'credential_service_primary')
            component = 'com.google.android.gms.auth.api.credentials.credman.service.PasswordAndPasskeyService'
            dump = adb('shell', 'dumpsys', 'package', 'com.google.android.gms')
            def listed(label):
                match = re.search(r'(?m)^([ ]+)' + label + r':\n((?:\1[ ]+[^\n]*\n)*)', dump)
                return bool(match and component in match[2])
            value['providerComponentState'] = 2 if listed('disabledComponents') else 1 if listed('enabledComponents') else 0
            user = re.search(r'User 0:[^\n]*enabled=(\d+)', dump)
            assert user and user[1] in ('0', '1', '2', '3', '4')
            value['providerPackageState'] = int(user[1])
            assert adb('shell', 'id', '-u') == '0', 'Provider configuration fault requires the owned rootable AVD'
        baseline.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
        if phase == 'ni-u02':
            density = adb('shell', 'wm', 'density')
            scales = re.findall(r'(?:Physical|Override) density: (\d+)', density)
            assert scales
            dpi = int(scales[-1])
            adb('shell', 'wm', 'size', f'{round(320 * dpi / 160)}x{round(712 * dpi / 160)}')
            put('system', 'font_scale', '1.6')
        if phase == 'ni-u01':
            # Change actual system provider configuration only on this owned AVD.
            # Keep originals; no credential, account or App data is removed.
            adb('shell', 'settings', 'delete', 'secure', 'credential_service')
            adb('shell', 'settings', 'delete', 'secure', 'credential_service_primary')
            # GMS automatically reenables its individual provider component;
            # suspend only this package on the owned AVD, preserving all data.
            adb('shell', 'pm', 'disable-user', '--user', '0', 'com.google.android.gms')
            assert 'No services found' in adb('shell', 'cmd', 'package', 'query-services', '--brief',
                '-a', 'android.service.credentials.CredentialProviderService')
        for name in ('ni-native-first', 'ni-native-second', 'ni-native-cleaned',
                     'ni-native-second-cleaned', 'ni-talkback-loaded', 'ni-talkback-prior-counts',
                     'ni-companion-ready', 'ni-companion-login-start'):
            adb('shell', 'run-as', APP, 'rm', '-f', 'files/' + name.replace('-', '_') + '.json')
        print('READY: owned device baseline; only fixed acceptance settings applied')
        return
    original = json.loads(baseline.read_text(encoding='utf-8'))
    assert original['device'] == device and original['phase'] == phase and original['apkSha256'] == installed_hash
    if args.action == 'restore':
        if phase == 'ni-u01':
            for key in ('credential_service', 'credential_service_primary'): put('secure', key, original[key])
            if 'providerComponentState' in original:
                command = {0: 'default-state', 1: 'enable', 2: 'disable'}[original['providerComponentState']]
                adb('shell', 'pm', command, '--user', '0',
                    'com.google.android.gms/.auth.api.credentials.credman.service.PasswordAndPasskeyService')
            if 'providerPackageState' in original:
                command = {0: 'default-state', 1: 'enable', 2: 'disable', 3: 'disable-user', 4: 'disable-until-used'}[original['providerPackageState']]
                adb('shell', 'pm', command, '--user', '0', 'com.google.android.gms')
        if phase == 'ni-l01':
            for key in ('accelerometer_rotation', 'user_rotation'): put('system', key, original[key])
            put('system', 'font_scale', original['font_scale'])
        if phase == 'ni-u02':
            match = re.search(r'Override size: (\d+x\d+)', original['size'])
            adb('shell', 'wm', 'size', match[1] if match else 'reset')
            put('system', 'font_scale', original['font_scale'])
        if phase == 'ni-u03':
            old = original['talkback']
            current = talkback()
            members = lambda s: {p for p in s.split(':') if p and p != 'null'}
            prior = members(old['enabledServices'])
            now = members(current['enabledServices'])
            assert prior <= now and all(p.startswith('com.google.android.marvin.talkback/') for p in now - prior)
            put('secure', 'enabled_accessibility_services', old['enabledServices'])
            put('secure', 'accessibility_enabled', old['accessibilityEnabled'])
        print('RESTORED: original owned orientation/display/accessibility settings')
        return
    assert args.pid and adb('shell', 'pidof', APP) == str(args.pid)
    seen = set()
    facts = {'phase': phase, 'pid': args.pid, 'apkSha256': installed_hash,
             'rawProofStored': False, 'humanSpeechCaptured': False}
    companion = None
    companion_log = None
    try:
        limit = time.monotonic() + 900
        while time.monotonic() < limit:
            current = stage().get('stage')
            if current == 'ni-prepare-companion' and current not in seen:
                companion_log = (evidence / 'ni-a03-companion.private.log').open('ab')
                companion = subprocess.Popen(['powershell', '-NoProfile', '-File',
                    str(Path(__file__).with_name('run-android-live-device.ps1')), '-DeviceId', EMULATOR,
                    '-Apk', str(ROOT / 'phone-b1b2.apk'), '-ConfigFile', str(ROOT / 'b1b2-device-config.json'),
                    '-DriverWorkspace', str(ROOT / 'emulator-driver/apps/mobile'), '-PubCache',
                    'D:/zewbbyTest/Hnuhole-android-live-faults-20261005/pub-windows', '-NonIOSPhases', 'ni-takeover'],
                    stdout=companion_log, stderr=companion_log,
                    creationflags=subprocess.CREATE_NO_WINDOW)
                deadline = time.monotonic() + 100
                while time.monotonic() < deadline:
                    result = subprocess.run([str(ADB), '-s', EMULATOR, 'shell', 'run-as', APP, 'cat',
                        'files/owned-device-driver-stage.json'], capture_output=True, text=True, timeout=15)
                    try: ready = json.loads(result.stdout)
                    except ValueError: ready = {}
                    if ready.get('stage') == 'ni-companion-ready': break
                    assert companion.poll() is None, 'Actual companion fixture failed before ready'
                    time.sleep(.25)
                else: raise RuntimeError('Actual companion was not ready; no old phone proof requested')
                facts['companionPid'] = ready['pid']
                ack('ni-companion-ready')
                seen.add(current)
            if current in ('ni-await-native-first', 'ni-await-native-second') and current not in seen:
                if not provider():
                    time.sleep(.2)
                    continue
                facts['actualOwnedNativeProviderObserved'] = True
                details = {}
                if phase == 'ni-l01':
                    prior = counters('owned-acceptance-lifecycle.json')
                    put('system', 'accelerometer_rotation', '0')
                    # Change to the opposite actual orientation, not a guessed rotation.
                    put('system', 'user_rotation', '1' if prior['orientation'] == 1 else '0')
                    # OEM selector may pin orientation. Font scale is also an actual
                    # configuration change handled by this manifest, not recreation.
                    put('system', 'font_scale', '1.15' if prior.get('fontScale') != 1.15 else '1.0')
                    deadline = time.monotonic() + 12
                    while time.monotonic() < deadline:
                        after = counters('owned-acceptance-lifecycle.json')
                        if after.get('configurationChanged', 0) > prior.get('configurationChanged', 0): break
                        time.sleep(.2)
                    assert after.get('configurationChanged', 0) > prior.get('configurationChanged', 0)
                    facts['actualConfigurationChange'] = True
                if phase == 'ni-l03':
                    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
                    time.sleep(1)
                    assert top() not in (APP + '/.MainActivity', 'com.vivo.credentialmanager/.CredentialSelectorActivity')
                    front()
                    time.sleep(1)
                    assert top() in (APP + '/.MainActivity', 'com.vivo.credentialmanager/.CredentialSelectorActivity')
                    details['actualHomeAndOwnedAppReturn'] = True
                if phase == 'ni-a01':
                    frozen = sql_control('freeze-c')
                    assert frozen['sql']['gateState'] == 'FROZEN'
                    facts['signedFreezeAfterActualNativeRequest'] = True
                if phase == 'ni-a03':
                    assert companion and facts.get('companionPid')
                    message = json.dumps({'pid': facts['companionPid'], 'stage': 'ni-companion-login-start',
                                          'phase': 'ni-takeover', 'observed': True})
                    result = subprocess.run([str(ADB), '-s', EMULATOR, 'shell', 'run-as', APP, 'tee',
                        'files/ni_companion_login_start.json'], input=message, capture_output=True, text=True, timeout=15)
                    assert result.returncode == 0
                    assert companion.wait(timeout=35) == 0, 'Actual companion login must finish before old phone UV'
                    accepted = json.loads((ROOT / 'emulator-driver/apps/mobile/live-ni-takeover.json').read_text())
                    assert accepted.get('explicitCompanionLoginSameAccount') is True
                    facts['actualCompanionLoginAfterNativeRequestBeforeOldUV'] = True
                ack('ni-native-second' if current.endswith('second') else 'ni-native-first', **details)
                seen.add(current)
                if phase in ('ni-a01', 'ni-a03', 'ni-a04'):
                    (evidence / (phase + '-ready-for-uv.json')).write_text(json.dumps(facts) + '\n')
                    print('READY_FOR_UV: ' + phase, flush=True)
            if current in ('ni-native-returned', 'ni-native-second-returned', 'ni-recreate-requested') and current not in seen:
                native = counters('owned-acceptance-passkey.json')
                if native.get('nativeCancelled', 0) < 1:
                    time.sleep(.2)
                    continue
                if current == 'ni-recreate-requested':
                    life = counters('owned-acceptance-lifecycle.json')
                    if life.get('activityCreated', 0) < 2 or life.get('activityDestroyed', 0) < 1 or native.get('engineDetached', 0) < 1:
                        time.sleep(.2)
                        continue
                    facts['actualActivityAndEngineTeardown'] = True
                    assert native.get('nativeBegun') == 1, 'New engine must not replay original native request'
                    if args.runner_pid:
                        # The original integration driver's request is tied to the
                        # destroyed isolate. Terminate only its exact owned process
                        # subtree so the runner can attach to the newly created engine.
                        query = subprocess.run(['powershell', '-NoProfile', '-Command',
                            'Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,CommandLine | ConvertTo-Json -Compress'],
                            capture_output=True, text=True, timeout=20)
                        assert query.returncode == 0
                        processes = json.loads(query.stdout)
                        by_pid = {p['ProcessId']: p for p in processes}
                        def owned_child(p):
                            visited = set()
                            while p and p['ProcessId'] not in visited:
                                visited.add(p['ProcessId'])
                                if p['ParentProcessId'] == args.runner_pid: return True
                                p = by_pid.get(p['ParentProcessId'])
                            return False
                        masters = [p for p in processes if p['Name'] == 'dart.exe' and
                            all(t in (p.get('CommandLine') or '') for t in ('flutter_tools.snapshot', 'drive',
                                '--use-existing-app', 'auth_android_b1_b2_device_test.dart', device)) and owned_child(p)]
                        completed = evidence / 'ni-l02-first-drive-done.json'
                        finished = completed.exists() and json.loads(completed.read_text()).get('pid') == args.pid
                        assert finished or len(masters) == 1, 'Original owned Flutter driver must be unambiguous'
                        master = masters[0]['ProcessId'] if masters and not finished else None
                        children = [p['ProcessId'] for p in processes if master and p['ParentProcessId'] == master and p['Name'] == 'dart.exe']
                        # Stop the Flutter tools parent first: if its driver child
                        # exits first, tools can close the new VM during cleanup.
                        for child in ([master, *children] if master else []):
                            stopped = subprocess.run(['powershell', '-NoProfile', '-Command',
                                'Stop-Process -Id ' + str(child) + ' -ErrorAction SilentlyContinue'], capture_output=True, timeout=15)
                            assert stopped.returncode == 0
                        facts['oldIsolateDriverStoppedAfterActualTeardown'] = True
                if provider(): adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
                front()
                ack('ni-native-second-cleaned' if current == 'ni-native-second-returned' else 'ni-native-cleaned')
                seen.add(current)
            if current == 'ni-talkback-prior-reconciled' and current not in seen:
                assert phase == 'ni-u03'
                prior_counts = subprocess.run(['wsl', '-d', 'Ubuntu-24.04', '--', 'python3',
                    LINUX + '/repo/tools/control-android-b1-b2.py',
                    'reanchor-talkback', '--phase', 'ni-u03'], capture_output=True, timeout=45)
                assert prior_counts.returncode == 0, 'Prior original-result count anchor failed'
                facts['priorRotationQueryReconciledBeforeFreshAnchor'] = True
                ack('ni-talkback-prior-counts', confirmationReplayed=False)
                seen.add(current)
            if current == 'ni-talkback-enable' and current not in seen:
                loaded = talkback()
                if loaded['talkBackBound'] and loaded['accessibilityEnabled'] == '1':
                    front()
                    ack('ni-talkback-loaded', actualLoadedTalkBack=True)
                    facts['actualLoadedTalkBack'] = True
                    seen.add(current)
            response = driver / 'build/integration_response_data.json'
            if response.exists():
                result = json.loads(response.read_text(encoding='utf-8'))
                if result.get('pid') == args.pid and result.get('phase') == phase:
                    if phase == 'ni-u03':
                        observation = private(f'owned-device-talkback-observation-{args.pid}.json')
                        assert observation.get('pid') == args.pid
                        assert observation['diagnosticOnly'] is True
                        assert observation['semanticsActionsInjected'] is False
                        assert observation['speechCaptured'] is False
                        assert observation['pendingState'] == 'NONE'
                        required_gates = ('errorFocused', 'rotateTapped', 'hideTapped',
                            'confirmationFocused', 'confirmTapped', 'unknownFocused',
                            'queryTapped', 'committedFocused', 'ackTapped', 'pendingCleared')
                        assert all(observation['gates'][key] is True for key in required_gates)
                        assert observation['diagnosticWriteFailures'] == 0
                        (evidence / 'ni-u03-public-observation.json').write_text(
                            json.dumps(observation, indent=2) + '\n')
                        facts['actualPublicSemanticsEventGatesObserved'] = True
                    if phase.startswith('ni-l') or phase in ('ni-a01', 'ni-a03', 'ni-a04'):
                        assert facts.get('actualOwnedNativeProviderObserved') is True
                    facts['result'] = 'PASS'
                    facts['scope'] = 'OWNED_DEVICE_WITNESSES_ONLY'
                    (evidence / (phase + '-device.json')).write_text(json.dumps(facts, indent=2) + '\n')
                    print('PASS: fixed actual device witnesses ' + phase)
                    return
            time.sleep(.25)
        raise RuntimeError('Fixed device witness deadline reached')
    finally:
        if companion and companion.poll() is None:
            # Stop only this exact owned runner, never an unrelated shell or adb server.
            companion.terminate()
            companion.wait(timeout=15)
        if companion_log: companion_log.close()


if __name__ == '__main__': main()
