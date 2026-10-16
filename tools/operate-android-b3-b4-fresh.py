#!/usr/bin/env python3
"""Review/install the fresh product or select a known provider on the owned vivo.

Without --execute this performs host artifact validation only. Never operates on
the historical application packages, exports a vault, or authenticates a user.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


FRESH = module('fresh_bootstrap_operator', 'prepare-android-b3-b4-fresh.py')
BUILD = module('fresh_builder_operator', 'build-android-b3-b4-fresh.py')
DIAG = module('fresh_diagnostic_operator', 'run-google-passkey-diagnostic.py')
ROOT = Path(FRESH.WINDOWS_HOST)
SNAPSHOT = ROOT.parent / 'phone-snapshot'
ADB = Path('E:/Hnuhole-env/android-sdk/platform-tools/adb.exe')
SDK = Path('E:/Hnuhole-env/android-sdk/build-tools/36.0.0')
JAVA = Path('E:/Hnuhole-env/windows/jdk-17.0.20.1+1/bin/java.exe')
HISTORICAL = {
    'org.hnuhole.hnuhole_mobile': 'ac66d81ffb760e17aca0770906b93c18b031bf8ffb9e0733974ef8b65abe5871',
    'org.hnuhole.hnuhole_mobile.acceptance': '7c0230c7df2cbcf1fc0074607bc621fe85395c3964308b092bc8e4f9df981f89',
}
GOOGLE = 'com.google.android.gms/com.google.android.gms.auth.api.credentials.credman.service.PasswordAndPasskeyService'
VIVO = 'com.vivo.cipherchain/com.vivo.cipherchain.credentialmanager.CipherchainCredentialProviderService'
GOOGLE_AUTOFILL = 'com.google.android.gms/.autofill.service.AutofillService'
VIVO_AUTOFILL = 'com.vivo.cipherchain/.service.CipChainService'
KEYS = ('credential_service', 'credential_service_primary', 'autofill_service')
COUNTERS = ('nativeBegun', 'nativeSucceeded', 'nativeErrored', 'nativeCancelled', 'nativeTimeout',
            'actualAssociationRejected', 'activityAttached', 'activityDetached', 'engineDetached')
PROVIDER_ACTIVITIES = (
    'com.vivo.credentialmanager/.CredentialSelectorActivity',
    'com.google.android.gms/.auth.api.credentials.fido.registration.ui.RegistrationActivity',
    'com.google.android.gms/.auth.api.credentials.fido.authentication.ui.AuthenticationActivity',
)
APK_ACTIONS = {
    'install-approved': ('b3b4-acceptance.apk', FRESH.PACKAGE, FRESH.CERT),
    'restore-approved': ('b3b4-acceptance.apk', FRESH.PACKAGE, FRESH.CERT),
    'install-bad-signature': ('b3b4-bad-signature.apk', FRESH.PACKAGE, BUILD.BAD_CERT),
    'install-unassociated': ('b3b4-unassociated.apk', FRESH.MISSING_PACKAGE, FRESH.CERT),
}
WATCHER_FILE = 'tools/control-android-b3-b4-device.py'
WATCHER_ORIGINAL_SHA = '1a2898c17e9e11cc9af86c170da3004954cc113542238bf87e55d1c9e476fe55'
WATCHER_MANIFEST_SHA = 'ec626d6afd873236f1094b69ee54ab63dff92351879ed8910c958c2b285561e5'
WATCHER_BACKUP = 'control-android-b3-b4-device.pre-local-unknown-guard.py'
WATCHER_RECEIPT = 'host-watcher-local-unknown-guard.json'
WATCHER_ANCHOR = (b"            elif stage.startswith('ni-native-ended-return-'):\n"
                  b"                state=private('owned-acceptance-passkey.json')\n")
WATCHER_INSERTION = (b"                assert all(type(state.get(k,0)) is int and state.get(k,0)==0\n"
                     b"                    for k in ('nativeTimeout','nativeCancelled')),'Local native timeout/cancel remains UNKNOWN; preserve provider task'\n")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read(path, maximum=2_000_000):
    require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= maximum,
            'Exact bounded owned record required: ' + path.name)
    value = json.loads(path.read_text(encoding='utf-8-sig'))
    require(isinstance(value, dict), 'Owned record must be an object')
    return value


def write_new(path, value):
    require(not path.exists() and not path.is_symlink(), 'Preserve the original operation evidence')
    with path.open('x', encoding='utf-8') as out:
        json.dump(value, out, ensure_ascii=False, indent=2)
        out.write('\n')
        out.flush()
        os.fsync(out.fileno())


def command(parts, timeout=30):
    result = subprocess.run([str(part) for part in parts], capture_output=True, timeout=timeout)
    require(result.returncode == 0, 'Owned operation failed; raw device/tool output was not exported')
    return result.stdout


def adb(*parts, timeout=30):
    return command([ADB, '-s', FRESH.DEVICE, *parts], timeout)


def install_success(output):
    """Accept bounded standard adb progress followed by one terminal Success."""
    if type(output) is not bytes or not 0 < len(output) <= 4096:
        return False
    if any(byte not in (9, 10, 13) and not 32 <= byte <= 126 for byte in output):
        return False
    lines = [line.strip(b' \t') for line in output.splitlines() if line.strip(b' \t')]
    return lines == [b'Success'] or (len(lines) == 2
        and lines[0] in (b'Performing Push Install', b'Performing Streamed Install')
        and lines[1] == b'Success')


def verify_apk(path, package, cert):
    require(path.is_file() and not path.is_symlink(), 'Exact regular reviewed APK required')
    certs = re.findall(r'Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})',
                      command([JAVA, '-jar', SDK / 'lib/apksigner.jar', 'verify', '--print-certs', path], 120).decode())
    require(certs == [cert], 'APK signature must have exactly the reviewed certificate')
    badging = command([SDK / 'aapt2.exe', 'dump', 'badging', path], 60).decode()
    found = re.search(r"^package: name='([^']+)'", badging, flags=re.MULTILINE)
    require(found is not None and found[1] == package, 'APK package differs from the reviewed identity')


def validate_pub_route(entry):
    receipt = entry.get('pubLockRouteOverlay')
    if receipt is None:
        return
    require(isinstance(receipt, dict), 'Bounded explicit hosted URL overlay receipt required')
    expected = dict(schemaVersion=1, owner=FRESH.TOKEN,
        sourceManifestSha256=BUILD.sha(ROOT / 'source-manifest.json'),
        scope='EXACT_WHOLE_FILE_HOSTED_URL_SUBSTITUTION_ONLY', sourceFile='apps/mobile/pubspec.lock',
        sourceSha256='3f1896969f3ed1bec71f75bea42cd6bce5989542013cb4d5ce3c225435bc2a51',
        stagedSha256='d81ec9b5a5b626bb88797d6dc20b89dea0811682a696dfae69d3717fcb067510',
        previousHostedUrl='https://pub.flutter-io.cn', hostedUrl='https://pub.dev', replacements=34,
        dependencyNamesVersionsAndContentDigestsPreserved=True, sourceLockModified=False,
        actualDeviceAcceptancePassed=False)
    path = ROOT / 'b3b4-evidence/pub-lock-route-overlay.json'
    require(read(path, 4096) == expected and receipt.get('receiptFileName') == path.name
            and receipt.get('receiptSha256') == BUILD.sha(path)
            and {key: value for key, value in receipt.items() if key not in ('receiptFileName', 'receiptSha256')} == expected,
            'Hosted route receipt differs from the exact reviewed byte substitution')
    original = (ROOT / 'repo' / expected['sourceFile']).read_bytes()
    old, new = expected['previousHostedUrl'].encode(), expected['hostedUrl'].encode()
    require(FRESH.digest(original) == expected['sourceSha256'] and original.count(old) == 34
            and FRESH.digest(original.replace(old, new)) == expected['stagedSha256'],
            'Hosted URL overlay must preserve the entire exact locked dependency file')


def guarded_watcher_bytes(original):
    require(type(original) is bytes and 0 < len(original) <= 64 * 1024
            and FRESH.digest(original) == WATCHER_ORIGINAL_SHA and original.count(WATCHER_ANCHOR) == 1,
            'Exact original watcher bytes and single insertion point required')
    return original.replace(WATCHER_ANCHOR, WATCHER_ANCHOR + WATCHER_INSERTION, 1)


def watcher_overlay_record(original):
    guarded = guarded_watcher_bytes(original)
    return dict(schemaVersion=1, owner=FRESH.TOKEN, scope='EXACT_WINDOWS_HOST_NATIVE_UNKNOWN_GUARD_ONLY',
        sourceFile=WATCHER_FILE, sourceManifestSha256=WATCHER_MANIFEST_SHA,
        originalSourceSha256=WATCHER_ORIGINAL_SHA, guardedSourceSha256=FRESH.digest(guarded),
        insertionSha256=FRESH.digest(WATCHER_INSERTION), originalBackupFileName=WATCHER_BACKUP,
        originalBackupSha256=WATCHER_ORIGINAL_SHA, preparedSourceManifestModified=False,
        linuxPreparedMirrorModified=False, apkPayloadModified=False, productNativePluginModified=False,
        phoneOperationExecuted=False, actualDeviceAcceptancePassed=False)


def validate_host_watcher_overlay(source):
    path = ROOT / 'repo' / WATCHER_FILE
    directory = ROOT / 'b3b4-evidence'
    receipt_path, backup = directory / WATCHER_RECEIPT, directory / WATCHER_BACKUP
    if not receipt_path.exists() and not receipt_path.is_symlink() and not backup.exists() and not backup.is_symlink():
        return None
    require(BUILD.sha(ROOT / 'source-manifest.json') == WATCHER_MANIFEST_SHA
            and source['stagedFilesSha256'].get(WATCHER_FILE) == WATCHER_ORIGINAL_SHA,
            'Watcher overlay must retain the exact original source admission')
    require(backup.is_file() and not backup.is_symlink() and 0 < backup.stat().st_size <= 64 * 1024,
            'Preserve the exact original watcher backup')
    original = backup.read_bytes()
    expected = watcher_overlay_record(original)
    require(read(receipt_path, 4096) == expected and path.is_file() and not path.is_symlink()
            and path.read_bytes() == guarded_watcher_bytes(original),
            'Watcher or receipt differs from the single reviewed native UNKNOWN guard insertion')
    return dict(expected, receiptFileName=WATCHER_RECEIPT, receiptSha256=BUILD.sha(receipt_path))


def validate_host(action):
    require(ROOT.is_dir() and not ROOT.is_symlink(), 'Exact fresh matrix root required')
    require((ROOT / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
            and (ROOT / 'FRESH_OWNER').read_text().strip() == FRESH.TOKEN, 'Exact fresh root owners required')
    source = read(ROOT / 'source-manifest.json')
    require(source.get('owner') == FRESH.TOKEN and source.get('servicesReady') is True
            and source.get('applicationId') == FRESH.PACKAGE and source.get('device') == FRESH.DEVICE
            and source.get('deviceRunId') == FRESH.RUN and source.get('accountRunId') == FRESH.ACCOUNT_RUN
            and source.get('approvedCertificateSha256') == FRESH.CERT, 'Ready fresh source admission required')
    watcher_overlay = validate_host_watcher_overlay(source)
    for name, expected in source['stagedFilesSha256'].items():
        path = ROOT / 'repo' / name
        if name == WATCHER_FILE and watcher_overlay is not None:
            expected = watcher_overlay['guardedSourceSha256']
        require(path.resolve().is_relative_to((ROOT / 'repo').resolve()) and not path.is_symlink()
                and path.is_file() and BUILD.sha(path) == expected, 'Prepared source mirror changed: ' + name)
    require((SNAPSHOT / 'OWNER').read_text().strip() == 'HNUHOLE_B3B4_PHONE_SNAPSHOT_20261012',
            'Original phone snapshot owner required')
    for package, expected in HISTORICAL.items():
        path = SNAPSHOT / (package + '.apk')
        require(path.is_file() and not path.is_symlink() and BUILD.sha(path) == expected,
                'Original package snapshot changed; preserve phone state')
    config = read(ROOT / 'b3b4-acceptance-config.json')
    require(config['AUTH_DEVICE_RUN_ID'] == FRESH.RUN
            and config['AUTH_MATRIX_ACCOUNT_RUN_ID'] == FRESH.ACCOUNT_RUN,
            'Exact fresh account/runtime config required')
    ledger_path = ROOT / 'b3b4-evidence/builds.json'
    ledger = read(ledger_path) if ledger_path.exists() else None
    if ledger is not None:
        require(ledger.get('owner') == FRESH.TOKEN
                and ledger.get('sourceManifestSha256') == BUILD.sha(ROOT / 'source-manifest.json')
                and ledger.get('sourceFilesSha256') == {name: source['stagedFilesSha256'][name] for name in FRESH.SOURCE_SET},
                'Exact fresh build/source ledger required')
    if action not in APK_ACTIONS:
        return source, ledger, None
    require(ledger is not None, 'Build and retain the real product APK ledger before installing')
    name, package, cert = APK_ACTIONS[action]
    entries = [value for value in ledger['apks'] if value.get('fileName') == name]
    require(len(entries) == 1, 'Exactly one reviewed product APK variant required')
    entry = entries[0]
    require(entry.get('applicationId') == package and entry.get('signingCertificateSha256') == cert
            and entry.get('fixtureTarget') == FRESH.FIXTURE
            and entry.get('actualProductFlutterRuntime') is True
            and entry.get('actualNativePasskeyAndVaultPlugins') is True
            and entry.get('nativeDebugSymbolsStripped') is True,
            'Actual product fixture and native plugins required')
    settings = dict(config, AUTH_B3B4_PACKAGE=package)
    require(entry.get('configSha256') == FRESH.digest(json.dumps(settings, sort_keys=True).encode()),
            'Compiled fixture environment changed')
    path = ROOT / name
    require(path.is_file() and not path.is_symlink() and BUILD.sha(path) == entry['apkSha256']
            and path.stat().st_size == entry['apkBytes'] and path.stat().st_size <= 150_000_000,
            'Reviewed product APK bytes changed')
    verify_apk(path, package, cert)
    validate_pub_route(entry)
    if action == 'install-bad-signature':
        approved = next(value for value in ledger['apks'] if value['fileName'] == 'b3b4-acceptance.apk')
        approved_path = ROOT / approved['fileName']
        require(BUILD.sha(approved_path) == approved['apkSha256'], 'Approved contrast artifact changed')
        contrast = BUILD.exact_payload_contrast(approved_path, path)
        require(entry.get('signatureOnlyPayloadMatches') is True
                and entry.get('signatureOnlyPayloadSha256') == contrast['signatureOnlyPayloadSha256']
                and entry.get('signatureOnlySourceApkSha256') == approved['apkSha256'],
                'Wrong-certificate variant must only re-sign the exact approved payload')
    for name in FRESH.SOURCE_SET:
        if name.startswith(('apps/', 'packages/')):
            path = ROOT / 'driver' / name
            require(path.is_file() and not path.is_symlink() and BUILD.sha(path) == source['stagedFilesSha256'][name],
                    'Windows driver product source changed: ' + name)
    return source, ledger, entry


def installed(package):
    require(package in (*HISTORICAL, FRESH.PACKAGE, FRESH.MISSING_PACKAGE), 'Owned package only')
    raw = adb('shell', 'cmd', 'package', 'list', 'packages', '--user', '0', package).decode()
    names = [line.strip() for line in raw.splitlines() if line.strip()]
    require(all(re.fullmatch(r'package:[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+', name) for name in names),
            'Successful exact package enumeration required')
    if 'package:' + package not in names:
        return None
    path = adb('shell', 'pm', 'path', '--user', '0', package).decode().strip()
    require(re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk', path) is not None,
            'Exact single installed base APK required')
    digest = adb('shell', 'sha256sum', path[8:]).decode().split()[0]
    require(re.fullmatch(r'[a-f0-9]{64}', digest) is not None, 'Exact installed APK hash required')
    return digest


def historical_guard():
    require(adb('get-state').strip() == b'device', 'Original vivo must be connected and authorized')
    values = {package: installed(package) for package in HISTORICAL}
    require(values == HISTORICAL, 'Historical phone application changed; preserve every package')
    return values


def private_json(package, relative):
    require(package in (FRESH.PACKAGE, FRESH.MISSING_PACKAGE)
            and relative in ('files/owned-acceptance-passkey.json', 'files/owned-device-driver-stage.json',
                             'files/owned-b3b4-rp-partial.json', DIAG.ADMISSION), 'Bounded non-secret witness path only')
    for flag in ('-L', '-e'):
        result = subprocess.run([str(ADB), '-s', FRESH.DEVICE, 'shell', 'run-as', package, 'test', flag, relative],
                                capture_output=True, timeout=25)
        require(result.returncode in (0, 1) and result.stdout == b'' and result.stderr == b'',
                'Private witness absence was not established; do not replace the application')
        if flag == '-L':
            require(result.returncode == 1, 'Preserve unexpected witness symlink')
        elif result.returncode == 1:
            return None
    raw = adb('shell', 'run-as', package, 'cat', relative)
    require(0 < len(raw) <= 4096, 'Bounded private witness required')
    value = json.loads(raw)
    require(isinstance(value, dict), 'Private witness must be an object')
    return value


def native_terminal(state):
    if state is None:
        return
    require(type(state.get('pid')) is int and state['pid'] > 0, 'Witness process identity required')
    for name in COUNTERS:
        require(type(state.get(name, 0)) is int and 0 <= state.get(name, 0) <= 1000, 'Bounded native counters required')
    # Both events release local ownership and send CancellationSignal; neither
    # proves that the provider finished. Its later callback is uncorrelated in
    # this aggregate witness, so equal completion counters cannot clear UNKNOWN.
    require(state.get('nativeTimeout', 0) == 0 and state.get('nativeCancelled', 0) == 0,
            'Preserve a locally timed out or cancelled native UNKNOWN; local completion is not a provider terminal callback')
    require(state.get('nativeBegun', 0) == sum(state.get(name, 0)
            for name in ('nativeSucceeded', 'nativeErrored', 'nativeCancelled')),
            'Preserve an active or uncertain native operation; wait for its actual terminal callback')


def no_active_runner():
    require(os.name == 'nt', 'Use the reviewed Windows host operator')
    script = "$v=Get-CimInstance Win32_Process | Where-Object {$_.ProcessId -ne $PID -and $_.Name -match '^(pwsh|powershell|python|python3|dart)(\\.exe)?$' -and $_.CommandLine -match '(run-android-b3-b4\\.ps1|run-android-live-device\\.ps1|control-android-b3-b4-device\\.py)'}; @($v | Select-Object -ExpandProperty ProcessId) | ConvertTo-Json -Compress"
    result = command(['pwsh', '-NoProfile', '-Command', script]).decode().strip()
    require(result in ('', '[]'), 'Preserve the live fixed runner/witness before installing or switching a provider')


def device_ui_observation():
    output = adb('shell', 'dumpsys', 'activity', 'activities')
    require(isinstance(output, bytes) and 0 < len(output) <= 1024 * 1024 and b'\x00' not in output,
            'Valid bounded activity inventory required')
    try:
        raw = output.decode('utf-8')
    except UnicodeError as error:
        raise RuntimeError('Valid bounded activity inventory required') from error
    require('ACTIVITY MANAGER ACTIVITIES' in raw and ('Task{' in raw or 'ActivityRecord{' in raw),
            'Valid bounded activity inventory required')
    require(not re.search(r'(?im)^\s*(?:error:|permission denial|exception|securityexception|can.t find service)', raw),
            'Failed activity inventory cannot establish native termination')
    foreground = re.search(r'topResumedActivity=[^\n]*? ([A-Za-z0-9._]+/[A-Za-z0-9._]+)', raw)
    component = foreground[1] if foreground else None
    classes = ('CredentialSelectorActivity', 'fido.registration.ui.RegistrationActivity',
               'fido.authentication.ui.AuthenticationActivity', 'common.api.GoogleApiActivity')
    rows = [line for line in raw.splitlines() if 'ActivityRecord{' in line
            and any(name in line for name in classes)]
    # Android retains a last-paused pointer after a finished selector has been
    # detached from its task and display. Only this exact removed reference is
    # excluded; a task member, foreground record or ambiguous shape still blocks.
    detached = [line for line in rows if re.fullmatch(
        r'\s*mLastPausedActivity: ActivityRecord\{[0-9a-f]+ u0 '
        r'com\.vivo\.credentialmanager/\.CredentialSelectorActivity t-1 d-1 f\}\}\s*', line)]
    rows = [line for line in rows if line not in detached]
    return dict(actualProviderComponent=component if component in PROVIDER_ACTIVITIES else None,
                actualProviderForeground=component in PROVIDER_ACTIVITIES,
                knownNativeActivityRows=len(rows), detachedFinishedProviderReferences=len(detached),
                accountUiExported=False)


def no_live_provider_ui():
    observed = device_ui_observation()
    require(observed['knownNativeActivityRows'] == 0 and observed['actualProviderForeground'] is False,
            'Preserve a remaining native provider task; terminal counters alone do not prove its UI/task ended')
    return observed


def consumed_diagnostic_retry(retirement_path):
    """Validate one explicitly retired debug-only timeout and its known retry.

    This never changes the old result, DIAG.unresolved_runs(), any product
    pending intent, or a fixed-case result. The exception is only an operator
    reviewed transition from this exact disposable diagnostic to the product.
    """
    retirement = read(retirement_path, 4096)
    old_run = retirement.get('runId')
    require(type(old_run) is str and re.fullmatch(r'gfd-[a-f0-9]{32}', old_run) is not None
            and retirement_path.name == old_run + '-diagnostic-retirement.json', 'Exact retired diagnostic run required')
    expected = {'schemaVersion', 'owner', 'scope', 'runId', 'applicationId', 'signingCertificateSha256',
        'apkSha256', 'startSha256', 'resultSha256', 'manifestSha256', 'evidenceSha256',
        'userRequestSha256', 'networkChange', 'originalTaskIds', 'localTaskSnapshotSha256',
        'originalLocalTasksAbsent', 'historicalNativeOutcomeUnknown', 'credentialMayExist',
        'nativeOutcomeResolved', 'productUnknownChanged', 'actualCSubmission', 'fixedCaseAcceptancePassed',
        'freshRetryBudget', 'freshChallengeAndUserRequired', 'hostRunnerSha256', 'recordedAtUnix'}
    require(set(retirement) == expected and type(retirement['schemaVersion']) is int and retirement['schemaVersion'] == 1
            and retirement['owner'] == DIAG.OWNER and retirement['scope'] == 'OPERATOR_RETIRED_DIAGNOSTIC_ONLY_UNKNOWN'
            and retirement['applicationId'] == FRESH.PACKAGE and retirement['signingCertificateSha256'] == FRESH.CERT,
            'Only the exact fresh standalone diagnostic retirement is admissible')
    for key in ('apkSha256', 'startSha256', 'resultSha256', 'manifestSha256', 'evidenceSha256',
                'userRequestSha256', 'localTaskSnapshotSha256', 'hostRunnerSha256'):
        require(type(retirement[key]) is str and re.fullmatch(r'[a-f0-9]{64}', retirement[key]) is not None,
                'Exact diagnostic retirement artifact hashes required')
    require(retirement['hostRunnerSha256'] == BUILD.sha(Path(DIAG.__file__)), 'Reviewed diagnostic host guard changed')
    for key in ('originalLocalTasksAbsent', 'historicalNativeOutcomeUnknown', 'credentialMayExist', 'freshChallengeAndUserRequired'):
        require(retirement[key] is True, 'Historical native uncertainty must remain explicit')
    for key in ('nativeOutcomeResolved', 'productUnknownChanged', 'actualCSubmission', 'fixedCaseAcceptancePassed'):
        require(retirement[key] is False, 'Diagnostic retirement cannot resolve a product UNKNOWN or claim C acceptance')
    require(type(retirement['freshRetryBudget']) is int and retirement['freshRetryBudget'] == 1,
            'Exactly one consumed fresh diagnostic retry required')
    require(type(retirement['recordedAtUnix']) is int and retirement['recordedAtUnix'] > 0,
            'Exact diagnostic retirement time required')
    cache = ROOT / 'google-direct-diagnostic'
    start_path, result_path = [cache / (old_run + '-' + suffix + '.json') for suffix in ('start', 'result')]
    start, result = read(start_path, 4096), read(result_path, 20000)
    retry_evidence_path = cache / (old_run + '-network-retry-evidence.json')
    retry_evidence = read(retry_evidence_path, 4096)
    require(BUILD.sha(start_path) == retirement['startSha256'] and BUILD.sha(result_path) == retirement['resultSha256']
            and BUILD.sha(retry_evidence_path) == retirement['evidenceSha256'], 'Original UNKNOWN/evidence bytes changed')
    DIAG.validate_network_retry_evidence(retry_evidence, start, result)
    for key in ('apkSha256', 'startSha256', 'resultSha256', 'manifestSha256', 'userRequestSha256', 'networkChange', 'originalTaskIds'):
        require(retirement[key] == retry_evidence[key], 'Retirement does not match the original diagnostic evidence')
    reservation_path = cache / (old_run + '-retry-reservation.json')
    reservation = read(reservation_path, 4096)
    expected_reservation = {'schemaVersion', 'owner', 'scope', 'retiredRunId', 'newRunId', 'authorizationSha256',
        'apkSha256', 'freshChallengeAndUserRequired', 'actualCSubmission', 'fixedCaseAcceptancePassed', 'recordedAtUnix'}
    authorization = BUILD.sha(retirement_path)
    new_run = reservation.get('newRunId')
    require(set(reservation) == expected_reservation and type(reservation['schemaVersion']) is int
            and reservation['schemaVersion'] == 1 and reservation['owner'] == DIAG.OWNER
            and reservation['scope'] == 'ONE_FRESH_DIAGNOSTIC_NETWORK_RETRY'
            and reservation['retiredRunId'] == old_run and reservation['authorizationSha256'] == authorization
            and reservation['apkSha256'] == retirement['apkSha256']
            and reservation['freshChallengeAndUserRequired'] is True
            and reservation['actualCSubmission'] is False and reservation['fixedCaseAcceptancePassed'] is False
            and type(new_run) is str and re.fullmatch(r'gfd-[a-f0-9]{32}', new_run) is not None and new_run != old_run,
            'Exact single-use fresh diagnostic reservation required')
    require(type(reservation['recordedAtUnix']) is int
            and reservation['recordedAtUnix'] >= retirement['recordedAtUnix'], 'Invalid consumed reservation time')
    new_start_path, new_result_path = [cache / (new_run + '-' + suffix + '.json') for suffix in ('start', 'result')]
    new_start, new_result = read(new_start_path, 4096), read(new_result_path, 20000)
    require(new_start.get('owner') == DIAG.OWNER and new_start.get('identityMode') == 'fresh'
            and new_start.get('runId') == new_run and new_start.get('retryOfRunId') == old_run
            and new_start.get('retryAuthorizationSha256') == authorization
            and new_start.get('applicationId') == FRESH.PACKAGE and new_start.get('signingCertificateSha256') == FRESH.CERT
            and new_start.get('apkSha256') == retirement['apkSha256']
            and new_start.get('mainApkSha256') == HISTORICAL[FRESH.MAIN_PACKAGE]
            and new_start.get('prepareOnly') is False and new_start.get('phase') == 'ni-d02'
            and new_start.get('variant') == 'control' and new_start.get('actualCSubmission') is False
            and new_start.get('fixedCaseAcceptancePassed') is False,
            'Retry start differs from the exact fresh diagnostic identity and one-use authorization')
    require(type(new_start.get('startedAtUnix')) is int and new_start['startedAtUnix'] >= reservation['recordedAtUnix']
            and new_start.get('uid') == start.get('uid')
            and new_start.get('hostRunnerSha256') == retirement['hostRunnerSha256'],
            'New diagnostic retry must retain the exact reviewed installed UID/host guard')
    require(re.fullmatch(r'[a-f0-9]{64}', new_start.get('nonceSha256', '')) is not None
            and new_start['nonceSha256'] != start['nonceSha256'], 'Original diagnostic nonce must never be replayed')
    DIAG.validate_report(new_result, new_run, new_start)
    require(new_result['finished'] is True and new_result['nativeOutcomeUnknown'] is False
            and new_result['prepareOnly'] is False and new_result['pendingIntentLaunched'] is True
            and new_result['actualCSubmission'] is False and new_result['fixedCaseAcceptancePassed'] is False,
            'The one fresh retry still has an unknown native outcome; preserve its installed diagnostic')
    return dict(scope='REVIEWED_DEBUG_DIAGNOSTIC_TO_PRODUCT_INSTALL_ONLY', retiredRunId=old_run,
        retryRunId=new_run, retirementReceiptSha256=authorization,
        retirementFileName=retirement_path.name, oldUnknownResultSha256=BUILD.sha(result_path),
        retryReservationSha256=BUILD.sha(reservation_path), retryStartSha256=BUILD.sha(new_start_path),
        knownRetryResultSha256=BUILD.sha(new_result_path), historicalNativeOutcomeUnknown=True,
        historicalCredentialMayExist=True, nativeOutcomeResolved=False, productUnknownChanged=False,
        actualCSubmission=False, fixedCaseAcceptancePassed=False)


def diagnostic_transition(pending, reviewed_sha256=None, action=None):
    if reviewed_sha256 is not None:
        require(action == 'install-approved' and re.fullmatch(r'[a-f0-9]{64}', reviewed_sha256) is not None,
                'Explicit diagnostic transition review is only for initial approved product installation')
        matches = []
        for path in (ROOT / 'google-direct-diagnostic').glob('gfd-*-diagnostic-retirement.json'):
            read(path, 4096)
            if BUILD.sha(path) == reviewed_sha256:
                matches.append(path)
        require(len(matches) == 1, 'Exactly one explicitly reviewed diagnostic retirement receipt required')
        transition = consumed_diagnostic_retry(matches[0])
    else:
        transition = None
        for path in (ROOT / 'b3b4-evidence').glob('install-approved-*-host-operation.json'):
            operation = read(path, 12000)
            receipt = operation.get('diagnosticTransition')
            if (operation.get('owner') == FRESH.TOKEN and operation.get('result') == 'PASS'
                    and operation.get('device') == FRESH.DEVICE and operation.get('deviceRunId') == FRESH.RUN
                    and operation.get('applicationId') == FRESH.PACKAGE
                    and operation.get('signingCertificateSha256') == FRESH.CERT
                    and operation.get('historicalPackagesBefore') == HISTORICAL
                    and operation.get('historicalPackagesAfter') == HISTORICAL
                    and operation.get('sourceManifestSha256') == BUILD.sha(ROOT / 'source-manifest.json')
                    and isinstance(receipt, dict) and isinstance(receipt.get('retirementFileName'), str)
                    and re.fullmatch(r'gfd-[a-f0-9]{32}-diagnostic-retirement\.json', receipt['retirementFileName'])):
                value = consumed_diagnostic_retry(ROOT / 'google-direct-diagnostic' / receipt['retirementFileName'])
                require(value == receipt, 'Retained explicitly reviewed diagnostic transition changed')
                transition = value
                break
        require(transition is not None, 'Preserve unresolved Google diagnostic start; review its exact consumed retry transition first')
    require(pending == [transition['retiredRunId']], 'Additional unknown diagnostic runs must remain blocked')
    return transition


def diagnostic_guard(ledger, reviewed_sha256=None, action=None):
    DIAG.configure_environment(argparse.Namespace(host=str(ROOT), adb=str(ADB), device=FRESH.DEVICE,
        package=FRESH.PACKAGE, certificate_sha256=FRESH.CERT, main_apk_sha256=HISTORICAL[FRESH.MAIN_PACKAGE]))
    pending = DIAG.unresolved_runs()
    transition = diagnostic_transition(pending, reviewed_sha256, action) if pending else None
    require(reviewed_sha256 is None or transition is not None, 'Do not apply an unnecessary diagnostic retirement exception')
    current = installed(FRESH.PACKAGE)
    if current is not None:
        require(current in reviewed_installed(ledger, FRESH.PACKAGE), 'Preserve unknown installed fresh APK')
        require(private_json(FRESH.PACKAGE, DIAG.ADMISSION) is None,
                'Retain diagnostic admission until its original runner safely cleans up')
    if transition is not None:
        retirement = read(ROOT / 'google-direct-diagnostic' / transition['retirementFileName'], 4096)
        DIAG.original_local_tasks_absent(adb('shell', 'dumpsys', 'activity', 'activities'), retirement['originalTaskIds'])
    return transition


def reviewed_installed(ledger, package):
    reviewed = {}
    if ledger is not None:
        for entry in ledger['apks']:
            if entry.get('applicationId') == package:
                allowed = {FRESH.CERT} if package == FRESH.MISSING_PACKAGE else {FRESH.CERT, BUILD.BAD_CERT}
                require(entry.get('signingCertificateSha256') in allowed, 'Unknown fresh package certificate in ledger')
                reviewed[entry['apkSha256']] = entry['signingCertificateSha256']
    if package == FRESH.PACKAGE:
        for dirname in ('google-direct-diagnostic', 'google-direct-diagnostic-attempt04'):
            folder = ROOT / dirname
            if not (folder / 'manifest.json').exists():
                continue
            value = read(folder / 'manifest.json')
            require(value.get('owner') == DIAG.OWNER and value.get('result') == 'PASS'
                    and value.get('identityMode') == 'fresh' and value.get('applicationId') == package
                    and value.get('signingCertificateSha256') == FRESH.CERT and value.get('flutterPayloadAbsent') is True,
                    'Only the exact owned fresh standalone diagnostic may be replaced')
            apk = folder / 'google-fido-diagnostic.apk'
            require(BUILD.sha(apk) == value['apkSha256'], 'Owned diagnostic APK changed')
            verify_apk(apk, package, FRESH.CERT)
            reviewed[value['apkSha256']] = FRESH.CERT
    return reviewed


def control_passed(ledger):
    evidence = ROOT / 'b3b4-evidence'
    approved = next(entry for entry in ledger['apks'] if entry['fileName'] == 'b3b4-acceptance.apk')
    for suffix in ('report', 'device', 'sql', 'version'):
        filename = 'ni-d02-control.json' if suffix == 'sql' else 'ni-d02-control-' + suffix + '.json'
        value = read(evidence / filename)
        require(value.get('phase') == 'ni-d02' and value.get('variant') == 'control', 'Exact fresh control evidence required')
        if suffix == 'report':
            require(value.get('applicationId') == FRESH.PACKAGE and value.get('actualApp') is True
                    and value.get('actualCV') is True and value.get('nativeVault') is True
                    and value.get('approvedPackageAndCertificateActualBinding') is True,
                    'Actual approved product binding must pass before the association negatives')
        elif suffix == 'version':
            require(value.get('applicationId') == FRESH.PACKAGE and value.get('apkSha256') == approved['apkSha256'],
                    'Positive control APK identity changed')
        else:
            require(value.get('result') == 'PASS', 'Independent control device and SQL acceptance must pass')
            if suffix == 'device':
                require(value.get('apkSha256') == approved['apkSha256'] and value.get('applicationId') == FRESH.PACKAGE,
                        'Control device witness APK identity changed')


def rp_terminal_guard(package, previous_certificate=FRESH.CERT, current_hash=None):
    if package != FRESH.PACKAGE or not (ROOT / 'b3b4-evidence/ni-d01-main-version.json').exists():
        return None
    if previous_certificate == BUILD.BAD_CERT:
        # The prior approved->bad certificate change deleted the fresh vault.
        # Its journal retained this bounded terminal witness before uninstall.
        for path in (ROOT / 'b3b4-evidence').glob('install-bad-signature-*-host-operation.json'):
            operation = read(path, 8192)
            witness = operation.get('rpTerminalWitness')
            if (operation.get('owner') == FRESH.TOKEN and operation.get('device') == FRESH.DEVICE
                    and operation.get('deviceRunId') == FRESH.RUN and operation.get('applicationId') == package
                    and operation.get('targetApkSha256') == current_hash
                    and operation.get('signingCertificateSha256') == BUILD.BAD_CERT
                    and operation.get('onlyFreshAcceptancePackageUninstalled') is True
                    and operation.get('historicalPackagesBefore') == HISTORICAL
                    and operation.get('sourceManifestSha256') == BUILD.sha(ROOT / 'source-manifest.json')
                    and isinstance(witness, dict) and witness.get('phase') == 'ni-d01'
                    and witness.get('actualServerWrongRpHashRejected422') is True
                    and witness.get('originalResultQueriedWithoutProofReplay') is True
                    and witness.get('rawProofStored') is False):
                return dict(witness, retainedBeforeFreshCertificateChange=True)
        raise RuntimeError('Retained original RP terminal witness is required before restoring the fresh certificate')
    partial = private_json(package, 'files/owned-b3b4-rp-partial.json')
    require(partial is not None and partial.get('phase') == 'ni-d01'
            and partial.get('actualServerWrongRpHashRejected422') is True
            and partial.get('originalResultQueriedWithoutProofReplay') is True and partial.get('rawProofStored') is False,
            'Preserve the original NI-D01 server anchor until its expiry reconciliation is terminal')
    return {name: partial.get(name) for name in ('pid', 'phase', 'clientPinnedRpRejectedWithoutNativeStart',
            'actualNativeWrongRpAssociationRejected', 'actualServerWrongRpHashRejected422',
            'originalResultQueriedWithoutProofReplay', 'rawProofStored')}


def settings():
    value = {key: adb('shell', 'settings', 'get', 'secure', key).decode().strip() for key in KEYS}
    validate_settings(value)
    return value


def validate_settings(value):
    require(set(value) == set(KEYS), 'Exact provider settings keys required')
    known = {GOOGLE, VIVO, GOOGLE.replace('com.google.android.gms/com.google.android.gms.', 'com.google.android.gms/.'),
             VIVO.replace('com.vivo.cipherchain/com.vivo.cipherchain.', 'com.vivo.cipherchain/.')}
    for key in KEYS[:2]:
        require(type(value[key]) is str and (value[key] == 'null'
                or (len(value[key].split(':')) <= 2 and all(part in known for part in value[key].split(':')))),
                'Unknown credential provider setting; preserve it')
    require(value['autofill_service'] in (GOOGLE_AUTOFILL, VIVO_AUTOFILL, 'null'),
            'Unknown autofill provider setting; preserve it')


def set_settings(target):
    validate_settings(target)
    for key, value in target.items():
        if value == 'null':
            adb('shell', 'settings', 'delete', 'secure', key)
        else:
            adb('shell', 'settings', 'put', 'secure', key, value)
    require(settings() == target, 'Actual provider settings do not match the explicit reviewed target')


def provider_target(action, original, with_autofill):
    if action == 'provider-restore':
        return dict(original)
    google = action == 'provider-google'
    provider = GOOGLE if google else VIVO
    target = dict(original, credential_service=provider, credential_service_primary=provider)
    if with_autofill:
        target['autofill_service'] = GOOGLE_AUTOFILL if google else VIVO_AUTOFILL
    return target


def provider_operation(action, with_autofill, record, journal):
    evidence = ROOT / 'b3b4-evidence'
    path = evidence / 'fresh-original-provider-settings.json'
    before = settings()
    if path.exists():
        backup = read(path, 4096)
        require(backup.get('owner') == FRESH.TOKEN and backup.get('device') == FRESH.DEVICE
                and backup.get('historicalPackagesSha256') == HISTORICAL,
                'Exact immutable original provider backup required')
        validate_settings(backup['originalSettings'])
        original = backup['originalSettings']
    else:
        require(action != 'provider-restore', 'Original provider backup is required for restore')
        original = before
        write_new(path, dict(owner=FRESH.TOKEN, device=FRESH.DEVICE, originalSettings=original,
            historicalPackagesSha256=HISTORICAL, accountsInspected=False, credentialsExported=False,
            createdAtUnix=int(time.time())))
    target = provider_target(action, original, with_autofill)
    # Restrict restoration to the exact original or our two explicit temporary
    # targets, including interrupted per-key writes. Do not clobber another app.
    google = provider_target('provider-google', original, True)
    vivo = provider_target('provider-vivo', original, True)
    require(all(before[key] in (original[key], google[key], vivo[key]) for key in KEYS),
            'Provider state changed outside the reviewed switch; preserve it')
    if action != 'provider-restore':
        credential = GOOGLE if action == 'provider-google' else VIVO
        services = adb('shell', 'cmd', 'package', 'query-services', '--brief', '-a',
                       'android.service.credentials.CredentialProviderService').decode().splitlines()
        short = credential.split('/')[0] + '/.' + credential.split('/')[1].removeprefix(credential.split('/')[0] + '.')
        require(any(line.strip() in (credential, short) for line in services), 'Exact known installed credential service required')
        if with_autofill:
            services = adb('shell', 'cmd', 'package', 'query-services', '--brief', '-a',
                           'android.service.autofill.AutofillService').decode().splitlines()
            require(target['autofill_service'] in [line.strip() for line in services], 'Exact known installed autofill service required')
    record.update(originalSettings=original, beforeSettings=before, targetSettings=target,
                  originalBackupSha256=BUILD.sha(path), settingsOnly=True, accountsInspected=False,
                  credentialsExported=False, hostDidNotAuthenticate=True)
    FRESH.write_json(journal, record)
    set_settings(target)
    record['actualVerifiedSettings'] = settings()


def install_operation(action, ledger, entry, record, journal):
    filename, package, cert = APK_ACTIONS[action]
    approved_hashes = reviewed_installed(ledger, package)
    current = installed(package)
    require(current is None or current in approved_hashes, 'Unknown installed fresh APK must be preserved')
    if action in ('install-bad-signature', 'install-unassociated'):
        control_passed(ledger)
    if current is not None:
        native_terminal(private_json(package, 'files/owned-acceptance-passkey.json'))
    record.update(applicationId=package, beforeApkSha256=current, targetApkSha256=entry['apkSha256'],
        signingCertificateSha256=cert, historicalPackagesUntouched=True, privateVaultExported=False,
        onlyFreshPackageMayBeUninstalled=True, actualFullCaseAcceptancePassed=False)
    FRESH.write_json(journal, record)
    if current != entry['apkSha256']:
        if current is not None and approved_hashes[current] != cert:
            require(package == FRESH.PACKAGE, 'Only the owned fresh acceptance package may change certificate')
            record['rpTerminalWitness'] = rp_terminal_guard(package, approved_hashes[current], current)
            FRESH.write_json(journal, record)
            require(adb('uninstall', package, timeout=240).strip() == b'Success', 'Owned fresh uninstall did not confirm success')
            require(installed(package) is None, 'Owned fresh package absence was not established')
            record['onlyFreshAcceptancePackageUninstalled'] = True
            FRESH.write_json(journal, record)
        result = adb('install', '--no-streaming', '-t', '-r', str(ROOT / filename), timeout=240)
        require(install_success(result), 'Owned fresh install did not confirm success; do not replay an uncertain action')
    require(installed(package) == entry['apkSha256'], 'Actual installed fresh product hash changed')
    if cert == FRESH.CERT:
        owner = ROOT / 'driver/apps/mobile/.device-app-owner'
        expected = FRESH.DEVICE + '|' + FRESH.RUN
        if owner.exists():
            require(not owner.is_symlink() and owner.read_text() == expected, 'Preserve unknown driver owner')
        else:
            with owner.open('x', encoding='utf-8', newline='') as out:
                out.write(expected)
        record['reviewedDriverOwnerCreated'] = True
    record['installedApkSha256'] = installed(package)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=(*APK_ACTIONS, 'provider-google', 'provider-vivo', 'provider-restore', 'status'))
    parser.add_argument('--with-autofill', action='store_true', help='Explicitly switch the known autofill service too')
    parser.add_argument('--execute', action='store_true', help='Run the reviewed device operation; never authenticates')
    parser.add_argument('--reviewed-diagnostic-retirement-sha256',
        help='Explicit initial install-approved review of one retired debug-only timeout plus its single known retry')
    args = parser.parse_args(argv)
    require(__debug__, 'Optimized execution disables imported diagnostic assertions; refuse device operations')
    require(args.reviewed_diagnostic_retirement_sha256 is None or args.action == 'install-approved',
            'Explicit diagnostic transition review is only for initial approved product installation')
    require(not args.with_autofill or args.action in ('provider-google', 'provider-vivo'), 'Autofill flag requires an explicit provider switch')
    source, ledger, entry = validate_host(args.action)
    if not args.execute:
        print('REVIEWED: ' + args.action + '; phone operation NOT_RUN; add --execute to operate the owned device')
        return
    DIAG.configure_environment(argparse.Namespace(host=str(ROOT), adb=str(ADB), device=FRESH.DEVICE,
        package=FRESH.PACKAGE, certificate_sha256=FRESH.CERT, main_apk_sha256=HISTORICAL[FRESH.MAIN_PACKAGE]))
    with DIAG.OperationLock():
        originals = historical_guard()
        if args.action == 'status':
            print(json.dumps(dict(owner=FRESH.TOKEN, device=FRESH.DEVICE, actualSettings=settings(),
                deviceRunId=FRESH.RUN, sourceManifestSha256=BUILD.sha(ROOT / 'source-manifest.json'),
                actualUiObservation=device_ui_observation(), historicalPackagesSha256=originals,
                hostDidNotAuthenticate=True, fixedCaseAcceptancePassed=False)))
            return
        transition = diagnostic_guard(ledger, args.reviewed_diagnostic_retirement_sha256, args.action)
        no_active_runner()
        ui = no_live_provider_ui()
        for package in (FRESH.PACKAGE, FRESH.MISSING_PACKAGE):
            current = installed(package)
            if current is not None:
                require(current in reviewed_installed(ledger, package), 'Unknown fresh installed package must be preserved')
                native_terminal(private_json(package, 'files/owned-acceptance-passkey.json'))
        operation = args.action + '-' + uuid.uuid4().hex
        path = ROOT / 'b3b4-evidence' / (operation + '-host-operation.json')
        record = dict(owner=FRESH.TOKEN, operationId=operation, action=args.action, device=FRESH.DEVICE,
            deviceRunId=FRESH.RUN, sourceManifestSha256=BUILD.sha(ROOT / 'source-manifest.json'),
            operatorSourceSha256=BUILD.sha(Path(__file__)), historicalPackagesBefore=originals,
            beforeUiObservation=ui,
            diagnosticTransition=transition,
            startedAtUnix=int(time.time()), result='STARTED', fixedCaseAcceptancePassed=False,
            hostDidNotAuthenticate=True)
        watcher_overlay = validate_host_watcher_overlay(source)
        if watcher_overlay is not None:
            record['hostRuntimeWatcherOverlay'] = watcher_overlay
        write_new(path, record)
        try:
            if args.action in APK_ACTIONS:
                install_operation(args.action, ledger, entry, record, path)
            else:
                provider_operation(args.action, args.with_autofill, record, path)
            record['historicalPackagesAfter'] = historical_guard()
            record.update(result='PASS', finishedAtUnix=int(time.time()))
        except BaseException as error:
            record.update(result='FAIL', failureType=type(error).__name__, operationMustBeInspectedBeforeRetry=True)
            raise
        finally:
            FRESH.write_json(path, record)
        print('PASS: ' + args.action + '; original two APKs verified; authentication/acceptance not claimed')


if __name__ == '__main__':
    main()
