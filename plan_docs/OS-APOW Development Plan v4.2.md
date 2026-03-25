# **workflow-orchestration-queue: Detailed Development Plan**

This document provides a comprehensive, multi-phase roadmap for building the **workflow-orchestration-queue** system. It prioritizes the creation of a resilient **Sentinel Orchestrator** to handle task discovery and execution, followed by the "Ear" (webhook) and advanced planning layers.

## **1\. Motivation & Guiding Principles**

Traditional agentic development is "Human-Gated." Even with advanced models, a human must manually clone repositories, configure local .env files, and initiate starting prompts. workflow-orchestration-queue transforms this workflow into an **Autonomous Development Floor**. By leveraging a persistent background service, work flows directly from high-level project management artifacts (GitHub Issues) to technical implementation (verified Pull Requests) without human intervention.

Success for workflow-orchestration-queue is defined as "Zero-Touch Construction": a user opens a single "Specification Issue" and, within minutes, receives a functional, test-passed branch and PR.

**Guiding Principles:**

1. **Script-First Integration ("The Bridge"):** The system must not reimplement container management. It uses the existing devcontainer-opencode.sh script as its primary API. This ensures that the agent's environment is identical to a local developer's, preventing "Environment Drift" and simplifying troubleshooting.  
2. **State Visibility & Transparency:** The distributed state of the system is stored in GitHub via labels and comments. This "Markdown-as-a-Database" approach provides a world-class audit trail, allowing humans to supervise, interrupt, or correct the agent's path in real-time.  
3. **Self-Bootstrapping Evolution:** The system is designed to build itself. Phase 1 (The Sentinel) is manually seeded into a template clone. Once Phase 1 is functional, the orchestrator is tasked with building Phase 2 (The Ear) and Phase 3 (Deep Planning) using its own agentic workflows.  
4. **Resiliency through Polling:** While webhooks provide speed, the system maintains a "Polling-First" mentality. This ensures that if the server crashes or the network fails, the agent will naturally "re-sync" its work queue upon restart by looking at the persistent GitHub labels.

## **2\. Phase 0: Seeding (Bootstrapping)**

**Epic Title: Manual Seeding & Initial Orchestration**

*Goal: Manually initialize the platform from the template repository to enable the system to build itself moving forward.*

### **User Stories**

* **Story 1: Template Cloning & Plan Seeding**  
  * **As a** Developer, **I want** to manually clone the workflow-orchestration-queue-juliet62 and seed it with these plan documents in the /docs directory, **so that** the AI agents have the necessary context to start building the orchestrator.  
  * **Acceptance Criteria:**  
    * Repository cloned and initialized.  
    * /docs directory contains architecture\_guide\_v2.md and development\_plan\_v2.md.  
* **Story 2: Project Setup Execution**  
  * **As a** Developer, **I want** to run the orchestrate-dynamic-workflow command with the project-setup assignment, **so that** the agent initializes the environment variables and indexes the codebase.  
  * **Acceptance Criteria:**  
    * ./scripts/devcontainer-opencode.sh up runs successfully.  
    * project-setup workflow completes, producing a valid .env and updated remote indices.

## **3\. Phase 1: The Sentinel (MVP)**

**Epic Title: Autonomous Polling & Shell-Bridge Execution**

*Goal: Establish a persistent background service (The Sentinel) that detects work orders via GitHub Labels and triggers the existing devcontainer-opencode.sh infrastructure.*

### **User Stories**

* **Story 1: Standardized Work Item Interface**  
  * **As a** Developer, **I want** a unified Pydantic-based WorkItem model and an abstract IWorkQueue base class, **so that** the orchestrator logic is decoupled from the specific provider (GitHub, Linear, etc.).  
  * **Implication:** This prevents vendor lock-in. If the team migrates to Linear or a custom internal dashboard, the "Brain" of the orchestrator remains unchanged.  
  * **Acceptance Criteria:**  
    * models.py defines a WorkItem with fields: id (string/int), source\_url (string), context\_body (string), target\_repo\_slug (string), task\_type (Enum: PLAN, IMPLEMENT), status (Enum mapping to GH Labels), and a metadata (dict) field to store provider-specific info like issue\_node\_id.  
    * interfaces.py defines fetch\_queued\_items() and update\_item\_status().  
    * A GitHubIssueQueue implementation successfully maps GH REST API calls to these interfaces.  
* **Story 2: The Resilient Polling Engine**  
  * **As an** Orchestrator, **I want** to query the GitHub REST API every 60 seconds for issues with the agent:queued label, **so that** I can autonomously discover new work without human signals.  
  * **Detail:** The poller must handle "Secondary Rate Limits" and 403 Forbidden responses using a jittered exponential backoff strategy.  
  * **Acceptance Criteria:**  
    * The script runs as a persistent service using uv run.  
    * Successfully logs the discovery of issues in the configured repository.  
    * Integrates with scripts/gh-auth.ps1 to maintain valid installation tokens for the GitHub App.  
  * **Implementation Directions:**  
    * On HTTP 403 or 429 responses, apply exponential backoff with random jitter: `wait = min(current_backoff + random(0, 0.1 * current_backoff), MAX_BACKOFF)`. Double `current_backoff` on each consecutive rate-limit hit. Reset to `POLL_INTERVAL` on any successful poll.
    * `MAX_BACKOFF` defaults to 960s (16 min).
    * Use the single-repo GitHub Issues API (`GET /repos/{owner}/{repo}/issues?labels=agent:queued&state=open`) for task discovery. `GITHUB_REPO` is a required env var.
    * **Future Phase:** Cross-repo org-wide polling via the GitHub Search API (`GET /search/issues?q=label:agent:queued+org:{ORG}+is:issue+is:open`) is planned for when the org has multiple workflow repos. At that point, `GITHUB_REPO` becomes optional and the Sentinel discovers work across the entire org.
    * Create `httpx.AsyncClient` once in `GitHubQueue.__init__()` and reuse across all API calls for connection pooling. Add an `async close()` wired to shutdown.
* **Story 3: Shell-Bridge Dispatcher**  
  * **As an** Orchestrator, **I want** to invoke ./scripts/devcontainer-opencode.sh prompt when a task is found, **so that** the agentic environment begins technical work.  
  * **Rationale:** By piping the task into the existing shell bridge, we inherit all the SSH-agent forwarding, volume mounts, and Docker network configurations defined in the workflow-orchestration-queue-juliet62.  
  * **Acceptance Criteria:**  
    * The Sentinel ensures the environment is "up" via ./scripts/devcontainer-opencode.sh up before sending the prompt.  
    * Subprocess output (stdout/stderr) is streamed to local JSON-structured log files (e.g., worker\_run\_ID.jsonl) to ensure durability and machine-readability during long-running tasks.  
    * The script detects a non-zero exit code from the shell script and triggers an "Error State" update.  
* **Story 4: Automated Status Feedback**  
  * **As an** Admin, **I want** the Sentinel to update the GitHub Issue labels from agent:queued to agent:in-progress and finally agent:success (or agent:error), **so that** stakeholders have real-time visibility.  
  * **Acceptance Criteria:**  
    * On task start, the Sentinel assigns the issue to the Agent account and posts a comment: "Sentinel ![][image1] is starting work."  
    * On completion, it removes the queue label and adds the terminal state label. For tasks exceeding 5 minutes, the Sentinel must post a \[Heartbeat\] comment every 5 minutes to confirm active status.  
    * If an error occurs, it attaches the last 20 lines of the worker log to a GitHub comment and performs contextual labeling: failures during 'up' or 'start' are flagged with agent:infra-failure, while failures during 'prompt' are flagged with agent:impl-error.  
  * **Implementation Directions — Heartbeat:**  
    * Implement a `_heartbeat_loop(item, start_time)` async coroutine that sleeps for `HEARTBEAT_INTERVAL` seconds (default 300, configurable via env var), then posts a status comment with elapsed time.  
    * Launch the heartbeat as an `asyncio.create_task()` alongside `process_task()`. Cancel it in a `finally` block when the task completes.  
    * This is critical because `devcontainer-opencode.sh prompt` calls can take 15+ minutes during subagent delegation with zero client-side output.  
  * **Implementation Directions — Locking (Assign-then-Verify):**  
    * Task claiming MUST use the assign-then-verify pattern to prevent race conditions between multiple Sentinel instances:  
      1. Attempt to assign `SENTINEL_BOT_LOGIN` to the issue via `POST /repos/{owner}/{repo}/issues/{number}/assignees`.  
      2. Re-fetch the issue via `GET /repos/{owner}/{repo}/issues/{number}`.  
      3. Verify that `SENTINEL_BOT_LOGIN` appears in the `assignees` array.  
      4. Only then update labels and post the claim comment.  
    * If verification fails (another sentinel won the race), abort gracefully and move to the next queued item.  
    * `SENTINEL_BOT_LOGIN` must be set to the GitHub login of the bot account. If unset, log a warning that locking is disabled.  
  * **Implementation Directions — Credential Scrubbing:**  
    * All log output and error messages posted to GitHub issue comments MUST be passed through a `scrub_secrets()` utility before posting.  
    * The scrubber strips patterns matching: `ghp_*`, `ghs_*`, `gho_*`, `github_pat_*`, `Bearer`, `token`, `sk-*`, and ZhipuAI keys.  
    * Implemented in the shared `src/models/work_item.py` module.  
* **Story 5: Unique Instance Identification**  
  * **As an** Administrator, **I want** each Sentinel to generate or accept a unique SENTINEL\_ID on startup, **so that** its actions and issue assignments are clearly attributable in logs and the GitHub UI.  
* **Story 6: Cost Guardrails & Resource Safety**  
  * **As an** Owner, **I want** the Sentinel to monitor LLM usage costs, **so that** the system does not exceed the daily budget during an autonomous loop.  
  * **Acceptance Criteria:**  
    * Sentinel checks a local credits\_used file after every prompt call.  
    * The polling loop automatically shuts down and labels the issue agent:stalled-budget if a daily threshold is exceeded.  
  * **Implementation Note:** Deferred from first version to reduce complexity. The `WorkItemStatus.STALLED_BUDGET` label and the `agent:stalled-budget` state are defined in the shared model but the monitoring logic should be implemented in a later iteration once the core polling-claim-execute loop is stable.

## **4\. Phase 2: The "Ear" (Webhook Automation)**

**Epic Title: Event-Driven Triage & Instant Intake**

*Goal: Implement a FastAPI service to handle incoming GitHub Webhooks, allowing for sub-second task ingestion and automated template validation.*

### **User Stories**

* **Story 1: Hardened FastAPI Webhook Receiver**  
  * **As a** System, **I want** a secure endpoint to receive issues and issue\_comment payloads, **so that** work can be acknowledged instantly.  
  * **Detail:** Security is paramount. The system must validate the X-Hub-Signature-256 header against the App's secret.  
  * **Acceptance Criteria:**  
    * FastAPI app rejects any request with an invalid signature.  
    * Responds with 202 Accepted to GitHub to acknowledge the event within the 10-second timeout.  
    * Dependencies are managed strictly via uv for reproducible production builds.  
* **Story 2: Intelligent Template Triaging**  
  * **As a** Product Manager, **I want** issues opened with specific headers (e.g., \[Application Plan\]) to be automatically labeled agent:queued, **so that** I don't have to manually tag tickets.  
  * **Acceptance Criteria:**  
    * The Notifier parses the markdown body of new issues.  
    * Successfully identifies "Plan" vs "Bug" vs "Feature" based on the issue template used.  
    * Applies appropriate agent labels via the GitHub API based on the parsed intent.  
* **Story 3: Local-to-Cloud Tunneling (Dev Mode)**  
  * **As a** Developer, **I want** the Notifier to integrate with ngrok or tailscale tunnel, **so that** I can receive webhooks on my local server during the construction phase.  
  * **Acceptance Criteria:**  
    * A start\_dev\_notifier.sh script launches both the FastAPI app and the tunnel.  
    * The Notifier service automatically updates its registered Webhook URL in the GitHub App settings (optional/bonus) or logs the required URL for manual entry.

## **5\. Phase 3: Deep Orchestration (Planning)**

**Epic Title: Hierarchical Decomposition & Self-Correction**

*Goal: Upgrade the system from simple "Prompt Passing" to high-level reasoning, allowing the AI to manage complex, multi-repo projects by delegating sub-tasks to itself.*

### **User Stories**

* **Story 1: The Architect Sub-Agent**  
  * **As a** System, **I want** a specialized LangChain agent to analyze an "Application Plan" and create a series of "Epic" issues, **so that** the project is broken down into parallelizable units.  
  * **Acceptance Criteria:**  
    * A single "Plan" issue results in 3-5 child "Epic" issues created via the GitHub API.  
    * Child issues include "Related To" links back to the parent Plan. The Architect must use GitHub Task List syntax to track completion of sub-issues and must not label a sub-issue as \[agent:queued\] until all its identified blocking dependencies (e.g. foundational infrastructure epics) are in the \[agent:success\] state.  
    * The Architect agent defines dependencies between Epics (e.g., Epic B won't be labeled queued until Epic A is success).  
* **Story 2: Autonomous Bug Correction Loop**  
  * **As a** Developer, **I want** the agent to read GitHub PR review comments and automatically re-queue the task to fix requested changes, **so that** it iterates until approval.  
  * **Implication:** This turns the agent into a true "Collaborator" that responds to human feedback.  
  * **Acceptance Criteria:**  
    * The Notifier detects pull\_request\_review\_comment events.  
    * The system moves the associated issue status from agent:success back to agent:queued.  
    * The prompt sent to the Worker includes the reviewer's feedback as specific context.  
* **Story 3: Proactive Workspace Indexing**  
  * **As an** Orchestrator, **I want** to execute ./scripts/update-remote-indices.ps1 immediately after cloning a repo, **so that** the agent always has an up-to-date vector-indexed view of the codebase.  
  * **Acceptance Criteria:**  
    * Sentinel triggers indexing before the primary prompt command.  
    * Worker verifies index presence before beginning generation tasks.

## **6\. Infrastructure & Self-Bootstrapping Lifecycle**

1. **Stage 0 (Seeding):** The developer manually clones the workflow-orchestration-queue-juliet62. This plan is added to /docs.  
2. **Stage 1 (Manual Launch):** Developer runs ./scripts/devcontainer-opencode.sh up to initialize the worker environment.  
3. **Stage 2 (Project Setup):** Developer runs the orchestrate-project-setup workflow. The agent indexes the repo and configures the notifier and sentinel skeletons generated in the plan.  
4. **Stage 3 (Handover):** The developer starts the sentinel.py service on the host. From this point, the developer interacts *only* via GitHub issues. The AI builds its own remaining features (Phase 2 and 3\) by picking up its own task tickets.

## **7\. Risk Assessment & Mitigation**

| **Potential Risk** | **Impact** | **Mitigation Plan** |

| **GitHub API Rate Limiting** | High | Use GitHub App Installation tokens (5,000 requests/hr); implement aggressive local caching of issue labels; use Long-Polling intervals. |

| **LLM "Looping" / Hallucination** | High | Implement a max\_steps timeout in the opencode run config. Implement Story 6 "Cost Guardrails" to monitor usage. Add an agent:retries counter to labels; if \>3, move to agent:stalled. |

| **Concurrency Collisions** | Medium | Use the GitHub "Assignee" feature as a locking mechanism. The Sentinel must use the **assign-then-verify** pattern: (1) assign itself, (2) re-fetch the issue, (3) verify it is the current assignee before proceeding. If another Sentinel won the race, abort gracefully. |

| **Container Drift** | Medium | The Sentinel stops the worker container between tasks to prevent state bleed, while keeping it available for fast restart. |

| **Security Injection** | Medium | Strict HMAC signature validation on all webhooks; the worker container is denied access to the host's .env files except via explicit injection. |

## **8\. Out of Scope (Phases 1-3)**

* Support for non-Git providers (e.g., Bitbucket, SVN).  
* Automatic deployment to production cloud environments (Agents stop at the PR/Staging phase).  
* Real-time websocket log streaming to a custom web GUI (Logs are retrieved via GitHub Issue comments or host file tailing only).

## **9\. Cross-Cutting Implementation Directions**

The following directions apply across multiple stories and phases. They are drawn from the plan review (see `OS-APOW Plan Review.md`).

### **Unified Data Model (I-1 / R-3)**

All Pydantic models (`WorkItem`, `TaskType`, `WorkItemStatus`) MUST be defined in a single shared module: `src/models/work_item.py`. Both `orchestrator_sentinel.py` and `notifier_service.py` import from there. This prevents model divergence between components.

### **Graceful Shutdown (R-4)**

The Sentinel MUST handle `SIGTERM` and `SIGINT` via `signal.signal()`. On receipt, set a `_shutdown_requested` flag. The polling loop checks this flag before starting a new task and after each sleep. The current task is allowed to finish before the process exits. This prevents orphaned `agent:in-progress` issues when the container is stopped by Docker or systemd.

### **Subprocess Timeout Safety Net (R-8)**

All `devcontainer-opencode.sh` subprocess calls MUST use `asyncio.wait_for()` with a timeout. The prompt command uses `SUBPROCESS_TIMEOUT` (default 5700s = 95 min), set higher than `run_opencode_prompt.sh`'s `HARD_CEILING_SECS` (5400s = 90 min) to avoid racing the inner watchdog. Infrastructure commands (`up`, `start`, `stop`, `down`) use shorter timeouts (60\u2013300s).

### **Environment Variable Validation (I-5 / R-6)**

Both the Sentinel and the Notifier MUST validate required environment variables at startup and crash immediately with a clear error message if any are missing or still set to placeholder values. Never embed secrets as default values in source code.

### **Connection Pooling (I-4 / R-5)**

The `GitHubQueue` class in `src/queue/github_queue.py` MUST create a single `httpx.AsyncClient` in `__init__()` and reuse it across all API calls. An `async close()` method releases the pool during graceful shutdown. Both the Sentinel and the Notifier import and use this consolidated class (see Simplification Report S-6).

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABsAAAAZCAYAAADAHFVeAAABeElEQVR4Xu2TvUrEUBCFd13xD0RRbPKfsBIJwlaCpYUg+A6ChYXvIDZWdraCb6AIwoJisY2dha2NTToLH0LPLHOX8ZDEQu3ywZDdOSeT5Nx7O52Wv6Yoipksy5a4D6a44fv+KlcQBCvsqyVJkvM4jj+5ZJD1hWHosYfqA7Xf7/dn7X2VwPgqN3Gf6MJzFkXRI4ausYj+nc6YZu0b7u24b0EKy/DcYOiFxF+hb0Mv5craBMldHiZDWLNgyJ74EOkWa4LneQuYcQnPlfxmfUyapgMZgmHHrFngORFfVYSCedgDr7mjp5tkJJuARQsGPTetKxJaV0/1l2mEw7p1sOi6ltx3uJhRp/jbZV3e9qBpHRx5ni+Kr2ldod/qrOqE3DmrNSjwbYgP10PWHPLVTTGLYahD5lizaERlXQJymDXCa9YmqOFX5wv9Xehv8O2wZunpw0YsWDTCl6oIscHmob1De2JtDKLY1IdwHVmf2zwNdZ/8cDZbWlr+ny9Eg4OAbRYuWgAAAABJRU5ErkJggg==>
