# Validation Guide

This repository uses a **single shared script** for both CI and local validation — zero drift between what CI checks and what you can check locally.

## Quick Start

```powershell
# Install all required tools (idempotent — safe to re-run)
pwsh -NoProfile -File ./scripts/install-dev-tools.ps1

# Run ALL checks (lint + scan + test)
pwsh -NoProfile -File ./scripts/validate.ps1
```

That's it. If it passes locally, CI will pass too.

## Commands

| Switch | What it runs | When to use |
|--------|-------------|-------------|
| *(none)* or `-All` | Lint → Scan → Test (sequential) | Default — use after every change |
| `-Lint` | actionlint, hadolint, shellcheck, PSScriptAnalyzer, JSON syntax | Quick check on workflow/script edits |
| `-Scan` | gitleaks secret detection | Before committing sensitive changes |
| `-Test` | Pester unit tests, prompt-assembly tests, image-tag-logic tests | After lint passes |

```powershell
# Examples
./scripts/validate.ps1              # all checks (default)
./scripts/validate.ps1 -Lint        # just linting
./scripts/validate.ps1 -Scan        # just secrets scan
./scripts/validate.ps1 -Test        # just tests
./scripts/validate.ps1 -All         # explicit all (same as no args)
```

## How CI Uses the Same Script

`.github/workflows/validate.yml` calls the exact same script with individual switches in **parallel jobs**:

```
lint job  →  validate.ps1 -Lint
scan job  →  validate.ps1 -Scan
test job  →  validate.ps1 -Test
```

If you add a check to CI, add it to `validate.ps1` too (and vice versa). This is enforced in `AGENTS.md`.

## Tool Installation

```powershell
pwsh -NoProfile -File ./scripts/install-dev-tools.ps1
```

This script is **idempotent** — it skips anything already installed and prints `[ok]` for each tool found. Re-running it is fast (seconds, not minutes).

### Required Tools

| Tool | Purpose | Windows install | Linux (CI) install |
|------|---------|----------------|-------------------|
| **actionlint** | GitHub Actions workflow linter | winget / choco / go | curl binary |
| **hadolint** | Dockerfile linter | scoop / choco | curl binary |
| **shellcheck** | Shell script linter | scoop / choco | apt-get |
| **gitleaks** | Secrets scanner | winget / scoop / choco | curl binary |
| **jq** | JSON processor | winget / choco | apt-get |
| **PSScriptAnalyzer** | PowerShell linter | Install-Module | Install-Module |
| **Pester** | PowerShell test framework | Install-Module | Install-Module |

### Windows: Admin vs Non-Admin

- **winget** and **scoop**: work without admin
- **choco**: requires an elevated (admin) shell

If choco fails with "Access denied", either:
1. Open PowerShell as Administrator and re-run the install script
2. Use scoop: `scoop install hadolint shellcheck gitleaks`

## Reading the Output

```
=== actionlint ===
  PASS                          ← tool ran, no issues found

=== hadolint ===
  SKIP: Not installed (...)     ← tool not present, check was skipped

=== PSScriptAnalyzer ===
  FAIL                          ← issues found — fix before committing

=============================
 Validation Summary (lint, scan, test)
=============================
  PASS:    actionlint, PSScriptAnalyzer, JSON syntax, Pester tests
  SKIP:    hadolint, shellcheck, gitleaks
  FAIL:    (none)
```

- **PASS**: check ran and found no problems
- **SKIP**: tool not installed locally — the check still runs in CI
- **FAIL**: issues found — the script exits non-zero and prints details

## Workflow

```
Make changes → Run validate.ps1 → Fix failures → Re-run → Commit
```

The rule is simple: **do not commit or push until validation passes.** This is enforced in `AGENTS.md` for AI agents and recommended for all contributors.
