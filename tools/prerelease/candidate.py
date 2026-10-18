#!/usr/bin/env python3
"""Actual main.dart release APK, exact Git commit, ephemeral TEST signing only."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

PACKAGE = 'org.hnuhole.hnuhole_mobile'
NS = '{http://schemas.android.com/apk/res/android}'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(args, cwd, env=None, binary=False, visible=False):
    r = subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True,
                       stdout=None if visible else subprocess.PIPE,
                       stderr=None if visible else subprocess.PIPE, text=not binary)
    return r.stdout


def git(source, *args):
    return run(['git', *args], source).strip()


def verify_manifest(xml, version, number):
    root = ET.fromstring(xml)
    app, sdk = root.find('application'), root.find('uses-sdk')
    require(root.get('package') == PACKAGE, 'unexpected packaged ID')
    require(root.get(NS + 'versionName') == version and root.get(NS + 'versionCode') == str(number), 'packaged version mismatch')
    require(app is not None and sdk is not None, 'APK application or SDK declaration missing')
    for name in ('debuggable', 'testOnly', 'allowBackup'):
        require(app.get(NS + name, 'false') in ('false', '0'), 'unsafe release manifest: ' + name)
    require(app.get(NS + 'allowBackup') in ('false', '0'), 'backup exclusion missing')
    require(sdk.get(NS + 'minSdkVersion') == '29', 'minSdk changed')
    for node in app.iter():
        name = node.get(NS + 'name', '')
        require('GoogleFidoDiagnosticActivity' not in name and name != 'asset_statements', 'debug diagnostic/DAL in release')
    return dict(applicationId=PACKAGE, versionName=version, versionCode=number,
                minSdk=29, targetSdk=int(sdk.get(NS + 'targetSdkVersion')), debuggable=False, allowBackup=False)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--source-sha', required=True)
    p.add_argument('--workflow-sha', required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--build-number', type=int, required=True)
    a = p.parse_args()
    require(all(re.fullmatch('[0-9a-f]{40}', value) for value in (a.source_sha, a.workflow_sha)), 'full lowercase SHA required')
    require(1 <= a.build_number <= 2100000000, 'invalid Android versionCode')
    source, out = a.source.resolve(), a.out.resolve()
    require(not out.is_relative_to(source) and not source.is_relative_to(out), 'artifact directory must be outside source')
    require(not out.exists(), 'use a new artifact directory')

    def clean():
        require(git(source, 'rev-parse', 'HEAD') == a.source_sha, 'source SHA mismatch')
        require(not git(source, 'status', '--porcelain', '--untracked-files=all'), 'source is dirty')

    clean()
    locks = {name: sha(source / name) for name in git(source, 'ls-files', '*pubspec.lock').splitlines()}
    app = source / 'apps/mobile'
    version = re.search(r'^version:\s*([^+\s]+)', (app / 'pubspec.yaml').read_text(), re.M).group(1)
    sdk = Path(os.environ['ANDROID_HOME'])
    signer = sdk / 'build-tools/36.0.0/apksigner'
    analyzer = sdk / 'cmdline-tools/latest/bin/apkanalyzer'
    keytool = Path(os.environ['JAVA_HOME']) / 'bin/keytool'
    flutter = Path(os.environ['FLUTTER_ROOT']) / 'bin/flutter'
    tools = json.loads(run([flutter, '--version', '--machine'], app))
    require(tools['frameworkVersion'] == '3.47.5', 'Flutter version mismatch')
    # The only exported identity is its public certificate digest. No CI secret
    # or production signing input is needed for an ephemeral candidate build.
    with tempfile.TemporaryDirectory(prefix='hnuhole-test-sign-', dir=out.parent) as private:
        os.chmod(private, 0o700)
        password = secrets.token_urlsafe(40)
        env = dict(os.environ, HNUHOLE_TEST_KEYSTORE=str(Path(private) / 'test.jks'),
                   HNUHOLE_TEST_KEY_ALIAS='prerelease-test', HNUHOLE_TEST_STORE_PASSWORD=password,
                   HNUHOLE_TEST_KEY_PASSWORD=password)
        run([keytool, '-genkeypair', '-noprompt', '-keystore', env['HNUHOLE_TEST_KEYSTORE'],
             '-storetype', 'JKS', '-storepass:env', 'HNUHOLE_TEST_STORE_PASSWORD',
             '-keypass:env', 'HNUHOLE_TEST_KEY_PASSWORD', '-alias', 'prerelease-test',
             '-keyalg', 'RSA', '-keysize', '3072', '-validity', '30',
             '-dname', 'CN=HnuHole Isolated Test,OU=Prerelease,O=HnuHole'], app, env)
        cert = run([keytool, '-exportcert', '-keystore', env['HNUHOLE_TEST_KEYSTORE'],
                    '-storepass:env', 'HNUHOLE_TEST_STORE_PASSWORD', '-alias', 'prerelease-test'], app, env, binary=True)
        digest = hashlib.sha256(cert).hexdigest()
        # Flutter #169336: --no-pub alone retains dev plugin registration.
        # Generate RELEASE tooling through the supported config-only command,
        # then require the already-enforced locks and source to remain exact.
        run([flutter, 'build', 'apk', '--release', '--config-only', '--target', 'lib/main.dart',
             '--target-platform', 'android-arm64', '--build-name', version,
             '--build-number', str(a.build_number)], app, env, visible=True)
        clean()
        require(all(sha(source / name) == value for name, value in locks.items()), 'config-only changed a lockfile')
        registrant = app / 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
        require(registrant.is_file() and 'dev.flutter.plugins.integration_test' not in registrant.read_text(), 'release tooling retained a dev-only integration plugin')
        run([flutter, 'build', 'apk', '--release', '--no-pub', '--target', 'lib/main.dart',
             '--target-platform', 'android-arm64', '--build-name', version,
             '--build-number', str(a.build_number)], app, env, visible=True)
        apk = app / 'build/app/outputs/flutter-apk/app-release.apk'
        verified = run([signer, 'verify', '--verbose', '--print-certs', apk], app, env)
        signers = re.findall(r'Signer #[0-9]+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', verified)
        require([s.lower() for s in signers] == [digest], 'APK signer mismatch')
        packaged = verify_manifest(run([analyzer, 'manifest', 'print', apk], app, env), version, a.build_number)
        clean()
        require(all(sha(source / name) == value for name, value in locks.items()), 'lockfile changed')
        out.mkdir()
        target = out / ('hnuhole-' + a.source_sha[:12] + '-arm64-test.apk')
        shutil.copyfile(apk, target)
        require(sha(target) == sha(apk), 'artifact copy changed verified APK bytes')
        manifest = dict(schemaVersion=1, result='PASS', createdAtUtc=datetime.now(timezone.utc).isoformat(),
                        sourceSha=a.source_sha, workflowSha=a.workflow_sha, sourceTree=git(source, 'rev-parse', 'HEAD^{tree}'),
                        workflowRunUrl=(os.environ.get('GITHUB_SERVER_URL', 'https://github.com') + '/' + os.environ['GITHUB_REPOSITORY'] + '/actions/runs/' + os.environ['GITHUB_RUN_ID']) if os.environ.get('GITHUB_RUN_ID') else None,
                        buildMode='release', entrypoint='lib/main.dart', **packaged,
                        signingPurpose='ephemeral-isolated-test-only', signingCertificateSha256=digest,
                        samePackageUpgradeAcrossRuns=False, apkSha256=sha(target), apkBytes=target.stat().st_size,
                        fileName=target.name, lockfileSha256=locks, toolchain=tools,
                        serviceConfiguration='unconfigured: compiled .invalid defaults; no development CA or RP override',
                        deviceValidation='NOT_RUN', serviceSmoke='NOT_RUN', productionRelease=False,
                        androidBuildTools='36.0.0', ndk='28.2.13676358', cmake='3.22.1',
                        gradleWrapperSha256=sha(app / 'android/gradle/wrapper/gradle-wrapper.properties'))
    require(not Path(private).exists(), 'test signing material not removed')
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (out / 'SHA256SUMS').write_text(sha(target) + '  ' + target.name + '\n' + sha(out / 'manifest.json') + '  manifest.json\n')
    print('Actual test-signed release candidate verified; device NOT_RUN', flush=True)


if __name__ == '__main__':
    main()
