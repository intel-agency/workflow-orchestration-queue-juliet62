#!/usr/bin/env bash
set -euo pipefail

# Local diagnostic harness for opencode runtime behavior in the runtime devcontainer path.
# It runs a matrix over credentials, agent casing, and prompt transport mode with hard timeouts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEVCONTAINER_CONFIG="$REPO_ROOT/.devcontainer/devcontainer.json"
PROMPT_TEMPLATE="$REPO_ROOT/.github/workflows/prompts/orchestrator-agent-prompt.md"
FIXTURE_FILE="$REPO_ROOT/test/fixtures/issues-opened.json"
LOCAL_PROMPT_FILE="$REPO_ROOT/.tmp-opencode-validation-prompt.md"
CONTAINER_PROMPT_FILE="/workspaces/ai-new-workflow-app-template/.tmp-opencode-validation-prompt.md"

RUN_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="/tmp/opencode-run-${RUN_STAMP}"
REPORT_FILE="$LOG_DIR/report.txt"
mkdir -p "$LOG_DIR"

PASS=0
FAIL=0
SKIP=0
RUN_PROMPT_FLAG_SUPPORTED="unknown"

cleanup() {
  rm -f "$LOCAL_PROMPT_FILE"
}
trap cleanup EXIT

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd"
    exit 1
  fi
}

extract_first_log_ts() {
  local file="$1"
  grep -m1 -E '^(INFO|DEBUG|WARN|ERROR)[[:space:]]+20[0-9]{2}-' "$file" | awk '{print $2}' || true
}

extract_error_ts() {
  local file="$1"
  grep -m1 -E '^(INFO|DEBUG|WARN|ERROR)[[:space:]]+20[0-9]{2}-.*(Error:|ERROR )' "$file" | awk '{print $2}' || true
}

extract_validation_ts() {
  local file="$1"
  awk '
    /^(INFO|DEBUG|WARN|ERROR)[[:space:]]+20[0-9]{2}-/ { ts=$2 }
    /^VALIDATION_OK$/ { print ts; exit }
  ' "$file"
}

record_result() {
  local status="$1"
  local message="$2"
  echo "[$status] $message" | tee -a "$REPORT_FILE"
  if [[ "$status" == "PASS" ]]; then
    PASS=$((PASS + 1))
  elif [[ "$status" == "FAIL" ]]; then
    FAIL=$((FAIL + 1))
  else
    SKIP=$((SKIP + 1))
  fi
}

assemble_validation_prompt() {
  local action actor repo event_block

  action="$(jq -r '.action' "$FIXTURE_FILE")"
  actor="$(jq -r '.sender.login' "$FIXTURE_FILE")"
  repo="$(jq -r '.repository.full_name' "$FIXTURE_FILE")"

  event_block="Event Name: issues
Action: ${action}
Actor: ${actor}
Repository: ${repo}
Ref: refs/heads/main
SHA: abc123def456"

  {
    sed '/__EVENT_DATA__/,$ d' "$PROMPT_TEMPLATE"
    echo "$event_block"
    echo ""
    echo '```json'
    cat "$FIXTURE_FILE"
    echo '```'
    echo ""
    echo "Validation instruction: Output exactly VALIDATION_OK and then exit."
  } > "$LOCAL_PROMPT_FILE"
}

run_case() {
  local case_name="$1"
  local credential_mode="$2"
  local agent_name="$3"
  local prompt_mode="$4"

  local case_log="$LOG_DIR/${case_name}.log"
  local start_ts first_output_ts first_terminal_ts
  local cmd rc has_validation has_auth_error has_mcp_timeout has_case_warning

  start_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [[ "$prompt_mode" == "flag" && "$RUN_PROMPT_FLAG_SUPPORTED" != "yes" ]]; then
    record_result "SKIP" "${case_name}: skipped (--prompt not supported by 'opencode run')"
    return
  fi

  cmd="timeout 120s opencode run --print-logs --log-level DEBUG --model zai-coding-plan/glm-5 --agent ${agent_name}"
  if [[ "$prompt_mode" == "flag" ]]; then
    cmd="${cmd} --prompt \"\$(cat ${CONTAINER_PROMPT_FILE})\""
  else
    cmd="${cmd} \"\$(cat ${CONTAINER_PROMPT_FILE})\""
  fi

  if [[ "$credential_mode" == "unset" ]]; then
    cmd="unset ZHIPU_API_KEY; ${cmd}"
  fi

  echo "=== CASE: ${case_name} ===" | tee -a "$REPORT_FILE"
  echo "start=${start_ts}" | tee -a "$REPORT_FILE"
  echo "command=${cmd}" | tee -a "$REPORT_FILE"

  set +e
  devcontainer exec \
    --workspace-folder "$REPO_ROOT" \
    --config "$DEVCONTAINER_CONFIG" \
    bash -lc "$cmd" 2>&1 | tee "$case_log"
  rc=${PIPESTATUS[0]}
  set -e

  first_output_ts="$(extract_first_log_ts "$case_log")"
  first_terminal_ts=""
  has_validation="no"
  has_auth_error="no"
  has_mcp_timeout="no"
  has_case_warning="no"

  grep -q '^VALIDATION_OK$' "$case_log" && has_validation="yes"
  grep -q 'Authentication parameter not received in Header' "$case_log" && has_auth_error="yes"
  grep -q 'local mcp startup failed' "$case_log" && has_mcp_timeout="yes"
  grep -q 'agent "Orchestrator" not found' "$case_log" && has_case_warning="yes"

  if [[ "$has_validation" == "yes" ]]; then
    first_terminal_ts="$(extract_validation_ts "$case_log")"
  fi
  if [[ -z "$first_terminal_ts" ]]; then
    first_terminal_ts="$(extract_error_ts "$case_log")"
  fi

  echo "exit_code=${rc}" | tee -a "$REPORT_FILE"
  echo "first_output_ts=${first_output_ts:-n/a}" | tee -a "$REPORT_FILE"
  echo "first_token_or_error_ts=${first_terminal_ts:-n/a}" | tee -a "$REPORT_FILE"
  echo "has_validation=${has_validation}" | tee -a "$REPORT_FILE"
  echo "has_auth_error=${has_auth_error}" | tee -a "$REPORT_FILE"
  echo "has_mcp_timeout=${has_mcp_timeout}" | tee -a "$REPORT_FILE"
  echo "has_agent_case_warning=${has_case_warning}" | tee -a "$REPORT_FILE"

  if [[ "$rc" -eq 124 ]]; then
    record_result "FAIL" "${case_name}: timed out at 120s"
    return
  fi

  if [[ -z "${first_output_ts}" ]]; then
    record_result "FAIL" "${case_name}: no output timestamp detected"
    return
  fi

  if [[ "$credential_mode" == "unset" ]]; then
    if [[ "$has_validation" == "yes" ]]; then
      record_result "FAIL" "${case_name}: produced VALIDATION_OK with ZHIPU_API_KEY unset"
      return
    fi
    if [[ "$has_auth_error" == "no" ]]; then
      record_result "FAIL" "${case_name}: expected auth error with ZHIPU_API_KEY unset"
      return
    fi
    record_result "PASS" "${case_name}: failed fast without key"
    return
  fi

  if [[ "$agent_name" == "orchestrator" && "$prompt_mode" == "flag" ]]; then
    if [[ "$has_validation" == "yes" ]]; then
      record_result "PASS" "${case_name}: canonical success"
    else
      record_result "FAIL" "${case_name}: canonical run did not emit VALIDATION_OK"
    fi
    return
  fi

  record_result "PASS" "${case_name}: diagnostic run completed"
}

echo "=== Opencode Runtime Diagnostic Matrix ==="
echo "Logs: $LOG_DIR"
echo "Report: $REPORT_FILE"
echo ""

require_cmd docker
require_cmd devcontainer
require_cmd jq

if [[ ! -f "$DEVCONTAINER_CONFIG" ]]; then
  echo "ERROR: missing devcontainer config: $DEVCONTAINER_CONFIG"
  exit 1
fi

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "ERROR: missing prompt template: $PROMPT_TEMPLATE"
  exit 1
fi

if [[ ! -f "$FIXTURE_FILE" ]]; then
  echo "ERROR: missing fixture: $FIXTURE_FILE"
  exit 1
fi

assemble_validation_prompt

echo "Bringing up runtime devcontainer..."
devcontainer up --workspace-folder "$REPO_ROOT" --config "$DEVCONTAINER_CONFIG" >/tmp/devcontainer-up-${RUN_STAMP}.log 2>&1
echo "Devcontainer is up."
echo ""

if devcontainer exec \
  --workspace-folder "$REPO_ROOT" \
  --config "$DEVCONTAINER_CONFIG" \
  bash -lc "opencode run --help | grep -q -- '--prompt'"; then
  RUN_PROMPT_FLAG_SUPPORTED="yes"
else
  RUN_PROMPT_FLAG_SUPPORTED="no"
fi
echo "opencode run --prompt support: ${RUN_PROMPT_FLAG_SUPPORTED}" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

for credential_mode in unset set; do
  if [[ "$credential_mode" == "set" && -z "${ZHIPU_API_KEY:-}" ]]; then
    record_result "SKIP" "set-credential matrix skipped (ZHIPU_API_KEY is not exported locally)"
    continue
  fi

  for agent_name in orchestrator Orchestrator; do
    for prompt_mode in positional flag; do
      case_name="${credential_mode}_${agent_name}_${prompt_mode}"
      run_case "$case_name" "$credential_mode" "$agent_name" "$prompt_mode"
      echo "" | tee -a "$REPORT_FILE"
    done
  done
done

echo "=== Summary ==="
echo "PASS=$PASS"
echo "FAIL=$FAIL"
echo "SKIP=$SKIP"
echo "Logs: $LOG_DIR"
echo "Report: $REPORT_FILE"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
