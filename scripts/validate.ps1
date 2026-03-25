#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Single validation script used by both CI (validate.yml) and local dev.

.DESCRIPTION
    Each switch runs one validation category. CI calls individual switches in
    parallel jobs; locally, use -All to run them sequentially.

    -Lint     actionlint, hadolint, shellcheck, PSScriptAnalyzer, JSON syntax
    -Scan     gitleaks secret detection
    -Test     Pester + bash test suites
    -All      Lint, then Scan, then Test (sequential — the local default)

.EXAMPLE
    # CI jobs (parallel)
    pwsh -NoProfile -File ./scripts/validate.ps1 -Lint
    pwsh -NoProfile -File ./scripts/validate.ps1 -Scan
    pwsh -NoProfile -File ./scripts/validate.ps1 -Test

    # Local dev (sequential, all checks)
    pwsh -NoProfile -File ./scripts/validate.ps1 -All
#>
[CmdletBinding()]
param(
    [switch]$Lint,
    [switch]$Scan,
    [switch]$Test,
    [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $script:RepoRoot

# Ensure GOPATH/bin is on PATH so go-installed tools are detected
$gobin = if ($env:GOBIN) { $env:GOBIN } elseif ($env:GOPATH) { Join-Path $env:GOPATH 'bin' } else { Join-Path $HOME 'go/bin' }
if ((Test-Path $gobin) -and ($env:PATH -notlike "*$gobin*")) {
    $env:PATH = "$gobin$([IO.Path]::PathSeparator)$env:PATH"
}

# If -All or no switch specified, run everything
if ($All -or (-not $Lint -and -not $Scan -and -not $Test)) {
    $Lint = $true; $Scan = $true; $Test = $true
}

$script:Failures = @()
$script:Skipped = @()
$script:Passed = @()
$script:Modes = @()

function Invoke-Check {
    param(
        [string]$Name,
        [scriptblock]$Block
    )
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    try {
        & $Block
        $script:Passed += $Name
        Write-Host '  PASS' -ForegroundColor Green
    }
    catch {
        $script:Failures += $Name
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Skip-Check {
    param([string]$Name, [string]$Reason)
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    Write-Host "  SKIP: $Reason" -ForegroundColor Yellow
    $script:Skipped += $Name
}

# ---------------------------------------------------------------------------
# LINT — mirrors validate.yml "lint" job
# ---------------------------------------------------------------------------
if ($Lint) {
    $script:Modes += 'lint'

    # actionlint — GitHub Actions workflow linter
    if (Get-Command actionlint -ErrorAction SilentlyContinue) {
        Invoke-Check 'actionlint' {
            $output = actionlint 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
        }
    }
    else { Skip-Check 'actionlint' 'Not installed (go install github.com/rhysd/actionlint/cmd/actionlint@latest)' }

    # hadolint — Dockerfile linter
    $dockerfile = '.github/.devcontainer/Dockerfile'
    if (Get-Command hadolint -ErrorAction SilentlyContinue) {
        if (Test-Path $dockerfile) {
            Invoke-Check 'hadolint' {
                $output = hadolint $dockerfile 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
            }
        }
        else { Skip-Check 'hadolint' "Dockerfile not found at $dockerfile" }
    }
    else { Skip-Check 'hadolint' 'Not installed (scoop install hadolint / choco install hadolint)' }

    # shellcheck — shell script linter
    $shellFiles = @()
    if (Test-Path 'test/*.sh') { $shellFiles += Get-Item test/*.sh }
    if (Test-Path 'run_opencode_prompt.sh') { $shellFiles += Get-Item run_opencode_prompt.sh }
    if (Get-Command shellcheck -ErrorAction SilentlyContinue) {
        if ($shellFiles.Count -gt 0) {
            Invoke-Check 'shellcheck' {
                $output = shellcheck --severity=warning @($shellFiles.FullName) 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
            }
        }
        else { Skip-Check 'shellcheck' 'No .sh files found' }
    }
    else { Skip-Check 'shellcheck' 'Not installed (scoop install shellcheck / choco install shellcheck)' }

    # PSScriptAnalyzer — PowerShell linter (matches CI excludeRules exactly)
    Invoke-Check 'PSScriptAnalyzer' {
        if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
            Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.24.0 -Force -Scope CurrentUser
        }
        $excludeRules = @(
            'PSAvoidUsingWriteHost',
            'PSAvoidUsingPlainTextForPassword',
            'PSAvoidUsingInvokeExpression',
            'PSAvoidDefaultValueSwitchParameter',
            'PSUseBOMForUnicodeEncodedFile',
            'PSUseSingularNouns',
            'PSUseDeclaredVarsMoreThanAssignments',
            'PSReviewUnusedParameter'
        )
        $results = @()
        if (Test-Path './prompt.ps1') {
            $results += @(Invoke-ScriptAnalyzer -Path ./prompt.ps1 -Severity Warning -ExcludeRule $excludeRules)
        }
        if (Test-Path './scripts/') {
            $results += @(Invoke-ScriptAnalyzer -Path ./scripts/ -Recurse -Severity Warning -ExcludeRule $excludeRules)
        }
        if (Test-Path './test/') {
            $results += @(Invoke-ScriptAnalyzer -Path ./test/ -Recurse -Severity Warning -ExcludeRule $excludeRules)
        }
        if ($results.Count -gt 0) {
            $results | Format-Table -AutoSize | Out-String | Write-Host
            throw "PSScriptAnalyzer found $($results.Count) issue(s)."
        }
    }

    # JSON syntax validation (matches CI file list exactly)
    Invoke-Check 'JSON syntax' {
        $jsonFiles = @(
            '.devcontainer/devcontainer.json',
            '.github/.devcontainer/devcontainer.json',
            '.github/.labels.json',
            '.vscode/settings.json',
            'global.json',
            'opencode.json'
        )
        if (Test-Path 'test/fixtures/*.json') {
            $jsonFiles += (Get-Item test/fixtures/*.json).FullName
        }
        $errors = 0
        foreach ($f in $jsonFiles) {
            if (-not (Test-Path $f)) { continue }
            try {
                Get-Content -Raw $f | ConvertFrom-Json | Out-Null
            }
            catch {
                Write-Host "  Invalid JSON: $f — $_" -ForegroundColor Red
                $errors++
            }
        }
        if ($errors -gt 0) { throw "Found $errors JSON validation error(s)." }
    }
}

# ---------------------------------------------------------------------------
# SCAN — mirrors validate.yml "scan" job
# ---------------------------------------------------------------------------
if ($Scan) {
    $script:Modes += 'scan'

    if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
        Invoke-Check 'gitleaks' {
            $output = gitleaks detect --source . --redact --no-git=false 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
        }
    }
    else { Skip-Check 'gitleaks' 'Not installed (scoop install gitleaks / choco install gitleaks)' }
}

# ---------------------------------------------------------------------------
# TEST — mirrors validate.yml test-pester / test-prompt-assembly / test-image-tag-logic
# ---------------------------------------------------------------------------
if ($Test) {
    $script:Modes += 'test'

    # Pester tests
    Invoke-Check 'Pester tests' {
        if (-not (Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge '5.0.0' })) {
            Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser -AllowClobber
        }
        $output = pwsh -NoProfile -File ./test/run-pester-tests.ps1 -OutputXml ./test-results-pester.xml 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
        Write-Host ($output -join "`n")
    }

    # Prompt assembly tests (bash — skip on Windows if bash unavailable)
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        if (Test-Path 'test/test-prompt-assembly.sh') {
            Invoke-Check 'prompt-assembly tests' {
                $output = bash test/test-prompt-assembly.sh 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
                Write-Host ($output -join "`n")
            }
        }
        if (Test-Path 'test/test-image-tag-logic.sh') {
            Invoke-Check 'image-tag-logic tests' {
                $output = bash test/test-image-tag-logic.sh 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
                Write-Host ($output -join "`n")
            }
        }
    }
    else { Skip-Check 'bash tests' 'bash not available on this system' }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Pop-Location
$modeLabel = $script:Modes -join ', '

Write-Host "`n=============================" -ForegroundColor Cyan
Write-Host " Validation Summary ($modeLabel)" -ForegroundColor Cyan
Write-Host '=============================' -ForegroundColor Cyan
if ($script:Passed.Count -gt 0) { Write-Host "  PASS:    $($script:Passed -join ', ')" -ForegroundColor Green }
if ($script:Skipped.Count -gt 0) { Write-Host "  SKIP:    $($script:Skipped -join ', ')" -ForegroundColor Yellow }
if ($script:Failures.Count -gt 0) {
    Write-Host "  FAIL:    $($script:Failures -join ', ')" -ForegroundColor Red
    Write-Host ''
    exit 1
}

if ($script:Passed.Count -eq 0) {
    Write-Host '  No checks ran — install at least one tool.' -ForegroundColor Yellow
    exit 1
}

Write-Host ''
exit 0
