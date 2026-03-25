# **New Application Implementation Specification**

## **App Title**

workflow-orchestration-queue

## **Development Plan**

The system's lifecycle is structured across a 4-phase evolutionary roadmap. This roadmap is specifically designed to focus on self-bootstrapping capabilities, moving the system from a fully manual setup to a state of progressive autonomy where the AI agent ultimately manages its own deployment, updates, and issue resolution.

* **Phase 0 (Seeding & Bootstrapping):** This initial phase requires manual intervention to establish the foundational environment. It entails cloning the base repository (workflow-orchestration-queue-juliet62), setting up the initial environment configuration files (e.g., .env), and establishing the DevContainer base image. During this phase, the developer acts as the system administrator, ensuring that the necessary API keys, organizational secrets, and Docker prerequisites are securely in place before handing over control.  
* **Phase 1 (The Sentinel \- MVP):** The core foundational logic is established here. This phase introduces the persistent orchestrator—a background Python service that continuously polls the designated GitHub repository's Issues tracker. It looks for specific markers (labels like agent:queued) and acts as a bridge to trigger the devcontainer-opencode.sh worker environments. The MVP proves that the system can asynchronously pick up a task, execute a local shell script to spawn an isolated AI worker, and report basic success or failure back to the human operators without requiring real-time prompting.  
* **Phase 2 (The Ear \- Webhook Automation):** Transitioning from a purely pull-based (polling) architecture to a push-based model. This phase implements a FastAPI webhook receiver (notifier\_service.py) designed for sub-second task ingestion and triage. Instead of waiting for the next polling cycle, the system immediately wakes up upon receiving a GitHub event payload, validates the cryptographic signature, triages the text within the issue, and places it into the execution queue. This drastically reduces latency between a product manager creating a ticket and the AI beginning its work.  
* **Phase 3 (Deep Orchestration & Self-Healing):** The final maturation of the platform. The orchestrator gains advanced hierarchical reasoning, allowing an "Architect Sub-Agent" to read a massive Epic-level issue and decompose it into a sequence of smaller, manageable child tasks. Furthermore, it introduces automated Pull Request review corrections—if a human reviewer requests changes, the system autonomously transitions the task back into the active queue, reads the feedback, and updates the PR. Dynamic workspace vector indexing is also introduced to give the AI instant, semantic recall of the entire codebase.

## **Description**

workflow-orchestration-queue is a groundbreaking headless agentic orchestration platform that fundamentally transforms the current paradigm of "interactive" AI coding. Today's AI development tools (like GitHub Copilot or Cursor) act as passive co-pilots; they sit idle until a human developer explicitly highlights code, writes a prompt, and continuously guides the AI through every roadblock. workflow-orchestration-queue eliminates this human-in-the-loop dependency, shifting the AI from a passive assistant to an autonomous background production service—effectively acting as a tireless junior developer on your team.

The system natively integrates into existing Agile workflows by translating standard project management artifacts (such as GitHub Issues, Epics, and Kanban board movements) into automated Execution Orders. A product manager or lead engineer simply writes a standard issue description, applies a specific label, and walks away. The workflow-orchestration-queue system detects this intent and dispatches a specialized AI agent (the Opencode-Server worker). This worker autonomously clones the target repository, configures its own local environment, generates and modifies code across multiple files, runs local test suites to verify its changes, and ultimately submits a fully formatted Pull Request for human review. It bridges the gap between natural language requirements and deployed infrastructure.

## **Overview**

The system architecture is strictly decoupled, adhering to an event-driven pattern that ensures high availability, modularity, and security. It is distributed across four conceptual pillars, each handling a distinct domain of the workflow:

1. **The Ear (Work Event Notifier):** A high-performance FastAPI-based webhook receiver serving as the system's sensory input. It securely ingests incoming events—primarily GitHub webhook events (issue creation, PR comments, label changes)—and parses the incoming JSON payloads. It maps these disparate events into standardized WorkItem manifests, ensuring that the downstream queue only deals with sanitized, uniform data structures, regardless of the originating platform.  
2. **The State (Work Queue):** A distributed state management layer that uniquely leverages GitHub Issues as its primary database, a concept referred to as "Markdown as a Database." Rather than maintaining an opaque, proprietary SQL database, workflow-orchestration-queue uses public-facing issue labels to manage task states (agent:queued, agent:in-progress, agent:success, agent:error). This provides perfect transparency; humans can view, audit, pause, or cancel the agent's state simply by looking at the GitHub UI.  
3. **The Brain (Sentinel Orchestrator):** The core decision engine. This asynchronous Python background service is responsible for polling the queue and claiming tasks. It utilizes GitHub's assignment feature as a distributed locking mechanism to prevent race conditions among multiple Sentinels. Once a task is securely claimed, the Brain marshals the necessary resources, injects temporary authentication tokens, and manages the entire lifecycle of the worker container, waiting for its exit code to determine the next step.  
4. **The Hands (Opencode Worker):** The execution layer where the actual coding happens. This is an isolated, high-fidelity Docker DevContainer invoked via a strict shell bridge (./scripts/devcontainer-opencode.sh). Inside this container, an LLM-driven agent executes markdown-based instruction modules against the cloned codebase. Because it uses a DevContainer, the AI operates in a locally reproducible environment that is bit-for-bit identical to what a human developer would use, completely eliminating "it works on my machine" discrepancies.

## **Document Links**

* **Architecture Guide v3:** Details the system-level diagrams, the transition from manual seeding to the autonomous phase, and the security boundaries (e.g., Network Isolation, Credentials Scrubbing).  
* **Development Plan v4:** Outlines the motivation, guiding principles (Script-First Integration, State Visibility), the phased roll-out strategy, and potential risks with their mitigations (such as API Rate Limits and Concurrency Collisions).  
* **Opencode-Server DevContainer Documentation:** Specifications for the worker environment, including volume mounts, resource constraints, and required base image dependencies.  
* **GitHub App Webhook Configuration Docs:** Instructions for setting up the necessary organizational permissions, HMAC secrets, and event subscriptions required for "The Ear" to function securely.

## **Requirements**

### **Features**

* **Secure Webhook Ingestion:** The system exposes a hardened endpoint (/webhooks/github) that strictly requires and verifies the X-Hub-Signature-256 HMAC hash attached to incoming requests. This cryptographic validation ensures that the payload definitively originated from the trusted GitHub App, providing critical protection against spoofing, prompt injection, and unauthorized remote code execution attempts.  
* **Intelligent Triaging:** The Notifier service features an intelligent routing layer. It automatically detects specific string templates (e.g., \[Application Plan\], \[Bugfix\]) in issue titles or bodies. Based on this detection, it dynamically assigns appropriate internal WorkItemTypes, applies tags, and prioritizes the execution queue accordingly, ensuring urgent bugs preempt standard feature work.  
* **Resilient Task Polling:** To guarantee system stability, the Sentinel utilizes a polling-first discovery mechanism fortified with jittered exponential backoff. This means if the Sentinel service crashes, experiences network outages, or the server restarts, it will automatically query the GitHub API upon reboot to find and reconcile any tasks that were left in the agent:queued or agent:in-progress states, ensuring zero dropped workloads.  
* **Concurrency Control:** In environments running multiple Sentinel instances, race conditions are a major risk. The system mitigates this risk by employing the **assign-then-verify** pattern using GitHub Assignees as a distributed lock semaphore. A Sentinel must: (1) attempt to assign itself to the issue, (2) re-fetch the issue, (3) verify it is the current assignee before proceeding. If another Sentinel won the race, the loser aborts gracefully. The `SENTINEL_BOT_LOGIN` env var identifies the bot account for this check.  
* **Shell-Bridge Execution:** The Orchestrator interacts with the underlying AI worker strictly via the ./scripts/devcontainer-opencode.sh CLI abstraction. It does not use direct Docker SDK bindings. This "script-first" approach guarantees that the AI operates in a locally reproducible environment identical to a human developer, and allows human engineers to debug the exact same scripts the AI uses.

### **Test cases**

* **TC-01 (Security Verification):** Trigger a POST request to /webhooks/github with a malformed or missing X-Hub-Signature-256 header. The system must instantly return a 401 Unauthorized response without parsing the JSON body, validating the primary defense against malicious payloads.  
* **TC-02 (Ingestion & Triage):** Send a valid webhook payload representing a newly opened issue with the title \[Application Plan\] Create Authentication Module. The system must successfully validate the signature, parse the text, dynamically apply the agent:queued label via the add\_to\_queue interface, and return a 200 OK with the tracking ID.  
* **TC-03 (Concurrency Locking):** Simulate two Sentinel instances attempting to claim the same agent:queued issue simultaneously. The first instance must successfully assign itself and begin work. The second instance, detecting the assignment during its API call, must safely ignore the issue and move to the next item in the queue without throwing a fatal error.  
* **TC-04 (Failure Reporting):** Force a DevContainer startup failure (e.g., by corrupting the devcontainer.json in the target repo). The Sentinel must catch the non-zero exit code from the shell bridge, immediately apply the agent:infra-failure label, and post a heavily sanitized snippet of the stderr logs as an issue comment to aid human debugging.

### **Logging**

* **Worker Output (Black Box):** To maintain a flawless audit trail, every byte of raw stdout and stderr generated by the worker container is captured and saved to persistent local files on the host server (e.g., worker\_run\_ID\_TIMESTAMP.jsonl). These logs contain full execution contexts, including potentially sensitive variable dumps, and are strictly reserved for internal forensic analysis and debugging by system administrators.  
* **Public Telemetry:** For user-facing visibility, the system relies on sanitized telemetry. A dedicated `scrub_secrets()` utility in `src/models/work_item.py` uses regex patterns to strip GitHub PATs (`ghp_*`, `ghs_*`, `gho_*`, `github_pat_*`), Bearer tokens, API keys (`sk-*`), and ZhipuAI keys from all output before posting to GitHub. Heartbeat comments are posted every 5 minutes (configurable via `SENTINEL_HEARTBEAT_INTERVAL` env var) by a background async coroutine.  
* **Service Logging:** Both the Sentinel Orchestrator and Notifier Webhook components utilize structured Python logging via StreamHandler for console output. When running in Docker, stdout is captured by the container runtime (`docker logs`). Every log line is stamped with a unique SENTINEL\_ID identifier, allowing administrators to easily trace workflows in a multi-node deployment cluster.

### **Containerization: Docker**

* **Network Isolation:** Security is paramount when executing AI-generated code. All worker DevContainers operate within a segregated, bridge Docker network. This strict network topology explicitly prevents the worker container from accessing the host machine's sensitive internal subnets, local metadata endpoints (like AWS IMDS), or other peer containers, mitigating the risk of lateral movement.  
* **Resource Constraints:** To ensure orchestrator stability and prevent a single "rogue agent" (e.g., an LLM writing an infinite loop in a build script) from causing a Denial-of-Service on the host, the devcontainer.json configuration imposes strict cgroup limits. Worker containers are hard-capped at 2 CPUs and 4GB of RAM.  
* **Ephemeral Credentials:** The system strictly adheres to the principle of least privilege. GitHub Installation Tokens and necessary API keys are dynamically generated by the Sentinel and injected into the DevContainer exclusively as temporary, in-memory environment variables. These variables are never written to disk within the container and are instantly, permanently destroyed the moment the container exits.

### **Containerization: Docker Compose**

* The system extensively leverages Docker Compose, orchestrated by the underlying devcontainer-opencode.sh framework, to manage complex, multi-container needs. If an Epic requires testing a web application alongside a PostgreSQL database, Docker Compose orchestrates both. The Sentinel stops the worker container between tasks to prevent state bleed, while keeping it available for fast restart.
* This guarantees a clean environment between tasks, eliminating the risk of "environment drift" or contaminated state bleeding from one task to another.

### **Swagger/OpenAPI**

* A major benefit of utilizing the FastAPI framework for "The Ear" (Work Event Notifier) is the out-of-the-box generation of Swagger and OpenAPI documentation. This interactive API documentation is automatically provided and available locally at <http://localhost:8000/docs>. It allows developers and human operators to manually inspect the webhook schemas, test payload ingestion, and verify routing logic directly from their browser without needing to trigger actual GitHub events.

### **Documentation**

* **Instructional Logic Modules:** The core logic dictating *how* the AI behaves (e.g., how it plans an app, how it writes a test) is not hardcoded into the Python infrastructure. Instead, it is abstracted into Markdown-based instructional logic modules stored in the /local\_ai\_instruction\_modules/ directory. This brilliant separation of concerns means that Prompt Engineers can update and refine the AI's behavior via standard Pull Requests, without needing to touch or redeploy the core Python orchestrator code.  
* **Inline Code Documentation:** All infrastructure code (notifier\_service.py, orchestrator\_sentinel.py, interfaces, and models) is heavily documented using standard docstrings. These docstrings adhere strictly to the Sphinx/Google format, detailing parameters, return types, and potential exceptions for every class and method, ensuring high maintainability and ease of onboarding for new human developers.

### **Acceptance Criteria**

* **Task Claiming:** Given a valid GitHub issue labeled with agent:queued, when the Sentinel background service executes its polling cycle, then the Sentinel must use the **assign-then-verify** pattern: (1) assign itself, (2) re-fetch the issue, (3) verify it is the assignee. Only then remove the agent:queued label, apply the agent:in-progress label, and log the state transition without errors. If verification fails, skip the issue gracefully.  
* **Infrastructure Failure Handling:** Given a task that is currently agent:in-progress, when the underlying devcontainer-opencode.sh up command exits with a non-zero exit code (indicating a container crash or build failure), then the orchestrator must immediately catch this exception, label the issue as agent:infra-failure, and post the last 50 lines of the stderr output as a comment to the issue to facilitate immediate human triage.  
* **Successful Execution & Delivery:** Given a successful execution of the AI's prompt routine inside the DevContainer, the system must detect the zero exit code, push the committed changes to a new remote branch, generate a fully formatted Pull Request linking back to the original issue, and finally label the parent issue as agent:success.  
* **Security & Payload Rejection:** Given an incoming HTTP POST request to the webhook endpoint that contains a payload originating from outside the authorized GitHub App (simulated via an invalid or missing signature), the Notifier service must reject the payload with an HTTP 401 error prior to any JSON parsing or data processing occurring.

## **Language**

* **Python:** Used as the primary language for the Orchestrator, the API Webhook receiver, and all system logic, providing an optimal blend of asynchronous capabilities and robust text processing.  
* **PowerShell Core (pwsh) / Bash:** Used exclusively for the Shell Bridge Scripts, Auth synchronization, and cross-platform CLI interactions, ensuring maximum compatibility across Linux and Windows host environments.

## **Language Version**

* **Python 3.12+:** Taking advantage of the latest asynchronous features, improved error messages, and significant performance enhancements in the core interpreter.

## **Include global.json?**

* **No**. As this is predominantly a Python and Shell ecosystem, .NET configuration files like global.json are entirely unnecessary. All dependency, environment, and version management will be strictly handled via pyproject.toml and the modern, Rust-based uv package manager (tracked via uv.lock).

## **Frameworks, Tools, Packages**

* **FastAPI:** Chosen as the high-performance async web framework for the Webhook Notifier due to its native Pydantic integration, automatic OpenAPI generation, and unparalleled speed.  
* **Uvicorn:** The lightning-fast ASGI web server implementation used to serve the FastAPI application in production.  
* **Pydantic:** Utilized extensively for strict data validation, settings management, and defining the complex data schemas needed for cross-component communication (e.g., WorkItem, TaskType).  
* **HTTPX:** Selected over the standard requests library to serve as a fully asynchronous HTTP client. This allows the Sentinel to execute REST API calls to GitHub without blocking the main event loop, significantly improving throughput.  
* **uv:** Employed as the Python package installer and dependency resolver. Written in Rust, it provides speeds orders of magnitude faster than pip or poetry, vastly accelerating DevContainer build times.  
* **Docker CLI / DevContainers:** The absolute core underlying worker execution engine, providing the necessary sandboxing, environment consistency, and lifecycle hooks for the LLM agents.

## **Project Structure/Package System**

workflow-orchestration-queue/  
├── pyproject.toml               \# Core definition file for uv dependencies and metadata  
├── uv.lock                      \# Deterministic lockfile for exact package versions  
├── src/                         \# Main application source code  
│   ├── notifier\_service.py      \# FastAPI Webhook ingestion and event routing logic  
│   ├── orchestrator\_sentinel.py \# Background polling, locking, and dispatch logic  
│   ├── models/                  \# Pydantic data schemas defining system entities  
│   │   ├── work\_item.py         \# Unified WorkItem, TaskType, WorkItemStatus, scrub\_secrets()  
│   │   └── github\_events.py     \# Schemas for parsing GitHub webhook payloads  
│   └── queue/                   \# Consolidated queue implementations  
│       └── github\_queue.py      \# ITaskQueue ABC + GitHubQueue (shared by sentinel & notifier)  
├── scripts/                     \# The "Shell Bridge" execution layer  
│   ├── devcontainer-opencode.sh \# Core orchestrator invoking the worker Docker context  
│   ├── gh-auth.ps1              \# PowerShell utility for syncing GitHub App authentication  
│   └── update-remote-indices.ps1\# Utility for maintaining proactive vector index syncs  
├── local\_ai\_instruction\_modules/\# Decoupled Markdown logic workflows for the LLM  
│   ├── create-app-plan.md       \# Prompts guiding the AI on how to map out a new application  
│   ├── perform-task.md          \# Standard operational instructions for feature implementation  
│   └── analyze-bug.md           \# Instructions for parsing stack traces and applying fixes  
└── docs/                        \# Comprehensive architectural and user documentation

## **GitHub**

**Repo:** <https://github.com/intel-agency/workflow-orchestration-queue> *(configurable dynamically via environment variables in .env)*

**Branch Strategy:**

* main: Represents the stable, production-ready release used by active, production Sentinel instances.  
* develop: The primary integration branch used for continuous integration, feature testing, and staging new orchestrator capabilities before release.

## **Deliverables**

1. **Fully functional notifier\_service.py:** A complete, deployable FastAPI application bound to a secure webhook URL, demonstrably capable of receiving GitHub events, validating HMAC signatures, and queueing actionable tasks.  
2. **Fully functional orchestrator\_sentinel.py:** A robust, asynchronous polling mechanism designed to run as a persistent background daemon (e.g., via systemd), capable of claiming tasks and managing state transitions without race conditions.  
3. **Shell bridge integration:** A deeply integrated script suite (devcontainer-opencode.sh) and corresponding DevContainer configurations (devcontainer.json, Dockerfile) that successfully marshal the environment, inject secure variables, and execute Opencode agents against generated context workflows without leaking state to the host.  
4. **A complete suite of Markdown instruction modules:** Thoroughly engineered prompts located in the local\_ai\_instruction\_modules directory, covering the entire lifecycle of software development: initial planning, execution, testing, and automated bug-fixing phases.

---

## **Appendix: Future Work**

*The following features and test cases are deferred from the current iteration. They are documented here for future planning.*

### **Deferred Features**

* **Hierarchical Task Delegation (Phase 3):** A capability where the AI acts as its own project manager. Utilizing an "Architect Sub-Agent," the system can digest a large, monolithic Epic description and autonomously decompose it into a sequentially ordered list of smaller, discrete child tasks (User Stories). It then creates these new issues in GitHub, linking them back to the parent Epic via markdown task lists in the parent issue body or GitHub native issue tracking relationships.
* **Self-Healing/Reconciliation Loop (Phase 3):** An automated recovery mechanism for "zombie" tasks. If an issue remains in the agent:in-progress state longer than a configurable timeout threshold (defined via a TASK\_TIMEOUT\_MINUTES environment variable, defaulting to 120), the system assumes the worker container crashed silently. The Sentinel will automatically transition the state back to agent:queued and append a warning comment, allowing a fresh worker to retry the execution.
* **Cost Guardrails & Resource Safety (Dev Plan Story 6):** The Sentinel monitors LLM usage costs so that the system does not exceed the daily budget during an autonomous loop. The `WorkItemStatus.STALLED_BUDGET` label and the `agent:stalled-budget` state are defined in the shared model but the monitoring logic is deferred until the core polling-claim-execute loop is stable.
* **Cross-Repo Org-Wide Polling:** Polling via the GitHub Search API (`GET /search/issues?q=label:agent:queued+org:{ORG}+is:issue+is:open`) for org-wide task discovery across multiple repos. Currently the Sentinel targets a single repo via `GITHUB_REPO`.
* **Configurable Environment Reset Modes:** Three-mode environment teardown between tasks (`"none"` / `"stop"` / `"down"`), controlled by an env var. Currently hardcoded to `"stop"`.

### **Deferred Test Cases**

* **TC-05 (Cost Management):** Inject a mock LLM usage report indicating the session has exceeded the pre-configured token/budget limit. The Orchestrator must immediately halt the worker execution, prevent further API calls, and flag the issue with the agent:stalled-budget label, protecting against runaway infrastructure costs.
* **TC-06 (Feedback Loop):** Simulate a human developer leaving a "Request Changes" review on a PR generated by the agent. The webhook receiver must catch the pull\_request\_review event, parse the reviewer's comments, automatically transition the parent issue from agent:success back to agent:queued (or a specific agent:revision state), and append the feedback to the context payload for the next run.
