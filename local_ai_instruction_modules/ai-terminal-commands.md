# Terminal Commands Cheat Sheet

Default shell: **bash** (WSL Ubuntu 24.04). PowerShell (pwsh) is also frequently used.
Detect before running commands: `echo $0` (bash) or `$PSVersionTable` (pwsh).

## Bash basics

- Download raw file: `curl -sL <raw-url> -o <path>`
- JSON: `cat file.json | jq .`
- Current shell: `echo $SHELL` or `echo $0`

## PowerShell basics

- Download raw file: `Invoke-WebRequest -Uri <raw-url> -OutFile <path>`
- JSON: `Get-Content -Raw file.json | ConvertFrom-Json`
- Current shell: `$PSVersionTable.PSEdition`

## GitHub CLI (gh)

- Auth: `gh auth status`
- Repo: `gh repo create owner/name --public|--private --template nam20485/ai-new-app-template`
- View: `gh repo view owner/name -w`
- Issues: `gh issue create -t "Title" -b "Body"`
- Subissue: `gh issue create --title "Subissue Title" --body "Details" --parent 123`
- PR: `gh pr create --title "Title" --body "Body" --base main`

## PR Review Thread Management

**Always use `scripts/query.ps1` instead of writing custom scripts for PR review comment resolution.**

```powershell
# List unresolved review threads
pwsh ./scripts/query.ps1 -Owner <owner> -Repo <repo> -PullRequestNumber <num> -NoResolve

# Auto-resolve all with a reply
pwsh ./scripts/query.ps1 -Owner <owner> -Repo <repo> -PullRequestNumber <num> -AutoResolve -ReplyEach "Fixed in commit abc123."

# Dry run (show what would be resolved)
pwsh ./scripts/query.ps1 -Owner <owner> -Repo <repo> -PullRequestNumber <num> -DryRun
```

## Git

- Clone: `git clone https://github.com/owner/name.git`
- Branch: `git checkout -B main`
- Commit: `git add -A && git commit -m "msg" && git push -u origin main`

## Running PowerShell scripts from bash

```bash
pwsh ./scripts/import-labels.ps1
pwsh ./scripts/create-milestones.ps1
```

## Safety

- bash: use `set -e` for strict error handling; quote variables (`"$var"`)
- pwsh: use `-WhatIf`/`-Confirm` for destructive cmdlets; use `-LiteralPath` and `Join-Path`

## Terminal/CLI Error Handling

- Check last exit code: `$?` (bash) or `$LASTEXITCODE` (pwsh)
- If a command fails, **BEFORE retrying:**
  - Read the error message and its context for hints
  - Verify command syntax with `--help` or `Get-Help`
  - Inspect usage syntax and examples; construct a correct command based on careful analysis
  - If the command is complex, break it into smaller parts and test each one
  - If it still fails, search the web for the error message to find solutions
- **DO NOT keep retrying the same command without understanding the issue.**
  - Diagnose and fix the problem **before** retrying
  - If you can't resolve it within 3 tries, search for documentation and/or solutions
- Once a working command is found, document it in the Examples section below with a short description

## Examples

<!-- Add working commands here with notes on what problems were encountered. -->

---

This file standardizes terminal usage when automation tools are unavailable.
