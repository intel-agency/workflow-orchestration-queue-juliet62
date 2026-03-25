# Implementation Plan: PR Approval, Merge, and Debrief Orchestration Steps

**Status:** IMPLEMENTED  
**Author:** Copilot (with NM feedback incorporated)  
**Date:** 2026-03-22  

---

## Objective

Establish two formal, dedicated orchestration steps after the implementation phase:

1. **PR Review & Merge** — A dedicated quality-gate step that manages CI validation, code review delegation, comment resolution (via the existing `pr-approval-and-merge.md` protocol), and final merge.
2. **Debrief & Plan Adjustment** — A lightweight feedback loop where deviations, new findings, and minor AC failures are captured and acted on before the next epic begins.

This separates "Quality Assurance & Delivery" and "Retrospective/Forward-Planning" from the "Implementation" phase, preventing monolithic agent states and enabling explicit error loops.

---

## Proposed Orchestration Sequence (Per Epic)

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────────────┐     ┌──────────────────────────┐
│ create-epic-v2  │ ──► │  implement-epic   │ ──► │  pr-approval-and-merge   │ ──► │ debrief + plan-adjustment│
│  (plan & issue) │     │ (code, test, PR)  │     │ (CI, review, merge)      │     │ (findings, update plan)  │
└─────────────────┘     └──────────────────┘     └──────────────────────────┘     └──────────────────────────┘
        ▲                                                                                     │
        └─────────────────────────────── Loop to next epic ◄──────────────────────────────────┘
```

---

## Phase 1: Update `pr-approval-and-merge.md` — Add CI Verification Loop

**File:** `agent-instructions/ai_instruction_modules/ai-workflow-assignments/pr-approval-and-merge.md`

The existing `pr-approval-and-merge.md` already has robust coverage for comment resolution (GraphQL thread resolution, reply templates, summary comments). What it currently lacks is an **explicit CI wait/remediation loop**. We will add this as a new preliminary state before the existing Phase 1.

### Changes to make

**Add a new "Phase 0.5: CI Verification & Remediation Loop" section** (after Pre-flight, before Phase 1):

- **Step 1 (CI Polling):** After the PR is opened/pushed to, wait briefly (30-60s) for GitHub Actions to trigger, then poll the PR's status checks using `gh pr checks <pr_num>`.
- **Step 2 (CI Remediation):** If any check fails:
  - Fetch the GitHub Actions run logs (`gh run view <run_id> --log-failed`).
  - Diagnose the failure (lint, test, build).
  - Push a fix commit to the PR branch.
  - Return to Step 1.
- **Step 3 (CI Green Gate):** Once all required checks pass, proceed to review delegation.
- **Max Retries:** Cap the CI remediation loop at 3 attempts before escalating to the orchestrator.

**Update the Code Review step to use delegation:**

- The orchestrator MUST delegate code review to the `code-reviewer` subagent (not self-review).
- After delegating (or after pushing new commits), wait briefly for auto-reviewers (e.g., Copilot reviewer, CodeQL) to add their own comments before beginning comment resolution.
- The existing Phase 1 (`pr-review-comments` protocol with GraphQL `resolveReviewThread` mutations) handles comment resolution exactly as-is — no changes needed there.

### Not changing

- The existing comment resolution flow (Phase 1) — it's already well-defined with explicit steps for fix, push, reply, and GraphQL thread resolution.
- The existing merge execution (Phase 3) — already complete.

---

## Phase 2: Refactor `implement-epic.md` — Hard Stop at PR Creation

**File:** `agent-instructions/ai_instruction_modules/ai-workflow-assignments/dynamic-workflows/implement-epic.md`

### Changes to make

- **Add explicit terminal condition:** The implementer's final output is an **opened Pull Request** linked to the epic issue. The implementer does NOT monitor CI, does NOT review comments, and does NOT merge.
- **Add handoff directive:** After opening the PR, the implementer reports the PR number back to the orchestrator and exits the assignment successfully.
- **Remove/clarify:** Any language that implies the implementer should wait for or respond to CI results or review feedback.

---

## Phase 3: Update Orchestrator Prompt — 4-Step Loop

**Locations to update:**
- The orchestrator prompt template in `ai-new-workflow-app-template` (e.g., `prompt.ps1`, `orchestrator-supervisor.md`, or the assembled prompt).
- Any references to the sequence in `ai-new-app-template.md` or `.github/ISSUE_TEMPLATE/application-plan.md`.

### Changes to make

- Explicitly define the per-epic loop as a **4-step sequence**:
  1. `create-epic-v2` — Plan the epic, create the issue.
  2. `implement-epic` — Implement code, open the PR.
  3. `pr-approval-and-merge` — CI verification, code review (delegated), comment resolution, merge.
  4. Debrief & Plan Adjustment (lightweight — see Phase 4 below).
- After Step 4, the orchestrator loops back to Step 1 for the next epic in the current phase.

---

## Phase 4: Debrief & Plan Adjustment Step (Lightweight)

### Approach: Minimal Guidance Now, Full Integration Later

Given that we are already making significant structural changes to the orchestration sequence, we will take the **conservative approach**:

- **Now:** Add 1-2 sentences of additional guidance to `debrief-and-document.md` and `report-progress.md` directing the agent to capture deviations and plan-impacting findings.
- **Later:** After proving the new 4-step sequence works, evaluate whether to integrate the full `continuous-improvement.md` workflow as a formal 5th step.

### Changes to `report-progress.md`

Add guidance (in the "Generate Progress Report" section) that the progress report MUST include:
- Any deviations from the epic's plan or acceptance criteria (even minor ones).
- New findings about the tech stack, architecture, or dependencies that subsequent epics should account for.
- A brief review of whether the next 1-2 upcoming epics still make sense given what was learned.

### Changes to `debrief-and-document.md`

Add guidance (in the "Assignment" section) that the debrief MUST:
- Flag any plan-impacting findings explicitly as **ACTION ITEMS** with a recommendation to either:
  - File a new issue for newly-discovered required work.
  - Update later phase/epic descriptions to account for new realities.
- Review upcoming steps in the current and next phase for continued validity.

### Future consideration (deferred)

The existing `continuous-improvement.md` assignment is a strong candidate for a full retrospective step. Once the 4-step sequence is proven, we can evaluate promoting it to a formal orchestration step that converts debrief findings into backlog items with value/risk scoring.

---

## Acceptance Criteria

- [x] `pr-approval-and-merge.md` has an explicit CI polling/remediation loop before the review phase.
- [x] `pr-approval-and-merge.md` directs code review delegation to the `code-reviewer` subagent (not self-review).
- [x] `pr-approval-and-merge.md` includes guidance to wait for auto-reviewers before beginning comment resolution.
- [x] `implement-epic.md` has an explicit terminal condition at PR creation with handoff to orchestrator.
- [x] `implement-epic.md` does NOT contain any CI monitoring, review, or merge expectations.
- [x] The orchestrator prompt explicitly defines the 4-step per-epic loop (`create` -> `implement` -> `pr-merge` -> `debrief`).
- [x] `report-progress.md` includes guidance to capture deviations and plan-impacting findings.
- [x] `debrief-and-document.md` includes guidance to flag ACTION ITEMS and review upcoming epics.
- [x] No structural changes to `continuous-improvement.md` at this time (deferred).

---

## Files Modified (Summary)

| File | Repo | Change |
|------|------|--------|
| `ai-workflow-assignments/pr-approval-and-merge.md` | agent-instructions | Add CI loop, review delegation guidance |
| `ai-workflow-assignments/dynamic-workflows/implement-epic.md` | agent-instructions | Hard stop at PR creation |
| `ai-workflow-assignments/report-progress.md` | agent-instructions | Add deviation/findings guidance |
| `ai-workflow-assignments/debrief-and-document.md` | agent-instructions | Add ACTION ITEM flagging guidance |
| Orchestrator prompt (TBD exact file) | ai-new-workflow-app-template | Define 4-step loop |
