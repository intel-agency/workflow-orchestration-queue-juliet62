#!/usr/bin/env bash
set -euo pipefail

event_name="${EVENT_NAME:-}"
ref_name="${REF_NAME:-}"
run_number="${RUN_NUMBER:-}"
workflow_run_head_branch="${WORKFLOW_RUN_HEAD_BRANCH:-}"
workflow_run_run_number="${WORKFLOW_RUN_RUN_NUMBER:-}"
version_prefix="${VERSION_PREFIX:-0.0}"

if [[ -z "$event_name" ]]; then
  echo "ERROR: EVENT_NAME is required" >&2
  exit 1
fi

if [[ "$event_name" == "workflow_run" ]]; then
  branch_name="$workflow_run_head_branch"
  effective_run_number="$workflow_run_run_number"
else
  branch_name="$ref_name"
  effective_run_number="$run_number"
fi

if [[ -z "$branch_name" ]]; then
  echo "ERROR: unable to determine branch name for event '$event_name'" >&2
  exit 1
fi

if [[ -z "$effective_run_number" ]]; then
  echo "ERROR: unable to determine run number for event '$event_name'" >&2
  exit 1
fi

latest_tag="${branch_name}-latest"
version_image_tag="${version_prefix}.${effective_run_number}"
versioned_tag="${branch_name}-${version_image_tag}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "branch_name=$branch_name"
    echo "run_number=$effective_run_number"
    echo "latest_tag=$latest_tag"
    echo "version_image_tag=$version_image_tag"
    echo "versioned_tag=$versioned_tag"
  } >> "$GITHUB_OUTPUT"
else
  cat <<EOF
branch_name=$branch_name
run_number=$effective_run_number
latest_tag=$latest_tag
version_image_tag=$version_image_tag
versioned_tag=$versioned_tag
EOF
fi