Describe 'Super Push isolated task preparation' {
    BeforeAll {
        . "$PSScriptRoot/../Functions/Invoke-SuperPush.ps1"
        . "$PSScriptRoot/../Functions/New-SuperPushCandidate.ps1"
        function Invoke-FixtureGit {
            param([string]$Root, [string[]]$Arguments)
            $output = @(& /usr/bin/git -C $Root @Arguments 2>&1)
            if ($LASTEXITCODE) { throw "Fixture Git failed: $($output -join '`n')" }
            ,$output
        }
        function Add-FixtureCommit {
            param([string]$Root, [string]$Path, [string]$Text)
            $file = Join-Path $Root $Path
            [IO.Directory]::CreateDirectory((Split-Path $file)) | Out-Null
            [IO.File]::WriteAllText($file, $Text)
            Invoke-FixtureGit $Root @('add', '--', $Path) | Out-Null
            Invoke-FixtureGit $Root @('commit', '-m', "add Bajor $Path") | Out-Null
            (Invoke-FixtureGit $Root @('rev-parse', 'HEAD'))[-1]
        }
    }

    BeforeEach {
        $script:fixture = Join-Path ([IO.Path]::GetTempPath()) "super-push-bajor-$([guid]::NewGuid())"
        [IO.Directory]::CreateDirectory($fixture) | Out-Null
        $script:remote = Join-Path $fixture 'remote.git'
        $script:source = Join-Path $fixture 'source'
        $script:upstream = Join-Path $fixture 'upstream'
        & /usr/bin/git init --bare --initial-branch=main $remote 2>&1 | Out-Null
        & /usr/bin/git clone $remote $source 2>&1 | Out-Null
        Invoke-FixtureGit $source @('config', 'user.name', 'Bajor Test') | Out-Null
        Invoke-FixtureGit $source @('config', 'user.email', 'bajor@example.invalid') | Out-Null
        $script:base = Add-FixtureCommit $source 'docs/base.md' 'Deep Space Nine'
        Invoke-FixtureGit $source @('push', 'origin', 'HEAD:main') | Out-Null
        & /usr/bin/git clone $remote $upstream 2>&1 | Out-Null
        Invoke-FixtureGit $upstream @('config', 'user.name', 'Bajor Test') | Out-Null
        Invoke-FixtureGit $upstream @('config', 'user.email', 'bajor@example.invalid') | Out-Null
        Invoke-FixtureGit $source @('checkout', '-b', 'bajor-task') | Out-Null
        Mock Get-CrispRepository { 'Crisp-Inc/bajor-test' }
        Mock Get-SuperPushAppCredential { throw 'Preparation must not access credentials' }
        Mock Invoke-SuperPushGit { throw 'Preparation must not push' }
        $script:candidate = $null
    }

    AfterEach {
        foreach ($line in (Invoke-FixtureGit $source @('worktree', 'list', '--porcelain'))) {
            if ($line -like 'worktree *rickscripts-super-push-candidate-*') {
                $path = $line.Substring(9)
                Invoke-FixtureGit $source @('worktree', 'remove', '--force', $path) | Out-Null
                Remove-Item (Split-Path $path) -Recurse -Force
            }
        }
        Remove-Item $fixture -Recurse -Force
    }

    It 'replays only selected docs onto advanced main and preserves staged, dirty and untracked source work' {
        $unrelated = Add-FixtureCommit $source 'docs/unrelated.md' 'Quark'
        $task = Add-FixtureCommit $source 'docs/task.md' 'Kira'
        $advanced = Add-FixtureCommit $upstream 'docs/remote.md' 'Sisko'
        Invoke-FixtureGit $upstream @('push', 'origin', 'HEAD:main') | Out-Null
        [IO.File]::WriteAllText((Join-Path $source 'docs/base.md'), 'staged Odo')
        Invoke-FixtureGit $source @('add', 'docs/base.md') | Out-Null
        [IO.File]::AppendAllText((Join-Path $source 'docs/base.md'), ' dirty Worf')
        [IO.File]::WriteAllText((Join-Path $source 'untracked.txt'), 'Dax')
        $status = Invoke-FixtureGit $source @('status', '--porcelain=v1')
        $index = Invoke-FixtureGit $source @('diff', '--cached')
        $dirty = Invoke-FixtureGit $source @('diff')
        $candidate = New-SuperPushCandidate -SourcePath $source -TaskCommit @($task)
        $candidate.OldSha | Should -Be $advanced
        $candidate.NewSha | Should -Not -Be $task
        $candidate.DocumentationOnly | Should -BeTrue
        Test-Path (Join-Path $candidate.Root 'docs/unrelated.md') | Should -BeFalse
        Test-Path (Join-Path $candidate.Root 'docs/remote.md') | Should -BeTrue
        (Invoke-FixtureGit $candidate.Root @('rev-list', '--count', "$advanced..HEAD"))[-1] | Should -Be '1'
        (Invoke-FixtureGit $source @('rev-parse', 'HEAD'))[-1] | Should -Be $task
        (Invoke-FixtureGit $source @('branch', '--show-current'))[-1] | Should -Be 'bajor-task'
        (Invoke-FixtureGit $source @('status', '--porcelain=v1')) | Should -Be $status
        (Invoke-FixtureGit $source @('diff', '--cached')) | Should -Be $index
        (Invoke-FixtureGit $source @('diff')) | Should -Be $dirty
        (Invoke-FixtureGit $candidate.Root @('branch', '--show-current')).Count | Should -Be 0
        Should -Invoke Get-SuperPushAppCredential -Times 0 -Exactly
        Should -Invoke Invoke-SuperPushGit -Times 0 -Exactly
    }

    It 'rebuilds docs preparation if main advances during replay, before approval' {
        $task = Add-FixtureCommit $source 'docs/task.md' 'Kira'
        $script:ActualCandidateGit = (Get-Command Invoke-GitCommand).ScriptBlock
        $script:MainAdvanced = $false
        $script:ReplayCount = 0
        Mock Invoke-GitCommand {
            param([string[]]$Arguments, [switch]$AllowFailure)
            $result = & $script:ActualCandidateGit -Arguments $Arguments -AllowFailure:$AllowFailure
            if ($Arguments -contains 'cherry-pick') {
                $script:ReplayCount++
                if (-not $script:MainAdvanced) {
                    $script:MainAdvanced = $true
                    Add-FixtureCommit $upstream 'docs/remote.md' 'Sisko' | Out-Null
                    Invoke-FixtureGit $upstream @('push', 'origin', 'HEAD:main') | Out-Null
                }
            }
            $result
        }
        $candidate = New-SuperPushCandidate -SourcePath $source -TaskCommit @($task)
        $ReplayCount | Should -Be 2
        Test-Path (Join-Path $candidate.Root 'docs/remote.md') | Should -BeTrue
        $candidate.OldSha | Should -Be (Invoke-FixtureGit $upstream @('rev-parse', 'HEAD'))[-1]
        @((Invoke-FixtureGit $source @('worktree', 'list', '--porcelain')) | Where-Object { $_ -like 'worktree *' }).Count | Should -Be 2
        Should -Invoke Invoke-SuperPushGit -Times 0 -Exactly
    }

    It 'bounds continuous pre-approval docs races to three preparation attempts' {
        $task = Add-FixtureCommit $source 'docs/task.md' 'Kira'
        $script:ActualCandidateGit = (Get-Command Invoke-GitCommand).ScriptBlock
        $script:ReplayCount = 0
        Mock Invoke-GitCommand {
            param([string[]]$Arguments, [switch]$AllowFailure)
            $result = & $script:ActualCandidateGit -Arguments $Arguments -AllowFailure:$AllowFailure
            if ($Arguments -contains 'cherry-pick') {
                $script:ReplayCount++
                Add-FixtureCommit $upstream "docs/race-$script:ReplayCount.md" 'Quark' | Out-Null
                Invoke-FixtureGit $upstream @('push', 'origin', 'HEAD:main') | Out-Null
            }
            $result
        }
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($task) } | Should -Throw '*Remote main changed*'
        $ReplayCount | Should -Be 3
        @((Invoke-FixtureGit $source @('worktree', 'list', '--porcelain')) | Where-Object { $_ -like 'worktree *' }).Count | Should -Be 1
        Should -Invoke Invoke-SuperPushGit -Times 0 -Exactly
    }

    It 'requires explicit full SHAs, rejecting missing scope, duplicates, wrong order and already published commits' {
        $first = Add-FixtureCommit $source 'docs/first.md' 'Kira'
        $second = Add-FixtureCommit $source 'docs/second.md' 'Odo'
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @() } | Should -Throw
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @('HEAD') } | Should -Throw '*full commit SHA*'
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($first, $first) } | Should -Throw '*duplicate*'
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($second, $first) } | Should -Throw '*order*'
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($base) } | Should -Throw '*already*'
    }

    It 'stops on conflicts without altering source or retaining failed worktrees' {
        $task = Add-FixtureCommit $source 'docs/base.md' 'Kira changed line'
        Add-FixtureCommit $upstream 'docs/base.md' 'Sisko changed line' | Out-Null
        Invoke-FixtureGit $upstream @('push', 'origin', 'HEAD:main') | Out-Null
        $before = Invoke-FixtureGit $source @('worktree', 'list', '--porcelain')
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($task) } | Should -Throw '*cherry-pick*'
        (Invoke-FixtureGit $source @('worktree', 'list', '--porcelain')) | Should -Be $before
        (Invoke-FixtureGit $source @('rev-parse', 'HEAD'))[-1] | Should -Be $task
        (Invoke-FixtureGit $source @('status', '--porcelain=v1')).Count | Should -Be 0
    }

    It 'requires validation for non-docs, rejects failed validation and validates the isolated cwd' {
        $task = Add-FixtureCommit $source 'code.txt' 'Dax'
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($task) } | Should -Throw '*validation*'
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($task) -ValidationCommand @('/usr/bin/false') } | Should -Throw '*validation*'
        $candidate = New-SuperPushCandidate -SourcePath $source -TaskCommit @($task) -ValidationCommand @(
            (Get-Command pwsh).Source, '-NoProfile', '-Command',
            'if ((git branch --show-current) -or -not (Test-Path ./code.txt)) { exit 1 }; exit 0'
        )
        $candidate.DocumentationOnly | Should -BeFalse
        $candidate.ValidationPassed | Should -BeTrue
        Get-SuperPushCandidateReceipt $candidate | Should -Not -BeNullOrEmpty
    }

    It 'rejects validation that mutates the candidate' {
        $task = Add-FixtureCommit $source 'code.txt' 'Dax'
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($task) -ValidationCommand @(
            (Get-Command pwsh).Source, '-NoProfile', '-Command', 'Set-Content ./code.txt Odo'
        ) } | Should -Throw '*clean worktree*'
    }

    It 'does not treat a docs net diff hiding executable intermediate commits as docs-only' {
        $code = Add-FixtureCommit $source 'code.txt' 'Quark'
        Remove-Item (Join-Path $source 'code.txt')
        Invoke-FixtureGit $source @('add', '-A') | Out-Null
        Invoke-FixtureGit $source @('commit', '-m', 'remove Quark code') | Out-Null
        $revert = (Invoke-FixtureGit $source @('rev-parse', 'HEAD'))[-1]
        $docs = Add-FixtureCommit $source 'docs/task.md' 'Kira'
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($code, $revert, $docs) } | Should -Throw '*validation*'
        $candidate = New-SuperPushCandidate -SourcePath $source -TaskCommit @($code, $revert, $docs) -ValidationCommand @('/usr/bin/true')
        $candidate.DocumentationOnly | Should -BeFalse
    }

    It 'rejects foreign and merge commits rather than expanding task scope' {
        $foreign = Add-FixtureCommit $upstream 'docs/foreign.md' 'Quark'
        Invoke-FixtureGit $source @('fetch', $upstream, 'HEAD') | Out-Null
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($foreign) } | Should -Throw '*source HEAD*'
        Add-FixtureCommit $source 'docs/task.md' 'Kira' | Out-Null
        Invoke-FixtureGit $source @('merge', '--no-ff', '-m', 'merge Bajor', $foreign) | Out-Null
        $merge = (Invoke-FixtureGit $source @('rev-parse', 'HEAD'))[-1]
        { New-SuperPushCandidate -SourcePath $source -TaskCommit @($merge) } | Should -Throw '*not merges*'
    }

    It 'freezes validation receipt identity across approval' {
        $task = Add-FixtureCommit $source 'docs/task.md' 'Kira'
        $candidate = New-SuperPushCandidate -SourcePath $source -TaskCommit @($task)
        Push-Location $candidate.Root
        try {
            $before = Get-SuperPushState
            $gitDir = (Invoke-FixtureGit $candidate.Root @('rev-parse', '--absolute-git-dir'))[-1]
            Add-Content (Join-Path $gitDir 'super-push-candidate.json') ' '
            $after = Get-SuperPushState
            { Assert-UnchangedState $before $after } | Should -Throw '*ReceiptFingerprint*'
        } finally { Pop-Location }
    }

    It 'does not rewrite an already prepared detached candidate during broker entry' {
        $task = Add-FixtureCommit $source 'docs/task.md' 'Kira'
        $candidate = New-SuperPushCandidate -SourcePath $source -TaskCommit @($task)
        Push-Location $candidate.Root
        try {
            Initialize-SuperPushInvocation | Should -BeNullOrEmpty
            { Initialize-SuperPushInvocation -TaskCommit @($task) } | Should -Throw '*cannot be rewritten*'
            (Invoke-FixtureGit $candidate.Root @('rev-parse', 'HEAD'))[-1] | Should -Be $candidate.NewSha
        } finally { Pop-Location }
    }

    It 'rejects candidate and remote drift after preparation instead of rebuilding' {
        $task = Add-FixtureCommit $source 'docs/task.md' 'Kira'
        $candidate = New-SuperPushCandidate -SourcePath $source -TaskCommit @($task)
        $original = $candidate.NewSha
        Add-FixtureCommit $candidate.Root 'docs/drift.md' 'Quark' | Out-Null
        { Assert-SuperPushCandidate $candidate } | Should -Throw '*candidate*'
        Invoke-FixtureGit $candidate.Root @('reset', '--hard', $original) | Out-Null
        Add-FixtureCommit $upstream 'docs/remote.md' 'Sisko' | Out-Null
        Invoke-FixtureGit $upstream @('push', 'origin', 'HEAD:main') | Out-Null
        { Assert-SuperPushCandidate $candidate } | Should -Throw '*main*'
        (Invoke-FixtureGit $candidate.Root @('rev-parse', 'HEAD'))[-1] | Should -Be $original
    }

    Context 'human orchestration with fake provider boundaries' {
        BeforeEach {
            Mock Write-Host {}
            Mock Confirm-SuperPush {}
            Mock Show-SuperPushCandidatePatch {}
            Mock Save-SuperPushDiagnostics { Join-Path $fixture 'diagnostics.txt' }
            Mock Get-SuperPushAppCredential { [pscustomobject]@{ ClientId = 'Iv1.bajor'; PrivateKey = 'fictional-key' } }
            Mock New-SuperPushToken {
                [pscustomobject]@{ token = 'fictional-token'; expires_at = '2099-01-01T00:00:00Z'; repository_selection = 'selected'; permissions = [pscustomobject]@{ contents = 'write' }; repositories = @([pscustomobject]@{ full_name = 'Crisp-Inc/bajor-test' }); installation_id = 1701 }
            }
            Mock Invoke-SuperPushGit { param($State); $script:candidate = $State }
            Mock Remove-SuperPushToken {}
            Mock Update-SuperPushTrackingRef {}
        }

        It 'prepares advanced-main docs and skips typed approval with one simulated push' {
            $task = Add-FixtureCommit $source 'docs/task.md' 'Kira'
            $advanced = Add-FixtureCommit $upstream 'docs/remote.md' 'Sisko'
            Invoke-FixtureGit $upstream @('push', 'origin', 'HEAD:main') | Out-Null
            Push-Location $source
            try {
                Invoke-SuperPush -TaskCommit @($task)
                (Get-Location).Path | Should -Be $source
            } finally { Pop-Location }
            $candidate.OldSha | Should -Be $advanced
            $candidate.NewSha | Should -Not -Be $task
            Should -Invoke Confirm-SuperPush -Times 0 -Exactly
            Should -Invoke Show-SuperPushCandidatePatch -Times 1 -Exactly
            Should -Invoke Invoke-SuperPushGit -Times 1 -Exactly
            Should -Invoke Remove-SuperPushToken -Times 1 -Exactly
        }

        It 'requires validation before non-docs confirmation and credentials' {
            $task = Add-FixtureCommit $source 'code.txt' 'Dax'
            Push-Location $source
            try {
                { Invoke-SuperPush -TaskCommit @($task) } | Should -Throw '*validation*'
            } finally { Pop-Location }
            Should -Invoke Confirm-SuperPush -Times 0 -Exactly
            Should -Invoke Get-SuperPushAppCredential -Times 0 -Exactly
            Push-Location $source
            try { Invoke-SuperPush -TaskCommit @($task) -ValidationCommand @('/usr/bin/true') }
            finally { Pop-Location }
            Should -Invoke Confirm-SuperPush -Times 1 -Exactly
            Should -Invoke Invoke-SuperPushGit -Times 1 -Exactly
        }

        It 'stops an approval-time main race before credentials, without a new candidate or retry' {
            $task = Add-FixtureCommit $source 'code.txt' 'Dax'
            Mock Confirm-SuperPush {
                Add-FixtureCommit $upstream 'docs/race.md' 'Quark' | Out-Null
                Invoke-FixtureGit $upstream @('push', 'origin', 'HEAD:main') | Out-Null
            }
            Push-Location $source
            try {
                { Invoke-SuperPush -TaskCommit @($task) -ValidationCommand @('/usr/bin/true') } | Should -Throw '*Phase=pre-credential*'
                (Get-Location).Path | Should -Be $source
            } finally { Pop-Location }
            Should -Invoke Get-SuperPushAppCredential -Times 0 -Exactly
            Should -Invoke Invoke-SuperPushGit -Times 0 -Exactly
            @((Invoke-FixtureGit $source @('worktree', 'list', '--porcelain')) | Where-Object { $_ -like 'worktree *' }).Count | Should -Be 2
        }
    }
}
