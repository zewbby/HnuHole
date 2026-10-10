#!/usr/bin/env python3
"""Offline build of one owned debug APK, without installation or canonical APK changes.

Run in WSL Ubuntu-24.04 after sourcing the existing Hnuhole env-wsl.sh.
All temporary source/build overlays are restored. The dedicated output stays
available for the root task's reviewed same-certificate update.
"""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

if not __debug__:
    raise RuntimeError('Optimized execution is not permitted for owned build guards')

ROOT = Path('/var/tmp/hnuhole-android-live-faults-20261005')
SOURCE = Path('/mnt/c/Users/Administrator/Documents/ChatGPT/HnuHole')
HOST = Path('/mnt/d/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
OWNER = 'HNUHOLE_GOOGLE_FIDO_DIAGNOSTIC_V1'
PACKAGE = 'org.hnuhole.hnuhole_mobile.acceptance'
ACTIVITY = 'org.hnuhole.hnuhole_mobile.GoogleFidoDiagnosticActivity'
CERT = 'fd26b276cb170bf084a932d3b3919bd3aa44874395809968bdd74ddab87389dc'
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


def main():
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


if __name__ == '__main__':
    main()
