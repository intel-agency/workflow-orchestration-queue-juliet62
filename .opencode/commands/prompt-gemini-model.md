---
description: Prompt Gemini model with a prompt
model: google/gemini-2.5-pro
---

# Gemini Model Invoker

A prompt used by GitHub Copilot Chat to invoke the Gemini model.

Implemented by using the VS Code GitHub Copilot Chat to invoke the Gemini model with the $ARGUMENTS as message.

- All tools approved.
- Read output from model's output or chat UI.

---

## Optional modules — activated

The following optional modes are enabled by default. Apply them in addition to the main task instructions. Keep responses concise, concrete, and actionable.

### 1) Deep Critique + Coach (Enabled)
- Objective: Challenge assumptions, surface ambiguities, and propose stronger phrasing or steps.
- Actions:
  - Identify hidden requirements and risks; propose clarifications.
  - Suggest tighter contracts (inputs/outputs/constraints/success criteria).
  - Prefer small, testable, idempotent steps.

### 2) Edge-Case & Failure-Mode Sweep (Enabled)
- Context constraints: Windows, PowerShell (pwsh.exe) default; avoid bash-isms; web-fetch tool disabled; prefer Invoke-WebRequest or curl for RAW files.
- Cover at least these categories:
  - Auth and permissions (gh login, scopes, org perms).
  - Network/transient errors, retries, rate limits.
  - Idempotency on reruns (no duplicates/corruption).
  - Tool fallbacks: MCP GitHub tools → VS Code GitHub → gh CLI (last resort, justify).
  - File path and encoding pitfalls on Windows.
- Output: A short checklist of mitigations next to each risk.

### 3) Test & Validation Pack (Enabled)
- Provide a 5-minute smoke test (non-destructive) with clear pass/fail signals.
- Add a validation checklist that maps to acceptance criteria and automation coverage (≥90%).
- Include a minimal log/telemetry plan (no secrets) for troubleshooting.

### Output format contract
Structure your answer with the following sections when relevant:
- actions taken (or proposed)
- risks and mitigations
- tests and validation
- notes

Keep terminal examples PowerShell-compatible. Do not run commands unless explicitly requested. Prefer brief lists over long prose.

<!--
copilot-source:
  file: prompt-gemini-model.prompt.md
  mode: agent
  model: gemini-2.5-pro
  notes: >
    Source had an unusual multi-separator YAML structure with 'description'
    and 'arguments' defined outside the first frontmatter block. The description
    and arguments section were treated as body content in the source.
    Arguments: name=prompt, description="The prompt to send to Gemini."
    Source referenced '$prompt' variable; translated to $ARGUMENTS for OpenCode.
-->
