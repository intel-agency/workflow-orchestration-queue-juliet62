---
name: prompt-bisect
description: >-
  Walking revision bisection for AI agent prompt constraints using git worktrees.
  Isolates single-variable prompt changes, runs orchestration tests in each worktree,
  and reports which constraint removal causes behavioral degradation.
  Use when: tuning agent system prompts, finding which constraint is load-bearing,
  A/B testing prompt variants against a known-good baseline.
license: MIT
compatibility: opencode
metadata:
  audience: prompt-engineers
  workflow: git-worktree
---

## What I do

- Set up isolated git worktrees from a known-good baseline commit
- Apply single-variable prompt constraint removals in each worktree
- Run orchestration tests per variant and capture output logs
- Evaluate results against baseline behavioral criteria
- Report a degradation gradient table showing which constraints are load-bearing
- Clean up all worktrees and bisect branches when done

## When to use me

Use this when you have a known-good agent prompt and want to find which constraint(s) are structurally critical. Also for A/B testing prompt changes against a baseline orchestration run.

Ask clarifying questions if the baseline commit, target file, or evaluation criteria are unclear.

## Workflow

### 1. Define the Experiment

Collect from the user:

- **Baseline commit**: The known-good commit hash (e.g. `d9920f0`)
- **Target file**: The prompt file to bisect (e.g. `.opencode/agents/orchestrator.md`)
- **Variants**: A list of single-variable changes to test, each with:
  - A short name (e.g. `no-checklist`, `no-depth-limit`, `no-concurrent-cap`)
  - The exact text to remove or replace
- **Test command**: How to evaluate each variant (manual or automated)
- **Worktree base path**: Where to create worktrees (default: `../bisect-worktrees/`)

### 2. Create Worktrees

For each variant, create an isolated git worktree:

```powershell
$baseCommit = "<baseline-commit>"
$worktreeBase = "../bisect-worktrees"

foreach ($variant in $variants) {
    $branchName = "bisect/$($variant.name)"
    $worktreePath = Join-Path $worktreeBase $variant.name

    git worktree add -b $branchName $worktreePath $baseCommit
}
```

### 3. Apply Variants

In each worktree, make exactly ONE change from the baseline:

| Variant | Change | File |
|---------|--------|------|
| `no-concurrent-cap` | Remove `(≤2 concurrent)` from step 5 | orchestrator.md |
| `no-depth-section` | Remove "Delegation Depth Management" section | orchestrator.md |
| `no-checklist` | Remove "Delegation Decision Framework" section | orchestrator.md |
| `no-context-levels` | Replace Progressive Context Reduction with condensed version | orchestrator.md |
| `no-depth-rule` | Remove `delegation-depth ≤2` rule | AGENTS.md |

### 4. Run Tests

For each worktree, run the test command and capture output:

```powershell
foreach ($variant in $variants) {
    $worktreePath = Join-Path $worktreeBase $variant.name
    Push-Location $worktreePath

    # Run orchestration test and capture to log
    # e.g. opencode orchestrate-project-setup | Tee-Object "bisect-$($variant.name).log"

    Pop-Location
}
```

### 5. Evaluate Results

For each variant, check against baseline criteria:

- Does the orchestrator produce sequential assignment execution?
- Does the todo list show individual `[x]` items for each assignment?
- Does the output include file tree and run report?
- Are colored status indicators present?

### 6. Report

Generate a summary table:

```
| Variant              | Sequential? | Todo tracking? | Full output? | Verdict    |
|======================|=============|================|==============|============|
| baseline             | YES         | YES            | YES          | GOOD       |
| no-concurrent-cap    | ???         | ???            | ???          | ???        |
| no-depth-section     | ???         | ???            | ???          | ???        |
| no-checklist         | ???         | ???            | ???          | ???        |
| no-context-levels    | ???         | ???            | ???          | ???        |
| no-depth-rule        | ???         | ???            | ???          | ???        |
```

### 7. Cleanup

```powershell
foreach ($variant in $variants) {
    $worktreePath = Join-Path $worktreeBase $variant.name
    git worktree remove $worktreePath
    git branch -D "bisect/$($variant.name)"
}
```

## Key Principles

- **One variable at a time**: Each worktree changes exactly one constraint from baseline
- **Isolation**: Worktrees ensure no cross-contamination between variants
- **Reversibility**: Worktrees are disposable; `git worktree remove` cleans up completely
- **Gradient capture**: Linear walk (not binary search) reveals proportional impact
- **Main tree untouched**: All experimentation happens in worktrees

## Notes

- For stochastic model outputs, run each variant 2-3 times to distinguish signal from noise
- Borderline variants are valuable data — the constraint helps but isn't the cliff edge
- The cliff edge is typically the constraint in the model's procedural hot path (numbered steps it follows every run) vs reference sections it may or may not consult
