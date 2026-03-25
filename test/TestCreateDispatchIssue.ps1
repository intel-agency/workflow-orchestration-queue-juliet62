#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'create-dispatch-issue.ps1' {
    BeforeAll {
        $script:scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/create-dispatch-issue.ps1')).Path
    }

    Context 'Parameter validation' {
        # These throw during param() binding, before any exit call, so dot-source is safe.

        It 'Throws when Repo is not in owner/repo format' {
            { . $script:scriptPath -Repo 'invalidrepo' -Body 'test body' } | Should -Throw
        }

        It 'Throws when Body is empty' {
            { . $script:scriptPath -Repo 'owner/repo' -Body '' } | Should -Throw
        }
    }

    Context 'Dry-run mode' {
        # Scripts call exit - run as subprocess so the Pester host is not terminated.
        # gh auth status succeeds on CI because GH_TOKEN is set; dry-run exits before
        # gh issue create, so no real issue is ever created.

        It 'Exits 0 with minimal required params' {
            pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Body 'test body' -DryRun" | Out-Null
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
        }

        It 'Exits 0 with a custom Title' {
            pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Title 'my-issue' -Body 'test body' -DryRun" | Out-Null
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
        }

        It 'Exits 0 with Labels' {
            pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Body 'b' -Labels 'automation','orchestration' -DryRun" | Out-Null
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
        }

        It 'Includes Project in output when provided' {
            $output = pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Body 'b' -Project 'My Board' -DryRun" 2>&1
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
            "$output" | Should -Match 'Project'
            "$output" | Should -Match 'My Board'
        }

        It 'Includes Milestone in output when provided' {
            $output = pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Body 'b' -Milestone 'Phase 1' -DryRun" 2>&1
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
            "$output" | Should -Match 'Milestone'
            "$output" | Should -Match 'Phase 1'
        }

        It 'Includes Template in output when provided' {
            $output = pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Body 'b' -Template 'bug_report.md' -DryRun" 2>&1
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
            "$output" | Should -Match 'Template'
            "$output" | Should -Match 'bug_report'
        }

        It 'Includes Assignee in output when provided' {
            $output = pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Body 'b' -Assignee 'alice','bob' -DryRun" 2>&1
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
            "$output" | Should -Match 'Assignee'
            "$output" | Should -Match 'alice'
        }

        It 'Exits 0 with all optional params combined' {
            $cmd = "& '$($script:scriptPath)' -Repo 'owner/repo' -Body 'b' " +
                   "-Labels 'l1' -Project 'p' -Milestone 'm' -Template 't.md' -Assignee 'u1' -DryRun"
            pwsh -NoProfile -NoLogo -Command $cmd | Out-Null
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
        }
    }

    Context 'Missing gh binary' {
        BeforeAll {
            $script:emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) "no-gh-$(New-Guid)"
            New-Item -ItemType Directory -Path $script:emptyDir -Force | Out-Null
        }

        AfterAll {
            Remove-Item -Recurse -Force $script:emptyDir -ErrorAction SilentlyContinue
        }

        It 'Exits non-zero when gh is not in PATH' {
            # Override PATH in the subprocess so gh cannot be found.
            pwsh -NoProfile -NoLogo -Command "
                `$env:PATH = '$($script:emptyDir)'
                & '$($script:scriptPath)' -Repo 'owner/repo' -Body 'test body'
            " 2>&1 | Out-Null
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Not -Be 0
        }
    }
}
