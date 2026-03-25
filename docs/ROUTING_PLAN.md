# Dynamic Runner Routing Plan

## Objective

The `orchestrator-agent` workflow defaults to running entirely on GitHub's cloud runners — exactly as it does today. No local connection is made unless explicitly requested.

Users can opt-in to attaching the workflow to a local `opencode` CLI server via two explicit routes:

- **`self-hosted`**: Run the workflow job on a local self-hosted GitHub Actions runner (direct LAN access, no VPN needed).
- **`cloud`**: Run on GitHub's cloud runners, but tunnel into the local `opencode` server over Tailscale.

## Routing Logic

A lightweight preliminary job (`analyze-trigger`) is added to the workflow. It inspects the event payload and determines the route before the main orchestrator job starts.

### Decision Criteria

Routes are selected **only** when explicitly requested. Precedence order:

1. **Comment command** (`issue_comment`, `pull_request_review_comment`):
   - `/orchestrator route self-hosted` → use the local self-hosted runner (direct attach).
   - `/orchestrator route cloud` → use GitHub cloud runner + Tailscale (VPN attach).

2. **Issue/PR label** (`issues`, `pull_request`):
   - Label `route:self-hosted` → same as the self-hosted comment command.
   - Label `route:cloud` → same as the cloud comment command.

3. **Default (no explicit request)**:
   - Run on `ubuntu-latest` as today, with no local attach (no `-a` flag passed to `run_opencode_prompt.sh`).

### Analyzed Output Values

The `analyze-trigger` job emits two outputs consumed by `run-orchestrator`. Credentials are never composed into a single string — they flow as separate `--remote-env` injections into `devcontainer exec`, matching how `run_opencode_prompt.sh` already resolves `OPENCODE_AUTH_USER` / `OPENCODE_AUTH_PASS` from the environment.

Note: the port is embedded directly in the URL secret value (e.g. `http://192.168.1.x:4096`). There is no separate port flag.

| Route | `runner_group` | `connection_method` |
| --- | --- | --- |
| default | `ubuntu-latest` | `none` |
| self-hosted | `${{ vars.SELF_HOSTED_RUNNER_LABEL }}` | `direct` |
| cloud | `ubuntu-latest` | `tailscale` |

## Workflow Architecture (`orchestrator-agent.yml`)

### Job 1: `analyze-trigger`

- **Runs on**: `ubuntu-latest`
- **Role**: Parses `github.event` JSON to detect route commands or labels.
- **Outputs**:
  - `runner_group` — value for `runs-on` in the next job.
  - `connection_method` — `none`, `direct`, or `tailscale`.

### Job 2: `run-orchestrator`

- **Runs on**: `${{ needs.analyze-trigger.outputs.runner_group }}`
- **Needs**: `analyze-trigger`
- **Steps**:
  1. **Checkout** — standard `actions/checkout`.
  2. **Tailscale Setup** — runs _only if_ `connection_method == 'tailscale'`, using `tailscale/github-action@v2` with OAuth secrets.
  3. **Devcontainer run** — same as today (no change to the devcontainer setup logic).
  4. **Run opencode** — calls `devcontainer exec` exactly as today, but conditionally injects three extra `--remote-env` values when `connection_method != 'none'`:
     - `OPENCODE_ATTACH_URL` — set from `OPENCODE_INTERNAL_URL` (direct) or `OPENCODE_TAILSCALE_URL` (tailscale) secret.
     - `OPENCODE_AUTH_USER` — from the `OPENCODE_AUTH_USER` secret.
     - `OPENCODE_AUTH_PASS` — from the `OPENCODE_AUTH_PASS` secret.

     Inside the devcontainer, `run_opencode_prompt.sh` is called with `-a "$OPENCODE_ATTACH_URL"` appended. `run_opencode_prompt.sh` already reads `OPENCODE_AUTH_USER` / `OPENCODE_AUTH_PASS` from the environment, so no additional flag-passing is needed for credentials. When `connection_method == 'none'` (default), the invocation is byte-for-byte identical to today.

## Required Secrets and Variables (workflow usage)

These are referenced by the workflow YAML. They must be populated via the one-time setup above before the routing logic will function.

| Secret | Purpose |
| --- | --- |
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID for ephemeral runner auth |
| `TS_OAUTH_SECRET` | Tailscale OAuth secret |
| `OPENCODE_INTERNAL_URL` | Full URL + port for the self-hosted route (e.g. `http://192.168.1.x:4096`) |
| `OPENCODE_TAILSCALE_URL` | Full URL + port for the cloud/Tailscale route (e.g. `http://mymachine.tailnet.ts.net:4096`) |
| `OPENCODE_AUTH_USER` | Basic auth username for the opencode server |
| `OPENCODE_AUTH_PASS` | Basic auth password for the opencode server |

## Required Variables (workflow usage)

| Variable | Purpose |
| --- | --- |
| `SELF_HOSTED_RUNNER_LABEL` | Runner label(s) for the local self-hosted runner — must match `--labels` used during runner registration |

## In-Container Server (default path)

When neither `self-hosted` nor `cloud` routing is requested, the workflow now starts an `opencode serve` backend **inside the devcontainer** and attaches to it locally. This is also the default behavior when the consumer devcontainer is opened in VS Code.

**How it works:**

1. `scripts/start-opencode-server.sh` is a guarded bootstrapper that starts `opencode serve` on `0.0.0.0:4096` and waits for readiness.
2. The consumer devcontainer calls it via `postStartCommand`, so the server is up as soon as the container finishes starting.
3. The workflow calls it explicitly after `devcontainer up`, then passes `-a "http://127.0.0.1:4096"` to `run_opencode_prompt.sh`.
4. The script is idempotent — repeated calls are no-ops if the server is already healthy.

This means the default `connection_method == 'none'` path **still does not connect to an external machine**, but it does benefit from a warm `opencode serve` process (no MCP cold boot on every `opencode run`).

Optional env vars for tuning the in-container server:

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENCODE_SERVER_HOSTNAME` | `0.0.0.0` | Bind address for `opencode serve` |
| `OPENCODE_SERVER_PORT` | `4096` | Listen port |
| `OPENCODE_SERVER_PASSWORD` | _(unset)_ | Enables HTTP basic auth (username defaults to `opencode`) |
| `OPENCODE_SERVER_USERNAME` | _(unset)_ | Overrides basic auth username |

## Network Topology

### Current (interim)

- **LAN server** — runs the self-hosted GitHub Actions runner.
- **Laptop** — runs the `opencode` CLI server.

`OPENCODE_INTERNAL_URL` must point to the laptop's LAN IP (e.g. `http://192.168.1.x:4096`). The runner reaches opencode across the LAN.

### Target (future)

Both the self-hosted runner and the `opencode` server will run on the **LAN server**. At that point `OPENCODE_INTERNAL_URL` becomes `http://localhost:4096` — the only change required is updating that one secret. Everything else in the workflow and routing logic stays identical.

---

## One-Time Setup

These steps are performed once by the repo operator before any routing can work. They are prerequisites for implementation.

### Self-Hosted Runner Setup

Run these commands on your local server machine:

```bash
mkdir actions-runner && cd actions-runner

# Download the runner (check https://github.com/actions/runner/releases for latest version)
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-2.323.0.tar.gz
tar xzf ./actions-runner-linux-x64.tar.gz

# Configure — token is generated at:
# Repo → Settings → Actions → Runners → New self-hosted runner
./config.sh --url https://github.com/intel-agency/workflow-orchestration \
            --token <YOUR_TOKEN> \
            --labels self-hosted,local
```

Then install it as a persistent systemd service so it survives reboots:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status   # verify it's running
```

Set the repo variable `SELF_HOSTED_RUNNER_LABEL` to match the `--labels` value you chose (e.g. `self-hosted,local`).

### Tailscale Setup

**On your local machine (the opencode server):**

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Get your MagicDNS name — use this in OPENCODE_TAILSCALE_URL
tailscale status
```

**In the Tailscale admin console** ([tailscale.com/admin](https://tailscale.com/admin)):

1. Go to **Settings** → **OAuth clients** → **Generate OAuth client**.
2. Scope: **Devices → Write**, tag: `tag:ci`.
3. Copy **Client ID** → GitHub secret `TS_OAUTH_CLIENT_ID`.
4. Copy **Secret** → GitHub secret `TS_OAUTH_SECRET`.

### GitHub Secrets and Variables to Configure

| Type | Name | Value |
| --- | --- | --- |
| Variable | `SELF_HOSTED_RUNNER_LABEL` | Labels given to the runner (e.g. `self-hosted,local`) |
| Secret | `OPENCODE_INTERNAL_URL` | Full LAN URL + port (e.g. `http://192.168.1.x:4096`) |
| Secret | `OPENCODE_TAILSCALE_URL` | Full Tailscale MagicDNS URL + port (e.g. `http://mymachine.tailnet.ts.net:4096`) |
| Secret | `OPENCODE_AUTH_USER` | opencode server basic auth username |
| Secret | `OPENCODE_AUTH_PASS` | opencode server basic auth password |
| Secret | `TS_OAUTH_CLIENT_ID` | From Tailscale admin OAuth client |
| Secret | `TS_OAUTH_SECRET` | From Tailscale admin OAuth client |

## Implementation Steps

Once this plan is approved:

1. Refactor `.github/workflows/orchestrator-agent.yml` to split into `analyze-trigger` + `run-orchestrator` jobs.
2. Add conditional Tailscale step in `run-orchestrator`.
3. Update the `devcontainer exec` call to conditionally inject `OPENCODE_ATTACH_URL`, `OPENCODE_AUTH_USER`, `OPENCODE_AUTH_PASS` as `--remote-env` values and pass `-a "$OPENCODE_ATTACH_URL"` to `run_opencode_prompt.sh` when `connection_method != 'none'`.
4. Add new fixtures to `test/fixtures/` for comment and label routing scenarios.
5. Update `AGENTS.md` to document the routing pattern so future agents understand the expected behavior.

---

_Please review this plan. Adjust routing keywords, label names, or default behavior as needed before implementation begins._
