import ast
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('watcher_overlay_test', Path(__file__).parents[1] / 'operate-android-b3-b4-fresh.py')
OP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OP)


class WatcherOverlayGuards(unittest.TestCase):
    def assertion(self):
        tree = ast.parse((Path(__file__).parents[1] / OP.WATCHER_FILE.removeprefix('tools/')).read_text())
        assertions = [node for node in ast.walk(tree) if isinstance(node, ast.Assert)
                      and isinstance(node.msg, ast.Constant)
                      and node.msg.value == 'Local native timeout/cancel remains UNKNOWN; preserve provider task']
        self.assertEqual(len(assertions), 1)
        return compile(ast.fix_missing_locations(ast.Module(body=assertions, type_ignores=[])), '<native-unknown-guard>', 'exec')

    def test_actual_callback_remains_admissible_before_provider_cleanup(self):
        exec(self.assertion(), {'state': dict(nativeBegun=1, nativeErrored=1, nativeTimeout=0, nativeCancelled=0)})
        exec(self.assertion(), {'state': dict(nativeBegun=1, nativeSucceeded=1)})

    def test_local_unknown_cannot_be_dismissed_despite_equal_counters_or_late_callback(self):
        for state in (dict(nativeBegun=1, nativeErrored=1, nativeTimeout=1),
                      dict(nativeBegun=1, nativeCancelled=1),
                      dict(nativeBegun=1, nativeErrored=1, nativeTimeout=1, actualAssociationRejected=1, lateIgnored=1),
                      dict(nativeTimeout=True), dict(nativeCancelled=-1)):
            with self.subTest(state=state), self.assertRaisesRegex(AssertionError, 'UNKNOWN'):
                exec(self.assertion(), {'state': state})

    def fixture(self, root):
        original = b'# exact fixture original\n' + OP.WATCHER_ANCHOR + b'                ended=0\n'
        original_sha = OP.FRESH.digest(original)
        source = {'stagedFilesSha256': {OP.WATCHER_FILE: original_sha}}
        root.joinpath('source-manifest.json').write_text(json.dumps(source))
        manifest_sha = OP.BUILD.sha(root / 'source-manifest.json')
        return original, original_sha, source, manifest_sha

    def test_only_one_exact_insertion_preserves_original_backup_and_source_admission(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original, old_sha, source, manifest_sha = self.fixture(root)
            directory = root / 'b3b4-evidence'
            directory.mkdir()
            target = root / 'repo' / OP.WATCHER_FILE
            target.parent.mkdir(parents=True)
            with patch.object(OP, 'ROOT', root), patch.object(OP, 'WATCHER_ORIGINAL_SHA', old_sha), \
                    patch.object(OP, 'WATCHER_MANIFEST_SHA', manifest_sha):
                guarded = OP.guarded_watcher_bytes(original)
                self.assertEqual(guarded.replace(OP.WATCHER_INSERTION, b'', 1), original)
                target.write_bytes(guarded)
                (directory / OP.WATCHER_BACKUP).write_bytes(original)
                receipt = OP.watcher_overlay_record(original)
                (directory / OP.WATCHER_RECEIPT).write_text(json.dumps(receipt))
                result = OP.validate_host_watcher_overlay(source)
                self.assertEqual(result['guardedSourceSha256'], OP.FRESH.digest(guarded))
                self.assertEqual(OP.BUILD.sha(root / 'source-manifest.json'), manifest_sha)
                self.assertEqual(source['stagedFilesSha256'][OP.WATCHER_FILE], old_sha)
                target.write_bytes(guarded + b'# unreviewed mutation\n')
                with self.assertRaisesRegex(RuntimeError, 'single reviewed'):
                    OP.validate_host_watcher_overlay(source)
                target.write_bytes(guarded)
                (directory / OP.WATCHER_RECEIPT).write_text(json.dumps(dict(receipt, apkPayloadModified=True)))
                with self.assertRaisesRegex(RuntimeError, 'single reviewed'):
                    OP.validate_host_watcher_overlay(source)
                (directory / OP.WATCHER_RECEIPT).write_text(json.dumps(receipt))
                (directory / OP.WATCHER_BACKUP).write_bytes(original + b' ')
                with self.assertRaisesRegex(RuntimeError, 'Exact original watcher'):
                    OP.validate_host_watcher_overlay(source)

    def test_unknown_original_or_duplicate_insertion_point_is_refused(self):
        original = b'# original\n' + OP.WATCHER_ANCHOR * 2
        with patch.object(OP, 'WATCHER_ORIGINAL_SHA', OP.FRESH.digest(original)), \
                self.assertRaisesRegex(RuntimeError, 'single insertion'):
            OP.guarded_watcher_bytes(original)
        with self.assertRaisesRegex(RuntimeError, 'Exact original watcher'):
            OP.guarded_watcher_bytes(b'unknown original')


if __name__ == '__main__':
    unittest.main()
