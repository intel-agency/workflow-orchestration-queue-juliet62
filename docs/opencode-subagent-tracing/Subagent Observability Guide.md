# **Subagent Observability Guide (Automated/Non-Interactive Mode)**

This document outlines the protocols for gaining full visibility into subagent delegations when running in headless environments, such as GitHub Actions, background "Sentinel" daemons, or automated workflow queues.

## **1\. Headless Execution Flags**

In automated modes, you cannot interact with the TUI. You must force the OpenCode engine to emit all sub-task reasoning and tool executions to the standard error/log streams.

### **Required Environment Variables**

Configure these in your GitHub Secrets or .env file:

* DEBUG\_ORCHESTRATOR=true — Enables verbose tracing in the Sentinel.  
* OPENCODE\_LOG\_LEVEL=DEBUG — Forces the daemon to log every JSON-RPC handshake.  
* OPENCODE\_PRINT\_LOGS=true — Forces subagent "thinking" blocks to be printed to stdout.

### **CLI invocation (run\_opencode\_prompt.sh)**

Ensure your runner uses these flags to capture the "Chain of Thought":

opencode run \--prompt "$PROMPT" \--thinking \--print-logs \--log-level DEBUG

## **2\. Automated Trace Extraction**

In non-interactive mode, subagent logs are stored in rotating files on the runner. To inspect a failure, you must extract the specific sub-session from the aggregate log.

### **The "Sentinel-to-Subagent" Correlation**

1. **Identify the Session:** The Orchestrator starts with a ParentSessionID.  
2. **Find the Handshake:** Search the logs for the Task tool call. This entry contains the childSessionId.  
3. **Isolate the Sub-Trace:** Filter the log file by that childSessionId.

**Automation Script snippet:**

\# Get the ID of the most recent subagent dispatched  
SUB\_ID=$(grep "tool=Task" \~/.local/share/opencode/log/\*.log | jq \-r '.childSessionId' | tail \-n 1\)

\# Dump the full reasoning of that specific subagent  
grep "$SUB\_ID" \~/.local/share/opencode/log/\*.log | jq \-r '.message' \> subagent\_trace.txt

## **3\. GitHub Actions Integration**

To make traces visible in the GitHub UI without manually digging through files:

### **Log Grouping**

Wrap the subagent execution in a GitHub Actions group to keep the main log clean while allowing "deep dives" on demand.

\- name: Execute Orchestrator  
  run: |  
    echo "::group::Subagent Traces"  
    ./run\_opencode\_prompt.sh  
    echo "::endgroup::"

### **Artifact Uploads (Diagnostic Bundle)**

Always upload the raw OpenCode logs as an artifact if the workflow fails. This is the only way to debug "silent" subagent crashes.

\- name: Upload Debug Logs  
  if: failure()  
  uses: actions/upload-artifact@v4  
  with:  
    name: opencode-debug-logs  
    path: \~/.local/share/opencode/log/\*.log

## **4\. Telemetry (OTEL) for Automated Monitoring**

If you are running a fleet of Sentinels, use the OpenTelemetry plugin to push traces to a central collector (e.g., Honeycomb, Jaeger, or Axiom).

### **Headless OTEL Config (opencode.json)**

{  
  "experimental": {  
    "openTelemetry": true,  
    "otelExporter": "otlp-http",  
    "otelEndpoint": "\[https://api.your-provider.com/v1/traces\](https://api.your-provider.com/v1/traces)"  
  }  
}

## **5\. Automated "Heartbeat" Monitoring**

The Sentinel should periodically report the status of its active subagents to the WorkItem store.

* **Status: agent:in-progress** — Subagent is currently thinking/executing.  
* **Status: agent:reconciling** — Subagent has returned data; Orchestrator is verifying.  
* **Telemetry Payload:** Include the childSessionId in the WorkItem metadata so developers can link a GitHub Issue directly to a specific log file.