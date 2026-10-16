#!/bin/sh
# macOS host regression for the shared Foundation/Darwin marker helper.
# This does not exercise iOS Keychain or prove device power-loss durability.
set -eu
command -v swiftc >/dev/null 2>&1 || { echo 'swiftc is required' >&2; exit 1; }
marker_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
marker_run_dir=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-marker-test.XXXXXX")
trap 'rm -rf "$marker_run_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
swiftc -module-cache-path "$marker_run_dir/modules" \
    "$marker_script_dir/../../ios/hnuhole_auth_vault/Sources/hnuhole_auth_vault/AuthInstallationMarker.swift" \
    "$marker_script_dir/installation_marker_test.swift" \
    -o "$marker_run_dir/tests"
"$marker_run_dir/tests"
