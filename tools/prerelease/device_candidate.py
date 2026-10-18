#!/usr/bin/env python3
"""Build a pinned-CA main.dart debug APK offline from any physical device.

All tools/caches/HOME must be under the explicitly owned --tool-root. Only public
CA/origins are build inputs. Signing material remains in a private local directory.
This command never invokes ADB, starts a server, or installs an APK.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import ssl
import tempfile
from urllib.parse import urlsplit

from candidate import PACKAGE, git, require, run, sha, verify_manifest

MARKER = 'hnuhole-prerelease-device-signing-v1'


def validate_origins(community, verifier):
    normalized = []
    for value in (community, verifier):
        origin = urlsplit(value)
        require(origin.scheme == 'https' and origin.hostname == '127.0.0.1'
                and origin.username is None and origin.password is None
                and origin.port is not None and 1024 <= origin.port <= 65535
                and not origin.path and not origin.query and not origin.fragment
                and value == 'https://127.0.0.1:' + str(origin.port), 'fixed loopback HTTPS origin required')
        normalized.append(origin.geturl())
    require(normalized[0] != normalized[1], 'independent C/V origins required')


def load_config(path):
    config = json.loads(path.read_text())
    require(set(config) == {'communityOrigin', 'verifierOrigin', 'caPem'}, 'only public origins and CA are accepted')
    validate_origins(config['communityOrigin'], config['verifierOrigin'])
    ca = config['caPem']
    require(isinstance(ca, str) and len(ca.encode()) <= 16384
            and ca.count('-----BEGIN CERTIFICATE-----') == 1
            and ca.strip().startswith('-----BEGIN CERTIFICATE-----')
            and ca.strip().endswith('-----END CERTIFICATE-----')
            and 'PRIVATE' not in ca, 'single public CA certificate required')
    ssl.PEM_cert_to_DER_cert(ca)
    return config


def private_directory(path):
    require(not path.is_symlink() and path == path.resolve(), 'canonical signing directory required')
    if not path.exists():
        path.mkdir(mode=0o700)
    require(path.is_dir() and path.stat().st_uid == os.getuid() and not path.stat().st_mode & 0o077,
            'signing directory must be owned and private')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--source-sha', required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--config', type=Path, required=True)
    p.add_argument('--tool-root', type=Path, required=True)
    p.add_argument('--signing-dir', type=Path, required=True)
    p.add_argument('--build-number', type=int, required=True)
    a = p.parse_args()
    require(os.name == 'posix' and os.getuid() != 0, 'owned non-root Linux build required')
    require(re.fullmatch('[0-9a-f]{40}', a.source_sha), 'exact source SHA required')
    require(1 <= a.build_number <= 2100000000, 'invalid Android versionCode')
    source, out, tool_root = a.source.resolve(), a.out.resolve(), a.tool_root.resolve()
    require(a.tool_root == tool_root and not a.tool_root.is_symlink()
            and tool_root.stat().st_uid == os.getuid() and not tool_root.stat().st_mode & 0o077
            and not tool_root.is_relative_to(source), 'owned private external tool root required')
    require(not out.is_relative_to(source) and not source.is_relative_to(out) and not out.exists(), 'new external artifact directory required')
    require(not a.signing_dir.resolve().is_relative_to(source) and not a.signing_dir.resolve().is_relative_to(out)
            and not out.is_relative_to(a.signing_dir.resolve()), 'signing material must be separate from source/artifacts')
    for name in ('HOME', 'PUB_CACHE', 'GRADLE_USER_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'FLUTTER_ROOT', 'JAVA_HOME'):
        require(Path(os.environ[name]).resolve().is_relative_to(tool_root), 'tool/cache outside owned root: ' + name)
    config = load_config(a.config)

    def clean():
        require(git(source, 'rev-parse', 'HEAD') == a.source_sha, 'source SHA mismatch')
        require(not git(source, 'status', '--porcelain', '--untracked-files=all'), 'source is dirty')

    clean()
    app = source / 'apps/mobile'
    locks = {name: sha(source / name) for name in git(source, 'ls-files', '*pubspec.lock').splitlines()}
    version = re.search(r'^version:\s*([^+\s]+)', (app / 'pubspec.yaml').read_text(), re.M).group(1)
    keytool = Path(os.environ['JAVA_HOME']) / 'bin/keytool'
    flutter = Path(os.environ['FLUTTER_ROOT']) / 'bin/flutter'
    sdk = Path(os.environ['ANDROID_HOME'])
    tools = json.loads(run([flutter, '--version', '--machine'], app))
    require(tools['frameworkVersion'] == '3.47.5', 'Flutter version mismatch')
    private_directory(a.signing_dir)
    marker, key, password_file = (a.signing_dir / name for name in ('marker.json', 'test.jks', 'password.private'))
    if not marker.exists():
        require(not list(a.signing_dir.iterdir()), 'refusing unmarked signing files')
        password_file.write_text(secrets.token_urlsafe(40))
        password_file.chmod(0o600)
    else:
        require(json.loads(marker.read_text()) == dict(marker=MARKER, applicationId=PACKAGE), 'signing scope mismatch')
    require(password_file.is_file() and not password_file.is_symlink()
            and not password_file.stat().st_mode & 0o077, 'private signing password required')
    env = dict(os.environ, HNUHOLE_PRERELEASE_DEVICE='1', HNUHOLE_TEST_KEYSTORE=str(key),
               HNUHOLE_TEST_KEY_ALIAS='prerelease-device-test', HNUHOLE_TEST_STORE_PASSWORD=password_file.read_text(),
               HNUHOLE_TEST_KEY_PASSWORD=password_file.read_text())
    if not marker.exists():
        run([keytool, '-genkeypair', '-noprompt', '-keystore', key, '-storetype', 'JKS',
             '-storepass:env', 'HNUHOLE_TEST_STORE_PASSWORD', '-keypass:env', 'HNUHOLE_TEST_KEY_PASSWORD',
             '-alias', env['HNUHOLE_TEST_KEY_ALIAS'], '-keyalg', 'RSA', '-keysize', '3072', '-validity', '90',
             '-dname', 'CN=HnuHole Owned Device Test,OU=Prerelease,O=HnuHole'], app, env)
        key.chmod(0o600)
        marker.write_text(json.dumps(dict(marker=MARKER, applicationId=PACKAGE)) + '\n')
        marker.chmod(0o600)
    require(key.is_file() and not key.is_symlink() and not key.stat().st_mode & 0o077, 'private signing key required')
    cert = run([keytool, '-exportcert', '-keystore', key, '-storepass:env', 'HNUHOLE_TEST_STORE_PASSWORD',
                '-alias', env['HNUHOLE_TEST_KEY_ALIAS']], app, env, binary=True)
    digest = hashlib.sha256(cert).hexdigest()
    with tempfile.TemporaryDirectory(prefix='device-config-', dir=out.parent) as private:
        os.chmod(private, 0o700)
        ca_file, defines_file = Path(private) / 'ca.pem', Path(private) / 'defines.json'
        ca_file.write_text(config['caPem'])
        # Reject an expired CA before spending time on a build. Leaf certificates
        # and the stopped backend remain a separate window-time preflight.
        run(['openssl', 'x509', '-in', ca_file, '-checkend', '0', '-noout'], app)
        run(['openssl', 'verify', '-CAfile', ca_file, ca_file], app)
        ssl.create_default_context(cafile=str(ca_file))
        dates = run(['openssl', 'x509', '-in', ca_file, '-noout', '-startdate', '-enddate'], app).strip()
        defines = dict(AUTH_COMMUNITY_BASE_URL=config['communityOrigin'], AUTH_VERIFIER_BASE_URL=config['verifierOrigin'],
                       AUTH_DEV_CA_BASE64=base64.b64encode(config['caPem'].encode()).decode())
        defines_file.write_text(json.dumps(defines, sort_keys=True) + '\n')
        define_sha = sha(defines_file)
        build_args = ['--target', 'lib/main.dart', '--target-platform', 'android-arm64', '--build-name', version,
                      '--build-number', str(a.build_number), '--dart-define-from-file', defines_file]
        run([flutter, 'build', 'apk', '--debug', '--config-only', *build_args], app, env, visible=True)
        clean()
        require(all(sha(source / name) == value for name, value in locks.items()), 'config-only changed a lockfile')
        run([flutter, 'build', 'apk', '--debug', '--no-pub', *build_args], app, env, visible=True)
        apk = app / 'build/app/outputs/flutter-apk/app-debug.apk'
        verified = run([sdk / 'build-tools/36.0.0/apksigner', 'verify', '--verbose', '--print-certs', apk], app, env)
        signers = re.findall(r'Signer #[0-9]+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', verified)
        require([s.lower() for s in signers] == [digest], 'APK signer mismatch')
        packaged = verify_manifest(run([sdk / 'cmdline-tools/latest/bin/apkanalyzer', 'manifest', 'print', apk], app, env),
                                   version, a.build_number, debug=True)
        clean()
        require(all(sha(source / name) == value for name, value in locks.items()), 'lockfile changed')
        out.mkdir()
        target = out / ('hnuhole-' + a.source_sha[:12] + '-arm64-device-test.apk')
        shutil.copyfile(apk, target)
        require(sha(target) == sha(apk), 'APK copy changed bytes')
        manifest = dict(schemaVersion=1, result='PASS_NON_DEVICE_PREPARATION', createdAtUtc=datetime.now(timezone.utc).isoformat(),
                        sourceSha=a.source_sha, sourceTree=git(source, 'rev-parse', 'HEAD^{tree}'), buildMode='debug',
                        entrypoint='lib/main.dart', **packaged, apkSha256=sha(target), apkBytes=target.stat().st_size,
                        fileName=target.name, signingPurpose='owned-session-device-test-only', signingCertificateSha256=digest,
                        signingKeyRetainedPrivately=True, authenticationIdentityChanged=False,
                        diagnosticActivityAndDalDeclarationsPresent=False, diagnosticCodeAndResourcesMayBePresent=True,
                        communityOrigin=config['communityOrigin'], verifierOrigin=config['verifierOrigin'],
                        developmentCaPemSha256=sha(ca_file), developmentCaValidity=dates, dartDefinesSha256=define_sha,
                        rpOverride=None, trust='debug app-only CA; normal certificate chain and hostname validation',
                        toolchain=tools, lockfileSha256=locks, androidBuildTools='36.0.0', ndk='28.2.13676358', cmake='3.22.1',
                        adbInvoked=False, deviceValidation='NOT_RUN', apkServiceSmoke='NOT_RUN', productionRelease=False,
                        installationPrecondition='check existing same-package ownership and signer; never uninstall or overwrite another task')
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (out / 'SHA256SUMS').write_text(sha(target) + '  ' + target.name + '\n' + sha(out / 'manifest.json') + '  manifest.json\n')
    print('Owned pinned-CA debug package verified; no device operation; device NOT_RUN', flush=True)


if __name__ == '__main__':
    main()
