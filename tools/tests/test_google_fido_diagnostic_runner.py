"""Host-only safety checks; no APK install, device API or ceremony is executed."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    'google_fido_runner', Path(__file__).parents[1] / 'run-google-passkey-diagnostic.py')
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
RUN = 'gfd-' + '1' * 32
APK_HASH = 'a' * 64


def report(stage='REGISTER_PREPARED', launched=False, unknown=False, finished=True):
    event = {'stage': stage, 'classification': 'BOUNDED_TEST_OUTCOME',
             'pid': 42, 'elapsedRealtimeMs': 1000}
    return {'schemaVersion': 1, 'owner': runner.OWNER, 'runId': RUN, 'pid': 42,
            'phase': 'ni-d02', 'variant': 'control', 'applicationId': runner.PACKAGE,
            'apkSha256': APK_HASH, 'prepareOnly': not launched,
            'pendingIntentLaunched': launched, 'keyguardSecure': True,
            'actualCSubmission': False, 'fixedCaseAcceptancePassed': False,
            'stages': [event], 'stage': stage, 'classification': event['classification'],
            'finished': finished, 'nativeOutcomeUnknown': unknown}


class DiagnosticReportTests(unittest.TestCase):
    def checked(self, value):
        return runner.validate_report(value, RUN, {'apkSha256': APK_HASH})

    def test_prepare_and_local_destruction_without_ui_are_resolved(self):
        self.checked(report())
        self.checked(report('LOCAL_ACTIVITY_DESTROYED'))

    def test_generic_cancellation_and_launched_lifecycle_end_remain_unresolved(self):
        for stage in ('REGISTER_UI_RESULT_WITHOUT_TYPED_ERROR', 'LOCAL_ACTIVITY_DESTROYED',
                      'REGISTER_UI_STARTED_TIMEOUT', 'REGISTER_UI_RESULT_DECODE_FAILED'):
            value = report(stage, launched=True, unknown=True)
            self.checked(value)
            value['nativeOutcomeUnknown'] = False
            with self.assertRaises(AssertionError):
                self.checked(value)

    def test_only_typed_error_or_actual_ok_attestation_resolves_native_launch(self):
        error = report('REGISTER_UI_ERROR', launched=True)
        error['stages'][0].update(errorEnum='SECURITY_ERR', authenticatorErrorCode=18)
        self.checked(error)
        error['stages'][0].pop('errorEnum')
        with self.assertRaises(AssertionError):
            self.checked(error)
        success = report('REGISTER_UI_COMPLETED', launched=True)
        success['stages'][0].update(credentialResponsePresent=True, activityResultCode=-1)
        self.checked(success)
        success['stages'][0]['activityResultCode'] = 0
        with self.assertRaises(AssertionError):
            self.checked(success)

    def test_incomplete_wrong_identity_and_coerced_completion_reports_are_rejected(self):
        original = report()
        for key, value in (('finished', 1), ('nativeOutcomeUnknown', 0), ('schemaVersion', True),
                           ('actualCSubmission', True), ('fixedCaseAcceptancePassed', True),
                           ('applicationId', 'other.package'), ('apkSha256', 'b' * 64)):
            changed = copy.deepcopy(original)
            changed[key] = value
            with self.assertRaises(AssertionError):
                self.checked(changed)
        original.pop('pendingIntentLaunched')
        with self.assertRaises(AssertionError):
            self.checked(original)

    def test_terminal_record_stays_blocking_when_native_result_is_unknown(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-google-report-') as folder:
            cache = Path(folder)
            start = {'owner': runner.OWNER, 'runId': RUN, 'apkSha256': APK_HASH, 'prepareOnly': False}
            (cache / (RUN + '-start.json')).write_text(json.dumps(start))
            result = report('LOCAL_ACTIVITY_DESTROYED', launched=True, unknown=True)
            output = cache / (RUN + '-result.json')
            output.write_text(json.dumps(result))
            with mock.patch.object(runner, 'CACHE', cache), mock.patch.object(runner, 'IDENTITY_MODE', 'legacy'):
                self.assertEqual(runner.unresolved_runs(), [RUN])
                result['nativeOutcomeUnknown'] = False
                output.write_text(json.dumps(result))
                with self.assertRaises(AssertionError):
                    runner.unresolved_runs()


class DiagnosticEnvironmentTests(unittest.TestCase):
    def test_absent_package_is_confirmed_before_failing_pm_path(self):
        package = runner.LEGACY_PACKAGE + '20261012'
        for enumeration in (b'', ('package:' + package + '.other\n').encode()):
            calls = []

            def device_command(command, **unused):
                calls.append(command)
                if 'list' in command:
                    return subprocess.CompletedProcess(command, 0, enumeration, b'')
                # Android returns status 1 for pm path of an absent package.
                return subprocess.CompletedProcess(command, 1, b'', b'Package not found')

            with self.subTest(enumeration=enumeration), mock.patch.object(runner.subprocess, 'run', side_effect=device_command):
                self.assertIsNone(runner.installed_hash(package, allow_absent=True))
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][-8:], ['shell', 'cmd', 'package', 'list', 'packages', '--user', '0', package])

    def test_failed_or_malformed_package_query_is_never_treated_as_absence(self):
        for status, output in ((1, b''), (0, b'Error: cannot access user 0\n')):
            result = subprocess.CompletedProcess([], status, output, b'')
            with self.subTest(status=status, output=output), mock.patch.object(runner.subprocess, 'run', return_value=result):
                with self.assertRaises(AssertionError):
                    runner.installed_hash(runner.PACKAGE, allow_absent=True)

    def test_present_package_pm_path_failure_is_never_treated_as_absence(self):
        def device_command(command, **unused):
            if 'list' in command:
                return subprocess.CompletedProcess(command, 0, ('package:' + runner.PACKAGE + '\n').encode(), b'')
            return subprocess.CompletedProcess(command, 1, b'', b'Path query failed')

        with mock.patch.object(runner.subprocess, 'run', side_effect=device_command):
            with self.assertRaises(AssertionError):
                runner.installed_hash(runner.PACKAGE, allow_absent=True)

    def test_present_package_hash_requires_successful_user_zero_path(self):
        calls = []

        def device_command(command, **unused):
            calls.append(command)
            if 'list' in command:
                data = ('package:' + runner.PACKAGE + '\n').encode()
            elif 'path' in command:
                data = b'package:/data/app/owned/base.apk\n'
            else:
                data = (APK_HASH + '  /data/app/owned/base.apk\n').encode()
            return subprocess.CompletedProcess(command, 0, data, b'')

        with mock.patch.object(runner.subprocess, 'run', side_effect=device_command):
            self.assertEqual(runner.installed_hash(runner.PACKAGE, allow_absent=True), APK_HASH)
        self.assertEqual(calls[1][-6:], ['shell', 'pm', 'path', '--user', '0', runner.PACKAGE])

    def test_fresh_identity_admission_preserves_both_original_packages(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-google-environment-') as folder:
            root = Path(folder)
            cache = root / 'google-direct-diagnostic'
            cache.mkdir()
            (root / 'OWNER').write_text('HNUHOLE_ANDROID_MATRIX_V1')
            (cache / 'OWNER').write_text(runner.OWNER)
            source = root / 'source.txt'
            source.write_text('synthetic source')
            apk = cache / 'synthetic.apk'
            apk.write_bytes(b'synthetic APK host fixture')
            apk_hash = hashlib.sha256(apk.read_bytes()).hexdigest()
            package = runner.LEGACY_PACKAGE + '20261012'
            manifest = {'owner': runner.OWNER, 'result': 'PASS', 'identityMode': 'fresh',
                        'applicationId': package, 'activity': runner.ACTIVITY,
                        'signingCertificateSha256': runner.CERT, 'releaseExcluded': True,
                        'apkPath': str(apk), 'apkSha256': apk_hash,
                        'sourceFilesSha256': {'source.txt': hashlib.sha256(source.read_bytes()).hexdigest()}}
            (cache / 'manifest.json').write_text(json.dumps(manifest))
            installed = {'org.hnuhole.hnuhole_mobile': runner.MAIN_APK,
                         runner.LEGACY_PACKAGE: runner.BASE_APK, package: None}
            with mock.patch.multiple(runner, HOST=root, CACHE=cache, REPO=root,
                                     PACKAGE=package, IDENTITY_MODE='fresh'), \
                 mock.patch.object(runner, 'adb', return_value=b'device'), \
                 mock.patch.object(runner, 'installed_hash', side_effect=lambda name, **unused: installed[name]):
                self.assertIsNone(runner.validate()[2])
                installed[package] = 'f' * 64
                with self.assertRaises(AssertionError):
                    runner.validate()
                installed[package] = None
                installed[runner.LEGACY_PACKAGE] = 'e' * 64
                with self.assertRaises(AssertionError):
                    runner.validate()

    def test_operation_lock_refuses_overlap_and_releases_on_failure(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-google-lock-') as folder:
            host = Path(folder)
            cache = host / 'google-direct-diagnostic'
            cache.mkdir()
            (host / 'OWNER').write_text('HNUHOLE_ANDROID_MATRIX_V1')
            (cache / 'OWNER').write_text(runner.OWNER)
            with mock.patch.multiple(runner, HOST=host, CACHE=cache):
                with self.assertRaisesRegex(RuntimeError, 'synthetic failure'):
                    with runner.OperationLock():
                        with self.assertRaisesRegex(RuntimeError, 'Another owned diagnostic'):
                            with runner.OperationLock():
                                self.fail('Overlapping diagnostic lock acquired')
                        raise RuntimeError('synthetic failure')
                with runner.OperationLock():
                    pass


class DiagnosticAdmissionTests(unittest.TestCase):
    def test_private_absence_requires_exact_clean_test_exit(self):
        for status, expected in ((0, True), (1, False)):
            result = subprocess.CompletedProcess([], status, b'', b'')
            with mock.patch.object(runner.subprocess, 'run', return_value=result):
                self.assertIs(runner.private_test('-e', runner.ADMISSION), expected)
        for status, out, error in ((1, b'', b'device offline'), (2, b'', b''),
                                   (0, b'Unexpected output', b''), (1, b'run-as failed', b'')):
            with self.subTest(status=status, out=out, error=error), \
                 mock.patch.object(runner.subprocess, 'run', return_value=subprocess.CompletedProcess([], status, out, error)):
                with self.assertRaises(AssertionError):
                    runner.private_test('-e', runner.ADMISSION)
        with mock.patch.object(runner.subprocess, 'run', side_effect=subprocess.TimeoutExpired('adb', 20)):
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.private_test('-e', runner.ADMISSION)

    def test_fresh_private_directory_is_created_before_use_and_symlinks_rejected(self):
        with mock.patch.object(runner, 'private_test', side_effect=[False, False, True, False]), \
             mock.patch.object(runner, 'adb') as device:
            runner.ensure_private_directory()
            device.assert_called_once_with('shell', 'run-as', runner.PACKAGE, 'mkdir', '-m', '700', 'no_backup')
        with mock.patch.object(runner, 'private_test', return_value=True), mock.patch.object(runner, 'adb') as device:
            with self.assertRaises(AssertionError):
                runner.ensure_private_directory()
            device.assert_not_called()
        with mock.patch.object(runner, 'private_test', return_value=True), mock.patch.object(runner, 'adb') as device:
            with self.assertRaises(AssertionError):
                runner.read_private(runner.ADMISSION)
            device.assert_not_called()

    def simulate_start_failure(self, folder, fail_at):
        cache = Path(folder)
        calls = []
        admission = {}

        def device(*args, **kwargs):
            calls.append(args)
            if 'tee' in args:
                admission.update(json.loads(kwargs['input_bytes']))
                if fail_at == 'tee':
                    raise AssertionError('synthetic admission write failure')
                return kwargs['input_bytes']
            if 'am' in args:
                raise subprocess.TimeoutExpired('am start', 20)
            return b''

        with mock.patch.multiple(runner, CACHE=cache), \
             mock.patch.object(runner, 'validate', return_value=({'apkSha256': APK_HASH}, Path('unused.apk'), APK_HASH)), \
             mock.patch.object(runner, 'unresolved_runs', return_value=[]), \
             mock.patch.object(runner, 'ensure_private_directory'), \
             mock.patch.object(runner, 'collect', return_value=None), \
             mock.patch.object(runner, 'private_test', return_value=False), \
             mock.patch.object(runner, 'uid', return_value=42), \
             mock.patch.object(runner, 'read_private', side_effect=lambda unused: json.dumps(admission).encode()), \
             mock.patch.object(runner, 'adb', side_effect=device):
            with self.assertRaises((AssertionError, subprocess.TimeoutExpired)):
                runner.run(SimpleNamespace(action='prepare'))
        return calls, list(cache.glob('gfd-*-start.json'))

    def test_failed_admission_retains_start_and_separate_host_abort_receipt(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-prelaunch-') as folder:
            calls, starts = self.simulate_start_failure(folder, 'tee')
            self.assertEqual(len(starts), 1)
            start = runner.read(starts[0])
            cache = Path(folder)
            receipt_path = cache / (start['runId'] + '-prelaunch-abort.json')
            self.assertTrue(receipt_path.exists())
            self.assertFalse(any('am' in call for call in calls))
            self.assertFalse((cache / (start['runId'] + '-result.json')).exists())
            with mock.patch.object(runner, 'CACHE', cache):
                runner.validate_prelaunch_abort(runner.read(receipt_path), start)
                self.assertEqual(runner.unresolved_runs(), [])
                changed = runner.read(receipt_path)
                changed['amStartInvoked'] = True
                receipt_path.write_text(json.dumps(changed))
                with self.assertRaises(AssertionError):
                    runner.unresolved_runs()

    def test_am_start_timeout_never_gets_prelaunch_abort_receipt(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-unknown-start-') as folder:
            calls, starts = self.simulate_start_failure(folder, 'am')
            self.assertEqual(len(starts), 1)
            self.assertTrue(any('am' in call for call in calls))
            self.assertEqual(list(Path(folder).glob('*-prelaunch-abort.json')), [])
            with mock.patch.object(runner, 'CACHE', Path(folder)):
                self.assertEqual(runner.unresolved_runs(), [runner.read(starts[0])['runId']])

    def historical_fixture(self, cache):
        start = {'owner': runner.OWNER, 'runId': RUN, 'applicationId': runner.PACKAGE,
                 'signingCertificateSha256': runner.CERT, 'apkSha256': APK_HASH,
                 'prepareOnly': True, 'nonceSha256': 'c' * 64,
                 'actualCSubmission': False, 'fixedCaseAcceptancePassed': False}
        start_path = cache / (RUN + '-start.json')
        start_path.write_text(json.dumps(start))
        build_path = cache / 'attempt05-build-manifest.json'
        build = {'owner': runner.OWNER, 'result': 'PASS', 'applicationId': runner.PACKAGE,
                 'signingCertificateSha256': runner.CERT, 'apkSha256': APK_HASH,
                 'sourceFilesSha256': {'tools/run-google-passkey-diagnostic.py': 'd' * 64}}
        build_path.write_text(json.dumps(build))
        evidence = {'schemaVersion': 1, 'owner': runner.OWNER, 'scope': 'REVIEWED_HOST_CONTROL_FLOW_FAILURE',
                    'runId': RUN, 'applicationId': runner.PACKAGE, 'signingCertificateSha256': runner.CERT,
                    'apkSha256': APK_HASH, 'startSha256': runner.sha256_file(start_path),
                    'hostRunnerSha256': 'd' * 64, 'failureStep': 'ADMISSION_WRITE',
                    'amStartInvoked': False,
                    'failedCommand': ['shell', 'run-as', runner.PACKAGE, 'tee', runner.ADMISSION],
                    'buildManifestFile': build_path.name, 'buildManifestSha256': runner.sha256_file(build_path)}
        evidence_path = cache / (RUN + '-host-prelaunch-evidence.json')
        evidence_path.write_text(json.dumps(evidence))
        return start, evidence, evidence_path

    def test_historical_abort_requires_exact_reviewed_evidence_and_preserves_start(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-historical-abort-') as folder:
            cache = Path(folder)
            start, evidence, evidence_path = self.historical_fixture(cache)
            start_before = (cache / (RUN + '-start.json')).read_bytes()
            with mock.patch.object(runner, 'CACHE', cache), mock.patch.object(runner, 'adb') as device:
                self.assertEqual(runner.unresolved_runs(), [RUN])
                runner.reconcile_prelaunch_abort(RUN, runner.sha256_file(evidence_path))
                self.assertEqual(runner.unresolved_runs(), [])
                device.assert_not_called()
                self.assertEqual((cache / (RUN + '-start.json')).read_bytes(), start_before)
                self.assertFalse((cache / (RUN + '-result.json')).exists())
                evidence['amStartInvoked'] = True
                evidence_path.write_text(json.dumps(evidence))
                with self.assertRaises(AssertionError):
                    runner.unresolved_runs()

    def test_historical_unknown_launch_wrong_command_or_build_never_unlocks(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-historical-refuse-') as folder:
            cache = Path(folder)
            start, evidence, evidence_path = self.historical_fixture(cache)
            with mock.patch.object(runner, 'CACHE', cache), mock.patch.object(runner, 'adb') as device:
                for key, value in (('amStartInvoked', True), ('failureStep', 'AM_START'),
                                   ('failedCommand', ['shell', 'am', 'start']),
                                   ('hostRunnerSha256', 'e' * 64),
                                   ('buildManifestFile', '../elsewhere.json')):
                    changed = copy.deepcopy(evidence)
                    changed[key] = value
                    evidence_path.write_text(json.dumps(changed))
                    with self.subTest(key=key), self.assertRaises(AssertionError):
                        runner.reconcile_prelaunch_abort(RUN, runner.sha256_file(evidence_path))
                    self.assertEqual(list(cache.glob('*-prelaunch-abort.json')), [])
                device.assert_not_called()


class DiagnosticNetworkRetryTests(unittest.TestCase):
    SNAPSHOT = b'ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)\n  Task{abc #12 type=home}\n    ActivityRecord{abc u0 launcher/.Home t12}\n'

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hnuhole-network-retry-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / 'cache'
        self.cache.mkdir()
        self.package = runner.LEGACY_PACKAGE + '20261012'
        patch = mock.patch.multiple(runner, CACHE=self.cache, REPO=self.root,
                                    PACKAGE=self.package, IDENTITY_MODE='fresh')
        patch.start()
        self.addCleanup(patch.stop)
        sources = {}
        for name in runner.DIAGNOSTIC_CORE:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('host fixture ' + name)
            sources[name] = runner.sha256_file(path)
        self.start = {'owner': runner.OWNER, 'runId': RUN, 'phase': 'ni-d02', 'variant': 'control',
            'applicationId': self.package, 'signingCertificateSha256': runner.CERT, 'identityMode': 'fresh',
            'apkSha256': APK_HASH, 'mainApkSha256': runner.MAIN_APK, 'uid': 42,
            'prepareOnly': False, 'nonceSha256': 'c' * 64, 'hostRunnerSha256': 'd' * 64,
            'actualCSubmission': False, 'fixedCaseAcceptancePassed': False}
        self.result = report('REGISTER_UI_STARTED_TIMEOUT', launched=True, unknown=True)
        self.result['classification'] = self.result['stages'][-1]['classification'] = 'LOCAL_BOUNDED_TIMEOUT'
        self.manifest = {'owner': runner.OWNER, 'result': 'PASS', 'identityMode': 'fresh',
            'scope': 'FRESH_STANDALONE_DIAGNOSTIC_ONLY', 'applicationId': self.package,
            'signingCertificateSha256': runner.CERT, 'activity': runner.ACTIVITY,
            'apkSha256': APK_HASH, 'sourceFilesSha256': {**sources, 'tools/run-google-passkey-diagnostic.py': 'd' * 64},
            'actualCSubmission': False, 'fixedCaseAcceptancePassed': False}
        self.write(RUN + '-start.json', self.start)
        self.write(RUN + '-result.json', self.result)
        self.write('attempt06-build-manifest.json', self.manifest)
        (self.cache / 'user-vpn-retry-request.txt').write_text('用户：你重试一下看行不行', encoding='utf-8')
        self.evidence = {'schemaVersion': 1, 'owner': runner.OWNER,
            'scope': 'USER_AUTHORIZED_DIAGNOSTIC_NETWORK_RETRY', 'runId': RUN,
            'applicationId': self.package, 'signingCertificateSha256': runner.CERT,
            'apkSha256': APK_HASH, 'startSha256': self.digest(RUN + '-start.json'),
            'resultSha256': self.digest(RUN + '-result.json'),
            'manifestFile': 'attempt06-build-manifest.json', 'manifestSha256': self.digest('attempt06-build-manifest.json'),
            'userRequestFile': 'user-vpn-retry-request.txt', 'userRequestSha256': self.digest('user-vpn-retry-request.txt'),
            'networkChange': 'USER_ENABLED_VPN', 'originalTaskIds': [45437],
            'originalGoogleActivity': runner.GOOGLE_REGISTRATION_ACTIVITY, 'device': runner.PHONE}
        self.write(RUN + '-network-retry-evidence.json', self.evidence)

    def write(self, name, value):
        (self.cache / name).write_text(json.dumps(value), encoding='utf-8')

    def digest(self, name):
        return runner.sha256_file(self.cache / name)

    def retire(self, *, snapshot=None, admission=None, device_result=None):
        installed = {self.package: APK_HASH, 'org.hnuhole.hnuhole_mobile': runner.MAIN_APK,
                     runner.LEGACY_PACKAGE: runner.BASE_APK}
        with mock.patch.object(runner, 'installed_hash', side_effect=lambda name: installed[name]), \
             mock.patch.object(runner, 'uid', return_value=42), \
             mock.patch.object(runner, 'collect', return_value=self.result if device_result is None else device_result), \
             mock.patch.object(runner, 'read_private', return_value=admission), \
             mock.patch.object(runner, 'adb', side_effect=lambda *args: b'device' if args == ('get-state',) else (self.SNAPSHOT if snapshot is None else snapshot)):
            return runner.retire_diagnostic_only(RUN, self.digest(RUN + '-network-retry-evidence.json'))

    def test_retirement_preserves_native_unknown_and_plain_launch_stays_blocked(self):
        original = (self.cache / (RUN + '-result.json')).read_bytes()
        receipt = self.retire()
        self.assertIs(receipt['historicalNativeOutcomeUnknown'], True)
        self.assertIs(receipt['nativeOutcomeResolved'], False)
        self.assertIs(receipt['credentialMayExist'], True)
        self.assertEqual((self.cache / (RUN + '-result.json')).read_bytes(), original)
        self.assertEqual(runner.unresolved_runs(), [RUN])
        with mock.patch.object(runner, 'validate', return_value=(self.manifest, Path('unused'), APK_HASH)), \
             mock.patch.object(runner, 'adb') as device:
            with self.assertRaises(AssertionError):
                runner.run(SimpleNamespace(action='launch'))
            device.assert_not_called()

    def test_missing_error_active_task_or_malformed_inventory_never_retires(self):
        for snapshot in (b'', b'Error: permission denied', b'ACTIVITY MANAGER ACTIVITIES\nno inventory',
                         self.SNAPSHOT + b'Permission Denial: denied\n',
                         self.SNAPSHOT + b'Task{abc #45437}\n',
                         self.SNAPSHOT + runner.ACTIVITY.encode(),
                         self.SNAPSHOT + b'com.google.android.gms/.auth.api.credentials.fido.registration.ui.RegistrationActivity'):
            with self.subTest(snapshot=snapshot), self.assertRaises(AssertionError):
                self.retire(snapshot=snapshot)
        self.assertFalse((self.cache / (RUN + '-diagnostic-retirement.json')).exists())

    def test_pending_admission_or_changed_device_report_never_retires(self):
        with self.assertRaises(AssertionError):
            self.retire(admission=b'pending admission')
        with self.assertRaises(AssertionError):
            self.retire(device_result={**self.result, 'pid': 43})

    def test_exact_human_instruction_timeout_scope_and_compiled_inputs_required(self):
        for change in ('human', 'terminal', 'scope', 'compiled'):
            with self.subTest(change=change):
                evidence = copy.deepcopy(self.evidence)
                result = copy.deepcopy(self.result)
                manifest = copy.deepcopy(self.manifest)
                if change == 'human':
                    (self.cache / evidence['userRequestFile']).write_text('untrusted implied retry', encoding='utf-8')
                    evidence['userRequestSha256'] = self.digest(evidence['userRequestFile'])
                elif change == 'terminal':
                    result['stage'] = result['stages'][-1]['stage'] = 'LOCAL_ACTIVITY_DESTROYED'
                elif change == 'scope':
                    manifest['scope'] = 'PRODUCT_ACCEPTANCE'
                else:
                    manifest['sourceFilesSha256'][runner.DIAGNOSTIC_CORE[0]] = 'f' * 64
                self.write(RUN + '-result.json', result)
                self.write(evidence['manifestFile'], manifest)
                evidence['resultSha256'] = self.digest(RUN + '-result.json')
                evidence['manifestSha256'] = self.digest(evidence['manifestFile'])
                with self.assertRaises(AssertionError):
                    runner.validate_network_retry_evidence(evidence, self.start, result)
                (self.cache / evidence['userRequestFile']).write_text('你重试一下看行不行', encoding='utf-8')

    def test_retirement_provenance_and_one_retry_budget_are_pinned(self):
        receipt = self.retire()
        path = RUN + '-diagnostic-retirement.json'
        for key, value in (('freshRetryBudget', 2), ('nativeOutcomeResolved', True),
                           ('hostRunnerSha256', 'f' * 64), ('localTaskSnapshotSha256', 'invalid'),
                           ('recordedAtUnix', True)):
            changed = {**receipt, key: value}
            self.write(path, changed)
            with self.subTest(key=key), self.assertRaises(AssertionError):
                runner.validate_diagnostic_retirement(RUN, self.digest(path))
        self.write(path, receipt)
        runner.validate_diagnostic_retirement(RUN, self.digest(path))
        self.write(RUN + '-retry-reservation.json', {'reserved': True})
        with self.assertRaises(AssertionError):
            runner.validate_diagnostic_retirement(RUN, self.digest(path))

    def test_fresh_retry_reserves_once_and_uses_new_run_and_nonce(self):
        self.retire()
        admission = {}
        calls = []
        def device(*args, **kwargs):
            calls.append(args)
            if 'dumpsys' in args:
                return self.SNAPSHOT
            if 'tee' in args:
                admission.update(json.loads(kwargs['input_bytes']))
                return kwargs['input_bytes']
            if 'am' in args:
                raise subprocess.TimeoutExpired('am start', 20)
            return b''
        def private(path):
            return json.dumps(admission).encode() if admission else None
        args = SimpleNamespace(action='launch', retry_of=RUN,
            authorization_sha256=self.digest(RUN + '-diagnostic-retirement.json'))
        with mock.patch.object(runner, 'validate', return_value=(self.manifest, Path('unused'), APK_HASH)), \
             mock.patch.object(runner, 'ensure_private_directory'), \
             mock.patch.object(runner, 'private_test', return_value=False), \
             mock.patch.object(runner, 'uid', return_value=42), \
             mock.patch.object(runner, 'collect', side_effect=lambda run, unused: self.result if run == RUN else None), \
             mock.patch.object(runner, 'read_private', side_effect=private), \
             mock.patch.object(runner, 'adb', side_effect=device):
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.run(args)
            with self.assertRaises(AssertionError):
                runner.run(args)
        reservation = runner.read(self.cache / (RUN + '-retry-reservation.json'))
        self.assertNotEqual(reservation['newRunId'], RUN)
        start = runner.read(self.cache / (reservation['newRunId'] + '-start.json'))
        self.assertNotEqual(start['nonceSha256'], self.start['nonceSha256'])
        self.assertEqual(start['retryOfRunId'], RUN)
        self.assertEqual(sum('am' in call for call in calls), 1)
        self.assertEqual(sum('dumpsys' in call for call in calls), 2)
        self.assertEqual(runner.read(self.cache / (RUN + '-result.json')), self.result)

    def test_task_reappearance_immediately_before_reservation_and_extra_unknown_block(self):
        self.retire()
        args = SimpleNamespace(action='launch', retry_of=RUN,
            authorization_sha256=self.digest(RUN + '-diagnostic-retirement.json'))
        with mock.patch.object(runner, 'validate', return_value=(self.manifest, Path('unused'), APK_HASH)), \
             mock.patch.object(runner, 'ensure_private_directory'), \
             mock.patch.object(runner, 'private_test', return_value=False), \
             mock.patch.object(runner, 'uid', return_value=42), \
             mock.patch.object(runner, 'collect', side_effect=lambda run, unused: self.result if run == RUN else None), \
             mock.patch.object(runner, 'read_private', return_value=None), \
             mock.patch.object(runner, 'adb', side_effect=[self.SNAPSHOT, self.SNAPSHOT + b'Task{a #45437}']):
            with self.assertRaises(AssertionError):
                runner.run(args)
        self.assertFalse((self.cache / (RUN + '-retry-reservation.json')).exists())
        other = 'gfd-' + '2' * 32
        self.write(other + '-start.json', {**self.start, 'runId': other})
        with mock.patch.object(runner, 'validate', return_value=(self.manifest, Path('unused'), APK_HASH)), \
             mock.patch.object(runner, 'collect', return_value=self.result), \
             mock.patch.object(runner, 'adb', return_value=self.SNAPSHOT):
            with self.assertRaises(AssertionError):
                runner.run(args)
        self.assertFalse((self.cache / (RUN + '-retry-reservation.json')).exists())

    def test_host_revision_preserves_exact_build_and_limits_changes_to_two_python_sources(self):
        base = copy.deepcopy(self.manifest)
        changes = {}
        for name in runner.HOST_GUARD_SOURCES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('current synthetic host revision ' + name)
            changes[name] = runner.sha256_file(path)
            base['sourceFilesSha256'][name] = 'f' * 64
        self.write('linux-build-manifest.json', base)
        linux_sha = self.digest('linux-build-manifest.json')
        base['crossHostCopy'] = {'sourceManifestSha256': linux_sha, 'apkBytesUnchanged': True, 'pathOnlyRebased': True}
        base['embeddedPolicySha256'] = 'b' * 64
        base['stagedSourceFilesSha256'] = {'exactPolicy': 'b' * 64}
        base['releaseExcluded'] = True
        self.write('attempt06-host-manifest.json', base)
        validation = {'schemaVersion': 1, 'owner': runner.OWNER,
            'scope': 'HOST_ONLY_NONCOMPILED_GUARD_VALIDATION', 'runnerSha256': changes[runner.HOST_GUARD_SOURCES[0]],
            'testSourceSha256': changes[runner.HOST_GUARD_SOURCES[1]], 'command': runner.HOST_TEST_COMMAND,
            'exitCode': 0, 'testsPassed': 24, 'result': 'PASS'}
        self.write('host-validation.json', validation)
        derived = copy.deepcopy(base)
        derived['sourceFilesSha256'].update(changes)
        derived['hostGuardRevision'] = {'schemaVersion': 1, 'scope': 'HOST_ONLY_NONCOMPILED_GUARD_REVISION',
            'baseManifestFile': 'attempt06-host-manifest.json', 'baseManifestSha256': self.digest('attempt06-host-manifest.json'),
            'originalLinuxManifestFile': 'linux-build-manifest.json', 'originalLinuxManifestSha256': linux_sha,
            'changedSourceFilesSha256': changes, 'validationFile': 'host-validation.json',
            'validationSha256': self.digest('host-validation.json')}
        runner.validate_host_guard_revision(derived)
        for change in ('apk', 'core', 'policy', 'release', 'extraHostSource', 'validation'):
            changed = copy.deepcopy(derived)
            if change == 'apk':
                changed['apkSha256'] = 'c' * 64
            elif change == 'core':
                changed['sourceFilesSha256'][runner.DIAGNOSTIC_CORE[0]] = 'c' * 64
            elif change == 'policy':
                changed['embeddedPolicySha256'] = 'c' * 64
            elif change == 'release':
                changed['releaseExcluded'] = False
            elif change == 'extraHostSource':
                changed['hostGuardRevision']['changedSourceFilesSha256']['other.py'] = 'c' * 64
            else:
                changed['hostGuardRevision']['validationSha256'] = 'c' * 64
            with self.subTest(change=change), self.assertRaises(AssertionError):
                runner.validate_host_guard_revision(changed)


if __name__ == '__main__':
    unittest.main()
