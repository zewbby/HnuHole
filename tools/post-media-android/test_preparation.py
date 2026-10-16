"""Host guard tests using synthetic APK bytes; never open sockets or devices."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys

spec = importlib.util.spec_from_file_location('ready', Path(__file__).with_name('check_ready.py'))
ready = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ready)
sys.modules['check_ready'] = ready
probe_spec = importlib.util.spec_from_file_location('create_probe', Path(__file__).with_name('create_probe.py'))
probe = importlib.util.module_from_spec(probe_spec)
probe_spec.loader.exec_module(probe)


class ReadyTests(unittest.TestCase):
    def setUp(self):
        parent = Path(os.environ['POST_MEDIA_PREP_TEST_ROOT']).resolve()
        parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='ready-unit-', dir=parent)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root/'.owner').write_text(ready.OWNER)
        for name in ['artifacts', 'fixtures', 'private', 'logs', 'source/apps/mobile/lib']:
            (self.root/name).mkdir(parents=True, exist_ok=True)
        source = self.root/'source/apps/mobile/lib/main.dart'
        source.write_text('// synthetic input')
        self.value = {'owner': ready.OWNER, 'deviceOperationsExecuted': False, 'artifacts': {}, 'fixtures': [],
                      'fixedKitInputs': {}, 'repository': str(self.root/'source'),
                      'sourceInputs': {'apps/mobile/lib/main.dart': ready.sha(source)}, 'tlsLeafExpiresAtUnix': 99999,
                      'status': 'READY_AWAITING_DEVICE'}
        for name, package in ready.PACKAGES.items():
            path = self.root/'artifacts'/(name+'.apk')
            path.write_bytes(('synthetic unit fixture '+name).encode())
            self.value['artifacts'][name] = {'package': package, 'minimumApi': 29, 'sha256': ready.sha(path), 'signerSha256': 'a'*64}
        for index in range(9):
            path = self.root/'fixtures'/('%02d.png' % index)
            path.write_bytes(bytes([index]))
            self.value['fixtures'].append({'name': path.name, 'sha256': ready.sha(path)})
        for name in ready.FIXED:
            path = self.root/name
            path.write_bytes(b'synthetic pinned input')
            self.value['fixedKitInputs'][name] = ready.sha(path)
        (self.root/'logs/server-preparation.json').write_text(json.dumps({'result': 'PASS', 'stopped': True, 'privateSocketOnly': True}))
        self.save()

    def save(self):
        (self.root/'window-plan.json').write_text(json.dumps(self.value))

    def verify(self):
        # An offline plan must still work if all network/process entry points
        # are forbidden. The checker does not import or execute an ADB client.
        with patch('socket.socket', side_effect=AssertionError('Network forbidden')), patch('subprocess.Popen', side_effect=AssertionError('Processes forbidden')):
            return ready.verify(self.root, now=1000)

    def test_offline_plan_needs_no_phone_or_service(self):
        self.assertEqual(self.verify()['status'], 'READY_AWAITING_DEVICE')

    def test_apk_changed_rejected(self):
        (self.root/'artifacts/main.apk').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'APK identity or digest'):
            self.verify()

    def test_original_changed_rejected(self):
        (self.root/'fixtures/00.png').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Original fixture changed'):
            self.verify()

    def test_source_changed_rejected(self):
        (self.root/'source/apps/mobile/lib/main.dart').write_text('// changed')
        with self.assertRaisesRegex(ValueError, 'Prepared source changed'):
            self.verify()

    def test_less_than_thirty_minutes_trust_rejected(self):
        self.value['tlsLeafExpiresAtUnix'] = 2799
        self.save()
        with self.assertRaisesRegex(ValueError, 'TLS leaf expired'):
            self.verify()

    def test_unknown_owner_rejected(self):
        (self.root/'.owner').write_text('other-task')
        with self.assertRaisesRegex(ValueError, 'owned kit'):
            self.verify()

    def test_signing_mismatch_rejected(self):
        self.value['artifacts']['probe']['signerSha256'] = 'b'*64
        self.save()
        with self.assertRaisesRegex(ValueError, 'signing identity differs'):
            self.verify()

    def test_unstopped_backend_rejected(self):
        (self.root/'logs/server-preparation.json').write_text(json.dumps({'result': 'PASS', 'stopped': False, 'privateSocketOnly': True}))
        with self.assertRaisesRegex(ValueError, 'stop evidence incomplete'):
            self.verify()

    def test_no_old_android_target(self):
        self.value['artifacts']['main']['minimumApi'] = 24
        self.save()
        with self.assertRaisesRegex(ValueError, 'APK identity'):
            self.verify()

    def test_fixed_input_escape_rejected_before_read(self):
        self.value['fixedKitInputs']['../../other-task.key'] = 'x'
        self.save()
        with self.assertRaisesRegex(ValueError, 'fixed scope'):
            self.verify()

    def test_source_input_escape_rejected(self):
        self.value['sourceInputs']['../other-task/key'] = 'x'
        self.save()
        with self.assertRaisesRegex(ValueError, 'escaped component scope'):
            self.verify()

    def test_nine_originals_required(self):
        self.value['fixtures'].pop()
        self.save()
        with self.assertRaisesRegex(ValueError, 'nine distinct'):
            self.verify()

    def test_probe_refuses_existing_entry(self):
        with self.assertRaisesRegex(ValueError, 'already fixed'):
            probe.generate(self.root)

    def test_probe_rejects_fixture_escape(self):
        (self.root/'private/native-probe.dart').unlink()
        entries = copy.deepcopy(self.value['fixtures'])
        entries[0]['name'] = '../private/build-defines.json'
        (self.root/'fixtures/manifest.json').write_text(json.dumps({'syntheticOnly': True, 'originals': entries}))
        with self.assertRaisesRegex(ValueError, 'escaped kit'):
            probe.generate(self.root)

    def test_probe_rejects_unmarked_photos(self):
        (self.root/'private/native-probe.dart').unlink()
        (self.root/'fixtures/manifest.json').write_text(json.dumps({'syntheticOnly': False, 'originals': self.value['fixtures']}))
        with self.assertRaisesRegex(ValueError, 'synthetic originals required'):
            probe.generate(self.root)


if __name__ == '__main__':
    unittest.main()
