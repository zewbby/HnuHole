"""Prove signature-only APK contrasts retain exact source/config and ZIP payload."""
import copy
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
import warnings
import zipfile

SPEC = importlib.util.spec_from_file_location('fresh_signature_builder',
    Path(__file__).parents[1] / 'build-android-b3-b4-fresh.py')
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)
fresh = builder.FRESH


class SignaturePayloadTests(unittest.TestCase):
    def apk(self, root, name, entries):
        path = root / name
        with zipfile.ZipFile(path, 'w') as archive:
            for key, value in entries.items():
                archive.writestr(key, value)
        return path

    def payload(self):
        return {'classes.dex': b'actual product code', 'AndroidManifest.xml': b'approved package',
                'assets/flutter_assets/kernel_blob.bin': b'Flutter fixture',
                'lib/arm64-v8a/libflutter.so': b'arm64 runtime', 'META-INF/LICENSE': b'retained metadata'}

    def test_changed_signer_metadata_preserves_exact_product_payload(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-apk-contrast-') as temporary:
            root = Path(temporary)
            approved = self.apk(root, 'approved.apk', dict(self.payload(), **{
                'META-INF/MANIFEST.MF': b'old manifest', 'META-INF/APP.SF': b'old SF', 'META-INF/APP.RSA': b'old signer'}))
            wrong = self.apk(root, 'wrong.apk', dict(self.payload(), **{
                'META-INF/MANIFEST.MF': b'new manifest', 'META-INF/BAD.SF': b'new SF', 'META-INF/BAD.RSA': b'new signer'}))
            result = builder.exact_payload_contrast(approved, wrong)
            self.assertIs(result['signatureOnlyPayloadMatches'], True)
            self.assertEqual(result['payloadEntriesCompared'], len(self.payload()))
            self.assertEqual(len(result['signatureOnlyPayloadSha256']), 64)

    def test_changed_code_assets_or_non_signer_metadata_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-apk-contrast-') as temporary:
            root = Path(temporary)
            approved = self.apk(root, 'approved.apk', self.payload())
            for index, name in enumerate(('classes.dex', 'assets/flutter_assets/kernel_blob.bin', 'META-INF/LICENSE')):
                changed = self.payload()
                changed[name] = b'any changed bytes'
                wrong = self.apk(root, str(index) + '.apk', changed)
                with self.subTest(name=name), self.assertRaises(RuntimeError):
                    builder.exact_payload_contrast(approved, wrong)
            changed = self.payload()
            changed['META-INF/nested/APP.SF'] = b'not root signing metadata'
            wrong = self.apk(root, 'nested.apk', changed)
            with self.assertRaises(RuntimeError):
                builder.exact_payload_contrast(approved, wrong)

    def test_duplicate_zip_entries_cannot_hide_a_payload_difference(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-apk-contrast-') as temporary:
            root = Path(temporary)
            approved = self.apk(root, 'approved.apk', self.payload())
            wrong = self.apk(root, 'wrong.apk', self.payload())
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                with zipfile.ZipFile(wrong, 'a') as archive:
                    archive.writestr('classes.dex', b'hidden second entry')
            with self.assertRaises(RuntimeError):
                builder.exact_payload_contrast(approved, wrong)


class ApprovedSourceLedgerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='hnuhole-signature-ledger-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.linux, self.host = self.root / 'linux', self.root / 'host'
        self.mirror = self.linux / 'repo'
        self.mirror.mkdir(parents=True)
        self.host.mkdir()
        for name in fresh.SOURCE_SET:
            path = self.mirror / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'exact staged source')
        (self.linux / 'source-manifest.json').write_text('retained source admission')
        self.apk = self.host / 'b3b4-acceptance.apk'
        self.apk.write_bytes(b'retained approved fixture')
        self.config = {'AUTH_RUNTIME': 'synthetic'}
        config_hash = fresh.digest(json.dumps(dict(self.config, AUTH_B3B4_PACKAGE=fresh.PACKAGE), sort_keys=True).encode())
        self.record = dict(variant='approved', fileName=self.apk.name, apkSha256=builder.sha(self.apk),
            applicationId=fresh.PACKAGE, signingCertificateSha256=fresh.CERT,
            fixtureTarget=fresh.FIXTURE, configSha256=config_hash,
            actualProductFlutterRuntime=True, actualNativePasskeyAndVaultPlugins=True,
            nativeDebugSymbolsStripped=True, buildOverlaySha256='a' * 64, mainManifestOverlaySha256='b' * 64)
        self.ledger = dict(owner=fresh.TOKEN, apks=[self.record],
            sourceManifestSha256=builder.sha(self.linux / 'source-manifest.json'),
            sourceFilesSha256={name: builder.sha(self.mirror / name) for name in fresh.SOURCE_SET})
        self.patcher = mock.patch.multiple(fresh, LINUX=self.linux, HOST=self.host)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_exact_approved_ledger_and_apk_are_required(self):
        apk, record = builder.approved_signing_source(self.ledger, self.mirror, self.config)
        self.assertEqual(apk, self.apk)
        self.assertEqual(record['apkSha256'], builder.sha(self.apk))
        self.apk.write_bytes(b'changed approved APK')
        with self.assertRaises(RuntimeError):
            builder.approved_signing_source(self.ledger, self.mirror, self.config)

    def test_wrong_configuration_source_or_duplicate_approved_record_is_rejected(self):
        alternatives = []
        wrong = copy.deepcopy(self.ledger)
        wrong['apks'][0]['configSha256'] = 'f' * 64
        alternatives.append(wrong)
        wrong = copy.deepcopy(self.ledger)
        wrong['sourceManifestSha256'] = 'e' * 64
        alternatives.append(wrong)
        wrong = copy.deepcopy(self.ledger)
        wrong['sourceFilesSha256'][fresh.SOURCE_SET[0]] = 'd' * 64
        alternatives.append(wrong)
        wrong = copy.deepcopy(self.ledger)
        wrong['apks'].append(copy.deepcopy(wrong['apks'][0]))
        alternatives.append(wrong)
        for index, ledger in enumerate(alternatives):
            with self.subTest(index=index), self.assertRaises(RuntimeError):
                builder.approved_signing_source(ledger, self.mirror, self.config)


class PreparedPubRouteTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='hnuhole-pub-route-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.linux, self.host, self.canonical = (self.root / name for name in ('linux', 'host', 'canonical'))
        self.mirror = self.linux / 'repo'
        # The frozen authentication-only builder admits its reviewed lock,
        # not whichever dependency graph the integrating product now has.
        # Normalize checkout line endings only for this text fixture; the
        # builder still requires the exact reviewed LF bytes.
        self.original = (Path(__file__).parent / 'fixtures' /
                         'auth-canonical-pubspec-d859cb05.lock').read_text(encoding='utf-8').encode('utf-8')
        self.routed = builder.pub_lock_route_bytes(self.original)
        for directory in (self.mirror, self.canonical):
            path = directory / builder.LOCK_NAME
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(self.original)
        self.host.mkdir()
        (self.mirror / 'product-source.txt').write_bytes(b'exact reviewed code')
        self.admission = dict(owner=fresh.TOKEN, stagedFilesSha256={
            builder.LOCK_NAME: builder.LOCK_ROUTE_SOURCE_SHA256,
            'product-source.txt': builder.sha(self.mirror / 'product-source.txt')})
        self.manifest = self.linux / 'source-manifest.json'
        self.manifest.write_text(json.dumps(self.admission))
        self.patcher = mock.patch.multiple(fresh, LINUX=self.linux, HOST=self.host, REPO=self.canonical)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_community_lock_is_not_admitted_by_the_frozen_authentication_builder(self):
        current = (Path(__file__).parents[2] / builder.LOCK_NAME).read_bytes()
        if fresh.digest(current) != builder.LOCK_ROUTE_SOURCE_SHA256:
            with self.assertRaises(RuntimeError):
                builder.pub_lock_route_bytes(current)
        # A changed version/checksum fails even when the approved URL count stays.
        with self.assertRaises(RuntimeError):
            builder.pub_lock_route_bytes(self.original + b'changed dependency bytes')

    def test_builder_still_rejects_unreviewed_crlf_lock_bytes(self):
        crlf = self.original.replace(b'\n', b'\r\n')
        self.assertNotEqual(fresh.digest(crlf), builder.LOCK_ROUTE_SOURCE_SHA256)
        with self.assertRaises(RuntimeError):
            builder.pub_lock_route_bytes(crlf)

    def test_explicit_route_records_identical_receipts_and_preserves_original_admission(self):
        before = self.manifest.read_bytes()
        self.assertIsNone(builder.verify_prepared_sources(self.mirror, self.admission))
        receipt = builder.verify_prepared_sources(self.mirror, self.admission, True, True)
        self.assertEqual((self.mirror / builder.LOCK_NAME).read_bytes(), self.routed)
        self.assertEqual((self.canonical / builder.LOCK_NAME).read_bytes(), self.original)
        self.assertEqual(self.manifest.read_bytes(), before)
        linux = self.linux / 'pub-lock-route-overlay.json'
        host = self.host / 'b3b4-evidence/pub-lock-route-overlay.json'
        self.assertEqual(linux.read_bytes(), host.read_bytes())
        self.assertEqual(receipt['receiptSha256'], builder.sha(host))
        self.assertEqual(receipt['replacements'], 34)
        self.assertEqual(builder.verify_prepared_sources(self.mirror, self.admission), receipt)

    def test_known_route_without_explicit_receipt_is_rejected(self):
        (self.mirror / builder.LOCK_NAME).write_bytes(self.routed)
        with self.assertRaises(RuntimeError):
            builder.verify_prepared_sources(self.mirror, self.admission)
        with self.assertRaises(RuntimeError):
            builder.verify_prepared_sources(self.mirror, self.admission, True, False)

    def test_changed_code_or_lock_dependency_bytes_are_rejected_before_receipt(self):
        (self.mirror / 'product-source.txt').write_bytes(b'changed actual product')
        with self.assertRaises(RuntimeError):
            builder.verify_prepared_sources(self.mirror, self.admission, True, True)
        self.assertFalse((self.linux / 'pub-lock-route-overlay.json').exists())
        (self.mirror / 'product-source.txt').write_bytes(b'exact reviewed code')
        (self.mirror / builder.LOCK_NAME).write_bytes(self.routed + b'changed dependency bytes')
        with self.assertRaises(RuntimeError):
            builder.verify_prepared_sources(self.mirror, self.admission, True, True)

    def test_changed_canonical_manifest_or_receipt_is_rejected(self):
        receipt = builder.verify_prepared_sources(self.mirror, self.admission, True, True)
        linux = self.linux / 'pub-lock-route-overlay.json'
        exact = linux.read_bytes()
        linux.write_bytes(exact + b' ')
        with self.assertRaises(RuntimeError):
            builder.verify_prepared_sources(self.mirror, self.admission)
        linux.write_bytes(exact)
        (self.canonical / builder.LOCK_NAME).write_bytes(self.original + b' changed')
        with self.assertRaises(RuntimeError):
            builder.verify_prepared_sources(self.mirror, self.admission)
        (self.canonical / builder.LOCK_NAME).write_bytes(self.original)
        self.manifest.write_text(json.dumps(dict(self.admission, extra='changed source manifest')))
        with self.assertRaises(RuntimeError):
            builder.verify_prepared_sources(self.mirror, self.admission)
        self.assertEqual(receipt['stagedSha256'], builder.LOCK_ROUTE_TARGET_SHA256)


class NativeSigningTests(unittest.TestCase):
    def elf(self, extra=(), machine=183):
        strings = b'\0.shstrtab\0' + b''.join(name.encode() + b'\0' for name, _ in extra)
        section_offset = 128
        count = 2 + len(extra)
        header = struct.pack('<16sHHIQQQIHHHHHH', b'\x7fELF\x02\x01\x01' + b'\0' * 9,
            3, machine, 1, 0, 0, section_offset, 0, 64, 0, 0, 64, count, 1)
        sections = [b'\0' * 64, struct.pack('<IIQQQQIIQQ', 1, 3, 0, 0, 64, len(strings), 0, 0, 1, 0)]
        for name, kind in extra:
            sections.append(struct.pack('<IIQQQQIIQQ', strings.index(name.encode()), kind, 0, 0, 0, 0, 0, 0, 1, 0))
        return header + strings + b'\0' * (section_offset - 64 - len(strings)) + b''.join(sections)

    def test_actual_native_debug_sections_and_symbol_tables_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-native-sections-') as temporary:
            path = Path(temporary) / 'native.apk'
            library = 'lib/arm64-v8a/libflutter.so'
            for sections in ((('.debug_info', 1),), (('.symtab', 2),), (('.gnu_debugdata', 1),)):
                with zipfile.ZipFile(path, 'w') as output:
                    output.writestr(library, self.elf(sections))
                with zipfile.ZipFile(path) as archive, self.subTest(sections=sections), self.assertRaises(RuntimeError):
                    builder.verify_packaged_native_symbols(archive, [library])
            with zipfile.ZipFile(path, 'w') as output:
                output.writestr(library, self.elf((('.dynsym', 11),)))
            with zipfile.ZipFile(path) as archive:
                facts = builder.verify_packaged_native_symbols(archive, [library])
            self.assertEqual(facts[library]['elfMachine'], 'AARCH64')
            self.assertEqual(facts[library]['debugSections'], [])
            self.assertEqual(facts[library]['nonDynamicSymbolTables'], [])

    def test_malformed_or_wrong_architecture_library_never_claims_stripped(self):
        for value in (b'not an ELF', self.elf(machine=62), self.elf()[:-2]):
            with self.subTest(value=value[:8]), self.assertRaises(RuntimeError):
                builder.elf_symbol_sections(value)

    def test_same_password_signing_uses_single_store_password_reader(self):
        command = builder.signer_command(Path('/sdk'), builder.VARIANTS['approved'], Path('/input.apk'), Path('/output.apk'))
        self.assertEqual(command.count('--ks-pass'), 1)
        self.assertNotIn('--key-pass', command)
        self.assertEqual(command[-3:], ['--out', str(Path('/output.apk')), str(Path('/input.apk'))])

    def test_native_strip_guard_checks_dispatch_and_only_reruns_the_strip_task(self):
        with tempfile.TemporaryDirectory(prefix='hnuhole-native-strip-') as temporary:
            root = Path(temporary)
            env = {'ANDROID_HOME': str(root / 'sdk')}
            with mock.patch.object(builder.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=b'llvm-strip, compatible with GNU strip', stderr=b'')) as command:
                init = builder.native_strip_guard(root, env)
                self.assertEqual(command.call_args.args[0][-1], '--version')
                self.assertEqual(command.call_args.kwargs['env'], env)
                self.assertIn("findByName('stripDebugDebugSymbols')", init.read_text())
                self.assertIn('gradle.parent != null', init.read_text())
                self.assertIn('outputs.upToDateWhen { false }', init.read_text())
                self.assertEqual(builder.native_strip_guard(root, env), init)
                init.write_text('unreviewed task changes')
                with self.assertRaises(RuntimeError):
                    builder.native_strip_guard(root, env)
            with mock.patch.object(builder.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=b'llvm-objcopy', stderr=b'')):
                with self.assertRaises(RuntimeError):
                    builder.native_strip_guard(root, env)


if __name__ == '__main__':
    unittest.main()
