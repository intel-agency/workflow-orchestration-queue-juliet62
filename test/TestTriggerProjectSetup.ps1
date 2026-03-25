#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'trigger-project-setup.ps1' {
    BeforeAll {
        $script:scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/trigger-project-setup.ps1')).Path
    }

    Context 'Parameter validation' {
        It 'Throws when Repo is not in owner/repo format' {
            { . $script:scriptPath -Repo 'badrepo' } | Should -Throw
        }
    }

    Context 'Dry-run mode' {
        It 'Exits 0 with the required Repo param' {
            pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -DryRun" | Out-Null
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
        }

        It 'Output includes project-setup workflow name' {
            $output = pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -DryRun" 2>&1
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
            "$output" | Should -Match 'project-setup'
        }

        It 'Passes Project through to output' {
            $output = pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Project 'My Board' -DryRun" 2>&1
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
            "$output" | Should -Match 'My Board'
        }

        It 'Passes Milestone through to output' {
            $output = pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Milestone 'Phase 1' -DryRun" 2>&1
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
            "$output" | Should -Match 'Phase 1'
        }

        It 'Passes Assignee through to output' {
            $output = pwsh -NoProfile -NoLogo -Command "& '$($script:scriptPath)' -Repo 'owner/repo' -Assignee 'alice' -DryRun" 2>&1
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
            "$output" | Should -Match 'alice'
        }

        It 'Exits 0 with all optional params combined' {
            $cmd = "& '$($script:scriptPath)' -Repo 'owner/repo' " +
                   "-Project 'p' -Milestone 'm' -Template 't.md' -Assignee 'u1' -DryRun"
            pwsh -NoProfile -NoLogo -Command $cmd | Out-Null
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
        }
    }
}
