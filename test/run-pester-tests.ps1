#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run all Pester tests in the test/ directory.

.DESCRIPTION
    Installs Pester 5 if not already available, discovers all Test*.ps1 files
    in the same directory as this script, runs them, and exits non-zero if any
    test fails. Optionally emits a JUnit XML results file for CI consumption.

.PARAMETER TestPath
    Path(s) to search for test files. Defaults to the directory containing
    this script.

.PARAMETER OutputXml
    Path for the JUnit XML test results file. Defaults to
    test-results-pester.xml in the repository root.

.PARAMETER Verbosity
    Pester output verbosity. One of: None, Normal, Detailed, Diagnostic.
    Default: Detailed.

.EXAMPLE
    # Run all tests
    ./test/run-pester-tests.ps1

.EXAMPLE
    # Run with custom output path
    ./test/run-pester-tests.ps1 -OutputXml ./results/pester.xml

.NOTES
    Requires PowerShell 7+ and network access to install Pester if not present.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$TestPath = @($PSScriptRoot),

    [Parameter()]
    [string]$OutputXml = (Join-Path $PSScriptRoot '../test-results-pester.xml'),

    [Parameter()]
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Detailed'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure Pester 5 is available
$pesterModule = Get-Module -Name Pester -ListAvailable | Where-Object { $_.Version -ge '5.0.0' } | Select-Object -First 1
if (-not $pesterModule) {
    Write-Host 'Pester 5 not found. Installing...' -ForegroundColor Cyan
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser -AllowClobber
}
Import-Module Pester -MinimumVersion 5.0.0 -Force

# Discover test files
$testFiles = $TestPath | ForEach-Object {
    Get-ChildItem -Path $_ -Filter 'Test*.ps1' -ErrorAction SilentlyContinue
} | Select-Object -ExpandProperty FullName -Unique

if (-not $testFiles -or @($testFiles).Count -eq 0) {
    Write-Host 'No Test*.ps1 files found.' -ForegroundColor Yellow
    exit 0
}

Write-Host "Discovered $(@($testFiles).Count) test file(s):" -ForegroundColor Cyan
$testFiles | ForEach-Object { Write-Host "  $_" }

# Configure and run
$config = New-PesterConfiguration
$config.Run.Path = $testFiles
$config.Run.PassThru = $true
$config.Output.Verbosity = $Verbosity
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = $OutputXml
$config.TestResult.OutputFormat = 'JUnitXml'

$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) {
    Write-Error "Pester: $($result.FailedCount) test(s) failed out of $($result.TotalCount)."
    exit 1
}

Write-Host "All $($result.PassedCount) Pester test(s) passed." -ForegroundColor Green
