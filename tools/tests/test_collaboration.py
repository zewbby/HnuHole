"""Exercise policy against real, disposable Git repositories; no project history changes."""

import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/check-collaboration.py"
SPEC = importlib.util.spec_from_file_location("policy", SCRIPT)
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)


class PolicyTests(unittest.TestCase):
    def test_subjects(self):
        for title in ("feat(image): 支持缩放", "fix!: change API", "docs: explain workflow",
                      "ci(policy): validate PRs", "revert(auth): revert session change"):
            with self.subTest(title=title):
                self.assertEqual([], policy.check_subject(title, "test"))
        for title in ("update", "feat: ", "fix(auth):missing space", "docs: x\nextra", "fix: x "):
            with self.subTest(title=title):
                self.assertTrue(policy.check_subject(title, "test"))

    def test_branches(self):
        for branch in ("feat/image-preview", "codex/chore/collaboration-rules", "fix/a1"):
            self.assertFalse(policy.check_branch(branch))
        for branch in ("main", "master", "codex/feature", "feat/Upper", "feat/a--b", "feat/a/b"):
            self.assertTrue(policy.check_branch(branch))

    def test_paths_and_legitimate_resources(self):
        for path in (".env", "a/.env.production", "a/node_modules/x.js", "x/build/a", "x/debug.apk",
                     "infra/.data/db", "a/.idea/workspace.xml", "key.properties", "id_ed25519"):
            self.assertTrue(policy.check_path(path), path)
        for path in (".env.example", "a/.env.example", "go.sum", "package-lock.json", "pubspec.lock",
                     "a/public.pem", "apps/mobile/android/build.gradle.kts", "docs/diagram.png"):
            self.assertFalse(policy.check_path(path), path)

    def test_credentials_are_detected_without_echoing_values(self):
        samples = [b"-----BEGIN " + b"RSA PRIVATE KEY-----", b"ghp_" + b"A" * 36,
                   b"github_pat_" + b"b" * 60, b"AKIA" + b"Z" * 16]
        for data in samples:
            errors = policy.check_blob("config.txt", data)
            self.assertTrue(errors)
            self.assertNotIn(data.decode(), " ".join(errors))
        self.assertFalse(policy.check_blob("public.pem", b"-----BEGIN CERTIFICATE-----"))

    def test_large_files(self):
        self.assertTrue(policy.check_blob("asset.bin", b"x" * (policy.MAX_BYTES + 1)))
        self.assertFalse(policy.check_blob("asset.bin", b"version https://git-lfs.github.com/spec/v1\n"))

    def test_push_checks_destination_even_from_feature_branch(self):
        for target in ("main", "master"):
            self.assertTrue(policy.check_push(io.StringIO(
                "refs/heads/feat/x abc refs/heads/" + target + " def\n")))
            self.assertTrue(policy.check_push(io.StringIO(
                "(delete) " + "0" * 40 + " refs/heads/" + target + " abc\n")))
        self.assertFalse(policy.check_push(io.StringIO("HEAD abc refs/heads/feat/x def\n")))
        self.assertFalse(policy.check_push(io.StringIO("refs/tags/v1 abc refs/tags/v1 def\n")))
        self.assertTrue(policy.check_push(io.StringIO("bad input\n")))


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hnuhole policy test ")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.env = os.environ.copy()
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
            self.env.pop(key, None)
        self.env.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                         "GIT_AUTHOR_NAME": "Policy Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
                         "GIT_COMMITTER_NAME": "Policy Test", "GIT_COMMITTER_EMAIL": "test@example.invalid"})
        self.git("init", "-b", "codex/test/policy")
        self.git("config", "core.autocrlf", "false")
        self.git("config", "commit.gpgsign", "false")
        self.write("README.md", "baseline\n")
        self.git("add", "README.md")
        # Deliberately non-conventional old history must not block new work.
        self.git("commit", "-m", "historical baseline")
        self.base = self.git("rev-parse", "HEAD").stdout.strip()

    def run_process(self, args, **kwargs):
        return subprocess.run(args, cwd=self.repo, env=self.env, text=True, encoding="utf-8",
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)

    def git(self, *args, ok=True):
        result = self.run_process(["git", *args])
        if ok:
            self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        return result

    def write(self, path, content):
        destination = self.repo / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content.encode("utf-8"))

    def check(self, *args):
        return self.run_process([sys.executable, str(SCRIPT), *args])

    def commit_file(self, path, text, title="feat: add sample"):
        self.write(path, text)
        self.git("add", "--", path)
        self.git("commit", "-m", title)

    def test_staged_reads_index_not_working_copy(self):
        self.write("config.txt", "ghp_" + "Z" * 36)
        self.git("add", "config.txt")
        self.write("config.txt", "safe working copy\n")
        result = self.check("--staged")
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn("Possible credential", result.stdout)
        self.assertNotIn("Z" * 36, result.stdout)

    def test_staged_protected_branch_and_deletion(self):
        self.git("switch", "-c", "main")
        self.assertEqual(1, self.check("--staged").returncode)
        self.git("switch", "codex/test/policy")
        self.git("rm", "README.md")
        self.assertEqual(0, self.check("--staged").returncode)

    def test_good_range_does_not_check_old_baseline(self):
        self.commit_file("new file.txt", "safe\n")
        self.assertEqual(0, self.check("--base", self.base).returncode)

    def test_bad_commit_is_rejected(self):
        self.commit_file("new.txt", "safe\n", "update")
        self.assertEqual(1, self.check("--base", self.base).returncode)

    def test_deleted_secret_is_still_rejected_in_history(self):
        self.commit_file("config.txt", "ghp_" + "Q" * 36)
        self.git("rm", "config.txt")
        self.git("commit", "-m", "fix: remove credential")
        self.assertEqual(1, self.check("--base", self.base).returncode)

    def test_missing_base_fails_closed(self):
        self.assertEqual(2, self.check("--base", "missing-ref").returncode)

    def test_pr_metadata_is_data_and_bad_title_fails(self):
        self.commit_file("new.txt", "safe\n")
        event = {"pull_request": {"base": {"sha": self.base},
                                  "head": {"sha": self.git("rev-parse", "HEAD").stdout.strip(),
                                           "ref": "codex/test/policy"},
                                  "title": "docs: $(touch SHOULD_NOT_EXIST)"}}
        self.write("event.json", json.dumps(event))
        self.assertEqual(0, self.check("--github-event", "event.json").returncode)
        self.assertFalse((self.repo / "SHOULD_NOT_EXIST").exists())
        event["pull_request"]["title"] = "update"
        self.write("event.json", json.dumps(event))
        self.assertEqual(1, self.check("--github-event", "event.json").returncode)

    def test_merge_resolution_content_is_checked(self):
        self.git("switch", "-c", "feat/other")
        self.commit_file("other.txt", "other\n")
        self.git("switch", "codex/test/policy")
        self.commit_file("ours.txt", "ours\n")
        self.git("merge", "--no-commit", "feat/other")
        self.write("merge-only.txt", "ghp_" + "M" * 36)
        self.git("add", "merge-only.txt")
        self.git("commit", "-m", "Merge branch 'feat/other'")
        self.assertEqual(1, self.check("--base", self.base).returncode)

    def test_clean_merge_may_use_git_generated_title(self):
        self.git("switch", "-c", "feat/other")
        self.commit_file("other.txt", "other\n")
        self.git("switch", "codex/test/policy")
        self.commit_file("ours.txt", "ours\n")
        self.git("merge", "--no-ff", "feat/other", "-m", "Merge branch 'feat/other'")
        result = self.check("--base", self.base)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_trailing_whitespace_is_rejected_without_echoing_content(self):
        self.commit_file("new.txt", "confidential detail  \n")
        result = self.check("--base", self.base)
        self.assertEqual(1, result.returncode)
        self.assertNotIn("confidential detail", result.stdout)

    def test_main_push_event_checks_new_commits(self):
        self.commit_file("new.txt", "safe\n")
        self.write("event.json", json.dumps({"ref": "refs/heads/main", "before": self.base,
                   "after": self.git("rev-parse", "HEAD").stdout.strip()}))
        self.assertEqual(0, self.check("--github-event", "event.json").returncode)
        self.write("event.json", "{}")
        self.assertEqual(1, self.check("--github-event", "event.json").returncode)

    def install_hooks(self):
        shutil.copytree(ROOT / ".githooks", self.repo / ".githooks")
        for hook in (self.repo / ".githooks").iterdir():
            hook.chmod(0o755)
        (self.repo / "tools").mkdir()
        shutil.copy2(SCRIPT, self.repo / "tools/check-collaboration.py")
        self.git("config", "core.hooksPath", ".githooks")

    def test_real_push_hook_checks_remote_destination(self):
        self.install_hooks()
        remote = self.repo / "remote.git"
        self.git("init", "--bare", str(remote))
        self.git("remote", "add", "test", str(remote))
        result = self.git("push", "test", "HEAD:refs/heads/main", ok=False)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Direct push", result.stdout + result.stderr)
        self.git("push", "test", "HEAD:refs/heads/test/policy")

    def test_real_commit_hooks_reject_bad_messages_and_artifacts(self):
        self.install_hooks()
        self.write("sample.txt", "safe\n")
        self.git("add", "sample.txt")
        bad = self.git("commit", "-m", "update", ok=False)
        self.assertNotEqual(0, bad.returncode)
        self.assertIn("Commit title", bad.stdout + bad.stderr)
        self.git("commit", "-m", "test: exercise hooks")
        self.write(".env", "EXAMPLE=sample\n")
        self.git("add", ".env")
        bad = self.git("commit", "-m", "test: reject local env", ok=False)
        self.assertNotEqual(0, bad.returncode)
        self.assertIn("Local environment", bad.stdout + bad.stderr)


if __name__ == "__main__":
    unittest.main()
