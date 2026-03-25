---
description: Create custom repository instructions for the current repository
model: openai/gpt-5
---

## Overview

1. Read `ai_instruction_modules/ai-creating-repository-custom-instructions.md`
2. Analyze current repo
3. Generate current repo-specific custom instructions based on `ai-creating-repository-custom-instructions.md` and analyzed information
4. Write to file

## Detailed Steps

- Place the current repository's URL into a variable hereafter referred to as `${var:__current_repo_url}`
- Add the generated custom repository instructions to a file called 'ai-repo-summary.md` located at the root of the current repository
- Instructions for creating the custom repository instructions can be found in a file called `ai-creating-repository-custom-instructions.md`
- `ai-creating-repository-custom-instructions.md` file can be found in a directory called `ai_instruction_modules` which is located at the root of the current repository
- If custom repository instructions file already exists for this current repository, list a link the existing file, ask the user if they want to re-create
  - If they want to re-create:
    - When finished generating but before writing to the existing file, confirm that the user wants over-write the file
    - When overwriting, create a backup of the existing file by copying it a new file with `.bak (*current date/time stamp)` appended to end
- Record completion status back to user.

## Runtime Flow (pseudo)
1. Detect path: ./ai-repo-summary.md
2. If exists:
   a. Output notice with link (${var:__current_repo_url}/blob/HEAD/ai-repo-summary.md)
   b. Ask: "Regenerate? (yes/no)"
   c. If no -> stop.
   d. If yes -> generate new content (do not write yet), show diff summary (line counts).
   e. Ask: "Overwrite? (yes/no)"
   f. If yes -> backup original to ai-repo-summary.md.bak-YYYYMMDD-HHMMSS; then write.
3. If not exists: generate then write.
4. Report success + backup path if created.

## Backup Filename Pattern
ai-repo-summary.md.bak-<UTC-YYYYMMDD-HHMMSS>

## Notes
- Never lose original without .bak creation when overwriting.
- Keep variable ${var:__current_repo_url} instead of hardcoding duplicates.

<!--
copilot-source:
  file: create-repo-custom-instructions.prompt.md
  mode: agent
  model: GPT-5 (Preview)
  descrition: Create custom repository instructions for the current repository
  tools:
    - codebase
    - usages
    - problems
    - changes
    - testFailure
    - terminalSelection
    - terminalLastCommand
    - openSimpleBrowser
    - fetch
    - findTestFiles
    - searchResults
    - githubRepo
    - extensions
    - editFiles
    - runNotebooks
    - search
    - new
    - runCommands
    - runTasks
    - sequential-thinking
    - memory
    - add_comment_to_pending_review
    - add_issue_comment
    - add_sub_issue
    - assign_copilot_to_issue
    - cancel_workflow_run
    - create_and_submit_pull_request_review
    - create_branch
    - create_issue
    - create_or_update_file
    - create_pending_pull_request_review
    - create_pull_request
    - create_pull_request_with_copilot
    - create_repository
    - delete_file
    - delete_pending_pull_request_review
    - delete_workflow_run_logs
    - dismiss_notification
    - download_workflow_run_artifact
    - fork_repository
    - get_code_scanning_alert
    - get_commit
    - get_dependabot_alert
    - get_discussion
    - get_discussion_comments
    - get_file_contents
    - get_issue
    - get_issue_comments
    - get_job_logs
    - get_me
    - get_notification_details
    - get_pull_request
    - get_pull_request_comments
    - get_pull_request_diff
    - get_pull_request_files
    - get_pull_request_reviews
    - get_pull_request_status
    - get_secret_scanning_alert
    - get_tag
    - get_workflow_run
    - get_workflow_run_logs
    - get_workflow_run_usage
    - list_branches
    - list_code_scanning_alerts
    - list_commits
    - list_issues
    - list_notifications
    - list_pull_requests
    - list_secret_scanning_alerts
    - list_sub_issues
    - list_tags
    - list_workflow_jobs
    - list_workflow_run_artifacts
    - list_workflow_runs
    - list_workflows
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
    - filesystem
    - copilotCodingAgent
    - activePullRequest
  notes: >
    Source had a typo in frontmatter key 'descrition' (missing 'p'); preserved as-is.
    Source also had additional YAML separator '---' after first frontmatter block
    containing '${var:__current_repo_url}=https://github.com/nam20485/agent-instructions'
    which was treated as body content.
-->
