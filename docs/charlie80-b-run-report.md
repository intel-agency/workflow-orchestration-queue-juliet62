# Charlie80-b Orchestration Run Report

**Repository:** `intel-agency/workflow-orchestration-queue-charlie80-b`
**Date range:** 2026-03-22 01:12 – 04:56 UTC (~3h 44m total elapsed)
**Generated:** 2026-03-22

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total workflow runs | 110 |
| Successful | 98 |
| Failed | 9 |
| Cancelled | 1 |
| Skipped | 2 |
| **Success rate** | **89.1%** |
| Issues created | 13 (incl. 3 sub-stories) |
| Issues closed | 8 |
| Issues still open | 5 |
| PRs merged | 6 |
| PRs open | 1 (PR #1 project-setup) |
| Milestones created | 8 |

### Runs by Workflow

| Workflow | Runs | Purpose |
|----------|------|---------|
| orchestrator-agent | 65 | AI orchestrator processing issues |
| CodeQL | 22 | Security analysis |
| validate | 18 | Lint + scan + test |
| Publish Docker | 2 | Container image build |
| Pre-build dev container image | 2 | DevContainer layer |
| Python CI | 1 | Python test/lint |

---

## Execution Sequence (Chronological)

### Phase 0: Bootstrap (01:12 – 01:28 UTC)

| Time | Event | Result |
|------|-------|--------|
| 01:12 | Initial commit triggers validate, Publish Docker, CodeQL | validate ✅, Docker ❌ cancelled, CodeQL ✅ |
| 01:12 | Seed commit triggers validate + Publish Docker | ✅ both |
| 01:12 | Pre-build dev container image | skipped → then ✅ on retry at 01:14 |
| 01:15 | orchestrator-agent first run (project-setup) | ✅ |
| 01:28 | PR #1 opened (project-setup branch) | validate ✅, CodeQL ✅ |

**Notes:** Standard template bootstrap. The Publish Docker cancel on initial commit is expected (no Dockerfile yet). Pre-build was initially skipped waiting for the Docker image, then succeeded.

### Phase 0: Planning & Task 0.1 (01:28 – 02:14 UTC)

| Time | Event | Result |
|------|-------|--------|
| 01:38 | PR #1 updated (project structure created) | validate ✅, CodeQL ✅ |
| 01:38 | Issue #2, #4 created (Application Plan) → orchestrator fires 4× | ✅ all (skip-event filters) |
| 01:45 | Issue #3 created (Task 1.1 Epic) → orchestrator fires 5× | ✅ all |
| 01:51 | Issue #4 label change → orchestrator fires 4× | ✅ all |
| 01:53 | **PR #5 opened** (Epic 1.1 – Python project bootstrap) | validate ✅, CodeQL ✅ |
| 01:55 | **PR #5 merged** → push to main | validate ✅, CodeQL ✅ |
| 01:56 | Issue #3 (Task 1.1) label → implementation:complete | orchestrator ✅ |
| 01:57 | PR #1 updated again → **Python CI ❌ fails** | `feat: create OS-APOW project structure` |
| 02:00 | Issue #6 created (Task 0.1 – template verification) → orchestrator fires 6× | ✅ all |
| 02:07 | Issue #7 created (Task 1.2 – WorkItem model) → orchestrator fires 5× | ✅ all |
| 02:11 | **PR #8 opened** (Task 0.1 – template verification) | **validate ❌**, CodeQL ✅ |
| 02:14 | **PR #8 merged** → push to main | **validate ❌**, CodeQL ✅ |
| 02:15 | Issue #6 (Task 0.1) → implementation:complete | orchestrator ✅ |

**Issues created:** #2, #3, #4, #6, #7
**PRs merged:** #5 (1.1 bootstrap), #8 (0.1 verification)
**Failures:**
- Python CI on PR #1: Agent-created Python scaffolding triggered a Python CI workflow that failed (likely missing dependencies or test config in the generated code)
- validate on PR #8 + merge: Template verification script had issues

### Phase 0: Task 0.2 – Seed Plan Docs (02:14 – 02:47 UTC)

| Time | Event | Result |
|------|-------|--------|
| 02:21 | Issue #9 created (Task 0.2 – seed docs) → orchestrator fires 5× | ✅ all |
| 02:27 | Issues #10, #11, #12 created (sub-stories for docs) → orchestrator fires 8× | ✅ all |
| 02:29 | **PR #13 opened** (seed plan docs to /docs) | **validate ❌** (gitleaks), CodeQL ✅ |
| 02:30 | Issue #7 (Task 1.2) label update → orchestrator fires | ✅ |
| 02:34 | **PR #13 merged** → push to main | **validate ❌** (gitleaks), CodeQL ✅ |
| 02:36 | Issue #9 (Task 0.2) → implementation:complete | orchestrator ✅ |
| 02:46 | Issue #14 created (Task 1.3 – sentinel polling) → orchestrator fires 5× | ✅ all |
| 02:46 | Issue #15 created (Task 0.3 – DevContainer init) → orchestrator fires 3× | 2× ✅, **1× ❌** |
| 02:47 | Issue #15 (Task 0.3) – orchestrator attempt | ❌ (unknown, likely skip-event edge case) |

**Issues created:** #9, #10, #11, #12, #14, #15
**PRs merged:** #13 (seed docs)
**Failures:**
- validate on PR #13 + merge: **gitleaks found 1 leak** — fake `sk-` key in `tests/test_work_item.py` line 90 (test fixture for credential scrubber). False positive. Root cause: AI-generated test code used a realistic-looking `sk-1234567890abcdefghijklmnopqrstuv` as test input.
- orchestrator on Issue #15: One of three runs failed

### Phase 1: Tasks 1.3 – 1.5 (03:52 – 04:56 UTC)

| Time | Event | Result |
|------|-------|--------|
| 03:52 | **PR #16 opened** (Task 1.3 – sentinel polling engine) | **validate ❌** (1st attempt), CodeQL ✅ |
| 03:54 | PR #16 updated (fix pushed) | validate ✅, CodeQL ✅ |
| 03:56 | **PR #16 merged** → push to main | validate ✅, CodeQL ✅ |
| 03:57 | Issue #14 (Task 1.3) → implementation:complete | orchestrator ✅ |
| 04:06 | Issue #17 created (Task 1.4 – distributed locking) → orchestrator fires 5× | ✅ all |
| 04:25 | **PR #18 opened** (Task 1.4 – distributed locking) | validate ✅, CodeQL ✅ |
| 04:27 | **PR #18 merged** → push to main | validate ✅, CodeQL ✅ |
| 04:28 | Issue #17 (Task 1.4) → implementation:complete | orchestrator ✅ |
| 04:36 | Issue #19 created (Task 1.5 – shell-bridge dispatcher) → orchestrator fires 5× | 4× ✅, **1× ❌** |
| 04:53 | **PR #20 opened** (Task 1.5 – shell-bridge dispatcher) | validate ✅, CodeQL ✅ |
| 04:54 | **PR #20 merged** → push to main | validate ✅, CodeQL ✅ |
| 04:55 | Issue #19 re-trigger (label change after merge) | **orchestrator ❌** |

**Issues created:** #17, #19
**PRs merged:** #16 (1.3 polling), #18 (1.4 locking), #20 (1.5 dispatcher)
**Failures:**
- validate on PR #16 (1st attempt): Failed validation, agent pushed a fix, 2nd attempt passed
- orchestrator on Issue #19 (run `23395766201`): opencode exited 0 but `devcontainer-opencode.sh` hit a bash syntax error on line 255 (`syntax error near unexpected token '('`). The orchestrator actually completed its work — the failure is in the **agent-modified** copy of the shell bridge script.
- orchestrator on Issue #19 (run `23396030587`): Spurious re-trigger after PR #20 was already merged. Failed with `Error: You must provide a message or a command` + `bc: command not found` — the issue was already complete, so the prompt was likely empty/malformed.

---

## Issue Tracker Summary

### Closed (8)

| # | Title | Phase | Labels | Closed |
|---|-------|-------|--------|--------|
| 3 | Task 1.1 – Foundation & Setup | Phase 1 | `implementation:complete` | 01:55 |
| 6 | Task 0.1 – Template Verification | Phase 0 | `implementation:complete` | 02:14 |
| 9 | Task 0.2 – Seed Plan Docs | Phase 0 | `implementation:complete` | 02:34 |
| 10 | Story 3: Doc Index | Phase 0 | `documentation` | 02:34 |
| 11 | Story 2: Doc Validation | Phase 0 | `documentation` | 02:34 |
| 12 | Story 1: Doc Migration | Phase 0 | `documentation` | 02:34 |
| 14 | Task 1.3 – Sentinel Polling Engine | Phase 1 | `implementation:complete` | 03:56 |
| 17 | Task 1.4 – Distributed Locking | Phase 1 | `implementation:complete` | 04:27 |
| 19 | Task 1.5 – Shell-Bridge Dispatcher | Phase 1 | `implementation:complete` | 04:54 |

### Open (4)

| # | Title | Phase | Status | Notes |
|---|-------|-------|--------|-------|
| 2 | Complete Implementation (Application Plan) | — | `state:planning` | Duplicate of #4; tracker issue |
| 4 | Complete Implementation (Application Plan) | — | `state:planning` | Master tracker; never closed |
| 7 | Task 1.2 – WorkItem Model | Phase 1 | `implementation:complete` | **Should be closed** — has `implementation:complete` label but state is OPEN |
| 15 | Task 0.3 – DevContainer Init | Phase 0 | `implementation:ready` | **Not started** — no PR created, no implementation |

### PR Summary

| # | Title | Branch | Status | Merged |
|---|-------|--------|--------|--------|
| 1 | project-setup: Initialize repository | `dynamic-workflow-project-setup` | **OPEN** | — |
| 5 | Epic 1.1 – Python Project Bootstrap | `feature/os-apow-implementation` | MERGED | 01:55 |
| 8 | Phase 0 Task 0.1 – Template Verification | `epic/6-verify-template-repository` | MERGED | 02:14 |
| 13 | docs: Seed plan documents (Epic #9) | `feature/workflow-orchestration-queue` | MERGED | 02:34 |
| 16 | Sentinel polling engine (Task 1.3) | `feature/sentinel-polling-engine` | MERGED | 03:56 |
| 18 | Distributed locking (Task 1.4) | `feature/epic-1.4-distributed-locking` | MERGED | 04:27 |
| 20 | Shell-Bridge Dispatcher (Task 1.5) | `feature/shell-bridge-dispatcher` | MERGED | 04:54 |

---

## Gap Analysis

### What Completed Successfully

The orchestrator executed a full Phase 0 + Phase 1 implementation sequence:

1. ✅ **Task 0.1** – Template repository verification (PR #8)
2. ✅ **Task 0.2** – Seed plan documents to /docs (PR #13)
3. ✅ **Task 1.1** – Python project bootstrap (PR #5)
4. ✅ **Task 1.2** – WorkItem model (created in PR #1 code, issue labeled `implementation:complete`)
5. ✅ **Task 1.3** – Sentinel polling engine (PR #16, self-healed after 1st validate failure)
6. ✅ **Task 1.4** – Distributed locking (PR #18, clean first pass)
7. ✅ **Task 1.5** – Shell-bridge dispatcher (PR #20, clean first pass)

### What Was Missed or Left Incomplete

| Gap | Severity | Description | Catalog Ref |
|-----|----------|-------------|-------------|
| **Issue #7 not closed** | Low | Has `implementation:complete` label but GitHub state is OPEN. The orchestrator labeled it but didn't close it — likely a label-vs-close race condition or the close action was omitted. | ISSUE-3 |
| **Issue #15 (Task 0.3) not started** | Medium | DevContainer initialization epic was created but no PR was ever opened for it. Agent went idle for 15m and was killed by watchdog. Task is a runtime concern, not a code task — the agent couldn't produce a deliverable. | ISSUE-4 |
| **Issue #2 duplicate of #4** | Low | Two nearly identical "Complete Implementation" tracker issues exist. #2 and #4 both have the same title. Neither is closed. | ISSUE-5 |
| **PR #1 still open** | Low | The project-setup PR was never merged. This is expected — it's the initial bootstrap PR that gets superseded by the individual feature PRs merged directly. | ISSUE-6 |
| **Gitleaks false positive** | Medium | `tests/test_work_item.py` contains a fake `sk-` key that fails gitleaks. validate failed on 5 runs across PRs #8, #13, #16. The code was merged despite failures. | ISSUE-1 |
| **Python CI failure** | Low | A `Python CI` workflow failed on PR #1 due to missing `README.md` in the Docker build. Not blocking since the workflow is disabled and work continued via other PRs. | ISSUE-7 |

### Spurious Orchestrator Runs

The orchestrator workflow fires on every `issues` event (opened, labeled, closed, etc.). For a single epic lifecycle, this produces **5–8 runs** per issue — most immediately exit via the `skip-event` filter job. This is working as designed but produces a lot of noise (65 orchestrator runs for ~10 actual work items).

---

## Failure Root Causes

| # | Workflow | Trigger | Root Cause | Impact | Catalog Ref |
|---|----------|---------|------------|--------|-------------|
| 1 | Python CI | PR #1 | Missing `README.md` during Docker editable install (`hatchling` build backend) | None — workflow disabled | ISSUE-7 |
| 2 | validate | PR #8 | Gitleaks: fake `sk-` key in `tests/test_work_item.py:90` (false positive) | PR merged despite failure | ISSUE-1 |
| 3 | validate | PR #8 merge | Same gitleaks false positive (push to main) | None | ISSUE-1 |
| 4 | validate | PR #13 | Same gitleaks false positive | PR merged despite failure | ISSUE-1 |
| 5 | validate | PR #13 merge | Same gitleaks false positive (push to main) | None | ISSUE-1 |
| 6 | orchestrator | Issue #15 | Agent idle 15m on runtime-verification task (no code deliverable) → watchdog SIGTERM | Issue left OPEN, not implemented | ISSUE-4 |
| 7 | validate | PR #16 (1st) | Same gitleaks false positive; agent self-healed with fix push, 2nd attempt passed | Resolved by retry | ISSUE-1 |
| 8 | orchestrator | Issue #19 | Agent modified `devcontainer-opencode.sh` in-place during execution → bash syntax error at old byte offset | Work completed (exit 0), cosmetic failure | ISSUE-8 |
| 9 | orchestrator | Issue #19 | Re-trigger on completed issue; empty/malformed prompt → `no message` + `bc: command not found` | Spurious, task already done | ISSUE-9 |

---

## Milestone Progress

| Milestone | Open Issues | Closed Issues | Status |
|-----------|-------------|---------------|--------|
| Phase 0: Seeding & Bootstrapping | 1 (#15) | 2 (#6, #9) | Incomplete — Task 0.3 not done |
| Phase 1: The Sentinel (MVP) | 2 (#4, #7) | 4 (#3, #14, #17, #19) | **Mostly complete** — #7 should be closed |
| Phase 2: The Ear | 0 | 0 | Not started |
| Phase 3: Deep Orchestration | 0 | 0 | Not started |

---

## Timeline Visualization

```
01:12  [SEED]     Initial commit + template seed
01:15  [ORCH]     Project-setup orchestrator run
01:28  [PR #1]    Project-setup PR opened
 |
01:45  [ISSUE #3] Task 1.1 Epic created
01:53  [PR #5]    ← Epic 1.1 Python bootstrap
01:55  [MERGE]    PR #5 merged ──── Task 1.1 ✅
 |
02:00  [ISSUE #6] Task 0.1 Epic created
02:07  [ISSUE #7] Task 1.2 Epic created
02:11  [PR #8]    ← Task 0.1 template verification
02:14  [MERGE]    PR #8 merged ──── Task 0.1 ✅ (validate ❌ ignored)
 |
02:21  [ISSUE #9] Task 0.2 Epic created
02:27  [ISSUE 10-12] Sub-stories created
02:29  [PR #13]   ← Task 0.2 seed plan docs
02:34  [MERGE]    PR #13 merged ── Task 0.2 ✅ (gitleaks ❌ ignored)
 |
02:46  [ISSUE #14] Task 1.3 Epic created
02:47  [ISSUE #15] Task 0.3 Epic created ── ⚠️ NEVER IMPLEMENTED
 |
03:52  [PR #16]   ← Task 1.3 sentinel polling (validate ❌, self-healed)
03:56  [MERGE]    PR #16 merged ── Task 1.3 ✅
 |
04:06  [ISSUE #17] Task 1.4 Epic created
04:25  [PR #18]   ← Task 1.4 distributed locking
04:27  [MERGE]    PR #18 merged ── Task 1.4 ✅
 |
04:36  [ISSUE #19] Task 1.5 Epic created
04:53  [PR #20]   ← Task 1.5 shell-bridge dispatcher
04:54  [MERGE]    PR #20 merged ── Task 1.5 ✅
04:55  [ORCH ❌]  Spurious re-trigger on closed issue
```

---

## Issues Catalog

### ISSUE-1: Gitleaks false positive on synthetic test fixture

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Where** | `tests/test_work_item.py:90` (charlie80-b, commit `bbeea4e`) |
| **Workflow** | `validate` — scan job, `gitleaks detect` step |
| **Runs affected** | `23393669406` (PR #8), `23393712348` (PR #8 merge), `23393952838` (PR #13), `23394022749` (PR #13 merge), `23395141930` (PR #16 1st attempt) |
| **Error output** | `FAIL: System.Management.Automation.RemoteException` / `leaks found: 1` |
| **Root cause** | Agent-generated test for `scrub_secrets()` used a fake OpenAI-style key `sk-1234567890abcdefghijklmnopqrstuv` as test input. Gitleaks `generic-api-key` rule flagged it (entropy 5.01). This is a **false positive** — the key is synthetic test data, not a real credential. |
| **Impact** | All validate runs that scan git history hit this. PRs were merged despite the failure because branch protection wasn't strict. |
| **Fix (template)** | **APPLIED** in commit `408339f`: (1) `.gitleaks.toml` with allowlist for `sk-1234567890abcdef` scoped to `tests/test_work_item.py`, (2) `AGENTS.md` directive telling agents to avoid real-looking secret prefixes (`sk-`, `ghp_`, `ghs_`, `AKIA`) in test fixtures, (3) `validate.ps1` bug fix: `$_` → `$_.Exception.Message` so gitleaks findings are visible in CI logs instead of showing `System.Management.Automation.RemoteException`. |
| **Fix (charlie80-b)** | Copy `.gitleaks.toml` from template into the repo. Alternatively, rewrite the test to use obviously fake values like `FAKE-KEY-FOR-TESTING-00000000`. |

---

### ISSUE-2: validate.ps1 error display swallows gitleaks finding details

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Where** | `scripts/validate.ps1`, `Invoke-Check` function (line 65 in template) |
| **Error output** | `FAIL: System.Management.Automation.RemoteException` instead of the actual gitleaks output |
| **Root cause** | The catch handler used `Write-Host " FAIL: $_"`. In PowerShell, when an exception is thrown from a string (the joined gitleaks output), `$_` stringifies to the exception type name, not the message content. |
| **Impact** | All gitleaks failures showed only the exception type, making it impossible to diagnose the finding from CI logs alone. Required cloning the repo and running gitleaks locally. |
| **Fix (template)** | **APPLIED** in commit `408339f`: Changed to `Write-Host " FAIL: $($_.Exception.Message)"`. |
| **Fix (charlie80-b)** | Will automatically pick up template fix on next template sync. |

---

### ISSUE-3: Issue #7 (Task 1.2 – WorkItem Model) left OPEN despite completion

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Where** | GitHub issue tracker — Issue #7 in charlie80-b |
| **What happened** | The orchestrator applied the `implementation:complete` label to Issue #7 but never closed the issue via `gh issue close`. Issue #7 (Task 1.2 WorkItem Model) was implemented as part of the project structure in commit `bbeea4e` and later enhanced in commit `3f7a5a7`. |
| **Root cause** | The orchestrator's close-issue logic has a gap: it labels issues as complete but doesn't consistently follow up with a close operation. This may be a timing issue (label applied, then the run ended before the close command) or an instruction gap in the orchestrator agent prompt. |
| **Impact** | Milestone progress reporting shows Task 1.2 as incomplete when it's actually done. |
| **Recommended fix** | `gh issue close 7 --repo intel-agency/workflow-orchestration-queue-charlie80-b --reason completed` |
| **Template fix** | Consider adding an explicit instruction in the orchestrator agent prompt: "After labeling an issue `implementation:complete`, always close it with `gh issue close`." |

---

### ISSUE-4: Issue #15 (Task 0.3 – DevContainer Init) never implemented

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Where** | GitHub issue #15, orchestrator run `23394201761` |
| **Error output** | `opencode idle for 15m (no output from client or server); terminating` / `opencode exit code: 143` (SIGTERM) |
| **Root cause** | The orchestrator picked up Issue #15 (DevContainer initialization) but the agent went idle — no client or server output for 15 minutes, triggering the watchdog timeout. Task 0.3 asks the agent to "start the devcontainer and verify tools" which is a **runtime/infra task**, not a code-writing task. The AI agent likely couldn't figure out what code to produce and stalled. |
| **Impact** | DevContainer initialization was never verified. Phase 0 milestone is incomplete (2/3 tasks done). |
| **Recommended fix** | Either: (A) Close Issue #15 as out-of-scope — DevContainer init is implicitly verified by every subsequent orchestrator run that successfully starts a devcontainer. Tasks 1.3–1.5 all proved the devcontainer works. Or (B) rewrite the issue body to be a code-deliverable task (e.g., "create a `test/test-devcontainer-health.sh` script") and re-trigger. |
| **Template fix** | Consider adding guidance to the plan-creation agent: "Do not create issues for runtime verification tasks that have no code deliverable. DevContainer health is validated implicitly by every orchestrator run." |

---

### ISSUE-5: Duplicate tracker issues #2 and #4

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Where** | GitHub issues #2 and #4, both titled "workflow-orchestration-queue – Complete Implementation (Application Plan)" |
| **Root cause** | The planning orchestrator created two nearly identical "Complete Implementation" tracker issues. Issue #2 was created at 01:38 and #4 at 01:51. Both have `implementation:ready` labels and neither is closed. Likely a duplicate creation during the initial planning phase when the orchestrator ran multiple times for the same event. |
| **Impact** | Confusing issue tracker. Neither serves as a clean parent tracker. |
| **Recommended fix** | Close Issue #2 as duplicate: `gh issue close 2 --repo intel-agency/workflow-orchestration-queue-charlie80-b --reason "not planned" --comment "Duplicate of #4"` |

---

### ISSUE-6: PR #1 (project-setup) still open

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Where** | PR #1, branch `dynamic-workflow-project-setup` |
| **Root cause** | The project-setup workflow creates PR #1 as a staging area. All actual work was delivered through feature PRs (#5, #8, #13, #16, #18, #20) merged directly to main. PR #1 was never merged because the individual PRs superseded it. The orchestrator doesn't have a "close stale project-setup PR" step. |
| **Impact** | Stale open PR in the repo. The branch diverges significantly from main. |
| **Recommended fix** | Close without merging: `gh pr close 1 --repo intel-agency/workflow-orchestration-queue-charlie80-b --comment "Superseded by feature PRs #5, #8, #13, #16, #18, #20"` |
| **Template fix** | Consider adding a debrief step to the orchestrator that closes the project-setup PR after all epics complete. |

---

### ISSUE-7: Python CI workflow failure on Docker build

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Where** | `Python CI` workflow, run `23393438738`, PR #1 |
| **Error output** | `OSError: Readme file does not exist: README.md` during `uv pip install --no-cache -e .` in Dockerfile |
| **Root cause** | The agent created a Python CI workflow and Dockerfile that attempted an editable install (`uv pip install -e .`). The `hatchling` build backend requires `README.md` referenced in `pyproject.toml`, but the file didn't exist at that point in the PR branch. |
| **Impact** | None — the Python CI workflow is in `.github/workflows/.disabled/` and the work continued through other PRs. |
| **Recommended fix** | No action needed. If the Python CI workflow is re-enabled, ensure `README.md` exists or remove it from `pyproject.toml`'s `[project]` table. |

---

### ISSUE-8: Bash syntax error in devcontainer-opencode.sh during Task 1.5 execution

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Where** | `scripts/devcontainer-opencode.sh:255`, orchestrator run `23395766201` |
| **Error output** | `./scripts/devcontainer-opencode.sh: line 255: syntax error near unexpected token '('` / exit code 2 |
| **Root cause** | The Task 1.5 agent (shell-bridge dispatcher) **modified `devcontainer-opencode.sh` while it was being executed by bash**. The opencode CLI finished (exit code 0 — the work was done), but the `devcontainer-opencode.sh` script that was wrapping it had been rewritten in-place. When bash continued parsing the file after the opencode subprocess exited, it encountered new syntax at the old byte offset, causing a parse error. This is a classic "modify a running shell script" race condition. |
| **Impact** | Cosmetic — the PR (#20) was created and merged successfully. The work was complete. The failure is only in the post-execution cleanup path. |
| **Recommended fix** | No fix needed for charlie80-b (the merged file is syntactically correct). For the template: consider adding a guard in `devcontainer-opencode.sh` that copies itself to a temp location and `exec`s the copy, so in-place modifications by agents don't affect the running process. |

---

### ISSUE-9: Spurious orchestrator re-trigger on completed issue

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Where** | Orchestrator run `23396030587`, triggered by Issue #19 label change after PR #20 merge |
| **Error output** | `Error: You must provide a message or a command` + `bc: command not found` (exit 127) |
| **Root cause** | After PR #20 merged, a label was applied to Issue #19 (e.g., `implementation:complete`), which triggered another `issues` event. The orchestrator picked it up, but the issue was already done — the assembled prompt was malformed or empty, causing opencode to reject it. The `bc` error is a secondary issue: the `run_opencode_prompt.sh` timing calculation uses `bc` which isn't installed in the devcontainer. |
| **Impact** | None — the task was already complete. |
| **Recommended fix** | (1) The `skip-event` filter in `orchestrator-agent.yml` should check for the `implementation:complete` label and skip runs where the issue is already done. (2) Install `bc` in the devcontainer Dockerfile or replace the timing calculation with bash arithmetic. |

---

## Recommendations Summary

| # | Action | Target | Priority | Status |
|---|--------|--------|----------|--------|
| 1 | Add `.gitleaks.toml` allowlist for synthetic test secrets | Template | High | **DONE** (`408339f`) |
| 2 | Fix `validate.ps1` error display (`$_` → `$_.Exception.Message`) | Template | High | **DONE** (`408339f`) |
| 3 | Add AGENTS.md directive: avoid real secret prefixes in test fixtures | Template | High | **DONE** (`408339f`) |
| 4 | Close Issue #7 as completed | charlie80-b | Low | Pending |
| 5 | Close Issue #2 as duplicate of #4 | charlie80-b | Low | Pending |
| 6 | Close PR #1 as superseded | charlie80-b | Low | Pending |
| 7 | Triage Issue #15 (close or rephrase as code task) | charlie80-b | Medium | Pending |
| 8 | Add `implementation:complete` to skip-event filter | Template | Medium | Not started |
| 9 | Guard against in-place script modification race | Template | Low | Not started |
| 10 | Install `bc` or use bash arithmetic in timing code | Template | Low | Not started |
