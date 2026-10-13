import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location('fresh_operator_test', Path(__file__).parents[1] / 'operate-android-b3-b4-fresh.py')
OP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OP)


class FreshOperatorTests(unittest.TestCase):
    def test_detached_finished_last_paused_pointer_is_not_a_task(self):
        row = b'mLastPausedActivity: ActivityRecord{40a1d1a u0 com.vivo.credentialmanager/.CredentialSelectorActivity t-1 d-1 f}}\n'
        header = b'ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)\nTask{abc #123}\n'
        with patch.object(OP, 'adb', return_value=header + row):
            value = OP.no_live_provider_ui()
            self.assertEqual(value['knownNativeActivityRows'], 0)
            self.assertEqual(value['detachedFinishedProviderReferences'], 1)
        for live in (row.replace(b't-1', b't123'), row.replace(b'd-1', b'd0'),
                     row.replace(b' f}}', b'}}'), row.replace(b'mLastPausedActivity:', b'Hist #0:')):
            with patch.object(OP, 'adb', return_value=header + live):
                with self.assertRaises(RuntimeError):
                    OP.no_live_provider_ui()

    def test_install_success_accepts_only_standard_progress_and_one_terminal_success(self):
        for output in (b'Success', b'Success\n', b'Performing Push Install\nSuccess\n',
                       b'Performing Streamed Install\r\nSuccess\r\n',
                       b'\r\nPerforming Push Install\r\nSuccess\r\n\r\n'):
            with self.subTest(output=output):
                self.assertTrue(OP.install_success(output))

    def test_install_success_rejects_failure_duplicate_unknown_empty_and_oversized_output(self):
        for output in (b'', b'\n', b'Performing Push Install\n', b'Failure [INSTALL_FAILED]\n',
                       b'Performing Push Install\nFailure [INSTALL_FAILED]\nSuccess\n',
                       b'Success\nSuccess\n', b'Success\nPerforming Push Install\n',
                       b'Performing Push Install\nPerforming Streamed Install\nSuccess\n',
                       b'unknown diagnostic line\nSuccess\n', b'Success but unconfirmed\n',
                       b'Success\x00', b'\xffSuccess', b'Success\v',
                       b'\n' * 4096 + b'Success', 'Success', None):
            with self.subTest(output=output):
                self.assertFalse(OP.install_success(output))

    def diagnostic_chain(self, folder):
        cache = folder / 'google-direct-diagnostic'
        cache.mkdir()
        old, new = 'gfd-' + 'a' * 32, 'gfd-' + 'b' * 32
        runner_sha = OP.BUILD.sha(Path(OP.DIAG.__file__))
        old_start = dict(nonceSha256='a' * 64, uid=10399)
        old_result = dict(nativeOutcomeUnknown=True, actualCSubmission=False, fixedCaseAcceptancePassed=False)
        for suffix, value in [('start', old_start), ('result', old_result)]:
            (cache / (old + '-' + suffix + '.json')).write_text(json.dumps(value))
        evidence = dict(apkSha256='d' * 64,
            startSha256=OP.BUILD.sha(cache / (old + '-start.json')),
            resultSha256=OP.BUILD.sha(cache / (old + '-result.json')),
            manifestSha256='e' * 64, userRequestSha256='f' * 64,
            networkChange='USER_ENABLED_VPN', originalTaskIds=[45437])
        evidence_path = cache / (old + '-network-retry-evidence.json')
        evidence_path.write_text(json.dumps(evidence))
        retirement = dict(schemaVersion=1, owner=OP.DIAG.OWNER,
            scope='OPERATOR_RETIRED_DIAGNOSTIC_ONLY_UNKNOWN', runId=old,
            applicationId=OP.FRESH.PACKAGE, signingCertificateSha256=OP.FRESH.CERT,
            **evidence, evidenceSha256=OP.BUILD.sha(evidence_path), localTaskSnapshotSha256='c' * 64,
            originalLocalTasksAbsent=True, historicalNativeOutcomeUnknown=True, credentialMayExist=True,
            nativeOutcomeResolved=False, productUnknownChanged=False, actualCSubmission=False,
            fixedCaseAcceptancePassed=False, freshRetryBudget=1, freshChallengeAndUserRequired=True,
            hostRunnerSha256=runner_sha, recordedAtUnix=100)
        retirement_path = cache / (old + '-diagnostic-retirement.json')
        retirement_path.write_text(json.dumps(retirement))
        authorization = OP.BUILD.sha(retirement_path)
        reservation = dict(schemaVersion=1, owner=OP.DIAG.OWNER, scope='ONE_FRESH_DIAGNOSTIC_NETWORK_RETRY',
            retiredRunId=old, newRunId=new, authorizationSha256=authorization, apkSha256='d' * 64,
            freshChallengeAndUserRequired=True, actualCSubmission=False, fixedCaseAcceptancePassed=False, recordedAtUnix=101)
        (cache / (old + '-retry-reservation.json')).write_text(json.dumps(reservation))
        start = dict(owner=OP.DIAG.OWNER, identityMode='fresh', runId=new, retryOfRunId=old,
            retryAuthorizationSha256=authorization, applicationId=OP.FRESH.PACKAGE,
            signingCertificateSha256=OP.FRESH.CERT, apkSha256='d' * 64,
            mainApkSha256=OP.HISTORICAL[OP.FRESH.MAIN_PACKAGE], prepareOnly=False,
            phase='ni-d02', variant='control', actualCSubmission=False, fixedCaseAcceptancePassed=False,
            nonceSha256='b' * 64, startedAtUnix=102, uid=10399, hostRunnerSha256=runner_sha)
        (cache / (new + '-start.json')).write_text(json.dumps(start))
        result = dict(finished=True, nativeOutcomeUnknown=False, prepareOnly=False,
            pendingIntentLaunched=True, actualCSubmission=False, fixedCaseAcceptancePassed=False)
        (cache / (new + '-result.json')).write_text(json.dumps(result))
        return old, new, retirement_path, start, result

    def test_active_native_counter_refuses_install_or_settings_switch(self):
        with self.assertRaisesRegex(RuntimeError, 'active or uncertain'):
            OP.native_terminal(dict(pid=123, nativeBegun=2, nativeSucceeded=1))
        OP.native_terminal(dict(pid=123, nativeBegun=2, nativeSucceeded=1, nativeErrored=1))
        with self.assertRaisesRegex(RuntimeError, 'Bounded'):
            OP.native_terminal(dict(pid=123, nativeBegun=True))

    def test_local_timeout_or_cancel_is_unknown_even_after_equal_counters_and_late_callback(self):
        for state in (
            dict(pid=42, nativeBegun=1, nativeErrored=1, nativeTimeout=1),
            dict(pid=42, nativeBegun=1, nativeCancelled=1),
            dict(pid=42, nativeBegun=1, nativeErrored=1, nativeTimeout=1,
                 actualAssociationRejected=1, lateIgnored=1),
        ):
            with self.subTest(state=state), self.assertRaisesRegex(RuntimeError, 'native UNKNOWN'):
                OP.native_terminal(state)
        with self.assertRaisesRegex(RuntimeError, 'Bounded'):
            OP.native_terminal(dict(pid=42, nativeBegun=1, nativeErrored=1, nativeTimeout=True))

    def test_direct_provider_error_callback_with_no_local_unknown_is_terminal(self):
        OP.native_terminal(dict(pid=42, nativeBegun=1, nativeErrored=1,
                                nativeTimeout=0, nativeCancelled=0, actualOtherCreateError=1))

    def test_unknown_provider_is_never_overwritten(self):
        original = dict(credential_service=OP.VIVO, credential_service_primary=OP.VIVO, autofill_service=OP.VIVO_AUTOFILL)
        OP.validate_settings(original)
        OP.validate_settings(dict(original, credential_service=OP.VIVO + ':' + OP.GOOGLE))
        with self.assertRaisesRegex(RuntimeError, 'Unknown credential'):
            OP.validate_settings(dict(original, credential_service='unknown.app/.Service'))
        with self.assertRaisesRegex(RuntimeError, 'Unknown autofill'):
            OP.validate_settings(dict(original, autofill_service='unknown.app/.Service'))

    def test_explicit_switch_and_exact_null_restore(self):
        original = dict(credential_service='null', credential_service_primary=OP.VIVO, autofill_service='null')
        self.assertEqual(OP.provider_target('provider-restore', original, False), original)
        google = OP.provider_target('provider-google', original, False)
        self.assertEqual(google['autofill_service'], 'null')
        google_autofill = OP.provider_target('provider-google', original, True)
        self.assertEqual(google_autofill['autofill_service'], OP.GOOGLE_AUTOFILL)
        with patch.object(OP, 'adb') as device, patch.object(OP, 'settings', return_value=original):
            OP.set_settings(original)
        self.assertEqual(device.call_args_list[0].args, ('shell', 'settings', 'delete', 'secure', 'credential_service'))
        self.assertEqual(device.call_args_list[2].args, ('shell', 'settings', 'delete', 'secure', 'autofill_service'))

    def test_diagnostic_pending_start_refuses_even_a_reviewed_product(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP.DIAG, 'configure_environment'), patch.object(OP.DIAG, 'unresolved_runs', return_value=['gfd-pending']), patch.object(OP, 'adb') as device:
            with self.assertRaisesRegex(RuntimeError, 'unresolved Google'):
                OP.diagnostic_guard({})
            device.assert_not_called()

    def test_unknown_fresh_package_never_uninstalled(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP, 'installed', return_value='f' * 64), patch.object(OP, 'reviewed_installed', return_value={}), patch.object(OP, 'adb') as device:
            with self.assertRaisesRegex(RuntimeError, 'Unknown installed'):
                OP.install_operation('install-approved', {}, {'apkSha256': 'a' * 64}, {}, Path(work) / 'audit.json')
            device.assert_not_called()

    def test_control_failure_never_installs_negative(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP, 'installed', return_value=None), patch.object(OP, 'reviewed_installed', return_value={}), patch.object(OP, 'control_passed', side_effect=RuntimeError('control missing')), patch.object(OP, 'adb') as device:
            with self.assertRaisesRegex(RuntimeError, 'control missing'):
                OP.install_operation('install-unassociated', {}, {'apkSha256': 'a' * 64}, {}, Path(work) / 'audit.json')
            device.assert_not_called()

    def test_bad_cert_switch_uninstalls_only_fresh_package_after_terminal_rp(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP, 'reviewed_installed', return_value={'a' * 64: OP.FRESH.CERT}), patch.object(OP, 'control_passed'), patch.object(OP, 'private_json', return_value=dict(pid=42, nativeBegun=1, nativeSucceeded=1)), patch.object(OP, 'rp_terminal_guard', return_value={'originalResultQueriedWithoutProofReplay': True}) as terminal, patch.object(OP, 'installed', side_effect=['a' * 64, None, 'b' * 64, 'b' * 64]), patch.object(OP, 'adb', return_value=b'Success') as device:
            journal = Path(work) / 'audit.json'
            record = {}
            OP.install_operation('install-bad-signature', {}, {'apkSha256': 'b' * 64}, record, journal)
            self.assertEqual(device.call_args_list[0].args, ('uninstall', OP.FRESH.PACKAGE))
            self.assertEqual(device.call_args_list[1].args[:4], ('install', '--no-streaming', '-t', '-r'))
            terminal.assert_called_once_with(OP.FRESH.PACKAGE, OP.FRESH.CERT, 'a' * 64)
            self.assertTrue(record['onlyFreshAcceptancePackageUninstalled'])
            self.assertEqual(json.loads(journal.read_text())['rpTerminalWitness']['originalResultQueriedWithoutProofReplay'], True)
            self.assertFalse(any(package in call.args for package in OP.HISTORICAL for call in device.call_args_list))

    def test_uncertain_original_rp_anchor_prevents_uninstall(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP, 'reviewed_installed', return_value={'a' * 64: OP.FRESH.CERT}), patch.object(OP, 'control_passed'), patch.object(OP, 'private_json', return_value=None), patch.object(OP, 'installed', return_value='a' * 64), patch.object(OP, 'rp_terminal_guard', side_effect=RuntimeError('original server anchor')), patch.object(OP, 'adb') as device:
            with self.assertRaisesRegex(RuntimeError, 'server anchor'):
                OP.install_operation('install-bad-signature', {}, {'apkSha256': 'b' * 64}, {}, Path(work) / 'audit.json')
            device.assert_not_called()

    def test_successful_same_cert_update_creates_exact_owner_without_uninstall(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP, 'reviewed_installed', return_value={'a' * 64: OP.FRESH.CERT}), patch.object(OP, 'installed', side_effect=['a' * 64, 'b' * 64, 'b' * 64]), patch.object(OP, 'private_json', return_value=None), patch.object(OP, 'adb', return_value=b'Performing Push Install\r\nSuccess\r\n') as device:
            (Path(work) / 'driver/apps/mobile').mkdir(parents=True)
            record = {}
            OP.install_operation('install-approved', {}, {'apkSha256': 'b' * 64}, record, Path(work) / 'audit.json')
            self.assertEqual(len(device.call_args_list), 1)
            self.assertEqual(device.call_args.args[:4], ('install', '--no-streaming', '-t', '-r'))
            self.assertEqual((Path(work) / 'driver/apps/mobile/.device-app-owner').read_text(), OP.FRESH.DEVICE + '|' + OP.FRESH.RUN)

    def test_success_output_still_requires_exact_installed_target_hash(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP, 'reviewed_installed', return_value={}), patch.object(OP, 'installed', side_effect=[None, 'c' * 64]), patch.object(OP, 'adb', return_value=b'Performing Push Install\nSuccess\n') as device:
            with self.assertRaisesRegex(RuntimeError, 'installed fresh product hash changed'):
                OP.install_operation('install-approved', {}, {'apkSha256': 'b' * 64}, {}, Path(work) / 'audit.json')
            self.assertEqual(len(device.call_args_list), 1)
            self.assertFalse((Path(work) / 'driver/apps/mobile/.device-app-owner').exists())

    def test_inspected_target_already_installed_never_replays_install(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP, 'reviewed_installed', return_value={'b' * 64: OP.FRESH.CERT}), patch.object(OP, 'installed', return_value='b' * 64), patch.object(OP, 'private_json', return_value=None), patch.object(OP, 'adb') as device:
            (Path(work) / 'driver/apps/mobile').mkdir(parents=True)
            record = {}
            OP.install_operation('install-approved', {}, {'apkSha256': 'b' * 64}, record, Path(work) / 'audit.json')
            device.assert_not_called()
            self.assertEqual(record['installedApkSha256'], 'b' * 64)
            self.assertTrue(record['reviewedDriverOwnerCreated'])

    def test_provider_original_backup_survives_switch_and_restore(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP, 'set_settings') as switch, patch.object(OP, 'adb', return_value=(OP.GOOGLE + '\n').encode()):
            evidence = Path(work) / 'b3b4-evidence'
            evidence.mkdir()
            original = dict(credential_service=OP.VIVO, credential_service_primary=OP.VIVO, autofill_service=OP.VIVO_AUTOFILL)
            google = OP.provider_target('provider-google', original, False)
            with patch.object(OP, 'settings', side_effect=[original, google]):
                OP.provider_operation('provider-google', False, {}, evidence / 'first.json')
            backup = (evidence / 'fresh-original-provider-settings.json').read_bytes()
            with patch.object(OP, 'settings', side_effect=[google, original]):
                OP.provider_operation('provider-restore', False, {}, evidence / 'restore.json')
            self.assertEqual((evidence / 'fresh-original-provider-settings.json').read_bytes(), backup)
            self.assertEqual(switch.call_args_list[0].args[0], google)
            self.assertEqual(switch.call_args_list[1].args[0], original)

    def test_private_witness_probe_failure_is_not_absence(self):
        failed = type('Result', (), dict(returncode=1, stdout=b'', stderr=b'permission denied'))()
        with patch.object(OP.subprocess, 'run', return_value=failed), patch.object(OP, 'adb') as device:
            with self.assertRaisesRegex(RuntimeError, 'absence was not established'):
                OP.private_json(OP.FRESH.PACKAGE, 'files/owned-acceptance-passkey.json')
            device.assert_not_called()

    def test_terminal_counter_does_not_hide_remaining_native_task(self):
        OP.native_terminal(dict(pid=42, nativeBegun=1, nativeErrored=1))
        raw = b'ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)\ntopResumedActivity=ActivityRecord{abc u0 com.google.android.gms/.auth.api.credentials.fido.registration.ui.RegistrationActivity t45437}\n'
        with patch.object(OP, 'adb', return_value=raw):
            with self.assertRaisesRegex(RuntimeError, 'remaining native provider task'):
                OP.no_live_provider_ui()

    def test_absent_provider_requires_valid_full_activity_inventory(self):
        valid = b'ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)\nTask{abc #123}\nActivityRecord{def u0 com.example.launcher/.Main t123}\n'
        with patch.object(OP, 'adb', return_value=valid):
            self.assertEqual(OP.no_live_provider_ui()['knownNativeActivityRows'], 0)
        for raw in (b'', b'Permission Denial\n', b'ACTIVITY MANAGER ACTIVITIES\n',
                    b'Task{abc #123}\n', b'\xff' + valid, valid + b'\x00',
                    valid + b'\n  Error: partial inventory\n', b'x' * (1024 * 1024 + 1)):
            with self.subTest(raw=raw[:80]), patch.object(OP, 'adb', return_value=raw), self.assertRaises(RuntimeError):
                OP.no_live_provider_ui()

    def test_host_process_check_excludes_its_own_query_process(self):
        with patch.object(OP.os, 'name', 'nt'), patch.object(OP, 'command', return_value=b'[]') as cmd:
            OP.no_active_runner()
            self.assertIn('$_.ProcessId -ne $PID', cmd.call_args.args[0][-1])

    def test_approved_restore_uses_exact_terminal_witness_retained_before_uninstall(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP, 'private_json') as private:
            evidence = Path(work) / 'b3b4-evidence'
            evidence.mkdir()
            (evidence / 'ni-d01-main-version.json').write_text('{}')
            (Path(work) / 'source-manifest.json').write_text('{}')
            witness = dict(phase='ni-d01', actualServerWrongRpHashRejected422=True,
                           originalResultQueriedWithoutProofReplay=True, rawProofStored=False)
            operation = dict(owner=OP.FRESH.TOKEN, device=OP.FRESH.DEVICE, deviceRunId=OP.FRESH.RUN,
                applicationId=OP.FRESH.PACKAGE, targetApkSha256='b' * 64,
                signingCertificateSha256=OP.BUILD.BAD_CERT, onlyFreshAcceptancePackageUninstalled=True,
                historicalPackagesBefore=OP.HISTORICAL, sourceManifestSha256=OP.BUILD.sha(Path(work) / 'source-manifest.json'),
                rpTerminalWitness=witness)
            path = evidence / 'install-bad-signature-test-host-operation.json'
            path.write_text(json.dumps(operation))
            result = OP.rp_terminal_guard(OP.FRESH.PACKAGE, OP.BUILD.BAD_CERT, 'b' * 64)
            self.assertTrue(result['retainedBeforeFreshCertificateChange'])
            private.assert_not_called()
            operation['rpTerminalWitness']['originalResultQueriedWithoutProofReplay'] = False
            path.write_text(json.dumps(operation))
            with self.assertRaisesRegex(RuntimeError, 'Retained original RP'):
                OP.rp_terminal_guard(OP.FRESH.PACKAGE, OP.BUILD.BAD_CERT, 'b' * 64)

    def test_route_overlay_refuses_unreviewed_receipt_before_dependency_read(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)):
            (Path(work) / 'source-manifest.json').write_text('{}')
            evidence = Path(work) / 'b3b4-evidence'
            evidence.mkdir()
            (evidence / 'pub-lock-route-overlay.json').write_text(json.dumps(dict(owner=OP.FRESH.TOKEN, replacements=33)))
            with self.assertRaisesRegex(RuntimeError, 'Hosted route receipt differs'):
                OP.validate_pub_route(dict(pubLockRouteOverlay=dict(receiptFileName='pub-lock-route-overlay.json')))

    def test_consumed_known_retry_does_not_resolve_or_rewrite_original_unknown(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP.DIAG, 'validate_network_retry_evidence'), patch.object(OP.DIAG, 'validate_report'), patch.object(OP, 'adb') as device:
            old, new, path, start, result = self.diagnostic_chain(Path(work))
            original_path = Path(work) / 'google-direct-diagnostic' / (old + '-result.json')
            original = original_path.read_bytes()
            transition = OP.consumed_diagnostic_retry(path)
            self.assertTrue(transition['historicalNativeOutcomeUnknown'])
            self.assertFalse(transition['nativeOutcomeResolved'])
            self.assertFalse(transition['productUnknownChanged'])
            self.assertFalse(transition['actualCSubmission'])
            self.assertEqual(original_path.read_bytes(), original)
            device.assert_not_called()

    def test_an_unknown_retry_or_same_nonce_still_blocks_transition(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP.DIAG, 'validate_network_retry_evidence'), patch.object(OP.DIAG, 'validate_report'):
            old, new, path, start, result = self.diagnostic_chain(Path(work))
            result_path = Path(work) / 'google-direct-diagnostic' / (new + '-result.json')
            result['nativeOutcomeUnknown'] = True
            result_path.write_text(json.dumps(result))
            with self.assertRaisesRegex(RuntimeError, 'still has an unknown native outcome'):
                OP.consumed_diagnostic_retry(path)
            result['nativeOutcomeUnknown'] = False
            result_path.write_text(json.dumps(result))
            start['nonceSha256'] = 'a' * 64
            (Path(work) / 'google-direct-diagnostic' / (new + '-start.json')).write_text(json.dumps(start))
            with self.assertRaisesRegex(RuntimeError, 'nonce must never be replayed'):
                OP.consumed_diagnostic_retry(path)

    def test_explicit_retirement_cannot_ignore_another_unknown_or_apply_to_provider(self):
        with tempfile.TemporaryDirectory() as work, patch.object(OP, 'ROOT', Path(work)), patch.object(OP.DIAG, 'validate_network_retry_evidence'), patch.object(OP.DIAG, 'validate_report'):
            old, new, path, start, result = self.diagnostic_chain(Path(work))
            authorization = OP.BUILD.sha(path)
            transition = OP.diagnostic_transition([old], authorization, 'install-approved')
            self.assertEqual(transition['retiredRunId'], old)
            with self.assertRaisesRegex(RuntimeError, 'Additional unknown'):
                OP.diagnostic_transition([old, new], authorization, 'install-approved')
            with self.assertRaisesRegex(RuntimeError, 'only for initial approved'):
                OP.diagnostic_transition([old], authorization, 'provider-google')


if __name__ == '__main__':
    unittest.main()
