# Workflow Issues & Remediation Plan

> **Sources analyzed:**
>
> - [yankee89-b repo](https://github.com/intel-agency/workflow-orchestration-queue-yankee89-b) — actions, issues, labels, projects, pull requests
> - [foxtrot54 PR #1](https://github.com/intel-agency/workflow-orchestration-queue-foxtrot54/pull/1) — all review comments (Codex + Gemini)
> - Local template files: `.github/.labels.json`, `orchestrator-agent.yml`, `orchestrator-agent-prompt.md`, `import-labels.ps1`, `ai-dynamic-workflows.md`
>
> **Date:** 2026-03-21

---

## Issue Summary

| # | Issue | Severity | Location | Category | Status |
|---|-------|----------|----------|----------|--------|
| 1 | `issues: labeled` trigger is commented out in workflow YAML | **P0 – Blocker** | `.github/workflows/orchestrator-agent.yml` | Orchestrator Workflow | Complete |
| 2 | Template `.labels.json` missing all `agent:*` and workflow labels | **P0 – Blocker** | `.github/.labels.json` | Labels / Template | Complete |
| 3 | No PR created in yankee89-b despite 1h12m orchestrator run | **P1 – Critical** | yankee89-b repo | Project Setup Workflow | Complete |
| 4 | No GitHub Project created in yankee89-b | **P1 – Critical** | yankee89-b repo | Project Setup Workflow | Complete |
| 5 | Label set incomplete in yankee89-b (17 vs 24 needed) | **P1 – Critical** | yankee89-b labels | Labels | Complete |
| 6 | Sentinel claim markers block reclaim after restart (30-min stale timeout) | **P1 – Critical** | `src/osapow/sentinel/orchestrator.py` | Orchestrator Code | Deferred |
| 7 | `SENTINEL_BOT_LOGIN` not validated at startup | **P1 – Critical** | `src/osapow/sentinel/orchestrator.py` | Orchestrator Code | Deferred |
| 8 | Incomplete label cleanup during requeue | **P2 – Medium** | `src/osapow/queue/github_queue.py` | Queue / Labels | Deferred |
| 9 | `GITHUB_TOKEN` not validated in notifier `create_app()` | **P2 – Medium** | `src/osapow/notifier/service.py` | Notifier Service | Deferred |
| 10 | Docker COPY order breaks editable install | **P2 – Medium** | `Dockerfile` | Infrastructure | Complete |
| 11 | Healthcheck uses `curl` instead of Python | **P2 – Medium** | `docker-compose.yml` | Infrastructure | Complete |
| 12 | `verify_signature()` silent on missing WEBHOOK_SECRET | **P2 – Medium** | `src/osapow/notifier/service.py` | Security | Deferred |
| 13 | Missing `issue_comment.created` action handling | **P2 – Medium** | `src/osapow/notifier/service.py` | Webhook Events | Deferred |
| 14 | Missing `pull_request_review` event support | **P2 – Medium** | `src/osapow/notifier/service.py` | Webhook Events | Deferred |
| 15 | `pyproject.toml` entry point uses async — needs sync wrapper | **P2 – Medium** | `pyproject.toml` | Packaging | Deferred |
| 16 | Traycerai bot edits trigger redundant orchestrator runs | **P3 – Low** | yankee89-b actions | Workflow Triggering | Complete |
| 17 | `.labels.json` URLs point to `nam20485/AgentAsAService` (stale source) | **P3 – Low** | `.github/.labels.json` | Template Hygiene | Complete |
| 18 | Concurrent delegation artificially limited to 2 in orchestrator prompt | **P1 – Critical** | `.opencode/agents/orchestrator.md`, `AGENTS.md` | Orchestrator Prompt | Complete |
| 19 | GitHub Project creation blocked — missing `project` OAuth scope | **P1 – Critical** | `orchestrator-agent.yml` permissions + PAT | Permissions | Complete |
| 20 | Agent incorrectly assumes project is .NET-based | **P2 – Medium** | `create-project-structure` dynamic workflow | Workflow Definition | Complete |
| 21 | Orchestrator idle-kill exits code 0, masking failures; no SIGKILL escalation | **P1 – Critical** | `scripts/devcontainer-opencode.sh` | Watchdog / CI | Complete |
| 22 | Watchdog race condition — premature idle-kill during active subagent work | **P1 – Critical** | `scripts/devcontainer-opencode.sh` | Watchdog | Complete |

---

## Detailed Issues & Proposed Solutions

---

### Issue 1: `issues: labeled` trigger is commented out in workflow YAML

**Status:** Complete

**Remarks:**

I added this already. Verify and mark completed. Add a condition to run a "skip" job which outputs the matching event and event data and explains it is explicitly ignored so the orchestration agent will skip running. We can add ignored conditions here cumulatively to the if: statement for cases we want to skip running the orchestration agent.

**Location:** `.github/workflows/orchestrator-agent.yml`, line 4

**Description:**
The orchestrator workflow only triggers on `issues: [opened]`. The `labeled` event type is commented out. However, the orchestrator prompt's match clauses rely heavily on `labeled` events:

- `case (action = labeled && labels contains: "implementation:ready" && title contains: "Complete Implementation")` — drives the Epic cascade
- `case (action = labeled && labels contains: "implementation:ready" && title contains: "Epic")` — drives Epic implementation
- `case (action = labeled && labels contains: "implementation:complete" && title contains: "Epic")` — drives next-Epic creation

**Impact:** The entire self-bootstrapping cascade (Epic creation → Epic implementation → next Epic) **cannot function**. The orchestrator can only react to issue opens and workflow_run completions.

**Proposed Solutions:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A (Recommended)** | Uncomment `labeled` in the issues trigger: `types: [opened, labeled]` | Enables full cascade; minimal change | May trigger on unrelated label additions; needs guard logic in prompt |
| B | Add a separate workflow for label events with its own filter | Separation of concerns | More files to maintain; duplicates infra |
| C | Switch to `issue_comment` dispatch model (agent posts command comments) | Avoids label-trigger noise | Requires rewriting all prompt clauses; bigger refactor |

**Recommended fix:**

```yaml
on:
  issues:
    types: [opened, labeled]
```

Add a condition in the job to skip runs for labels that aren't workflow-relevant (e.g., only proceed if the label is `implementation:ready` or `implementation:complete`).

---

### Issue 2: Template `.labels.json` missing all `agent:*` and workflow labels

**Status:** Complete

**Remarks:**

Implement A as recommended. Additionally add more prevalent directions with the path to the .labels.json file to reduce the probability of agents missing it.

**Location:** `.github/.labels.json`

**Description:**
The template's labels file is a snapshot from `nam20485/AgentAsAService` and contains only 15 labels (GitHub defaults + `assigned`, `state:*`, `type:enhancement`). It is missing the OS-APOW workflow labels that the orchestrator state machine depends on:

**Missing labels:**
- `agent:queued` — Tasks waiting for agent
- `agent:in-progress` — Tasks being processed by agent
- `agent:success` — Successfully completed tasks
- `agent:error` — Tasks that failed
- `agent:infra-failure` — Infrastructure failures
- `agent:stalled-budget` — Budget exceeded (deferred)
- `implementation:complete` — Marks completed epics
- `epic` — Epic-level issues
- `story` — Story-level issues

**Evidence:** foxtrot54 repo has 24 labels (agent added them during project-setup). yankee89-b has only 17 (agent did NOT add them → broken state machine).

**Proposed Solutions:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A (Recommended)** | Add all required labels to `.github/.labels.json` in the template | Every new repo starts correct; single source of truth | Must keep in sync with orchestrator prompt |
| B | Have `import-labels.ps1` merge from a second "workflow-labels.json" file | Separates base labels from workflow labels | Two files to manage |
| C | Have the project-setup workflow create labels via `gh label create` on the fly | No template change needed | Non-deterministic; varies per run |

**Recommended fix:** Add the following entries to `.github/.labels.json`:

```json
{"name": "agent:queued",       "color": "0e8a16", "description": "Tasks waiting for agent"},
{"name": "agent:in-progress",  "color": "fbca04", "description": "Tasks being processed by agent"},
{"name": "agent:success",      "color": "0e8a16", "description": "Successfully completed tasks"},
{"name": "agent:error",        "color": "d73a4a", "description": "Tasks that failed"},
{"name": "agent:infra-failure","color": "b60205", "description": "Infrastructure failures"},
{"name": "agent:stalled-budget","color": "e99695","description": "Budget limit reached"},
{"name": "implementation:complete","color":"0e8a16","description":"Implementation completed"},
{"name": "epic",               "color": "3E4B9E", "description": "Epic-level issues"},
{"name": "story",              "color": "7057ff", "description": "Story-level issues"}
```

Also remove the stale `id`, `node_id`, and `url` fields that point to `nam20485/AgentAsAService` — `import-labels.ps1` only needs `name`, `color`, and `description`.

---

### Issue 3: No PR created in yankee89-b despite 1h12m orchestrator run

**Status:** Complete

**Remarks:**

Implement A as recommended.

**Location:** yankee89-b repository — 0 open/closed PRs

**Description:**
The orchestrator-agent #2 ran for 1h 12m 47s and completed successfully, but the repo has 0 pull requests. The workflow plan specifies that `init-existing-repository` (Assignment 1) should create a `dynamic-workflow-project-setup` branch and a PR.

The orchestrator ran due to the `workflow_run` trigger (prebuild devcontainer completed), entered the `project-setup` dynamic workflow, but the agent appears to have only produced a workflow plan document (`plan_docs/workflow-plan.md`) without proceeding to actual repo initialization.

**Proposed Solutions:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A (Recommended)** | Fix the project-setup workflow to explicitly create the branch and PR as its first action, before proceeding to planning docs | Ensures critical infra is created early | Requires workflow script update |
| B | Add pre-flight validation in orchestrator that checks for branch/PR existence after each assignment | Catches failures; enables retry | More complex; post-hoc |
| C | Make `init-existing-repository` a mandatory non-skippable step with explicit failure if PR creation fails | Hard guarantee | May block other assignments |

**Root cause hypothesis:** The agent created the workflow plan but either (a) hit an error during PR creation that it silently swallowed, or (b) the `project-setup` workflow's `init-existing-repository` assignment was never reached because the orchestrator interpreted the `workflow_run` event data and stopped after the planning step.

**Recommended:** Investigate the full orchestrator agent log (requires authenticated access to Actions run #2). Also ensure the project-setup workflow has explicit "create PR" steps with error handling that surfaces failures.

---

### Issue 4: No GitHub Project created in yankee89-b

**Status:** Complete

**Remarks:**

trigger-project-setup.ps1 I commented out because the timing didn't work. At the end of create-repo-from-plan-docs.ps1 the docker and devcontainer images haven't had time to build yet so orchestration doesn't work. It just ends up calling orchestrate-agent workflow which errors out. Create the create-project.ps1 script but after that only add directions in the existing workflow explaining how to use it and then increase the visibility of the directions to use it to create the project in order to reduce the possibility it's missed.

**Location:** yankee89-b repository — 0 projects

**Description:**
The workflow plan's Assignment 1 (`init-existing-repository`) specifies creating a GitHub Project (Board template) linked to the repository with columns: Not Started, In Progress, In Review, Done. No project exists.

Contrast with foxtrot54 which successfully created a project: "workflow-orchestration-queue-foxtrot54" (org project #6).

**Proposed Solutions:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A (Recommended)** | Add project creation as a scripted step in `trigger-project-setup.ps1` or a new `create-project.ps1` script | Deterministic; runs outside agent | Requires API permissions (org:project scope) |
| B | Keep it as an agent task but add explicit retry + validation | Agent handles it; less scripting | Subject to agent hallucination/failure |
| C | Make project creation a separate workflow step (GitHub Action) that runs before the orchestrator | Guaranteed by CI | More workflow complexity |

**Recommended:** Create a `scripts/create-project.ps1` that uses `gh project create` and `gh project link` with proper error handling. Call it from `trigger-project-setup.ps1`.

---

### Issue 5: Label set incomplete in yankee89-b (17 vs 24 needed)

**Status:** Complete


**Remarks:** Issue 2 fix will be sufficient, as explained.

**Location:** yankee89-b labels page

**Description:**
yankee89-b has 17 labels. foxtrot54 has 24 labels. The difference includes the `agent:*` state machine labels and `epic`/`story` taxonomy labels. The orchestrator cannot transition issues through the state machine without these labels.

**Current yankee89-b labels (17):** `assigned`, `assigned:copilot`, `bug`, `documentation`, `duplicate`, `enhancement`, `good first issue`, `help wanted`, `implementation:ready`, `invalid`, `planning`, `question`, `state`, `state:in-progress`, `state:planning`, `type:enhancement`, `wontfix`

**Missing (needed):** `agent:queued`, `agent:in-progress`, `agent:success`, `agent:error`, `agent:infra-failure`, `epic`, `story`

**This is a direct consequence of Issue 2** (template `.labels.json` incomplete). See Issue 2 for fix.

**Additional fix needed for yankee89-b specifically:** Run `import-labels.ps1` against the repo after updating `.labels.json`, or manually create the missing labels.

---

### Issue 6: Sentinel claim markers block reclaim after restart

**Status:** Deferred

**Remarks:**

Leave not started — this will be resolved in the implementation phase (which hasn't started yet).

**Location:** `src/osapow/sentinel/orchestrator.py` (foxtrot54 codebase, produced by project-setup)

**Description:**
Per Codex review: `_cleanup()` now requeues the active task back to `agent:queued` on shutdown, but `GitHubQueue.claim_task()` still treats another sentinel's `<!-- sentinel-claim: ... -->` comment as authoritative until `claim_stale_timeout_secs` expires (30 minutes by default). Because `main()` generates a new sentinel ID on every restart, the replacement process will refuse to reclaim the just-requeued task for up to 30 minutes.

**Proposed Solutions:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A (Recommended)** | On shutdown, delete the sentinel claim comment (or edit it to mark it expired) in addition to requeuing | Clean state on restart | Extra API call during shutdown |
| B | Allow sentinels to claim tasks even with existing claim markers if the task has `agent:queued` label | Faster recovery | Risk of dual-claim if cleanup races |
| C | Use a persistent sentinel ID (stored in a file or env var) so restarts reuse the same ID | Avoids the problem entirely | Adds state management complexity |

---

### Issue 7: `SENTINEL_BOT_LOGIN` not validated at startup

**Status:** Deferred


**Remarks:**

Leave not started — this will be resolved in the implementation phase (which hasn't started yet).

**Location:** `src/osapow/sentinel/orchestrator.py`, `main()` function

**Description:**
Per Codex review: `main()` only validates `GITHUB_TOKEN`, `GITHUB_ORG`, and `GITHUB_REPO` before constructing the orchestrator. If `SENTINEL_BOT_LOGIN` is blank, `GitHubQueue.claim_task()` skips the entire assign-and-verify branch (`if bot_login:`), allowing multiple sentinel processes to label-claim and execute the same queued issue in parallel.

**Proposed Solutions:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A (Recommended)** | Add `SENTINEL_BOT_LOGIN` to the required env var check and `sys.exit(1)` if missing | Fail-fast; prevents silent dual-execution | Breaking change if some deployments don't set it |
| B | Default to the authenticated user's login via `gh api /user` | Auto-discovers; no config needed | Extra API call; may fail |

---

### Issue 8: Incomplete label cleanup during requeue

**Status:** Deferred

**Remarks:**

Leave not started — this will be resolved in the implementation phase (which hasn't started yet).

**Location:** `src/osapow/queue/github_queue.py`, `requeue_with_feedback()`

**Description:**
Per Codex review: `handle_github_webhook()` sends retries from `agent:reconciling`, `agent:infra-failure`, and `agent:stalled-budget` into `requeue_with_feedback()`, but this helper only deletes `agent:success`, `agent:error`, and `agent:in-progress`. Requeueing from any of the other states leaves `agent:queued` alongside the old terminal label, creating contradictory state.

**Proposed Solutions:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A (Recommended)** | Add all `agent:*` labels to the cleanup list in `requeue_with_feedback()` | Complete cleanup; consistent state | None significant |
| B | Create a `remove_all_agent_labels()` helper called by all state transitions | DRY; used everywhere | Slightly more refactoring |

---

### Issue 9: `GITHUB_TOKEN` not validated in notifier `create_app()`

**Status:** Deferred

**Remarks:**

Leave not started — this will be resolved in the implementation phase (which hasn't started yet).

**Location:** `src/osapow/notifier/service.py`, `create_app()` function

**Description:**
Per Codex review: `create_app()` always constructs `GitHubQueue` from `os.environ.get("GITHUB_TOKEN", "")`, and the health endpoint stays green even when that value is empty. The notifier accepts and verifies webhooks but every later call to `add_to_queue()` / `requeue_with_feedback()` fails at runtime.

**Recommended fix:** Validate `GITHUB_TOKEN` is non-empty at app startup; return a degraded health status if not configured.

---

### Issue 10: Docker COPY order breaks editable install

**Status:** Complete

**Remarks:**

Implement recommended solution.

**Location:** `Dockerfile`

**Description:**
Per Codex review: `COPY src/ ./src/` must come before `uv pip install -e .` for the editable install to find the package source.

**Recommended fix:** Reorder Dockerfile to COPY source before install.

---

### Issue 11: Healthcheck uses `curl` instead of Python

**Status:** Complete

**Remarks:**

Implement recommended solution.

**Location:** `docker-compose.yml`

**Description:**
Per Codex review: The container doesn't include `curl`. Use a Python-based urllib healthcheck instead: `python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"`.

**Recommended fix:** Replace `curl` healthcheck with Python-based check.

---

### Issue 12: `verify_signature()` silent on missing WEBHOOK_SECRET

**Status:** Deferred

**Remarks:**

Leave not started — this will be resolved in the implementation phase (which hasn't started yet).

**Location:** `src/osapow/notifier/service.py`

**Description:**
Per Codex review: If `WEBHOOK_SECRET` is not configured, signature verification silently passes, allowing any payload to be accepted.

**Recommended fix:** Raise an error or return 500 if `WEBHOOK_SECRET` is not set when a webhook arrives with an `X-Hub-Signature-256` header.

---

### Issue 13: Missing `issue_comment.created` action handling

**Status:** Deferred

**Remarks:**

Leave not started — this isn't needed yet. What action would we need for issue_comment.created?

**Location:** `src/osapow/notifier/service.py`

**Description:**
Per Codex review: The webhook handler didn't handle the `created` action for `issue_comment` events, only `edited`.

**Recommended fix:** Add `created` to the handled actions for `issue_comment`.

---

### Issue 14: Missing `pull_request_review` event support

**Status:** Deferred

**Remarks:**

Leave not started — this isn't needed yet. What action would we need for pull_request_review?

**Location:** `src/osapow/notifier/service.py`

**Description:**
Per Codex review: `pull_request_review` events (submitted, edited) were not handled by the webhook receiver.

**Recommended fix:** Add `pull_request_review` event type handling.

---

### Issue 15: `pyproject.toml` entry point uses async — needs sync wrapper

**Status:** Deferred

**Remarks:**

Leave not started — this isn't needed yet.

**Location:** `pyproject.toml`

**Description:**
Per Codex review: Console script entry points must be synchronous functions. The entry point was pointing to an async function.

**Recommended fix:** Create a `run_main()` synchronous wrapper that calls `asyncio.run(main())` and point the entry point there.

---

### Issue 16: Traycerai bot edits trigger redundant orchestrator runs

**Status:** Complete

**Remarks:**

Add this case to the "skip" job explained in Issue 1.

**Location:** yankee89-b Actions tab

**Description:**
Orchestrator-agent runs #3-#6 were triggered by `traycerai` bot editing its comment on Issue #1. Each edit re-triggers the `issue_comment` workflow (if enabled), causing redundant runs.

**Proposed Solutions:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A (Recommended)** | Add `if: github.actor != 'traycerai[bot]'` condition to the workflow job | Prevents bot loops | Must maintain actor exclusion list |
| B | Ignore `edited` events for `issue_comment`, only react to `created` | Reduces noise | May miss legitimate edits |

---

### Issue 17: `.labels.json` URLs point to `nam20485/AgentAsAService`

**Status:** Complete

**Remarks:**

Fix.

**Location:** `.github/.labels.json`

**Description:**
The labels file was exported from a different repo (`nam20485/AgentAsAService`). The `id`, `node_id`, and `url` fields reference that repo. While `import-labels.ps1` only uses `name`, `color`, and `description`, the stale metadata is confusing.

**Recommended fix:** Strip `id`, `node_id`, and `url` fields from `.labels.json`, keeping only `name`, `color`, and `description`.

---

### Issue 18: Concurrent delegation artificially limited to 2 in orchestrator prompt

**Status:** Complete
**Remarks:** Fixed in commit `bc4126c`. Validated in delta86 logs (model still echoes old behavior on pre-fix repos seeded before the fix).

Remove depth constraints as well. Leave no artificial constraints on orchestrator's delegations.

**Location:** `.opencode/agents/orchestrator.md`, `AGENTS.md`

**Description:**
The orchestrator agent was explicitly told to limit concurrent delegations to 2 in three places:
1. `.opencode/agents/orchestrator.md` step 5: `Build delegation tree (≤2 concurrent)`
2. `.opencode/agents/orchestrator.md` Delegation Depth Management: `Concurrent delegation limit: Maximum 2 concurrent delegations`
3. `AGENTS.md` coding conventions: `Keep orchestrator delegation-depth ≤2`

This is a prompt-level constraint only — opencode supports parallel Task tool calls natively with no hard limit. The model was obeying the instruction literally, serializing independent tasks unnecessarily.

Log evidence (delta86):

```
Let me delegate these tasks. I can delegate up to 2 tasks concurrently.
• Update .labels.json with agent labels  →  Developer Agent
• Create GitHub Project for tracking     →  Github-Expert Agent
```

**Fix applied:** Removed all three concurrent-limit references. The depth limit (max 2 nesting levels) is preserved since that controls nesting depth, not parallelism.

---

### Issue 19: GitHub Project creation blocked — missing `project` OAuth scope

**Status:** Complete
**Remarks:** Fixed in commit `7f835c0`. `projects: write` added to workflow permissions; `GH_ORCHESTRATION_AGENT_TOKEN` PAT must also have the `project` scope (verify via `gh auth refresh -h github.com -s project`).

I believe the GH_ORCHESTRATION_AGENT_TOKEN already has this scope. Verify that it's used in this process.

**Location:** `.github/workflows/orchestrator-agent.yml` permissions block; `GH_ORCHESTRATION_AGENT_TOKEN` PAT settings

**Description:**
GitHub Projects V2 uses the GraphQL API, which requires the `project` OAuth scope. The workflow permissions block was missing `projects: write`. Additionally, the built-in `GITHUB_TOKEN` cannot manage Projects V2 at all — only a classic PAT with the `project` scope can.

Log evidence (delta86):

```
Github-Expert: "GITHUB_TOKEN doesn't have permission to create projects"
```

**Fix applied:** Added `projects: write` to the `orchestrator-agent.yml` permissions block.

---

### Issue 20: Agent incorrectly assumes project is .NET-based

**Status:** Complete
**Remarks:**

Fix.

**Location:** `create-project-structure` dynamic workflow definition (remote: `nam20485/agent-instructions`)

**Description:**
The `create-project-structure` assignment template appears to include .NET-specific examples (`.sln`, `.csproj` structure). When the orchestrator delegates this assignment for a Python/FastAPI project, subagents have explicitly noted the mismatch:

Log evidence:

```
• Execute create-project-structure  Backend-Developer Agent
Now executing Assignment 3: create-project-structure. This requires Python adaptation
as the assignment is designed for .NET.
```

This is also flagged as Open Question 6.1 in `plan_docs/workflow-plan.md`:
> *"The planning documents describe a Python/FastAPI system, but `create-project-structure` assignment mentions .NET solution structure in its example."*

**Proposed Solutions:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A (Recommended)** | Update the `create-project-structure` dynamic workflow in `agent-instructions` repo to be tech-stack-agnostic, reading the tech stack from planning docs | Correct for all future repos | Requires updating remote canonical workflow |
| B | Add a note in the assignment prompt that the .NET example is illustrative and agents must adapt to the actual tech stack | Low effort | Relies on agent correctly interpreting the note |
| C | Create a separate `create-project-structure-python` workflow variant | Tailored | Proliferates workflow variants |

---

### Issue 21: Orchestrator idle-kill exits code 0, masking failures; no SIGKILL escalation

**Status:** Complete
**Remarks:** Fixed in commit `cafd0b0`. End-to-end validated in yankee89-a (run 23352743760, exit code 0, 7/7 assignments completed).

**Location:** `scripts/devcontainer-opencode.sh` (watchdog / wrapper logic)

**Description:**
Three related infrastructure bugs:
1. **Exit code masking:** Idle-killed runs exited 0, making GitHub Actions report "succeeded" despite incomplete work.
2. **`::warning::` → `::error::`:** Idle kills and hard-ceiling kills are failures — were annotated as `::warning::` so they didn't surface prominently in the workflow summary.
3. **No SIGTERM→SIGKILL escalation:** After sending SIGTERM, the wrapper didn't follow up with SIGKILL if the process failed to exit, allowing zombie/hung processes.

Log evidence (india42):

```
Warning: opencode idle for 15m (no output from client or server); terminating
opencode exit code: 143                     ← SIGTERM received
Notice: devcontainer-opencode.sh exited with code: 0   ← BUG: should be non-zero
```

**Fix applied:** (a) Wrapper now exits 1 when watchdog fires. (b) Idle/ceiling kills annotated as `::error::`. (c) Sends SIGKILL after 10s if process hasn't exited following SIGTERM.

---

### Issue 22: Watchdog race condition — premature idle-kill during active subagent work

**Status:** Complete
**Remarks:** Fixed in commit `5d89c97`. End-to-end validated in yankee89-a (run 23352743760): watchdog survived 225s and 292s client-idle periods across 7 delegations without premature kills.

**Location:** `scripts/devcontainer-opencode.sh` (watchdog loop)

**Description:**
Race condition in the watchdog loop. When checking server activity via `/proc/<pid>/io write_bytes`, a single 30-second interval where `write_bytes` didn't change caused `server_io_active` to flip to `false`. The fallback used `server_log_idle` (mtime of `/tmp/opencode-serve.log`), which only reflected server **startup** time — not last activity. So `server_idle` jumped from 0 to the full runtime (~950s), immediately triggering the 15m idle kill even though the server was actively working 30 seconds earlier.

Log evidence (india42 — buggy behavior):

```
11:44:44 [watchdog] client output idle 886s, server I/O active (write_bytes=146317312) — subagent likely running
11:45:14 Warning: opencode idle for 15m (no output from client or server); terminating
```

Server I/O was active at 11:44:44. One 30s check later, write_bytes didn't change → `server_idle` jumped to ~952s → killed prematurely.

**Why golf43 succeeded (golden run):** Same code, same template. golf43 ran 1h 4m and completed all tasks. It never had a 30-second I/O gap at a moment when client output idle exceeded 15m — timing-dependent race condition.

**Fix applied:** Track `_last_server_io_time` (timestamp of last observed I/O activity) instead of falling back to server log mtime. The process is only killed when server I/O has been truly inactive for a full 15 minutes since it was last observed.

---

## Priority Fix Order

### Phase 1 — Unblock the orchestrator cascade (P0)

1. **Uncomment `labeled` trigger** in `orchestrator-agent.yml` (Issue 1)
2. **Add all required labels** to `.github/.labels.json` (Issue 2 + 5)
3. **Clean up stale metadata** in `.labels.json` (Issue 17)

### Phase 2 — Fix project-setup reliability (P1)

1. **Investigate yankee89-b orchestrator logs** to determine why no PR/project was created (Issue 3 + 4)
2. **Script project creation** as a deterministic step (Issue 4)
3. **Add bot-actor exclusion** to prevent traycerai edit loops (Issue 16)

### Phase 3 — Harden sentinel/notifier (P1-P2, apply to generated code)

1. **Validate `SENTINEL_BOT_LOGIN`** at startup (Issue 7)
2. **Delete claim markers** on shutdown (Issue 6)
3. **Complete label cleanup** in `requeue_with_feedback()` (Issue 8)
4. **Validate `GITHUB_TOKEN`** in notifier startup (Issue 9)
5. **Fix `WEBHOOK_SECRET` validation** (Issue 12)

### Phase 4 — Infrastructure & packaging (P2)

1. **Fix Docker COPY order** (Issue 10)
2. **Fix healthcheck** (Issue 11)
3. **Fix entry point** (Issue 15)
4. **Add missing event handlers** (Issues 13, 14)

### Already Fixed (historical record)

- **Issue 18** — Concurrent delegation limit removed from orchestrator prompt (`bc4126c`)
- **Issue 19** — `projects: write` added to workflow permissions + PAT scope clarified (`7f835c0`)
- **Issue 21** — Watchdog exit-code masking + `::error::` annotation + SIGKILL escalation (`cafd0b0`)
- **Issue 22** — Watchdog race condition fixed via `_last_server_io_time` tracking (`5d89c97`)

### Issue 20 — Backlog (open)

- **Issue 20** — Investigate and fix `.NET` assumptions in `create-project-structure` dynamic workflow
