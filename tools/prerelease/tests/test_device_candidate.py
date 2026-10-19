import importlib.util
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
spec = importlib.util.spec_from_file_location('device_candidate', Path(__file__).parents[1] / 'device_candidate.py')
device = importlib.util.module_from_spec(spec)
spec.loader.exec_module(device)


class DeviceBoundaryTest(unittest.TestCase):
    def test_reject_external_cleartext_duplicate_and_ambiguous_origins(self):
        c, v = 'https://127.0.0.1:49291', 'https://127.0.0.1:59947'
        device.validate_origins(c, v)
        for invalid in ('http://127.0.0.1:49291', 'https://example.com:49291', c + '/',
                        c + '?secret=x', 'https://user@127.0.0.1:49291', 'https://127.0.0.1:443', v):
            with self.subTest(origin=invalid), self.assertRaises((RuntimeError, ValueError)):
                device.validate_origins(invalid, v)

    def test_device_manifest_requires_explicit_profile_and_same_identity(self):
        xml = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.hnuhole.hnuhole_mobile" android:versionName="0.1.0" android:versionCode="123"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="36"/><application android:allowBackup="false" android:debuggable="true" android:label="HnuHole Prerelease Test" android:usesCleartextTraffic="false"/></manifest>'''
        self.assertTrue(device.verify_manifest(xml, '0.1.0', 123, debug=True)['debuggable'])
        for invalid in (xml.replace('HnuHole Prerelease Test', 'hnuhole_mobile'),
                        xml.replace('usesCleartextTraffic="false"', 'usesCleartextTraffic="true"'),
                        xml.replace('debuggable="true"', 'debuggable="false"'),
                        xml.replace('org.hnuhole.hnuhole_mobile', 'org.hnuhole.other'),
                        xml.replace('/></manifest>', '><meta-data android:name="asset_statements"/></application></manifest>')):
            with self.subTest(xml=invalid), self.assertRaises(RuntimeError):
                device.verify_manifest(invalid, '0.1.0', 123, debug=True)


if __name__ == '__main__':
    unittest.main()
