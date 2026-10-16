#!/usr/bin/env python3
"""Validate a prepared kit and print its offline window plan. No network/ADB."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import ssl
import subprocess

OWNER = 'HNUHOLE_POST_MEDIA_ANDROID_V1|E:/Hnuhole-post-media-joint-20261015/repo'
PACKAGES = {'main': 'org.hnuhole.post_media_android', 'probe': 'org.hnuhole.post_media_android.probe'}
FIXED = ['private/build-defines.json', 'private/debug-manifest.xml', 'private/debug-manifest-probe.xml',
         'private/native-probe.dart', 'private/dev-ca.pem', 'fixtures/manifest.json']


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()


def owned(kit):
    kit = Path(kit)
    if not kit.is_absolute() or kit.is_symlink() or kit.resolve() != kit or (kit/'.owner').read_text().strip() != OWNER:
        raise ValueError('Canonical owned kit required')
    return kit


def verify(kit, now=None):
    kit = owned(kit)
    manifest = json.loads((kit/'window-plan.json').read_text())
    if manifest.get('owner') != OWNER or manifest.get('deviceOperationsExecuted') is not False:
        raise ValueError('Preparation manifest scope mismatch')
    if set(manifest['artifacts']) != set(PACKAGES) or set(manifest['fixedKitInputs']) != set(FIXED):
        raise ValueError('Prepared kit inputs incomplete or outside fixed scope')
    if len(manifest['fixtures']) != 9 or len({item['name'] for item in manifest['fixtures']}) != 9:
        raise ValueError('Exactly nine distinct original fixtures required')
    for name, package in PACKAGES.items():
        artifact = manifest['artifacts'][name]
        path = kit/'artifacts'/(name+'.apk')
        if artifact['package'] != package or artifact['minimumApi'] != 29 or sha(path) != artifact['sha256']:
            raise ValueError('APK identity or digest changed: '+name)
    if manifest['artifacts']['main']['signerSha256'] != manifest['artifacts']['probe']['signerSha256']:
        raise ValueError('Main/probe test signing identity differs')
    for item in manifest['fixtures']:
        name = item['name']
        if Path(name).name != name or sha(kit/'fixtures'/name) != item['sha256']:
            raise ValueError('Original fixture changed')
    for name, fingerprint in manifest['fixedKitInputs'].items():
        if sha(kit/name) != fingerprint:
            raise ValueError('Prepared build input changed: '+name)
    repo = Path(manifest['repository'])
    if not repo.is_absolute() or repo.is_symlink() or repo.resolve() != repo or not manifest['sourceInputs']:
        raise ValueError('Canonical source repository and nonempty input inventory required')
    for name, fingerprint in manifest['sourceInputs'].items():
        if Path(name).is_absolute() or '..' in Path(name).parts or not name.startswith((
                'apps/mobile/', 'packages/image_viewer/', 'packages/auth_vault/',
                'packages/auth_passkey/', 'tools/post-media-android/')):
            raise ValueError('Source input escaped component scope')
        if hashlib.sha256((repo/name).read_bytes().replace(b'\r\n', b'\n')).hexdigest() != fingerprint:
            raise ValueError('Prepared source changed: '+name)
    now = datetime.datetime.now(datetime.timezone.utc).timestamp() if now is None else now
    if now + 1800 >= manifest['tlsLeafExpiresAtUnix']:
        raise ValueError('Private TLS leaf expired or less than 30 minutes left; rebuild trust kit before phone use')
    server = json.loads((kit/'logs/server-preparation.json').read_text())
    if server['result'] != 'PASS' or not server['stopped'] or not server['privateSocketOnly']:
        raise ValueError('Backend preparation/stop evidence incomplete')
    return manifest


def create(kit, repository):
    kit, repository = owned(kit), Path(repository).resolve()
    artifacts = {}
    for name, package in PACKAGES.items():
        aapt = (kit/'logs'/(name+'-aapt.log')).read_text(encoding='utf-8-sig')
        signature = (kit/'logs'/(name+'-signature.log')).read_text(encoding='utf-8-sig')
        import re
        cert = re.search(r'Signer #1 certificate SHA-256 digest:\s*([a-fA-F0-9]{64})', signature)
        if not cert or 'Verified using v2 scheme (APK Signature Scheme v2): true' not in signature:
            raise ValueError('APK signature not verified')
        if "package: name='"+package+"'" not in aapt or "sdkVersion:'29'" not in aapt or "versionCode='20263115'" not in aapt:
            raise ValueError('Unexpected native package/minimum API/version')
        path = kit/'artifacts'/(name+'.apk')
        artifacts[name] = {'package': package, 'minimumApi': 29, 'versionCode': 20263115,
                           'versionName': '0.1.0-media-android-ready', 'sha256': sha(path),
                           'bytes': path.stat().st_size, 'signerSha256': cert[1].lower(),
                           'signature': 'PASS_V2', 'installed': False}
    certs = [ssl._ssl._test_decode_cert(str(kit/'private'/name)) for name in ['c-public.pem', 'v-public.pem']]
    expiry = min(ssl.cert_time_to_seconds(item['notAfter']) for item in certs)
    fixture = json.loads((kit/'fixtures/manifest.json').read_text())
    source = {}
    names = subprocess.check_output(['git', '-C', str(repository), 'ls-files', '--cached', '--others', '--exclude-standard', '--',
                                     'apps/mobile/lib', 'apps/mobile/android', 'apps/mobile/integration/post_media_android_preflight_test.dart', 'packages/image_viewer/lib',
                                     'packages/auth_vault', 'packages/auth_passkey', 'tools/post-media-android'], text=True).splitlines()
    for name in names + ['apps/mobile/pubspec.yaml', 'apps/mobile/pubspec.lock', 'packages/image_viewer/pubspec.lock']:
        path = repository/name
        if path.is_file():
            source[name] = hashlib.sha256(path.read_bytes().replace(b'\r\n',b'\n')).hexdigest()
    fixed = FIXED
    server = json.loads((kit/'logs/server-preparation.json').read_text())
    manifest = {'schema': 'hnuhole-post-media-android-ready/v1', 'owner': OWNER,
                'repository': str(repository), 'sourceHeadBeforePreparationCommit': subprocess.check_output(['git','-C',str(repository),'rev-parse','HEAD'],text=True).strip(),
                'sourceInputs': dict(sorted(source.items())), 'artifacts': artifacts,
                'fixedKitInputs': {name: sha(kit/name) for name in fixed}, 'fixtures': fixture['originals'],
                'tlsLeafExpiresAtUnix': expiry, 'deviceOperationsExecuted': False,
                'backendRoot': server['root'], 'backendPreparedAndStopped': True,
                'status': 'READY_AWAITING_DEVICE',
                'pending': {name: 'NOT_RUN' for name in ['nativeProbeWriteReadPurge', 'realPhotoPicker', 'mainOriginalUpload',
                    'killAndRestore', 'missingItemResume', 'mainViewerEntryAndGestures', 'nativeOriginalSaveAndAlbums',
                    'businessImeAndNewControlsAccessibility', 'accountIsolationAndLateRead', 'resourceObservation']}}
    (kit/'window-plan.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return verify(kit)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kit', required=True)
    parser.add_argument('--create', action='store_true')
    parser.add_argument('--repository')
    args = parser.parse_args()
    value = create(args.kit, args.repository) if args.create else verify(args.kit)
    print(json.dumps({'status': value['status'], 'packages': PACKAGES, 'deviceOperationsExecuted': False,
                      'tlsLeafExpiresAtUnix': value['tlsLeafExpiresAtUnix'], 'next': 'Release device window; start own lab and follow README. No phone operation executed.'}))
