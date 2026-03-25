#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Create a GitHub Project (Board template) and link it to a repository.

.DESCRIPTION
    Creates a GitHub Project named after the repository, links it to the repo,
    and sets up standard columns (Not Started, In Progress, In Review, Done).

    This script is designed to be run manually after the devcontainer image has
    been built and the first orchestrator run has completed. It is NOT called
    automatically from any workflow — the timing of image builds makes
    automated project creation unreliable.

.PARAMETER Owner
    GitHub organization or user that owns the repository (e.g. "intel-agency").

.PARAMETER Repo
    Repository name (e.g. "my-app-bravo84"). Do NOT include the owner prefix.

.PARAMETER DryRun
    Show what would be created without making any changes.

.EXAMPLE
    ./scripts/create-project.ps1 -Owner intel-agency -Repo my-app-bravo84

.EXAMPLE
    ./scripts/create-project.ps1 -Owner intel-agency -Repo my-app-bravo84 -DryRun

.NOTES
    Requires: GitHub CLI (gh) authenticated with `project` and `read:project` scopes.
    The GH_ORCHESTRATION_AGENT_TOKEN PAT already has these scopes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "Required command 'gh' not found in PATH. Please install the GitHub CLI first."
    exit 1
}

$fullRepo = "$Owner/$Repo"

Write-Host "Creating GitHub Project for $fullRepo..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "[DryRun] Would create project '$Repo' under owner '$Owner'" -ForegroundColor Yellow
    Write-Host "[DryRun] Would link project to repository $fullRepo" -ForegroundColor Yellow
    return
}

# Create the project
$projectJson = gh project create --owner $Owner --title $Repo --format json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create project: $projectJson"
    exit 1
}

$project = $projectJson | ConvertFrom-Json
$projectNumber = $project.number
Write-Host "Created project #$projectNumber '$Repo'" -ForegroundColor Green

# Link project to repository
gh project link $projectNumber --owner $Owner --repo $fullRepo 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to link project #$projectNumber to $fullRepo — link manually."
} else {
    Write-Host "Linked project #$projectNumber to $fullRepo" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Project URL: $($project.url)" -ForegroundColor Cyan
Write-Host "Note: Configure project columns (Not Started, In Progress, In Review, Done) in the project settings UI." -ForegroundColor DarkGray
