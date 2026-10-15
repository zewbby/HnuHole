#!/usr/bin/env python3
"""Owned task-2 native suites and real-plugin process probes; no automatic reboot."""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import socket
import subprocess
import time
from pathlib import Path
from urllib.parse import urlsplit

spec = importlib.util.spec_from_file_location('community_stage1_transport', Path(__file__).parents[1] / 'community-android-stage1/phone.py')
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)
OWNER = 'HNUHOLE_COMMUNITY_ANDROID_STAGE2_V1'
APP = 'org.hnuhole.hnuhole_mobile.communityf5.storage'
VAULT = 'org.hnuhole.communityf5.storage.vault.test'
PASSKEY = 'org.hnuhole.communityf5.storage.passkey.test'
ARTIFACTS = {'storage': APP, 'vault': VAULT, 'passkey': PASSKEY}
SUITES = [
    ('vault', 'org.hnuhole.authvault.AndroidBusinessStorageTest', 7),
    ('vault', 'org.hnuhole.authvault.AndroidAuthVaultTest', 16),
    ('passkey', 'org.hnuhole.authpasskey.PasskeyCodecTest', 9),
    ('passkey', 'org.hnuhole.authpasskey.PasskeyAcceptanceErrorsTest', 3),
]
ORDER = {'write': 'suites', 'read': 'write', 'reboot-read': 'read', 'purge': 'read', 'closed': 'purge'}


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def consent(args):
    transport.consent(args.confirmed_window, args.allow_isolated_install,
                      args.auth_session_released, args.allow_owned_adb_key)
    if not args.allow_owned_force_stop:
        raise ValueError('explicit permission to force-stop only the three task-2 packages required')


def load_manifest(path):
    path = Path(path).resolve(strict=True)
    root = path.parent
    manifest = json.loads(path.read_text())
    if (root / '.owner').read_text().strip() != OWNER or manifest.get('owner') != OWNER:
        raise ValueError('task-2 owner required')
    if not re.fullmatch(r'community-storage-[0-9a-f]{16}', manifest.get('runId', '')):
        raise ValueError('fixed synthetic run ID required')
    if set(manifest['apks']) != set(ARTIFACTS):
        raise ValueError('exact task-2 artifact set required')
    for name, package in ARTIFACTS.items():
        item = manifest['apks'][name]
        apk = Path(item['path']).resolve(strict=True)
        if apk.parent != root or item['applicationId'] != package or digest(apk) != item['sha256']:
            raise ValueError('fixed task-2 APK/package mismatch')
    adb = Path(manifest['adb']).resolve(strict=True)
    if adb != root / 'adb' / 'adb.exe' or set(manifest['adbFiles']) != {'adb.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll', 'libwinpthread-1.dll'}:
        raise ValueError('exact owned ADB files required')
    for name, expected in manifest['adbFiles'].items():
        if digest(adb.parent / name) != expected:
            raise ValueError('owned ADB hash mismatch')
    transport.adb_port(manifest['adbServerPort'])
    return root, manifest


def instrumentation_ok(text, count):
    # Exit code alone or a green-looking prefix never constitutes a test result.
    if re.search(r'FAILURES|INSTRUMENTATION_FAILED|Process crashed|INSTRUMENTATION_ABORTED|Error:|INSTRUMENTATION_STATUS_CODE: -[234]|INSTRUMENTATION_RESULT: shortMsg=', text):
        raise ValueError('native suite failed or has an unknown outcome')
    matches = re.findall(r'^OK \((\d+) tests?\)\s*$', text, re.M)
    if matches != [str(count)] or re.search(r'numtests=(\d+)', text) and set(re.findall(r'numtests=(\d+)', text)) != {str(count)}:
        raise ValueError('exact native test count required')


def filtered_result(raw, phase):
    data = raw.get('data') or {}
    if raw.get('result') != 'true' or data.get('phase') != 'storage-' + phase:
        raise ValueError('original storage probe failed; no automatic replay')
    if data.get('nativeVault') is not True or data.get('nativeBusinessSqlite') is not True or data.get('syntheticFixturesOnly') is not True or data.get('actualMainCalled') is not False:
        raise ValueError('native synthetic-fixture scope mismatch')
    flags = data.get('flags', {})
    required = {
        'write': {'durableWritesAcknowledged', 'realSqliteWithoutPayloadPlaintext'},
        'read': {'draftAndOriginalIntentRestored', 'nativeAuthRecordPreserved', 'otherAccountPreserved', 'realSqliteWithoutPayloadPlaintext'},
        'reboot-read': {'draftAndOriginalIntentRestored', 'nativeAuthRecordPreserved', 'otherAccountPreserved', 'realSqliteWithoutPayloadPlaintext'},
        'purge': {'nativeLocalPurgeCompleted', 'nativeAuthRecordPreserved', 'otherAccountPreserved'},
        'closed': {'closedMarkerSurvivesNewProcess', 'closedKeyAndDatabaseFilesAbsent', 'nativeAuthRecordPreserved', 'otherAccountPreserved'},
    }[phase]
    if not required.issubset(flags) or not all(type(v) is bool and v for v in flags.values()) or type(data.get('pid')) is not int or data['pid'] <= 0:
        raise ValueError('required boolean facts and real process witness missing')
    return {'result': 'PASS', 'phase': phase, 'pid': data['pid'], 'flags': {key: flags[key] for key in sorted(required)},
            'syntheticFixturesOnly': True, 'actualMainCalled': False,
            'systemPasskeyCeremony': False, 'manualImeVerified': False}


def validate_order(state, phase, device_hash, manual_reboot=False):
    if state.get('deviceIdHash') not in (None, device_hash):
        raise ValueError('same confirmed physical phone required')
    if phase in state.get('started', []):
        raise ValueError('phase already started; inspect original outcome before any retry')
    if phase != 'suites' and state.get('results', {}).get(ORDER[phase], {}).get('result') != 'PASS':
        raise ValueError('prior phase must have a confirmed result')
    if phase == 'reboot-read' and not manual_reboot:
        raise ValueError('separate confirmation of completed manual whole-phone reboot required')
    if phase in ('read', 'reboot-read') and 'purge' in state.get('started', []):
        raise ValueError('cannot resume a pre-purge probe after purge started')


def server_witness(port):
    """Read only the chosen Windows listener; never query/connect to global ADB."""
    transport.adb_port(port)
    if os.name != 'nt':
        raise ValueError('prepared device runner requires the owned Windows ADB copy')
    code = "$ErrorActionPreference='Stop'; $items=@(Get-NetTCPConnection -State Listen -LocalPort " + str(port) + " -ErrorAction SilentlyContinue); if($items.Count -eq 0){'null';exit}; $ids=@($items.OwningProcess|Sort-Object -Unique); if($ids.Count -ne 1){throw 'Ambiguous owned port'}; $p=Get-Process -Id $ids[0] -ErrorAction Stop; @{pid=$p.Id;start=$p.StartTime.ToUniversalTime().Ticks.ToString();exe=$p.Path}|ConvertTo-Json -Compress"
    shell = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    result = subprocess.run([str(shell), '-NoProfile', '-NonInteractive', '-Command', code],
                            check=True, capture_output=True, text=True, timeout=20)
    return json.loads(result.stdout)


def owned_server(witness, previous, adb):
    if witness is not None and (previous is None or witness != previous or
                                Path(witness['exe']).resolve() != Path(adb).resolve()):
        raise ValueError('dedicated port belongs to an unknown/replaced ADB process')


def run_phone(args):
    consent(args)  # Before filesystem reads, socket binding, or any ADB call.
    if args.phase not in ['suites', *ORDER] or not re.fullmatch(r'[A-Za-z0-9._:-]{1,128}', args.device or ''):
        raise ValueError('explicit phase and device required')
    root, manifest = load_manifest(args.manifest)
    state_path = root / 'device-state.json'
    state = json.loads(state_path.read_text()) if state_path.exists() else {'started': [], 'results': {}}
    device_hash = hashlib.sha256(args.device.encode()).hexdigest()
    validate_order(state, args.phase, device_hash, args.confirmed_manual_reboot)
    port = manifest['adbServerPort']
    # Never attach to another server (even on the dedicated prepared port).
    # Our server may survive phases; record its own startup before the first call.
    witness = server_witness(port)
    owned_server(witness, state.get('adbServerWitness'), manifest['adb'])
    if witness is None:
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', port))
    def adb(*parts, optional=False):
        current = server_witness(port)
        owned_server(current, state.get('adbServerWitness'), manifest['adb'])
        before = current
        done = subprocess.run([manifest['adb'], '-P', str(port), '-s', args.device, *map(str, parts)],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=240,
                              env=transport.adb_environment(root))
        if tuple(parts[:3]) == ('shell', 'am', 'instrument'):
            if len(done.stdout) + len(done.stderr) > 262144:
                raise ValueError('native output bound exceeded; result unknown')
            # Only synthetic native suites, never the VM witness or App vault.
            # Local private diagnostic output is excluded from Git/evidence export.
            with (root / 'native-instrumentation.private.log').open('ab') as log:
                log.write(done.stdout + done.stderr + b'\n')
        current = server_witness(port)
        if current is None or Path(current['exe']).resolve() != Path(manifest['adb']).resolve():
            raise ValueError('owned ADB server startup not witnessed')
        if before is not None:
            owned_server(current, state['adbServerWitness'], manifest['adb'])
        state['adbServerWitness'] = current
        state_path.write_text(json.dumps(state, indent=2) + '\n')
        if done.returncode and not optional:
            raise RuntimeError('owned ADB operation failed; original outcome retained')
        return done.stdout.decode(errors='replace').strip()
    state['deviceIdHash'] = device_hash
    state['runId'] = manifest['runId']
    state_path.write_text(json.dumps(state, indent=2) + '\n')
    print('Authorize this task USB debugging key on the confirmed phone if prompted.', flush=True)
    end = time.monotonic() + 90
    while adb('get-state', optional=True) != 'device':
        if time.monotonic() > end:
            raise ValueError('confirmed phone not authorized; no test phase started')
        time.sleep(.5)
    if adb('shell', 'getprop', 'ro.kernel.qemu') == '1' or 'arm64-v8a' not in adb('shell', 'getprop', 'ro.product.cpu.abilist'):
        raise ValueError('physical ARM64 Android required')
    if adb('shell', 'getprop', 'sys.boot_completed') != '1':
        raise ValueError('phone boot not complete')
    boot_hash = hashlib.sha256(adb('shell', 'cat', '/proc/sys/kernel/random/boot_id').encode()).hexdigest()
    if args.phase == 'reboot-read' and boot_hash == state['results']['read']['bootIdHash']:
        raise ValueError('whole-phone reboot not witnessed')

    def installed(name, may_install=False):
        package = ARTIFACTS[name]
        value = adb('shell', 'pm', 'path', package, optional=True)
        if value:
            match = re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)', value)
            if not match or adb('shell', 'sha256sum', match[1]).split()[0] != manifest['apks'][name]['sha256']:
                raise ValueError('unknown existing task-2 package; never overwrite')
        elif may_install:
            if 'Success' not in adb('install', '-t', manifest['apks'][name]['path']):
                raise ValueError('isolated install failed')
        else:
            raise ValueError('owned prior-phase package missing; do not reinstall or clear data')

    def stop(package):
        if package not in ARTIFACTS.values():
            raise ValueError('force-stop outside exact task-2 allowlist')
        adb('shell', 'am', 'force-stop', package)
        if adb('shell', 'pidof', package, optional=True):
            raise ValueError('owned prior process still alive')

    state['started'].append(args.phase)
    state_path.write_text(json.dumps(state, indent=2) + '\n')
    if args.phase == 'suites':
        for name in ('vault', 'passkey'):
            installed(name, True)
        results = []
        for name, test_class, count in SUITES:
            text = adb('shell', 'am', 'instrument', '-w', '-e', 'class', test_class,
                       ARTIFACTS[name] + '/androidx.test.runner.AndroidJUnitRunner')
            instrumentation_ok(text, count)
            results.append({'class': test_class, 'result': 'PASS', 'count': count})
        # Existing crash probes are opt-in and only kill their own test process.
        restart = 'org.hnuhole.authvault.AuthVaultProcessRestartTest'
        for index, (write, read) in enumerate([('write', 'read'), ('kill-before-replace', 'read-before'), ('kill-after-sync', 'read-after')]):
            namespace = 'native.restart.' + manifest['runId'] + '.' + str(index)
            def probe(phase):
                return adb('shell', 'am', 'instrument', '-w', '-e', 'class', restart,
                           '-e', 'vault_restart_phase', phase, '-e', 'vault_restart_namespace', namespace,
                           VAULT + '/androidx.test.runner.AndroidJUnitRunner', optional=index > 0 and phase == write)
            text = probe(write)
            if index == 0:
                instrumentation_ok(text, 1)
            elif not re.search(r'Process crashed|INSTRUMENTATION_FAILED', text) or re.search(r'OK \(', text):
                raise ValueError('expected owned process interruption absent; original probe unknown')
            stop(VAULT)
            instrumentation_ok(probe(read), 1)
            results.append({'id': 'auth-process-pair-' + str(index), 'result': 'PASS'})
        result = {'result': 'PASS', 'nativeTests': results, 'suiteCount': 35, 'restartPairs': 3}
    else:
        installed('storage', args.phase == 'write')
        stop(APP)
        adb('shell', 'am', 'start', '-n', APP + '/org.hnuhole.hnuhole_mobile.MainActivity',
            '--ez', 'hnuhole-device-driver', 'true', '--es', 'hnuhole-device-phase', 'storage-' + args.phase)
        vm = None
        end = time.monotonic() + 100
        while time.monotonic() < end:
            try:
                witness = json.loads(adb('shell', 'run-as', APP, 'cat', 'files/owned-device-driver-vm.json', optional=True))
                pid = adb('shell', 'pidof', APP)
                if pid.isdecimal() and witness['pid'] == int(pid):
                    vm = witness['uri']
                    break
            except (ValueError, KeyError):
                pass
            time.sleep(.3)
        if vm is None:
            raise RuntimeError('original process VM unavailable; never restart unknown probe')
        parsed = urlsplit(vm)
        if parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or not parsed.port or parsed.username or parsed.query or parsed.fragment:
            raise ValueError('private loopback VM required')
        forward = adb('forward', 'tcp:0', 'tcp:' + str(parsed.port))
        if not forward.isdecimal():
            raise ValueError('owned ephemeral forward unavailable')
        try:
            client = transport.VM('http://127.0.0.1:' + forward + parsed.path)
            try:
                result = filtered_result(client.run(), args.phase)
            finally:
                client.close()
            if result['pid'] != int(pid):
                raise ValueError('VM and native process PID mismatch')
            previous = state['results'].get(ORDER[args.phase], {})
            if args.phase != 'reboot-read' and result['pid'] == previous.get('pid'):
                raise ValueError('new Android process not witnessed')
        finally:
            adb('forward', '--remove', 'tcp:' + forward, optional=True)
    result['bootIdHash'] = boot_hash
    state['results'][args.phase] = result
    state['result'] = 'PARTIAL_DEVICE_MANUAL_CHECKS_PENDING'
    state_path.write_text(json.dumps(state, indent=2) + '\n')
    print('PASS scoped phase: ' + args.phase + '; manual actual-account/IME/TalkBack checks remain.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest')
    parser.add_argument('--device')
    parser.add_argument('--phase', choices=['suites', *ORDER])
    for flag in ['confirmed-window', 'allow-isolated-install', 'auth-session-released', 'allow-owned-adb-key', 'allow-owned-force-stop', 'confirmed-manual-reboot', 'plan-only']:
        parser.add_argument('--' + flag, action='store_true')
    args = parser.parse_args()
    if args.plan_only:
        print('Plan only (no manifest/ADB access): consent -> 7+16+12 native tests + 3 auth process pairs -> write -> read -> optional approved manual reboot/read -> local purge -> closed/new-process. Only task-2 packages; no uninstall, data clear, settings change, or reboot command.')
    else:
        run_phone(args)
