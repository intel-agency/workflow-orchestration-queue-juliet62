# Orchestrator Supervisor

## Concept

Run a second `opencode serve` instance (the **supervisor**) at a known address, passed to the regular orchestrator during startup. The orchestrator saves this address. Whenever the orchestrator finishes — success or failure — its final action is to POST a status payload to the supervisor containing:

- A structured status report (outcome, error details, partial progress)
- The orchestrator's own address (so the supervisor can prompt it back)

The supervisor evaluates the report and decides:
- **Success** → advance to the next workflow stage, or close out
- **Recoverable failure** → craft a corrective prompt and send it back to the orchestrator at its address
- **Unrecoverable failure** → log, alert, stop

This creates a **leapfrog** pattern: orchestrator prompts supervisor → supervisor prompts orchestrator → repeat. The supervisor course-corrects across runs without human intervention.

## Feedback

**This is a strong idea.** It directly addresses the biggest weakness we hit in november57-b: the orchestrator failed, hallucinated a reason, output "Manual Steps Required," and the pipeline stopped dead. There was no recovery path — the workflow just ended. A supervisor would have caught the structured error, seen "PR creation returned non-zero," and could have re-prompted with "The branch has no commits ahead of main. Push an initial commit first, then retry `gh pr create`."

### What it solves

1. **No more dead-end failures.** Today if the orchestrator fails mid-assignment (PR creation, label import, project creation), the entire workflow run ends and you have to manually re-trigger. The supervisor can retry or adjust.

2. **Hallucination recovery.** When the model fabricates a reason for failure (like "Actions token permissions" when the real issue was an empty branch), the supervisor sees the *actual* exit code and stderr — not the model's narrative. It can re-prompt with ground truth.

3. **Cross-run state continuity.** Right now each `orchestrator-agent.yml` run is stateless — it gets an event payload and that's it. The supervisor maintains context across the leapfrog cycle, so retries don't start from scratch.

4. **Graceful degradation in the `implementation:ready` → `create-epic-v2` chain.** Currently if one epic fails, the whole chain stops. The supervisor could skip a failed epic, note it, and advance to the next.

### Architectural fit

The fact that the supervisor is just another `opencode serve` instance (same devcontainer image, same scripts) is the right call. It means:

- No new infrastructure — same Docker image, same deployment mechanism
- The supervisor gets all the same tools (`gh`, `opencode`, MCP servers)
- It can be tested with the exact same `devcontainer-opencode.sh` wrapper
- The supervisor prompt is just another assembled markdown file, like `orchestrator-agent-prompt.md`
- The supervisor prompt will be located at `.github/workflows/prompts/orchestrator-supervisor-agent-prompt.md`

### Concerns and open questions

1. **GitHub Actions job timeout.** A single workflow job has a 6-hour max. The leapfrog cycle adds round-trips. If the supervisor and orchestrator are in the same job, the hard ceiling applies to the whole cycle. If they're in separate jobs, you need a mechanism to trigger the next job (which is the same `GITHUB_TOKEN` vs PAT problem we just fixed).

2. **Cost multiplication.** Each leapfrog hop is a full LLM session. A 3-hop recovery cycle triples the API cost of that workflow stage. Need a max-hops cap (suggest: 3 retries, then escalate to human).

3. **Supervisor prompt design.** The supervisor needs to be opinionated but minimal — it shouldn't re-do the orchestrator's job. Its prompt should be: "Here's the status report. Decide: retry with corrections, skip and advance, or stop and alert." If the supervisor prompt is too open-ended, it'll hallucinate its own plans.

#### **4. Address passing mechanism.**

 `opencode serve` listens on a port. In the same container, this is trivial (localhost:4096 vs localhost:4097). Across containers or across workflow runs, you'd need service discovery or a fixed convention. Suggest: supervisor always at `:4097`, orchestrator always at `:4096`.

##### Implementation

This is handled by setting thje supervisor's host and port, new orchestrators will be passed whatever the supervisor's host and port are. This just laves the external address (if any). So it doesnt have to be specified by convention, since the actual value the supervisor is using wil be passed to the orcehstrators. This means the supervisor is alwayus started before any orchestrators. And for the first phase we will deply to the same subnet or LAN, so no need for service discovery or external portion of the address is necessary.


1. **Status report schema.** The payload from orchestrator → supervisor needs a defined structure, not free-form text. Otherwise the supervisor is parsing natural language, which is unreliable. The payload should include **all logs and output** — the supervisor's main advantage over a human is that it can ingest the full trace, not just a summary. Suggested JSON envelope:

```json
{
  "outcome": "failure",
  "assignment": "init-existing-repository",
  "step": "Create PR",
  "error_code": 1,
  "hop": 1,
  "max_hops": 3,
  "orchestrator_address": "http://127.0.0.1:4096",
  "run_id": "23384757066",
  "elapsed_seconds": 912,
  "model_narrative": "PR creation failed due to Actions token permissions",
  "logs": {
    "client_output": "<full stdout/stderr from opencode run, captured by run_opencode_prompt.sh>",
    "server_log": "<tail of /tmp/opencode-serve.log — subagent spawns, tool calls, errors>",
    "session_trace": "<tail of /tmp/opencode-traces/*.log — the 11MB-class session log>",
    "git_status": "<output of git status --short at exit>",
    "gh_auth_status": "<output of gh auth status at exit>"
  }
}
```

   **Why ship the logs:** In the november57-b investigation, the model said "Actions token permissions" but the actual error was "No commits between main and branch." The `model_narrative` field is what the orchestrator *thinks* happened. The `logs` fields are what *actually* happened. The supervisor should always trust `logs` over `model_narrative`. This is the entire point — ground truth recovery.

   **Size concern:** Session traces can be 10+ MB. For same-container (localhost) this is fine. For cross-network, truncate to last N lines (suggest: last 500 lines of each log, plus any lines matching `error|fail|fatal|denied|refused`). The status report schema should define a `max_log_bytes` field the orchestrator respects.

1. **Infinite loop prevention.** If the orchestrator keeps failing the same step, the supervisor could keep retrying forever. Need: (a) a retry counter per step, (b) a backoff strategy (e.g. add more context on each retry), (c) a hard stop after N attempts.

1. **Who starts the supervisor?** Options:
   - **Same workflow job** — `start-opencode-server.sh` launches two instances on different ports. Simple but shares the job timeout.
   - **Separate workflow job** — supervisor runs in a prior job, orchestrator connects to it. More isolated but needs networking between jobs (not trivial on Actions runners).
   - **Always-on service** — supervisor runs persistently outside Actions (e.g. on a small VM or as a GitHub App webhook handler). Most powerful but introduces infrastructure.

   For v1, same-job with two ports is the pragmatic choice.

## Implementation sketch

### Phase 1: Same-job dual-server

```
orchestrator-agent.yml
  └─ orchestrate job
       ├─ devcontainer up
       ├─ start-opencode-server.sh --port 4097  (supervisor)
       ├─ start-opencode-server.sh --port 4096  (orchestrator)
       ├─ run_opencode_prompt.sh -a :4096 -f orchestrator-prompt.md
       │    └─ orchestrator runs assignments...
       │    └─ on exit: POST status to :4097
       ├─ supervisor evaluates, optionally re-prompts :4096
       └─ repeat until supervisor says "done" or max-hops reached
```

### Phase 2: Structured status reports

Add a "## Supervisor Report" section to the orchestrator prompt that instructs it to always emit a JSON status block as its final output, regardless of success or failure.

### Phase 3: Supervisor prompt

A minimal prompt:
- Parse the incoming status report
- If success: check if more work remains, advance or close
- If failure: analyze error_code + stderr (ignore model_narrative), craft a targeted correction prompt, send back
- If max retries exceeded: comment on the issue with a failure summary, stop

### Changes required

| File | Change |
|------|--------|
| `start-opencode-server.sh` | Accept `--port` argument; generate self-signed TLS cert at startup; pass `--tls-cert`/`--tls-key` to `opencode serve` |
| `devcontainer-opencode.sh` | Add `supervisor` command that starts second server |
| `run_opencode_prompt.sh` | Add `--supervisor-url` flag, emit status payload on exit |
| `orchestrator-agent.yml` | Add supervisor startup step before orchestrator execution |
| New: `supervisor-prompt.md` | Supervisor system prompt with recovery decision tree |
| New: `status-report-schema.json` | JSON schema for orchestrator → supervisor payloads |

## Security: Authentication and Authorization

### Phase 1: Same container, same LAN — keep it simple

For phase 1, both the supervisor (`:4097`) and orchestrator (`:4096`) run inside the **same devcontainer** on the same Actions runner. The threat model is minimal:

- **Network boundary:** localhost only. Both servers bind to `127.0.0.1` (or `0.0.0.0` within the container, but the container's network namespace is isolated from the host and the internet). No ports are exposed outside the runner VM.
- **Authentication:** `opencode serve` already supports basic auth via `OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` env vars. Both servers share the same container env, so they share the same credentials. This is sufficient — it prevents accidental cross-talk but there's no untrusted party on localhost.
- **Token inheritance:** Both servers inherit the same `GH_TOKEN` (PAT) from the container env. The supervisor doesn't need separate credentials — it operates with the same GitHub permissions as the orchestrator.
- **TLS even on localhost (zero-trust stance):** Self-signed TLS is required from day one. Even on loopback, plaintext HTTP is unacceptable because: (1) a prompt-injection exploit could trick a subagent into exfiltrating the PAT from an intercepted HTTP payload — catastrophic if the PAT has `repo + workflow` scope; (2) TLS provides identity verification — the supervisor knows it's talking to the real orchestrator, not a rogue process that grabbed the port first; (3) self-signed certs are trivially cheap to generate at container startup (`openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj '/CN=localhost'`). Generate a fresh keypair in `start-opencode-server.sh` before launching the daemon and pass `--tls-cert` / `--tls-key` (or the env-var equivalents) to `opencode serve`.
- **Payload trust:** The status report JSON travels over TLS-encrypted localhost. Combined with basic auth, this provides confidentiality, integrity, and mutual authentication within a single container. No need for HMAC signing in phase 1.

No- they can have their own containers. This is a critical distinction.

**What this means:** Phase 1 security is "same container, same user, but zero-trust networking." Basic auth + self-signed TLS is the minimum viable gate — both are already cheap to implement and defend against the most dangerous threat vector: prompt injection leading to credential theft.

### Phase 2+: Cross-network considerations (future)

If the supervisor moves to a separate runner, VM, or always-on service, the threat model changes significantly:

| Concern | Phase 1 (localhost) | Phase 2+ (cross-network) |
|---------|---------------------|--------------------------|
| Transport | Self-signed TLS, localhost | **CA-signed TLS** — mutual TLS preferred |
| Authentication | Shared basic auth env var | **Per-instance credentials** — supervisor and orchestrator get unique tokens |
| Authorization | N/A (same trust domain) | **Role-based** — supervisor can prompt orchestrator, but not vice versa without supervisor approval |
| Payload integrity | TLS + basic auth (localhost) | **HMAC-signed payloads** — defense-in-depth against TLS termination bugs |
| Token scope | Shared PAT | **Separate PATs** — supervisor gets `repo, workflow, read:org`; orchestrator gets `repo` only (least privilege) |
| Network exposure | Container-internal | **Firewall rules** — allowlist supervisor IP; deny all others |
| Secrets in logs | Logs stay on ephemeral runner | **Redact secrets from status payloads** — logs may contain tokens, API keys in env dumps |
| Prompt injection | TLS mitigates credential theft; schema validation recommended | **Validate status report schema strictly** — a compromised orchestrator could craft malicious recovery prompts |

**Recommendation:** Don't build any of this until phase 1 proves the leapfrog pattern works. The security complexity of cross-network is substantial and should only be incurred when there's a demonstrated need to separate the supervisor from the orchestrator's runtime.

Agreed. We may never even graduate to extra-subnet supervision.

---

## Architecture Exploration: Many-to-One + Separate Containers

The original design assumed a 1:1 dual-server within a single container and a single Actions job. Two key shifts reframe the architecture:

1. **Many orchestrators, one supervisor.** The supervisor is a singleton that oversees *all* concurrent orchestrator runs across multiple repos. Each `orchestrator-agent.yml` run spawns its own orchestrator container, but they all report to the same long-lived supervisor.
2. **Separate containers.** The supervisor runs in its own container (or VM/service), not colocated with any orchestrator. Orchestrators are ephemeral (Actions job lifetime); the supervisor is always-on.

The supervisor's lifetime strictly contains every orchestrator's — it is started before any orchestrators and always outlives them.

### What this looks like

```
┌─────────────────────────────────────────────────────┐
│           SUPERVISOR (always-on container)           │
│   opencode serve :4097  ──  supervisor-prompt.md     │
│   Accepts status reports, issues corrective prompts  │
│   Maintains registry of active orchestrator sessions │
└──────────┬──────────────┬──────────────┬────────────┘
           │              │              │
     TLS + basic auth     │        TLS + basic auth
           │              │              │
┌──────────▼──┐  ┌────────▼───┐  ┌──────▼────────────┐
│ Orch A      │  │ Orch B     │  │ Orch C            │
│ repo: nov57 │  │ repo: dec12│  │ repo: jan03       │
│ :4096       │  │ :4096      │  │ :4096             │
│ (ephemeral) │  │ (ephemeral)│  │ (ephemeral)       │
└─────────────┘  └────────────┘  └───────────────────┘
  Actions job 1    Actions job 2    Actions job 3
```

Each orchestrator container:
- Gets the supervisor's address as an env var or CLI flag at startup
- Runs its assignment as normal
- On exit (success or failure), POSTs the status report JSON to the supervisor
- The supervisor can prompt back into any orchestrator at its address, as long as that orchestrator's job is still alive

The supervisor container:
- Runs independently of GitHub Actions job boundaries
- Maintains a session registry: `{run_id, repo, orchestrator_address, status, hop_count}`
- Can handle multiple concurrent leapfrog cycles without confusion
- Persists across orchestrator crashes (the whole point)

### Implementation: What changes

| Component | Current state | Required change |
|-----------|--------------|-----------------|
| **Supervisor container** | Doesn't exist | New: standalone container from same devcontainer image, running `opencode serve :4097` with supervisor prompt. Needs its own PAT, TLS cert, and basic auth credentials. Deployed as a long-running service (Docker Compose, systemd, or a lightweight VM). |
| **`orchestrator-agent.yml`** | Starts opencode server + prompt in same container | Add `SUPERVISOR_URL` env var (set as repo secret or org-level variable). Remove supervisor startup steps — the supervisor is already running externally. |
| **`run_opencode_prompt.sh`** | Exits after orchestrator completes | On exit: collect logs, build status report JSON, POST to `$SUPERVISOR_URL`. Must handle the case where POST fails (see below). |
| **`start-opencode-server.sh`** | Starts one server, hardcoded port | Orchestrator side: unchanged (still `:4096` inside its own container). Supervisor side: new startup script or parameterized with `--port 4097 --tls-cert ... --supervisor-mode`. |
| **Supervisor prompt** | Doesn't exist | New: `supervisor-prompt.md` — must handle concurrent reports from multiple repos. Needs repo-aware context: "You are supervising runs for repos X, Y, Z. Here is a status report from repo X's orchestrator." |
| **Status report schema** | Doesn't exist | Add `repo` and `repo_url` fields to the JSON envelope so the supervisor can disambiguate concurrent orchestrators. |
| **Networking** | localhost | Orchestrator containers must be able to reach the supervisor's host:port. Same Docker network (Compose), same VPC, or exposed endpoint. |
| **TLS** | Self-signed on localhost | Supervisor needs a stable TLS cert (self-signed is fine if all orchestrators trust it, but the cert can't rotate every container startup like it would for ephemeral orchestrators). Distribute the supervisor's CA cert to orchestrator containers via env var or mounted secret. |
| **Auth credentials** | Shared env vars in one container | Per-orchestrator credentials or a shared secret distributed via Actions secrets. Each orchestrator authenticates to the supervisor; the supervisor authenticates back to each orchestrator. |
| **Session registry** | N/A (single session) | Supervisor needs in-memory (or persisted) tracking of which orchestrators are alive, their addresses, hop counts, and assignment state. |

### Biggest concerns

#### 1. Supervisor is a single point of failure

Every orchestrator depends on the supervisor being reachable. If the supervisor goes down, *all* in-flight orchestrators lose their recovery path. Mitigations:
- Health check endpoint on the supervisor (`GET /healthz`), monitored externally
- Orchestrators should degrade gracefully if the supervisor is unreachable (see "Unreachable supervisor" below)
- The supervisor is a single `opencode serve` process — if it crashes, restart it (systemd, Docker restart policy). State is lost but orchestrators can re-register.

#### 2. Networking across containers

GitHub Actions runners are ephemeral VMs. An orchestrator container on one runner can't reach a supervisor on a different runner by default. Options:
- **Same runner, Docker network:** Use `docker network create` in the workflow to put both containers on a shared bridge. Simplest, but the supervisor dies when the runner's job ends.
- **External supervisor on a fixed host:** Supervisor runs on a small VM or cloud instance with a stable hostname/IP. Orchestator containers reach it over the network. This is the natural fit for always-on.
- **Tailscale/WireGuard mesh:** Each runner joins a VPN mesh, supervisor has a stable mesh IP. Zero infrastructure beyond the mesh. Adds a dependency but keeps everything private.

For v1 with same-subnet deployment: supervisor runs on a known host within the same network, orchestrator containers reach it by IP or DNS name. No service discovery needed since the supervisor address is passed to orchestrators at startup.

#### 3. Orchestrator address reachability from supervisor

The leapfrog pattern requires the supervisor to prompt *back* to the orchestrator. But an orchestrator running inside a GitHub Actions runner's container is not routable from outside that runner. This is the hardest networking problem.

Options:
- **Orchestrator polls supervisor** instead of supervisor pushing to orchestrator. The orchestrator POSTs its status, then polls `GET /directive/{run_id}` until the supervisor responds with a corrective prompt or "done." This reverses the connection direction — only outbound from orchestrator is needed, which always works.
- **Supervisor opens a tunnel** — orchestrator exposes its port via a reverse tunnel (e.g., `ssh -R`) back to the supervisor host at startup. Fragile, adds complexity.
- **Webhook callback** — supervisor triggers a new `workflow_dispatch` event on the orchestrator's repo with the corrective prompt as an input. This uses the GitHub API (always reachable) instead of direct network access. Downside: each hop is a new workflow run, not a prompt to an existing server.

**Recommendation:** The polling pattern is the safest default. Orchestrators only need outbound HTTPS to the supervisor — no inbound ports, no tunnels, works through any NAT or firewall. The supervisor queues directives; orchestrators pick them up.

#### 4. Concurrent leapfrog confusion

With N orchestrators reporting simultaneously, the supervisor's LLM context gets interleaved status reports from different repos. Risk of cross-contamination: the supervisor crafts a corrective prompt for repo A using context from repo B's error.

Mitigations:
- Each supervisor prompt invocation is scoped to a single orchestrator's status report. Don't batch reports.
- The session registry is the source of truth — the supervisor prompt includes only the relevant repo's history, not all concurrent sessions.
- Enforce `run_id` + `repo` as a compound key in every interaction.

#### 5. Cost and resource management

An always-on supervisor is a persistent cost even when no orchestrators are running. Unlike the dual-server-in-one-job model, this supervisor idles between workflow triggers.

Mitigations:
- Use the cheapest viable instance (the supervisor's LLM calls are infrequent — only on orchestrator exit)
- Auto-shutdown after N minutes of no incoming reports (and auto-start on first incoming report via a lightweight webhook proxy)
- The supervisor's `opencode serve` process itself is cheap — it's the LLM API calls that cost money, and those only happen on orchestrator check-ins

#### 6. State loss on supervisor restart

If the supervisor crashes and restarts, it loses its in-memory session registry. An orchestrator that was mid-leapfrog now has a supervisor with no history of their conversation.

Mitigations:
- Persist the session registry to disk (JSON file) or a lightweight store (SQLite)
- Each status report includes full context (logs, assignment, step) — the supervisor can reconstruct state from the latest report alone without needing prior history
- This favors a stateless supervisor design: every decision is made from the current status report, not accumulated conversation

### Critical question: What happens if the supervisor can't be reached?

This is the most important failure mode to get right because it determines whether the supervisor *improves* reliability or *reduces* it. If an unreachable supervisor causes orchestrators to hang or crash, we've made things worse.

**Proposed behavior — fail-open with degraded capability:**

```
Orchestrator exits (success or failure)
  └─ Attempt POST status report to SUPERVISOR_URL
       ├─ Success (2xx) → enter poll loop for directive
       │    └─ Poll GET /directive/{run_id} every 30s, timeout after 5min
       │         ├─ Directive received → execute it (corrective prompt)
       │         └─ Timeout / error → log warning, exit normally
       │
       └─ Failure (connection refused, timeout, 5xx)
            ├─ Retry 3x with exponential backoff (2s, 4s, 8s)
            ├─ All retries exhausted:
            │    ├─ Log: "Supervisor unreachable at $SUPERVISOR_URL — proceeding without supervision"
            │    ├─ Comment on GitHub issue: "⚠️ Supervisor unreachable — this run was unsupervised"
            │    └─ Exit with the orchestrator's own exit code (don't mask it)
            └─ The orchestrator's work is NOT rolled back — whatever it accomplished stands
```

**Key principles:**

1. **Fail-open, not fail-closed.** An unreachable supervisor must never block or kill an orchestrator run. The orchestrator did its work; the supervisor is a bonus recovery layer, not a gate.
2. **The orchestrator's exit code is authoritative.** If the orchestrator succeeded, it succeeded — even if it couldn't report to the supervisor. The supervisor missing a success report is a monitoring gap, not a correctness problem.
3. **Visibility over silence.** If the supervisor is unreachable, leave a trace: GitHub issue comment, workflow annotation (`::warning::`), and log entry. Someone will notice.
4. **No retry storms.** Three retries with short backoff, then move on. Don't let a dead supervisor consume the remaining job timeout spinning on connection attempts.
5. **Idempotent status reports.** If the orchestrator's POST succeeds but the poll times out, the supervisor still has the report. It can act on it later (e.g., open an issue, trigger a new workflow). The orchestrator doesn't need to know.

**What this means for the codebase:** The `run_opencode_prompt.sh` exit path needs a robust HTTP client section (curl with `--retry`, `--max-time`, `--connect-timeout`) and a fallback path that comments on the issue via `gh`. This is ~20 lines of shell, not a major engineering effort.

##
