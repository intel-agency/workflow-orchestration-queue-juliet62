---
description: Invokes the pr-review-comments assignment with model and PR number
---

## Arguments

### $pr

- The PR where you can find the review comments you will work on
- This can be a URL to an URL of the PR, or a number, in which case you will look for a PR with that number in the current repo.

### $model

The model to use for executing this prompt.

## Description

You have been assigned the `pr-review-comments` assignment. Review comments in the PR specified via $ARGUMENTS.

## Custom Instructions Context

Read, use, and adhere to the following instructions files.

[ai-quick-reference.md](../ai_instruction_modules/ai-quick-reference.md)
[ai-terminal-management.md](../ai_instruction_modules/ai-terminal-management.md)
[ai-workflow-config.md](../ai_instruction_modules/ai-workflow-config.md)
[ai-deployment-environment.md](../ai_instruction_modules/ai-deployment-environment.md)
[ai-local-environment.md](../ai_instruction_modules/ai-local-environment.md)
[ai-testing-validation.md](../ai_instruction_modules/ai-testing-validation.md)
[ai-tools-config.md](../ai_instruction_modules/ai-tools-config.md)
[ai-task-based-workflow.md](../ai_instruction_modules/ai-task-based-workflow.md)
[ai-workflow-roles.md](../ai_instruction_modules/ai-workflow-roles.md)
[ai-workflow-assignments.md](../ai_instruction_modules/ai-workflow-assignments.md)
[ai-application-guidelines.md](../ai_instruction_modules/ai-application-guidelines.md)
[ai-new-app-template.md](../ai_instruction_modules/ai-new-app-template.md)
[ai-design-principles.md](../ai_instruction_modules/ai-design-principles.md)
[ai-instructions-aspnet-abp.md](../ai_instruction_modules/ai-instructions-aspnet-abp.md)

<!--
copilot-source:
  file: "pr-review-comments(model, pr_num).prompt.md"
  mode: agent
  model: "${model}"
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
    Source filename contained parentheses 'pr-review-comments(model, pr_num).prompt.md'
    which are not valid in OpenCode command names. Slugged to
    'pr-review-comments-model-pr-num'. Source used '${model}' Copilot variable
    in the model frontmatter field; this has no OpenCode equivalent and was
    omitted from frontmatter.
-->
