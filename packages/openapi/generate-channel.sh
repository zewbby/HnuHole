#!/bin/sh
set -eu

# Use an explicitly installed, pinned tool. Never download a tool on execution.
task_root=$(cd "$(dirname "$0")" && pwd)
task_codegen=${OAPI_CODEGEN:-oapi-codegen}
task_version=$("$task_codegen" --version)
case " $task_version " in
  *[[:space:]]v2.4.1[[:space:]]*) ;;
  *)
  printf '%s\n' 'Expected oapi-codegen v2.4.1; set OAPI_CODEGEN to that executable.' >&2
  exit 1
  ;;
esac
task_dir=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-channel-codegen.XXXXXX")
trap 'rm -rf "$task_dir"' EXIT
"$task_codegen" -generate types,chi-server -package channelapi \
  -o "$task_dir/channel-api.gen.go" "$task_root/channel-api.yaml"
task_output="$task_root/generated/channel-api.gen.go"
case "${1:-}" in
  '')
    mkdir -p "$task_root/generated"
    cp "$task_dir/channel-api.gen.go" "$task_output"
    ;;
  --check)
    if [ ! -f "$task_output" ]; then
      printf '%s\n' 'No local generated baseline; run packages/openapi/generate-channel.sh first.' >&2
      exit 1
    fi
    diff -u "$task_output" "$task_dir/channel-api.gen.go"
    ;;
  *)
    printf '%s\n' 'Usage: generate-channel.sh [--check]' >&2
    exit 2
    ;;
esac
