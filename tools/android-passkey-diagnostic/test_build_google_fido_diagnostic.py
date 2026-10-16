"""Host guards for fresh diagnostic identity, scope, payload and manifest checks."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location('diagnostic_build',
    Path(__file__).with_name('build-google-fido-diagnostic.py'))
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)
PACKAGE = 'org.hnuhole.hnuhole_mobile.acceptance20261012'
CERT = '1' * 64
POLICY = '\n'.join(('static final String PACKAGE = "' + BUILD.PACKAGE + '";',
                    'static final String CERT = "' + BUILD.CERT + '";'))
MANIFEST = ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
            'package="' + PACKAGE + '"><application android:debuggable="true">'
            '<activity android:name="' + BUILD.ACTIVITY + '" android:exported="true" android:excludeFromRecents="true" '
            'android:taskAffinity="" android:theme="@android:style/Theme.Material.Light.NoActionBar" '
            'android:configChanges="orientation|keyboardHidden|screenSize|smallestScreenSize|uiMode" />'
            '<meta-data android:name="asset_statements" android:resource="@string/asset_statements" />'
            '</application></manifest>')
DEX = (b'GoogleFidoDiagnosticActivity GoogleFidoDiagnosticPolicy '
       b'Lcom/google/android/gms/fido/fido2/Fido2ApiClient;')


class FreshBuildGuards(unittest.TestCase):
    def test_staging_changes_only_exact_identity_constants(self):
        staged = BUILD.fresh_identity(POLICY, PACKAGE, CERT)
        self.assertIn('PACKAGE = "' + PACKAGE + '";', staged)
        self.assertIn('CERT = "' + CERT + '";', staged)
        self.assertEqual(POLICY, '\n'.join((
            'static final String PACKAGE = "' + BUILD.PACKAGE + '";',
            'static final String CERT = "' + BUILD.CERT + '";')))

    def test_refuse_product_and_legacy_packages_and_invalid_certificate(self):
        for package in ('org.hnuhole.hnuhole_mobile', BUILD.PACKAGE, PACKAGE + '.evil', '../elsewhere'):
            with self.subTest(package=package), self.assertRaises(AssertionError):
                BUILD.fresh_identity(POLICY, package, CERT)
        with self.assertRaises(AssertionError):
            BUILD.fresh_identity(POLICY, PACKAGE, 'not-a-certificate')
        with self.assertRaises(AssertionError):
            BUILD.fresh_identity(POLICY + POLICY, PACKAGE, CERT)

    def check_archive(self, manifest=MANIFEST, dex=DEX, extra=None):
        with tempfile.TemporaryDirectory() as temporary:
            apk = Path(temporary) / 'diagnostic.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('classes.dex', dex)
                if extra:
                    archive.writestr(extra, b'forbidden payload')
            BUILD.validate_fresh_apk(apk, manifest, PACKAGE)

    def test_minimal_fido_payload_accepts(self):
        self.check_archive()

    def test_refuse_non_debug_manifest_wrong_package_and_extra_activity(self):
        invalid = [MANIFEST.replace('debuggable="true"', 'debuggable="false"'),
                   MANIFEST.replace(PACKAGE, BUILD.PACKAGE),
                   MANIFEST.replace('</application>', '<activity android:name="Another" /></application>')]
        for manifest in invalid:
            with self.subTest(manifest=manifest), self.assertRaises(AssertionError):
                self.check_archive(manifest=manifest)

    def test_refuse_native_flutter_product_and_missing_fido_payloads(self):
        for extra in ('lib/arm64-v8a/libflutter.so', 'lib/x86_64/unknown.so', 'assets/flutter_assets/kernel_blob.bin'):
            with self.subTest(extra=extra), self.assertRaises(AssertionError):
                self.check_archive(extra=extra)
        with self.assertRaises(AssertionError):
            self.check_archive(dex=DEX + b' org/hnuhole/authvault')
        with self.assertRaises(AssertionError):
            self.check_archive(dex=b'GoogleFidoDiagnosticActivity GoogleFidoDiagnosticPolicy')

    def test_groovy_path_and_alias_are_data(self):
        self.assertEqual(BUILD.groovy_string("/owned/user's $file"), "'/owned/user\\'s $file'")
        gradle = BUILD.standalone_build_gradle("/owned/user's/key.p12", 'alias')
        self.assertIn("storeFile file('/owned/user\\'s/key.p12')", gradle)
        self.assertIn("debugImplementation('com.google.android.gms:play-services-fido:21.0.0')", gradle)
        self.assertNotIn("implementation('com.google.android.gms", gradle)

    def test_android_side_dal_is_fixed_and_required(self):
        BUILD.validate_asset_statements('[{"include":"' + BUILD.ASSETLINKS + '"}]')
        BUILD.validate_asset_statements('[{\\"include\\":\\"' + BUILD.ASSETLINKS + '\\"}]')
        for value in ('[]', '[{"include":"https://other.example/.well-known/assetlinks.json"}]'):
            with self.subTest(value=value), self.assertRaises(AssertionError):
                BUILD.validate_asset_statements(value)
        with self.assertRaises(AssertionError):
            self.check_archive(manifest=MANIFEST.replace('asset_statements', 'other_metadata'))
        with self.assertRaises(AssertionError):
            self.check_archive(manifest=MANIFEST.replace('keyboardHidden|', ''))

    def test_exact_non_exported_google_sdk_manifest_contributions(self):
        sdk = ('<activity android:name="com.google.android.gms.common.api.GoogleApiActivity" '
               'android:theme="@android:style/Theme.Translucent.NoTitleBar" android:exported="false" />'
               '<meta-data android:name="com.google.android.gms.version" android:value="@integer/google_play_services_version" />')
        merged = MANIFEST.replace('</application>', sdk + '</application>')
        self.check_archive(manifest=merged)
        self.check_archive(manifest=merged.replace('orientation|keyboardHidden|screenSize|smallestScreenSize|uiMode', '0x00000ea0'))
        for changed in (merged.replace('GoogleApiActivity', 'OtherActivity'),
                        merged.replace('android:exported="false"', 'android:exported="true"'),
                        merged.replace('com.google.android.gms.version', 'unreviewed_metadata'),
                        merged.replace('orientation|keyboardHidden|screenSize|smallestScreenSize|uiMode', '0x00000ea1')):
            with self.subTest(manifest=changed), self.assertRaises(AssertionError):
                self.check_archive(manifest=changed)


if __name__ == '__main__':
    unittest.main()
