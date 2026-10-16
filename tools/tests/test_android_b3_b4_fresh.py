"""Fresh continuation guards and source overlays, without services or a phone."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import copy
import json


REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fresh_b3b4', REPO / 'tools/prepare-android-b3-b4-fresh.py')
fresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fresh)


class FreshPreparationTest(unittest.TestCase):
    def test_failed_unit_gc_requires_retained_failure_and_rejects_unknown_loaded_unit(self):
        fresh.admit_failed_unit('not-found', 'inactive', '0', '', retained_failure=True)
        fresh.admit_failed_unit('loaded', 'failed', '0', str(fresh.LINUX / 'start-fresh-services.sh'))
        for args in (('not-found', 'inactive', '0', '', False),
                     ('not-found', 'active', '0', '', True),
                     ('not-found', 'inactive', '123', '', True),
                     ('loaded', 'inactive', '0', '/unknown/launcher.sh', True),
                     ('error', 'inactive', '0', '', True)):
            with self.assertRaises(ValueError):
                fresh.admit_failed_unit(*args)

    def docker_fixture(self):
        project = 'hnuhole-device-hnuholeandroidliveb3b420261012'
        containers = []
        for service in ('community-postgres', 'verifier-postgres', 'mailpit'):
            mounts = []
            if service != 'mailpit':
                party = 'community' if service == 'community-postgres' else 'verifier'
                mounts = [dict(Type='volume', Name=project + '_' + party + '-dev-data', Destination='/var/lib/postgresql/data'),
                          dict(Type='bind', Source=str(fresh.LINUX / 'repo/infra/postgres/init-auth.sh'),
                               Destination='/docker-entrypoint-initdb.d/10-auth.sh', RW=False)]
            containers.append(dict(Id=service, Config=dict(Image='axllent/mailpit:v1.21.8' if service == 'mailpit' else 'postgres:16.6-alpine',
                Labels={'com.docker.compose.project': project, 'com.docker.compose.service': service}), Mounts=mounts))
        volumes = [dict(Name=project + '_' + party + '-dev-data', Labels={'com.docker.compose.project': project})
                   for party in ('community', 'verifier')]
        networks = [dict(Name=project + '_default', Labels={'com.docker.compose.project': project}, Containers={})]
        return project, containers, volumes, networks

    def test_bootstrap_repair_admits_only_exact_owned_resource_topology(self):
        project, containers, volumes, networks = self.docker_fixture()
        fresh.failed_bootstrap_resources(project, containers, volumes, networks)
        bad = copy.deepcopy(containers)
        bad[0]['Config']['Labels']['com.docker.compose.project'] = 'unknown-project'
        with self.assertRaises(ValueError):
            fresh.failed_bootstrap_resources(project, bad, volumes, networks)
        bad = copy.deepcopy(volumes); bad[0]['Name'] = 'user-data'
        with self.assertRaises(ValueError):
            fresh.failed_bootstrap_resources(project, containers, bad, networks)
        bad = copy.deepcopy(networks); bad[0]['Containers'] = {'unknown-container': {}}
        with self.assertRaises(ValueError):
            fresh.failed_bootstrap_resources(project, containers, volumes, bad)
        bad = copy.deepcopy(containers); bad[0]['Mounts'][1]['RW'] = True
        with self.assertRaises(ValueError):
            fresh.failed_bootstrap_resources(project, bad, volumes, networks)

    def test_bootstrap_repair_refuses_started_environment_before_subprocesses(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            linux, host = root / 'linux', root / 'host'
            with patch.object(fresh, 'LINUX', linux), patch.object(fresh, 'HOST', host):
                fresh.owned_directory(linux, 'HNUHOLE_ANDROID_LIVE_DEV_V1')
                fresh.owned_directory(host, 'HNUHOLE_ANDROID_MATRIX_V1')
                (linux / 'source-manifest.json').write_text(json.dumps(dict(owner=fresh.TOKEN, servicesReady=True)))
                with patch('subprocess.run') as run:
                    with self.assertRaises(ValueError):
                        fresh.repair_failed_bootstrap()
                    run.assert_not_called()

    def test_public_postgres_init_is_readable_without_exposing_private_launchers(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(Path, 'chmod') as chmod:
                fresh.write_source_file(Path(directory), 'infra/postgres/init-auth.sh', b'public source', True)
                chmod.assert_called_once_with(0o755)

    def test_partial_helper_refresh_requires_an_exact_admitted_prior_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            repo, mirror = root / 'repo', root / 'mirror'
            repo.mkdir(); mirror.mkdir()
            name = 'owned-helper.py'
            (repo / name).write_bytes(b'current reviewed helper')
            (mirror / name).write_bytes(b'exact prior helper')
            admitted = {name: frozenset((fresh.digest(b'exact prior helper'),))}
            with patch.dict(fresh.PARTIAL_HELPER_VERSIONS, admitted, clear=True):
                self.assertEqual(fresh.verify_partial_tree(repo, mirror, {name}), 1)
                (mirror / name).write_bytes(b'any other prior helper')
                with self.assertRaises(ValueError):
                    fresh.verify_partial_tree(repo, mirror, {name})

    def test_drvfs_tree_copy_preserves_bytes_without_any_metadata_calls(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / 'source', root / 'target'
            (source / 'nested').mkdir(parents=True)
            data = b'\x89PNG\x00\xff\xfe'
            (source / 'nested/asset.png').write_bytes(data)
            with patch('shutil.copystat', side_effect=PermissionError('drvfs')) as copystat, \
                 patch.object(Path, 'chmod', side_effect=PermissionError('drvfs')) as chmod:
                fresh.copy_source_tree(source, target)
                self.assertEqual((target / 'nested/asset.png').read_bytes(), data)
                copystat.assert_not_called()
                chmod.assert_not_called()

    def test_partial_mirror_rejects_unknown_or_changed_product_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            repo, mirror = root / 'repo', root / 'mirror'
            repo.mkdir(); mirror.mkdir()
            (repo / 'source.dart').write_text('reviewed source')
            (mirror / 'source.dart').write_text('reviewed source')
            self.assertEqual(fresh.verify_partial_tree(repo, mirror, {'source.dart'}), 1)
            (mirror / 'source.dart').write_text('unknown replacement')
            with self.assertRaises(ValueError):
                fresh.verify_partial_tree(repo, mirror, {'source.dart'})
            (mirror / 'source.dart').write_text('reviewed source')
            (mirror / 'user-data.txt').write_text('preserve me')
            with self.assertRaises(ValueError):
                fresh.verify_partial_tree(repo, mirror, {'source.dart'})

    def test_windows_mirror_does_not_chmod_but_linux_failures_propagate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(Path, 'chmod', side_effect=PermissionError('unsupported')) as chmod:
                fresh.write_source_file(root, 'infra/postgres/init-auth.sh', b'#!/bin/sh\n', False)
                chmod.assert_not_called()
                with self.assertRaises(PermissionError):
                    fresh.write_source_file(root, 'tools/run-auth-device-services.sh', b'#!/bin/sh\n', True)
                chmod.assert_called_once_with(0o700)

    def test_binary_repository_asset_is_copied_without_decoding(self):
        asset = b'\x89PNG\r\n\x1a\n\x00\xff\xfe\x80'
        self.assertEqual(fresh.overlay('apps/mobile/assets/example.png', asset), asset)

    def test_signing_origin_uses_raw_digest_not_hex_text(self):
        self.assertEqual(fresh.origin(fresh.CERT),
                         'android:apk-key-hash:bx-o-Xp6aODhOgqVczEHOYOhmnk1PN1aVKqLCWpRqgM')
        with self.assertRaises(ValueError):
            fresh.origin('00')

    def test_all_reviewed_overlays_apply_and_compile(self):
        names = [fresh.FIXTURE, fresh.PROXY, 'tools/run-auth-device-services.sh',
                 'tools/control-android-b3-b4.py', 'tools/control-android-b3-b4-device.py',
                 'tools/run-android-live-device.ps1', 'tools/run-android-b3-b4.ps1']
        for name in names:
            original = (REPO / name).read_bytes()
            revised = fresh.overlay(name, original)
            self.assertNotEqual(original, revised, name)
            if name.endswith('.py'):
                compile(revised, name, 'exec')

    def test_runner_replaces_complete_linux_root_before_nested_account_run(self):
        revised = fresh.overlay('tools/run-android-live-device.ps1',
            (REPO / 'tools/run-android-live-device.ps1').read_bytes()).decode()
        controller = fresh.LINUX.as_posix() + '/repo/tools/control-android-b3-b4.py'
        self.assertEqual(revised.count(controller), 2)
        self.assertNotIn('/var/tmp/' + fresh.ACCOUNT_RUN, revised)
        self.assertIn("'" + fresh.ACCOUNT_RUN + "'", revised)

    def test_fixture_preserves_native_server_rejection_requirements(self):
        revised = fresh.overlay(fresh.FIXTURE, (REPO / fresh.FIXTURE).read_bytes()).decode()
        for required in ('actualNativeWrongRpAssociationRejected',
                         'actualServerWrongRpHashRejected422',
                         'actualProviderAssociationRejectedBeforeProofSubmission',
                         'approvedPackageAndCertificateActualBinding',
                         'originalResultQueriedWithoutProofReplay'):
            self.assertIn(required, revised)
        self.assertIn("defaultValue: '" + fresh.PACKAGE + "'", revised)
        self.assertNotIn(fresh.OLD_ACCOUNT_RUN, revised)

    def test_wrapper_cannot_resume_or_run_historical_closure(self):
        revised = fresh.overlay('tools/run-android-b3-b4.ps1',
                                (REPO / 'tools/run-android-b3-b4.ps1').read_bytes()).decode()
        self.assertIn("$Phase -notin @('ni-d01','ni-d02','ni-d03')", revised)
        self.assertIn('No historical closure state exists', revised)
        self.assertNotIn("$package+='.acceptance'", revised)
        self.assertIn('E:/Hnuhole-env/acceptance-20261012/matrix/repo', revised)
        self.assertIn("-EnvironmentRoot 'E:/Hnuhole-env'", revised)

    def test_unknown_existing_directory_is_never_adopted(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises((ValueError, FileNotFoundError)):
                fresh.owned_directory(Path(directory), 'HNUHOLE_ANDROID_LIVE_DEV_V1')

    def test_coordinate_replacement_fails_when_source_changed(self):
        with self.assertRaises(ValueError):
            fresh.replace_exact('unreviewed source', 'old coordinate', 'new coordinate')
        with self.assertRaises(ValueError):
            fresh.replace_exact('coordinate coordinate', 'coordinate', 'replacement', 1)


if __name__ == '__main__':
    unittest.main()
