# Subagent Tracing & Logging — Options Report

> **Goal**: Achieve superior delegated subagent tracing and logging for the OS-APOW orchestrator workflow running in GitHub Actions via OpenCode CLI.
>
> **Sources**: `docs/opencode-subagent-tracing/CLI Subagent Tracing and Logging.md`, `docs/opencode-subagent-tracing/Subagent Observability Guide.md`, `scripts/trace-extract.py`, `scripts/WorkItemModel.py`

---

## Executive Summary

OpenCode's subagent architecture deliberately isolates child sessions from parent stdout, making delegated work opaque by default. Six distinct tracing strategies are available, ranging from zero-config CLI flags to full OpenTelemetry distributed tracing. This report evaluates each option on effort, fidelity, cost, and fitness for the OS-APOW headless CI environment, then provides a tiered implementation recommendation.

---

## 1. Options Inventory

### Option A — CLI Flags (`--print-logs --log-level DEBUG`)

| Attribute | Detail |
|---|---|
| **Mechanism** | Pass `--print-logs --log-level DEBUG --format json` to `opencode run` (or `opencode serve`) |
| **What it exposes** | Session creation, Task tool dispatch, child session IDs, LLM request/response payloads, tool executions |
| **Output location** | `stderr` stream (interleaved with TUI if interactive) |
| **Effort** | **Minimal** — one-line change to `run_opencode_prompt.sh` |
| **Fidelity** | Medium-High — all events present but as flat text/JSON on stderr; no structured parent-child linking |
| **Limitations** | Noisy; log volume can be very high on long runs; no built-in filtering by subagent |
| **Best for** | Quick debugging, immediate CI visibility |

### Option B — Environment Variables (`OPENCODE_LOG_LEVEL`, `OPENCODE_VERBOSE`, `OPENCODE_PRINT_LOGS`)

| Attribute | Detail |
|---|---|
| **Mechanism** | Set `OPENCODE_LOG_LEVEL=DEBUG`, `OPENCODE_VERBOSE=true`, `OPENCODE_PRINT_LOGS=true` as GitHub Secrets or workflow env vars |
| **What it exposes** | Same as Option A plus full HTTP headers/payloads to AI providers |
| **Output location** | `stderr` + rotating log files at `~/.local/share/opencode/log/` |
| **Effort** | **Minimal** — add env vars to workflow YAML |
| **Fidelity** | Medium-High — verbose but unstructured |
| **Limitations** | `OPENCODE_VERBOSE=true` dumps raw HTTP bodies including large prompt payloads, inflating log size significantly |
| **Best for** | CI pipelines where CLI flag injection is awkward; always-on baseline tracing |

### Option C — Persistent Log Files + Post-Hoc Extraction

| Attribute | Detail |
|---|---|
| **Mechanism** | OpenCode writes rotating logs to `~/.local/share/opencode/log/*.log` (max 10 files, ISO 8601 timestamped). Use `trace-extract.py` or `grep`/`jq` to isolate subagent sessions by `childSessionId` |
| **What it exposes** | Full execution trace per child session — tool calls, file reads, bash commands, synthesised responses |
| **Output location** | On-disk log files on the runner; uploadable as GitHub Actions artifact |
| **Effort** | **Low** — `trace-extract.py` already exists in the repo; need artifact upload step |
| **Fidelity** | **High** — complete trace per subagent, filterable by session ID |
| **Limitations** | Only 10 most recent log files retained (rotation); long-running orchestrator sessions may lose early subagent traces; post-mortem only |
| **Best for** | Failure diagnosis; artifact-based debug bundles |

### Option D — GitHub Actions Log Grouping + Artifact Upload

| Attribute | Detail |
|---|---|
| **Mechanism** | Wrap execution in `::group::Subagent Traces` / `::endgroup::` blocks; upload `~/.local/share/opencode/log/*.log` as artifacts on failure |
| **What it exposes** | Same raw data as Options A–C, but with UX improvements in the GitHub Actions UI |
| **Output location** | GitHub Actions run log (collapsible groups) + downloadable artifact bundle |
| **Effort** | **Low** — 5-10 lines added to `orchestrator-agent.yml` |
| **Fidelity** | Medium — depends on underlying log level; grouping is cosmetic |
| **Limitations** | Artifact uploads only on failure (by design); collapsed groups still contain unstructured text |
| **Best for** | Operator UX in GitHub; "drill-down on demand" pattern |

### Option E — Plugin-Based Tool Lifecycle Hooks

| Attribute | Detail |
|---|---|
| **Mechanism** | Create a TypeScript plugin at `.opencode/plugins/tracer/index.ts` (or global `~/.config/opencode/plugins/`). Hook `tool.execute.before` and `tool.execute.after` to intercept every tool call with full args and output |
| **What it exposes** | Exact tool name, JSON args, output, execution latency per tool call — for both primary agents and subagents |
| **Output location** | Plugin can write to custom file, or use `client.app.log()` to feed into the native log stream |
| **Effort** | **Medium** — requires writing ~50-100 lines of TypeScript; must install in devcontainer image |
| **Fidelity** | **Very High** — surgical interception of every tool call with before/after correlation |
| **Limitations** | Requires TypeScript/Node.js in the runtime; `client.app.log()` has a known bug where logs don't always appear on stdout (they do persist to files); plugin must be maintained across OpenCode version upgrades |
| **Best for** | Custom audit trails; per-tool latency tracking; security auditing of subagent file/shell operations |

**Known Bug**: In some OpenCode versions (~1.0.220), `client.app.log()` traces don't propagate to `--print-logs` terminal output but *are* written to the log files. Always check files, not just terminal.

### Option F — OpenTelemetry (OTEL) Distributed Tracing

| Attribute | Detail |
|---|---|
| **Mechanism** | Enable `experimental.openTelemetry: true` in `opencode.json`; install `@opentelemetry/sdk-node` (>=0.200); optionally use `@devtheops/opencode-plugin-otel` for OTLP export |
| **What it exposes** | Structured spans: `ai.streamText` (full LLM lifecycle), `ai.toolCall` (exact tool invocations with JSON schema), `ai.streamText.doStream` (network-level chunk tracing). Native parent→child span linking maps subagent work back to the delegating prompt |
| **Output location** | OTLP/gRPC → observability backend (Honeycomb, Jaeger, Grafana, Datadog); or local JSONL file via custom `SpanProcessor` plugin |
| **Effort** | **High** — experimental feature; manual dependency injection; exporter configuration; backend infrastructure |
| **Fidelity** | **Maximum** — structured spans with parent-child relationships, token counts, cost calculations, exact prompts, tool schemas. Mathematically provable audit trail |
| **Limitations** | Experimental status; requires `@opentelemetry/sdk-node` manually installed in the OpenCode runtime; adds performance overhead; needs a trace backend to be useful (unless dumping to local JSONL) |
| **Best for** | Enterprise/fleet monitoring; SLA tracking; cost accounting across swarms; security forensics |

---

## 2. Comparison Matrix

| Criterion | A: CLI Flags | B: Env Vars | C: Log Files + Extract | D: GHA Groups + Artifacts | E: Plugin Hooks | F: OTEL |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Implementation effort | ★☆☆ | ★☆☆ | ★★☆ | ★★☆ | ★★★ | ★★★★ |
| Trace fidelity | ●●●○ | ●●●○ | ●●●● | ●●●○ | ●●●●● | ●●●●● |
| Structured output | No | No | Semi (JSON lines) | No | Yes (custom) | Yes (OTLP spans) |
| Parent→child linking | Manual grep | Manual grep | Script-assisted | Manual grep | Manual correlation | **Native** |
| Real-time visibility | Yes (stderr) | Yes (stderr) | No (post-mortem) | Partial (collapsed) | Depends on sink | Yes (live dashboard) |
| GitHub Actions fit | Good | Good | **Great** | **Great** | Good | Moderate |
| Credential safety | None built-in | None built-in | Via `scrub_secrets()` | None built-in | Custom | None built-in |
| Maintenance burden | None | None | Low | Low | Medium | High |

---

## 3. Existing Tooling in This Repo

### `scripts/trace-extract.py`
- Parses OpenCode rotating JSON logs
- Extracts subagent sessions by `childSessionId`
- Supports `--sentinel-id` filtering for multi-Sentinel environments
- Outputs chronological per-subagent trace dumps
- ~~**Gap**: No credential scrubbing applied to output; no structured export format~~ **Resolved** — see §7

### `scripts/WorkItemModel.py`
- Pydantic model for WorkItem with `WorkItemStatus` enum matching OS-APOW label taxonomy
- `scrub_secrets()` function with patterns for: GitHub PATs (classic, fine-grained, app, OAuth), Bearer tokens, OpenAI keys, ZhipuAI keys
- ~~**Gap**: Not integrated with `trace-extract.py`; scrubber not applied to log artifacts before upload~~ **Resolved** — see §7

---

## 4. Recommendations

### Tier 1 — Implement Immediately (Low Effort, High Impact)

**Combine Options B + C + D** for a complete CI-native tracing stack:

1. **Add env vars to `orchestrator-agent.yml`**:

   ```yaml
   env:
     OPENCODE_LOG_LEVEL: DEBUG
     OPENCODE_PRINT_LOGS: "true"
   ```

2. **Update `run_opencode_prompt.sh`** to include `--format json` when in CI:

   ```bash
   opencode run --prompt "$PROMPT" --thinking --print-logs --log-level DEBUG --format json
   ```

3. **Add GitHub Actions log grouping** around the orchestrator step:

   ```yaml
   - name: Execute Orchestrator
     run: |
       echo "::group::Subagent Traces"
       ./run_opencode_prompt.sh
       echo "::endgroup::"
   ```

4. **Upload log artifacts on failure**:

   ```yaml
   - name: Upload Debug Logs
     if: failure()
     uses: actions/upload-artifact@v4
     with:
       name: opencode-debug-logs
       path: ~/.local/share/opencode/log/*.log
   ```

5. **Integrate `scrub_secrets()` into `trace-extract.py`** — import and apply the scrubber to every log line before output, preventing credential leaks in uploaded artifacts.

6. **Run `trace-extract.py` as a post-step** to produce a distilled summary artifact:

   ```yaml
   - name: Extract Subagent Traces
     if: always()
     run: |
       python3 scripts/trace-extract.py --log ~/.local/share/opencode/log/*.log > subagent-traces.txt
       # Scrub before upload
   ```

### Tier 2 — Implement Next (Medium Effort, Precision Tracing)

**Add Option E — Plugin-based tool hooks**:

- Create `.opencode/plugins/tracer/index.ts` in the devcontainer image
- Hook `tool.execute.before` / `tool.execute.after` to capture:
  - Exact tool name + JSON args (what the subagent *intended* to do)
  - Tool output + exit codes (what *actually happened*)
  - Execution duration per tool call
- Write output directly to a structured JSONL file (don't rely solely on `client.app.log()` due to the known stdout propagation bug)
- Include the `childSessionId` in each log entry for correlation with the parent WorkItem

### Tier 3 — Implement When Scaling (High Effort, Enterprise Observability)

**Add Option F — OpenTelemetry** when running multiple Sentinels:

- Enable `experimental.openTelemetry: true` in `opencode.json`
- Install `@opentelemetry/sdk-node` (≥0.200) into the devcontainer
- Start with local JSONL export via a custom `SpanProcessor` plugin (air-gapped, no external dependency)
- Graduate to `@devtheops/opencode-plugin-otel` with OTLP export to Honeycomb/Jaeger when the fleet exceeds 3+ concurrent Sentinels
- Use `ai.toolCall` spans to build automated cost-per-subagent dashboards

---

## 5. Additional Recommendations

### Credential Safety
- **Always** pipe trace output through `scrub_secrets()` before uploading artifacts or posting to issues
- Extend `_SECRET_PATTERNS` in `WorkItemModel.py` to cover any new provider API key formats as models are added
- Consider adding `OPENCODE_VERBOSE=true` only in targeted debug runs, not always-on — it dumps full HTTP bodies which may include prompt content with embedded secrets

### Trace Bloat Control
- Use `permission.task` in `opencode.json` to restrict which subagents each primary agent can see:

  ```json
  {
    "permission": {
      "task": { "*": "deny" }
    },
    "agent": {
      "orchestrator": {
        "permission": {
          "task": {
            "explore": "allow",
            "build": "allow"
          }
        }
      }
    }
  }
  ```

- This reduces token overhead in traces and prevents system prompt bloat from injecting all subagent schemas

### WorkItem Telemetry Linkage
- Include `childSessionId` in WorkItem metadata when updating issue labels (e.g., `agent:in-progress` → `agent:reconciling`)
- This creates a direct link from a GitHub Issue to the specific log file/trace span, enabling one-click debugging from the issue tracker

### Log Rotation Awareness
- OpenCode retains only **10 log files**. Long-running orchestrator sessions risk losing early subagent traces
- Mitigate by copying logs to a persistent location at defined checkpoints, or by increasing rotation limits if configurable in future OpenCode versions

---

## 6. Recommended Implementation Order

| Phase | Actions | Outcome |
|---|---|---|
| **Phase 1** (now) | Add env vars + `--format json` + GHA log groups + artifact upload | Full trace capture on every CI run; collapsible in GHA UI; downloadable on failure |
| **Phase 2** (next sprint) | Integrate `scrub_secrets()` into `trace-extract.py`; run as post-step | Safe, distilled subagent summaries as artifacts; no credential exposure |
| **Phase 3** (when needed) | Build plugin with `tool.execute.before`/`after` hooks | Surgical, per-tool audit trail with latency metrics |
| **Phase 4** (fleet scale) | Enable OTEL + JSONL export → graduate to OTLP backend | Distributed tracing with native parent→child span linking; cost dashboards |

---

## 7. Implementation Status

> Completed 2026-03-21. Options B-lite + C + D implemented with zero impact on main workflow output.

### What was implemented

| Change | File | Description |
|---|---|---|
| Server-side DEBUG logging | `scripts/start-opencode-server.sh` | `opencode serve` now starts with `--log-level DEBUG` (configurable via `OPENCODE_SERVER_LOG_LEVEL` env var). Writes to `/tmp/opencode-serve.log` only — client stdout stays at INFO. |
| Credential scrubbing in extractor | `scripts/trace-extract.py` | Imports `scrub_secrets()` from `WorkItemModel.py`. Scrubbing is on by default; disable with `--no-scrub`. |
| Artifact collection post-step | `.github/workflows/orchestrator-agent.yml` | New `if: always()` step collects OpenCode rotating logs + server log + runs `trace-extract.py --scrub` to produce `subagent-traces.txt`. |
| Artifact upload post-step | `.github/workflows/orchestrator-agent.yml` | Uploads the bundle as `opencode-traces` artifact with 14-day retention via `actions/upload-artifact@v4`. |

### What was NOT changed (by design)

- **Client log level**: `run_opencode_prompt.sh` still runs at `INFO` with `--print-logs`. No noise added to the main workflow output.
- **`--format json`**: Only activated when `DEBUG_ORCHESTRATOR=true` (existing behavior preserved).
- **Log grouping around execution**: Not added — the orchestrator step already has clean, readable output. Wrapping it in `::group::` would hide the useful real-time output by default.
- **Artifact upload condition**: Set to `always()` not just `failure()`, so traces are available even for successful runs (useful for cost analysis and subagent behavior auditing).

### Artifacts produced per workflow run

| Artifact | Contents | When |
|---|---|---|
| `opencode-traces/subagent-traces.txt` | Distilled per-subagent trace dump with credentials scrubbed | Every run |
| `opencode-traces/opencode-serve.log` | Full server-side log at DEBUG level | Every run |
| `opencode-traces/*.log` | OpenCode rotating session logs from `~/.local/share/opencode/log/` | Every run |

### Gaps closed

- ~~`trace-extract.py` had no credential scrubbing~~ → Now imports and applies `scrub_secrets()` by default
- ~~`WorkItemModel.py` scrubber was not integrated~~ → Now consumed by `trace-extract.py` via sibling import
- ~~Server-side logs at INFO missed subagent session details~~ → Server now runs at DEBUG, capturing Task tool dispatches, child session IDs, and full tool execution traces
- ~~No artifact collection~~ → Logs + distilled traces uploaded on every run with 14-day retention

---

## 8. Minimal Subagent Tracing in Main Workflow Output — Feasibility Analysis

> **Request**: Can a _small_ amount of subagent tracing be added to the main workflow output without disrupting the clean orchestrator log?
>
> **Status**: Research only — not implemented.

### What the main output already shows

The orchestrator's `--print-logs` output already includes lightweight subagent markers emitted by the OpenCode TUI renderer:

```
• Execute create-workflow-plan assignment Planner Agent        ← dispatch
[watchdog] client output idle 75s, server I/O active ...      ← heartbeat
✓ Execute create-workflow-plan assignment Planner Agent        ← completion
```

These `•` (started) and `✓` (completed) lines come from the parent agent's Task tool invocation lifecycle. They already provide:
- **Which** subagent was dispatched (agent name)
- **What** the task was (objective text)
- **When** it started and finished (by position in the log stream)
- **Whether** it succeeded (✓) or is in-progress (•)

The watchdog heartbeats fill the silent gaps with server I/O activity confirmation.

### Options for adding more without noise

| Approach | What it adds | Impact on output | Feasibility |
|---|---|---|---|
| **1. Subagent summary line** — parse `trace-extract.py` output and echo a 1-line summary per subagent after completion | Agent name, duration, tool count, token estimate | +1 line per delegation. Clean. | **Medium** — requires `trace-extract.py` to run mid-session (not just post-mortem). Would need the server log to be readable while the process is still running, and a hook after each `✓` line. Not straightforward with current architecture where the client blocks on `opencode run`. |
| **2. `::notice::` annotations** — emit GitHub Actions `::notice::` for each delegation start/end | Annotation badge in the GHA summary tab | Zero lines added to main log. Shows in sidebar. | **Low effort** — but requires a mechanism to detect Task dispatches in real-time. Currently the client blocks silently during subagent execution, so there's no hook point to emit annotations mid-run. Would require a sidecar process tailing the server log. |
| **3. Watchdog enhancement** — extend the existing watchdog loop to grep the server log for Task dispatches and print a one-liner | "Subagent: Planner started 45s ago (server write_bytes: 125MB)" | Replaces/augments existing `[watchdog]` lines | **Low effort, best fit**. The watchdog already runs every 30s and reads `/proc/<pid>/io`. It could additionally `grep` the server log for the most recent `tool=Task` entry and print the subagent name. This adds ~2 lines of bash to `run_opencode_prompt.sh` and produces output that blends naturally with the existing watchdog messages. |
| **4. Server `--print-logs` at INFO** — add `--print-logs` to `opencode serve` | Server INFO events appear in `/tmp/opencode-serve.log` (already captured) | No change to client output — server logs go to file | **Already done** by the server DEBUG change. But this doesn't route to client stdout. |

### Recommendation

**Option 3 (watchdog enhancement)** is the only approach that fits the constraints:
- Adds 0-1 lines per 30s watchdog cycle (same cadence as existing heartbeats)
- Requires ~5 lines of bash in the watchdog loop in `run_opencode_prompt.sh`
- Blends with existing `[watchdog]` output format
- Example output:
  ```
  [watchdog] client idle 82s, server active — subagent: Backend-Developer (started 52s ago, 117MB written)
  ```
- **Risk**: Depends on the server log containing parseable `tool=Task` entries at DEBUG level (which is now the case after the server log-level bump). If the log format changes in a future OpenCode version, the grep would silently produce nothing (safe degradation).

### Why other approaches don't fit

- **Options 1 & 2** require real-time detection of delegation events from the client side, but the `opencode run --attach` client blocks opaquely during subagent execution. There's no callback, hook, or streaming event that the CI script can intercept. The only signal available is the server's log file and `/proc/<pid>/io`.
- **Option 4** doesn't route to client stdout by design — the server and client are separate processes.

### If implementing Option 3

The change would go in the watchdog loop in `run_opencode_prompt.sh`, inside the `while kill -0 "$OPENCODE_PID"` block, adding a conditional grep for the most recent Task dispatch:

```bash
# Show active subagent name if server log contains a recent Task dispatch
if [[ -f "$SERVER_LOG" ]]; then
    _last_task=$(grep -o '"tool":"Task".*"agent":"[^"]*"' "$SERVER_LOG" 2>/dev/null | tail -1)
    if [[ -n "$_last_task" ]]; then
        _agent_name=$(echo "$_last_task" | grep -o '"agent":"[^"]*"' | cut -d'"' -f4)
        echo "[watchdog] subagent active: ${_agent_name} — server write_bytes=${_cur_server_write:-n/a}"
    fi
fi
```

This would only fire when the server log is at DEBUG level (now the default), and degrades to no output if the grep finds nothing.
