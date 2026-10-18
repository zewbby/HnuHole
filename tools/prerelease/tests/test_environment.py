import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import urllib.parse
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location('environment', Path(__file__).parents[1] / 'environment.py')
environment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(environment)


class IsolatedEnvironmentTest(unittest.TestCase):
    def test_cleanup_does_not_treat_pg_status_error_as_stopped(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'new-root'
            lab = environment.Lab(root, Path('/source'))
            lab.state = dict(processes={}, pgPorts={'source': {'c': 15432, 'v': 15433}})
            for party in 'cv':
                (root / ('source-' + party) / 'data').mkdir(parents=True)
            lab.run = Mock(return_value=4)
            with self.assertRaisesRegex(RuntimeError, 'could not prove owned PostgreSQL stopped'):
                lab.stop()
            self.assertEqual(lab.run.call_count, 2)

    def test_migrator_dsn_works_with_libpq_percent_decoding(self):
        lab = environment.Lab(Path(tempfile.gettempdir()) / 'nonexistent-prerelease-unit-root', Path('/source'))
        lab.state = dict(target='source', tag='hnuhole_runtime_unit', pgPorts={'source': {'c': 15432}})
        raw = lab.dsn('c', 'migrator')
        # libpq URI parameters percent-decode, but do not form-decode '+'.
        params = {k: urllib.parse.unquote(v) for k, v in (part.split('=', 1) for part in raw.split('?', 1)[1].split('&'))}
        self.assertEqual(params['options'], '-c role=hnuhole_c_owner')
        self.assertNotIn('+', raw)

    @unittest.skipUnless(os.name == 'posix', 'Linux ownership boundary')
    def test_reject_shared_or_symlink_root_before_reading_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'shared'
            root.mkdir(mode=0o755)
            with self.assertRaises(RuntimeError):
                environment.Lab(root, Path('/source'))
            root.chmod(0o700)
            link = Path(directory) / 'link'
            link.symlink_to(root)
            with self.assertRaises(RuntimeError):
                environment.Lab(link, Path('/source'))


if __name__ == '__main__':
    unittest.main()
