# LLM Client Subagents

This project uses a shared set of 25 specialist subagents for targeted delegation and automation-first workflows. The same agent names and roles are deployed across all compatible LLM coding clients.

## Source and Deployment

The canonical agent definitions originate from Claude Code format in `nam20485/accp-generator/.source/agents/`. They are converted to each client's native format and deployed user-wide. Conversion reports live in `accp-generator/.source/reports/`.

### Client Deployment Locations

| Client                 | Format                                           | Location                                   |
| ---------------------- | ------------------------------------------------ | ------------------------------------------ |
| VS Code GitHub Copilot | `.agent.md`                                      | `%APPDATA%/Code - Insiders/User/agents/`   |
| Kilo Code              | `custom_modes.yaml` + per-mode `instructions.md` | `~/.kilo/`                                 |
| Codex CLI              | `.prompt.md` + `SKILL.md`                        | `~/.codex/prompts/` and `~/.codex/skills/` |
| OpenCode               | References `AGENTS.md`                           | `opencode.json` in project root            |

Agent names and roles are consistent across all clients. Each client resolves agents from its own location, but the canonical role definitions are listed below.

## Usage

1. Open your LLM client's agent panel (e.g., `@agent-name` in Copilot, `/agents` in others).
2. Select the appropriate specialist agent for the task.
3. Use the **orchestrator** to plan, delegate to specialists, and approve work.
4. Delegate research tasks to the **researcher** agent.

## Agent Index

### Core

- orchestrator — Plans, delegates, approves; avoids direct implementation.
- researcher — Uses configured research tooling to produce citation-rich briefs.
- code-reviewer — Reviews diffs for correctness, security, performance, and style.
- dev-team-lead — Coordinates development across multiple agents and tracks progress.

### Build & Quality

- qa-test-engineer — Designs and runs tests; validates green builds.
- devops-engineer — CI/CD, reproducible builds, observability basics.
- frontend-developer — UI components/pages with component tests.
- backend-developer — Endpoints/modules with unit/integration tests.

### Planning

- planner — Breaks work into tasks with acceptance criteria.
- product-manager — Defines goals, constraints, acceptance criteria.
- scrum-master — Facilitates cadence; removes blockers; enforces DoD.

### Specialized

- cloud-infra-expert — Cloud architecture, IaC patterns, security baselines.
- github-expert — GitHub platform features, APIs, and integrations.
- github-ops-agent — Manages GitHub configuration, automation, and policy enforcement.
- performance-optimizer — Profiles and enforces performance budgets.
- security-expert — Threat modeling, secrets hygiene, dependency risk.
- database-admin — Schema/migrations, performance, backup/restore.
- data-scientist — Data pipelines, metrics, experiments, reproducibility.
- ml-engineer — Model training/inference, evaluation, deployment readiness.
- ux-ui-designer — Wireframes, flows, accessibility, design QA.
- mobile-developer — Platform-specific builds and store readiness.
- debugger — Repro steps, minimal failing tests, fix validation.
- developer — Generalist for small, scoped tasks.
- documentation-expert — Writes developer and user docs, quickstarts, and runbooks.
- prompt-engineer — System prompts, tool routing, guardrails.

## References

- [nam20485/accp-generator](https://github.com/nam20485/accp-generator) — canonical source agents and conversion reports
- [nam20485/agent-instructions](https://github.com/nam20485/agent-instructions) — canonical instruction modules
