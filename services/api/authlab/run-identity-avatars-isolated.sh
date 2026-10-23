#!/bin/sh
# Fresh private-socket PG + real bounded image decoder; no external DSN.
set -eu
POST_MEDIA_TEST_PATTERN='^(TestIdentity|TestRealHTTPSIdentity)'
POST_MEDIA_PREPARE_AVATAR_UPGRADE=1
export POST_MEDIA_TEST_PATTERN POST_MEDIA_PREPARE_AVATAR_UPGRADE
exec sh "$(dirname "$0")/run-post-images-isolated.sh"
