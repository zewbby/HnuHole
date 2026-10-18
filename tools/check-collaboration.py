#!/usr/bin/env python3
"""Small, dependency-free collaboration checks for Git hooks and CI."""

import argparse
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


TYPES = r"feat|fix|refactor|docs|test|chore|ci|build|perf|revert"
SUBJECT = re.compile(r"^(?:" + TYPES + r")(?:\([a-z0-9][a-z0-9._/-]*\))?!?: \S.*$")
BRANCH = re.compile(r"^(?:codex/)?(?:" + TYPES + r")/[a-z0-9]+(?:-[a-z0-9]+)*$")
MAX_BYTES = 10 * 1024 * 1024
BAD_DIRS = {"node_modules", "target", "dist", "build", ".dart_tool", ".pub-cache",
            "__pycache__", ".idea", ".vscode", ".worktrees", "logs"}
BAD_SUFFIXES = {".apk", ".aab", ".ipa", ".class", ".pyc", ".pyo", ".log", ".tmp",
                ".p12", ".pfx", ".jks", ".keystore"}
SECRET_PATTERNS = [
    re.compile(rb"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"),
    re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{22,255})\b"),
    re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
]


def git(*args):
    return subprocess.check_output(["git", *args], stderr=subprocess.PIPE)


def git_text(*args):
    return git(*args).decode("utf-8", errors="replace").strip()


def check_branch(branch):
    if not BRANCH.fullmatch(branch):
        return ["Use a task branch: [codex/]<type>/<lowercase-hyphenated-slug>."]
    return []


def check_subject(subject, label):
    if not SUBJECT.fullmatch(subject) or subject != subject.rstrip():
        return [label + ": expected type(scope)!: description (scope and ! optional)."]
    return []


def check_path(path):
    parts = PurePosixPath(path.lower()).parts
    name = parts[-1]
    if any(part in BAD_DIRS for part in parts[:-1]):
        return ["Generated/local file: " + repr(path)]
    if (name == ".env" or name.startswith(".env.")) and name != ".env.example":
        return ["Local environment file: " + repr(path)]
    if (PurePosixPath(name).suffix in BAD_SUFFIXES
            or name in {"application-local.yml", "application-local.yaml", "id_rsa",
                        "id_ed25519", "id_ecdsa", "local.properties", "key.properties"}
            or parts[:2] in {("infra", ".data"), ("infra", ".cache")}):
        return ["Sensitive/local artifact: " + repr(path)]
    return []


def check_blob(path, data):
    errors = []
    if len(data) > MAX_BYTES:
        errors.append("File exceeds 10 MiB; use Git LFS: " + repr(path))
    if any(pattern.search(data) for pattern in SECRET_PATTERNS):
        # Do not print matched values, diff lines or file contents.
        errors.append("Possible credential/private key: " + repr(path))
    return errors


def check_files(revision=None):
    if revision is None:
        raw = git("diff", "--cached", "--name-only", "--diff-filter=ACMRT", "-z")
    else:
        raw = git("diff-tree", "--root", "--no-commit-id", "-m", "--first-parent", "-r",
                  "--name-only", "--diff-filter=ACMRT", "-z", revision)
    errors = []
    for encoded in raw.split(b"\0"):
        if not encoded:
            continue
        path = encoded.decode("utf-8")
        errors.extend(check_path(path))
        spec = ":" + path if revision is None else revision + ":" + path
        # Gitlinks point to commits, not file blobs; do not inspect external repos.
        if git_text("cat-file", "-t", spec) != "blob":
            continue
        size = int(git_text("cat-file", "-s", spec))
        if size > MAX_BYTES:
            errors.append("File exceeds 10 MiB; use Git LFS: " + repr(path))
            continue
        errors.extend(check_blob(path, git("cat-file", "blob", spec)))
    return errors


def check_whitespace(*revisions):
    result = subprocess.run(["git", "diff", "--check", *revisions],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    # Git's diff --check prints source lines; keep potentially sensitive content out of logs.
    return ["Whitespace/conflict-marker errors; inspect git diff --check locally."] if result.returncode else []


def check_range(base, head):
    base_sha = git_text("rev-parse", "--verify", base + "^{commit}")
    head_sha = git_text("rev-parse", "--verify", head + "^{commit}")
    common = git_text("merge-base", base_sha, head_sha)
    errors = []
    for sha in git_text("rev-list", "--reverse", base_sha + ".." + head_sha).splitlines():
        parents = git_text("show", "-s", "--format=%P", sha).split()
        if len(parents) < 2:
            errors.extend(check_subject(git_text("show", "-s", "--format=%s", sha),
                                        "Commit " + sha[:12]))
        errors.extend("Commit " + sha[:12] + ": " + error for error in check_files(sha))
    errors.extend(check_whitespace(common, head_sha))
    return errors


def check_push(stream):
    errors = []
    for line in stream:
        fields = line.split()
        if len(fields) != 4:
            errors.append("Invalid pre-push input.")
            continue
        local_ref, local_sha, remote_ref, _ = fields
        if remote_ref in {"refs/heads/main", "refs/heads/master"}:
            errors.append("Direct push/deletion of main/master is forbidden; use a PR.")
        elif remote_ref.startswith("refs/heads/") and set(local_sha) != {"0"}:
            errors.extend(check_branch(remote_ref[len("refs/heads/"):]))
        # Tag pushes are outside the branch naming policy.
    return errors


def check_event(path):
    event = json.loads(Path(path).read_text(encoding="utf-8"))
    if "pull_request" in event:
        pr = event["pull_request"]
        errors = check_branch(pr["head"]["ref"])
        errors.extend(check_subject(pr["title"], "PR title"))
        errors.extend(check_range(pr["base"]["sha"], pr["head"]["sha"]))
        return errors
    if event.get("ref") == "refs/heads/main":
        if set(event["before"]) == {"0"}:
            return ["New main branch requires a reviewed baseline; no automatic history exemption."]
        return check_range(event["before"], event["after"])
    return ["Unsupported event; expected a pull_request or main push."]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--staged", action="store_true")
    mode.add_argument("--base")
    mode.add_argument("--commit-msg", type=Path)
    mode.add_argument("--pre-push", action="store_true")
    mode.add_argument("--github-event", type=Path)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--branch")
    parser.add_argument("--pr-title")
    args = parser.parse_args()
    try:
        if args.staged:
            errors = check_branch(git_text("branch", "--show-current"))
            errors.extend(check_files())
            errors.extend(check_whitespace("--cached"))
        elif args.commit_msg:
            message = args.commit_msg.read_text(encoding="utf-8-sig")
            # git merge uses a generated title; only exempt an actual merge in progress.
            merging = Path(git_text("rev-parse", "--git-path", "MERGE_HEAD")).exists()
            subject = message.splitlines()[0] if message.splitlines() else ""
            errors = [] if merging and subject.startswith("Merge ") else check_subject(subject, "Commit title")
        elif args.pre_push:
            errors = check_push(sys.stdin)
        elif args.github_event:
            errors = check_event(args.github_event)
        else:
            errors = check_range(args.base, args.head)
        if args.branch:
            errors.extend(check_branch(args.branch))
        if args.pr_title:
            errors.extend(check_subject(args.pr_title, "PR title"))
    except (subprocess.CalledProcessError, OSError, ValueError, KeyError) as error:
        # Avoid echoing external content/credentials from Git stderr or JSON.
        print("Collaboration check could not run (" + type(error).__name__ + ").", file=sys.stderr)
        return 2
    if errors:
        for error in dict.fromkeys(errors):
            print("ERROR: " + error)
        return 1
    print("Collaboration checks passed (policy only; not product acceptance).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
