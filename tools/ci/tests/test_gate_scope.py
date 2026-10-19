import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('gate_scope', Path(__file__).parents[1] / 'gate_scope.py')
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class GateScopeTests(unittest.TestCase):
    def test_gate_component_with_evidence_and_ci(self):
        self.assertTrue(scope.gate_only(scope.GATE_FILES | scope.CI_FILES | {
            'README.md', 'docs/design/gate-verification.json',
        }))

    def test_other_product_inputs_keep_android_and_rehearsal(self):
        for path in (
            'services/api/internal/authprivacy/community.go',
            'services/api/migrations/0018_comment_reports.sql',
            'services/api/go.mod', 'apps/mobile/lib/main.dart',
            'tools/prerelease/environment.py', 'infra/prerelease/config.json',
            '.github/workflows/moderation.yml', 'docs/unexpected.py',
        ):
            with self.subTest(path=path):
                self.assertFalse(scope.gate_only(scope.GATE_FILES | {path}))

    def test_docs_or_workflow_alone_do_not_exempt_candidate(self):
        for paths in ([], scope.CI_FILES, ['README.md'], ['docs/design/gate.md']):
            with self.subTest(paths=paths):
                self.assertFalse(scope.gate_only(paths))

    def test_renamed_or_deleted_non_gate_file_still_requires_candidate(self):
        self.assertFalse(scope.gate_only(scope.GATE_FILES | {
            'services/api/internal/authprivacy/new_gate.go',
        }))


if __name__ == '__main__':
    unittest.main()
