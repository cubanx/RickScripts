BeforeAll {
    . "$PSScriptRoot/../Common/OrcaReap.ps1"
    . "$PSScriptRoot/../Functions/Remove-OldOrcaWorktree.ps1"

    function New-ReapFixture {
        $script:Tree = [ordered]@{
            id = 'ds9::/tmp/quark'; path = '/tmp/quark'; repoId = 'ds9'
            hostId = 'local'; instanceId = 'quark-1'
            identity = @{ key = 'wt2:local:quark-1'; executionHostId = 'local'; instanceId = 'quark-1' }
            isMainWorktree = $false; isPinned = $false; isBare = $false
            lastActivityAt = [DateTimeOffset]::UtcNow.AddDays(-40).ToUnixTimeMilliseconds()
            head = 'abcdef'; branch = 'refs/heads/quark'; baseRef = 'refs/remotes/origin/main'
            childWorktreeIds = @()
        }
        $script:Activity = [ordered]@{
            worktreeId = $script:Tree.id; path = $script:Tree.path; hostId = 'local'
            worktreeInstanceId = 'quark-1'; status = 'inactive'; liveTerminalCount = 0
            lastActivityAt = $script:Tree.lastActivityAt
            hasAttachedPty = $false; hasHostSidebarActivity = $false; isActive = $false
            agents = @(); isMainWorktree = $false; isPinned = $false
        }
        $script:Scope = @{ hostIds = @('local'); omittedHostIds = @() }
        $script:Truncated = $false; $script:Total = 1
        $script:Calls = @(); $script:ShowCount = 0; $script:Change = $null
        $script:BadJson = $false; $script:RemoveFailure = $false; $script:Tabs = @()
        $script:LocalFiles = $false; $script:GitSafe = $true; $script:Removed = $false
        $script:KeepRemovedListed = $false; $script:TerminalRows = @(); $script:Runtime = 'ds9-runtime'
    }
}

Describe 'Remove-OldOrcaWorktree safety workflow' {
    BeforeEach {
        New-ReapFixture
        Mock Get-OrcaReapGitSafety { if (-not $script:GitSafe) { throw 'GitUnverified' }; [pscustomobject]@{ HasLocalFiles = $script:LocalFiles } }
        Mock Invoke-OrcaReapCommand {
            param($Executable, $Arguments)
            $command = $Arguments -join ' '
            $script:Calls += $command
            if ($script:BadJson) { return '{not-json secret=do-not-display' }
            $result = switch -Wildcard ($command) {
                'worktree list *' { @{ worktrees = @(if (-not $script:Removed -or $script:KeepRemovedListed) { $script:Tree }); hostScope = $script:Scope; totalCount = $(if ($script:Removed -and -not $script:KeepRemovedListed) { 0 } else { $script:Total }); truncated = $script:Truncated } }
                'worktree ps *' { @{ worktrees = @($script:Activity); hostScope = $script:Scope; totalCount = $script:Total; truncated = $script:Truncated } }
                'worktree show *' {
                    $script:ShowCount++
                    if ($script:ShowCount -gt 1 -and $script:Change) { & $script:Change }
                    @{ worktree = $script:Tree }
                }
                'terminal list *' { @{ terminals = $script:TerminalRows; hostScope = $script:Scope; totalCount = $script:TerminalRows.Count; truncated = $false } }
                'tab list *' { @{ tabs = $script:Tabs } }
                'worktree rm *' {
                    if ($script:RemoveFailure) { throw 'CommandExit:17' }
                    $script:Removed = $true
                    @{ removed = $true }
                }
                default { throw 'UnexpectedCommand' }
            }
            @{ ok = $true; result = $result; _meta = @{ runtimeId = $script:Runtime } } | ConvertTo-Json -Depth 12 -Compress
        }
    }

    It 'reports an old inactive candidate with WhatIf' {
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.CandidateCount | Should -Be 1
        $r.DeletedCount | Should -Be 0
        $r.Results[0].Status | Should -Be 'Candidate'
        $script:Calls -join '|' | Should -Not -Match 'worktree rm'
    }
    It 'supports configurable age and excludes exactly the threshold or newer' {
        (Remove-OldOrcaWorktree -WhatIf -InactiveDays 45).SkippedCount | Should -Be 1
        (Remove-OldOrcaWorktree -WhatIf -InactiveDays 35).CandidateCount | Should -Be 1
        $script:Tree.lastActivityAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        (Remove-OldOrcaWorktree).CandidateCount | Should -Be 0
    }
    It 'uses ShouldProcess and never removes with WhatIf' {
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.DeletedCount | Should -Be 0
        $script:Calls -join '|' | Should -Not -Match 'worktree rm'
    }
    It 'revalidates then removes only through the supported guarded command' {
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.DeletedCount | Should -Be 1
        $script:ShowCount | Should -Be 2
        @($script:Calls | Where-Object { $_ -like 'worktree rm *' })[0] | Should -Be 'worktree rm --worktree identity:wt2:local:quark-1 --run-hooks --json'
        Should -Invoke Get-OrcaReapGitSafety -Times 2 -Exactly
    }
    It 'skips unsafe metadata: <Label>' -ForEach @(
        @{ Label = 'main'; Key = 'isMainWorktree'; Value = $true }
        @{ Label = 'pinned'; Key = 'isPinned'; Value = $true }
        @{ Label = 'bare'; Key = 'isBare'; Value = $true }
        @{ Label = 'missing timestamp'; Key = 'lastActivityAt'; Value = $null }
        @{ Label = 'invalid timestamp'; Key = 'lastActivityAt'; Value = 'yesterday' }
        @{ Label = 'zero timestamp'; Key = 'lastActivityAt'; Value = 0 }
        @{ Label = 'foreign host'; Key = 'hostId'; Value = 'mordor' }
        @{ Label = 'children'; Key = 'childWorktreeIds'; Value = @('ds9::/tmp/rom') }
    ) {
        $script:Tree[$Key] = $Value
        (Remove-OldOrcaWorktree -Confirm:$false).SkippedCount | Should -Be 1
        $script:Removed | Should -BeFalse
    }
    It 'requires all inactivity indicators: <Key>' -ForEach @(
        @{ Key = 'status'; Value = 'active' }
        @{ Key = 'liveTerminalCount'; Value = 1 }
        @{ Key = 'liveTerminalCount'; Value = '0' }
        @{ Key = 'hasAttachedPty'; Value = $true }
        @{ Key = 'hasHostSidebarActivity'; Value = $true }
        @{ Key = 'isActive'; Value = $true }
        @{ Key = 'agents'; Value = @(@{state='working'}) }
    ) {
        $script:Activity[$Key] = $Value
        (Remove-OldOrcaWorktree -Confirm:$false).SkippedCount | Should -Be 1
    }
    It 'does not interpret archived metadata as sleep or eligibility' {
        $script:Tree.isArchived = $true
        $script:Activity.status = 'working'
        (Remove-OldOrcaWorktree).CandidateCount | Should -Be 0
    }
    It 'rejects missing inactivity fields' {
        $script:Activity.Remove('hasAttachedPty')
        (Remove-OldOrcaWorktree).SkippedCount | Should -Be 1
    }
    It 'excludes browser resources and unsafe Git' {
        $script:Tabs = @(@{browserPageId='quark-browser'})
        (Remove-OldOrcaWorktree).CandidateCount | Should -Be 0
        $script:Tabs = @(); $script:GitSafe = $false
        (Remove-OldOrcaWorktree).CandidateCount | Should -Be 0
    }
    It 'blocks removal for partial scope or truncated/count-mismatched coverage: <Kind>' -ForEach @(
        @{ Kind = 'truncated' }; @{ Kind = 'omitted' }; @{ Kind = 'count' }; @{ Kind = 'unknown' }
    ) {
        switch ($Kind) {
            truncated { $script:Truncated = $true }
            omitted { $script:Scope.omittedHostIds = @('gondor') }
            count { $script:Total = 2 }
            unknown { $script:Scope = @{} }
        }
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.CoverageComplete | Should -BeFalse
        $r.DeletedCount | Should -Be 0
        $script:Removed | Should -BeFalse
    }
    It 'handles malformed JSON without leaking raw output' {
        $script:BadJson = $true
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.CoverageComplete | Should -BeFalse
        $r.FailedCount | Should -Be 1
        $r | ConvertTo-Json -Depth 10 | Should -Not -Match 'do-not-display'
    }
    It 'rejects a duplicate identity instead of guessing' {
        Mock Invoke-OrcaReapCommand { '{"ok":true,"result":{"worktrees":[{},{}],"totalCount":2,"truncated":false,"hostScope":{"hostIds":["local"],"omittedHostIds":[]}}}' }
        (Remove-OldOrcaWorktree -Confirm:$false).DeletedCount | Should -Be 0
    }
    It 'skips a changed candidate during revalidation: <Kind>' -ForEach @(
        @{ Kind = 'identity' }; @{ Kind = 'activity' }; @{ Kind = 'git' }; @{ Kind = 'terminal' }; @{ Kind = 'pinned' }
    ) {
        $script:Change = switch ($Kind) {
            identity { { $script:Tree.instanceId = 'rom-2' } }
            activity { { $script:Tree.lastActivityAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() } }
            git { { $script:GitSafe = $false } }
            terminal { { $script:Activity.liveTerminalCount = 1 } }
            pinned { { $script:Tree.isPinned = $true } }
        }
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.SkippedCount | Should -Be 1
        $script:Removed | Should -BeFalse
    }
    It 'lists local-file blockers with a Force hint instead of removing them' {
        $script:LocalFiles = $true
        $r = Remove-OldOrcaWorktree -WarningAction SilentlyContinue
        $r.NeedsForce.Count | Should -Be 1
        $r.NeedsForce[0].Reason | Should -Be 'GitDirty'
        $script:Removed | Should -BeFalse
    }
    It 'uses Orca force only for explicit Force while honoring WhatIf' {
        $script:LocalFiles = $true
        (Remove-OldOrcaWorktree -Force -WhatIf).CandidateCount | Should -Be 1
        $script:Removed | Should -BeFalse
        (Remove-OldOrcaWorktree -Force -Confirm:$false).DeletedCount | Should -Be 1
        @($script:Calls | Where-Object { $_ -like 'worktree rm *' })[0] | Should -Be 'worktree rm --worktree identity:wt2:local:quark-1 --run-hooks --force --json'
    }
    It 'never bypasses commit or resource safety with Force' {
        $script:GitSafe = $false
        (Remove-OldOrcaWorktree -Force).CandidateCount | Should -Be 0
        $script:GitSafe = $true; $script:Activity.hasAttachedPty = $true
        (Remove-OldOrcaWorktree -Force).CandidateCount | Should -Be 0
        $script:Removed | Should -BeFalse
    }
    It 'does not recommend Force when files coexist with active resources' {
        $script:LocalFiles = $true; $script:Tabs = @(@{browserPageId='odo'})
        (Remove-OldOrcaWorktree).NeedsForce.Count | Should -Be 0
    }
    It 'skips activity timestamp drift even if the workspace is currently inactive' {
        $script:Activity.lastActivityAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        (Remove-OldOrcaWorktree).CandidateCount | Should -Be 0
    }
    It 'refuses a live terminal found by the independent terminal listing' {
        $script:TerminalRows = @(@{handle='term-quark'})
        (Remove-OldOrcaWorktree).CandidateCount | Should -Be 0
        $script:Removed | Should -BeFalse
    }
    It 'marks coverage incomplete if it changes during revalidation' {
        $script:Change = { $script:Truncated = $true }
        $r = Remove-OldOrcaWorktree
        $r.CoverageComplete | Should -BeFalse
        $r.Results[0].Reason | Should -Be 'IncompleteCoverage'
        $script:Removed | Should -BeFalse
    }
    It 'refuses a runtime restart during revalidation' {
        $script:Change = { $script:Runtime = 'ds9-restarted' }
        $r = Remove-OldOrcaWorktree
        $r.CoverageComplete | Should -BeFalse
        $r.Results[0].Reason | Should -Be 'RuntimeChanged'
        $script:Removed | Should -BeFalse
    }
    It 'does not report success when removal is not confirmed by a complete listing' {
        $script:KeepRemovedListed = $true
        $r = Remove-OldOrcaWorktree
        $r.DeletedCount | Should -Be 0
        $r.FailedCount | Should -Be 1
        $r.CoverageComplete | Should -BeFalse
        $r.Results[0].Reason | Should -Be 'RemovalUnverified'
        @($script:Calls | Where-Object { $_ -like 'worktree rm *' }).Count | Should -Be 1
    }
    It 'reports a removal failure without retries' {
        $script:RemoveFailure = $true
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.FailedCount | Should -Be 1
        $r.DeletedCount | Should -Be 0
        @($script:Calls | Where-Object { $_ -like 'worktree rm *' }).Count | Should -Be 1
    }
}

Describe 'Orca reap real Git safety boundaries (disposable local repositories)' {
    BeforeAll {
        function Invoke-FixtureGit {
            param([string[]]$Arguments)
            Invoke-OrcaReapCommand -Executable 'git' -Arguments $Arguments -TimeoutSeconds 10
        }
    }
    BeforeEach {
        $script:GitRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Repo = Join-Path $script:GitRoot 'shire'
        $script:Remote = Join-Path $script:GitRoot 'gondor.git'
        $script:Checkout = Join-Path $script:GitRoot 'samwise'
        New-Item -ItemType Directory $script:GitRoot | Out-Null
        Invoke-FixtureGit @('init', '--initial-branch=main', $script:Repo) | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'config', 'user.name', 'Samwise Gamgee') | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'config', 'user.email', 'samwise@example.invalid') | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'config', 'commit.gpgSign', 'false') | Out-Null
        Set-Content (Join-Path $script:Repo 'seed.txt') 'There and back again'
        Invoke-FixtureGit @('-C', $script:Repo, 'add', '.') | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'commit', '-m', 'seed') | Out-Null
        Invoke-FixtureGit @('clone', '--bare', $script:Repo, $script:Remote) | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'remote', 'add', 'origin', $script:Remote) | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'fetch', 'origin') | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'worktree', 'add', '-b', 'samwise', $script:Checkout, 'main') | Out-Null
        $script:GitTree = @{
            path = (Get-Item $script:Checkout).FullName
            head = (Invoke-FixtureGit @('-C', $script:Checkout, 'rev-parse', 'HEAD')).Trim()
            branch = 'refs/heads/samwise'; baseRef = 'refs/remotes/origin/main'
        }
    }
    It 'accepts a clean branch whose HEAD/reflog is merged into a freshly verified remote base' {
        (Get-OrcaReapGitSafety $script:GitTree).HasLocalFiles | Should -BeFalse
    }
    It 'identifies tracked, untracked and ignored files without bypassing commit checks: <Kind>' -ForEach @(
        @{Kind='tracked'}; @{Kind='untracked'}; @{Kind='ignored'}
    ) {
        switch ($Kind) {
            tracked { Set-Content (Join-Path $script:Checkout 'seed.txt') 'Frodo was here' }
            untracked { Set-Content (Join-Path $script:Checkout 'frodo.txt') 'Precious' }
            ignored {
                $exclude = (Invoke-FixtureGit @('-C', $script:Checkout, 'rev-parse', '--git-path', 'info/exclude')).Trim()
                Add-Content $exclude 'precious.txt'
                Set-Content (Join-Path $script:Checkout 'precious.txt') 'Ignored but not disposable'
            }
        }
        (Get-OrcaReapGitSafety $script:GitTree).HasLocalFiles | Should -BeTrue
    }
    It 'rejects an unmerged/unpushed commit' {
        Invoke-FixtureGit @('-C', $script:Checkout, 'commit', '--allow-empty', '-m', 'unpublished') | Out-Null
        $script:GitTree.head = (Invoke-FixtureGit @('-C', $script:Checkout, 'rev-parse', 'HEAD')).Trim()
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw
    }
    It 'rejects stale remote tracking refs even when the cached base contains HEAD' {
        Invoke-FixtureGit @('-C', $script:Repo, 'commit', '--allow-empty', '-m', 'remote drift') | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'push', 'origin', 'main') | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'update-ref', 'refs/remotes/origin/main', $script:GitTree.head) | Out-Null
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw '*GitRemoteStale*'
    }
    It 'rejects an unavailable remote without treating cached refs as proof' {
        Invoke-FixtureGit @('-C', $script:Repo, 'remote', 'set-url', 'origin', (Join-Path $script:GitRoot 'missing.git')) | Out-Null
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw '*CommandExit*'
    }
    It 'rejects abandoned commits in the checkout reflog' {
        Invoke-FixtureGit @('-C', $script:Checkout, 'commit', '--allow-empty', '-m', 'abandoned') | Out-Null
        Invoke-FixtureGit @('-C', $script:Checkout, 'reset', '--hard', $script:GitTree.head) | Out-Null
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw
    }
    It 'independently refuses the main checkout' {
        $script:GitTree.path = $script:Repo; $script:GitTree.branch = 'refs/heads/main'
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw '*GitUnverified*'
    }
    It 'rejects a locked worktree' {
        Invoke-FixtureGit @('-C', $script:Repo, 'worktree', 'lock', $script:Checkout) | Out-Null
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw '*GitUnverified*'
    }
    It 'rejects missing/detached/local-only base verification' {
        $script:GitTree.baseRef = 'refs/heads/main'
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw '*GitUnverified*'
        Invoke-FixtureGit @('-C', $script:Checkout, 'checkout', '--detach') | Out-Null
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw
    }
    It 'does not allow inherited Git selectors to redirect inspection' {
        $prior = $env:GIT_WORK_TREE
        try {
            $env:GIT_WORK_TREE = $script:Repo
            (Get-OrcaReapGitSafety $script:GitTree).HasLocalFiles | Should -BeFalse
        }
        finally { $env:GIT_WORK_TREE = $prior }
    }
}

Describe 'Orca reap command transport and parsing' {
    It 'bounds a hanging command and returns sanitized diagnostics' {
        { Invoke-OrcaReapCommand -Executable 'pwsh' -Arguments @('-NoProfile', '-Command', 'Start-Sleep 10') -TimeoutSeconds 1 } | Should -Throw '*CommandTimeout*'
    }
    It 'never exposes stderr from a failed command' {
        try {
            Invoke-OrcaReapCommand -Executable 'pwsh' -Arguments @('-NoProfile', '-Command', '[Console]::Error.WriteLine("secret-from-quark"); exit 17')
            throw 'Expected failure'
        }
        catch { Get-OrcaReapDiagnostic $_ | Should -Be 'CommandExit:17' }
    }
    It 'rejects malformed success envelopes: <Text>' -ForEach @(
        @{Text='null'}; @{Text='{}'}; @{Text='{"ok":"true","result":{}}'}
        @{Text='{"ok":false,"error":"secret"}'}; @{Text='{"ok":true,"result":[],"_meta":{"runtimeId":"ds9"}}'}
    ) {
        { ConvertFrom-OrcaReapResponse $Text } | Should -Throw '*InvalidResponse*'
    }
    It 'exports only the public cmdlet through the module manifest' {
        Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force
        (Get-Module RickScripts).ExportedFunctions.ContainsKey('Remove-OldOrcaWorktree') | Should -BeTrue
        (Get-Module RickScripts).ExportedFunctions.ContainsKey('Get-OrcaReapGitSafety') | Should -BeFalse
    }
}
