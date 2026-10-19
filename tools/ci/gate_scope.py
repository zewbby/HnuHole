"""Select component CI for an exclusively Gate-focused pull request.

Everything outside this explicit allowlist keeps the existing Android build and
deployment rehearsal. Manual candidate requests always keep those jobs too.
"""
import argparse
from pathlib import PurePosixPath
import re
import subprocess


GATE_FILES = {
    'services/api/internal/authprivacy/authorization_gate.go',
    'services/api/internal/authprivacy/authorization_gate_cancellation_test.go',
}
CI_FILES = {
    'services/api/authlab/run-isolated.sh',
    '.github/workflows/android-prerelease.yml',
    '.github/workflows/authorization-gate.yml',
    'tools/ci/gate_scope.py',
    'tools/ci/tests/test_gate_scope.py',
}


def gate_only(paths):
    paths = set(paths)
    return bool(paths & GATE_FILES) and all(
        path in GATE_FILES | CI_FILES
        or path == 'README.md'
        or (PurePosixPath(path).parts[0] == 'docs' and path.endswith(('.md', '.json')))
        for path in paths
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('base')
    parser.add_argument('head')
    args = parser.parse_args()
    for commit in (args.base, args.head):
        if not re.fullmatch('[0-9a-f]{40}', commit):
            parser.error('expected full commit SHA')
    changed = subprocess.check_output([
        'git', 'diff', '--name-only', '--no-renames', '-z', args.base, args.head, '--',
    ]).decode('utf-8').split('\0')
    print('gate_only=' + str(gate_only(path for path in changed if path)).lower())


if __name__ == '__main__':
    main()
