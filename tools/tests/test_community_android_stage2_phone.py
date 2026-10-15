import importlib.util
import hashlib
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('stage2_phone', ROOT / 'tools/community-android-stage2/phone.py')
phone = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phone)
imports = importlib.util.spec_from_file_location('stage2_public_import', ROOT / 'tools/community-android-stage2/import-test-dependencies.py')
public_import = importlib.util.module_from_spec(imports)
imports.loader.exec_module(public_import)


class StoragePhoneGuardTests(unittest.TestCase):
    def test_each_consent_required_before_manifest_socket_or_adb(self):
        names = ['confirmed_window', 'allow_isolated_install', 'auth_session_released', 'allow_owned_adb_key', 'allow_owned_force_stop']
        for missing in names:
            args = types.SimpleNamespace(**{key: key != missing for key in names})
            with patch.object(phone, 'load_manifest') as files, patch.object(phone.subprocess, 'run') as command:
                with self.assertRaises(ValueError):
                    phone.run_phone(args)
                files.assert_not_called()
                command.assert_not_called()

    def test_exact_native_selection_includes_business_and_both_passkey_classes(self):
        self.assertEqual([v[2] for v in phone.SUITES], [7, 16, 9, 3])
        self.assertEqual(sum(v[2] for v in phone.SUITES), 35)
        self.assertEqual(len(set(phone.ARTIFACTS.values())), 3)
        self.assertNotIn(phone.transport.PACKAGE, phone.ARTIFACTS.values())

    def test_instrumentation_requires_exact_count_and_complete_success(self):
        good = 'INSTRUMENTATION_STATUS: numtests=7\nINSTRUMENTATION_STATUS_CODE: 0\nOK (7 tests)\n'
        phone.instrumentation_ok(good, 7)
        for value in ['', 'OK (6 tests)', good + 'FAILURES', good + 'INSTRUMENTATION_STATUS_CODE: -3', good + 'INSTRUMENTATION_RESULT: shortMsg=Process crashed', good + 'OK (7 tests)']:
            with self.assertRaises(ValueError):
                phone.instrumentation_ok(value, 7)

    def test_unknown_or_incomplete_prior_result_never_replayed(self):
        for state in [{'started': ['write'], 'results': {}}, {'started': [], 'results': {'suites': {'result': 'FAIL'}}}]:
            with self.assertRaises(ValueError):
                phone.validate_order(state, 'write', 'same')
        with self.assertRaises(ValueError):
            phone.validate_order({'deviceIdHash': 'other'}, 'suites', 'same')

    def test_reboot_needs_separate_confirmation_and_cannot_follow_purge(self):
        state = {'started': ['read'], 'results': {'read': {'result': 'PASS'}}}
        with self.assertRaises(ValueError):
            phone.validate_order(state, 'reboot-read', 'same')
        phone.validate_order(state, 'reboot-read', 'same', True)
        state['started'].append('purge')
        with self.assertRaises(ValueError):
            phone.validate_order(state, 'reboot-read', 'same', True)

    def test_server_replacement_or_unknown_listener_rejected(self):
        adb = Path('owned/adb.exe').resolve()
        original = {'pid': 123, 'start': '10', 'exe': str(adb)}
        phone.owned_server(original, original, adb)
        phone.owned_server(None, original, adb)
        for changed, prior in [(original, None), ({**original, 'start': '11'}, original), ({**original, 'exe': str(Path('foreign/adb.exe').resolve())}, original)]:
            with self.assertRaises(ValueError):
                phone.owned_server(changed, prior, adb)

    def test_fake_native_success_and_incomplete_facts_rejected(self):
        for data in [{}, {'phase': 'storage-read', 'nativeVault': False}, {'phase': 'storage-read', 'nativeVault': True, 'nativeBusinessSqlite': True, 'syntheticFixturesOnly': True, 'actualMainCalled': False, 'pid': 12, 'flags': {}}]:
            with self.assertRaises(ValueError):
                phone.filtered_result({'result': 'true', 'data': data}, 'read')

    def test_only_redacted_boolean_facts_exported(self):
        raw = {'result': 'true', 'failureDetails': ['secret'], 'data': {
            'phase': 'storage-read', 'nativeVault': True, 'nativeBusinessSqlite': True,
            'syntheticFixturesOnly': True, 'actualMainCalled': False, 'pid': 123,
            'flags': {key: True for key in ['draftAndOriginalIntentRestored', 'nativeAuthRecordPreserved', 'otherAccountPreserved', 'realSqliteWithoutPayloadPlaintext', 'secret']}, 'token': 'secret',
        }}
        report = phone.filtered_result(raw, 'read')
        self.assertNotIn('secret', json.dumps(report))
        self.assertFalse(report['actualMainCalled'])

    def test_manifest_fails_before_adb_on_unknown_package_or_changed_apk(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / '.owner').write_text(phone.OWNER)
            manifest = {'owner': phone.OWNER, 'runId': 'community-storage-0123456789abcdef', 'apks': {}}
            for name, package in phone.ARTIFACTS.items():
                apk = root / (name + '.apk')
                apk.write_bytes(b'synthetic-apk')
                manifest['apks'][name] = {'path': str(apk), 'applicationId': package, 'sha256': phone.digest(apk)}
            path = root / 'manifest.json'
            for mutation in ['package', 'apk']:
                with self.subTest(mutation=mutation), patch.object(phone.subprocess, 'run') as command:
                    if mutation == 'package':
                        manifest['apks']['storage']['applicationId'] = phone.transport.PACKAGE
                    else:
                        manifest['apks']['storage']['applicationId'] = phone.APP
                        (root / 'storage.apk').write_bytes(b'changed')
                    path.write_text(json.dumps(manifest))
                    with self.assertRaises(ValueError):
                        phone.load_manifest(path)
                    command.assert_not_called()

    def test_public_import_checks_content_and_preserves_exact_pom(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            work = root / 'work'; work.mkdir()
            (work / '.owner').write_text(phone.OWNER)
            cache = root / 'files-2.1'; cache.mkdir()
            body = b'<project xmlns="http://maven.apache.org/POM/4.0.0"><version>1.3.0</version></project>'
            path = cache / 'androidx.test.ext/junit/1.3.0' / hashlib.sha1(body).hexdigest().lstrip('0') / 'junit-1.3.0.pom'
            path.parent.mkdir(parents=True)
            path.write_bytes(body)
            with patch.object(sys, 'argv', ['import', '--work', str(work), '--public-cache', str(cache)]):
                public_import.main()
            target = work / 'test-maven/androidx/test/ext/junit/1.3.0/junit-1.3.0.pom'
            self.assertEqual(target.read_bytes(), body)
            self.assertEqual(path.read_bytes(), body)
            path.write_bytes(b'tampered')
            with patch.object(sys, 'argv', ['import', '--work', str(work), '--public-cache', str(cache)]):
                with self.assertRaises(ValueError):
                    public_import.main()
            self.assertEqual(target.read_bytes(), body)

    def test_unknown_adb_server_refused_before_any_device_command(self):
        args = types.SimpleNamespace(confirmed_window=True, allow_isolated_install=True, auth_session_released=True, allow_owned_adb_key=True, allow_owned_force_stop=True, phase='suites', device='synthetic-physical-id', manifest='not-read', confirmed_manual_reboot=False)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with patch.object(phone, 'load_manifest', return_value=(root, {'adbServerPort': 30001, 'adb': 'owned/adb.exe'})), patch.object(phone, 'server_witness', return_value={'pid': 1, 'start': '2', 'exe': 'unknown/adb.exe'}), patch.object(phone.subprocess, 'run') as device:
                with self.assertRaises(ValueError):
                    phone.run_phone(args)
                device.assert_not_called()


if __name__ == '__main__':
    unittest.main()
