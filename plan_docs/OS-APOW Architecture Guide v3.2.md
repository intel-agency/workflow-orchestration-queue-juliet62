# **Architecture Guide: workflow-orchestration-queue**

## **1\. Executive Summary**

workflow-orchestration-queue represents a paradigm shift from **Interactive AI Coding** to **Headless Agentic Orchestration**. Traditional AI developer tools require a human-in-the-loop to navigate files, provide context, and trigger executions. workflow-orchestration-queue replaces this manual overhead with a persistent, event-driven infrastructure. It transforms standard project management artifacts—specifically GitHub Issues—into "Execution Orders" that are autonomously fulfilled by specialized AI agents. This system moves the agent from a passive co-pilot role to a background production service capable of multi-step, specification-driven task fulfillment without human intervention.

The system is designed to be **Self-Bootstrapping**. The initial deployment is seeded from a clone of the workflow-orchestration-queue-juliet62, which provides the foundational Docker/DevContainer configs and the devcontainer-opencode.sh bridge. Once the "Sentinel" is active, the system uses its own orchestration capabilities (via the project-setup workflow) to refine its components, effectively allowing the AI to "build its own house" while residing within it. This details the transition from a manual seed to an autonomous engine by using its own orchestration logic to configure its internal environment and indices.

## **2\. System Level Diagram & Component Overview**

### **A. Work Event Notifier (The "Ear")**

* **Technology Stack:** Python 3.12, FastAPI, UV for high-speed dependency management, Pydantic for strict schema validation.  
* **Role:** The system's primary gateway for external stimuli and asynchronous triggers.  
* **Responsibilities:**  
  * **Secure Webhook Ingestion:** Exposes a hardened endpoint to receive issues, issue\_comment, and pull\_request events from the GitHub App.  
  * **Cryptographic Verification:** Every incoming request is validated using HMAC SHA256 against the WEBHOOK\_SECRET. This prevents "Prompt Injection via Webhook" by ensuring only verified GitHub events can trigger agent actions. This security necessity addresses a specific threat model—preventing unauthorized "Spec-Issues" from being injected into the pipeline by spoofing GitHub payloads.  
  * **Intelligent Event Triage & Manifest Generation:** Notifier parses the issue body and labels using Pydantic models to map diverse GitHub payloads into a unified WorkItem object. Crucially, it generates a structured **WorkItem Manifest (JSON)**—persisted either in a shared volume or as a hidden metadata block in the GitHub Issue—allowing the Sentinel and Worker to share machine-readable state without fragile natural language re-parsing at every step.  
  * **Queue Initialization:** If a valid trigger is detected, the Notifier uses the GitHub REST API to apply the agent:queued label, signaling the Sentinel to begin processing.

### **B. Work Queue (The Logic State)**

* **Implementation:** Distributed state management via GitHub Issues, Labels, and Milestones.  
* **Philosophy: "Markdown as a Database":** By leveraging GitHub as the persistence layer, the system gains world-class audit logs, transparent versioning of requirements, and an out-of-the-box UI for human supervision. This high transparency allows humans to perform real-time "intervention-via-commenting" if the agent goes off-course.  
* **State Machine Detail (Label Logic):**  
  * agent:queued: The task has passed validation and is awaiting an available Sentinel instance.  
  * agent:in-progress: A Sentinel has claimed the issue. **Implication:** The issue is assigned to the Agent's GitHub profile to prevent concurrency collisions. "Assignees" act as a distributed lock, preventing two agent instances from grabbing the same ticket.  
  * agent:reconciling: A specialized state for a "Reconciliation Loop" in the Sentinel. If a Sentinel instance crashes while a task is 'in-progress', a background loop identifies "stale" tasks (e.g., no updates for 15 minutes) and moves them here for re-assignment or recovery, ensuring the system is truly self-healing.  
  * agent:success: The workflow reached a terminal success state (e.g., PR created and tests passed).  
  * agent:error: A technical failure occurred. **Detail:** The agent automatically posts the last 50 lines of the worker's stderr as a comment for the developer. This protocol ensures the system doesn't just stall; it reports diagnostic logs back to the issue UI.  
* **Concurrency Control:** The system utilizes GitHub "Assignees" as a semaphore. A Sentinel will only pick up a queued task if it can successfully assign the issue to itself **and verify the assignment by re-fetching the issue** (assign-then-verify pattern). This two-step check ensures no two Sentinel instances can claim the same ticket, even under simultaneous API calls. If another Sentinel won the race, the loser aborts gracefully and moves to the next queued item. The `SENTINEL_BOT_LOGIN` env var must be set to the GitHub login of the bot account used by the Sentinel.

### **C. The Sentinel Orchestrator (The "Brain")**

* **Technology Stack:** Python (Async Background Service), PowerShell Core (pwsh), Docker CLI.  
* **Role:** The persistent supervisor that manages the lifecycle of Worker environments and maps high-level intent to low-level shell commands.  
* **Lifecycle Management Detail:**  
  1. **Polling Discovery:** Every 60 seconds (configurable), the Sentinel scans the configured repository for issues with the agent:queued label using the GitHub Issues API (`GET /repos/{owner}/{repo}/issues?labels=agent:queued&state=open`). Cross-repo org-wide polling via the GitHub Search API is planned for a future phase. This strategy uses a configurable heartbeat and interval-based discovery to ensure a steady task discovery cycle. On rate-limit responses (HTTP 403/429), the Sentinel applies **jittered exponential backoff** to avoid hammering the API.  
  2. **Auth Synchronization:** Before execution, it runs scripts/gh-auth.ps1 and scripts/common-auth.ps1. This ensures that the environment has the necessary scoped installation tokens to perform git operations and API calls, explicitly linking the Orchestrator's logic to your provided authentication infrastructure.  
  3. **The Shell-Bridge Protocol:** The Sentinel manages the Worker via three primary commands, utilizing formalized return codes (e.g., Exit 0 \= Success, Exit 1-10 \= Infra Error, Exit 11+ \= Logic/Agent Error) to determine if it should retry or escalate to a human:  
     * ./scripts/devcontainer-opencode.sh up: Ensures the Docker network and base volumes are provisioned.  
     * ./scripts/devcontainer-opencode.sh start: Launches the opencode-server inside the DevContainer.  
     * ./scripts/devcontainer-opencode.sh prompt "{workflow\_instruction}": This is the core "dispatch" mechanism.  
  4. **Workflow Mapping:** It translates the issue type into a specific prompt string. For example, an issue with the epic label triggers the implement-epic workflow module. The metadata is used to select the correct agent-instruction module for precise prompt construction.  
  5. **Telemetry:** The Sentinel captures the Worker's stdout and streams it to a local log file, while periodically updating the GitHub issue with "Heartbeat" comments to let the user know the agent is still alive. **Heartbeats are posted every 5 minutes** (configurable via `SENTINEL_HEARTBEAT_INTERVAL`) by a background `asyncio` coroutine running concurrently with `process_task()`. This is critical because `devcontainer-opencode.sh prompt` calls can take 15+ minutes during subagent delegation with zero client-side output. The heartbeat is cancelled when the task completes.
  6. **Environment Reset:** After each task, the Sentinel stops the worker container to prevent state bleed between tasks, while keeping it available for fast restart on the next task.
  7. **Graceful Shutdown:** The Sentinel handles `SIGTERM` and `SIGINT` signals. On receipt, it sets a shutdown flag, finishes the current task, closes the `httpx` connection pool, and exits cleanly. This prevents orphaned `agent:in-progress` issues when the container is stopped.

### **D. Opencode Worker (The "Hands")**

* **Technology Stack:** opencode-server CLI, LLM Core (GLM-5 or Claude 3.5 Sonnet).  
* **Environment:** A high-fidelity DevContainer built from the workflow-orchestration-queue-juliet62.  
* **Worker Capabilities:**  
  * **Contextual Awareness:** Accesses the local project structure and uses ./scripts/update-remote-indices.ps1 to maintain a vector-indexed view of the codebase. This emphasizes that the agent remains context-aware by running the indexing script as part of its setup.  
  * **Instructional Logic:** Reads and executes the .md workflow modules stored in /local\_ai\_instruction\_modules/. This allows the Orchestrator to "upgrade" the agent's logic simply by committing new markdown files to the repository. This "Logic-as-Markdown" principle highlights system flexibility, allowing workflows to be updated without changing Python code.  
  * **Verification:** Before submitting a PR, the worker is instructed to run local test suites within the container to ensure zero-regression code generation.

## **3\. Key Architectural Decisions (ADRs)**

### **ADR 07: Standardized Shell-Bridge Execution**

* **Decision:** The Orchestrator interacts with the agentic environment *exclusively* via the ./scripts/devcontainer-opencode.sh script.  
* **Rationale:** The existing shell infrastructure handles complex Docker logic, including volume mounting, SSH-agent forwarding, and host-to-container port mapping. Re-implementing this in Python would create a maintenance nightmare and introduce "Configuration Drift"—where the agent runs in a different environment than a local developer. Reusing the shell scripts instead of the Python Docker SDK ensures perfect environment parity.  
* **Consequence:** The Python code remains lightweight and focused on logic/state, while the Shell scripts handle the "Heavy Lifting" of container orchestration. This identifies a clear separation of concerns between the "Logic Layer" and the "Infra Layer."

### **ADR 08: Polling-First Resiliency Model**

* **Decision:** The Sentinel uses a polling loop as its primary discovery mechanism; Webhooks (the Notifier) are treated as an "Optimization."  
* **Rationale:** Webhooks are "Fire and Forget." If the workflow-orchestration-queue server is down for maintenance or a power cycle during a GitHub event, that event is lost forever. Polling ensures that upon every restart, the Sentinel performs a "State Reconciliation" by looking at GitHub labels, making the system inherently self-healing and resilient against server downtime or network partitions.

### **ADR 09: Provider-Agnostic Interface Layer**

* **Decision:** All queue interactions are abstracted behind a strictly defined ITaskQueue interface using the Strategy Pattern.  
* **Rationale:** While Phase 1 is built for GitHub, the architecture is designed for "Ticket Provider Swapping." The interface must include: fetch\_queued(), claim\_task(id, sentinel\_id), update\_progress(id, log\_line), and finish\_task(id, artifacts). This ensures that Phase 1 code is actually reusable for support of Linear, Notion, or internal SQL queues without a rewrite of the Orchestrator's core dispatch logic.

## **4\. Data Flow (The "Happy Path")**

1. **Stimulus:** A user opens a GitHub Issue using the application-plan.md template.  
2. **Notification:** The GitHub Webhook hits the **Notifier** (FastAPI).  
3. **Triage:** The Notifier verifies the signature, confirms the title starts with \[Plan\], and calls the GH API to add the agent:queued label. This step includes specific signature and title pattern checks that occur before a task is queued.  
4. **Claim:** The **Sentinel** poller detects the new label. It assigns the issue to the Agent account and updates the label to agent:in-progress.  
5. **Sync:** Sentinel runs git clone or git pull on the target repo into a managed workspace volume, ensuring the local repository state is synced before the Worker container begins work.  
6. **Environment Check:** Sentinel executes devcontainer-opencode.sh up.  
7. **Dispatch:** Sentinel sends the command: ./scripts/devcontainer-opencode.sh prompt "Run workflow: create-app-plan.md for context: <https://github.com/org/repo/issues/123>".  
8. **Execution:** The **Worker** (Opencode) reads the issue, analyzes the tech stack, and calls the GitHub API to create 5 new "Epic" issues, each linked back to the parent Plan. This fleshes out how an "Application Plan" autonomously results in the creation of sub-tasks.  
9. **Finalize:** The Worker posts a "Execution Complete" comment. The Sentinel detects the subprocess exit, removes the in-progress label, and adds agent:success.

## **5\. Security, Authentication & Isolation**

* **Network Isolation:** Worker containers run in a dedicated Docker network. They can reach the internet to fetch packages but cannot access the Orchestrator's host network or local subnet. This isolation strategy prevents an agent from probing the local host infrastructure.  
* **Credential Scoping:** The Sentinel manages the GitHub App Installation Token. This token is passed to the Worker container via a temporary environment variable that is destroyed as soon as the session ends. This "least privilege" model limits worker access to only what is necessary for the current task.  
* **Credential Scrubbing & Audit Trail:** All log output from the Worker is piped through a regex-based "Scrubber" (`scrub_secrets()` in `src/models/work_item.py`). The scrubber strips patterns matching GitHub PATs (`ghp_*`, `ghs_*`, `gho_*`, `github_pat_*`), Bearer tokens, API keys (`sk-*`), and ZhipuAI keys. It produces a sanitized log for GitHub visibility and a raw log for local forensic audit trails (The "Black Box"). This creates an internal record for forensics while preventing accidental leaking of sensitive credentials into public comments.  
* **Resource Constraints:** Worker containers are assigned strict CPU and RAM limits (e.g., 2 CPUs, 4GB RAM) to prevent a "rogue agent" from causing a denial-of-service on the host server. This protects the host infrastructure and ensures orchestrator stability.

## **6\. Self-Bootstrapping Lifecycle**

workflow-orchestration-queue is built to be an iterative, evolving system.

1. **Bootstrap:** The developer manually clones the workflow-orchestration-queue-juliet62.  
2. **Seed:** The developer adds these plan docs to the repo and runs the create-repo-from-plan-docs script.  
3. **Init:** The developer runs devcontainer-opencode.sh up for the first time.  
4. **Orchestrate:** The developer uses the orchestrate-dynamic-workflow command with the project-setup assignment to allow the agent to configure its own environment variables and index the codebase. This phase transitions the system from human-managed setup to agent-managed environment configuration.  
5. **Autonomous Phase:** Once initialized, the "Sentinel" service is started on the server, and from that point forward, the AI manages all further development of the workflow-orchestration-queue system itself.
