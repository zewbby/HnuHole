#!/bin/sh
# Only disposable PostgreSQL clusters and Redis children started by test fixtures.
set -eu
umask 077
snapshot_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COMMENT_SNAPSHOT_REDIS_SERVER=${COMMENT_SNAPSHOT_REDIS_SERVER:-$(command -v redis-server)}
test -x "$COMMENT_SNAPSHOT_REDIS_SERVER" || { echo 'Redis 7 binary required' >&2; exit 1; }
export COMMENT_SNAPSHOT_REDIS_SERVER
POST_MEDIA_PYTHON=${POST_MEDIA_PYTHON:-$(command -v python3)}
"$POST_MEDIA_PYTHON" -c 'import PIL; assert PIL.__version__ == "12.3.0"'
snapshot_fixture_dir=$(mktemp -d /tmp/hnuhole-snapshot-media.XXXXXX)
trap 'rm -rf "$snapshot_fixture_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
POST_MEDIA_VALIDATOR="$snapshot_fixture_dir/validate_image.py"
POST_MEDIA_FIXTURES="$snapshot_fixture_dir/media"
cp "$snapshot_script_dir/../media/validate_image.py" "$POST_MEDIA_VALIDATOR"
chmod 600 "$POST_MEDIA_VALIDATOR"
"$POST_MEDIA_PYTHON" "$snapshot_script_dir/../media/test_validator.py" --fixtures "$POST_MEDIA_FIXTURES"
export POST_MEDIA_PYTHON POST_MEDIA_VALIDATOR POST_MEDIA_FIXTURES
cd "$snapshot_script_dir/.."
go test -race -count=1 ./internal/commentsnapshot ./cmd/commentsnapshotctl -v
COMMENT_TEST_PATTERN='^(TestCommentSnapshot|TestCommentText|TestCommentBusiness)'
export COMMENT_TEST_PATTERN
sh "$snapshot_script_dir/run-comment-text-isolated.sh"
