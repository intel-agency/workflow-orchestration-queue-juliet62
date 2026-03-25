#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Idempotent install of all tools required by scripts/validate.ps1.

.DESCRIPTION
    Installs actionlint, hadolint, shellcheck, gitleaks, PSScriptAnalyzer,
    and Pester. Skips anything already present. Works on Windows (winget/choco)
    and Linux (direct binary download, matching CI).

.EXAMPLE
    ./scripts/install-dev-tools.ps1          # install everything
    ./scripts/install-dev-tools.ps1 -Verbose # see skip/install decisions
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$IsWindows_ = $IsWindows -or ($env:OS -eq 'Windows_NT')
$IsLinux_ = $IsLinux -or (!(Test-Path variable:IsWindows) -and $false) -or ($IsLinux -eq $true)

# Ensure GOPATH/bin is on PATH so go-installed tools are detected
$gobin = if ($env:GOBIN) { $env:GOBIN } elseif ($env:GOPATH) { Join-Path $env:GOPATH 'bin' } else { Join-Path $HOME 'go/bin' }
if ((Test-Path $gobin) -and ($env:PATH -notlike "*$gobin*")) {
    $env:PATH = "$gobin$([IO.Path]::PathSeparator)$env:PATH"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Test-Installed { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Install-Binary {
    param(
        [string]$Name,
        [scriptblock]$WindowsInstall,
        [scriptblock]$LinuxInstall
    )
    if (Test-Installed $Name) {
        $ver = & $Name --version 2>&1 | Select-Object -First 1
        Write-Host "  [ok] $Name already installed ($ver)" -ForegroundColor Green
        return
    }
    Write-Host "  [..] Installing $Name..." -ForegroundColor Yellow
    if ($IsWindows_) { & $WindowsInstall } else { & $LinuxInstall }
    if (Test-Installed $Name) {
        $ver = & $Name --version 2>&1 | Select-Object -First 1
        Write-Host "  [ok] $Name installed ($ver)" -ForegroundColor Green
    }
    else {
        Write-Warning "  $Name not found on PATH after install — you may need to restart your shell."
    }
}

# ---------------------------------------------------------------------------
# 1. actionlint
# ---------------------------------------------------------------------------
Write-Host "`nactionlint (GitHub Actions linter)" -ForegroundColor Cyan
Install-Binary 'actionlint' `
    -WindowsInstall {
    if (Test-Installed 'winget') {
        winget install --id rhysd.actionlint --accept-package-agreements --accept-source-agreements --silent
    }
    elseif (Test-Installed 'choco') {
        choco install actionlint -y
    }
    elseif (Test-Installed 'go') {
        go install github.com/rhysd/actionlint/cmd/actionlint@latest
    }
    else { Write-Warning 'No installer found (need winget, choco, or go)' }
} `
    -LinuxInstall {
    $tmp = '/tmp/actionlint'
    curl -sSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash -s -- latest /usr/local/bin
}

# ---------------------------------------------------------------------------
# 2. hadolint
# ---------------------------------------------------------------------------
Write-Host "`nhadolint (Dockerfile linter)" -ForegroundColor Cyan
Install-Binary 'hadolint' `
    -WindowsInstall {
    if (Test-Installed 'scoop') { scoop install hadolint }
    elseif (Test-Installed 'choco') { choco install hadolint -y }
    else { Write-Warning 'No installer found (need scoop or choco)' }
} `
    -LinuxInstall {
    $dest = '/usr/local/bin/hadolint'
    curl -sSL -o $dest https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64
    chmod +x $dest
}

# ---------------------------------------------------------------------------
# 3. shellcheck
# ---------------------------------------------------------------------------
Write-Host "`nshellcheck (shell script linter)" -ForegroundColor Cyan
Install-Binary 'shellcheck' `
    -WindowsInstall {
    if (Test-Installed 'scoop') { scoop install shellcheck }
    elseif (Test-Installed 'choco') { choco install shellcheck -y }
    else { Write-Warning 'No installer found (need scoop or choco)' }
} `
    -LinuxInstall {
    apt-get update -qq && apt-get install -y -qq shellcheck
}

# ---------------------------------------------------------------------------
# 4. gitleaks
# ---------------------------------------------------------------------------
Write-Host "`ngitleaks (secrets scanner)" -ForegroundColor Cyan
Install-Binary 'gitleaks' `
    -WindowsInstall {
    if (Test-Installed 'winget') {
        winget install --id Gitleaks.Gitleaks --accept-package-agreements --accept-source-agreements --silent
    }
    elseif (Test-Installed 'scoop') { scoop install gitleaks }
    elseif (Test-Installed 'choco') { choco install gitleaks -y }
    else { Write-Warning 'No installer found (need winget, scoop, or choco)' }
} `
    -LinuxInstall {
    $tarball = '/tmp/gitleaks.tar.gz'
    curl -sSL -o $tarball https://github.com/gitleaks/gitleaks/releases/download/v8.24.3/gitleaks_8.24.3_linux_x64.tar.gz
    tar -xzf $tarball -C /usr/local/bin gitleaks
    Remove-Item $tarball -Force
    chmod +x /usr/local/bin/gitleaks
}

# ---------------------------------------------------------------------------
# 5. jq
# ---------------------------------------------------------------------------
Write-Host "`njq (JSON processor)" -ForegroundColor Cyan
if (Test-Installed 'jq') {
    $v = jq --version 2>&1 | Select-Object -First 1
    Write-Host "  [ok] jq already installed ($v)" -ForegroundColor Green
}
else {
    Write-Host '  [..] Installing jq...' -ForegroundColor Yellow
    if ($IsWindows_) {
        if (Test-Installed 'winget') { winget install --id jqlang.jq --accept-package-agreements --accept-source-agreements --silent }
        elseif (Test-Installed 'choco') { choco install jq -y }
        else { Write-Warning 'No installer found (need winget or choco)' }
    }
    else {
        apt-get update -qq && apt-get install -y -qq jq
    }
}

# ---------------------------------------------------------------------------
# 6. PowerShell modules
# ---------------------------------------------------------------------------
Write-Host "`nPSScriptAnalyzer (PowerShell linter)" -ForegroundColor Cyan
$pssa = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1
if ($pssa) {
    Write-Host "  [ok] PSScriptAnalyzer $($pssa.Version) already installed" -ForegroundColor Green
}
else {
    Write-Host '  [..] Installing PSScriptAnalyzer 1.24.0...' -ForegroundColor Yellow
    Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.24.0 -Force -Scope CurrentUser
    Write-Host '  [ok] PSScriptAnalyzer installed' -ForegroundColor Green
}

Write-Host "`nPester (PowerShell test framework)" -ForegroundColor Cyan
$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge '5.0.0' } | Select-Object -First 1
if ($pester) {
    Write-Host "  [ok] Pester $($pester.Version) already installed" -ForegroundColor Green
}
else {
    Write-Host '  [..] Installing Pester 5...' -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser -AllowClobber
    Write-Host '  [ok] Pester installed' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=============================" -ForegroundColor Cyan
Write-Host ' Dev tool status' -ForegroundColor Cyan
Write-Host '=============================' -ForegroundColor Cyan
$tools = @('actionlint', 'hadolint', 'shellcheck', 'gitleaks', 'jq')
foreach ($t in $tools) {
    if (Test-Installed $t) {
        $v = & $t --version 2>&1 | Select-Object -First 1
        Write-Host "  [ok] $t — $v" -ForegroundColor Green
    }
    else {
        Write-Host "  [!!] $t — NOT FOUND" -ForegroundColor Red
    }
}
$mods = @('PSScriptAnalyzer', 'Pester')
foreach ($m in $mods) {
    $mod = Get-Module -ListAvailable $m | Select-Object -First 1
    if ($mod) { Write-Host "  [ok] $m — $($mod.Version)" -ForegroundColor Green }
    else { Write-Host "  [!!] $m — NOT FOUND" -ForegroundColor Red }
}
Write-Host ''
