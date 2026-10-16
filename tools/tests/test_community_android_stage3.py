import base64
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[2]
def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools/community-android-stage3' / file)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module
proposal = load('stage3_proposal_tests', 'proposal.py')
checker = load('stage3_dal_tests', 'check-association.py')


class Stage3PreparationTests(unittest.TestCase):
    def proof(self):
        return {'owner': proposal.OWNER, 'sourceCommit': '0c8e2470d6281785ba9e6ff647cfc2aa7fc19cc4',
                'deviceUsed': False, 'associationApplied': False,
                'badSignaturePayloadEqualsControl': True,
                'apks': {'control': {'applicationId': proposal.PACKAGE, 'certificateSha256': '12' * 32},
                         'unassociated': {'applicationId': proposal.MISSING_PACKAGE, 'certificateSha256': '12' * 32},
                         'badSignature': {'applicationId': proposal.PACKAGE, 'certificateSha256': '34' * 32}}}

    def test_exact_single_entry_origin_and_both_relations(self):
        files = proposal.values(ROOT, self.proof(), proposal.PROPOSED_RP)
        values = json.loads(files['site/.well-known/assetlinks.json'])
        self.assertEqual(len(values), 1)
        self.assertEqual(values[0]['target']['package_name'], proposal.PACKAGE)
        self.assertEqual(values[0]['target']['sha256_cert_fingerprints'], [':'.join(['12'] * 32)])
        self.assertEqual(values[0]['relation'], ['delegate_permission/common.get_login_creds', 'delegate_permission/common.handle_all_urls'])
        runtime = json.loads(files['runtime/web-authn.config.fragment.json'])['webAuthn']
        self.assertEqual(runtime['androidOrigins'], ['android:apk-key-hash:' + base64.urlsafe_b64encode(bytes.fromhex('12' * 32)).decode().rstrip('=')])
        self.assertEqual(runtime['rpId'], proposal.PROPOSED_RP)

    def test_authentication_session_rp_and_noncanonical_domain_refused(self):
        for rp in ['zewbby.github.io', 'anything.zewbby.github.io', 'https://rp.example', '127.0.0.1', 'RP.example', 'rp.example/path']:
            with self.assertRaises(ValueError):
                proposal.values(ROOT, self.proof(), rp)

    def test_signature_only_and_package_contrast_required(self):
        for field in ['package', 'same-signature', 'different-payload', 'wrong-unassociated-certificate']:
            proof = self.proof()
            if field == 'package': proof['apks']['control']['applicationId'] = 'org.hnuhole.hnuhole_mobile'
            if field == 'same-signature': proof['apks']['badSignature']['certificateSha256'] = '12' * 32
            if field == 'different-payload': proof['badSignaturePayloadEqualsControl'] = False
            if field == 'wrong-unassociated-certificate': proof['apks']['unassociated']['certificateSha256'] = '34' * 32
            with self.assertRaises(ValueError): proposal.values(ROOT, proof, proposal.PROPOSED_RP)

    def test_bundle_is_draft_not_an_approval_or_device_result(self):
        files = proposal.values(ROOT, self.proof(), proposal.PROPOSED_RP)
        record = json.loads(files['proposal.json'])
        for key in ['domainControlVerified', 'domainAvailabilityChecked', 'publicAssociationPublished', 'securityConfigurationApplied', 'deviceWindowGranted', 'deviceReadyApks']:
            self.assertIs(record[key], False)
        self.assertTrue(record['baselineApksNeedRebuildWithApprovedRPAndOwnTLSLab'])
        self.assertIn('review-only.patch', files)

    def test_negative_signature_and_package_never_enter_dal_or_server_trust(self):
        files = proposal.values(ROOT, self.proof(), proposal.PROPOSED_RP)
        for name in ['site/.well-known/assetlinks.json', 'runtime/web-authn.config.fragment.json']:
            self.assertNotIn(proposal.MISSING_PACKAGE, files[name])
            self.assertNotIn('34' * 32, files[name])
        self.assertTrue(all(v['expectedAssociation'] is False for v in json.loads(files['proposal.json'])['excludedNegativeControls']))

    def test_new_bundle_refuses_overwrite_and_preserves_repository(self):
        resource = ROOT / 'apps/mobile/android/app/src/debug/res/values/passkey_associations.xml'
        before = resource.read_bytes()
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / 'bundle'
            files = proposal.values(ROOT, self.proof(), proposal.PROPOSED_RP)
            proposal.write_new(destination, files)
            with self.assertRaises(FileExistsError): proposal.write_new(destination, files)
            self.assertEqual((destination / 'proposal.json').read_text(), files['proposal.json'])
        self.assertEqual(resource.read_bytes(), before)

    def test_no_confirmation_prevents_filesystem_and_network_access(self):
        with patch.object(checker.urllib.request, 'build_opener') as network:
            with self.assertRaises(ValueError): checker.check(Path('not-read'), False)
            network.assert_not_called()

    def test_redirects_always_rejected(self):
        with self.assertRaises(ValueError): checker.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.example')

    def test_exact_public_response_and_bounded_json_required(self):
        expected = [{'relation': ['reviewed'], 'target': {'namespace': 'android_app'}}]
        body = json.dumps(expected).encode()
        checker.validate_response(200, 'application/json; charset=utf-8', body, expected)
        for status, content, raw in [(301, 'application/json', body), (200, 'text/html', body), (200, 'application/json', b'[]'), (200, 'application/json', b' ' * 65537), (200, 'application/json', b'not-json')]:
            with self.assertRaises(ValueError): checker.validate_response(status, content, raw, expected)

    def test_truthful_tool_identifier_keeps_tls_redirect_and_exact_document_checks(self):
        files = proposal.values(ROOT, self.proof(), proposal.PROPOSED_RP)
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder) / 'bundle'
            proposal.write_new(bundle, files)
            response = MagicMock()
            response.status = 200
            response.headers = {'Content-Type': 'application/json'}
            response.read.return_value = files['site/.well-known/assetlinks.json'].encode()
            response.__enter__.return_value = response
            opener = MagicMock()
            opener.open.return_value = response
            with patch.object(checker.urllib.request, 'build_opener', return_value=opener) as build:
                result = checker.check(bundle, True)
            request = opener.open.call_args[0][0]
            self.assertEqual(request.get_header('User-agent'), checker.USER_AGENT)
            self.assertEqual(request.get_header('Accept'), 'application/json')
            self.assertEqual(request.full_url, 'https://' + proposal.PROPOSED_RP + '/.well-known/assetlinks.json')
            self.assertEqual(build.call_args[0][0].proxies, {})
            self.assertIsInstance(build.call_args[0][1], checker.NoRedirect)
            context = build.call_args[0][2]._context
            self.assertTrue(context.check_hostname)
            self.assertEqual(context.verify_mode, checker.ssl.CERT_REQUIRED)
            response.read.assert_called_once_with(65537)
            self.assertFalse(result['providerAcceptanceProved'])
            self.assertFalse(result['deviceUsed'])


if __name__ == '__main__':
    unittest.main()
