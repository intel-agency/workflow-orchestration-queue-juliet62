---
description: Assigns agent the orchestrate-dynamic-workflow assignment with provided inputs
---

You have been assigned the `orchestrate-dynamic-workflow` assignment with input variables: $workflow_name, $context.

## Input

1. $ARGUMENTS: Pass the workflow_name as the first argument.

>Example: /orchestrate-dynamic-workflow my-workflow-name

## Instructions

- Your custom instructions are located in the files inside of the [nam20485/agent-instructions](https://github.com/nam20485/agent-instructions) repository
- Look at the files in the `main` branch
- Start with your core instructions (linked below)
- Then follow the links to the other instruction files in that repo as required or needed.
- You will need to follow the links and read the files to understand your instructions
- Some files are **REQUIRED** and some are **OPTIONAL**
- Files marked **REQUIRED** are ALWAYS active and so must be followed and read
- Otherwise files are optionally active based on user needs and your assigned roles and workflow assignments

## Core Instructions (**REQUIRED**)
[ai-core-instructions.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-core-instructions.md)

## Workflow Assignment Specific Instructions (**REQUIRED**)
[orchestrate-dynamic-workflow.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-workflow-assignments/orchestrate-dynamic-workflow.md)

[ai-workflow-assignments.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-workflow-assignments.md)

## Workflow Assignment ##

Perform the `orchestrate-dynamic-workflow` assignment with $workflow_name variable provided as input.

<!--
copilot-source:
  file: orchestrate-dynamic-workflow.prompt.md
  mode: agent
  description: "Assigns agent the orchestrate-dynamic-workflow assignment with provided inputs: $workflow_name and $context"
  tools:
    - githubRepo
    - testFailure
    - think
    - search
    - usages
    - vscodeAPI
    - problems
    - changes
    - fetch
    - extensions
    - runTests
    - add_comment_to_pending_review
    - add_issue_comment
    - add_sub_issue
    - create_and_submit_pull_request_review
    - create_branch
    - create_gist
    - create_issue
    - create_or_update_file
    - create_pending_pull_request_review
    - create_pull_request
    - delete_file
    - delete_pending_pull_request_review
    - download_workflow_run_artifact
    - fork_repository
    - get_code_scanning_alert
    - get_commit
    - get_file_contents
    - get_issue
    - get_issue_comments
    - get_job_logs
    - get_latest_release
    - get_me
    - get_notification_details
    - get_pull_request
    - get_pull_request_comments
    - get_pull_request_diff
    - get_pull_request_files
    - get_pull_request_reviews
    - get_pull_request_status
    - get_release_by_tag
    - get_tag
    - get_teams
    - get_workflow_run
    - get_workflow_run_logs
    - get_workflow_run_usage
    - list_branches
    - list_code_scanning_alerts
    - list_commits
    - list_dependabot_alerts
    - list_discussion_categories
    - list_discussions
    - list_gists
    - list_global_security_advisories
    - list_issue_types
    - list_issues
    - list_notifications
    - list_pull_requests
    - list_releases
    - list_repository_security_advisories
    - list_secret_scanning_alerts
    - list_sub_issues
    - list_tags
    - list_workflow_jobs
    - list_workflow_run_artifacts
    - list_workflow_runs
    - list_workflows
    - manage_notification_subscription
    - manage_repository_notification_subscription
    - mark_all_notifications_read
    - merge_pull_request
    - push_files
    - remove_sub_issue
    - reprioritize_sub_issue
    - request_copilot_review
    - rerun_failed_jobs
    - rerun_workflow_run
    - run_workflow
    - search_code
    - search_issues
    - search_orgs
    - search_pull_requests
    - search_repositories
    - search_users
    - submit_pending_pull_request_review
    - update_issue
    - update_pull_request
    - update_pull_request_branch
    - edit
    - runCommands
    - sequential-thinking
    - memory
    - filesystem
  notes: >
    Source used '${input:workflow_name}' Copilot input variable syntax. Translated
    to use $ARGUMENTS placeholder for OpenCode.
-->
