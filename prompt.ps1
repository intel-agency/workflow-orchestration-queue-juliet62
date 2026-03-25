#!/usr/bin/env pwsh

param(
    [string]$File,
    [string]$Prompt,
    [string]$Attach,
    [string]$Username,   # prefer env var OPENCODE_AUTH_USER
    [string]$Password,   # prefer env var OPENCODE_AUTH_PASS
    [string]$Dir,
    [ValidateSet("DEBUG","INFO","WARN","ERROR")]
    [string]$LogLevel = "INFO",
    [switch]$PrintLogs
)

# Resolve the prompt from either a file or a string argument
if ($File)
{
    $prompt = Get-Content -Raw -Path $File
} elseif ($Prompt)
{
    $prompt = $Prompt
} else
{
    Write-Error "Either -File <path> or -Prompt <string> must be specified."
    exit 1
}

# Credentials: flags take precedence over env vars
$user = if ($Username)
{ $Username 
} else
{ $env:OPENCODE_AUTH_USER 
}
$pass = if ($Password)
{ $Password 
} else
{ $env:OPENCODE_AUTH_PASS 
}

# Embed basic auth credentials into the attach URL if provided
$attachUrl = $Attach
if ($attachUrl -and $user -and $pass)
{
    if ($attachUrl -match '^http://')
    {
        Write-Warning "Basic auth credentials over http:// are sent in plaintext — use https://"
    }
    $uri = [System.Uri]$attachUrl
    $attachUrl = "$($uri.Scheme)://${user}:${pass}@$($uri.Authority)$($uri.PathAndQuery)"
} elseif (($user -or $pass) -and -not $attachUrl)
{
    Write-Error "OPENCODE_AUTH_USER/PASS (or -Username/-Password) require -Attach <url>"
    exit 1
}

$opencodeArgs = @(
    "run",
    "--model", "zai-coding-plan/glm-5",
    "--agent", "orchestrator",
    "--log-level", $LogLevel
)

if ($attachUrl)
{ $opencodeArgs += "--attach", $attachUrl 
}
if ($Dir)
{ $opencodeArgs += "--dir",    $Dir       
}
if ($PrintLogs)
{ $opencodeArgs += "--print-logs"         
}

$opencodeArgs += $prompt

opencode @opencodeArgs
