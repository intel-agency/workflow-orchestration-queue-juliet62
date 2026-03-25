---
description: Resolve all review comments in a pull request
---

# Inputs

- pr_num: The number of the pull request to address comments for. Pass as $ARGUMENTS.

# Prompt

In PR #$ARGUMENTS, address **ALL** review comments.

**ALL REVIEW COMMENTS MUST BE ADDRESSED.**

# Steps

1. Fetch a list of ALL unresolved review comments from the PR.
2. Create a list of all unresolved review comments.
3. Resolve all of them, one by one, following the steps below for each comment.

Resolving a review comment means:

1. analyzing the comment
    a. if functionality is working as designed or otherwise no code change is needed, skip to step 4. and explain why no code change is needed.
2. making necessary code changes to address the comment
3. committing/pushing the changes
4. replying to the comment with an explanation of the changes made
5. using the Graphql API to resolve the review comment thread.

**DO NOT SKIP ANY STEPS.**

You can leave a comment on the review thread if you need clarification about the comment, but you must still resolve the review after getting clarification.

After all review comments are resolved, please:
1. leave a final comment on the PR summarizing the changes made to address the review comments.
2. Show the list, marked with final status of each, to the user in the chat

When finished, fetch the list again to make sure that there are 0 unresolved comments left. If not, resolve the remaining ones.

<!--
copilot-source:
  file: resolve-pr-comments.prompt.md
  argument-hint: "pr_num = pull request number"
  notes: >
    Source used '${pr_num}' variable syntax; translated to $ARGUMENTS for OpenCode.
    Source had a commented-out 'agent: agent' field in frontmatter.
-->
