import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('candidate', Path(__file__).parents[1] / 'candidate.py')
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class PackagedManifestTest(unittest.TestCase):
    xml = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.hnuhole.hnuhole_mobile" android:versionName="0.1.0" android:versionCode="123"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="36"/><application android:allowBackup="false"/></manifest>'''

    def test_actual_package_metadata(self):
        self.assertEqual(candidate.verify_manifest(self.xml, '0.1.0', 123)['minSdk'], 29)

    def test_reject_debug_backup_and_identity_drift(self):
        for modified in (
            self.xml.replace('<application ', '<application android:debuggable="true" '),
            self.xml.replace('allowBackup="false"', 'allowBackup="true"'),
            self.xml.replace('org.hnuhole.hnuhole_mobile', 'org.example.foreign'),
            self.xml.replace('/></manifest>', '><meta-data android:name="asset_statements"/></application></manifest>'),
        ):
            with self.subTest(xml=modified), self.assertRaises((RuntimeError, candidate.ET.ParseError)):
                candidate.verify_manifest(modified, '0.1.0', 123)

    def test_reject_packaged_version_drift(self):
        with self.assertRaises(RuntimeError):
            candidate.verify_manifest(self.xml, '0.1.0', 124)


if __name__ == '__main__':
    unittest.main()
