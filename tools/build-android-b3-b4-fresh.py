#!/usr/bin/env python3
"""Build the actual product B3/B4 fixture in the fresh source mirror, without a phone.

Run after prepare-android-b3-b4-fresh.py --execute. The locked source mirror is
used with normal AGP native stripping, one arm64 ABI, and explicit fresh signing.
Canonical sources, historical artifacts, and installed applications are untouched.
"""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import time
import zipfile


SPEC = importlib.util.spec_from_file_location('fresh_b3b4', Path(__file__).with_name('prepare-android-b3-b4-fresh.py'))
FRESH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FRESH)
BAD_CERT = 'cc8fb1ee0048d854831a1886971bc8013f68a34e9ee51210885c6fee6c113ce7'
LOCK_ROUTE_SOURCE_SHA256 = '3f1896969f3ed1bec71f75bea42cd6bce5989542013cb4d5ce3c225435bc2a51'
LOCK_ROUTE_TARGET_SHA256 = 'd81ec9b5a5b626bb88797d6dc20b89dea0811682a696dfae69d3717fcb067510'
LOCK_NAME = 'apps/mobile/pubspec.lock'
SIGNING = Path('/mnt/e/Hnuhole-env/acceptance-20261012/signing')
VARIANTS = {
    'approved': dict(package=FRESH.PACKAGE, cert=FRESH.CERT, keystore='acceptance.p12',
                     alias='b3b4-20261012', files=['phone-b3b4.apk', 'b3b4-acceptance.apk']),
    'bad-signature': dict(package=FRESH.PACKAGE, cert=BAD_CERT, keystore='unapproved.p12',
                         alias='b3b4-unapproved-20261012', files=['b3b4-bad-signature.apk']),
    'missing-package': dict(package=FRESH.MISSING_PACKAGE, cert=FRESH.CERT, keystore='acceptance.p12',
                           alias='b3b4-20261012', files=['b3b4-unassociated.apk']),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pub_lock_route_bytes(original):
    """The reviewed whole-file URL substitution preserves every dependency byte."""
    before, after = b'https://pub.flutter-io.cn', b'https://pub.dev'
    if FRESH.digest(original) != LOCK_ROUTE_SOURCE_SHA256 or original.count(before) != 34:
        raise RuntimeError('Exact reviewed canonical Pub lock required for hosted URL overlay')
    routed = original.replace(before, after)
    if FRESH.digest(routed) != LOCK_ROUTE_TARGET_SHA256:
        raise RuntimeError('Exact reviewed routed Pub lock required')
    return routed


def verify_prepared_sources(mirror, admission, allow_pub_route=False, record_pub_route=False):
    """Validate all prepared bytes; only an explicit, recorded route overlay can differ."""
    manifest = FRESH.LINUX / 'source-manifest.json'
    if (manifest.is_symlink() or json.loads(manifest.read_text()) != admission
            or admission.get('owner') != FRESH.TOKEN):
        raise RuntimeError('Exact retained prepared source admission required')
    manifest_hash = sha(manifest)
    root = mirror.resolve()
    changed = []
    for name, expected in admission['stagedFilesSha256'].items():
        path = mirror / name
        if (path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root)
                or not isinstance(expected, str) or not re.fullmatch('[a-f0-9]{64}', expected)):
            raise RuntimeError('Exact regular prepared source files required')
        if sha(path) != expected:
            changed.append(name)
    if any(name != LOCK_NAME for name in changed):
        raise RuntimeError('Prepared source mirror changed; inspect before building')
    receipt_path = FRESH.LINUX / 'pub-lock-route-overlay.json'
    host_receipt = FRESH.HOST / 'b3b4-evidence/pub-lock-route-overlay.json'
    if receipt_path.is_symlink() or host_receipt.is_symlink():
        raise RuntimeError('Exact regular hosted URL overlay receipt required')
    if not allow_pub_route and not changed and not receipt_path.exists():
        return None
    if not allow_pub_route and not receipt_path.is_file():
        raise RuntimeError('Prepared Pub lock changed without an explicitly recorded URL route overlay')
    canonical = FRESH.REPO / LOCK_NAME
    if (admission['stagedFilesSha256'].get(LOCK_NAME) != LOCK_ROUTE_SOURCE_SHA256
            or canonical.is_symlink() or not canonical.is_file()):
        raise RuntimeError('Pinned original Pub lock admission required')
    routed = pub_lock_route_bytes(canonical.read_bytes())
    lock = mirror / LOCK_NAME
    current = lock.read_bytes()
    original = canonical.read_bytes()
    if current not in (original, routed):
        raise RuntimeError('Pub lock differs beyond the exact hosted URL substitutions')
    receipt = dict(schemaVersion=1, owner=FRESH.TOKEN, sourceManifestSha256=manifest_hash,
        scope='EXACT_WHOLE_FILE_HOSTED_URL_SUBSTITUTION_ONLY', sourceFile=LOCK_NAME,
        sourceSha256=LOCK_ROUTE_SOURCE_SHA256, stagedSha256=LOCK_ROUTE_TARGET_SHA256,
        previousHostedUrl='https://pub.flutter-io.cn', hostedUrl='https://pub.dev', replacements=34,
        dependencyNamesVersionsAndContentDigestsPreserved=True, sourceLockModified=False,
        actualDeviceAcceptancePassed=False)
    receipt_bytes = (json.dumps(receipt, indent=2, ensure_ascii=False) + '\n').encode()
    if receipt_path.exists() and receipt_path.read_bytes() != receipt_bytes:
        raise RuntimeError('Retained hosted URL overlay receipt changed')
    if host_receipt.exists() and host_receipt.read_bytes() != receipt_bytes:
        raise RuntimeError('Transferred hosted URL overlay receipt changed')
    if allow_pub_route and record_pub_route:
        if not receipt_path.exists():
            with receipt_path.open('xb') as output:
                output.write(receipt_bytes)
        if not host_receipt.exists():
            host_receipt.parent.mkdir(parents=True, exist_ok=True)
            with host_receipt.open('xb') as output:
                output.write(receipt_bytes)
        if current == original:
            lock.write_bytes(routed)
    if (not receipt_path.is_file() or not host_receipt.is_file()
            or receipt_path.read_bytes() != receipt_bytes or host_receipt.read_bytes() != receipt_bytes
            or lock.read_bytes() != routed or sha(manifest) != manifest_hash):
        raise RuntimeError('Recorded exact hosted URL overlay and immutable source admission required')
    return dict(receipt, receiptFileName=host_receipt.name, receiptSha256=FRESH.digest(receipt_bytes))


def signature_entry(name):
    return re.fullmatch(r'META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC)|SIG-[^/]+)',
                        name, flags=re.IGNORECASE) is not None


def payload_entries(apk):
    """Preserve every ZIP entry except the defined JAR signing metadata."""
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise RuntimeError('Duplicate APK ZIP entries cannot establish an exact signing contrast')
        payload = {}
        for name in names:
            if signature_entry(name):
                continue
            digest = hashlib.sha256()
            with archive.open(name) as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            payload[name] = dict(bytes=archive.getinfo(name).file_size, sha256=digest.hexdigest())
    if not payload:
        raise RuntimeError('APK payload is absent')
    return payload


def exact_payload_contrast(approved, resigned):
    entries = payload_entries(approved)
    if entries != payload_entries(resigned):
        raise RuntimeError('Wrong-certificate APK differs from the exact approved payload')
    digest = FRESH.digest(json.dumps(entries, sort_keys=True, separators=(',', ':')).encode())
    return dict(signatureOnlyPayloadMatches=True, payloadEntriesCompared=len(entries),
                signatureOnlyPayloadSha256=digest,
                signatureMetadataExclusion='META-INF/MANIFEST.MF, root SF/RSA/DSA/EC and SIG-* signer entries only')


def approved_signing_source(prior, mirror, config):
    """A retained approved artifact and its exact source/config ledger are required."""
    if (prior.get('owner') != FRESH.TOKEN
            or prior.get('sourceManifestSha256') != sha(FRESH.LINUX / 'source-manifest.json')
            or prior.get('sourceFilesSha256') != {name: sha(mirror / name) for name in FRESH.SOURCE_SET}):
        raise RuntimeError('Exact approved source ledger required before signature-only contrast')
    approved = [record for record in prior['apks']
                if record.get('variant') == 'approved' and record.get('fileName') == 'b3b4-acceptance.apk']
    if len(approved) != 1:
        raise RuntimeError('Build and retain exactly one approved product APK before wrong-certificate signing')
    record = approved[0]
    settings = dict(config, AUTH_B3B4_PACKAGE=FRESH.PACKAGE)
    expected_config = FRESH.digest(json.dumps(settings, sort_keys=True).encode())
    if (record.get('applicationId') != FRESH.PACKAGE
            or record.get('signingCertificateSha256') != FRESH.CERT
            or record.get('fixtureTarget') != FRESH.FIXTURE
            or record.get('configSha256') != expected_config
            or record.get('actualProductFlutterRuntime') is not True
            or record.get('actualNativePasskeyAndVaultPlugins') is not True
            or record.get('nativeDebugSymbolsStripped') is not True
            or not all(isinstance(record.get(name), str) and re.fullmatch('[a-f0-9]{64}', record[name])
                       for name in ('buildOverlaySha256', 'mainManifestOverlaySha256'))):
        raise RuntimeError('Approved product APK configuration or identity changed')
    apk = FRESH.HOST / record['fileName']
    if apk.is_symlink() or not apk.is_file() or sha(apk) != record['apkSha256']:
        raise RuntimeError('Retained approved product APK changed')
    return apk, record


def execute(command, cwd, log, timeout=1800, env=None):
    with log.open('a') as output:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        raise RuntimeError('Actual product build failed; inspect the owned private build log')


def signer_command(sdk, variant, candidate, output):
    # The fresh PKCS12 key has the same password as its store. apksigner's
    # default reuses that value; a second file reader consumes another line.
    return [str(sdk / 'build-tools/36.0.0/apksigner'), 'sign',
        '--ks', str(SIGNING / variant['keystore']), '--ks-key-alias', variant['alias'],
        '--ks-pass', 'file:' + str(SIGNING / 'store.password'),
        '--out', str(output), str(candidate)]


def native_strip_guard(root, environment):
    tool = Path(environment['ANDROID_HOME']) / 'ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
    probe = subprocess.run([str(tool), '--version'], capture_output=True, timeout=20, env=environment)
    if probe.returncode != 0 or b'llvm-strip' not in probe.stdout + probe.stderr:
        raise RuntimeError('Verified NDK llvm-strip dispatch required; preserve a broken SDK alias')
    content = ('''// HNUHOLE_B3B4_FRESH_20261012_V1: rerun only normal AGP native stripping.
gradle.projectsEvaluated {
    if (gradle.parent != null) return
    def app = rootProject.findProject(':app')
    if (app == null) throw new GradleException('Exact product app project required')
    def strip = app.tasks.findByName('stripDebugDebugSymbols')
    if (strip == null) throw new GradleException('Normal AGP debug stripping task required')
    strip.outputs.upToDateWhen { false }
    strip.outputs.cacheIf { false }
}
''').encode()
    path = root / 'product-native-stripping.init.gradle'
    if path.is_symlink() or (path.exists() and path.read_bytes() != content):
        raise RuntimeError('Preserve an unexpected native stripping init script')
    if not path.exists():
        with path.open('xb') as output:
            output.write(content)
    return path


def elf_symbol_sections(data):
    """Read actual arm64 ELF sections without relying on an SDK readelf alias."""
    if len(data) < 64 or data[:7] != b'\x7fELF\x02\x01\x01':
        raise RuntimeError('Exact arm64 little-endian ELF64 library required')
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    offset, entry_bytes, count, string_index = header[6], header[11], header[12], header[13]
    if (header[1:4] != (3, 183, 1) or header[8] != 64 or entry_bytes != 64
            or count < 2 or not 0 < string_index < count or offset < 64
            or offset + entry_bytes * count > len(data)):
        raise RuntimeError('Bounded actual shared-library section table required')
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + index * entry_bytes)
                for index in range(count)]
    strings = sections[string_index]
    if strings[1] != 3 or strings[5] < 1 or strings[4] + strings[5] > len(data):
        raise RuntimeError('Bounded ELF section names required')
    names = data[strings[4]:strings[4] + strings[5]]
    debug, symbols = [], []
    for section in sections:
        name_start = section[0]
        if name_start >= len(names):
            raise RuntimeError('Invalid ELF section name offset')
        name_end = names.find(b'\0', name_start)
        if name_end < 0:
            raise RuntimeError('Unterminated ELF section name')
        name = names[name_start:name_end].decode('ascii')
        if name.startswith(('.debug', '.zdebug')) or name in ('.gnu_debugdata', '.gdb_index'):
            debug.append(name)
        if section[1] == 2:
            symbols.append(name)
    return dict(elfClass=64, elfMachine='AARCH64', sectionCount=count,
                debugSections=debug, nonDynamicSymbolTables=symbols)


def verify_packaged_native_symbols(archive, libraries):
    evidence = {}
    for name in libraries:
        facts = elf_symbol_sections(archive.read(name))
        if facts['debugSections'] or facts['nonDynamicSymbolTables']:
            raise RuntimeError('Actual packaged native library retains debug symbols; rerun verified AGP stripping')
        evidence[name] = facts
    return evidence


def variant_gradle(source, package):
    revised = FRESH.replace_exact(source, 'applicationId = "' + FRESH.MAIN_PACKAGE + '"',
        'applicationId = "' + package + '"\n        ndk { abiFilters.clear(); abiFilters.add("arm64-v8a") }', 1)
    # The optional Vulkan validation layer is a developer graphics diagnostic;
    # neither the product nor native authentication plugins load this library.
    revised = FRESH.replace_exact(revised, '    buildTypes {',
        '    packaging { jniLibs { excludes.add("**/libVkLayer_khronos_validation.so") } }\n\n    buildTypes {', 1)
    return revised


def validate_apk(apk, variant, sdk, maximum_bytes):
    if not apk.is_file() or not 1000000 < apk.stat().st_size <= maximum_bytes:
        raise RuntimeError('Product APK size is outside the reviewed bounded range; preserve the candidate')
    signer = sdk / 'build-tools/36.0.0/apksigner'
    signed = subprocess.run([str(signer), 'verify', '--print-certs', str(apk)],
                            capture_output=True, text=True, check=True)
    certificates = re.findall(r'Signer #[0-9]+ certificate SHA-256 digest: ([a-f0-9]{64})', signed.stdout)
    if certificates != [variant['cert']]:
        raise RuntimeError('Product APK signing certificate mismatch')
    analyzer = sdk / 'cmdline-tools/latest/bin/apkanalyzer'
    manifest = subprocess.run([str(analyzer), 'manifest', 'print', str(apk)],
                              capture_output=True, text=True, check=True).stdout
    if ('package="' + variant['package'] + '"' not in manifest
            or 'android:debuggable="true"' not in manifest
            or 'org.hnuhole.hnuhole_mobile.MainActivity' not in manifest):
        raise RuntimeError('Actual product manifest/package/debug activity mismatch')
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        libraries = [name for name in names if name.startswith('lib/') and name.endswith('.so')]
        if not libraries or any(not name.startswith('lib/arm64-v8a/') for name in libraries):
            raise RuntimeError('Product APK must contain only actual arm64 native libraries')
        if not any(name.endswith('/libflutter.so') for name in libraries):
            raise RuntimeError('Flutter product runtime is absent')
        if any(name.endswith('/libVkLayer_khronos_validation.so') for name in libraries):
            raise RuntimeError('Developer GPU validation layer unexpectedly packaged')
        if not any(name.startswith('assets/flutter_assets/') for name in names):
            raise RuntimeError('Actual product Flutter assets are absent')
        dex = b''.join(archive.read(name) for name in names if re.fullmatch(r'classes[0-9]*\.dex', name))
        for product in (b'org/hnuhole/authpasskey', b'org/hnuhole/authvault', b'MainActivity'):
            if product not in dex:
                raise RuntimeError('Actual product native authentication plugins are absent')
        native_sizes = {name: archive.getinfo(name).file_size for name in libraries}
        native_symbols = verify_packaged_native_symbols(archive, libraries)
    return dict(apkSha256=sha(apk), apkBytes=apk.stat().st_size,
                signingCertificateSha256=variant['cert'], applicationId=variant['package'],
                actualProductFlutterRuntime=True, actualNativePasskeyAndVaultPlugins=True,
                arm64Only=True, gpuValidationLayerExcluded=True, nativeLibrariesBytes=native_sizes,
                nativeDebugSymbolsStripped=True, nativeSymbolValidation=native_symbols)


def certificate_matches(variant, jdk):
    keystore = SIGNING / variant['keystore']
    password = SIGNING / 'store.password'
    if keystore.is_symlink() or password.is_symlink() or not keystore.is_file() or not password.is_file():
        raise RuntimeError('Exact fresh private signing materials required')
    exported = subprocess.run([str(jdk / 'bin/keytool'), '-exportcert', '-keystore', str(keystore),
        '-alias', variant['alias'], '-storepass:file', str(password)], capture_output=True, check=True).stdout
    if hashlib.sha256(exported).hexdigest() != variant['cert']:
        raise RuntimeError('Fresh signing key does not match the explicit variant certificate')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variants', nargs='+', choices=tuple(VARIANTS), default=list(VARIANTS))
    parser.add_argument('--allow-network', action='store_true', help='Acquire missing locked Pub/Gradle dependencies')
    parser.add_argument('--pub-hosted-url-overlay', choices=('https://pub.dev',),
                        help='Record the reviewed 34 URL-only lock substitutions in the owned build mirror')
    parser.add_argument('--maximum-apk-bytes', type=int, default=150000000)
    args = parser.parse_args()
    if not __debug__ or os.name != 'posix':
        raise RuntimeError('Run without optimization in the dedicated Linux environment')
    if not 50000000 <= args.maximum_apk_bytes <= 150000000:
        raise RuntimeError('Review unexpected oversized APKs rather than lifting the size guard')
    if len(set(args.variants)) != len(args.variants):
        raise RuntimeError('Each build variant can occur only once')
    args.variants = [name for name in VARIANTS if name in args.variants]
    import fcntl
    FRESH.owned_directory(FRESH.LINUX, 'HNUHOLE_ANDROID_LIVE_DEV_V1')
    FRESH.owned_directory(FRESH.HOST, 'HNUHOLE_ANDROID_MATRIX_V1')
    mirror = FRESH.LINUX / 'repo'
    admission = json.loads((FRESH.LINUX / 'source-manifest.json').read_text())
    if admission['owner'] != FRESH.TOKEN or not admission.get('servicesReady'):
        raise RuntimeError('Actual fresh isolated service readiness required before compiling product fixture')
    # The receipt is prepared under the build lock, after checking all source bytes.
    config = json.loads((FRESH.LINUX / 'b3b4-device-config.json').read_text())
    if config['AUTH_DEVICE_RUN_ID'] != FRESH.RUN or config['AUTH_MATRIX_ACCOUNT_RUN_ID'] != FRESH.ACCOUNT_RUN:
        raise RuntimeError('Exact fresh account/runtime configuration required')
    for env in ('JAVA_HOME', 'ANDROID_HOME', 'FLUTTER_ROOT', 'GRADLE_USER_HOME'):
        if not Path(os.environ[env]).is_dir():
            raise RuntimeError('Missing installed tool directory: ' + env)
    sdk, jdk, flutter = [Path(os.environ[name]) for name in ('ANDROID_HOME', 'JAVA_HOME', 'FLUTTER_ROOT')]
    ndk = sdk / 'ndk/28.2.13676358'
    if not (ndk / 'toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip').is_file():
        raise RuntimeError('Installed NDK28.2.13676358 stripping tool required; do not keep debug symbols')
    for variant in args.variants:
        certificate_matches(VARIANTS[variant], jdk)
        for filename in VARIANTS[variant]['files']:
            if (FRESH.HOST / filename).exists():
                raise RuntimeError('Preserve an existing product artifact; never overwrite a prior attempt')
    evidence = FRESH.HOST / 'b3b4-evidence'
    ledger = evidence / 'builds.json'
    lock_path = FRESH.LINUX / 'product-build.lock'
    with lock_path.open('a+') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('A fresh product build is already active')
        pub_route = verify_prepared_sources(mirror, admission,
            allow_pub_route=bool(args.pub_hosted_url_overlay), record_pub_route=True)
        child_environment = os.environ.copy()
        if pub_route:
            child_environment['PUB_HOSTED_URL'] = pub_route['hostedUrl']
        for name in args.variants:
            for filename in VARIANTS[name]['files']:
                if (FRESH.HOST / filename).exists():
                    raise RuntimeError('Preserve an existing product artifact; never overwrite a prior attempt')
        if ledger.is_symlink():
            raise RuntimeError('Exact owned build ledger required')
        if ledger.exists():
            prior = json.loads(ledger.read_text())
            if prior['owner'] != FRESH.TOKEN:
                raise RuntimeError('Exact fresh build ledger owner required')
        else:
            prior = dict(owner=FRESH.TOKEN, apks=[], sourceFilesSha256={name: sha(mirror / name) for name in FRESH.SOURCE_SET},
                         sourceManifestSha256=sha(FRESH.LINUX / 'source-manifest.json'),
                         historicalPassRecordsPreserved=True, installationNotRun=True, actualDeviceAcceptancePassed=False)
        app = mirror / 'apps/mobile'
        android = app / 'android'
        log = FRESH.LINUX / 'product-build.private.log'
        needs_compile = any(name != 'bad-signature' for name in args.variants)
        strip_guard = native_strip_guard(FRESH.LINUX, child_environment) if needs_compile else None
        if needs_compile:
            wrapper = flutter / 'bin/cache/artifacts/gradle_wrapper'
            for name in ('gradlew', 'gradle/wrapper/gradle-wrapper.jar'):
                target = android / name
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists():
                    shutil.copyfile(wrapper / name, target)
            (android / 'gradlew').chmod(0o700)
            properties = android / 'local.properties'
            properties.write_text('sdk.dir=' + str(sdk) + '\nflutter.sdk=' + str(flutter)
                + '\nflutter.buildMode=debug\nflutter.versionCode=20261012\nflutter.versionName=0.1.0-fresh20261012\n')
            pub = [str(flutter / 'bin/flutter'), 'pub', 'get']
            if not args.allow_network:
                pub.append('--offline')
            execute(pub, app, log, timeout=900, env=child_environment)
            pub_route = verify_prepared_sources(mirror, admission)
        build_file = android / 'app/build.gradle.kts'
        main_manifest = android / 'app/src/main/AndroidManifest.xml'
        originals = {build_file: build_file.read_bytes(), main_manifest: main_manifest.read_bytes()} if needs_compile else {}
        try:
            if needs_compile:
                main_manifest.write_text(FRESH.replace_exact(main_manifest.read_text(),
                    'android:name=".MainActivity"', 'android:name="org.hnuhole.hnuhole_mobile.MainActivity"', 1))
            for name in args.variants:
                variant = VARIANTS[name]
                signed = FRESH.LINUX / ('product-' + name + '.apk')
                if signed.exists():
                    raise RuntimeError('Preserve an existing Linux signed candidate; inspect its prior attempt')
                if name == 'bad-signature':
                    candidate, approved_record = approved_signing_source(prior, mirror, config)
                    approved_hash = sha(candidate)
                    validate_apk(candidate, VARIANTS['approved'], sdk, args.maximum_apk_bytes)
                    snapshot = evidence / 'bad-signature-approved-builds.json'
                    if snapshot.exists():
                        raise RuntimeError('Preserve the original approved source ledger snapshot')
                    with snapshot.open('xb') as saved:
                        saved.write(ledger.read_bytes())
                    execute(signer_command(sdk, variant, candidate, signed), android, log, timeout=120)
                    facts = validate_apk(signed, variant, sdk, args.maximum_apk_bytes)
                    contrast = exact_payload_contrast(candidate, signed)
                    if sha(candidate) != approved_hash:
                        raise RuntimeError('Approved product APK changed during signature-only signing')
                    approved_signing_source(prior, mirror, config)
                    facts.update(contrast, variant=name, fixtureTarget=FRESH.FIXTURE,
                        nativeDebugSymbolsStripped=approved_record['nativeDebugSymbolsStripped'],
                        buildOverlaySha256=approved_record['buildOverlaySha256'],
                        mainManifestOverlaySha256=approved_record['mainManifestOverlaySha256'],
                        configSha256=approved_record['configSha256'], actualGradleBuildExecuted=False,
                        compiledVariant='approved', certificateContrastOnly=True,
                        signatureOnlySourceFileName=approved_record['fileName'],
                        signatureOnlySourceApkSha256=approved_hash,
                        signatureOnlySourceLedgerFileName=snapshot.name,
                        signatureOnlySourceLedgerSha256=sha(snapshot),
                        pubLockRouteOverlay=pub_route,
                        privateSigningMaterialExported=False, actualDeviceAcceptancePassed=False)
                    for filename in variant['files']:
                        shutil.copyfile(signed, FRESH.HOST / filename)
                        prior['apks'].append(dict(facts, fileName=filename))
                    FRESH.write_json(ledger, prior)
                    print('SIGNED: bad-signature from exact approved payload; compilation/installation NOT_RUN')
                    continue
                build_file.write_text(variant_gradle(originals[build_file].decode(), variant['package']))
                settings = dict(config, AUTH_B3B4_PACKAGE=variant['package'])
                defines = ','.join(base64.b64encode((key + '=' + str(value)).encode()).decode()
                                   for key, value in sorted(settings.items()))
                command = ['./gradlew', '--no-daemon', '--max-workers=2', '--init-script', str(strip_guard)]
                if not args.allow_network:
                    command.append('--offline')
                # ZipFlinger may retain obsolete native-library data from an
                # earlier unsigned output. Recreate the actual app outputs so
                # the size guard measures a fresh compact APK, without changing
                # product payload or compression policy.
                command += [':app:clean', ':app:assembleDebug', '-Ptarget-platform=android-arm64',
                    '-Ptarget=integration_test/auth_android_b3_b4_device_test.dart',
                    '-Pdart-defines=' + defines, '-Pdart-obfuscation=false', '-Ptrack-widget-creation=true',
                    '-Ptree-shake-icons=false']
                execute(command, android, log, env=child_environment)
                candidate = app / 'build/app/outputs/apk/debug/app-debug.apk'
                if not candidate.is_file():
                    raise RuntimeError('Actual product APK output is absent')
                execute(signer_command(sdk, variant, candidate, signed), android, log, timeout=120)
                facts = validate_apk(signed, variant, sdk, args.maximum_apk_bytes)
                facts.update(variant=name, fixtureTarget=FRESH.FIXTURE,
                    nativeStrippingInitSha256=sha(strip_guard), nativeStrippingTaskRerunRequired=True,
                    buildOverlaySha256=sha(build_file), mainManifestOverlaySha256=sha(main_manifest),
                    configSha256=FRESH.digest(json.dumps(settings, sort_keys=True).encode()),
                    actualGradleBuildExecuted=True, compiledVariant=name,
                    pubLockRouteOverlay=pub_route,
                    privateSigningMaterialExported=False, actualDeviceAcceptancePassed=False)
                for filename in variant['files']:
                    shutil.copyfile(signed, FRESH.HOST / filename)
                    prior['apks'].append(dict(facts, fileName=filename))
                FRESH.write_json(ledger, prior)
                print('BUILT: ' + name + ', ' + str(facts['apkBytes']) + ' bytes; installation NOT_RUN')
        finally:
            for path, original in originals.items():
                path.write_bytes(original)
        verify_prepared_sources(mirror, admission)
    # Windows attach-only flutter drive needs its own generated package config;
    # the owner marker is deliberately not created until a reviewed installation.
    print('READY: actual product variants and build ledger; phone installation/authentication NOT_RUN')


if __name__ == '__main__':
    main()
