# Implementation Plan — Workflow Issues Remediation

> **Source:** `docs/workflow-issues-and-fixes.md` (with owner remarks applied 2026-03-21)
>
> **Scope:** Template repo `ai-new-workflow-app-template` only. Issues targeting generated code (sentinel, notifier, queue) are deferred to the implementation phase.

---

## Decision Summary

Of 22 issues, the owner's remarks produced the following disposition:

| Disposition | Count | Issues |
|---|---|---|
| **Implement now** | 8 | 1, 2, 3, 4, 10, 11, 17, 20 |
| **Verify & mark complete** | 3 | 1 (partial), 18, 19 |
| **Covered by another fix** | 2 | 5 (by #2), 16 (by #1 skip job) |
| **Defer to implementation phase** | 6 | 6, 7, 8, 9, 12, 15 |
| **Defer — not needed yet** | 2 | 13, 14 |
| **Already complete** | 4 | 18, 19, 21, 22 |

---

## Implementation Tasks

### Task 1 — Verify `labeled` trigger and add skip job (Issue 1)

**Status in doc:** Owner says "I added this already. Verify and mark completed."

**Actions:**

1. **Verify** that `orchestrator-agent.yml` has `types: [opened, labeled]` on the `issues:` trigger.
2. **Add a skip job** that runs when the event matches conditions we want to explicitly ignore. The skip job should:
   - Output the matching event name and event data
   - Print a message explaining why the orchestration agent is skipping this event
   - Use a cumulative `if:` condition so future ignored cases can be added
3. **Add `traycerai[bot]` actor exclusion** to the skip condition (Issue 16's fix lives here).
4. Mark Issue 1 status as **Complete** in the doc.

**Files:**

- `.github/workflows/orchestrator-agent.yml` — verify trigger, add skip job

---

### Task 2 — Add required labels to `.labels.json` + cleanup (Issues 2, 5, 17)

**Owner direction:** "Implement A. Additionally add more prevalent directions with the path to the .labels.json file to reduce the probability of agents missing it."

**Actions:**

1. **Add** the 9 missing labels to `.github/.labels.json`:
   - `agent:queued`, `agent:in-progress`, `agent:success`, `agent:error`, `agent:infra-failure`, `agent:stalled-budget`
   - `implementation:complete`, `epic`, `story`
2. **Strip** stale `id`, `node_id`, and `url` fields from all existing entries (Issue 17).
3. **Add prominent directions** referencing the `.github/.labels.json` path in:
   - `AGENTS.md` — add a note in the project conventions section
   - Orchestrator prompt or dynamic workflow instructions — reference the label file path so agents know where to find/verify labels
4. Mark Issues 2, 5, 17 as **Complete** in the doc.

**Files:**

- `.github/.labels.json` — add labels, strip stale fields
- `AGENTS.md` — add label file reference
- Potentially `orchestrator-agent-prompt.md` or workflow docs — add label path directions

---

### Task 3 — Fix project-setup workflow to create branch + PR reliably (Issue 3)

**Owner direction:** "Implement A as recommended."

**Actions:**

1. Update the `project-setup` dynamic workflow (or the `init-existing-repository` assignment) to explicitly create the branch and PR as its first concrete action, with error handling that surfaces failures.
2. Ensure the orchestrator logs contain clear success/failure messages for PR creation.

**Files:**

- Dynamic workflow definitions (remote `nam20485/agent-instructions` or local overrides)
- Potentially `scripts/` if a helper script is needed

**Note:** This may require changes in the `agent-instructions` repo. If so, document what needs to change there and flag it.

---

### Task 4 — Create `create-project.ps1` script + add directions (Issue 4)

**Owner direction:** "Create the create-project.ps1 script but after that only add directions in the existing workflow explaining how to use it and then increase the visibility of the directions to use it to create the project in order to reduce the possibility it's missed."

**Context:** `trigger-project-setup.ps1` was commented out because docker/devcontainer images haven't built yet when it runs. The orchestration agent errors out.

**Actions:**

1. **Create** `scripts/create-project.ps1` that:
   - Uses `gh project create` to create a Board-template project
   - Uses `gh project link` to link it to the repository
   - Includes proper error handling and output
   - Can be run standalone by a human or future automation
2. **Do NOT** auto-call it from `trigger-project-setup.ps1` or the orchestration workflow.
~3. **Add prominent directions** in multiple locations explaining:
   - When to run `create-project.ps1` (after devcontainer image is built and first orchestrator run completes)
   - How to run it (`./scripts/create-project.ps1 -Org <org> -Repo <repo>`)
4. Increase visibility of these directions in:
   - `AGENTS.md` or project README
   - The orchestrator prompt or workflow plan docs
   - The project-setup dynamic workflow instructions (so subagents know about it)
5. Mark Issue 4 as **Complete** in the doc.

**CHANGE: DONT ADD ANY EXTRA STEPS ANYWHERE ELSE. Just create the script and add directns to call it with how in the same spot where the project creation directions already exist (i.e. in the workfow assignemnt). Just add more visibility in or around that spot in the existing workflow assignment file. Add to Acceptance Criteria ormake more prominent if its already there.**

**Files:**

- `scripts/create-project.ps1` — new file
- `AGENTS.md` or README — add directions
- Dynamic workflow docs — add directions about manual project creation step

---

### Task 5 — Fix Docker COPY order (Issue 10)

**Owner direction:** "Implement recommended solution."

**Actions:**

1. Reorder Dockerfile so `COPY src/ ./src/` comes before `uv pip install -e .`.

**Files:**

- `Dockerfile` (template)

**Note:** This file may not exist in the template repo directly (it's generated by project-setup). If so, the fix goes into the `create-project-structure` dynamic workflow instructions. Document accordingly.

---

### Task 6 — Fix healthcheck to use Python instead of curl (Issue 11)

**Owner direction:** "Implement recommended solution."

**Actions:**

1. Replace `curl`-based healthcheck in `docker-compose.yml` with:

   ```yaml
   healthcheck:
     test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
   ```

**Files:**

- `docker-compose.yml` (template)

**Note:** Same as Task 5 — may be in generated code. If template doesn't contain this file, document the fix for the `create-project-structure` workflow.

---

### Task 7 — Fix .NET assumption in `create-project-structure` (Issue 20)

**Owner direction:** "Fix."

**Actions:**

1. Update the `create-project-structure` dynamic workflow definition to be tech-stack-agnostic.
2. The assignment should read the tech stack from planning docs / app plan rather than assuming .NET.
3. Remove or replace `.sln`/`.csproj` examples with generic or multi-stack examples.

**Files:**

- Remote: `nam20485/agent-instructions` repo — `create-project-structure` assignment
- If local overrides exist, update those too

**Note:** This is in a remote repo. Document the exact changes needed. If we can't push there, create a local override or document as a follow-up.

---

### Task 8 — Verify Issue 18 depth constraints removed (Issue 18)

**Owner direction:** "Remove depth constraints as well. Leave no artificial constraints on orchestrator's delegations."

**Actions:**

1. **Verify** that commit `bc4126c` already removed all concurrent-limit references.
2. **Additionally remove** any remaining depth constraints (e.g., "max 2 nesting levels", "delegation-depth ≤2") from:
   - `.opencode/agents/orchestrator.md`
   - `AGENTS.md`
3. Update Issue 18 remarks to reflect this additional change.

**Files:**

- `.opencode/agents/orchestrator.md`
- `AGENTS.md`

---

### Task 9 — Verify Issue 19 PAT scope usage (Issue 19)

**Owner direction:** "I believe the GH_ORCHESTRATION_AGENT_TOKEN already has this scope. Verify that it's used in this process."

**Actions:**

1. **Trace** the token flow: confirm `GH_ORCHESTRATION_AGENT_TOKEN` is passed through `orchestrator-agent.yml` → `devcontainer-opencode.sh` → `run_opencode_prompt.sh` → opencode process → `gh project create` calls.
2. **Verify** the PAT has the `project` scope by checking the scope validation in `run_opencode_prompt.sh` (which already checks `project` in `_required_scopes`).
3. Document findings in Issue 19 remarks.

**Files:**

- Read-only verification (no changes expected)

---

## Sequencing

```
Task 1  ─── Verify labeled trigger + add skip job
   │
Task 2  ─── Add labels to .labels.json + cleanup + directions
   │
Task 8  ─── Verify/remove depth constraints (Issue 18)
Task 9  ─── Verify PAT scope flow (Issue 19)
   │          (these two are independent verifications)
   │
Task 4  ─── Create create-project.ps1 + add directions (Issue 4)
   │
Task 3  ─── Fix project-setup PR creation (Issue 3)
   │          (depends on understanding current workflow)
   │
Task 5  ─── Fix Docker COPY order (Issue 10)
Task 6  ─── Fix healthcheck (Issue 11)
Task 7  ─── Fix .NET assumption (Issue 20)
            (these are independent of each other)
```

Tasks 1, 2, 8, 9 can proceed first (template repo changes). Tasks 3, 5, 6, 7 may require changes in remote repos or generated-code templates.

---

## Out of Scope (Deferred)

These issues are explicitly deferred per owner direction:

| Issue | Reason |
|---|---|
| 6 — Sentinel claim markers | Deferred to implementation phase |
| 7 — SENTINEL_BOT_LOGIN validation | Deferred to implementation phase |
| 8 — Incomplete label cleanup | Deferred to implementation phase |
| 9 — GITHUB_TOKEN notifier validation | Deferred to implementation phase |
| 12 — WEBHOOK_SECRET validation | Deferred to implementation phase |
| 13 — issue_comment.created handling | Not needed yet |
| 14 — pull_request_review support | Not needed yet |
| 15 — pyproject.toml async entry point | Not needed yet |

---

## Approval

- [ ] Plan approved — proceed with implementation
- [x] Plan approved with modifications (see below)
- [ ] Plan rejected — revise

**Modifications requested:**

See item 4. All other items are approved as presented.

For the external repos.

_(space for feedback)_
