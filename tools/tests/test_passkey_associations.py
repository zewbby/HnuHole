import base64
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET


SPEC = importlib.util.spec_from_file_location('associations', Path(__file__).parents[1] / 'configure-passkey-associations.py')
associations = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(associations)


class PasskeyAssociationTests(unittest.TestCase):
    def values(self):
        return associations.artifacts('auth.example.invalid', 'org.hnuhole.synthetic', '12' * 32,
                                      'A1B2C3D4E5', 'org.hnuhole.synthetic')

    def test_same_certificate_generates_exact_runtime_origin_and_assetlinks(self):
        values = self.values()
        origin = values['web-authn.config.fragment.json']['webAuthn']['androidOrigins'][0]
        self.assertEqual(origin, 'android:apk-key-hash:' + base64.urlsafe_b64encode(bytes.fromhex('12' * 32)).decode().rstrip('='))
        fingerprint = values['assetlinks.json'][0]['target']['sha256_cert_fingerprints'][0]
        self.assertEqual(fingerprint, ':'.join(['12'] * 32))
        self.assertEqual(values['assetlinks.json'][0]['relation'], ['delegate_permission/common.get_login_creds'])
        resource = ET.fromstring(values['android-passkey-associations.xml']).find('string')
        self.assertEqual(json.loads(resource.text.replace('\\"', '"')), [{'include': 'https://auth.example.invalid/.well-known/assetlinks.json'}])
        snippet = ET.fromstring(values['android-passkey-manifest-snippet.xml'])
        self.assertEqual(snippet.get('{http://schemas.android.com/apk/res/android}resource'), '@string/asset_statements')

    def test_aasa_and_entitlement_use_only_supplied_ids(self):
        values = self.values()
        self.assertEqual(values['apple-app-site-association'], {'webcredentials': {'apps': ['A1B2C3D4E5.org.hnuhole.synthetic']}})
        self.assertEqual(values['Runner.Passkey.entitlements'], {'com.apple.developer.associated-domains': ['webcredentials:auth.example.invalid']})

    def test_single_platform_generation_does_not_fabricate_other_platform(self):
        ios = associations.artifacts('auth.example.invalid', ios_team_id='A1B2C3D4E5', ios_bundle_id='org.hnuhole.synthetic')
        self.assertNotIn('assetlinks.json', ios)
        self.assertEqual(ios['web-authn.config.fragment.json']['webAuthn']['androidOrigins'], [])
        android = associations.artifacts('auth.example.invalid', 'org.hnuhole.synthetic', '12:' * 31 + '12')
        self.assertNotIn('Runner.Passkey.entitlements', android)

    def test_invalid_domain_and_missing_or_placeholder_signing_material_fail(self):
        for rp in ['https://auth.example.invalid', 'Auth.Example.Invalid', '127.0.0.1', 'auth.example.invalid/path', 'example.invalid.', 'a' * 64 + '.invalid']:
            with self.assertRaises(ValueError):
                associations.artifacts(rp, 'org.hnuhole.synthetic', '12' * 32)
        for kwargs in [{}, {'android_package': 'org.hnuhole.synthetic'}, {'android_package': 'org.hnuhole.synthetic', 'android_cert_sha256': '00' * 32},
                       {'android_package': 'org.hnuhole.synthetic', 'android_cert_sha256': '12' * 31}, {'ios_team_id': 'fake', 'ios_bundle_id': 'org.hnuhole.synthetic'}]:
            with self.assertRaises(ValueError):
                associations.artifacts('auth.example.invalid', **kwargs)

    def test_new_private_directory_serializes_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-passkey-associations-') as parent:
            path = Path(parent) / 'new'
            associations.write_new_directory(path, self.values())
            self.assertEqual(path.stat().st_mode & 0o777, 0o700)
            for file in path.iterdir():
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads((path / 'assetlinks.json').read_text()), self.values()['assetlinks.json'])
            self.assertEqual(plistlib.loads((path / 'Runner.Passkey.entitlements').read_bytes()), self.values()['Runner.Passkey.entitlements'])
            previous = (path / 'assetlinks.json').read_bytes()
            with self.assertRaises(FileExistsError):
                associations.write_new_directory(path, self.values())
            self.assertEqual((path / 'assetlinks.json').read_bytes(), previous)


if __name__ == '__main__':
    unittest.main()
