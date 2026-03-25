# OS-APOW Plan Review

**Reviewer:** GitHub Copilot (Claude Opus 4.6)
**Date:** 2025-03-19
**Documents Reviewed:**

- OS-APOW Architecture Guide v3
- OS-APOW Development Plan v4
- OS-APOW Implementation Specification v1
- `orchestrator_sentinel.py` (reference implementation)
- `notifier_service.py` (reference implementation)
- `interactive-report.html` (presentation dashboard)

**Source Location:** `plan_docs/workflow-orchestration-queue/` (seeded from `nam20485/workflow-launch2`)

---

## Summary Verdict

The plan docs are substantially above average for AI-generated project plans. The architecture is sound, the phased rollout is realistic, and the ADRs reflect genuine engineering judgment. The main gaps are in the reference implementation code — race conditions in locking, missing features from the spec (heartbeats, cost guardrails, backoff), and model divergence between components. These are normal for a "scaffold" meant to be built out by agents, but they should be flagged as explicit TODO items so the AI doesn't assume they're done.

The biggest operational risk is one already encountered in production: **long-running subagent delegations look indistinguishable from hangs.** The heartbeat system described in the plan is the right fix, but it needs to be implemented at both layers — the inner opencode watchdog (already fixed in `run_opencode_prompt.sh`) and the outer sentinel heartbeat (specced but not coded).

---

## Strengths

### S-1: Clean 4-Pillar Architecture

The Ear/State/Brain/Hands decomposition maps cleanly to real separation of concerns. Each component has a single responsibility and a clear interface boundary. The naming is memorable and the metaphor holds under scrutiny.

**Ref:** Architecture Guide v3, §2 "System Level Diagram & Component Overview"

> **Remarks:**
>
> _[Your feedback here]_

---

### S-2: Shell-Bridge Decision (ADR 07)

Reusing `devcontainer-opencode.sh` instead of the Docker SDK is the right call. It guarantees environment parity between the AI agent and a human developer. The sentinel code correctly uses it. This avoids "Configuration Drift" and keeps the Python layer focused on logic/state.

**Ref:** Architecture Guide v3, §3 "ADR 07: Standardized Shell-Bridge Execution"

> **Remarks:**
>
> _[Your feedback here]_

---

### S-3: Polling-First Resiliency (ADR 08)

Webhooks-as-optimization rather than webhooks-as-requirement means the system self-heals on restart. If the server goes down during a GitHub event, the polling loop naturally reconciles on reboot. The `agent:reconciling` state for stale tasks is a nice touch that most plans skip.

**Ref:** Architecture Guide v3, §3 "ADR 08: Polling-First Resiliency Model"; Development Plan v4, §1 Principle 4

> **Remarks:**
>
> _[Your feedback here]_

---

### S-4: "Markdown as a Database"

Using GitHub Issues as the persistence layer gives you free audit trail, UI, permissions, notifications, and API. For the expected volume (single-digit concurrent tasks), this scales fine. Human intervention-via-commenting is a natural fit.

**Ref:** Architecture Guide v3, §2B "Work Queue (The Logic State)"; Development Plan v4, §1 Principle 2

> **Remarks:**
>
> _[Your feedback here]_

---

### S-5: Realistic Self-Bootstrapping Lifecycle

Phase 0→1 is manual seed, then the system builds its own Phase 2 and 3. This maps exactly to how the template repo + `project-setup` workflow already works. The "system builds itself" narrative is credible because Phase 1 is scoped small enough to be manually verifiable.

**Ref:** Development Plan v4, §6 "Infrastructure & Self-Bootstrapping Lifecycle"; Architecture Guide v3, §6

> **Remarks:**
>
> _[Your feedback here]_

---

### S-6: Thorough Security Model

HMAC webhook verification, ephemeral credentials, network isolation, credential scrubbing, resource constraints (2 CPUs / 4GB RAM). The plan covers the OWASP-relevant attack surfaces including prompt injection via spoofed webhooks.

**Ref:** Architecture Guide v3, §5 "Security, Authentication & Isolation"; Implementation Spec v1, §Containerization: Docker

> **Remarks:**
>
> _[Your feedback here]_

---

### S-7: Provider-Agnostic Interface (ADR 09)

The `ITaskQueue` ABC in the notifier code already demonstrates the Strategy Pattern. Swapping GitHub for Linear, Notion, or a SQL queue stays local to the interface implementation without touching orchestrator logic.

**Ref:** Architecture Guide v3, §3 "ADR 09: Provider-Agnostic Interface Layer"; `notifier_service.py` lines 23-35

> **Remarks:**
>
> _[Your feedback here]_

---

## Issues & Gotchas

### I-1: Divergent `WorkItem` Models Between Components

The sentinel defines `WorkItem` with `id, issue_number, source_url, context_body, target_repo_slug, task_type, status, node_id`. The notifier defines `WorkItem` with `provider_id, target_repo, item_type, content, raw_payload`. These are two separate Pydantic models with different field names, different enums (`TaskType` vs `WorkItemType`, `WorkItemStatus` with different values), and no shared base. They will drift immediately once both components evolve independently.

**Ref:** `orchestrator_sentinel.py` lines 28-47; `notifier_service.py` lines 18-34

**Recommendation:** Unify into a single shared `src/models/work_item.py`. Both sentinel and notifier import from there.

> **Remarks:**
>
> _[Your feedback here]_

---

### I-2: Race Condition in Task Claiming

The sentinel does label-remove → label-add → post comment as separate API calls. Between the delete of `agent:queued` and the add of `agent:in-progress`, a second sentinel instance could also succeed at deleting the same label and believe it has the lock. The plan says "use GitHub Assignees as a distributed lock," but the code doesn't implement the assign-then-verify pattern. There is no re-fetch and no assignee check after the claim attempt.

**Ref:** Development Plan v4, §3 Story 4 & §7 "Concurrency Collisions"; `orchestrator_sentinel.py` `claim_task()` method (lines ~130-155)

**Recommendation:** Implement: (1) attempt to assign yourself, (2) re-fetch the issue, (3) verify you're the assignee before proceeding. If not, abort claim gracefully.

> **Remarks:**
>
> _[Your feedback here]_

---

### I-3: No Jittered Exponential Backoff on Poller

The plan specifies "jittered exponential backoff" for rate limiting (Development Plan v4, §3 Story 2), but `run_forever()` uses a fixed `await asyncio.sleep(POLL_INTERVAL)` with a constant 60s interval. A 403 or 429 from GitHub will be retried every 60 seconds indefinitely, potentially getting the installation token permanently rate-limited.

**Ref:** Development Plan v4, §3 Story 2 "The Resilient Polling Engine"; `orchestrator_sentinel.py` `run_forever()` (line ~280)

**Recommendation:** Add exponential backoff with jitter on non-200 responses. Reset to base interval on successful poll.

> **Remarks:**
>
> _[Your feedback here]_

---

### I-4: `httpx.AsyncClient()` Created Per-Call

Both `fetch_queued_tasks()` and `claim_task()` create a new `async with httpx.AsyncClient()` on each invocation. This means a new TCP connection + TLS handshake for every API call. In a 60-second poll loop with multiple label mutations per task, this is wasteful and adds unnecessary latency.

**Ref:** `orchestrator_sentinel.py` lines ~95, ~130, ~160

**Recommendation:** Create `httpx.AsyncClient` once in `GitHubQueue.__init__()`, reuse it as a session-level client with connection pooling. Add an `async close()` method for graceful cleanup.

> **Remarks:**
>
> _[Your feedback here]_

---

### I-5: Hardcoded Secrets in Notifier Scaffold

`WEBHOOK_SECRET = b"your_webhook_secret_here"` and `GitHubIssuesQueue(token="YOUR_GITHUB_TOKEN")` are placeholder values inline in the source. Even though they're obviously fake, this pattern makes it easy to accidentally commit real values. The sentinel correctly uses `os.getenv()` for its secrets, but the notifier doesn't.

**Ref:** `notifier_service.py` lines 83, 77

**Recommendation:** Use `os.environ["WEBHOOK_SECRET"]` from the start. Crash at import time if not set, rather than silently running with placeholder values.

> **Remarks:**
>
> _[Your feedback here]_

---

### I-6: No Heartbeat Implementation

The plan specifies "post a Heartbeat comment every 5 minutes for tasks exceeding 5 minutes" (Development Plan v4, §3 Story 4). The sentinel processes tasks synchronously in `process_task()` and has no background heartbeat coroutine. Long-running `devcontainer-opencode.sh prompt` calls (which have been observed to take 15+ minutes during subagent delegation) will look dead to observers watching the GitHub issue.

**Ref:** Development Plan v4, §3 Story 4 "Automated Status Feedback"; Architecture Guide v3, §2C item 5 "Telemetry"

**Recommendation:** Run `process_task()` and a heartbeat poster as concurrent `asyncio.gather()` tasks. Cancel the heartbeat when the task completes.

> **Remarks:**
>
> _[Your feedback here]_

---

### I-7: Cost Guardrails Story Has No Implementation

Story 6 specifies monitoring a `credits_used` file and auto-stalling on budget exceeded. Neither the sentinel nor any referenced script implements this. Given the idle-timeout issue already observed in production, a runaway loop or hallucinating agent is a real operational risk.

**Ref:** Development Plan v4, §3 Story 6 "Cost Guardrails & Resource Safety"

**Recommendation:** At minimum, implement a token/cost counter that reads the opencode session summary after each prompt call and accumulates to a daily total. Stall with `agent:stalled-budget` on threshold breach.

> **Remarks:**
>
> _[Your feedback here]_

---

### I-8: Single-Repo Polling vs. Spec'd Cross-Repo Discovery

`GitHubQueue` is initialized with a single `org/repo` pair. The plan says the sentinel "scans the organization for issues" with the `agent:queued` label, implying cross-repo discovery. The code only searches one repo.

**Ref:** Architecture Guide v3, §2C "Polling Discovery"; `orchestrator_sentinel.py` `GitHubQueue.__init__()` (line ~88)

**Recommendation:** For multi-repo orchestration, use the GitHub Search API: `GET /search/issues?q=label:agent:queued+org:intel-agency` instead of per-repo issue listing.

> **Remarks:**
>
> _[Your feedback here]_

---

### I-9: Bare `except: pass` in `claim_task`

The label deletion in `claim_task()` has `except: pass` which silently swallows any exception — including network errors, auth failures, and HTTP 500s. A failed claim should be treated as "could not lock" and the task should be skipped, not silently continued into the `in-progress` state.

**Ref:** `orchestrator_sentinel.py` `claim_task()` method, label deletion block (~line 138)

**Recommendation:** Catch specific exceptions (`httpx.HTTPStatusError` for 404/410 on label-not-found). Let network and auth errors propagate or log-and-skip.

> **Remarks:**
>
> _[Your feedback here]_

---

### I-10: No Environment Reset Between Tasks

The Implementation Spec says the sentinel should issue `docker-compose down -v && docker-compose up --build` between distinct Epic tasks to guarantee a pristine environment. The `process_task()` method runs `up → start → prompt` with no teardown. State from one task bleeds into the next.

**Ref:** Implementation Spec v1, §Containerization: Docker Compose

**Recommendation:** Add a teardown step after `process_task()` completes (or before the next task starts). At minimum call `devcontainer-opencode.sh stop` between tasks; for full isolation, use `down`.

> **Remarks:**
>
> _[Your feedback here]_

---

## Improvement Recommendations

### R-1: Add Watchdog/Heartbeat Coroutine to Sentinel

Run `process_task()` and a heartbeat-poster as concurrent `asyncio.gather()` tasks. The heartbeat should post a status comment to the GitHub issue every 5 minutes with elapsed time and last known activity. Cancel the heartbeat when the task finishes.

This is critical given observed 15+ minute subagent delegation times that produce no visible output.

**Ref:** Development Plan v4, §3 Story 4

> **Remarks:**
>
> _[Your feedback here]_

---

### R-2: Implement Proper Distributed Locking

Use the assign-then-verify pattern: (1) attempt to assign the sentinel's bot account to the issue via the GitHub API, (2) re-fetch the issue, (3) verify the current assignee matches before proceeding. If assignment fails or was stolen, skip the task gracefully.

**Ref:** Architecture Guide v3, §2B "Concurrency Control"; Development Plan v4, §7

> **Remarks:**
>
> _[Your feedback here]_

---

### R-3: Unify the Data Model

Put `WorkItem`, `TaskType`, `WorkItemStatus` in a single shared `src/models/work_item.py`. Both sentinel and notifier import from there. Include all fields needed by both components; use `Optional` for fields only populated by one side.

**Ref:** I-1 above

> **Remarks:**
>
> _[Your feedback here]_

---

### R-4: Add Graceful Shutdown / Signal Handling

The sentinel catches `KeyboardInterrupt` but doesn't handle `SIGTERM`, which is what Docker and systemd send. Add a signal handler that sets a shutdown flag, finishes the current task, then exits cleanly. This prevents orphaned `agent:in-progress` issues when the container is stopped.

**Ref:** Implementation Spec v1, §Acceptance Criteria; `orchestrator_sentinel.py` entry point (line ~300)

> **Remarks:**
>
> _[Your feedback here]_

---

### R-5: Connection Pooling for GitHub API Client

Create `httpx.AsyncClient` once in `GitHubQueue.__init__()` and reuse it across all API calls. Add connection pool limits and a `close()` method wired into the shutdown handler (R-4).

**Ref:** I-4 above

> **Remarks:**
>
> _[Your feedback here]_

---

### R-6: Environment Variable Validation in Notifier

The sentinel validates env vars at startup — the notifier doesn't. Add a startup check for `WEBHOOK_SECRET` and `GITHUB_TOKEN`. Crash immediately with a clear error if they're missing or still set to placeholder values.

**Ref:** I-5 above; `notifier_service.py`

> **Remarks:**
>
> _[Your feedback here]_

---

### R-7: Implement Credential Scrubber for Public Logs

The plan describes a regex-based "Scrubber" for sanitizing worker output before posting to GitHub comments. This is specced in both the Architecture Guide and Implementation Spec but has no implementation. At minimum, strip patterns matching `ghp_`, `ghs_`, `Bearer `, and common API key formats before posting any worker output to issues.

**Ref:** Architecture Guide v3, §5 "Credential Scrubbing & Audit Trail"; Implementation Spec v1, §Logging "Public Telemetry"

> **Remarks:**
>
> _[Your feedback here]_

---

### R-8: Add Subprocess Timeout to Sentinel's Shell Bridge

The sentinel's `run_shell_command()` uses `asyncio.create_subprocess_exec` with no timeout. If `devcontainer-opencode.sh` hangs past its own internal watchdog, the sentinel blocks forever. Wrap with `asyncio.wait_for(process.communicate(), timeout=HARD_CEILING_SECS + buffer)` where the buffer accounts for the inner watchdog's own ceiling.

**Ref:** `orchestrator_sentinel.py` `run_shell_command()` (line ~70); relates to the idle watchdog fix in `run_opencode_prompt.sh`

> **Remarks:**
>
> _[Your feedback here]_

---

### R-9: Serve a Lightweight Status Dashboard

The `interactive-report.html` is a great presentation artifact but it's static. Once the system is running, consider having the sentinel expose a small FastAPI status endpoint (or extend the notifier's existing FastAPI app) showing current task, queue depth, sentinel uptime, and recent history. The notifier already has `/health` — extend it.

**Ref:** `notifier_service.py` `/health` endpoint; `interactive-report.html`

> **Remarks:**
>
> _[Your feedback here]_

---

## Appendix: Cross-Reference Matrix

| Finding | Architecture Guide v3 | Development Plan v4 | Implementation Spec v1 | Sentinel Code | Notifier Code |
|---------|----------------------|--------------------|-----------------------|---------------|---------------|
| S-1: 4-Pillar Architecture | §2 | — | §Overview | — | — |
| S-2: Shell-Bridge (ADR 07) | §3 ADR 07 | §1 Principle 1 | §Features | ✓ Uses it | — |
| S-3: Polling-First (ADR 08) | §3 ADR 08 | §1 Principle 4 | §Features | ✓ Implements | — |
| S-4: Markdown-as-DB | §2B | §1 Principle 2 | §Overview item 2 | ✓ Label ops | — |
| S-5: Self-Bootstrap | §6 | §6 | §Development Plan | — | — |
| S-6: Security Model | §5 | — | §Containerization | — | ✓ HMAC verify |
| S-7: Provider-Agnostic | §3 ADR 09 | — | — | — | ✓ ITaskQueue |
| I-1: Model Divergence | — | — | — | WorkItem v1 | WorkItem v2 |
| I-2: Race Condition | §2B Concurrency | §7 Risk table | §TC-03 | ✗ Missing | — |
| I-3: No Backoff | — | §3 Story 2 | §Features | ✗ Missing | — |
| I-4: No Connection Pool | — | — | — | ✗ Per-call | — |
| I-5: Hardcoded Secrets | — | — | — | — | ✗ Inline |
| I-6: No Heartbeat | §2C item 5 | §3 Story 4 | — | ✗ Missing | — |
| I-7: No Cost Guardrails | — | §3 Story 6 | §TC-05 | ✗ Missing | — |
| I-8: Single-Repo Only | §2C | — | — | ✗ Single repo | — |
| I-9: Bare except:pass | — | — | — | ✗ claim_task | — |
| I-10: No Env Reset | — | — | §Docker Compose | ✗ Missing | — |
