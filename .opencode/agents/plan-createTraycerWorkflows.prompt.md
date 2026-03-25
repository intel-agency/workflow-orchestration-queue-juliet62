# Plan: Create Traycer Workflows from Source Agent/Prompt Files

Translate your `.source/agents/` and `.source/prompts/` structure into Traycer's system using a **hybrid approach**: local files for templates/CLI agents/AGENTS.md, plus a specification document for manual UI workflow creation.

## Key Research Findings

| Question | Answer |
|----------|--------|
| **Workflow storage** | **UI/cloud only** — no local filesystem storage for workflows. Created via `+ Add Workflow` in Traycer UI panel. |
| **Local file options** | CLI Agents: `~/.traycer/cli-agents` or `.traycer/cli-agents`. Templates: Markdown + frontmatter. AGENTS.md auto-detected. |
| **Tool specifications** | Traycer doesn't support per-command tool allowlists. Tools come via MCP integrations or CLI agent configs. Embed tool guidance in instructions instead. |

## Steps

1. **Create a "Project Setup" workflow spec document** in the repo (e.g., `.traycer/workflows/project-setup.workflow.md`) that documents the workflow structure for manual UI entry:
   - Workflow name, description, entrypoint
   - Each command: name, description, argument hints (`$1`, `$2`), next steps, instruction body
   - Maps `orchestrate-project-setup.prompt.md` → `trigger_workflow`, `orchestrate-dynamic-workflow.prompt.md` → `orchestrate-dynamic-workflow`, `continue-orchestrating-project-setup.prompt.md` → `continue-workflow`, `assign.prompt.md` → `assign-agent`

2. **Create Traycer templates** in `.traycer/templates/` with `applicableFor: plan` or `generic` to inject your agent delegation patterns into Traycer's plan handoff:
   - Template wrapping `{{planMarkdown}}` with references to `@orchestrator`, `@researcher` delegation conventions
   - Preserve instruction links to agent-instructions repo (<https://github.com/nam20485/agent-instructions>)

3. **Generate CLI agent wrappers** in `.traycer/cli-agents/` for specialized agent invocations:
   - Example: `orchestrator.sh` / `orchestrator.ps1` that passes `$TRAYCER_PROMPT` with orchestrator-specific flags

4. **Create an AGENTS.md file** at repo root documenting your agent structure (from `.source/agents/instructions/list.md`) so Traycer auto-detects agent capabilities for task context

5. **Update** `generate-target-commands.md` with Traycer target index entry documenting:
   - Workflow creation: UI-only (no local files)
   - Templates: `.traycer/templates/*.md` with frontmatter (`displayName`, `applicableFor`)
   - CLI Agents: `~/.traycer/cli-agents` (user) or `.traycer/cli-agents` (workspace)
   - AGENTS.md: auto-detected at repo root

## Field Mapping

| Source Field | Traycer Equivalent | Notes |
|--------------|-------------------|-------|
| `mode: agent` | Command in workflow (UI) | Indicates workflow command type |
| `description` | Command description | Shown in `/` picker |
| `tools` | Embed in instructions | No native tool allowlist; reference via prose |
| Input vars (`$workflow_name`) | Argument hints + `$1`, `$2` refs | Configure hints in UI, reference in markdown |
| Body instructions | Command instruction markdown | Direct copy with `$N` variable substitution |
| Chained prompts (`/orchestrate-dynamic-workflow`) | Next Steps config | Link commands in UI |

## Deliverables

- `.traycer/workflows/project-setup.workflow.md` — Spec doc for UI workflow creation
- `.traycer/templates/orchestrator-plan.md` — Template with agent delegation patterns
- `.traycer/cli-agents/orchestrator.ps1` — Windows CLI agent wrapper
- `AGENTS.md` — Agent index for Traycer auto-detection
- Updated `generate-target-commands.md` with Traycer target entry
