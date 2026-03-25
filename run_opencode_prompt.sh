#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 -f <file> | -p <prompt> [-a <url>] [-u <user>] [-P <pass>] [-d <dir>] [-l <log-level>] [-L]" >&2
    echo "  -f <file>       Read prompt from file" >&2
    echo "  -p <prompt>     Use prompt string directly" >&2
    echo "  -a <url>        Attach to a running opencode server (e.g. https://host:4096)" >&2
    echo "  -u <user>       Basic auth username (prefer env var OPENCODE_AUTH_USER)" >&2
    echo "  -P <pass>       Basic auth password (prefer env var OPENCODE_AUTH_PASS)" >&2
    echo "  -d <dir>        Working directory on the server (used with -a)" >&2
    echo "  -l <log-level>  opencode log level (DEBUG|INFO|WARN|ERROR), default: INFO" >&2
    echo "  -L              Enable --print-logs (disabled by default)" >&2
    echo "" >&2
    echo "  Credentials are resolved in order: flags > env vars OPENCODE_AUTH_USER / OPENCODE_AUTH_PASS" >&2
    exit 1
}

prompt=""
attach_url=""
auth_user="${OPENCODE_AUTH_USER:-}"   # prefer env vars — flags override if provided
auth_pass="${OPENCODE_AUTH_PASS:-}"
work_dir=""
log_level="INFO"
print_logs="--print-logs"
format_flag=()

while getopts ":f:p:a:u:P:d:l:L" opt; do
    case $opt in
        f) prompt=$(cat "$OPTARG") ;;
        p) prompt="$OPTARG" ;;
        a) attach_url="$OPTARG" ;;
        u) auth_user="$OPTARG" ;;
        P) auth_pass="$OPTARG" ;;
        d) work_dir="$OPTARG" ;;
        l) log_level="$OPTARG" ;;
        L) print_logs="--print-logs" ;;
        *) usage ;;
    esac
done

if [ -z "$prompt" ]; then
    usage
fi

if [[ -z "${ZHIPU_API_KEY:-}" ]]; then
    echo "::error::ZHIPU_API_KEY is not set" >&2
    exit 1
fi

if [[ -z "${KIMI_CODE_ORCHESTRATOR_AGENT_API_KEY:-}" ]]; then
    echo "::error::KIMI_CODE_ORCHESTRATOR_AGENT_API_KEY is not set" >&2
    exit 1
fi

# Authenticate GitHub CLI and set MCP-compatible token.
#
# Token priority:
#   1. GH_ORCHESTRATION_AGENT_TOKEN — org secret PAT with scopes: repo, workflow,
#                                      project, read:org. Required for cross-repo access.
#   2. GITHUB_TOKEN — the built-in Actions token. Scoped to this repo only; use as
#                    a fallback when no cross-repo access is needed.
if [[ -n "${GH_ORCHESTRATION_AGENT_TOKEN:-}" ]]; then
    _active_token="${GH_ORCHESTRATION_AGENT_TOKEN}"
    echo "Using GH_ORCHESTRATION_AGENT_TOKEN for authentication (cross-repo access enabled)"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    _active_token="${GITHUB_TOKEN}"
    echo "::warning::GH_ORCHESTRATION_AGENT_TOKEN is not set — falling back to GITHUB_TOKEN (this repo only)"
else
    echo "::error::Neither GH_ORCHESTRATION_AGENT_TOKEN nor GITHUB_TOKEN is set — gh CLI will not be authenticated" >&2
    exit 1
fi

# Export under all names that tools (gh CLI, MCP servers, opencode) may read.
export GH_TOKEN="${_active_token}"
export GITHUB_TOKEN="${_active_token}"
export GITHUB_PERSONAL_ACCESS_TOKEN="${_active_token}"
export OPENCODE_EXPERIMENTAL=1

# Validate the token is accepted by the API and check required scopes.
# --include surfaces response headers; X-OAuth-Scopes lists granted scopes.
# Use ||true to prevent set -e from exiting before we can capture/report the error.
_api_response=$(gh api rate_limit --include 2>&1) || true
if ! echo "${_api_response}" | grep -q '^HTTP'; then
    echo "::error::gh CLI token validation failed — unexpected response:" >&2
    echo "${_api_response}" >&2
    exit 1
fi
echo "gh CLI token validation succeeded"

if [[ -n "${GH_ORCHESTRATION_AGENT_TOKEN:-}" ]]; then
    _granted_scopes=$(echo "${_api_response}" | grep -i '^X-OAuth-Scopes:' | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
    echo "Granted OAuth scopes: ${_granted_scopes:-<none>}"

    # Tokenize the comma-space delimited scope string into an array.
    IFS=', ' read -ra _scope_tokens <<< "${_granted_scopes}"

    _required_scopes=("repo" "workflow" "project" "read:org")
    _missing=()
    for _scope in "${_required_scopes[@]}"; do
        _found=false
        for _token in "${_scope_tokens[@]}"; do
            [[ "${_token}" == "${_scope}" ]] && { _found=true; break; }
        done
        [[ "${_found}" == false ]] && _missing+=("${_scope}")
    done

    if [[ ${#_missing[@]} -gt 0 ]]; then
        echo "::error::GH_ORCHESTRATION_AGENT_TOKEN is missing required scopes: ${_missing[*]}" >&2
        echo "::error::Required: ${_required_scopes[*]}  |  Granted: ${_granted_scopes}" >&2
        exit 1
    fi
    echo "All required scopes verified: ${_required_scopes[*]}"
fi

# Embed basic auth credentials into the attach URL if provided
if [[ -n "$attach_url" && -n "$auth_user" && -n "$auth_pass" ]]; then
    # Warn if credentials are being sent over plain HTTP
    if [[ "$attach_url" == http://* ]]; then
        echo "::warning::Basic auth credentials over http:// are sent in plaintext — use https://" >&2
    fi
    scheme="${attach_url%%://*}"
    rest="${attach_url#*://}"
    attach_url="${scheme}://${auth_user}:${auth_pass}@${rest}"
elif [[ ( -n "$auth_user" || -n "$auth_pass" ) && -z "$attach_url" ]]; then
    echo "::error::OPENCODE_AUTH_USER/PASS (or -u/-P) require -a <url>" >&2
    exit 1
fi

# When DEBUG_ORCHESTRATOR is set, crank up diagnostics
if [[ "${DEBUG_ORCHESTRATOR:-}" == "true" ]]; then
    log_level="DEBUG"
    format_flag=(--format json)
    echo "[debug] DEBUG_ORCHESTRATOR=true — enabling verbose output"
fi

# Build opencode args — optional flags only included when set
opencode_args=(
    run
    --model zai-coding-plan/glm-5
    --agent orchestrator
    --log-level "$log_level"
    --thinking
)
[[ -n "$print_logs"  ]] && opencode_args+=(--print-logs)
[[ ${#format_flag[@]} -gt 0 ]] && opencode_args+=("${format_flag[@]}")
[[ -n "$attach_url" ]] && opencode_args+=(--attach "$attach_url")
[[ -n "$work_dir"   ]] && opencode_args+=(--dir    "$work_dir")
opencode_args+=("$prompt")

# Always show concise info; verbose diagnostics only with DEBUG_ORCHESTRATOR
echo "Prompt: ${#prompt} chars | attach: ${attach_url:-local} | log-level: ${log_level}"
if [[ "${DEBUG_ORCHESTRATOR:-}" == "true" ]]; then
    echo "=== run_opencode_prompt.sh diagnostics ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "PWD: $(pwd)"
    echo "opencode binary: $(which opencode 2>&1 || echo 'NOT FOUND')"
    echo "opencode version: $(opencode --version 2>&1 || echo 'UNKNOWN')"
    echo "Prompt first 200 chars: ${prompt:0:200}"
    echo "Prompt last 200 chars: ${prompt: -200}"
    echo "opencode args (excluding prompt):"
    for i in "${!opencode_args[@]}"; do
      if [[ $i -lt $(( ${#opencode_args[@]} - 1 )) ]]; then
        echo "  [$i] ${opencode_args[$i]}"
      else
        echo "  [$i] <prompt content, ${#prompt} chars>"
      fi
    done
    echo "=== end diagnostics ==="
fi

echo "Starting opencode at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Idle watchdog: kill opencode if it produces no output for IDLE_TIMEOUT_SECS.
# An active agent continuously emits tool calls, reasoning, etc. Sustained silence
# means it's stuck. This replaces a hard wall-clock timeout so long-running but
# actively-working agents aren't killed prematurely.
#
# IMPORTANT: When the orchestrator delegates to a subagent via the Task tool,
# the `opencode run` client blocks silently waiting for the server-side subagent
# to finish. During this time the client produces NO stdout, and the server log
# file (stdout/stderr of `opencode serve`) is NOT actively written either — it
# only contains startup messages. However the server PROCESS is busy (database
# writes, LLM API calls, tool execution). We detect this by reading the server
# process's cumulative I/O counters from /proc/<pid>/io. If write_bytes
# increases between checks the server is actively working, even if no log files
# are changing. We only consider the process idle when the client output is
# stale AND the server process shows no new I/O within the timeout window.
IDLE_TIMEOUT_SECS=900   # 15 minutes of no output
HARD_CEILING_SECS=5400  # 90-minute absolute safety net
OUTPUT_LOG=$(mktemp /tmp/opencode-output.XXXXXX)
SERVER_LOG="${OPENCODE_SERVER_LOG:-/tmp/opencode-serve.log}"
SERVER_PIDFILE="${OPENCODE_SERVER_PIDFILE:-/tmp/opencode-serve.pid}"
echo "Output log: $OUTPUT_LOG"
echo "Server log: $SERVER_LOG"
echo "Server PID file: $SERVER_PIDFILE (monitored for process I/O activity)"

set +e

# Start opencode with output redirected to a log file
echo "Launching: opencode ${opencode_args[*]:0:$(( ${#opencode_args[@]} - 1 ))} <prompt>"
stdbuf -oL -eL opencode "${opencode_args[@]}" > "$OUTPUT_LOG" 2>&1 &
OPENCODE_PID=$!
echo "opencode PID: $OPENCODE_PID"

# Verify the process actually started
sleep 1
if ! kill -0 "$OPENCODE_PID" 2>/dev/null; then
    echo "::error::opencode process $OPENCODE_PID died immediately after launch"
    echo "=== Output log contents ==="
    cat "$OUTPUT_LOG"
    echo "=== end output log ==="
    rm -f "$OUTPUT_LOG"
    exit 1
fi
echo "opencode process $OPENCODE_PID confirmed running after 1s"

# Stream the log to stdout in real-time so CI can see it
tail -f "$OUTPUT_LOG" &
TAIL_PID=$!

START_TIME=$(date +%s)
IDLE_KILLED=0
_prev_server_write=""           # tracks server process write_bytes between iterations
_last_server_io_time=$START_TIME  # last time server I/O was observed active

# _read_server_write_bytes: read cumulative write_bytes from the server process.
# Returns the value via stdout; empty string if unavailable.
_read_server_write_bytes() {
    local pidfile="$SERVER_PIDFILE"
    if [[ -f "$pidfile" ]]; then
        local spid
        spid=$(cat "$pidfile" 2>/dev/null)
        if [[ -n "$spid" && -f "/proc/$spid/io" ]]; then
            awk '/^write_bytes:/{print $2}' "/proc/$spid/io" 2>/dev/null
            return
        fi
    fi
    echo ""
}

# Watchdog loop: check output freshness every 30 seconds
while kill -0 "$OPENCODE_PID" 2>/dev/null; do
    sleep 30

    # Hard ceiling safety net
    now=$(date +%s)
    elapsed=$(( now - START_TIME ))

    # Watchdog status — concise by default, verbose when debugging.
    log_size=$(wc -c < "$OUTPUT_LOG" 2>/dev/null || echo 0)
    log_lines=$(wc -l < "$OUTPUT_LOG" 2>/dev/null || echo 0)
    output_last_mod=$(stat -c %Y "$OUTPUT_LOG" 2>/dev/null || echo "$now")
    output_idle=$(( now - output_last_mod ))

    # --- Server activity detection ---
    # Primary: check if the server process is performing I/O (database writes,
    # LLM API calls, tool execution) by reading /proc/<pid>/io write_bytes.
    # This works even when the server log file is not being updated.
    # Fallback: server log file mtime (in case /proc/io is unavailable).
    server_io_active=false
    _cur_server_write=$(_read_server_write_bytes)
    if [[ -n "$_cur_server_write" ]]; then
        if [[ -n "$_prev_server_write" && "$_cur_server_write" != "$_prev_server_write" ]]; then
            server_io_active=true
            _last_server_io_time=$now
        fi
        _prev_server_write="$_cur_server_write"
    fi

    # Server log mtime as a secondary signal (only relevant when /proc/io unavailable)
    if [[ -f "$SERVER_LOG" ]]; then
        server_last_mod=$(stat -c %Y "$SERVER_LOG" 2>/dev/null || echo "$now")
        server_log_idle=$(( now - server_last_mod ))
    else
        server_log_idle=$output_idle
    fi

    # Determine effective server idle time.
    # Use time-since-last-I/O-activity as the primary measure. This avoids
    # the race condition where a single 30s I/O pause causes server_idle to
    # jump from 0 to the full runtime (because server_log_idle reflects
    # server startup, not last activity). Only fall back to server_log_idle
    # when /proc/io was never available (e.g. non-Linux or PID file missing).
    if [[ "$server_io_active" == true ]]; then
        server_idle=0
    elif [[ -n "$_cur_server_write" ]]; then
        # /proc/io is available but write_bytes didn't change this interval.
        # Compute idle from when I/O was LAST seen active — not from startup.
        server_idle=$(( now - _last_server_io_time ))
    else
        # /proc/io not available at all — fall back to log mtime
        server_idle=$server_log_idle
    fi

    # The process is only truly idle when BOTH client output is stale
    # AND the server shows no activity.
    if [[ $output_idle -le $server_idle ]]; then
        idle=$output_idle
    else
        idle=$server_idle
    fi

    if [[ "${DEBUG_ORCHESTRATOR:-}" == "true" ]]; then
        echo "[watchdog] elapsed=${elapsed}s output_idle=${output_idle}s server_idle=${server_idle}s server_io_active=${server_io_active} effective_idle=${idle}s log_size=${log_size}b log_lines=${log_lines} pid=$OPENCODE_PID server_write_bytes=${_cur_server_write:-n/a} last_io=$(( now - _last_server_io_time ))s_ago"
    elif [[ $output_idle -ge 60 && "$server_io_active" == true ]]; then
        # Emit a brief note when client output is stale but server is active
        # (i.e. subagent delegation in progress) so CI isn't silent for minutes
        echo "[watchdog] client output idle ${output_idle}s, server I/O active (write_bytes=${_cur_server_write}) — subagent likely running"
    fi

    if [[ $elapsed -ge $HARD_CEILING_SECS ]]; then
        echo ""
        echo "::error::opencode hit ${HARD_CEILING_SECS}s hard ceiling; terminating"
        kill "$OPENCODE_PID" 2>/dev/null
        # Escalate to SIGKILL if SIGTERM doesn't work within 10s
        sleep 10
        if kill -0 "$OPENCODE_PID" 2>/dev/null; then
            echo "::warning::opencode did not exit after SIGTERM; sending SIGKILL"
            kill -9 "$OPENCODE_PID" 2>/dev/null
        fi
        IDLE_KILLED=1
        break
    fi

    # Idle detection: only trigger when BOTH client output and server are stale
    if [[ $idle -ge $IDLE_TIMEOUT_SECS ]]; then
        echo ""
        echo "::error::opencode idle for $(( idle / 60 ))m (no output from client or server); terminating"
        kill "$OPENCODE_PID" 2>/dev/null
        # Escalate to SIGKILL if SIGTERM doesn't work within 10s
        sleep 10
        if kill -0 "$OPENCODE_PID" 2>/dev/null; then
            echo "::warning::opencode did not exit after SIGTERM; sending SIGKILL"
            kill -9 "$OPENCODE_PID" 2>/dev/null
        fi
        IDLE_KILLED=1
        break
    fi
done

wait "$OPENCODE_PID" 2>/dev/null
OPENCODE_EXIT=$?
kill "$TAIL_PID" 2>/dev/null
wait "$TAIL_PID" 2>/dev/null

echo ""
echo "opencode exit code: $OPENCODE_EXIT"

# When idle-killed, always dump server log tail (even without DEBUG_ORCHESTRATOR)
# so the CI log shows what the server was doing when the watchdog fired.
if [[ $IDLE_KILLED -eq 1 && -f "$SERVER_LOG" ]]; then
    echo "=== server log tail (last 80 lines before idle kill) ==="
    tail -n 80 "$SERVER_LOG" 2>/dev/null || true
    echo "=== end server log tail ==="
fi

if [[ "${DEBUG_ORCHESTRATOR:-}" == "true" ]]; then
    echo "=== opencode post-execution diagnostics ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Idle killed: $IDLE_KILLED"
    echo "Output log file: $OUTPUT_LOG"
    if [[ -f "$OUTPUT_LOG" ]]; then
        echo "Output log size: $(wc -c < "$OUTPUT_LOG") bytes, $(wc -l < "$OUTPUT_LOG") lines"
        echo "=== Full output log contents ==="
        cat "$OUTPUT_LOG"
        echo ""
        echo "=== end output log ==="
    else
        echo "WARNING: Output log file $OUTPUT_LOG does not exist!"
    fi
    echo "Server log file: $SERVER_LOG"
    if [[ -f "$SERVER_LOG" ]]; then
        echo "Server log size: $(wc -c < "$SERVER_LOG") bytes, $(wc -l < "$SERVER_LOG") lines"
        echo "=== Full server log contents ==="
        cat "$SERVER_LOG"
        echo ""
        echo "=== end server log ==="
    else
        echo "Server log not found (opencode may be running in local mode)"
    fi
fi

rm -f "$OUTPUT_LOG"

set -e

# Exit non-zero on idle kill so the workflow properly reports failure.
# Previously this was `exit 0` which masked SIGTERM (143) as success,
# causing incomplete runs to appear as "succeeded" in GitHub Actions.
if [[ $IDLE_KILLED -eq 1 ]]; then
    exit 1
fi

exit ${OPENCODE_EXIT}
