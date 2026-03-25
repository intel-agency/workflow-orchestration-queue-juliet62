# Architecture

**Project:** workflow-orchestration-queue  
**Last Updated:** 2026-03-25

---

## Executive Summary

workflow-orchestration-queue represents a paradigm shift from **Interactive AI Coding** to **Headless Agentic Orchestration**. Traditional AI developer tools require a human-in-the-loop to navigate files, provide context, and trigger executions. This system replaces manual overhead with a persistent, event-driven infrastructure that transforms GitHub Issues into "Execution Orders" autonomously fulfilled by specialized AI agents.

**Success Definition:** "Zero-Touch Construction" — a user opens a single "Specification Issue" and, within minutes, receives a functional, test-passed branch and PR.

---

## The 4-Pillar Architecture

The system is strictly decoupled across four conceptual pillars, each handling a distinct domain:

```
┌─────────────────────────────────────────────────────────────────┐
│                        EXTERNAL STIMULI                         │
│                    (GitHub Webhooks, Issues)                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     THE EAR (Notifier)                          │
│              FastAPI Webhook Ingestion Service                  │
│  • HMAC SHA256 signature validation                             │
│  • Event parsing and triage                                     │
│  • WorkItem manifest generation                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    THE STATE (Work Queue)                       │
│              GitHub Issues as Database                          │
│  • Label-based state machine (queued → in-progress → success)   │
│  • Distributed locking via Assignees                            │
│  • Perfect transparency and audit trail                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  THE BRAIN (Sentinel)                           │
│              Background Polling Orchestrator                    │
│  • Polling discovery (60s interval)                             │
│  • Task claiming with assign-then-verify                        │
│  • Shell-bridge dispatch                                        │
│  • Heartbeat monitoring                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    THE HANDS (Worker)                           │
│              DevContainer + Opencode Agent                      │
│  • Isolated execution environment                               │
│  • LLM-driven code generation                                   │
│  • Test verification                                            │
│  • PR creation                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Pillar 1: The Ear (Work Event Notifier)

**Technology:** Python 3.12, FastAPI, Pydantic

**Role:** Primary gateway for external stimuli and asynchronous triggers.

### Responsibilities

| Function | Description |
|----------|-------------|
| **Secure Webhook Ingestion** | Exposes `/webhooks/github` endpoint for `issues`, `issue_comment`, `pull_request` events |
| **Cryptographic Verification** | Validates `X-Hub-Signature-256` HMAC against `WEBHOOK_SECRET` |
| **Intelligent Triage** | Parses issue body/title, detects templates (`[Application Plan]`, `[Bugfix]`) |
| **Queue Initialization** | Applies `agent:queued` label via GitHub REST API |

### Security Model

```
GitHub Webhook ──► HMAC SHA256 Verification ──► Parse Payload ──► Triage ──► Queue
                      │
                      └──► 401 Unauthorized on invalid signature
```

---

## Pillar 2: The State (Work Queue)

**Implementation:** GitHub Issues, Labels, Milestones

**Philosophy:** "Markdown as a Database" — using GitHub as the persistence layer provides world-class audit logs, transparent versioning, and an out-of-the-box UI for human supervision.

### State Machine

```
                    ┌─────────────────┐
                    │ agent:queued    │ ◄── New task ready for processing
                    └────────┬────────┘
                             │ Sentinel claims
                             ▼
                    ┌─────────────────┐
                    │ agent:in-progress│ ◄── Task assigned to Sentinel
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
     ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐
     │agent:success│ │ agent:error │ │agent:infra-failure│
     └─────────────┘ └─────────────┘ └─────────────────┘
```

### Special States

| Label | Purpose |
|-------|---------|
| `agent:reconciling` | Stale tasks detected by reconciliation loop |
| `agent:stalled-budget` | Cost guardrail threshold exceeded |

### Concurrency Control

The **assign-then-verify** pattern prevents race conditions:

1. Attempt to assign `SENTINEL_BOT_LOGIN` to issue via `POST /repos/{owner}/{repo}/issues/{number}/assignees`
2. Re-fetch issue via `GET /repos/{owner}/{repo}/issues/{number}`
3. Verify `SENTINEL_BOT_LOGIN` appears in `assignees` array
4. Only then update labels and post claim comment

If verification fails (another sentinel won the race), abort gracefully.

---

## Pillar 3: The Brain (Sentinel Orchestrator)

**Technology:** Python (Async), PowerShell Core, Docker CLI

**Role:** Persistent supervisor managing Worker lifecycle and mapping intent to shell commands.

### Lifecycle

```
┌──────────────────────────────────────────────────────────────┐
│                    SENTINEL LIFECYCLE                        │
├──────────────────────────────────────────────────────────────┤
│  1. POLLING DISCOVERY                                        │
│     └── Query GitHub Issues API every 60s for agent:queued   │
│     └── Jittered exponential backoff on 403/429              │
│                                                              │
│  2. AUTH SYNCHRONIZATION                                     │
│     └── Run scripts/gh-auth.ps1 for valid installation token │
│                                                              │
│  3. TASK CLAIMING                                            │
│     └── Assign-then-verify pattern                           │
│     └── Apply agent:in-progress label                        │
│                                                              │
│  4. ENVIRONMENT PROVISION                                    │
│     └── ./scripts/devcontainer-opencode.sh up                │
│                                                              │
│  5. DISPATCH                                                 │
│     └── ./scripts/devcontainer-opencode.sh prompt "{workflow}"│
│     └── Background heartbeat coroutine (5 min intervals)     │
│                                                              │
│  6. FINALIZATION                                             │
│     └── Detect exit code                                     │
│     └── Apply terminal label (success/error/infra-failure)   │
│     └── Post execution summary comment                       │
│                                                              │
│  7. ENVIRONMENT RESET                                        │
│     └── ./scripts/devcontainer-opencode.sh stop              │
│     └── Prevent state bleed between tasks                    │
└──────────────────────────────────────────────────────────────┘
```

### Heartbeat System

For tasks exceeding 5 minutes, the Sentinel posts heartbeat comments every 5 minutes:

```python
async def _heartbeat_loop(item, start_time):
    while True:
        await asyncio.sleep(HEARTBEAT_INTERVAL)  # Default 300s
        elapsed = time.time() - start_time
        await post_comment(item, f"[Heartbeat] Still working... ({elapsed:.0f}s elapsed)")
```

### Graceful Shutdown

Handles `SIGTERM` and `SIGINT` to prevent orphaned `agent:in-progress` issues:

```python
_shutdown_requested = False

def signal_handler(signum, frame):
    global _shutdown_requested
    _shutdown_requested = True

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)
```

---

## Pillar 4: The Hands (Opencode Worker)

**Technology:** opencode-server CLI, LLM (GLM-5), DevContainer

**Environment:** High-fidelity DevContainer built from template repository.

### Worker Capabilities

| Capability | Description |
|------------|-------------|
| **Contextual Awareness** | Accesses project structure, runs `update-remote-indices.ps1` for vector indexing |
| **Instructional Logic** | Executes markdown workflow modules from `/local_ai_instruction_modules/` |
| **Verification** | Runs local test suites before PR submission |

### Shell-Bridge Protocol

The Orchestrator interacts with the Worker exclusively via shell scripts:

| Command | Purpose | Timeout |
|---------|---------|---------|
| `devcontainer-opencode.sh up` | Provision Docker network/volumes | 60s |
| `devcontainer-opencode.sh start` | Launch opencode-server | 60s |
| `devcontainer-opencode.sh prompt` | Execute workflow | 5700s (95 min) |
| `devcontainer-opencode.sh stop` | Stop container | 60s |

---

## Architecture Decision Records (ADRs)

### ADR 07: Standardized Shell-Bridge Execution

**Decision:** Orchestrator interacts with agentic environment exclusively via `./scripts/devcontainer-opencode.sh`.

**Rationale:** The existing shell infrastructure handles complex Docker logic (volume mounting, SSH-agent forwarding, port mapping). Re-implementing in Python would create "Configuration Drift."

**Consequence:** Python code remains lightweight (logic/state); Shell scripts handle "Heavy Lifting" (container orchestration).

---

### ADR 08: Polling-First Resiliency Model

**Decision:** Sentinel uses polling as primary discovery; webhooks are an optimization.

**Rationale:** Webhooks are "Fire and Forget" — if the server is down during an event, it's lost forever. Polling ensures automatic "State Reconciliation" on restart.

**Consequence:** System is inherently self-healing and resilient against downtime/network partitions.

---

### ADR 09: Provider-Agnostic Interface Layer

**Decision:** All queue interactions abstracted behind `ITaskQueue` interface using Strategy Pattern.

**Rationale:** While Phase 1 targets GitHub, architecture supports "Ticket Provider Swapping" (Linear, Notion, SQL queues) without Orchestrator rewrite.

**Interface Methods:**
- `fetch_queued()`
- `claim_task(id, sentinel_id)`
- `update_progress(id, log_line)`
- `finish_task(id, artifacts)`

---

## Data Flow (Happy Path)

```
1. STIMULUS
   User opens GitHub Issue with [Application Plan] template
   
2. NOTIFICATION
   GitHub Webhook hits Notifier (FastAPI)
   
3. TRIAGE
   Notifier verifies signature, confirms title pattern, adds agent:queued label
   
4. CLAIM
   Sentinel poller detects new label
   Assigns issue to bot account (assign-then-verify)
   Updates label to agent:in-progress
   
5. SYNC
   Sentinel runs git clone/pull on target repo into workspace volume
   
6. ENVIRONMENT CHECK
   Sentinel executes devcontainer-opencode.sh up
   
7. DISPATCH
   Sentinel sends: devcontainer-opencode.sh prompt "Run workflow: create-app-plan.md"
   
8. EXECUTION
   Worker (Opencode) reads issue, analyzes tech stack, creates Epic issues
   
9. FINALIZE
   Worker posts "Execution Complete" comment
   Sentinel removes in-progress, adds agent:success
```

---

## Security Model

### Network Isolation

```
┌─────────────────────────────────────────────────────┐
│                    HOST SERVER                      │
│  ┌───────────────┐      ┌───────────────────────┐  │
│  │   Sentinel    │      │   Notifier (FastAPI)  │  │
│  │   (Brain)     │      │   (Ear)               │  │
│  └───────┬───────┘      └───────────────────────┘  │
│          │                                         │
│          │ Shell Bridge                            │
│          ▼                                         │
│  ┌───────────────────────────────────────────┐    │
│  │         Docker Bridge Network             │    │
│  │         (Isolated)                        │    │
│  │  ┌─────────────────────────────────────┐  │    │
│  │  │        Worker DevContainer          │  │    │
│  │  │        (Hands)                      │  │    │
│  │  │   • Cannot access host subnet       │  │    │
│  │  │   • Cannot access peer containers   │  │    │
│  │  │   • 2 CPU / 4GB RAM limit           │  │    │
│  │  └─────────────────────────────────────┘  │    │
│  └───────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### Credential Scoping

| Layer | Mechanism |
|-------|-----------|
| **GitHub App Token** | Passed via temporary environment variable, destroyed after session |
| **Webhook Secret** | HMAC SHA256 verification, never exposed to worker |
| **API Keys** | Injected as ephemeral env vars, never written to disk |

### Credential Scrubbing

All worker output is sanitized before posting to GitHub:

```python
PATTERNS_TO_SCRUB = [
    r'ghp_[A-Za-z0-9_]+',           # GitHub PAT
    r'ghs_[A-Za-z0-9_]+',           # GitHub Server Token
    r'gho_[A-Za-z0-9_]+',           # GitHub OAuth Token
    r'github_pat_[A-Za-z0-9_]+',    # GitHub Fine-grained PAT
    r'Bearer\s+[A-Za-z0-9_-]+',     # Bearer tokens
    r'sk-[A-Za-z0-9]+',             # OpenAI-style keys
    r'zhipu_[A-Za-z0-9]+',          # ZhipuAI keys
]
```

---

## Project Structure

```
workflow-orchestration-queue/
├── pyproject.toml               # uv dependencies and metadata
├── uv.lock                      # Deterministic lockfile
├── src/
│   ├── notifier_service.py      # FastAPI webhook ingestion
│   ├── orchestrator_sentinel.py # Background polling and dispatch
│   ├── models/
│   │   ├── work_item.py         # Unified WorkItem, TaskType, WorkItemStatus
│   │   └── github_events.py     # GitHub webhook payload schemas
│   └── queue/
│       └── github_queue.py      # ITaskQueue + GitHubQueue (shared)
├── scripts/
│   ├── devcontainer-opencode.sh # Core shell bridge
│   ├── gh-auth.ps1              # GitHub App auth sync
│   └── update-remote-indices.ps1# Vector index sync
├── local_ai_instruction_modules/
│   ├── create-app-plan.md       # App planning workflow
│   ├── perform-task.md          # Feature implementation
│   └── analyze-bug.md           # Bug analysis and fixes
└── plan_docs/
    ├── tech-stack.md            # This document
    ├── architecture.md          # Architecture reference
    └── *.md                     # Original plan documents
```

---

## Self-Bootstrapping Lifecycle

```
Stage 0 (Seeding)
└── Developer clones template repository

Stage 1 (Manual Launch)
└── Developer runs devcontainer-opencode.sh up

Stage 2 (Project Setup)
└── Agent indexes repo, configures environment

Stage 3 (Handover)
└── Developer starts sentinel.py service
└── From this point: AI builds remaining features via GitHub Issues
```

---

## References

- **Development Plan v4.2:** Phased rollout, risk mitigation
- **Architecture Guide v3.2:** System diagrams, ADRs
- **Implementation Specification v1.2:** Requirements, acceptance criteria
- **Simplification Report v1:** Applied simplifications
- **Plan Review:** Issues identified and recommendations
