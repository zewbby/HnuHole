#!/usr/bin/env python3
"""Prepare an isolated B3/B4 continuation after the archive key was lost.

This creates fresh disposable C/V resources and reviewed source overlays only.
It never installs, uninstalls, launches or authenticates an Android application.
The historical eight PASS records and original phone packages remain untouched.
Run in the dedicated HnuHole WSL distro after sourcing ~/.hnuhole-env.sh.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import time


TOKEN = 'HNUHOLE_B3B4_FRESH_20261012_V1'
LINUX = Path('/home/hnuhole/hnuhole-android-live-b3-b4-20261012')
HOST = Path('/mnt/e/Hnuhole-env/acceptance-20261012/matrix')
WINDOWS_HOST = 'E:/Hnuhole-env/acceptance-20261012/matrix'
REPO = Path('/mnt/e/Hnuhole-env/source/HnuHole')
CERT = '6f1fa8f97a7a68e0e13a0a957331073983a19a79353cdd5a54aa8b096a51aa03'
PACKAGE = 'org.hnuhole.hnuhole_mobile.acceptance20261012'
MISSING_PACKAGE = 'org.hnuhole.hnuhole_mobile.unassociated20261012'
DEVICE = '10CEAG17RY003M7'
RUN = 'hnuhole-android-live-matrix-20261012'
ACCOUNT_RUN = LINUX.name
OLD_LINUX = '/var/tmp/hnuhole-android-live-b3-b4-20261009'
OLD_HOST = 'D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix'
OLD_SOURCE = 'C:/Users/Administrator/Documents/ChatGPT/HnuHole'
OLD_RUN = 'hnuhole-android-live-matrix-20261006'
OLD_ACCOUNT_RUN = 'hnuhole-android-live-b3-b4-20261009'
MAIN_PACKAGE = 'org.hnuhole.hnuhole_mobile'
CONTROL_PACKAGE = MAIN_PACKAGE + '.acceptance'
OLD_MISSING_PACKAGE = MAIN_PACKAGE + '.unassociated'
PROXY = 'tools/android-auth-b3-b4-proxy.py'
FIXTURE = 'apps/mobile/integration_test/auth_android_b3_b4_device_test.dart'
SOURCE_SET = (
    FIXTURE, 'apps/mobile/integration_test/owned_auth_device_helpers.dart',
    'apps/mobile/android/app/src/main/kotlin/org/hnuhole/hnuhole_mobile/MainActivity.kt',
    'packages/auth_passkey/android/src/main/kotlin/org/hnuhole/authpasskey/AuthPasskeyPlugin.kt',
    'packages/auth_passkey/android/src/main/kotlin/org/hnuhole/authpasskey/PasskeyCodec.kt',
    'packages/auth_passkey/android/src/main/kotlin/org/hnuhole/authpasskey/PendingOperation.kt',
    'packages/auth_passkey/android/src/main/kotlin/org/hnuhole/authpasskey/PasskeyAcceptanceErrors.kt',
    'packages/auth_vault/android/src/main/kotlin/org/hnuhole/authvault/AndroidAuthVault.kt',
    'packages/auth_vault/android/src/main/kotlin/org/hnuhole/authvault/AuthVaultPlugin.kt',
    'tools/run-android-live-device.ps1', 'tools/control-android-b3-b4-device.py',
    'tools/control-android-b3-b4.py', PROXY, 'tools/control-android-closure.py',
    'tools/start-android-b3-b4-service.py',
)
OVERLAY_FILES = frozenset((FIXTURE, 'tools/run-auth-device-services.sh', PROXY,
    'tools/control-android-b3-b4.py', 'tools/control-android-b3-b4-device.py',
    'tools/run-android-live-device.ps1', 'tools/run-android-b3-b4.ps1'))
# Exact generated versions observed in the owned mirrors after preparation
# stopped at drvfs metadata copying. They authorize only refreshing these
# task-created helper files; never a changed product source or user artifact.
PARTIAL_HELPER_VERSIONS = {
    'tools/prepare-android-b3-b4-fresh.py': frozenset(('76fbd54d1188f0fbdbc9cc1b44951802a12a63a5793e0a89618949723627dd25',)),
    'tools/tests/test_android_b3_b4_fresh.py': frozenset(('6589b4156b4a2a494d264154b0fe80095c0309743cb4b287b343dd7c309829a1',)),
    # Parent inspected every changed file: this diagnostic build helper was
    # subsequently tightened with AAPT2/association guards; no product differed.
    'tools/android-passkey-diagnostic/build-google-fido-diagnostic.py': frozenset(('6ef753e69eace82d82ed5ed623de2c1edc6a8d23f96af5aaa7b8b084fb7997bb',)),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    temp.replace(path)


def origin(cert):
    if not re.fullmatch('[a-f0-9]{64}', cert):
        raise ValueError('An exact SHA-256 certificate digest is required')
    return 'android:apk-key-hash:' + base64.urlsafe_b64encode(bytes.fromhex(cert)).decode().rstrip('=')


def owned_directory(path, owner):
    if path.is_symlink():
        raise ValueError('Owned directory must not be a symlink')
    if path.exists():
        if not path.is_dir() or (path / 'OWNER').read_text().strip() != owner:
            raise ValueError('Refusing to adopt an existing unknown directory')
        if (path / 'FRESH_OWNER').read_text().strip() != TOKEN:
            raise ValueError('An exact fresh-run ownership marker is required')
    else:
        path.mkdir(mode=0o700, parents=False)
        (path / 'OWNER').write_text(owner + '\n')
        (path / 'FRESH_OWNER').write_text(TOKEN + '\n')
    if path.resolve() != path:
        raise ValueError('Owned directory must resolve to its exact absolute path')


def replace_exact(text, old, new, expected=None):
    count = text.count(old)
    if count == 0 or (expected is not None and count != expected):
        raise ValueError('Overlay source changed; review its replacement before retrying')
    return text.replace(old, new)


def overlay(name, data):
    """Only execution coordinates change; no authentication assertions loosen."""
    if name not in OVERLAY_FILES:
        return data
    text = data.decode('utf-8')
    if name == FIXTURE:
        text = replace_exact(text, OLD_RUN, RUN, 1)
        text = replace_exact(text, OLD_ACCOUNT_RUN, ACCOUNT_RUN, 1)
        text = replace_exact(text, "const _batch = '20261010-v16';", "const _batch = '20261012-fresh';", 1)
        text = replace_exact(text, CONTROL_PACKAGE, PACKAGE)
        text = replace_exact(text, "defaultValue: '" + MAIN_PACKAGE + "'", "defaultValue: '" + PACKAGE + "'", 1)
    elif name == 'tools/run-auth-device-services.sh':
        old = ' -smtp-port "$MAILPIT_SMTP_PORT" \\\n'
        new = old + (' -webauthn-rp-id "zewbby.github.io" \\\n'
                     ' -webauthn-https-origins "https://zewbby.github.io" \\\n'
                     ' -webauthn-android-origins ' + shlex.quote(origin(CERT)) + ' \\\n')
        text = replace_exact(text, old, new, 1)
    elif name == PROXY:
        text = replace_exact(text, OLD_LINUX, LINUX.as_posix(), 1)
        text = replace_exact(text, OLD_RUN, RUN, 1)
    elif name == 'tools/control-android-b3-b4.py':
        text = replace_exact(text, OLD_LINUX, LINUX.as_posix(), 1)
        text = replace_exact(text, 'hnuhole-device-hnuholeandroidliveb3b420261009',
                             'hnuhole-device-hnuholeandroidliveb3b420261012', 1)
        # This fresh continuation cannot invoke closure/recovery of old cases.
        text = replace_exact(text, 'args=parser.parse_args();owned()',
            "args=parser.parse_args();owned()\n    assert args.phase in ('ni-d01','ni-d02','ni-d03') or args.action in ('status','normal','wrong-rp-options','wrong-rp-hash'), 'Fresh continuation is limited to the remaining association cases'\n    assert not args.resume_existing, 'Historical state cannot be resumed in the fresh database'", 1)
    elif name == 'tools/control-android-b3-b4-device.py':
        text = replace_exact(text, OLD_HOST, WINDOWS_HOST)
        text = replace_exact(text, 'D:/zewbbyTest/Hnuhole-env', 'E:/Hnuhole-env')
        text = replace_exact(text, OLD_LINUX, LINUX.as_posix())
        text = replace_exact(text, OLD_RUN, RUN)
        text = replace_exact(text, CONTROL_PACKAGE, PACKAGE)
        text = replace_exact(text, OLD_MISSING_PACKAGE, MISSING_PACKAGE)
        text = replace_exact(text, "PACKAGES=('" + MAIN_PACKAGE + "'", "PACKAGES=('" + PACKAGE + "'", 1)
        text = replace_exact(text, "['wsl','-d','Ubuntu-24.04','--','python3'",
                             "['wsl','-d','HnuHole-Ubuntu-24.04','-u','hnuhole','--','python3'", 1)
        text = replace_exact(text, 'args=parser.parse_args()',
            "args=parser.parse_args()\n    assert args.phase in ('ni-d01','ni-d02','ni-d03'), 'Fresh witness is limited to remaining association cases'", 1)
    elif name in ('tools/run-android-live-device.ps1', 'tools/run-android-b3-b4.ps1'):
        if name.endswith('run-android-live-device.ps1'):
            text = replace_exact(text, CONTROL_PACKAGE, PACKAGE)
            text = replace_exact(text, OLD_MISSING_PACKAGE, MISSING_PACKAGE)
        # Preserve the Java/Kotlin activity namespace. Replace package literals
        # only, never org.hnuhole.hnuhole_mobile.MainActivity.
        text = text.replace("'" + MAIN_PACKAGE + "'", "'" + PACKAGE + "'")
        # Replace complete coordinates before their contained run names. The
        # reverse order leaves /var/tmp/<new-account-run> pointing nowhere.
        text = text.replace(OLD_LINUX, LINUX.as_posix()).replace(OLD_HOST, WINDOWS_HOST)
        text = text.replace(OLD_ACCOUNT_RUN, ACCOUNT_RUN).replace(OLD_RUN, RUN)
        text = text.replace('D:\\zewbbyTest\\Hnuhole-env', 'E:\\Hnuhole-env')
        text = text.replace('D:/zewbbyTest/Hnuhole-android-live-faults-20261005', WINDOWS_HOST.rsplit('/matrix', 1)[0])
        text = text.replace(OLD_SOURCE, WINDOWS_HOST + '/repo')
        text = text.replace('& wsl -d Ubuntu-24.04 --', '& wsl -d HnuHole-Ubuntu-24.04 -u hnuhole --')
        if name.endswith('run-android-b3-b4.ps1'):
            text = replace_exact(text, '$ErrorActionPreference=\'Stop\'',
                "$ErrorActionPreference='Stop'\nif($Phase -notin @('ni-d01','ni-d02','ni-d03')){throw 'Fresh continuation accepts only the three remaining association cases'}\nif($ResumeOriginalDraftClosure){throw 'No historical closure state exists in the fresh environment'}", 1)
            text = replace_exact(text, "$package+='.acceptance'", "$package='" + PACKAGE + "'", 1)
            text = replace_exact(text, "$package+='.unassociated'", "$package='" + MISSING_PACKAGE + "'", 1)
            text = replace_exact(text, "-PubCache 'E:/Hnuhole-env/acceptance-20261012/pub-windows'",
                "-PubCache 'E:/Hnuhole-env/acceptance-20261012/pub-windows' -EnvironmentRoot 'E:/Hnuhole-env'", 1)
    else:
        return data
    return text.replace('\r\n', '\n').encode('utf-8')


def tracked_sources(repo):
    result = subprocess.run(['git', '-c', 'safe.directory=' + str(repo), '-C', str(repo), 'ls-files', '-z'],
                            capture_output=True, check=True)
    names = [n.decode('utf-8') for n in result.stdout.split(b'\0') if n]
    # The bootstrap is itself new source and is included before any commit.
    for this in ('tools/prepare-android-b3-b4-fresh.py', 'tools/build-android-b3-b4-fresh.py',
                 'tools/tests/test_android_b3_b4_fresh.py'):
        if (repo / this).is_file() and this not in names:
            names.append(this)
    for name in names:
        rel = Path(name)
        if rel.is_absolute() or '..' in rel.parts or '.git' in rel.parts:
            raise ValueError('Unexpected tracked source path')
        source = repo / rel
        if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(repo):
            raise ValueError('Only actual repository source files may enter the mirror')
    return names


def write_source_file(root, name, data, linux_executable):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    # Windows drvfs files do not use Linux executable ownership. Do not mask a
    # failure on the real Linux service/build mirror; its scripts need mode0700.
    if linux_executable and (name.endswith('.sh') or name.endswith('/gradlew')):
        # PostgreSQL's entrypoint sources this public script as the container's
        # postgres user. Source bytes contain no secrets; its bind mount must be
        # readable by that UID. Private launchers remain owner-only.
        path.chmod(0o755 if name == 'infra/postgres/init-auth.sh' else 0o700)


def copy_source_tree(source, target):
    """Copy bytes and directory structure only; drvfs must not receive copystat."""
    if source.is_symlink() or not source.is_dir():
        raise ValueError('Only a real generated source directory may be copied')
    target.mkdir(parents=True, exist_ok=True)
    for child in source.rglob('*'):
        if child.is_symlink() or not child.resolve().is_relative_to(source.resolve()):
            raise ValueError('Generated source tree contains a symlink or escaped path')
        destination = target / child.relative_to(source)
        if child.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
        elif child.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            data = child.read_bytes()
            if not destination.exists() or destination.read_bytes() != data:
                destination.write_bytes(data)


def fresh_launcher_bytes():
    return ('#!/bin/bash\nset -euo pipefail\numask 077\nsource /home/hnuhole/.hnuhole-env.sh\n'
        + 'export AUTH_DEVICE_WORK=' + shlex.quote(str(LINUX)) + '\n'
        + 'export AUTH_DEVICE_RETAIN=1\n'
        + 'exec /bin/bash ' + shlex.quote(str(LINUX / 'repo/tools/run-auth-device-services.sh')) + '\n').encode()


def admit_failed_unit(load_state, active_state, main_pid, exec_start, retained_failure=False):
    if main_pid != '0' or active_state not in ('inactive', 'failed'):
        raise ValueError('Preserve a live or unknown bootstrap process')
    if load_state == 'loaded':
        if str(LINUX / 'start-fresh-services.sh') not in exec_start:
            raise ValueError('Preserve an unknown loaded service unit')
    elif load_state == 'not-found':
        if active_state != 'inactive' or exec_start or not retained_failure:
            raise ValueError('Absent unit requires the exact retained failed launcher/log')
    else:
        raise ValueError('Preserve an unknown service unit load state')


def verify_partial_tree(repo, target, names):
    if not target.exists():
        return 0
    if target.is_symlink() or not target.is_dir() or target.resolve() != target:
        raise ValueError('Partial source mirror must be an exact real directory')
    count = 0
    for path in target.rglob('*'):
        if path.is_symlink() or not path.resolve().is_relative_to(target):
            raise ValueError('Refuse partial source recovery with a symlink or escaped file')
        if path.is_file():
            name = path.relative_to(target).as_posix()
            if name not in names:
                raise ValueError('Partial source recovery found an unknown file; preserve it')
            source = (repo / name).read_bytes()
            data = path.read_bytes()
            if data not in (source, overlay(name, source)) and digest(data) not in PARTIAL_HELPER_VERSIONS.get(name, ()):
                raise ValueError('Partial source content changed; preserve it for review')
            count += 1
    return count


def prepare(repo, resume_partial=False):
    owned_directory(LINUX, 'HNUHOLE_ANDROID_LIVE_DEV_V1')
    owned_directory(HOST, 'HNUHOLE_ANDROID_MATRIX_V1')
    target = LINUX / 'repo'
    host_target = HOST / 'repo'
    if (LINUX / 'source-manifest.json').exists() or (HOST / 'source-manifest.json').exists():
        raise ValueError('Preserve the previous source mirror; inspect instead of overwriting it')
    names = tracked_sources(repo)
    if resume_partial:
        if any((LINUX / name).exists() for name in ('services', 'device-config.json')):
            raise ValueError('Started services cannot use partial-source continuation')
        verify_partial_tree(repo, target, set(names))
        verify_partial_tree(repo, host_target, set(names))
        verify_partial_tree(repo, HOST / 'driver', set(names))
    elif target.exists() or host_target.exists() or (HOST / 'driver').exists():
        raise ValueError('Preserve partial generated sources; use explicit --resume-partial after review')
    target.mkdir(mode=0o700, exist_ok=resume_partial)
    host_target.mkdir(mode=0o700, exist_ok=resume_partial)
    originals, compiled, modifications = {}, {}, {}
    for name in names:
        data = (repo / name).read_bytes()
        revised = overlay(name, data)
        originals[name] = digest(data)
        compiled[name] = digest(revised)
        if data != revised:
            modifications[name] = dict(sourceSha256=digest(data), stagedSha256=digest(revised),
                scope='FRESH_RP_AND_APPROVED_ORIGIN_POLICY' if name == 'tools/run-auth-device-services.sh'
                    else 'EXECUTION_COORDINATES_AND_REMAINING_PHASE_ADMISSION')
        for root in (target, host_target):
            write_source_file(root, name, revised, linux_executable=(root == target))
    (LINUX / 'b3b4-evidence').mkdir(mode=0o700, exist_ok=resume_partial)
    (HOST / 'b3b4-evidence').mkdir(mode=0o700, exist_ok=resume_partial)
    driver = HOST / 'driver'
    copy_source_tree(host_target / 'apps', driver / 'apps')
    copy_source_tree(host_target / 'packages', driver / 'packages')
    manifest = dict(owner=TOKEN, prepared=True, servicesStarted=False, deviceMutated=False,
        historicalPassRecordsPreserved=True, historicalPackages=[MAIN_PACKAGE, CONTROL_PACKAGE],
        phases=['ni-d01', 'ni-d02', 'ni-d03'], device=DEVICE, applicationId=PACKAGE,
        unassociatedApplicationId=MISSING_PACKAGE, approvedCertificateSha256=CERT,
        approvedAndroidOrigin=origin(CERT), rpId='zewbby.github.io',
        deviceRunId=RUN, accountRunId=ACCOUNT_RUN, linuxRoot=str(LINUX), windowsRoot=WINDOWS_HOST,
        sourceRepository=str(repo), sourceFilesSha256=originals, stagedFilesSha256=compiled,
        overlays=modifications, actualDeviceAcceptancePassed=False)
    write_json(LINUX / 'source-manifest.json', manifest)
    write_json(HOST / 'source-manifest.json', manifest)
    descriptor = dict(target='integration_test/auth_android_b3_b4_device_test.dart',
        targetPlatform='android-arm64', debug=True, install=False, buildNumber=20261012,
        dartDefinesFromFile=str(LINUX / 'b3b4-device-config.json'),
        variants=[dict(fileName='phone-b3b4.apk', applicationId=PACKAGE, signing='approved'),
                  dict(fileName='b3b4-acceptance.apk', applicationId=PACKAGE, signing='approved'),
                  dict(fileName='b3b4-bad-signature.apk', applicationId=PACKAGE, signing='fresh-unassociated-cert'),
                  dict(fileName='b3b4-unassociated.apk', applicationId=MISSING_PACKAGE, signing='approved')],
        sourceFilesSha256={name: compiled[name] for name in SOURCE_SET},
        privateSigningRoot='/mnt/e/Hnuhole-env/acceptance-20261012/signing',
        phaseExecutionUsesReviewedAttachOnlyRunner=True, actualDeviceAcceptancePassed=False)
    write_json(HOST / 'mobile-build-inputs.json', descriptor)
    launcher = LINUX / 'start-fresh-services.sh'
    launcher.write_bytes(fresh_launcher_bytes())
    launcher.chmod(0o700)
    return manifest


def repair_partial(repo):
    """Remove only this run's incomplete, reproducible source mirrors."""
    owned_directory(LINUX, 'HNUHOLE_ANDROID_LIVE_DEV_V1')
    owned_directory(HOST, 'HNUHOLE_ANDROID_MATRIX_V1')
    if any((LINUX / name).exists() for name in ('source-manifest.json', 'services', 'device-config.json')):
        raise ValueError('A completed or started environment cannot use partial-source repair')
    if (HOST / 'source-manifest.json').exists():
        raise ValueError('Preserve a completed host source manifest')
    names = set(tracked_sources(repo))
    verified = []
    for target in (LINUX / 'repo', HOST / 'repo', HOST / 'driver'):
        if not target.exists():
            continue
        owner = LINUX if target.parent == LINUX else HOST
        if target.is_symlink() or target.resolve() != owner / target.name or not target.is_dir():
            raise ValueError('Partial mirror must stay inside its exact freshly owned root')
        count = verify_partial_tree(repo, target, names)
        verified.append((target, count))
    for target, _ in verified:
        shutil.rmtree(target)
    write_json(LINUX / 'partial-source-repair.json', dict(owner=TOKEN, generatedSourceMirrorsOnly=True,
        servicesExisted=False, sourceManifestExisted=False,
        removed=[dict(path=str(path), verifiedFileCount=count) for path, count in verified],
        historicalPhoneAndDatabaseUntouched=True))
    print('REPAIRED: exact owned partial source mirrors; services and phone untouched')


def docker_read_json(*arguments):
    result = subprocess.run(['docker', *arguments], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError('Owned Docker inspection failed; no repair mutation performed')
    return json.loads(result.stdout)


def docker_ids(kind, project):
    command = ['docker', kind, 'ls', '-q', '--filter', 'label=com.docker.compose.project=' + project]
    if kind == 'container':
        command.insert(4, '-a')
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError('Owned Docker inventory failed; no repair mutation performed')
    return result.stdout.split()


def failed_bootstrap_resources(project, containers, volumes, networks):
    """Admit exactly the three services/two volumes/one network of this run."""
    expected_services = {'community-postgres', 'verifier-postgres', 'mailpit'}
    expected_volumes = {project + '_community-dev-data', project + '_verifier-dev-data'}
    if len(containers) != 3 or len(volumes) != 2 or len(networks) != 1:
        raise ValueError('Preserve unexpected Docker resource topology')
    found = set()
    for container in containers:
        labels = container['Config'].get('Labels') or {}
        service = labels.get('com.docker.compose.service')
        if labels.get('com.docker.compose.project') != project or service not in expected_services or service in found:
            raise ValueError('Container is not an exact fresh-project service')
        found.add(service)
        image = 'axllent/mailpit:v1.21.8' if service == 'mailpit' else 'postgres:16.6-alpine'
        if container['Config']['Image'] != image:
            raise ValueError('Preserve a container using an unexpected image')
        for mount in container['Mounts']:
            if mount['Type'] == 'volume' and mount['Name'] not in expected_volumes:
                raise ValueError('Container has a volume outside this exact disposable project')
        if service != 'mailpit':
            expected = 'community-dev-data' if service == 'community-postgres' else 'verifier-dev-data'
            if {m['Name'] for m in container['Mounts'] if m['Type'] == 'volume'} != {project + '_' + expected}:
                raise ValueError('PostgreSQL volume identity mismatch')
            mount = next((m for m in container['Mounts'] if m['Destination'] == '/docker-entrypoint-initdb.d/10-auth.sh'), None)
            if not mount or mount['Type'] != 'bind' or mount['Source'] != str(LINUX / 'repo/infra/postgres/init-auth.sh') or mount.get('RW'):
                raise ValueError('PostgreSQL initialization mount is not this run\'s read-only source')
    for volume in volumes:
        labels = volume.get('Labels') or {}
        if volume['Name'] not in expected_volumes or labels.get('com.docker.compose.project') != project:
            raise ValueError('Volume is not part of this exact freshly generated project')
    if {v['Name'] for v in volumes} != expected_volumes:
        raise ValueError('Fresh-project volume identity mismatch')
    network = networks[0]
    if network['Name'] != project + '_default' or (network.get('Labels') or {}).get('com.docker.compose.project') != project:
        raise ValueError('Network is not this run\'s exact default network')
    if set(network.get('Containers', {})) - {c['Id'] for c in containers}:
        raise ValueError('Network has an attachment outside this fresh disposable project')


def repair_failed_bootstrap():
    """Repair only an unstarted database initialization failure in this run."""
    owned_directory(LINUX, 'HNUHOLE_ANDROID_LIVE_DEV_V1')
    owned_directory(HOST, 'HNUHOLE_ANDROID_MATRIX_V1')
    manifest = json.loads((LINUX / 'source-manifest.json').read_text())
    if manifest.get('owner') != TOKEN or manifest.get('servicesStarted') or manifest.get('servicesReady'):
        raise ValueError('Preserve a started or unknown service environment')
    for root in (LINUX, HOST):
        for name in ('device-config.json', 'b3b4-device-config.json', 'b3b4-acceptance-config.json', 'b3b4-unassociated-config.json'):
            if (root / name).exists():
                raise ValueError('A device-ready environment cannot use failed-bootstrap repair')
        evidence = root / 'b3b4-evidence'
        if evidence.exists() and any(evidence.iterdir()):
            raise ValueError('Preserve existing product acceptance/build evidence')
    services = LINUX / 'services'
    if not services.is_dir() or services.is_symlink() or services.resolve() != LINUX / 'services':
        raise ValueError('Exact newly generated service directory required')
    unit = 'hnuhole-b3b4-fresh-20261012-services'
    status = subprocess.run(['systemctl', '--user', 'show', unit, '--property=LoadState',
        '--property=ActiveState', '--property=MainPID', '--property=ExecStart'], capture_output=True, text=True, timeout=15)
    if status.returncode:
        raise ValueError('Could not inspect the exact failed service unit')
    properties = dict(line.split('=', 1) for line in status.stdout.splitlines() if '=' in line)
    retained_failure = False
    if properties.get('LoadState') == 'not-found':
        launcher = LINUX / 'start-fresh-services.sh'
        log = LINUX / 'services.private.log'
        if (launcher.is_file() and not launcher.is_symlink() and launcher.resolve() == launcher
                and launcher.read_bytes() == fresh_launcher_bytes()
                and log.is_file() and not log.is_symlink() and log.resolve() == log
                and 0 < log.stat().st_size <= 10000000):
            failure = log.read_bytes()
            retained_failure = (b'RETAINED: owned device environment; no exit cleanup requested' in failure
                and b'READY: actual C/V, private disposable SQL, Mailpit and independent development Gates' not in failure)
    admit_failed_unit(properties.get('LoadState'), properties.get('ActiveState'), properties.get('MainPID'),
                      properties.get('ExecStart', ''), retained_failure)
    # The runtime/watchers must never have become live. Commands are inspected
    # in memory; no process environment or authentication payload is exported.
    exact = {str(services / name).encode() for name in ('authdev', 'community', 'verifier')}
    for process in Path('/proc').iterdir():
        if process.name.isdecimal():
            try:
                words = (process / 'cmdline').read_bytes().split(b'\0')
            except OSError:
                continue
            if words and words[0] in exact:
                raise ValueError('Preserve a live owned C/V/operator runtime')
    project = 'hnuhole-device-hnuholeandroidliveb3b420261012'
    ids = docker_ids('container', project)
    volume_ids = docker_ids('volume', project)
    network_ids = docker_ids('network', project)
    containers = docker_read_json('container', 'inspect', *ids) if ids else []
    volumes = docker_read_json('volume', 'inspect', *volume_ids) if volume_ids else []
    networks = docker_read_json('network', 'inspect', *network_ids) if network_ids else []
    failed_bootstrap_resources(project, containers, volumes, networks)
    logs = {}
    for container in containers:
        label = container['Config']['Labels']['com.docker.compose.service']
        result = subprocess.run(['docker', 'logs', container['Id']], capture_output=True, timeout=30)
        if result.returncode:
            raise RuntimeError('Could not preserve the original owned failure log')
        logs[label] = result.stdout + result.stderr
        if label != 'mailpit':
            if b'/docker-entrypoint-initdb.d/10-auth.sh' not in logs[label] or b'Permission denied' not in logs[label]:
                raise ValueError('This repair is limited to the observed public-init-script permissions failure')
            if container['State']['Running']:
                role = 'hnuhole_c_admin' if label == 'community-postgres' else 'hnuhole_v_admin'
                database = 'hnuhole_c' if label == 'community-postgres' else 'hnuhole_v'
                query = "SELECT count(*) FROM pg_namespace WHERE nspname IN ('c_auth','v_auth');"
                check = subprocess.run(['docker', 'exec', container['Id'], 'psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1',
                                        '-U', role, '-d', database, '-c', query], capture_output=True, text=True, timeout=20)
                if check.returncode or check.stdout.strip() != '0':
                    raise ValueError('Preserve an initialized application database or unknown SQL state')
    for volume in volume_ids:
        users = subprocess.run(['docker', 'container', 'ls', '-a', '-q', '--filter', 'volume=' + volume], capture_output=True, text=True, timeout=20)
        if users.returncode or set(users.stdout.split()) - {value[:12] for value in ids} - set(ids):
            raise ValueError('Preserve a volume referenced outside this exact disposable project')
    script = LINUX / 'repo/infra/postgres/init-auth.sh'
    if script.is_symlink() or sha256_file(script) != manifest['stagedFilesSha256']['infra/postgres/init-auth.sh']:
        raise ValueError('Public initialization source bytes changed; review before repair')
    attempt = next((LINUX / ('bootstrap-attempt-' + str(i).zfill(2)) for i in range(1, 100)
                    if not (LINUX / ('bootstrap-attempt-' + str(i).zfill(2))).exists()), None)
    if attempt is None or attempt.resolve() != attempt or not attempt.is_relative_to(LINUX):
        raise ValueError('No bounded, exact owned archive destination is available')
    attempt.mkdir(mode=0o700)
    for label, data in logs.items():
        path = attempt / (label + '.private.log')
        path.write_bytes(data); path.chmod(0o600)
    record = dict(owner=TOKEN, reason='PUBLIC_INIT_SCRIPT_MODE0700_UNREADABLE_BY_POSTGRES_UID',
        unitLoadState=properties['LoadState'], retainedFailureLogAdmitted=retained_failure,
        project=project, containerIds=[c['Id'] for c in containers],
        volumeNames=[v['Name'] for v in volumes], networkNames=[n['Name'] for n in networks],
        noProductDatabaseSchema=True, deviceConfigAbsent=True, liveRuntimeAbsent=True,
        privateMaterialsPreserved=True, oldPhoneAndPassRecordsUntouched=True, result='REPAIRING')
    write_json(attempt / 'repair.json', record)
    # Every target above is exact, fresh, label-owned, and has no product data.
    for command in (['docker', 'container', 'rm', '--force', *ids],
                    ['docker', 'volume', 'rm', *volume_ids], ['docker', 'network', 'rm', *network_ids]):
        result = subprocess.run(command, capture_output=True, timeout=60)
        if result.returncode:
            raise RuntimeError('Exact owned resource repair stopped; retained repair journal identifies the completed scope')
    services.rename(attempt / 'services')
    for name in ('services.private.log', 'service-failure.log'):
        path = LINUX / name
        if path.exists():
            if path.is_symlink() or path.resolve() != LINUX / name:
                raise ValueError('Preserve an unexpected failure-log path')
            path.rename(attempt / name)
    script.chmod(0o755)
    if sha256_file(script) != manifest['stagedFilesSha256']['infra/postgres/init-auth.sh']:
        raise RuntimeError('Public source bytes unexpectedly changed during mode-only repair')
    subprocess.run(['systemctl', '--user', 'reset-failed', unit], capture_output=True, timeout=15)
    record.update(result='REPAIRED', publicInitMode='0755', sourceBytesUnchanged=True,
                  freshServicesMayStartAgain=True, retainedPrivateDirectory=str(attempt / 'services'))
    write_json(attempt / 'repair.json', record)
    print('REPAIRED: only this failed disposable project removed; original private materials/logs retained; init script mode0755')


def sha256_file(path):
    return digest(path.read_bytes())


def private_command(command, log, cwd=None, timeout=600):
    with log.open('a') as output:
        result = subprocess.run(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        raise RuntimeError('Preparation prerequisite failed; inspect the owned private log')


def ensure_prerequisites(allow_network):
    for tool in ('go', 'goose', 'docker', 'psql', 'python3', 'curl', 'systemd-run', 'systemctl'):
        if shutil.which(tool) is None:
            raise RuntimeError('Missing prerequisite: ' + tool)
    private = LINUX / 'dependency-preparation.private.log'
    for image in ('postgres:16.6-alpine', 'axllent/mailpit:v1.21.8'):
        existing = subprocess.run(['docker', 'image', 'inspect', image], capture_output=True)
        if existing.returncode:
            if not allow_network:
                raise RuntimeError('Required local image is missing: ' + image + '; use --allow-network to acquire it')
            private_command(['docker', 'pull', image], private, timeout=600)
    env = os.environ.copy()
    env['GOTOOLCHAIN'] = 'local'
    env['GOPROXY'] = env.get('GOPROXY', 'https://goproxy.cn,direct') if allow_network else 'off'
    with private.open('a') as output:
        result = subprocess.run(['go', 'mod', 'download'], cwd=LINUX / 'repo/services/api', env=env,
                                stdout=output, stderr=subprocess.STDOUT, timeout=900)
    if result.returncode:
        raise RuntimeError('Go modules are unavailable; inspect the owned private dependency log')


def systemd_start(unit, command, logfile):
    status = subprocess.run(['systemctl', '--user', 'is-active', unit], capture_output=True, text=True)
    if status.stdout.strip() == 'active':
        raise RuntimeError('Preserve an existing active service; no duplicate launch')
    subprocess.run(['systemctl', '--user', 'reset-failed', unit], capture_output=True)
    result = subprocess.run(['systemd-run', '--user', '--unit=' + unit, '--property=Type=exec',
        '--property=Restart=no', '--property=StandardOutput=append:' + str(logfile),
        '--property=StandardError=append:' + str(logfile), *command], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Fresh owned service launch failed')


def start_services(manifest, allow_network):
    if (LINUX / 'services').exists():
        raise RuntimeError('Preserve existing services and their private material; inspect before retrying')
    ensure_prerequisites(allow_network)
    unit = 'hnuhole-b3b4-fresh-20261012-services'
    systemd_start(unit, ['/bin/bash', str(LINUX / 'start-fresh-services.sh')], LINUX / 'services.private.log')
    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        if (LINUX / 'device-config.json').exists():
            break
        status = subprocess.run(['systemctl', '--user', 'is-active', unit], capture_output=True, text=True)
        if status.stdout.strip() not in ('active', 'activating'):
            raise RuntimeError('Fresh service bootstrap ended before readiness; private resources retained')
        time.sleep(1)
    else:
        raise RuntimeError('Fresh service bootstrap readiness timeout; no duplicate retry')
    proxy_unit = 'hnuhole-b3b4-fresh-20261012-proxy'
    systemd_start(proxy_unit, ['/usr/bin/python3', str(LINUX / 'repo' / PROXY)], LINUX / 'proxy.private.log')
    deadline = time.monotonic() + 30
    while not (LINUX / 'b3b4-device-config.json').exists() and time.monotonic() < deadline:
        time.sleep(.2)
    config = json.loads((LINUX / 'b3b4-device-config.json').read_text())
    config['AUTH_B3B4_PACKAGE'] = PACKAGE
    write_json(LINUX / 'b3b4-device-config.json', config)
    write_json(HOST / 'b3b4-device-config.json', config)
    write_json(HOST / 'b3b4-acceptance-config.json', config)
    missing = dict(config, AUTH_B3B4_PACKAGE=MISSING_PACKAGE)
    write_json(HOST / 'b3b4-unassociated-config.json', missing)
    material = LINUX / 'services/material'
    service = json.loads((material / 'c.json').read_text())
    policy = service.get('webAuthn', {})
    if (policy.get('rpId') != 'zewbby.github.io' or policy.get('origins') != ['https://zewbby.github.io']
            or policy.get('androidOrigins') != [origin(CERT)]):
        raise RuntimeError('Fresh C service does not have the exact approved RP/signing policy')
    verifier = json.loads((material / 'v.json').read_text())
    if verifier.get('webAuthn') is not None:
        raise RuntimeError('V must remain independent from the C WebAuthn signing policy')
    # Public manifest records policy and service readiness without passwords or
    # evidence/operator key material. C and V keep independent generated keys.
    manifest.update(servicesStarted=True, servicesReady=True, serviceUnit=unit, proxyUnit=proxy_unit,
        freshDatabases=True, externallySuppliedDatabaseUrl=False,
        independentCommunityVerifierMaterial=True, passkeyPolicyConfigured=True,
        privateServiceMaterialExported=False)
    write_json(LINUX / 'source-manifest.json', manifest)
    write_json(HOST / 'source-manifest.json', manifest)
    print('READY: fresh C/V, owned disposable SQL, Mailpit and B3/B4 proxy; Android actions NOT_RUN')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=REPO)
    parser.add_argument('--execute', action='store_true', help='Start new disposable services after source preparation')
    parser.add_argument('--allow-network', action='store_true', help='Acquire required standard images and locked Go modules')
    parser.add_argument('--start-prepared', action='store_true', help='Start a previously prepared exact mirror; never overwrite it')
    parser.add_argument('--repair-partial', action='store_true', help='Remove only verified partial source mirrors before preparing again')
    parser.add_argument('--resume-partial', action='store_true', help='Continue byte-verified incomplete mirrors without deleting them')
    parser.add_argument('--repair-failed-bootstrap', action='store_true', help='Repair only the exact fresh PostgreSQL init-script permissions failure')
    args = parser.parse_args()
    if not __debug__:
        raise RuntimeError('Optimized execution cannot bypass preparation guards')
    if os.name != 'posix' or args.repo.resolve() != REPO or args.repo.is_symlink():
        raise RuntimeError('Run only in the dedicated Linux environment against the exact current repository')
    if args.allow_network and not args.execute:
        raise RuntimeError('Network acquisition requires --execute')
    if args.repair_failed_bootstrap:
        if args.start_prepared or args.resume_partial or args.repair_partial or args.execute or args.allow_network:
            raise RuntimeError('Failed-bootstrap repair must be a separate explicit invocation')
        repair_failed_bootstrap()
        return
    if args.repair_partial:
        if args.start_prepared or args.resume_partial or args.execute or args.allow_network:
            raise RuntimeError('Partial-source repair must be a separate explicit invocation')
        repair_partial(args.repo)
        return
    if args.start_prepared:
        if args.resume_partial:
            raise RuntimeError('Completed and partial source continuation cannot be combined')
        owned_directory(LINUX, 'HNUHOLE_ANDROID_LIVE_DEV_V1')
        owned_directory(HOST, 'HNUHOLE_ANDROID_MATRIX_V1')
        manifest = json.loads((LINUX / 'source-manifest.json').read_text())
        if manifest['owner'] != TOKEN or manifest['approvedCertificateSha256'] != CERT:
            raise RuntimeError('Exact prepared owner and signing identity required')
        for name, sha in manifest['stagedFilesSha256'].items():
            if digest((LINUX / 'repo' / name).read_bytes()) != sha:
                raise RuntimeError('Prepared source changed; review before starting services')
    else:
        manifest = prepare(args.repo, resume_partial=args.resume_partial)
    if args.execute:
        start_services(manifest, args.allow_network)
    else:
        print('PREPARED: isolated source mirror and build inputs; services and Android actions NOT_RUN')


if __name__ == '__main__':
    main()
