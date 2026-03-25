#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Create a GitHub issue to dispatch an orchestrator dynamic workflow.

.DESCRIPTION
    Creates an issue with the specified title, body, and labels on a target
    repository.  Designed as the control-flow mechanism for triggering the
    orchestrator-agent workflow via the
    "orchestrate-dynamic-workflow" match clause.

    The default title and body are pre-configured for the
    orchestrate-dynamic-workflow dispatch pattern, but they can be
    overridden for any arbitrary issue creation.

.PARAMETER Repo
    Target repository in the form "owner/repo".

.PARAMETER Title
    Issue title. Default: "orchestrate-dynamic-workflow".

.PARAMETER Body
    Issue body text. When using the default dispatch pattern, include the
    workflow invocation line (e.g., /orchestrate-dynamic-workflow ...).

.PARAMETER Labels
    Optional array of label names to apply to the issue.

.PARAMETER Project
    Optional GitHub project name or number to add the issue to.

.PARAMETER Milestone
    Optional milestone name or number to assign to the issue.

.PARAMETER Template
    Optional issue template filename to use (e.g., "bug_report.md").

.PARAMETER Assignee
    Optional array of GitHub usernames to assign to the issue.

.PARAMETER DryRun
    Show what would be created without making any changes.

.EXAMPLE
    # Dispatch project-setup workflow on a target repo
    ./scripts/create-dispatch-issue.ps1 -Repo "owner/repo" `
        -Body '/orchestrate-dynamic-workflow
    $workflow_name = project-setup'

.EXAMPLE
    # Dispatch with labels
    ./scripts/create-dispatch-issue.ps1 -Repo "owner/repo" `
        -Body '/orchestrate-dynamic-workflow
    $workflow_name = create-epic-v2 { $phase = "1", $line_item = "1.1" }' `
        -Labels "automation","orchestration"

.EXAMPLE
    # Custom issue (non-dispatch)
    ./scripts/create-dispatch-issue.ps1 -Repo "owner/repo" `
        -Title "My custom issue" `
        -Body "Issue description here" `
        -Labels "bug","priority:high"

.EXAMPLE
    # Preview without creating
    ./scripts/create-dispatch-issue.ps1 -Repo "owner/repo" `
        -Body '/orchestrate-dynamic-workflow
    $workflow_name = project-setup' -DryRun

.NOTES
    Requires: GitHub CLI (gh) and authenticated session (gh auth status).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repo,

    [Parameter()]
    [string]$Title = 'orchestrate-dynamic-workflow',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Body,

    [Parameter()]
    [string[]]$Labels,

    [Parameter()]
    [string]$Project,

    [Parameter()]
    [string]$Milestone,

    [Parameter()]
    [string]$Template,

    [Parameter()]
    [string[]]$Assignee,

    [switch]$DryRun
)

function Test-CommandExists {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' not found in PATH. Please install it first."
    }
}

try {
    Test-CommandExists gh
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

# Dot-source common auth helper if present
$commonAuth = Join-Path $PSScriptRoot 'common-auth.ps1'
if (Test-Path -LiteralPath $commonAuth) { . $commonAuth }
if (Get-Command Initialize-GitHubAuth -ErrorAction SilentlyContinue) { Initialize-GitHubAuth } else {
    $st = & gh auth status 2>$null; $code = $LASTEXITCODE
    if ($code -ne 0) { Write-Warning 'GitHub CLI not authenticated. Initiating gh auth login...'; & gh auth login }
}

# Build gh issue create arguments
$ghArgs = @(
    'issue', 'create',
    '--repo', $Repo,
    '--title', $Title,
    '--body', $Body
)

foreach ($label in $Labels) {
    $ghArgs += @('--label', $label)
}
if ($Project) { $ghArgs += @('--project', $Project) }
if ($Milestone) { $ghArgs += @('--milestone', $Milestone) }
if ($Template) { $ghArgs += @('--template', $Template) }
foreach ($a in $Assignee) {
    $ghArgs += @('--assignee', $a)
}

# Display planned action
Write-Host 'Dispatch issue details:' -ForegroundColor Cyan
Write-Host "  Repo:   $Repo"
Write-Host "  Title:  $Title"
Write-Host "  Body:   $Body"
if ($Labels) { Write-Host "  Labels:    $($Labels -join ', ')" }
if ($Project) { Write-Host "  Project:   $Project" }
if ($Milestone) { Write-Host "  Milestone: $Milestone" }
if ($Template) { Write-Host "  Template:  $Template" }
if ($Assignee) { Write-Host "  Assignee:  $($Assignee -join ', ')" }

if ($DryRun) {
    Write-Host '[dry-run] Would run: gh issue create ...' -ForegroundColor Yellow
    exit 0
}

Write-Host 'Creating dispatch issue...' -ForegroundColor Cyan

$issueUrl = & gh @ghArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create issue on repo '$Repo'."
    exit 1
}

Write-Host "Issue created: $issueUrl" -ForegroundColor Green
Write-Output $issueUrl
