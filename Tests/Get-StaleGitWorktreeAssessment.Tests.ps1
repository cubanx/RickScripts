BeforeAll {
    . "$PSScriptRoot/../Common/Get-StaleGitWorktreeAssessment.ps1"

    function git {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

        $path = $null
        $commandParts = @()
        for ($i = 0; $i -lt $Args.Length; $i++) {
            if ($Args[$i] -eq '-C' -and ($i + 1) -lt $Args.Length) {
                $path = $Args[++$i]
                continue
            }
            $commandParts += $Args[$i]
        }

        $command = $commandParts -join ' '
        $script:GitCallLog += "$path|$command"
        $global:LASTEXITCODE = 0

        if ($path -eq '/tmp/stale' -and $command -like 'for-each-ref --contains HEAD --format=*') {
            return @('main', 'origin/main')
        }

        switch ("$path|$command") {
            '/tmp/stale|status --porcelain=v1 --untracked-files=all' { return @() }
            '/tmp/stale|log --oneline HEAD --not --branches --remotes --tags' { return @() }
            '/tmp/stale|rev-parse HEAD' { return 'abcdef1234567890' }
            '/tmp/stale|rev-parse --short HEAD' { return 'abcdef1' }
            '/tmp/dirty|status --porcelain=v1 --untracked-files=all' { return ' M file.txt' }
            '/tmp/unique|status --porcelain=v1 --untracked-files=all' { return @() }
            '/tmp/unique|log --oneline HEAD --not --branches --remotes --tags' { return 'deadbeef unique' }
            '/tmp/unique|rev-parse HEAD' { return 'cafebabe12345678' }
            '/tmp/unique|rev-parse --short HEAD' { return 'cafebab' }
            default { return @() }
        }
    }

    $script:Worktrees = @(
        [PSCustomObject]@{ Path = '/tmp/stale'; RepositoryRoot = '/tmp/repo'; IsDetached = $true; IsBare = $false }
        [PSCustomObject]@{ Path = '/tmp/stay'; RepositoryRoot = '/tmp/repo'; IsDetached = $false; IsBare = $false }
        [PSCustomObject]@{ Path = '/tmp/dirty'; RepositoryRoot = '/tmp/repo2'; IsDetached = $true; IsBare = $false }
        [PSCustomObject]@{ Path = '/tmp/unique'; RepositoryRoot = '/tmp/repo3'; IsDetached = $true; IsBare = $false }
    )
}

Describe 'Get-StaleGitWorktreeAssessment' {
    BeforeEach {
        $script:GitCallLog = @()
    }

    It 'marks a clean detached worktree with shared refs and an owner as stale' {
        $assessment = Get-StaleGitWorktreeAssessment -Worktree $script:Worktrees[0] -AllWorktrees $script:Worktrees

        $assessment.IsStale | Should -BeTrue
        $assessment.OwnerPath | Should -Be '/tmp/stay'
        $assessment.ShortHead | Should -Be 'abcdef1'
    }

    It 'keeps an attached worktree' {
        (Get-StaleGitWorktreeAssessment -Worktree $script:Worktrees[1] -AllWorktrees $script:Worktrees).IsStale | Should -BeFalse
    }

    It 'keeps a dirty detached worktree' {
        (Get-StaleGitWorktreeAssessment -Worktree $script:Worktrees[2] -AllWorktrees $script:Worktrees).IsStale | Should -BeFalse
    }

    It 'keeps a detached worktree with unique commits' {
        (Get-StaleGitWorktreeAssessment -Worktree $script:Worktrees[3] -AllWorktrees $script:Worktrees).IsStale | Should -BeFalse
    }
}
