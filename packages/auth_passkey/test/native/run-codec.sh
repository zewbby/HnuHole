#!/bin/sh
set -eu
command -v swiftc >/dev/null 2>&1 || { echo 'Missing tool: swiftc' >&2; exit 1; }
PASSKEY_PACKAGE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PASSKEY_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-passkey-codec.XXXXXXXX")
trap 'rm -rf "$PASSKEY_TEMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
swiftc -module-cache-path "$PASSKEY_TEMP/module-cache" \
  "$PASSKEY_PACKAGE/ios/hnuhole_auth_passkey/Sources/hnuhole_auth_passkey/PasskeyCodec.swift" \
  "$PASSKEY_PACKAGE/ios/hnuhole_auth_passkey/Sources/hnuhole_auth_passkey/PendingOperation.swift" \
  "$PASSKEY_PACKAGE/test/native/PasskeyCodecTest.swift" \
  -o "$PASSKEY_TEMP/check"
"$PASSKEY_TEMP/check"
