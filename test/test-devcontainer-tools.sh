#!/usr/bin/env bash
set -euo pipefail

# Smoke test: verify all expected tools are installed and respond to --version.
# Intended to run INSIDE the devcontainer.

PASS=0
FAIL=0

check_tool() {
  local name="$1"
  local cmd="$2"
  local expected="${3:-}"

  if output=$(eval "$cmd" 2>&1); then
    if [[ -n "$expected" && ! "$output" =~ $expected ]]; then
      echo "  FAIL: $name — unexpected version: $output (expected match: $expected)"
      FAIL=$((FAIL + 1))
    else
      echo "  PASS: $name — $output"
      PASS=$((PASS + 1))
    fi
  else
    echo "  FAIL: $name — command failed: $cmd"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Devcontainer Tool Smoke Tests ==="
echo ""

check_tool "dotnet"   "dotnet --version"        "10\\.0"
check_tool "node"     "node --version"           "v24\\."
check_tool "bun"      "bun --version"
check_tool "uv"       "uv --version"
check_tool "gh"       "gh --version"
check_tool "opencode" "opencode --version"
check_tool "git"      "git --version"
check_tool "jq"       "jq --version"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
