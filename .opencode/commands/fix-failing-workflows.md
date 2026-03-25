---
description: Describe when to use this prompt
---

Repeat until workflows succeed:

1. check for failing workflows
    a. if $ARGUMENTS is empty, check all workflows
    b. if $ARGUMENTS is not empty, check only the specified workflows (comma or space separated list of workflow names)
2. for each failing workflow, check the logs to identify the cause of failure
3. fix the identified issues in the codebase
4. commit and push the changes to trigger the workflows again
5. monitor the workflow progress
6. if any workflows fail again, repeat the process from step 1

For multiple workflows, prioritize fixing the ones that are critical for the project or have the most impact on the development process.
- Work through one workflow at a time to ensure that each issue is properly addressed before moving on to the next one.
- If the same issue is causing multiple workflows to fail, focus on fixing that issue first to resolve multiple failures at once.

<!--
copilot-source:
  file: fix-failing-workflows.prompt.md
  name: fix-failing-workflows
  argument-hint: "$workflow_names = comma or space separated list of 0 or more workflow names"
  notes: >
    Source used 'name' and 'argument-hint' frontmatter keys which have no
    OpenCode equivalent. The argument-hint info has been incorporated into
    the body text using $ARGUMENTS placeholder. Original body used
    '${workflow_names}' variable syntax.
-->
