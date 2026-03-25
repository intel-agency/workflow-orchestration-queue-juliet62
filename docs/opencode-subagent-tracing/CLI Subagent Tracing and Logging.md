# **Comprehensive Diagnostics and Traceability of Subagent Delegation in OpenCode CLI Environments**

The architectural paradigm of autonomous coding agents relies fundamentally on the concept of delegation, wherein a primary orchestrator model dispatches specific, bounded tasks to specialized subagents. Within the OpenCode environment, this delegation model utilizes subagents that operate as distinct artificial intelligence personalities, invoked for domain-specific execution such as codebase exploration, security auditing, or test generation.1 To prevent cross-task pollution, context window exhaustion, and hallucination drift, each subagent operates within a strictly isolated session state, utilizing independent memory structures and restricted toolsets configured via the opencode.json schema.1 While this strict isolation guarantees deterministic task execution, it introduces profound challenges for observability, debugging, and trace output extraction.1

When a primary agent leverages the internal Task tool to delegate work, the standard input and output streams of the parent session do not inherently capture the cognitive processing, prompt streaming, or intermediary tool executions of the child subagent.3 The parent session merely logs the dispatch of the task and subsequently awaits the finalized output result, treating the subagent as an opaque, asynchronous function call.5 For systems engineers, observability specialists, and developers operating exclusively within Command Line Interface (CLI) environments or utilizing remote headless server configurations (opencode serve coupled with opencode attach), capturing the granular trace outputs of these subagents requires deliberate telemetry instrumentation, advanced logging configurations, and an intimate understanding of the underlying Vercel AI SDK execution loop.6

This comprehensive report provides an exhaustive, deeply nuanced analysis of the methodologies required to expose, capture, and analyze subagent trace outputs, debugging logs, and OpenTelemetry (OTEL) spans specifically within the OpenCode CLI and server/CLI attach topologies, explicitly excluding desktop and web application environments.

## **The Architectural Paradigm of Subagent Delegation**

To effectively trace subagent execution, one must first deeply comprehend the mechanical pathway of delegation within the OpenCode runtime architecture. OpenCode utilizes a hierarchical agent topology comprising primary agents, such as build and plan, and subagents, such as explore and general.8 The primary agent maintains the user-facing interaction loop and orchestrates the overarching intent of the user prompt. When a user explicitly invokes a subagent via an @ mention (for example, @explore find authentication vulnerabilities) or when the primary agent autonomously determines a task requires specialized processing, a delegation event is triggered.8

This delegation is executed mechanically via the Task tool, which acts as the inter-agent communication bridge.4 Upon invocation of the Task tool, the internal SubAgentManager instantiates a new child session.2 This instantiation deliberately passes a message\_history=None parameter or equivalent blank-slate context to ensure the subagent begins with a pristine context window, isolated from the parent's conversational drift and previous tool outputs.2 If the primary agent dictates multiple parallel tasks within a single generation step, the system leverages concurrent execution models—conceptually mirroring asyncio.gather() in Python environments—to fan out the work to multiple isolated subagent threads.2

Because these subagents execute outside the primary standard output buffer managed by the Terminal User Interface (TUI), standard CLI visualization masks their internal chain-of-thought.9 Observers monitoring the terminal will typically note the parent agent entering a "busy" or "thinking" state while the subagent silently processes the request in the background.5 To penetrate this abstraction layer and view the hard details of the subagent's internal reasoning, exact tool calls, file reads, and LLM network requests, operators must configure the runtime to emit highly verbose diagnostic logs or structure external telemetry pipelines.2 The isolation that provides OpenCode its structural stability is precisely what necessitates advanced tracing techniques.

## **Foundation Level Tracing: Standard Logging and CLI Flags**

The most immediate, native, and accessible mechanism for surfacing subagent traces involves manipulating the native logging facilities provided by the OpenCode CLI executable. The application logs all internal state transitions, tool resolutions, context summarizations, and Large Language Model (LLM) network requests to local storage, provided the correct verbosity thresholds are breached by the operator.10

### **Invoking Verbose Output via CLI Flags**

When operating the CLI in standalone mode (for instance, executing opencode run), standard execution suppresses low-level diagnostic information to maintain a clean, readable Terminal User Interface.11 To expose the underlying LLM requests—which contain the critical prompts sent to and received from the subagent—the execution must be augmented with global debugging flags.12

The \--log-level DEBUG flag forces the application to record high-resolution trace data.9 This includes the precise models being utilized by the subagent, the payload sizes, the provider routing logic, and the raw prompts dispatched to the subagent's configured LLM endpoint.9 However, simply lowering the log level does not automatically present this data to the user's immediate terminal session, as the Bubble Tea-based TUI requires exclusive control over the standard output buffer to render the interactive interface.11 To bypass this presentation layer and force the daemon to emit traces directly to the terminal's standard error stream, operators must append the \--print-logs flag.12

The combination of opencode run \--print-logs \--log-level DEBUG creates a highly verbose, continuously scrolling trace stream.12 Interleaved with the TUI rendering characters, the stderr stream will surface the initialization of the Task tool, the creation of the child session identifier, and the subsequent HTTP POST requests made to the configured model provider on behalf of the subagent.9

For programmatic consumption, pipeline integrations, or when piping the CLI output to external log aggregators and parsers like jq, operators should additionally append the \--format json flag.12 This flag suppresses the human-readable string formatting and forces the CLI to emit a continuous stream of raw JSON events.12 By filtering these JSON payloads for specific session IDs or tool names (such as Task or spawn\_subagent), developers can programmatically isolate the exact trace logs of the delegated subagent from the noise of the primary agent's execution.4

### **Environment Variable Driven Traceability**

In deployment scenarios where passing CLI flags is ergonomically prohibitive or impossible—such as within continuous integration (CI) pipelines, background cron jobs, or containerized environments—tracing can be enforced via environment variables.12 This approach ensures that trace generation is intrinsically linked to the execution environment rather than the specific command invocation.

| Environment Variable | Data Type | Subagent Tracing Implication |
| :---- | :---- | :---- |
| OPENCODE\_LOG\_LEVEL | String | Setting this variable to DEBUG enforces maximum verbosity across all internal services and background daemon processes, ensuring that all subagent network calls and state changes are recorded persistently.15 |
| OPENCODE\_VERBOSE | Boolean | When evaluated as truthy, this deeply embedded constant forces the application to print granular details of all outgoing REST API requests. This includes complete HTTP header maps, routing configurations, and the raw payload bodies sent to the AI providers, which is essential for diagnosing subagent prompt formulation.17 |
| OPENCODE\_EXPERIMENTAL | Boolean | Setting this parameter to true globally unlocks experimental features across the OpenCode codebase. Historically, this includes advanced telemetry hooks, beta instrumentation pipelines, and specific tool tracing capabilities that generate deeper forensic traces of subagent tool executions.1 |

By combining these environment variables (e.g., OPENCODE\_LOG\_LEVEL=DEBUG OPENCODE\_VERBOSE=true opencode run), the system administrator ensures that no subagent activity can occur without generating a corresponding forensic artifact in the system's standard streams or log directories.

## **Persistent State Storage and Log File Diagnostics**

Regardless of whether the \--print-logs flag is utilized during execution, the OpenCode daemon persistently writes diagnostic traces to the local filesystem by default.10 These files represent the primary, immutable artifact for post-mortem debugging of subagent failures, particularly when an automated subagent loop terminates unexpectedly, encounters an API rate limit, or hallucinates a recursive tool execution path.1

### **The File System Pathway and Log Rotation**

Log files are automatically generated, timestamped utilizing a strict ISO 8601 derived format (for example, 2025-01-09T123456.log), and automatically rotated by the daemon.10 To prevent disk exhaustion and maintain system performance, the system preserves only the ten most recent log files.10 Operators must be aware of this rotation policy when debugging long-running autonomous sessions, as older subagent traces may be overwritten.

| Operating System Environment | Default Log Storage Pathway |
| :---- | :---- |
| macOS and Linux distributions | \~/.local/share/opencode/log/ 10 |
| Windows environments | %USERPROFILE%\\.local\\share\\opencode\\log 10 |

To analyze a subagent trace retroactively, the operator must navigate to this directory and inspect the most recently generated log file. Within this file, the execution trace will manifest as a sequence of structured entries. To isolate subagent activity, the operator must search for lines containing specific key-value pairs, primarily service=server coupled with tool=Task.4

The log entry corresponding to the Task tool execution will reveal the instantiation of a new sessionID. This identifier is the cryptographic key to the subagent's trace. By filtering the remainder of the log file exclusively for this newly minted sessionID, the operator isolates the complete operational trace of the subagent, entirely filtering out the noisy background operations of the primary agent.5 This isolated trace reveals precisely which files the subagent attempted to read, the exact bash commands it executed in its isolated sandbox, and the final synthesized text response it formulated to pass back to the primary agent's waiting context.1

### **Database Storage and Session Reconstruction**

Beyond the standard rotating text logs, OpenCode persists all interactions, tool usages, agent configurations, and session metadata within SQLite databases and JSON flat files.11 This storage layer is critical for deep forensic tracing after a session has fully concluded.

The application utilizes a dual-tiered storage architecture dependent on the execution context.10 If the OpenCode CLI is executed within a recognized Git repository, the persistent trace data is localized to a hidden directory structure at ./\<project-slug\>/storage/.10 For executions occurring outside of version-controlled boundaries, data is routed to the global store at \~/.local/share/opencode/global/storage/.10

Within these directories, the execution traces of all sessions—including the ephemeral, hidden child sessions created by subagents—are serialized and stored.1 By parsing the SQLite database or the raw JSON message files using standard command-line utilities (such as sqlite3 or jq), operators can perform advanced trace analytics.11

For example, each serialized message file contains highly specific metadata fields, including internal cost calculations represented as cost: 0 (or greater), which are populated via token counts utilizing standard pricing algorithms like LiteLLM.20 Extracting and aggregating these files allows an auditor to calculate the exact token expenditure of a specific subagent invocation.20 Furthermore, because the relational database stores the explicit structural relationship between the parent session ID and the child session ID, shell scripts can be authored to recursively reconstruct the entire tree of delegation. This enables the generation of a complete, chronological trace of the primary agent's overarching requests perfectly interspersed with the subagents' granular tool executions.8

## **Introspective Auditing via the Terminal User Interface**

While external logging to files and database querying provide robust programmatic observability and post-mortem auditing, developers actively interacting with the CLI require immediate, introspective mechanisms to verify a subagent's execution path without breaking their flow state to context-switch to a separate log viewer.9 OpenCode solves this by providing built-in mechanisms for navigating the hierarchical session tree directly within the terminal, allowing operators to visually "step into" the subagent's execution loop.8

### **Navigating the Child Session Hierarchy**

As previously established, subagent encapsulation relies on the creation of isolated child sessions.1 When a primary agent delegates a task via the Task tool, the Terminal User Interface typically remains focused on the parent session.4 The user sees the parent agent's summary of what the subagent achieved, but not the raw trace of *how* it achieved it.9 This abstraction is by design, preventing the user from being overwhelmed by the subagent's rapid iteration through files and search results.

To directly observe the trace output, command history, file diffs, and reasoning blocks of the subagent in real-time, the user must command the TUI to pivot its viewport into the child session.8 OpenCode implements specific, Vim-inspired keybindings for traversing this complex session graph 8:

| TUI Action | Configured Keybinding | Observability Purpose and Trace Function |
| :---- | :---- | :---- |
| session\_child\_first | \<Leader\>+Down | Forces the CLI viewport to transition from the primary conversational thread directly into the isolated trace context of the most recently executed subagent.8 |
| session\_child\_cycle | Right Arrow | In advanced scenarios where multiple subagents were spawned concurrently (parallel fanning), this command cycles the viewport forward through the parallel execution traces.8 |
| session\_child\_cycle\_reverse | Left Arrow | Cycles the viewport backward through the sibling subagent traces, allowing comparison of parallel work streams.8 |
| session\_parent | Up Arrow | Ascends the session tree, terminating the subagent inspection and returning the viewport to the primary agent's context.8 |

By pressing the session\_child\_first combination while a primary agent is awaiting a subagent's return, the operator transitions directly into the subagent's live trace feed.8 Within this view, the raw, unfiltered output is entirely visible. The developer can verify if the subagent is hallucinating file paths, trapped in a recursive error loop, or failing to utilize its restricted toolset correctly.2

If the trace indicates that the subagent is drifting down a hazardous execution path or wasting context window tokens on irrelevant files, the operator can manually halt the generation process. Furthermore, because the TUI is active, the operator can inject corrective prompts directly into the child session, effectively steering the subagent's trajectory before returning to the parent session to resume the overarching workflow.9 This interactive trace auditing represents a crucial operational advantage of the OpenCode architecture over fully opaque, "fire-and-forget" agentic black boxes.9

## **The Server and Attach Topology: Decoupling and Trace Routing**

A highly scalable and increasingly common deployment topology for OpenCode involves running a persistent, headless backend server (via opencode serve or opencode web) and subsequently attaching ephemeral CLI instances (opencode attach) to execute specific tasks.7 This client-server architecture mitigates the severe cold-start latency associated with initializing Model Context Protocol (MCP) servers, establishing database connections, and loading the codebase context into memory for every discrete CLI invocation.12 However, this architectural bifurcation significantly complicates the capture and routing of subagent traces.

### **The Decoupling of the Standard Output Stream**

When an operator invokes opencode serve \--port 4096 \--hostname 0.0.0.0, the primary OpenCode process daemonizes. It binds to the specified network port and becomes the sole custodian of all LLM execution states, filesystem access controls, and the SubAgentManager.3 When a developer connects via an alternate terminal window using opencode attach http://localhost:4096, the attached TUI acts merely as a thin RPC (Remote Procedure Call) presentation layer.12

Crucially, the standard output (stdout) and standard error (stderr) streams of the *attached client* do not receive the deep diagnostic traces of the server's background operations.19 The daemon maintains ownership of the file descriptors utilized by the subagent threads. Consequently, if a primary agent delegates a task to a subagent, the attached CLI will simply display a generic loading indicator, while the actual, highly verbose trace of the subagent's execution occurs entirely on the host machine running the opencode serve process.5

### **Forcing Trace Emission on the Headless Server**

To successfully monitor subagent behavior in this distributed topology, tracing parameters must be strictly enforced at the server daemon level, not the client level. Applying \--log-level DEBUG to the opencode attach command will yield no subagent data, as the client is unaware of the subagent's internal mechanics. The server must be initiated with maximum logging verbosity:

opencode serve \--port 4096 \--print-logs \--log-level DEBUG 14

In this configuration, the terminal hosting the serve process becomes the master trace console for the entire system.12 As remote clients attach and submit prompts, the server terminal will continuously stream the resulting internal state machine transitions. If a user prompt triggers the Task tool, the server's stdout will immediately populate with the subagent initialization parameters, the prompt template applied, and the resulting tool execution loop.5

Operators utilizing this pattern for automated workflows, swarm orchestration, or continuous integration pipelines routinely redirect the server's trace output to a persistent stream for ingestion by external log aggregation platforms:

OPENCODE\_VERBOSE=true opencode serve \--port 4096 \--print-logs \--log-level DEBUG 2\>&1 | tee /var/log/opencode-daemon.log 16

This approach guarantees that even if the attached client disconnects, crashes, or times out, the subagent's execution trace is permanently captured on the server.

### **Diagnosing Subagent Deadlocks over REST APIs**

A critical, documented edge case in the headless topology occurs when interacting with the server via pure REST API calls (utilizing the @opencode-ai/sdk in a Node.js script or external application) rather than the official attach CLI command.5 Analysis of extensive issue reports indicates a specific failure mode: when an API-driven session triggers a subagent via the Task tool, the subagent may successfully begin processing. This processing is visible in the server logs as an incrementing sequence of steps (step=0, step=1, step=2).5

However, under certain conditions, multiple asynchronous NotFoundError rejections occur within the internal acp-command service.5 This internal exception causes both the parent session and the child subagent session to enter an infinite "busy" loop, commonly referred to as a deadlock.5 Because the system is deadlocked, no final response is ever formulated or returned via the SDK client's polling mechanism.5

To debug this precise failure mode, the operator *must* have direct access to the opencode serve host machine's log file or stderr stream.5 The remote client will reveal nothing but a timeout. The server-side trace, however, will reveal the exact tool call or filesystem access attempt that triggered the NotFoundError within the subagent's execution loop. Armed with this trace data, the developer can adjust the subagent's configuration, restrict its toolset via the permission schema, or refine its system prompt to prevent the recursive error path.8

## **Advanced Telemetry: OpenTelemetry (OTEL) Instrumentation**

For enterprise environments requiring rigorous observability, SLA monitoring, and complex swarm debugging, unstructured text logs and tailing terminal streams are highly insufficient. System architectures orchestrating dozens of primary agents and subagents require distributed tracing to map the complex, multi-layered causal relationships between a user prompt, the primary agent's task delegation, the subagent's internal loop, and the ultimate synthesized response.2

To fulfill this enterprise requirement, OpenCode provides support for OpenTelemetry (OTEL). This system generates highly structured, standardized spans that can be exported via OTLP/gRPC to backend observability platforms like Datadog, Honeycomb, Grafana Cloud, or Jaeger.21

### **Activating the Native OTEL Engine and Injecting Dependencies**

The OTEL instrumentation within OpenCode is explicitly marked as experimental. It is deactivated by default to minimize performance overhead and reduce the size of the distributed binaries.6 The telemetry engine hooks deeply into the Vercel AI SDK, the foundational library which powers OpenCode's underlying generative text streaming logic.6

To expose subagent traces via OTEL, operators must satisfy two distinct prerequisites. First, the configuration schema must explicitly enable the experimental telemetry feature. This requires modifying the global or project-specific configuration file (for example, \~/.config/opencode/opencode.json or \<project-root\>/opencode.json).15

JSON

{  
  "$schema": "https://opencode.ai/config.json",  
  "experimental": {  
    "openTelemetry": true  
  }  
}

6

Second, because OpenCode executes within a highly optimized JavaScript runtime (typically Bun or Node.js depending on the specific deployment methodology), the standard @opentelemetry libraries are not bundled in the default distribution.6 The operator must manually inject the requisite OpenTelemetry SDK into the OpenCode execution environment to prevent the daemon from crashing when it attempts to initialize the span processors.6

The most reliable methodology for this injection involves appending the required package to the OpenCode dependency manifest located at \~/.config/opencode/packages.json, and subsequently executing the bun install command within that directory.6 Specifically, the @opentelemetry/sdk-node package (version 0.200 or higher) is strictly required to enable the foundational tracing APIs.6

### **Span Architecture and Subagent Trace Mapping**

Once the NodeSDK is successfully initialized and the application restarts, the execution of any agent—whether a primary agent or a delegated subagent—generates highly structured trace spans.6 Unlike standard flat logs, which require manual string matching and time-correlation, OTEL spans utilize native parent-child relationships. This architecture natively maps the subagent's isolated work back to the primary agent's initial prompt, creating a perfectly structured tree of execution.6

The Vercel AI SDK implementation utilized by OpenCode emits three primary span categories that are critical to analyzing subagent behavior:

| OpenTelemetry Span Name | Trace Description and Debugging Value |
| :---- | :---- |
| ai.streamText | Captures the overarching lifecycle of an LLM generation cycle. For a subagent, this span records the total wall-clock duration of the isolated child session's execution, the specific model routed to, and the total token consumption (vital for subagent cost tracking).6 |
| ai.toolCall | The most critical span for subagent debugging and behavioral analysis. This span contains the exact, unredacted JSON schema of the tool execution. If the primary agent delegates work, the ai.toolCall span will detail the invocation of the Task tool.6 If the subagent subsequently executes a bash command or reads a file, another nested ai.toolCall span is generated containing the exact command string or file path.4 |
| ai.streamText.doStream | Contains highly granular tracing of the chunk-by-chunk stream processing. This is particularly useful for debugging network latency, TLS handshake issues, or provider-side rate limiting during subagent response generation.6 |

The contents of these spans, particularly ai.toolCall and ai.streamText, encapsulate the full text of the system prompts transmitted to the LLM and the raw JSON strings returned by the model.6 This capability allows an operator or security auditor to mathematically prove exactly what context the subagent received, devoid of any UI abstractions, formatting filters, or truncation.

### **Implementing Span Processors and Exporters**

Enabling experimental.openTelemetry instructs the AI SDK to generate the spans in memory, but it does not inherently configure an export pipeline. Without an exporter, the traces are generated and immediately discarded by the garbage collector.6 The runtime requires an initialized SpanProcessor to capture, batch, and route these telemetry objects to a destination.6

Operators have two distinct pathways to capture these traces. The first and most scalable involves utilizing dedicated third-party plugins designed explicitly to bridge OpenCode's internal events with standard OTLP/gRPC endpoints.21 The opencode-plugin-otel (@devtheops/opencode-plugin-otel) acts as a drop-in exporter for this exact purpose.21 By registering this plugin within the opencode.json configuration array, the CLI automatically begins flushing session lifecycle metrics, tool durations, and subagent delegation traces to the configured OpenTelemetry Collector.21 This mirrors the enterprise-grade monitoring capabilities seen in proprietary tools, providing dashboards that visualize the exact time spent by a subagent executing bash commands versus awaiting LLM inference.21

The second pathway involves custom plugin development to instantiate a localized, file-based trace logger.6 For deep, offline forensic analysis of subagent behavior in air-gapped environments, writing the OTEL spans directly to a local JSONL (JSON Lines) file provides an immutable ledger of the AI's internal state machine without requiring external network access.6

To achieve this offline tracing, developers can author a local plugin file (for example, \~/.config/opencode/plugins/otel-dumper/index.ts).30 Within the plugin's main execution function, the TypeScript code must dynamically import the OpenTelemetry SDK. This dynamic import is critical; if standard static imports are used at the top of the file, OpenCode will freeze on startup if the @opentelemetry module is missing or corrupt, leading to a state that is exceptionally hard to debug.6

The logic entails instantiating a custom JsonlSpanProcessor attached to a standard Node.js file stream, and passing this processor to a newly constructed NodeSDK instance.6 Once sdk.start() is invoked within the plugin, all subsequent subagent delegations, file modifications, and API network requests are serialized as deeply nested JSON objects and appended to the target trace file.6 This methodology completely demystifies the subagent; the resulting JSON lines reveal the precise instructions passed to the subagent, bypassing the obfuscation of the primary agent's summarization.

## **Plugin-Driven Trace Interception**

When native logging is too unstructured and full OpenTelemetry instrumentation is deemed overly complex or resource-intensive, developers can leverage OpenCode's robust plugin architecture to intercept, modify, or record subagent traces dynamically.14 Plugins act as asynchronous middleware functions that execute directly within the OpenCode runtime, granting them highly privileged access to internal lifecycle hooks, context windows, and runtime data.30

### **Hooking into the Tool Execution Lifecycle**

Because subagents operate primarily by executing defined tools (such as bash, edit, read, or webfetch), tracing tool execution is functionally synonymous with tracing the subagent's logical progression.4 The @opencode-ai/plugin SDK exposes specific lifecycle hooks designed precisely for this level of granular interception.30

By creating a TypeScript file at .opencode/plugins/tracer/index.ts (for project-scoped tracing) or \~/.config/opencode/plugins/tracer/index.ts (for global tracing), developers can define an async factory function that returns these operational hooks.30

The tool.execute.before hook is triggered immediately before an agent (or subagent) executes an action.30 This hook receives the complete context of the intended action, including the name of the tool and the parsed JSON arguments generated by the LLM.6 A custom plugin can extract this data and write it to a dedicated trace file, providing a highly legible audit trail of exactly what the subagent is attempting to do before it actually modifies the filesystem or executes a shell command.30

Conversely, the tool.execute.after hook fires upon the successful or failed completion of the tool's execution.30 This hook receives the output generated by the tool—such as the standard output of a bash command, the contents of a read file, or the success boolean of an edit operation.30 By correlating the timestamps of the before and after hooks, the plugin can calculate precise execution latencies for subagent tasks, mirroring the functionality of complex Application Performance Monitoring (APM) solutions using only native SDK primitives.21

### **Leveraging the Native Logging API**

While custom plugins can write traces directly to the filesystem using standard Node.js libraries (such as node:fs/promises), the optimal methodology utilizes OpenCode's internal, structured logging API.14 The SDK exposes the client.app.log() function, which constructs a highly structured JSON payload and transmits it to the main OpenCode server via an internal POST /log HTTP request.14

The schema for client.app.log() accepts several strongly-typed parameters designed to structure the trace output:

* service: A string identifying the source of the log, useful for filtering (e.g., "subagent-tracer-plugin").14  
* level: A severity indicator constrained to debug, info, warn, or error.14  
* message: The primary string payload containing the human-readable trace data.14  
* extra: An arbitrary JSON object allowing for the attachment of deep contextual metadata, such as the sessionId, agentId, or specific tool arguments intercepted during the hook execution.14

When a plugin invokes this function, the trace data is ingested seamlessly into the central daemon's logging stream.19 This implies that the traces captured by the plugin will be written to the standard \~/.local/share/opencode/log/ rotated files, directly alongside the native system traces.10

It is vital to acknowledge historical bugs and nuances within the application's logging pipeline when building these tools. Diagnostics and community issue reports indicate that in certain architectural versions (notably around version 1.0.220), logs generated via client.app.log() occasionally failed to propagate to the standard output terminal, even when the \--print-logs \--log-level DEBUG flags were explicitly provided during the invocation of opencode serve.19 In such edge cases, while the terminal output may remain inexplicably silent, the POST /log requests are successfully received by the daemon and successfully persisted to the underlying log files.19 Therefore, operators utilizing plugin-based trace interception must always prioritize inspecting the physical log files on the host machine when terminal streams appear incomplete or missing.10

## **Trace Bloat Mitigation via Task Permissions**

A secondary but critical aspect of tracing subagents is managing the sheer volume of trace data generated. In environments with dozens of configured subagents, the primary agent's system prompt can become heavily bloated because the Task tool automatically injects the schemas and descriptions of every available subagent into the context window.32 This bloat not only increases token costs but also makes debugging the primary agent's trace exceedingly difficult, as the logs become saturated with irrelevant subagent definitions.32

To mitigate this trace bloat, operators must actively manage subagent visibility utilizing the permission.task schema within opencode.json.8 By applying glob patterns, administrators can explicitly allow or deny specific subagents from appearing in the Task tool's execution context.

JSON

{  
  "$schema": "https://opencode.ai/config.json",  
  "permission": {  
    "task": {  
      "\*": "deny"  
    }  
  },  
  "agent": {  
    "builder": {  
      "permission": {  
        "task": {  
          "build-specialist": "allow"  
        }  
      }  
    }  
  }  
}

32

In this configuration, all subagents are globally denied from the Task tool, drastically reducing the size of the system prompt payload visible in the trace logs.32 The builder primary agent is then explicitly granted permission to invoke only the build-specialist subagent. This precision engineering ensures that the generated trace logs remain focused, concise, and highly relevant to the specific delegation pathway being audited, removing thousands of tokens of unnecessary schema definitions from the ai.streamText spans.32

## **Methodological Synthesis and Best Practices**

The extraction of high-fidelity trace output from subagents within the OpenCode CLI ecosystem requires a layered, defense-in-depth approach to observability. Because the architecture mandates strict contextual isolation to prevent cognitive drift and token exhaustion, subagents are inherently designed as opaque, asynchronous workers executing within detached child sessions.1

For rapid, interactive debugging during the development of custom subagent prompts or toolset configurations, operators should rely primarily on TUI session navigation. The mastery of the session\_child\_first (\<Leader\>+Down) keybinding is critical; it is the only native mechanism that allows a developer to directly observe a subagent's stream-of-consciousness logic, bash command outputs, and file modifications in real-time, preventing the need to decipher post-execution logs.8

When transitioning from interactive development to automated scripting, headless environments, or continuous integration execution via the opencode serve daemon, reliance on TUI keybindings becomes physically impossible.12 In these remote or automated topologies, the foundation of traceability relies on the strict enforcement of the \--print-logs and \--log-level DEBUG arguments at the server level, coupled with the strategic redirection of the daemon's standard error stream to persistent file storage or log aggregators.10 Operators must fundamentally understand that attaching a client (opencode attach) does not grant visibility into the server's background tracing; the server itself remains the sole source of truth for all subagent execution logs.5

Finally, for enterprise-scale deployments, continuous security monitoring, or rigorous forensic analysis of LLM behavior, the standard text logs must be superseded by structured telemetry.21 While currently marked as an experimental feature requiring manual dependency injection of @opentelemetry/sdk-node, the activation of experimental.openTelemetry in the JSON configuration schema represents the absolute pinnacle of subagent tracing.6 The resulting ai.toolCall and ai.streamText spans provide an immutable, mathematically rigorous ledger of the exact prompts dispatched to the AI provider and the precise JSON schema utilized for delegation via the Task tool.6 Whether dumped to a local JSON Lines file via a custom SpanProcessor plugin or exported to a sophisticated observability backend via the @devtheops/opencode-plugin-otel plugin, these telemetry spans transform the inherently opaque nature of autonomous subagents into a fully transparent, heavily instrumented state machine.6

#### **Works cited**

1. \[feat\] Add "subagent" AI task delegation · Issue \#1293 · anomalyco/opencode \- GitHub, accessed March 20, 2026, [https://github.com/anomalyco/opencode/issues/1293](https://github.com/anomalyco/opencode/issues/1293)  
2. Building AI Coding Agents for the Terminal: Scaffolding, Harness, Context Engineering, and Lessons Learned \- arXiv, accessed March 20, 2026, [https://arxiv.org/html/2603.05344v1](https://arxiv.org/html/2603.05344v1)  
3. Building Effective AI Coding Agents for the Terminal: Scaffolding, Harness, Context Engineering, and Lessons Learned \- arXiv, accessed March 20, 2026, [https://arxiv.org/html/2603.05344v3](https://arxiv.org/html/2603.05344v3)  
4. How Coding Agents Actually Work: Inside OpenCode | Moncef Abboud, accessed March 20, 2026, [https://cefboud.com/posts/coding-agents-internals-opencode-deepdive/](https://cefboud.com/posts/coding-agents-internals-opencode-deepdive/)  
5. Sessions hang indefinitely when Task tool spawns subagents via REST API (opencode serve) · Issue \#6573 \- GitHub, accessed March 20, 2026, [https://github.com/anomalyco/opencode/issues/6573](https://github.com/anomalyco/opencode/issues/6573)  
6. feat: integrate OpenTelemetry by tianhuil · Pull Request \#5245 · anomalyco/opencode, accessed March 20, 2026, [https://github.com/anomalyco/opencode/pull/5245](https://github.com/anomalyco/opencode/pull/5245)  
7. Web | OpenCode, accessed March 20, 2026, [https://opencode.ai/docs/web/](https://opencode.ai/docs/web/)  
8. Agents \- OpenCode, accessed March 20, 2026, [https://opencode.ai/docs/agents/](https://opencode.ai/docs/agents/)  
9. My brief (and bad) experience with Claude Code after OpenCode block \- Reddit, accessed March 20, 2026, [https://www.reddit.com/r/opencodeCLI/comments/1ryl1l6/my\_brief\_and\_bad\_experience\_with\_claude\_code/](https://www.reddit.com/r/opencodeCLI/comments/1ryl1l6/my_brief_and_bad_experience_with_claude_code/)  
10. Troubleshooting | OpenCode, accessed March 20, 2026, [https://opencode.ai/docs/troubleshooting/](https://opencode.ai/docs/troubleshooting/)  
11. opencode/README.md at main \- GitHub, accessed March 20, 2026, [https://github.com/opencode-ai/opencode/blob/main/README.md](https://github.com/opencode-ai/opencode/blob/main/README.md)  
12. CLI | OpenCode, accessed March 20, 2026, [https://opencode.ai/docs/cli/](https://opencode.ai/docs/cli/)  
13. Large Language Models (LLMs), accessed March 20, 2026, [https://renenyffenegger.ch/notes/development/Artificial-intelligence/language-model/LLM/index](https://renenyffenegger.ch/notes/development/Artificial-intelligence/language-model/LLM/index)  
14. OpenCode config \- shamelessly lifted from the Discord server \- GitHub Gist, accessed March 20, 2026, [https://gist.github.com/thoroc/1dafddebede4a2577876c844923862aa](https://gist.github.com/thoroc/1dafddebede4a2577876c844923862aa)  
15. opencode-configuration | Skills Mark... \- LobeHub, accessed March 20, 2026, [https://lobehub.com/zh/skills/fkxxyz-cclover-skills-opencode-configuration](https://lobehub.com/zh/skills/fkxxyz-cclover-skills-opencode-configuration)  
16. opencode-server-launcher | Skills Ma... \- LobeHub, accessed March 20, 2026, [https://lobehub.com/ar/skills/igorwarzocha-opencode-agent-swarm-demo-opencode-server-launcher](https://lobehub.com/ar/skills/igorwarzocha-opencode-agent-swarm-demo-opencode-server-launcher)  
17. Solution draft log for https://github.com/link-assistant/agent/pull/202 · GitHub, accessed March 20, 2026, [https://gist.github.com/konard/c9aa8a74ad6b263750d31f46352c2e90](https://gist.github.com/konard/c9aa8a74ad6b263750d31f46352c2e90)  
18. Tools | OpenCode, accessed March 20, 2026, [https://opencode.ai/docs/tools/](https://opencode.ai/docs/tools/)  
19. Logs sent via client.app.log() are not visible with \--print-logs · Issue \#7301 · anomalyco/opencode \- GitHub, accessed March 20, 2026, [https://github.com/anomalyco/opencode/issues/7301](https://github.com/anomalyco/opencode/issues/7301)  
20. OpenCode CLI Overview (Beta) \- ccusage, accessed March 20, 2026, [https://ccusage.com/guide/opencode/](https://ccusage.com/guide/opencode/)  
21. A curated list of awesome plugins, themes, agents, projects, and resources for https://opencode.ai \- GitHub, accessed March 20, 2026, [https://github.com/awesome-opencode/awesome-opencode](https://github.com/awesome-opencode/awesome-opencode)  
22. Releases · anomalyco/opencode \- GitHub, accessed March 20, 2026, [https://github.com/anomalyco/opencode/releases](https://github.com/anomalyco/opencode/releases)  
23. marcusquinn/aidevops: Vibe-Coding is easy. DevOps is hard. AI DevOps automates your software, business, and personal development with managed infrastructure through AI chat in OpenCode. Opinionated tools, services, CLI & API tech-stack — for speed, security, and 24/7 results. Open-source-preferred, and SOTA everything. · GitHub, accessed March 20, 2026, [https://github.com/marcusquinn/aidevops](https://github.com/marcusquinn/aidevops)  
24. Windows: opencode prints help and exits for \*any\* command. Desktop GUI fails to spawn server (1.1.12–1.1.15) \#8233 \- GitHub, accessed March 20, 2026, [https://github.com/anomalyco/opencode/issues/8233](https://github.com/anomalyco/opencode/issues/8233)  
25. OpenCode 서버 실행기 | Skills Marketplace \- LobeHub, accessed March 20, 2026, [https://lobehub.com/ko/skills/igorwarzocha-opencode-agent-swarm-demo-opencode-server-launcher](https://lobehub.com/ko/skills/igorwarzocha-opencode-agent-swarm-demo-opencode-server-launcher)  
26. accessed March 20, 2026, [https://www.daytona.io/docs/llms-full.txt](https://www.daytona.io/docs/llms-full.txt)  
27. opencode/packages/sdk/js/src/gen/types.gen.ts at dev \- GitHub, accessed March 20, 2026, [https://github.com/anomalyco/opencode/blob/dev/packages/sdk/js/src/gen/types.gen.ts](https://github.com/anomalyco/opencode/blob/dev/packages/sdk/js/src/gen/types.gen.ts)  
28. Config | OpenCode, accessed March 20, 2026, [https://opencode.ai/docs/config/](https://opencode.ai/docs/config/)  
29. DEVtheOPS/opencode-plugin-otel: An opencode plugin ... \- GitHub, accessed March 20, 2026, [https://github.com/DEVtheOPS/opencode-plugin-otel](https://github.com/DEVtheOPS/opencode-plugin-otel)  
30. opencode-build-plugins | Skills Mark... \- LobeHub, accessed March 20, 2026, [https://lobehub.com/en/skills/pantheon-org-tekhne-build-plugins](https://lobehub.com/en/skills/pantheon-org-tekhne-build-plugins)  
31. \[FEATURE\]: On-idle background processing · Issue \#5895 · anomalyco/opencode \- GitHub, accessed March 20, 2026, [https://github.com/anomalyco/opencode/issues/5895](https://github.com/anomalyco/opencode/issues/5895)  
32. Reduce token overhead: Task tool injects all subagent descriptions into system prompt · Issue \#7269 · anomalyco/opencode \- GitHub, accessed March 20, 2026, [https://github.com/anomalyco/opencode/issues/7269](https://github.com/anomalyco/opencode/issues/7269)