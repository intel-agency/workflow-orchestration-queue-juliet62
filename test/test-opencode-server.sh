#!/usr/bin/env bash
set -euo pipefail

# Smoke test the guarded opencode server bootstrapper in the runtime devcontainer.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVCONTAINER_CONFIG="$REPO_ROOT/.devcontainer/devcontainer.json"

echo "=== Opencode Server Smoke Test ==="
echo ""

for cmd in docker devcontainer; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required but not found."
    exit 1
  fi
done

echo "--- Step 1: Starting runtime devcontainer ---"
devcontainer up --workspace-folder "$REPO_ROOT" --config "$DEVCONTAINER_CONFIG"
echo ""

echo "--- Step 2: Verifying opencode serve bootstrapper ---"
devcontainer exec \
  --workspace-folder "$REPO_ROOT" \
  --config "$DEVCONTAINER_CONFIG" \
  bash -lc '
    set -euo pipefail
    ./scripts/start-opencode-server.sh
    ./scripts/start-opencode-server.sh
    curl -sS -o /dev/null --connect-timeout 2 http://127.0.0.1:4096/
    test -s /tmp/opencode-serve.pid
    test -s /tmp/opencode-serve.log
  '

echo ""
echo "=== Opencode server smoke test passed ==="