#!/usr/bin/env bash
# assemble-orchestrator-prompt.sh
#
# Assembles the orchestrator agent prompt by injecting GitHub event data into
# the prompt template. Called from orchestrator-agent.yml "Assemble orchestrator
# prompt" step.
#
# Required environment variables (set by the workflow step env: block):
#   EVENT_JSON      — toJson(github.event) output
#   CUSTOM_PROMPT   — optional custom prompt from workflow_dispatch input
#
# Context variables injected by the workflow at call time via positional args:
#   $1  event_name
#   $2  event_action
#   $3  actor
#   $4  repository
#   $5  ref
#   $6  sha
#
# Outputs:
#   .assembled-orchestrator-prompt.md   — the assembled prompt file
#   ORCHESTRATOR_PROMPT_PATH            — written to $GITHUB_ENV

set -euo pipefail

ASSEMBLED_PROMPT=".assembled-orchestrator-prompt.md"
PROMPT_TEMPLATE=".github/workflows/prompts/orchestrator-agent-prompt.md"

EVENT_NAME="${1:-}"
EVENT_ACTION="${2:-}"
ACTOR="${3:-}"
REPOSITORY="${4:-}"
REF="${5:-}"
SHA="${6:-}"

# If a custom prompt was provided via workflow_dispatch, use it directly.
if [[ -n "${CUSTOM_PROMPT:-}" ]]; then
  echo "::notice::Using custom prompt from workflow_dispatch input"
  echo "${CUSTOM_PROMPT}" > "$ASSEMBLED_PROMPT"
  echo "ORCHESTRATOR_PROMPT_PATH=$ASSEMBLED_PROMPT" >> "$GITHUB_ENV"
  exit 0
fi

echo "::group::Event metadata"
echo "event_name=${EVENT_NAME}"
echo "event.action=${EVENT_ACTION}"
echo "actor=${ACTOR}"
echo "repository=${REPOSITORY}"
echo "ref=${REF}"
echo "sha=${SHA}"
echo "::endgroup::"

EVENT_BLOCK="          Event Name: ${EVENT_NAME}
          Action: ${EVENT_ACTION}
          Actor: ${ACTOR}
          Repository: ${REPOSITORY}
          Ref: ${REF}
          SHA: ${SHA}"

echo "::group::Template diagnostics"
echo "Template path: $PROMPT_TEMPLATE"
echo "Template exists: $(test -f "$PROMPT_TEMPLATE" && echo YES || echo NO)"
echo "Template size: $(wc -c < "$PROMPT_TEMPLATE") bytes, $(wc -l < "$PROMPT_TEMPLATE") lines"
echo "Injection point occurrences:"
grep -n '{{__EVENT_DATA__}}' "$PROMPT_TEMPLATE" || echo "  WARNING: no {{__EVENT_DATA__}} found in template!"
echo "::endgroup::"

# Replace {{__EVENT_DATA__}} injection point with structured context + full event JSON.
{
  sed '/{{__EVENT_DATA__}}/,$ d' "$PROMPT_TEMPLATE"
  echo "$EVENT_BLOCK"
  echo ""
  printf '```json\n'
  echo "$EVENT_JSON"
  printf '```\n'
} > "$ASSEMBLED_PROMPT"

echo "::group::Assembled prompt diagnostics"
echo "Output path: $ASSEMBLED_PROMPT"
echo "Output exists: $(test -f "$ASSEMBLED_PROMPT" && echo YES || echo NO)"
echo "Output size: $(wc -c < "$ASSEMBLED_PROMPT") bytes, $(wc -l < "$ASSEMBLED_PROMPT") lines"
echo "--- First 20 lines ---"
head -20 "$ASSEMBLED_PROMPT"
echo "--- Last 30 lines ---"
tail -30 "$ASSEMBLED_PROMPT"
echo "--- Key sections present ---"
echo "  Instructions:      $(grep -c '## Instructions'           "$ASSEMBLED_PROMPT" || echo 0)"
echo "  Branching Logic:   $(grep -c 'EVENT_DATA Branching Logic' "$ASSEMBLED_PROMPT" || echo 0)"
echo "  Match Clauses:     $(grep -c '## Match Clause Cases'      "$ASSEMBLED_PROMPT" || echo 0)"
echo "  Helper Functions:  $(grep -c '## Helper Functions'        "$ASSEMBLED_PROMPT" || echo 0)"
echo "  Final section:     $(grep -c '## Final'                   "$ASSEMBLED_PROMPT" || echo 0)"
echo "  Event Name line:   $(grep -c 'Event Name:'               "$ASSEMBLED_PROMPT" || echo 0)"
printf '  JSON code block:   %s\n' "$(grep -c '^\`\`\`json' "$ASSEMBLED_PROMPT" || echo 0)"
echo "  Injection leftover:$(grep -c '{{__EVENT_DATA__}}'        "$ASSEMBLED_PROMPT" || echo 0)"
echo "::endgroup::"

echo "ORCHESTRATOR_PROMPT_PATH=$ASSEMBLED_PROMPT" >> "$GITHUB_ENV"
