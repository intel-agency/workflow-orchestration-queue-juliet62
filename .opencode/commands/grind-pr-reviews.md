---
description: Repeatedly iterate on reviewing PRs and resolving the new comments
---

# Grind PR Reviews

## Arguments

- `pr_num`: The PR number to grind review resolutions on. Pass as $ARGUMENTS.

Repeatedly assign automated reviewers to the PR, then wait for them to conclude their reviews, and then once they finish leaving a batch of review comments, resolve all of them by invoking the /resolve-pr-comments prompt.

## Steps

### 1. Assign whatever automated agent reviewers are available in the PR

You can use the following methods to assign automated reviewers.

They involve leaving comments with specific commands in the PR to trigger the assignment of automated reviewers.

Each of these commands will trigger a different automated reviewer to be assigned to the PR.

Command for assigning agents (copilot in this example) as a reviewer:

``` shell
gh pr comment <PR_NUMBER> --body "@copilot please review these changes for performance issues."
```

Here is the comment text for each specific agent:

- For Copilot: `@copilot please review these changes`
- For Gemini: `@gemini review`
- For Claude: `@claude review`
- For Codex: `@codex review`
- For Opencode.ai: `@opencode review`

Leave comments for every one of the agents each time.

### 2. Wait for the automated reviewers to finish their reviews and leave comments

This may take a while, so be patient. You can monitor the PR for new comments from the automated reviewers. Use a wait threshold process to determine when they have finished leaving comments.

- Monitor the PR for new comments.
- Once at least one comment from an automated reviewer is detected, start a timer.
- If no new comments from automated reviewers are detected for a certain period (e.g., 10 minutes), assume that the reviewers have finished their reviews.
- Then move on to the next step.

### 3. Once the automated reviewers have finished leaving comments, invoke the /resolve-pr-comments prompt to resolve all of the comments left by the automated reviewers

```
/resolve-pr-comments ${pr_num}
```

If the `/resolve-pr-comments` prompt returns that there are still unresolved comments, then repeat step 3. and add the following text to the end of the prompt:

```
Please resolve all of the comments left by the automated reviewers. If there are still unresolved comments, please resolve them and then check again if there are any remaining unresolved comments. Repeat this process until all comments left by the automated reviewers are resolved.

You can use the graphql API to resolve comment threads. **DO NOT FAIL TO RESOLVE ALL OF THE COMMENT THREADS LEFT BY THE AUTOMATED REVIEWERS.**
```

## End condition

Repeat this entire process (steps 1-3) until there are no more comments left by the automated reviewers in the PR, or the comments that are left are trivial or low priority and can be ignored.

<!--
copilot-source:
  file: grind-pr-reviews.prompt.md
  name: grind-pr-reviews
  argument-hint: "pr_num = the PR number to grind review resolutions on"
  notes: >
    Source used 'name' and 'argument-hint' frontmatter keys which have no
    OpenCode equivalent. The argument-hint info has been incorporated into
    the body text using $ARGUMENTS placeholder.
-->
