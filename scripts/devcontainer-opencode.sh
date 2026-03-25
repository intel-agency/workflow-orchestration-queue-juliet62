#!/usr/bin/env bash
set -euo pipefail

# devcontainer-opencode.sh
#
# Thin CLI wrapper around devcontainer for the opencode server workflow.
# Shared defaults mean callers only specify what differs.
#
# Commands:
#   up      Start (or reconnect to) the devcontainer
#   start   Ensure opencode serve is running inside the container
#   prompt  Dispatch a prompt to the agent via opencode run --attach
#   stop    Gracefully stop the container (keeps it for fast restart)
#   down    Stop and remove the container (full teardown)
#
# Shared options (env or flag, all commands):
#   -c <config>   devcontainer.json path  (env: DEVCONTAINER_CONFIG,  default: .devcontainer/devcontainer.json)
#   -w <dir>      workspace folder        (env: WORKSPACE_FOLDER,     default: .)
#
# prompt-only options:
#   -f <file>     assembled prompt file path (required, or use -p)
#   -p <prompt>   inline prompt string       (required, or use -f)
#   -u <url>      opencode server URL        (env: OPENCODE_SERVER_URL, default: http://127.0.0.1:4096)

DEVCONTAINER_CONFIG="${DEVCONTAINER_CONFIG:-.devcontainer/devcontainer.json}"
WORKSPACE_FOLDER="${WORKSPACE_FOLDER:-.}"
OPENCODE_SERVER_URL="${OPENCODE_SERVER_URL:-http://127.0.0.1:4096}"
PROMPT_FILE=""
PROMPT_STRING=""

usage() {
    cat >&2 <<'EOF'
Usage: devcontainer-opencode.sh <command> [options]

Commands:
  up      Start (or reconnect to) the devcontainer
  start   Ensure opencode serve is running inside the container
  prompt  Dispatch a prompt file to the agent via opencode run --attach
  stop    Gracefully stop the container (keeps it; fast restart via 'up')
  down    Stop and remove the container (full teardown)

Shared options:
  -c <config>   Path to devcontainer.json (default: .devcontainer/devcontainer.json)
  -w <dir>      Workspace folder          (default: .)

'prompt' options:
  -f <file>     Assembled prompt file path (required, or use -p)
  -p <prompt>   Inline prompt string       (required, or use -f)
  -u <url>      opencode server URL        (default: http://127.0.0.1:4096)

Environment variables:
  DEVCONTAINER_CONFIG, WORKSPACE_FOLDER, OPENCODE_SERVER_URL
  ZHIPU_API_KEY, KIMI_CODE_ORCHESTRATOR_AGENT_API_KEY, GITHUB_TOKEN  (required for 'prompt')
EOF
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

COMMAND="$1"
shift

while getopts ":c:w:f:p:u:" opt; do
    case $opt in
        c) DEVCONTAINER_CONFIG="$OPTARG" ;;
        w) WORKSPACE_FOLDER="$OPTARG" ;;
        f) PROMPT_FILE="$OPTARG" ;;
        p) PROMPT_STRING="$OPTARG" ;;
        u) OPENCODE_SERVER_URL="$OPTARG" ;;
        *) usage ;;
    esac
done

shared_args=(
    --workspace-folder "$WORKSPACE_FOLDER"
    --config "$DEVCONTAINER_CONFIG"
)

case "$COMMAND" in
    up)
        devcontainer up "${shared_args[@]}"
        ;;

    start)
        abs_workspace="$(cd "$WORKSPACE_FOLDER" && pwd)"
        container_id="$(docker ps -aq --filter "label=devcontainer.local_folder=${abs_workspace}")"
        if [[ -z "$container_id" ]]; then
            echo "[devcontainer-opencode] no container found; creating via 'up'"
            devcontainer up "${shared_args[@]}"
        else
            container_state="$(docker inspect --format '{{.State.Status}}' "$container_id")"
            if [[ "$container_state" != "running" ]]; then
                echo "[devcontainer-opencode] restarting stopped container ${container_id}"
                docker start "$container_id"
            fi
        fi
        devcontainer exec "${shared_args[@]}" \
            -- bash ./scripts/start-opencode-server.sh
        ;;

    prompt)
        if [[ -z "$PROMPT_FILE" && -z "$PROMPT_STRING" ]]; then
            echo "error: -f <prompt-file> or -p <prompt> is required for the 'prompt' command" >&2
            usage
        fi
        for var in ZHIPU_API_KEY KIMI_CODE_ORCHESTRATOR_AGENT_API_KEY GITHUB_TOKEN; do
            if [[ -z "${!var:-}" ]]; then
                echo "::error::${var} is not set" >&2
                exit 1
            fi
        done
        # Build the prompt source arg: -p takes precedence over -f when both are given
        if [[ -n "$PROMPT_STRING" ]]; then
            prompt_arg=(-p "$PROMPT_STRING")
        else
            prompt_arg=(-f "$PROMPT_FILE")
        fi
        devcontainer exec "${shared_args[@]}" \
            --remote-env ZHIPU_API_KEY="$ZHIPU_API_KEY" \
            --remote-env KIMI_CODE_ORCHESTRATOR_AGENT_API_KEY="$KIMI_CODE_ORCHESTRATOR_AGENT_API_KEY" \
            --remote-env GITHUB_TOKEN="$GITHUB_TOKEN" \
            --remote-env GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_TOKEN" \
            --remote-env GH_ORCHESTRATION_AGENT_TOKEN="${GH_ORCHESTRATION_AGENT_TOKEN:-}" \
            -- bash ./run_opencode_prompt.sh -a "$OPENCODE_SERVER_URL" "${prompt_arg[@]}"
        ;;

    stop|down)
        # Locate the container via the label devcontainer stamps with the workspace path.
        abs_workspace="$(cd "$WORKSPACE_FOLDER" && pwd)"
        container_id="$(docker ps -aq --filter "label=devcontainer.local_folder=${abs_workspace}")"
        if [[ -z "$container_id" ]]; then
            echo "[devcontainer-opencode] no running container found for workspace ${abs_workspace}" >&2
            exit 1
        fi
        echo "[devcontainer-opencode] stopping container ${container_id}"
        docker stop "$container_id"
        if [[ "$COMMAND" == "down" ]]; then
            echo "[devcontainer-opencode] removing container ${container_id}"
            docker rm "$container_id"
        fi
        ;;

    *)
        echo "error: unknown command '${COMMAND}'" >&2
        usage
        ;;
esac
