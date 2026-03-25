#!/usr/bin/env bash
set -euo pipefail

# Test prompt assembly: replicates the workflow's sed logic locally
# against each fixture in test/fixtures/ and validates the output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT_TEMPLATE="$REPO_ROOT/.github/workflows/prompts/orchestrator-agent-prompt.md"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

# Map fixture filenames to event metadata
declare -A EVENT_NAMES=(
  ["issues-opened.json"]="issues"
  ["issue-comment-created.json"]="issue_comment"
  ["issue-comment-on-pr.json"]="issue_comment"
  ["pr-opened.json"]="pull_request"
  ["pr-review-submitted.json"]="pull_request_review"
  ["pr-review-comment-created.json"]="pull_request_review_comment"
)

assemble_prompt() {
  local fixture_file="$1"
  local event_name="$2"
  local output_file="$3"

  local action
  action=$(jq -r '.action' "$fixture_file")
  local actor
  actor=$(jq -r '.sender.login' "$fixture_file")
  local repo
  repo=$(jq -r '.repository.full_name' "$fixture_file")

  EVENT_BLOCK="Event Name: $event_name
Action: $action
Actor: $actor
Repository: $repo
Ref: refs/heads/main
SHA: abc123def456"

  {
    sed '/{{__EVENT_DATA__}}/,$ d' "$PROMPT_TEMPLATE"
    echo "$EVENT_BLOCK"
    echo ""
    echo '```json'
    cat "$fixture_file"
    echo '```'
  } > "$output_file"
}

check_result() {
  local name="$1"
  local condition="$2"
  if eval "$condition"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Prompt Assembly Tests ==="
echo ""

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "ERROR: Prompt template not found at $PROMPT_TEMPLATE"
  exit 1
fi

if [[ ! -d "$FIXTURES_DIR" ]]; then
  echo "ERROR: Fixtures directory not found at $FIXTURES_DIR"
  exit 1
fi

for fixture in "$FIXTURES_DIR"/*.json; do
  basename="$(basename "$fixture")"
  event_name="${EVENT_NAMES[$basename]:-unknown}"
  output_file="/tmp/test-assembled-${basename%.json}.md"

  echo "Testing: $basename (event=$event_name)"

  # Assemble
  assemble_prompt "$fixture" "$event_name" "$output_file"

  # Check: {{__EVENT_DATA__}} injection point placeholder is gone
  check_result "no {{__EVENT_DATA__}} placeholder" \
    "! grep -q '{{__EVENT_DATA__}}' '$output_file'"

  # Check: structured event block is present
  check_result "event name present" \
    "grep -q 'Event Name: $event_name' '$output_file'"

  # Check: action field is present
  action=$(jq -r '.action' "$fixture")
  check_result "action present ($action)" \
    "grep -q 'Action: $action' '$output_file'"

  # Check: JSON block is present and valid
  check_result "json code block present" \
    "grep -q '^\`\`\`json' '$output_file'"

  # Extract JSON from the assembled prompt and validate with jq
  json_tmp="/tmp/test-extracted-${basename%.json}.json"
  sed -n '/^```json$/,/^```$/p' "$output_file" | sed '1d;$d' > "$json_tmp"
  check_result "json is valid" \
    "jq empty '$json_tmp' 2>/dev/null"
  rm -f "$json_tmp"

  # Check: branching logic section is present
  check_result "branching logic present" \
    "grep -q 'EVENT_DATA Branching Logic' '$output_file'"

  # Cleanup
  rm -f "$output_file"
  echo ""
done

echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
