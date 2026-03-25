# Tech Stack

**Project:** workflow-orchestration-queue  
**Last Updated:** 2026-03-25

---

## Core Language & Runtime

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Python** | CPython | 3.12+ | Primary language for Orchestrator, Webhook receiver, and all system logic |

---

## Web Framework & Server

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **FastAPI** | FastAPI | Latest | High-performance async web framework for Webhook Notifier ("The Ear") |
| **Uvicorn** | Uvicorn | Latest | ASGI web server implementation for serving FastAPI in production |

---

## Data Validation & Settings

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Pydantic** | Pydantic | v2 | Strict data validation, settings management, and schema definitions for `WorkItem`, `TaskType`, `WorkItemStatus` |

---

## HTTP Client

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **httpx** | httpx | Latest | Fully async HTTP client for GitHub REST API calls without blocking the event loop |

---

## Package Management

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **uv** | uv | 0.10+ | Rust-based Python package installer and dependency resolver (orders of magnitude faster than pip/poetry) |
| **pyproject.toml** | - | - | Core definition file for dependencies and project metadata |
| **uv.lock** | - | - | Deterministic lockfile for exact package versions |

---

## Containerization

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Docker** | Docker Engine | Latest | Core worker execution engine providing sandboxing, environment consistency, and lifecycle hooks |
| **Docker Compose** | Docker Compose | Latest | Multi-container orchestration for complex workflows (e.g., web app + database) |
| **DevContainers** | VS Code DevContainer | Latest | Reproducible development environment identical to human developers |

---

## Testing

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **pytest** | pytest | Latest | Primary testing framework for unit and integration tests |
| **pytest-asyncio** | pytest-asyncio | Latest | Async test support for testing async sentinel and notifier code |

---

## Shell Scripts (Bridge Layer)

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Bash** | GNU Bash | 5.x | Shell bridge scripts for container lifecycle management |
| **PowerShell Core** | pwsh | 7.x | Cross-platform auth synchronization and CLI utilities |

---

## LLM Agent Runtime

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **opencode CLI** | opencode | 1.2.24 | AI agent runtime executing markdown-based instruction modules |
| **ZhipuAI GLM** | GLM-5 | Latest | Primary LLM model for agent reasoning |

---

## Key Dependencies

```toml
[project]
dependencies = [
    "fastapi>=0.110.0",
    "uvicorn[standard]>=0.27.0",
    "pydantic>=2.5.0",
    "pydantic-settings>=2.1.0",
    "httpx>=0.27.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0.0",
    "pytest-asyncio>=0.23.0",
    "pytest-cov>=4.1.0",
]
```

---

## Security Dependencies

| Pattern | Purpose |
|---------|---------|
| HMAC SHA256 | Webhook signature verification via `X-Hub-Signature-256` header |
| Credential Scrubbing | Regex-based sanitization of logs before posting to GitHub |

---

## Infrastructure

| Component | Technology | Purpose |
|-----------|------------|---------|
| **GitHub Issues** | - | Distributed state management ("Markdown as a Database") |
| **GitHub Labels** | - | Task status tracking (`agent:queued`, `agent:in-progress`, `agent:success`, `agent:error`) |
| **GitHub Assignees** | - | Distributed locking mechanism for concurrency control |
| **GitHub App** | - | Webhook delivery and API authentication |

---

## Resource Constraints

| Resource | Limit | Purpose |
|----------|-------|---------|
| **CPU** | 2 cores | Worker container limit to prevent DoS on host |
| **RAM** | 4 GB | Worker container memory limit |
| **Network** | Isolated bridge | Prevents worker from accessing host network/subnet |

---

## Configuration

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `GITHUB_TOKEN` | Yes | - | GitHub API authentication |
| `GITHUB_REPO` | Yes | - | Target repository (format: `owner/repo`) |
| `SENTINEL_BOT_LOGIN` | Yes | - | Bot account login for task claiming/locking |

---

## References

- Architecture Guide v3.2: System-level diagrams and security boundaries
- Development Plan v4.2: Phased rollout and risk mitigations
- Implementation Specification v1.2: Detailed requirements and acceptance criteria
