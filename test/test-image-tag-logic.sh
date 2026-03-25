#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TAG_SCRIPT="$REPO_ROOT/scripts/resolve-image-tags.sh"

run_case() {
  local case_name="$1"
  shift

  local output_file
  output_file="$(mktemp)"

  if "$@" GITHUB_OUTPUT="$output_file" bash "$TAG_SCRIPT"; then
    echo "PASS: $case_name"
  else
    echo "FAIL: $case_name"
    rm -f "$output_file"
    exit 1
  fi

  cat "$output_file"
  rm -f "$output_file"
}

echo "=== Image Tag Logic Tests ==="

push_output="$(run_case \
  'push event uses github.ref_name/github.run_number' \
  env \
    EVENT_NAME=push \
    REF_NAME=main \
    RUN_NUMBER=2 \
    VERSION_PREFIX=0.1)"

grep -q '^latest_tag=main-latest$' <<<"$push_output"
grep -q '^version_image_tag=0.1.2$' <<<"$push_output"
grep -q '^versioned_tag=main-0.1.2$' <<<"$push_output"

workflow_run_output="$(run_case \
  'workflow_run uses triggering workflow branch/run number' \
  env \
    EVENT_NAME=workflow_run \
    REF_NAME=ignored-ref \
    RUN_NUMBER=99 \
    WORKFLOW_RUN_HEAD_BRANCH=main \
    WORKFLOW_RUN_RUN_NUMBER=2 \
    VERSION_PREFIX=0.1)"

grep -q '^branch_name=main$' <<<"$workflow_run_output"
grep -q '^run_number=2$' <<<"$workflow_run_output"
grep -q '^latest_tag=main-latest$' <<<"$workflow_run_output"
grep -q '^version_image_tag=0.1.2$' <<<"$workflow_run_output"
grep -q '^versioned_tag=main-0.1.2$' <<<"$workflow_run_output"

workflow_dispatch_output="$(run_case \
  'workflow_dispatch uses github.ref_name/github.run_number' \
  env \
    EVENT_NAME=workflow_dispatch \
    REF_NAME=main \
    RUN_NUMBER=7 \
    VERSION_PREFIX=0.1.2)"

grep -q '^branch_name=main$' <<<"$workflow_dispatch_output"
grep -q '^run_number=7$' <<<"$workflow_dispatch_output"
grep -q '^latest_tag=main-latest$' <<<"$workflow_dispatch_output"
grep -q '^version_image_tag=0.1.2.7$' <<<"$workflow_dispatch_output"
grep -q '^versioned_tag=main-0.1.2.7$' <<<"$workflow_dispatch_output"

schedule_output="$(run_case \
  'schedule uses github.ref_name/github.run_number' \
  env \
    EVENT_NAME=schedule \
    REF_NAME=main \
    RUN_NUMBER=8 \
    VERSION_PREFIX=0.1.2)"

grep -q '^branch_name=main$' <<<"$schedule_output"
grep -q '^run_number=8$' <<<"$schedule_output"
grep -q '^latest_tag=main-latest$' <<<"$schedule_output"
grep -q '^version_image_tag=0.1.2.8$' <<<"$schedule_output"
grep -q '^versioned_tag=main-0.1.2.8$' <<<"$schedule_output"

echo "All image tag logic tests passed."