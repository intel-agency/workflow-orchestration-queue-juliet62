#!/usr/bin/env bash
set -euo pipefail
export GH_PAGER=cat

# Trigger the orchestrator-agent workflow by creating a dispatch issue.
# Usage: ./scripts/trigger-orchestrator-test.sh [repo]

REPO="${1:-intel-agency/workflow-orchestration-queue-uniform39}"

TITLE="orchestrate-dynamic-workflow"
BODY='/orchestrate-dynamic-workflow
$workflow_name = create-epic-v2 { $phase = "1", $line_item = "1.1" }'

echo "Creating dispatch issue on ${REPO}..."
echo "  Title: ${TITLE}"
echo "  Body:  ${BODY}"
echo ""

ISSUE_URL=$(gh issue create \
  --repo "$REPO" \
  --title "$TITLE" \
  --body "$BODY")

echo "Issue created: ${ISSUE_URL}"
echo ""
echo "Waiting for orchestrator-agent workflow to start..."
sleep 5

gh run list \
  --repo "$REPO" \
  --workflow=orchestrator-agent.yml \
  --limit 1 \
  --json status,conclusion,headBranch,displayTitle,databaseId,url
