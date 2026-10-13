#!/usr/bin/env python3
"""Build-only Google FIDO diagnostic; never installs or opens authentication UI.

--fresh stages a small standalone debug project with an explicitly supplied
new package/certificate. Optional dependency warmup is followed by an offline
build. The original no-argument mode retains its exact archived-artifact guards.
"""
import base64
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import shutil
import xml.etree.ElementTree as ET
import zipfile

if not __debug__:
    raise RuntimeError('Optimized execution is not permitted for owned build guards')

ROOT = Path('/var/tmp/hnuhole-android-live-faults-20261005')
SOURCE = Path('/mnt/c/Users/Administrator/Documents/ChatGPT/HnuHole')
HOST = Path('/mnt/d/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
OWNER = 'HNUHOLE_GOOGLE_FIDO_DIAGNOSTIC_V1'
PACKAGE = 'org.hnuhole.hnuhole_mobile.acceptance'
ACTIVITY = 'org.hnuhole.hnuhole_mobile.GoogleFidoDiagnosticActivity'
ASSETLINKS = 'https://zewbby.github.io/.well-known/assetlinks.json'
CONFIG_CHANGES = {'orientation', 'keyboardHidden', 'screenSize', 'smallestScreenSize', 'uiMode'}
# Android API 36 attrs_manifest.xml: 0x20 | 0x80 | 0x200 | 0x400 | 0x800.
CONFIG_CHANGES_MASK = 0xEA0
CERT = 'fd26b276cb170bf084a932d3b3919bd3aa44874395809968bdd74ddab87389dc'
AAPT2 = 'com.android.tools.build:aapt2:9.1.0-14792394:linux'
DEBUG = 'apps/mobile/android/app/src/debug'
JAVA = DEBUG + '/java/org/hnuhole/hnuhole_mobile/'
NEW_FILES = [JAVA + 'GoogleFidoDiagnosticActivity.java', JAVA + 'GoogleFidoDiagnosticPolicy.java',
             DEBUG + '/AndroidManifest.xml', 'apps/mobile/android/app/build.gradle.kts']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def owned_directory(path):
    if path.exists():
        assert not path.is_symlink() and (path/'OWNER').read_text().strip() == OWNER
    else:
        path.mkdir(mode=0o700)
        (path/'OWNER').write_text(OWNER + '\n')


def legacy_main():
    assert (ROOT/'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    assert (HOST/'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_MATRIX_V1'
    assert os.environ['GRADLE_USER_HOME'] == str(ROOT/'gradle')
    local, output = ROOT/'matrix/google-direct-diagnostic', HOST/'google-direct-diagnostic'
    owned_directory(local)
    owned_directory(output)
    assert not (output/'manifest.json').exists(), 'Keep the original diagnostic build manifest'
    canonical = json.loads((HOST/'b3b4-evidence/builds.json').read_text())
    canonical_hashes = {p: sha(HOST/p) for p in ['b3b4-evidence/builds.json',
        'phone-b3b4.apk', 'b3b4-acceptance.apk', 'b3b4-bad-signature.apk', 'b3b4-unassociated.apk']}
    mirror = ROOT/'repo'
    product_hashes = {}
    for name, digest in canonical['sourceFilesSha256'].items():
        if name.startswith(('apps/', 'packages/')):
            assert sha(SOURCE/name) == digest and (mirror/name).read_text() == (SOURCE/name).read_text(), 'Product or fixture source changed'
            product_hashes[name] = digest
    changed = NEW_FILES + ['apps/mobile/android/build.gradle.kts',
                          'apps/mobile/android/app/src/main/AndroidManifest.xml',
                          'packages/auth_vault/android/src/main/kotlin/org/hnuhole/authvault/AuthVaultPlugin.kt']
    backups = {name: (mirror/name).read_bytes() if (mirror/name).exists() else None for name in changed}
    try:
        for name in NEW_FILES:
            (mirror/name).parent.mkdir(parents=True, exist_ok=True)
            (mirror/name).write_bytes((SOURCE/name).read_bytes())
        path = mirror/'apps/mobile/android/app/build.gradle.kts'
        original = path.read_text()
        assert original.count('applicationId = "org.hnuhole.hnuhole_mobile"') == 1
        path.write_text(original.replace('applicationId = "org.hnuhole.hnuhole_mobile"',
                                        'applicationId = "' + PACKAGE + '"'))
        path = mirror/'apps/mobile/android/app/src/main/AndroidManifest.xml'
        original = path.read_text()
        assert original.count('android:name=".MainActivity"') == 1
        path.write_text(original.replace('android:name=".MainActivity"',
                                        'android:name="org.hnuhole.hnuhole_mobile.MainActivity"'))
        path = mirror/'apps/mobile/android/build.gradle.kts'
        original = path.read_text()
        assert original.count('.dir("../../build")') == 1
        path.write_text(original.replace('.dir("../../build")', '.dir("' + str(local/'build') + '")'))
        # Retain the exact already reviewed isolated-package native IO overlay.
        spec = importlib.util.spec_from_file_location('owned_overlay', SOURCE/'tools/prepare-android-b3-b4-vault-overlay.py')
        overlay = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(overlay)
        path = mirror/overlay.PLUGIN
        original = path.read_text()
        revised = original.replace('private lateinit var vault: AndroidAuthVault',
            'private lateinit var vault: AndroidAuthVault\n    private lateinit var ownedIO: OwnedB3B4CommitIO')
        revised = revised.replace('vault = AndroidAuthVault(binding.applicationContext)',
            'ownedIO = OwnedB3B4CommitIO(binding.applicationContext)\n        vault = AndroidAuthVault(binding.applicationContext, ownedIO)')
        revised = revised.replace('vault.write(namespace, text)', 'ownedIO.arm(namespace)\n                    vault.write(namespace, text)')
        path.write_text(revised + overlay.SEAM)
        assert sha(path) == canonical['nativeIOOverlay']['isolatedOverlaySha256']
        config = json.loads((ROOT/'matrix/b3b4-acceptance-config.json').read_text())
        assert config['AUTH_B3B4_PACKAGE'] == PACKAGE
        dart_defines = ','.join(base64.b64encode((key+'='+str(value)).encode()).decode() for key,value in config.items())
        android = mirror/'apps/mobile/android'
        prebuilt_init = local/'prebuilt-debug-only.gradle'
        prebuilt_init.write_text('''import groovy.json.JsonSlurper
if (gradle.parent != null) return
if (gradle.startParameter.taskNames != [':app:assembleDebug'])
  throw new GradleException('Owned prebuilt verification accepts only assembleDebug')
gradle.beforeProject { project ->
  project.pluginManager.withPlugin('dev.flutter.flutter-gradle-plugin') {
    if (project.name != 'app') throw new GradleException('Unexpected Flutter app')
    def json = new JsonSlurper()
    def appRoot = project.rootDir.parentFile
    def plugins = json.parse(new File(appRoot, '.flutter-plugins-dependencies')).plugins.android
    if (plugins.collect { it.name } != ['hnuhole_auth_passkey', 'hnuhole_auth_vault', 'integration_test'])
      throw new GradleException('Unexpected plugins require review')
    def configuration = new File(appRoot, '.dart_tool/package_config.json')
    json.parse(configuration).packages.each { dep ->
      def root = new File(configuration.toURI().resolve(dep.rootUri))
      if (new File(root, 'hook/build.dart').exists() || new File(root, 'hook/link.dart').exists())
        throw new GradleException('Native hooks require standard native build')
    }
    def properties = new Properties()
    new File(project.rootDir, 'local.properties').withInputStream { properties.load(it) }
    def expected = new File(properties.getProperty('flutter.sdk'),
      'packages/flutter_tools/gradle/src/main/scripts/CMakeLists.txt').canonicalFile
    def android = project.extensions.getByName('android')
    def synthetic = android.externalNativeBuild.cmake.path
    if (synthetic == null || synthetic.canonicalFile != expected ||
        !synthetic.readLines().every { it.trim().isEmpty() || it.trim().startsWith('#') })
      throw new GradleException('Refuse to skip real native compilation')
    android.externalNativeBuild.cmake.path = null
    android.packagingOptions.jniLibs.keepDebugSymbols.add('**/*.so')
  }
}
gradle.taskGraph.whenReady { graph ->
  if (graph.allTasks.any { it.name.contains('Release') || it.name.contains('Profile') })
    throw new GradleException('Owned prebuilt build cannot package release/profile')
}
''')
        command = ['./gradlew', '--offline', '--no-daemon', '--max-workers=2', '-I', str(prebuilt_init), ':app:assembleDebug',
            '-Ptarget-platform=android-arm64', '-Ptarget=integration_test/auth_android_b3_b4_device_test.dart',
            '-Pdart-defines='+dart_defines, '-Pdart-obfuscation=false', '-Ptrack-widget-creation=true',
            '-Ptree-shake-icons=false']
        with (local/'build.private.log').open('w') as log:
            result = subprocess.run(command, cwd=android, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
        assert result.returncode == 0, 'Offline diagnostic build failed; see owned local log'
        candidates = list((local/'build/app/outputs').rglob('app-debug.apk'))
        assert candidates
        apk = output/'google-fido-diagnostic.apk'
        apk.write_bytes(candidates[0].read_bytes())
        signer = Path(os.environ['ANDROID_HOME'])/'build-tools/36.0.0/apksigner'
        signed = subprocess.run([str(signer), 'verify', '--print-certs', str(apk)], capture_output=True, text=True, check=True)
        cert = re.search(r'Signer #1 certificate SHA-256 digest: ([a-f0-9]+)', signed.stdout)[1]
        assert cert == CERT
        analyzer = Path(os.environ['ANDROID_HOME'])/'cmdline-tools/latest/bin/apkanalyzer'
        manifest = subprocess.run([str(analyzer), 'manifest', 'print', str(apk)], capture_output=True, text=True, check=True).stdout
        assert 'package="'+PACKAGE+'"' in manifest and ACTIVITY in manifest and 'android:debuggable="true"' in manifest
        with zipfile.ZipFile(apk) as archive:
            dex = b''.join(archive.read(name) for name in archive.namelist() if re.fullmatch(r'classes[0-9]*\.dex', name))
            assert b'GoogleFidoDiagnosticActivity' in dex and b'GoogleFidoDiagnosticPolicy' in dex
        # Run real Gradle source-set inspection and release manifest processing.
        init = local/'release-source-check.gradle'
        init.write_text('''if (gradle.parent != null) return
gradle.projectsEvaluated {
  def app = gradle.rootProject.project(':app')
  app.tasks.register('verifyGoogleFidoDiagnosticReleaseExcluded') {
    doLast {
      def android = app.extensions.getByName('android')
      def excluded = ['main', 'release'].every { kind ->
        android.sourceSets.getByName(kind).java.srcDirs.every { dir ->
          app.fileTree(dir).matching { include '**/GoogleFidoDiagnostic*.java' }.files.isEmpty()
        }
      }
      if (!excluded) throw new GradleException('Diagnostic source entered release')
      if (['releaseImplementation', 'releaseCompileOnly'].any { kind ->
          app.configurations.getByName(kind).dependencies.any { it.name == 'play-services-fido' }
      })
        throw new GradleException('Diagnostic dependency entered release')
      println('PASS: Gradle main/release source sets and direct dependency exclude Google diagnostic')
    }
  }
}
''')
        with (local/'release-exclusion.private.log').open('w') as log:
            result = subprocess.run(['./gradlew', '--offline', '--no-daemon', '--max-workers=2', '-I', str(init),
                ':app:verifyGoogleFidoDiagnosticReleaseExcluded', ':app:processReleaseManifest'],
                cwd=android, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        assert result.returncode == 0, 'Release exclusion check failed'
        release_manifests = list((local/'build/app/intermediates').glob('merged_manifests/release/**/AndroidManifest.xml'))
        assert release_manifests and all(ACTIVITY not in p.read_text() for p in release_manifests)
        policy = SOURCE/(JAVA+'GoogleFidoDiagnosticPolicy.java')
        test = SOURCE/'tools/android-passkey-diagnostic/GoogleFidoDiagnosticPolicyTest.java'
        test_classes = local/'policy-test-classes'
        test_classes.mkdir(exist_ok=True)
        javac = Path(os.environ['JAVA_HOME'])/'bin/javac'
        java = Path(os.environ['JAVA_HOME'])/'bin/java'
        subprocess.run([str(javac), '-d', str(test_classes), str(policy), str(test)], check=True)
        checks = subprocess.run([str(java), '-cp', str(test_classes), 'org.hnuhole.hnuhole_mobile.GoogleFidoDiagnosticPolicyTest'],
                                capture_output=True, text=True, check=True).stdout.strip()
        source_hashes = product_hashes | {name: sha(SOURCE/name) for name in NEW_FILES}
        source_hashes['tools/android-passkey-diagnostic/GoogleFidoDiagnosticPolicyTest.java'] = sha(test)
        source_hashes['tools/android-passkey-diagnostic/build-google-fido-diagnostic.py'] = sha(Path(__file__))
        record = dict(schemaVersion=1, owner=OWNER, result='PASS', scope='OFFLINE_BUILD_AND_DEBUG_BOUNDARIES_ONLY',
            applicationId=PACKAGE, activity=ACTIVITY, apkPath='D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix/google-direct-diagnostic/google-fido-diagnostic.apk',
            apkSha256=sha(apk), signingCertificateSha256=cert, sourceFilesSha256=source_hashes,
            releaseExcluded=True, releaseExclusionEvidence='Gradle main/release source-set/direct dependency inspection and freshly processed release manifest',
            releaseApkRebuilt=False, compilePass=True, cachedFidoVersion='21.0.0', offline=True,
            prebuiltEngineSymbolsKept=True, syntheticEmptyCmakeOnlySkipped=True, realNativeHooksAbsent=True,
            policyTestResult=checks, defaultPrepareOnly=True, deviceInstalled=False, deviceApiExecuted=False,
            systemUiLaunched=False, actualCSubmission=False, fixedCaseAcceptancePassed=False,
            previousAcceptanceApkSha256=canonical_hashes['b3b4-acceptance.apk'], canonicalBuildsPreserved=True)
        (output/'manifest.json').write_text(json.dumps(record, indent=2)+'\n')
        print(checks)
        print('PASS: one approved debug APK, fresh release exclusion check; no device operation')
        print('APK_SHA256 '+record['apkSha256'])
    finally:
        for name, original in backups.items():
            if original is None: (mirror/name).unlink(missing_ok=True)
            else: (mirror/name).write_bytes(original)
        assert all(sha(HOST/name) == digest for name,digest in canonical_hashes.items()), 'Canonical artifact changed'


def groovy_string(value):
    """Quote data for generated Groovy, including paths containing apostrophes."""
    return "'" + str(value).replace('\\', '\\\\').replace("'", "\\'") + "'"


def fresh_identity(policy, package, certificate):
    assert re.fullmatch(r'org\.hnuhole\.hnuhole_mobile\.acceptance[0-9]{8}', package), 'Use a new dated isolation package'
    assert re.fullmatch(r'[a-f0-9]{64}', certificate), 'Exact SHA-256 certificate required'
    for name, old, new in [('PACKAGE', PACKAGE, package), ('CERT', CERT, certificate)]:
        original = 'static final String ' + name + ' = "' + old + '";'
        assert policy.count(original) == 1, 'Review changed diagnostic policy before staging'
        policy = policy.replace(original, 'static final String ' + name + ' = "' + new + '";')
    return policy


def validate_fresh_apk(path, manifest, package):
    """A diagnostic must stay small and contain no product/Flutter/native payload."""
    assert 0 < path.stat().st_size <= 32 * 1024 * 1024, 'Oversized standalone diagnostic APK'
    android_ns = '{http://schemas.android.com/apk/res/android}'
    parsed = ET.fromstring(manifest)
    assert parsed.attrib['package'] == package
    app = parsed.find('application')
    assert app is not None and app.attrib.get(android_ns + 'debuggable') == 'true'
    activities = app.findall('activity')
    owned = [node for node in activities if node.attrib.get(android_ns + 'name') == ACTIVITY]
    assert len(owned) == 1, 'Exact single owned diagnostic Activity required'
    runtime = [node for node in activities if node not in owned]
    # The pinned play-services-base 18.5.0 manifest contributes this resolver.
    # Do not accept arbitrary SDK/product components or an exported resolver.
    assert len(runtime) <= 1
    for node in runtime:
        assert node.attrib.get(android_ns + 'name') == 'com.google.android.gms.common.api.GoogleApiActivity'
        assert node.attrib.get(android_ns + 'exported') == 'false' and len(node) == 0
        assert set(node.attrib) == {android_ns + 'name', android_ns + 'theme', android_ns + 'exported'}
    activity = owned[0]
    assert activity.attrib.get(android_ns + 'exported') == 'true'
    assert activity.attrib.get(android_ns + 'excludeFromRecents') == 'true'
    assert activity.attrib.get(android_ns + 'taskAffinity') == ''
    changes = activity.attrib.get(android_ns + 'configChanges', '')
    assert set(changes.split('|')) == CONFIG_CHANGES or (re.fullmatch(r'0x[0-9a-fA-F]+|[0-9]+', changes)
        and int(changes, 16 if changes.startswith('0x') else 10) == CONFIG_CHANGES_MASK)
    assert activity.attrib.get(android_ns + 'theme'), 'Keep the canonical standalone Activity theme'
    all_metadata = app.findall('meta-data')
    metadata = [node for node in all_metadata if node.attrib.get(android_ns + 'name') == 'asset_statements']
    assert len(metadata) == 1
    assert metadata[0].attrib.get(android_ns + 'resource', '').startswith('@'), 'Android-side DAL resource missing'
    assert set(metadata[0].attrib) == {android_ns + 'name', android_ns + 'resource'} and len(metadata[0]) == 0
    runtime_metadata = [node for node in all_metadata if node not in metadata]
    assert len(runtime_metadata) <= 1
    for node in runtime_metadata:
        assert node.attrib.get(android_ns + 'name') == 'com.google.android.gms.version' and len(node) == 0
        assert set(node.attrib) == {android_ns + 'name', android_ns + 'value'}
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        assert not any(name.startswith(('lib/', 'assets/flutter_assets/')) for name in names), 'Standalone diagnostic unexpectedly includes native/Flutter libraries'
        dex = b''.join(archive.read(name) for name in names if re.fullmatch(r'classes[0-9]*\.dex', name))
        assert b'GoogleFidoDiagnosticActivity' in dex and b'GoogleFidoDiagnosticPolicy' in dex
        assert b'com/google/android/gms/fido/fido2/Fido2ApiClient' in dex, 'FIDO runtime missing'
        assert b'org/hnuhole/authvault' not in dex and b'org/hnuhole/authpasskey' not in dex, 'Product authentication plugin entered diagnostic'


def validate_asset_statements(value):
    """Both the copied XML resource and compiled resource must point to fixed RP."""
    value = value.strip()
    if value.startswith('"'):
        value = json.loads(value)
    statements = json.loads(value.replace(r'\"', '"'))
    assert statements == [{'include': ASSETLINKS}], 'Unexpected Android-side DAL statement'


def standalone_debug_inputs(source):
    manifest = source / (DEBUG + '/AndroidManifest.xml')
    resources = source / (DEBUG + '/res/values/passkey_associations.xml')
    android_ns = '{http://schemas.android.com/apk/res/android}'
    parsed = ET.fromstring(manifest.read_text())
    assert [node.attrib.get(android_ns + 'name') for node in parsed.findall('uses-permission')] == ['android.permission.INTERNET']
    application = parsed.find('application')
    assert application is not None and len(application.findall('activity')) == 1
    assert {node.tag for node in application} == {'activity', 'meta-data'}, 'Review changed debug manifest before staging'
    activity = application.find('activity')
    assert activity.attrib.get(android_ns + 'name') == ACTIVITY
    assert activity.attrib.get(android_ns + 'theme') == '@android:style/Theme.Material.Light.NoActionBar'
    assert activity.attrib.get(android_ns + 'excludeFromRecents') == 'true' and activity.attrib.get(android_ns + 'taskAffinity') == ''
    assert set(activity.attrib.get(android_ns + 'configChanges', '').split('|')) == CONFIG_CHANGES
    assert activity.attrib.get(android_ns + 'exported') == 'true'
    metadata = application.findall('meta-data')
    assert len(metadata) == 1 and metadata[0].attrib == {android_ns + 'name': 'asset_statements', android_ns + 'resource': '@string/asset_statements'}
    resource_xml = ET.fromstring(resources.read_text())
    assert len(resource_xml) == 1 and resource_xml[0].tag == 'string'
    assert resource_xml[0].attrib.get('name') == 'asset_statements'
    validate_asset_statements(resource_xml[0].text)
    return manifest, resources


def standalone_build_gradle(keystore, alias):
    return '''plugins { id 'com.android.application' version '9.1.0' }
android {
  namespace 'org.hnuhole.hnuhole_mobile'
  compileSdk 36
  defaultConfig {
    applicationId @PACKAGE@
    minSdk 28
    targetSdk 36
    versionCode 1
    versionName 'diagnostic-only-1'
  }
  compileOptions {
    sourceCompatibility JavaVersion.VERSION_17
    targetCompatibility JavaVersion.VERSION_17
  }
  signingConfigs {
    ownedDiagnostic {
      storeFile file(@KEYSTORE@)
      storePassword System.getenv('HNUHOLE_DIAGNOSTIC_STORE_PASSWORD')
      keyAlias @ALIAS@
      keyPassword System.getenv('HNUHOLE_DIAGNOSTIC_KEY_PASSWORD') ?: System.getenv('HNUHOLE_DIAGNOSTIC_STORE_PASSWORD')
    }
  }
  buildTypes {
    debug { signingConfig signingConfigs.ownedDiagnostic }
  }
}
dependencies {
  debugImplementation('com.google.android.gms:play-services-fido:21.0.0') {
    version { strictly '21.0.0' }
  }
  debugImplementation('com.google.android.gms:play-services-base:18.5.0') {
    version { strictly '18.5.0' }
  }
  debugImplementation('com.google.android.gms:play-services-basement:18.5.0') {
    version { strictly '18.5.0' }
  }
  debugImplementation('com.google.android.gms:play-services-tasks:18.2.0') {
    version { strictly '18.2.0' }
  }
}
tasks.register('resolveDiagnosticDependencies') {
  doLast {
    ['debugCompileClasspath', 'debugRuntimeClasspath'].each { name ->
      configurations.getByName(name).resolve()
    }
    // AGP resolves its native packaging tool lazily in a detached configuration.
    // Warm the exact Linux artifact explicitly before the offline build.
    def aapt2 = configurations.detachedConfiguration(dependencies.create(@AAPT2@))
    aapt2.transitive = false
    aapt2.resolve()
  }
}
tasks.register('verifyGoogleFidoDiagnosticReleaseExcluded') {
  doLast {
    ['main', 'release'].each { name ->
      android.sourceSets.getByName(name).java.srcDirs.each { directory ->
        if (!fileTree(directory).matching { include '**/GoogleFidoDiagnostic*.java' }.isEmpty())
          throw new GradleException('Diagnostic source entered standalone release')
      }
    }
    if (configurations.releaseCompileClasspath.allDependencies.any {
      it.group == 'com.google.android.gms'
    }) throw new GradleException('Diagnostic dependency entered standalone release')
    println('PASS: standalone main/release exclude diagnostic sources and dependencies')
  }
}
tasks.matching { it.name in ['assembleRelease', 'bundleRelease', 'packageRelease'] }.configureEach {
  doFirst { throw new GradleException('Standalone diagnostic must never package release') }
}
'''.replace('@KEYSTORE@', groovy_string(keystore)).replace('@ALIAS@', groovy_string(alias)).replace('@AAPT2@', groovy_string(AAPT2))


def fresh_main(args):
    """Build only debug Java diagnostic sources in a new owned project.

    No archived APK, old private key, Flutter build mirror, acceptance config or
    native IO overlay is used. This output cannot replace product acceptance.
    """
    assert os.name == 'posix', 'Run fresh Gradle preparation in Linux/WSL'
    source = args.source.resolve()
    root = args.root.absolute()
    output = args.output.absolute() if args.output else root / 'output'
    assert root == root.resolve() and output == output.resolve(), 'Symlinked owned paths are forbidden'
    assert not root.is_relative_to(source) and not source.is_relative_to(root), 'Owned build root must be separate from source'
    assert output.is_relative_to(root), 'Keep fresh outputs in the exact owned build root'
    assert root.name and root.parent.is_dir()
    owned_directory(root)
    owned_directory(output)
    assert not (output / 'manifest.json').exists(), 'Preserve original successful preparation'
    project = root / 'standalone'
    assert not project.exists(), 'Use a new owned root for each build attempt'
    project.mkdir(mode=0o700)
    android = project / 'app'
    android.mkdir()
    sdk = Path(os.environ['ANDROID_HOME']).resolve()
    jdk = Path(os.environ['JAVA_HOME']).resolve()
    gradle_home = Path(os.environ['GRADLE_USER_HOME']).resolve()
    assert sdk.is_dir() and jdk.is_dir() and gradle_home.is_dir()
    keystore = args.keystore.resolve()
    assert keystore.is_file() and not args.keystore.is_symlink()
    assert re.fullmatch(r'[A-Za-z0-9_-]{1,80}', args.key_alias)
    assert os.environ.get('HNUHOLE_DIAGNOSTIC_STORE_PASSWORD'), 'Private signing password environment variable required'
    identity_policy = fresh_identity((source / (JAVA + 'GoogleFidoDiagnosticPolicy.java')).read_text(),
                                     args.package, args.certificate_sha256)
    exported_cert = subprocess.run([str(jdk / 'bin/keytool'), '-exportcert', '-keystore', str(keystore),
        '-alias', args.key_alias, '-storepass:env', 'HNUHOLE_DIAGNOSTIC_STORE_PASSWORD'],
        capture_output=True, check=True).stdout
    assert hashlib.sha256(exported_cert).hexdigest() == args.certificate_sha256, 'Signing key does not match admitted fresh certificate'
    inputs = ['apps/mobile/android/gradle/wrapper/gradle-wrapper.properties',
              JAVA + 'GoogleFidoDiagnosticActivity.java', JAVA + 'GoogleFidoDiagnosticPolicy.java',
              DEBUG + '/AndroidManifest.xml', DEBUG + '/res/values/passkey_associations.xml',
              'tools/android-passkey-diagnostic/GoogleFidoDiagnosticPolicyTest.java',
              'tools/android-passkey-diagnostic/build-google-fido-diagnostic.py',
              'tools/android-passkey-diagnostic/test_build_google_fido_diagnostic.py',
              'tools/run-google-passkey-diagnostic.py',
              'tools/tests/test_google_fido_diagnostic_runner.py']
    source_hashes = {name: sha(source / name) for name in inputs}
    wrapper_properties = (source / inputs[0]).read_text()
    assert 'gradle-9.3.1-bin.zip' in wrapper_properties, 'Review changed Gradle version'
    # Flutter intentionally ignores generated wrapper script/jar in Git. Copy the
    # installed tool artifact, never synthesize or download an unverified jar.
    wrapper = (args.gradle_wrapper_directory or
        Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/artifacts/gradle_wrapper').resolve()
    tool_hashes = {str(wrapper / name): sha(wrapper / name)
        for name in ('gradlew', 'gradle/wrapper/gradle-wrapper.jar')}
    for name in ('gradlew', 'gradle/wrapper/gradle-wrapper.jar'):
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(wrapper / name, target)
    shutil.copyfile(source / inputs[0], project / 'gradle/wrapper/gradle-wrapper.properties')
    (project / 'gradlew').chmod(0o700)
    (project / 'settings.gradle').write_text('''pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = 'HnuHoleOwnedGoogleDiagnostic'
include ':app'
''')
    (project / 'gradle.properties').write_text('org.gradle.jvmargs=-Xmx2048m\nandroid.useAndroidX=true\norg.gradle.caching=true\n')
    # A single explicit SDK path; no old local.properties or deployment overlay.
    (project / 'local.properties').write_text('sdk.dir=' + str(sdk).replace('\\', '\\\\').replace(':', '\\:') + '\n')
    (android / 'build.gradle').write_text(standalone_build_gradle(keystore, args.key_alias)
        .replace('@PACKAGE@', groovy_string(args.package)))
    main_manifest = android / 'src/main/AndroidManifest.xml'
    main_manifest.parent.mkdir(parents=True)
    main_manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="HnuHole Google diagnostic" /></manifest>\n')
    debug_manifest = android / 'src/debug/AndroidManifest.xml'
    debug_manifest.parent.mkdir(parents=True)
    canonical_manifest, canonical_resources = standalone_debug_inputs(source)
    shutil.copyfile(canonical_manifest, debug_manifest)
    resource_target = android / 'src/debug/res/values/passkey_associations.xml'
    resource_target.parent.mkdir(parents=True)
    shutil.copyfile(canonical_resources, resource_target)
    java_dir = android / 'src/debug/java/org/hnuhole/hnuhole_mobile'
    java_dir.mkdir(parents=True)
    shutil.copyfile(source / (JAVA + 'GoogleFidoDiagnosticActivity.java'), java_dir / 'GoogleFidoDiagnosticActivity.java')
    policy = java_dir / 'GoogleFidoDiagnosticPolicy.java'
    policy.write_text(identity_policy)
    test_classes = root / 'policy-test-classes'
    test_classes.mkdir()
    subprocess.run([str(jdk / 'bin/javac'), '-d', str(test_classes), str(policy),
        str(source / 'tools/android-passkey-diagnostic/GoogleFidoDiagnosticPolicyTest.java')], check=True)
    checks = subprocess.run([str(jdk / 'bin/java'), '-cp', str(test_classes),
        'org.hnuhole.hnuhole_mobile.GoogleFidoDiagnosticPolicyTest'], capture_output=True, text=True, check=True).stdout.strip()
    base = ['./gradlew', '--no-daemon', '--max-workers=2', '--console=plain']
    if args.resolve_dependencies:
        with (root / 'dependency-resolution.private.log').open('w') as log:
            resolved = subprocess.run(base + [':app:resolveDiagnosticDependencies'], cwd=project,
                stdout=log, stderr=subprocess.STDOUT, timeout=1200)
        assert resolved.returncode == 0, 'Dependency warmup failed; see owned private log'
    with (root / 'build.private.log').open('w') as log:
        built = subprocess.run(base + ['--offline', ':app:assembleDebug',
            ':app:verifyGoogleFidoDiagnosticReleaseExcluded', ':app:processReleaseManifest'],
            cwd=project, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
    assert built.returncode == 0, 'Offline standalone build failed; see owned private log'
    candidates = list((android / 'build/outputs/apk/debug').glob('*.apk'))
    assert len(candidates) == 1
    apk = output / 'google-fido-diagnostic.apk'
    assert not apk.exists(), 'Preserve prior candidate APK'
    shutil.copyfile(candidates[0], apk)
    signer = sdk / 'build-tools/36.0.0/apksigner'
    analyzer = sdk / 'cmdline-tools/latest/bin/apkanalyzer'
    signed = subprocess.run([str(signer), 'verify', '--print-certs', str(apk)], capture_output=True, text=True, check=True).stdout
    certificates = re.findall(r'Signer #[0-9]+ certificate SHA-256 digest: ([a-f0-9]+)', signed)
    assert certificates == [args.certificate_sha256], 'Exact single fresh certificate required'
    manifest = subprocess.run([str(analyzer), 'manifest', 'print', str(apk)], capture_output=True, text=True, check=True).stdout
    validate_fresh_apk(apk, manifest, args.package)
    asset_statements = subprocess.run([str(analyzer), 'resources', 'value', '--config', 'default',
        '--name', 'asset_statements', '--type', 'string', '--package', args.package, str(apk)],
        capture_output=True, text=True, check=True).stdout
    validate_asset_statements(asset_statements)
    release_manifests = list((android / 'build/intermediates').glob('merged_manifests/release/**/AndroidManifest.xml'))
    assert release_manifests and all(ACTIVITY not in item.read_text() for item in release_manifests), 'Standalone release manifest includes diagnostic'
    assert all(sha(source / name) == digest for name, digest in source_hashes.items()), 'Source changed during preparation'
    staged_sources = {str(path.relative_to(project)): sha(path) for path in project.rglob('*')
        if path.is_file() and ('/src/' in str(path) or path.name in ('build.gradle', 'settings.gradle', 'gradle.properties'))}
    record = dict(schemaVersion=2, owner=OWNER, result='PASS', scope='FRESH_STANDALONE_DIAGNOSTIC_ONLY',
        identityMode='fresh', applicationId=args.package, activity=ACTIVITY,
        apkPath=str(apk), apkSha256=sha(apk), apkSizeBytes=apk.stat().st_size,
        signingCertificateSha256=args.certificate_sha256, sourceFilesSha256=source_hashes,
        toolFilesSha256=tool_hashes,
        stagedSourceFilesSha256=staged_sources, embeddedPolicySha256=sha(policy),
        releaseExcluded=True, releaseExclusionScope='STANDALONE_DEBUG_SOURCE_SET_AND_DEPENDENCIES_ONLY',
        productReleaseExcluded=False, releaseApkRebuilt=False,
        compilePass=True, cachedFidoVersion='21.0.0', offline=True,
        dependencyWarmupExecuted=args.resolve_dependencies, flutterPayloadAbsent=True,
        offlinePackagingToolDependency=AAPT2,
        androidAssetStatementsVerified=True, fixedAssetlinksInclude=ASSETLINKS,
        allowedSdkManifestActivity='com.google.android.gms.common.api.GoogleApiActivity',
        nativePayloadAbsent=True, sourceModified=False, archivedArtifactsRequired=False,
        policyTestResult=checks, defaultPrepareOnly=True, deviceInstalled=False,
        deviceApiExecuted=False, systemUiLaunched=False, actualCSubmission=False,
        fixedCaseAcceptancePassed=False, acceptanceEnvironmentReady=False)
    with (output / 'manifest.json').open('x') as result:
        result.write(json.dumps(record, indent=2) + '\n')
    print(checks)
    print('PASS: fresh small standalone debug diagnostic; product/device acceptance NOT_RUN')
    print('APK_SHA256 ' + record['apkSha256'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fresh', action='store_true', help='New owned standalone Java diagnostic, independent of archived acceptance artifacts')
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--root', type=Path, help='New empty owned Linux build directory outside the source checkout')
    parser.add_argument('--output', type=Path, help='Output directory inside --root; defaults to root/output')
    parser.add_argument('--package', help='New dated org.hnuhole.hnuhole_mobile.acceptanceYYYYMMDD package')
    parser.add_argument('--certificate-sha256', help='Exact explicitly admitted fresh signing certificate SHA-256')
    parser.add_argument('--keystore', type=Path)
    parser.add_argument('--key-alias')
    parser.add_argument('--gradle-wrapper-directory', type=Path, help='Installed wrapper artifact directory; defaults to FLUTTER_ROOT/bin/cache/artifacts/gradle_wrapper')
    parser.add_argument('--resolve-dependencies', action='store_true', help='Explicit online dependency warmup, followed by a fully offline build')
    args = parser.parse_args()
    if args.fresh:
        for name in ('root', 'package', 'certificate_sha256', 'keystore', 'key_alias'):
            if getattr(args, name) is None:
                parser.error('--fresh requires --' + name.replace('_', '-'))
        fresh_main(args)
    else:
        if any((args.root, args.output, args.package, args.certificate_sha256, args.keystore,
                args.key_alias, args.gradle_wrapper_directory, args.resolve_dependencies)):
            parser.error('Portable options require --fresh; legacy build retains exact archived guards')
        legacy_main()


if __name__ == '__main__':
    main()
