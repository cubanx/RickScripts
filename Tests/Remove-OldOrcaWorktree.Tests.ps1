BeforeAll {
    . "$PSScriptRoot/../Common/OrcaReap.ps1"
    . "$PSScriptRoot/../Common/OrcaReapDisplay.ps1"
    . "$PSScriptRoot/../Functions/Remove-OldOrcaWorktree.ps1"

    $script:RealPathProbe = (Get-Command Get-OrcaReapPathMissing).ScriptBlock

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
        $script:GitSafe = $true; $script:Removed = $false
        $script:PathMissing = $false; $script:KeepRemovedListed = $false; $script:TerminalRows = @(); $script:Runtime = 'ds9-runtime'
    }
}

Describe 'Remove-OldOrcaWorktree safety workflow' {
    BeforeEach {
        New-ReapFixture
        Mock Initialize-OrcaReapSpectre {}
        Mock Show-OrcaReapSpectre {}
        Mock Get-OrcaReapPathMissing { $script:PathMissing }
        Mock Get-OrcaReapGitSafety { if (-not $script:GitSafe) { throw 'GitUnverified' }; [pscustomobject]@{ Verified = $true } }
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

    It 'previews missing directories regardless of age/timestamp without Git inspection: <Timestamp>' -ForEach @(
        @{ Timestamp = 0 }
        @{ Timestamp = $null }
        @{ Timestamp = 'unknown' }
        @{ Timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
    ) {
        $script:PathMissing = $true
        $script:Tree.lastActivityAt = $Timestamp
        $script:Activity.lastActivityAt = $Timestamp
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.CandidateCount | Should -Be 1
        $r.Results[0].MissingPath | Should -BeTrue
        $r.Results[0].Checks.Ready | Should -BeTrue
        $r.Results[0].Explanation | Should -Match 'Missing directory.*waiver'
        Should -Invoke Get-OrcaReapGitSafety -Times 0 -Exactly
        $script:Removed | Should -BeFalse
    }
    It 'waives hooks only for a revalidated missing directory and verifies removal' {
        $script:PathMissing = $true
        $script:Tree.lastActivityAt = 0; $script:Activity.lastActivityAt = 0
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.DeletedCount | Should -Be 1
        $r.Results[0].MissingPath | Should -BeTrue
        @($script:Calls | Where-Object { $_ -like 'worktree rm *' }) | Should -Be @('worktree rm --worktree identity:wt2:local:quark-1 --run-hooks --allow-failed-archive-hook --json')
        Should -Invoke Get-OrcaReapGitSafety -Times 0 -Exactly
    }
    It 'uses the global browser inventory instead of the hanging per-worktree query' {
        $script:PathMissing = $true
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.CandidateCount | Should -Be 1
        @($script:Calls | Where-Object { $_ -like 'tab list *' }) | Should -Be @('tab list --worktree all --json')
    }
    It 'blocks tabs associated with the exact candidate worktree' {
        $script:PathMissing = $true
        $script:Tabs = @(@{ browserPageId='odo-page'; worktreeId=$script:Tree.id })
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.Results[0].Reason | Should -Be 'ActiveResources'
        $script:Removed | Should -BeFalse
    }
    It 'does not let tabs on unrelated worktrees block cleanup' {
        $script:PathMissing = $true
        $script:Tabs = @(@{ browserPageId='rom-page'; worktreeId='ds9::/tmp/quark-other' })
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.CandidateCount | Should -Be 1
        $r.Results[0].Checks.Ready | Should -BeTrue
        $script:Removed | Should -BeFalse
    }
    It 'fails closed on unassignable global tab records: <Kind>' -ForEach @(
        @{ Kind='missing' }; @{ Kind='blank' }; @{ Kind='scalar' }; @{ Kind='null-inventory' }
    ) {
        $script:PathMissing = $true
        $script:Tabs = switch ($Kind) {
            missing { ,@{browserPageId='odo-page'} }
            blank { ,@{browserPageId='odo-page';worktreeId=' '} }
            scalar { ,42 }
            null-inventory { $null }
        }
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.Results[0].Reason | Should -Be 'ActiveResources'
        $script:Removed | Should -BeFalse
    }
    It 'refreshes global tabs during revalidation and blocks newly opened tabs' {
        $script:PathMissing = $true
        $script:Change = { $script:Tabs = @(@{browserPageId='odo-page';worktreeId=$script:Tree.id}) }
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.Results[0].Reason | Should -Be 'ActiveResources'
        @($script:Calls | Where-Object { $_ -eq 'tab list --worktree all --json' }).Count | Should -Be 2
        $script:Removed | Should -BeFalse
    }
    It 'never waives hooks for existing paths even with Force' {
        Remove-OldOrcaWorktree -Force -Confirm:$false | Out-Null
        $script:Calls -join '|' | Should -Not -Match '--allow-failed-archive-hook'
    }
    It 'does not remove a missing entry that gains a directory during revalidation' {
        $script:PathMissing = $true
        $script:Change = { $script:PathMissing = $false }
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.Results[0].Reason | Should -Be 'PathChanged'
        $r.Results[0].Checks.Ready | Should -BeFalse
        $script:Removed | Should -BeFalse
    }
    It 'fails closed on permission or other path inspection errors' {
        Mock Get-OrcaReapPathMissing { throw 'PathUnverified' }
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.Results[0].Reason | Should -Be 'PathUnverified'
        $script:Removed | Should -BeFalse
    }
    It 'checks absence again immediately before removal' {
        $script:MissingProbes = 0
        Mock Get-OrcaReapPathMissing { $script:MissingProbes++; $script:MissingProbes -lt 4 }
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.Results[0].Reason | Should -Be 'PathChanged'
        $r.Results[0].Checks.Ready | Should -BeFalse
        $script:Removed | Should -BeFalse
        $script:Calls -join '|' | Should -Not -Match 'worktree rm'
    }
    It 'does not retry an uncertain missing-entry removal' {
        $script:PathMissing = $true; $script:RemoveFailure = $true
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.FailedCount | Should -Be 1
        $r.Results[0].Checks.Ready | Should -BeFalse
        @($script:Calls | Where-Object { $_ -like 'worktree rm *' }).Count | Should -Be 1
    }
    It 'revalidates a real missing directory and refuses one that reappears' {
        Mock Get-OrcaReapPathMissing { param($Path); & $script:RealPathProbe -Path $Path }
        $script:Tree.path = Join-Path $TestDrive 'ds9-stale-registration'
        $script:Tree.id = "ds9::$($script:Tree.path)"
        $script:Activity.path = $script:Tree.path
        $script:Activity.worktreeId = $script:Tree.id
        $script:Tree.lastActivityAt = 0; $script:Activity.lastActivityAt = 0
        $preview = Remove-OldOrcaWorktree -WhatIf
        $preview.CandidateCount | Should -Be 1
        $preview.Results[0].MissingPath | Should -BeTrue
        $script:ShowCount = 0
        $script:Change = { New-Item -ItemType Directory $script:Tree.path | Out-Null }
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.Results[0].Reason | Should -Be 'PathChanged'
        Test-Path -LiteralPath $script:Tree.path | Should -BeTrue
        $script:Removed | Should -BeFalse
    }
    It 'retains protections for missing entries: <Kind>' -ForEach @(
        @{ Kind='main' }; @{ Kind='pinned' }; @{ Kind='children' }; @{ Kind='terminal' }
        @{ Kind='tab' }; @{ Kind='active' }; @{ Kind='identity' }; @{ Kind='coverage' }
    ) {
        $script:PathMissing = $true
        switch ($Kind) {
            main { $script:Tree.isMainWorktree = $true }
            pinned { $script:Tree.isPinned = $true }
            children { $script:Tree.childWorktreeIds = @('ds9::/tmp/rom') }
            terminal { $script:TerminalRows = @(@{handle='odo'}) }
            tab { $script:Tabs = @(@{browserPageId='odo'}) }
            active { $script:Activity.isActive = $true }
            identity { $script:Tree.instanceId = 'rom-2' }
            coverage { $script:Truncated = $true }
        }
        $r = Remove-OldOrcaWorktree -Force -Confirm:$false
        $r.DeletedCount | Should -Be 0
        $script:Removed | Should -BeFalse
    }
    It 'renders Spectre without changing WhatIf or the structured pipeline' {
        Mock Initialize-OrcaReapSpectre {}
        Mock Show-OrcaReapSpectre {}
        $r = @(Remove-OldOrcaWorktree -Spectre -WhatIf)
        $r.Count | Should -Be 1
        $r[0].Results[0].Checks.Ready | Should -BeTrue
        $r[0].Results[0].Checks.PSObject.Properties.Name | Should -Not -Contain 'CommitsSafe'
        $r[0].SpectreRendered | Should -BeTrue
        $script:Removed | Should -BeFalse
        Should -Invoke Show-OrcaReapSpectre -Times 1 -Exactly
    }
    It 'uses Spectre by default without requiring the switch' {
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.SpectreRendered | Should -BeTrue
        Should -Invoke Initialize-OrcaReapSpectre -Times 1 -Exactly
        Should -Invoke Show-OrcaReapSpectre -Times 1 -Exactly
        $script:Removed | Should -BeFalse
    }
    It 'falls back to plain output when Spectre cannot be loaded' {
        Mock Initialize-OrcaReapSpectre { throw 'secret-from-quark' }
        $r = @(Remove-OldOrcaWorktree -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue)
        $r.Count | Should -Be 1
        $r[0].SpectreRendered | Should -BeFalse
        $r[0].CandidateCount | Should -Be 1
        "$warnings" | Should -Match 'Spectre unavailable.*plain output'
        "$warnings" | Should -Not -Match 'secret-from-quark'
        Should -Invoke Show-OrcaReapSpectre -Times 0 -Exactly
        $script:Removed | Should -BeFalse
    }
    It 'returns the verified result and warns without retrying when rendering fails' {
        Mock Initialize-OrcaReapSpectre {}
        Mock Show-OrcaReapSpectre { throw 'secret-from-quark' }
        $r = Remove-OldOrcaWorktree -Spectre -WarningVariable warnings -WarningAction SilentlyContinue
        $r.DeletedCount | Should -Be 1
        $r.SpectreRendered | Should -BeFalse
        "$warnings" | Should -Match 'Spectre display failed'
        "$warnings" | Should -Not -Match 'secret-from-quark'
        @($script:Calls | Where-Object { $_ -like 'worktree rm *' }).Count | Should -Be 1
    }
    It 'does not load or render Spectre when explicitly disabled' {
        Mock Initialize-OrcaReapSpectre {}
        Mock Show-OrcaReapSpectre {}
        $r = Remove-OldOrcaWorktree -Spectre:$false -WhatIf
        $r.SpectreRendered | Should -BeFalse
        Should -Invoke Initialize-OrcaReapSpectre -Times 0 -Exactly
        Should -Invoke Show-OrcaReapSpectre -Times 0 -Exactly
    }
    It 'reports an old inactive candidate with WhatIf' {
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.CandidateCount | Should -Be 1
        $r.DeletedCount | Should -Be 0
        $r.Results[0].Status | Should -Be 'Candidate'
        $script:Calls -join '|' | Should -Not -Match 'worktree rm'
    }
    It 'marks every check green only after complete safe eligibility validation' {
        $r = Remove-OldOrcaWorktree -WhatIf
        foreach ($key in @('OldEnough', 'Inactive', 'Unpinned', 'NoChildren', 'Ready')) {
            $r.Results[0].Checks.$key | Should -BeTrue
        }
    }
    It 'shows independent metadata checks even when pinned or parented' {
        $script:Tree.isPinned = $true; $script:Tree.childWorktreeIds = @('ds9::/tmp/rom')
        $r = Remove-OldOrcaWorktree
        $r.Results[0].Checks.OldEnough | Should -BeTrue
        $r.Results[0].Checks.Inactive | Should -BeTrue
        $r.Results[0].Checks.Unpinned | Should -BeFalse
        $r.Results[0].Checks.NoChildren | Should -BeFalse
        $r.Results[0].Checks.PSObject.Properties.Name | Should -Not -Contain 'FilesSafe'
        $r.Results[0].Checks.Ready | Should -BeFalse
        $r.Results[0].Explanation | Should -Match 'Pinned.*1 child worktree'
        $script:Removed | Should -BeFalse
    }
    It 'delegates file protection to Orca without a local Files gate' {
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.Results[0].Checks.Ready | Should -BeTrue
        $r.Results[0].Checks.PSObject.Properties.Name | Should -Not -Contain 'FilesSafe'
        $r.PSObject.Properties.Name | Should -Not -Contain 'NeedsForce'
        $r.Results[0].PSObject.Properties.Name | Should -Not -Contain 'NeedsForce'
        $script:Removed | Should -BeFalse
    }
    It 'does not claim unverified Git registration or partial coverage is ready' {
        $script:GitSafe = $false
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.Results[0].Checks.Ready | Should -BeFalse
        $script:Truncated = $true
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.Results[0].Checks.Ready | Should -BeFalse
    }
    It 'invalidates readiness after failed revalidation or removal' {
        $script:Change = { $script:Activity.liveTerminalCount = 1 }
        $r = Remove-OldOrcaWorktree
        $r.Results[0].Checks.Ready | Should -BeFalse
        $r.Results[0].Checks.Inactive | Should -BeFalse
        New-ReapFixture; $script:RemoveFailure = $true
        $r = Remove-OldOrcaWorktree
        $r.Results[0].Checks.Ready | Should -BeFalse
    }
    It 'adds a folder label without changing the full path or identity' {
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.Results[0].Worktree | Should -Be 'quark'
        $r.Results[0].Path | Should -Be '/tmp/quark'
        $r.Results[0].Id | Should -Be 'ds9::/tmp/quark'
        $r.PSObject.TypeNames | Should -Contain 'RickScripts.OrcaReapSummary'
        $r.Results[0].PSObject.TypeNames | Should -Contain 'RickScripts.OrcaReapResult'
    }
    It 'uses folder names consistently in summary, Results and Spectre: <Folder>' -ForEach @(
        @{ Folder = 'yoda'; Main = $true }
        @{ Folder = 'data-warehouse'; Main = $true }
        @{ Folder = 'dotfiles'; Main = $true }
        @{ Folder = 'worktree'; Main = $false }
    ) {
        Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force
        $script:Tree.path = "/tmp/$Folder"
        $script:Tree.id = "ds9::/tmp/$Folder"
        $script:Tree.branch = 'refs/heads/main'
        $script:Tree.isMainWorktree = $Main
        $script:Activity.path = $script:Tree.path
        $script:Activity.worktreeId = $script:Tree.id
        $r = Remove-OldOrcaWorktree -Spectre:$false -WhatIf
        $r.Results[0].Worktree | Should -Be $Folder
        $r.Results | Out-String -Width 140 | Should -Match ([regex]::Escape($Folder))
        if ($Main) {
            $r | Out-String -Width 140 | Should -Not -Match ([regex]::Escape($Folder))
            @(Get-OrcaReapSpectreRows $r).Count | Should -Be 0
            $r.Results[0].Reason | Should -Be 'ProtectedWorktree'
            $r.Results[0].Checks.Ready | Should -BeFalse
        }
        else {
            $r | Out-String -Width 140 | Should -Match ([regex]::Escape($Folder))
            @(Get-OrcaReapSpectreRows $r)[0].Worktree | Should -Be $Folder
        }
        $script:Removed | Should -BeFalse
    }
    It 'sanitizes folder labels without changing validation metadata' {
        $script:Tree.path = "/tmp/quark`e[red]"
        $r = Remove-OldOrcaWorktree -WhatIf
        $r.Results[0].Worktree | Should -Be 'quark[red]'
        $script:Tree.path | Should -Be "/tmp/quark`e[red]"
        @(Get-OrcaReapSpectreRows $r)[0].Worktree | Should -Be 'quark[[red]]'
    }
    It 'extracts a final folder from either separator and trailing separators: <Path>' -ForEach @(
        @{ Path = '/Users/odo/orca/workspaces/DS9/quark/' }
        @{ Path = 'C:\Orca\workspaces\DS9\quark\' }
    ) {
        $script:Tree.path = $Path
        $script:Tree.branch = $null
        # Metadata is deliberately inconsistent so no native checks/removal can run.
        $r = Remove-OldOrcaWorktree
        $r.Results[0].Worktree | Should -Be 'quark'
        $r.Results[0].Path | Should -Be $Path
    }
    It 'shows a recent age in days in summary, Results and Spectre' {
        Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force
        $script:Tree.lastActivityAt = [DateTimeOffset]::UtcNow.AddDays(-3).AddHours(-1).ToUnixTimeMilliseconds()
        $script:Activity.lastActivityAt = $script:Tree.lastActivityAt
        $r = Remove-OldOrcaWorktree -Spectre:$false -WhatIf
        $r.Results[0].Checks.OldEnough | Should -BeFalse
        $r.Results[0].Checks.AgeDays | Should -Be 3
        $r | Out-String -Width 140 | Should -Match '(?m)^\s*quark\s+3d\s+'
        $r.Results | Out-String -Width 140 | Should -Match '(?m)^\s*quark\s+3d\s+'
        @(Get-OrcaReapSpectreRows $r)[0].Age | Should -Be '[yellow]3d[/]'
        $r.Results[0].Checks.Ready | Should -BeFalse
        $script:Removed | Should -BeFalse
    }
    It 'keeps a checkmark for an old-enough age' {
        Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force
        $r = Remove-OldOrcaWorktree -Spectre:$false -WhatIf
        $r.Results[0].Checks.AgeDays | Should -Be 40
        @(Get-OrcaReapSpectreRows $r)[0].Age | Should -Be '[green]✅[/]'
        $r.Results | Out-String -Width 140 | Should -Match '(?m)^\s*quark\s+✅\s+'
    }
    It 'renders a readable check matrix without leaking full paths into the default display' {
        Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force
        $r = Remove-OldOrcaWorktree -Spectre:$false -WhatIf
        $text = $r | Out-String -Width 140
        $text | Should -Match 'Age.*Idle.*Unpinned.*NoKids.*Ready'
        $text | Should -Match '(?m)^\s*quark\s+✅\s+✅\s+✅\s+✅\s+✅'
        $text | Should -Match 'quark'
        $text | Should -Not -Match '/tmp/quark|ds9::|Commits|Files'
        $r | ConvertTo-Json -Depth 8 | Should -Match '/tmp/quark'
    }
    It 'keeps Orca removal failures visible without retrying or escalating to force' {
        $script:RemoveFailure = $true
        $r = Remove-OldOrcaWorktree -Confirm:$false
        $r.Results[0].Status | Should -Be 'Failed'
        $r.Results[0].Reason | Should -Be 'CommandExit:17'
        $r.Results[0].Checks.Ready | Should -BeFalse
        @($script:Calls | Where-Object { $_ -like 'worktree rm *' }).Count | Should -Be 1
        $script:Calls -join '|' | Should -Not -Match '--force'
    }
    It 'hides protected main worktrees in the summary without weakening safety' {
        Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force
        $script:Tree.isMainWorktree = $true
        $r = Remove-OldOrcaWorktree -Spectre:$false -Force
        $text = $r | Out-String -Width 140
        $text | Should -Not -Match 'quark'
        $r.Results[0].Checks.Ready | Should -BeFalse
        $r.Results.Count | Should -Be 1
        $r.Results[0].IsMainWorktree | Should -BeTrue
        $r.Results[0].Reason | Should -Be 'ProtectedWorktree'
        $r.SkippedCount | Should -Be 1
        $script:Removed | Should -BeFalse
    }
    It 'keeps pinned worktrees visible and protected' {
        Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force
        $script:Tree.isPinned = $true
        $r = Remove-OldOrcaWorktree -Spectre:$false
        $text = $r | Out-String -Width 140
        $text | Should -Match '❌'
        $text | Should -Match 'quark'
        $r.Results[0].IsMainWorktree | Should -BeFalse
        $script:Removed | Should -BeFalse
    }
    It 'does not hide an identity failure merely because a row claims to be main' {
        Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force
        $script:Tree.isMainWorktree = $true; $script:Tree.hostId = 'mordor'
        $r = Remove-OldOrcaWorktree -Spectre:$false
        $r | Out-String -Width 140 | Should -Match 'quark'
        $r.Results[0].Reason | Should -Be 'IdentityUnverified'
    }
    It 'keeps coverage failures visible even when there are no worktree rows' {
        Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force
        $script:BadJson = $true
        $r = Remove-OldOrcaWorktree -Spectre:$false
        $text = $r | Out-String -Width 140
        $text | Should -Match 'INCOMPLETE'
        $text | Should -Match 'MalformedResponse'
        $text | Should -Match '❌'
        $text | Should -Not -Match 'do-not-display'
    }
    It 'defaults to 14 days and allows overriding the threshold from the command line' {
        $script:Tree.lastActivityAt = [DateTimeOffset]::UtcNow.AddDays(-20).ToUnixTimeMilliseconds()
        $script:Activity.lastActivityAt = $script:Tree.lastActivityAt
        $default = Remove-OldOrcaWorktree -WhatIf
        $default.InactiveDays | Should -Be 14
        $default.CandidateCount | Should -Be 1
        $longer = Remove-OldOrcaWorktree -InactiveDays 30 -WhatIf
        $longer.InactiveDays | Should -Be 30
        $longer.CandidateCount | Should -Be 0
        $longer.Results[0].Reason | Should -Be 'RecentlyActive'
        $script:Tree.lastActivityAt = [DateTimeOffset]::UtcNow.AddDays(-10).ToUnixTimeMilliseconds()
        $script:Activity.lastActivityAt = $script:Tree.lastActivityAt
        (Remove-OldOrcaWorktree -WhatIf).CandidateCount | Should -Be 0
        (Remove-OldOrcaWorktree -InactiveDays 7 -WhatIf).CandidateCount | Should -Be 1
        $script:Removed | Should -BeFalse
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
    It 'uses Orca force only for explicit Force while honoring WhatIf' {
        (Remove-OldOrcaWorktree -Force -WhatIf).CandidateCount | Should -Be 1
        $script:Removed | Should -BeFalse
        (Remove-OldOrcaWorktree -Force -Confirm:$false).DeletedCount | Should -Be 1
        @($script:Calls | Where-Object { $_ -like 'worktree rm *' })[0] | Should -Be 'worktree rm --worktree identity:wt2:local:quark-1 --run-hooks --force --json'
    }
    It 'never bypasses Git registration or resource safety with Force' {
        $script:GitSafe = $false
        (Remove-OldOrcaWorktree -Force).CandidateCount | Should -Be 0
        $script:GitSafe = $true; $script:Activity.hasAttachedPty = $true
        (Remove-OldOrcaWorktree -Force).CandidateCount | Should -Be 0
        $script:Removed | Should -BeFalse
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
        $script:NativeReapCommand = (Get-Command Invoke-OrcaReapCommand).ScriptBlock
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
    It 'accepts a clean registered worktree' {
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
    }
    It 'leaves tracked, untracked and ignored files to Orca: <Kind>' -ForEach @(
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
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
    }
    It 'does not inspect local files or request Git status' {
        Mock Invoke-OrcaReapCommand {
            param($Executable, $Arguments, $TimeoutSeconds)
            & $script:NativeReapCommand -Executable $Executable -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
        }
        Mock Invoke-OrcaReapCommand { throw 'Unexpected file scan' } -ParameterFilter { $Executable -eq 'git' -and $Arguments -contains 'status' }
        $exclude = (Invoke-FixtureGit @('-C', $script:Checkout, 'rev-parse', '--git-path', 'info/exclude')).Trim()
        Add-Content $exclude "node_modules/`ndist/`n.env"
        foreach ($folder in @('node_modules', 'dist')) {
            New-Item -ItemType Directory (Join-Path $script:Checkout $folder) | Out-Null
            Set-Content (Join-Path $script:Checkout "$folder/quark.txt") 'Fictional Ferengi build output'
        }
        Set-Content (Join-Path $script:Checkout '.env') 'DS9_LOCATION=promenade'
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
        # Neither new source files nor tracked edits are checked locally.
        Set-Content (Join-Path $script:Checkout 'frodo.ps1') 'Write-Output Shire'
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
        Remove-Item (Join-Path $script:Checkout 'frodo.ps1')
        Add-Content $exclude 'seed.txt'
        Set-Content (Join-Path $script:Checkout 'seed.txt') 'Tracked edits belong to Orca checks'
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
        Should -Invoke Invoke-OrcaReapCommand -Times 0 -Exactly -ParameterFilter { $Executable -eq 'git' -and $Arguments -contains 'status' }
    }
    It 'accepts an unmerged/unpushed commit' {
        Invoke-FixtureGit @('-C', $script:Checkout, 'commit', '--allow-empty', '-m', 'unpublished') | Out-Null
        $script:GitTree.head = (Invoke-FixtureGit @('-C', $script:Checkout, 'rev-parse', 'HEAD')).Trim()
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
    }
    It 'accepts stale remote tracking refs' {
        Invoke-FixtureGit @('-C', $script:Repo, 'commit', '--allow-empty', '-m', 'remote drift') | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'push', 'origin', 'main') | Out-Null
        Invoke-FixtureGit @('-C', $script:Repo, 'update-ref', 'refs/remotes/origin/main', $script:GitTree.head) | Out-Null
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
    }
    It 'does not require access to a remote' {
        Invoke-FixtureGit @('-C', $script:Repo, 'remote', 'set-url', 'origin', (Join-Path $script:GitRoot 'missing.git')) | Out-Null
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
    }
    It 'accepts abandoned commits in the checkout reflog' {
        Invoke-FixtureGit @('-C', $script:Checkout, 'commit', '--allow-empty', '-m', 'abandoned') | Out-Null
        Invoke-FixtureGit @('-C', $script:Checkout, 'reset', '--hard', $script:GitTree.head) | Out-Null
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
    }
    It 'still refuses stashes after removing commit validation' {
        Set-Content (Join-Path $script:Checkout 'seed.txt') 'Bilbo needs this later'
        Invoke-FixtureGit @('-C', $script:Checkout, 'stash', 'push', '-m', 'Bilbo stash') | Out-Null
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw '*GitUnverified*'
    }
    It 'still refuses submodule registrations after removing commit validation' {
        Invoke-FixtureGit @('-C', $script:Checkout, 'update-index', '--add', '--cacheinfo', "160000,$($script:GitTree.head),bag-end") | Out-Null
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw '*GitUnverified*'
    }
    It 'independently refuses the main checkout' {
        $script:GitTree.path = $script:Repo; $script:GitTree.branch = 'refs/heads/main'
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw '*GitUnverified*'
    }
    It 'rejects a locked worktree' {
        Invoke-FixtureGit @('-C', $script:Repo, 'worktree', 'lock', $script:Checkout) | Out-Null
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw '*GitUnverified*'
    }
    It 'accepts missing/local-only base refs while still refusing detached Git state' {
        $script:GitTree.baseRef = 'refs/heads/main'
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
        $script:GitTree.Remove('baseRef')
        (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
        Invoke-FixtureGit @('-C', $script:Checkout, 'checkout', '--detach') | Out-Null
        { Get-OrcaReapGitSafety $script:GitTree } | Should -Throw
    }
    It 'does not allow inherited Git selectors to redirect inspection' {
        $prior = $env:GIT_WORK_TREE
        try {
            $env:GIT_WORK_TREE = $script:Repo
            (Get-OrcaReapGitSafety $script:GitTree).Verified | Should -BeTrue
        }
        finally { $env:GIT_WORK_TREE = $prior }
    }
}

Describe 'Orca reap real path absence checks' {
    It 'proves missing leaf and missing parent paths' {
        Get-OrcaReapPathMissing (Join-Path $TestDrive 'missing-ds9') | Should -BeTrue
        Get-OrcaReapPathMissing (Join-Path $TestDrive 'missing-ds9/worktree') | Should -BeTrue
    }
    It 'does not classify existing directories or files as missing' {
        Get-OrcaReapPathMissing $TestDrive | Should -BeFalse
        $file = Join-Path $TestDrive 'quark.txt'
        Set-Content $file 'Latinum receipts'
        Get-OrcaReapPathMissing $file | Should -BeFalse
        { Get-OrcaReapPathMissing (Join-Path $file 'worktree') } | Should -Throw '*PathUnverified*'
    }
    It 'does not waive a dangling symlink or missing descendant through one' -Skip:$IsWindows {
        $link = Join-Path $TestDrive 'odo-link'
        New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $TestDrive 'absent-odo') | Out-Null
        Get-OrcaReapPathMissing $link | Should -BeFalse
        { Get-OrcaReapPathMissing (Join-Path $link 'worktree') } | Should -Throw '*PathUnverified*'
    }
    It 'does not confuse access denial with a missing path' -Skip:$IsWindows {
        $blocked = Join-Path $TestDrive 'quark-private'
        New-Item -ItemType Directory $blocked | Out-Null
        try {
            & chmod 000 $blocked
            { Get-OrcaReapPathMissing (Join-Path $blocked 'worktree') } | Should -Throw '*PathUnverified*'
        }
        finally { & chmod 700 $blocked }
    }
    It 'rejects relative paths' {
        { Get-OrcaReapPathMissing 'ds9/worktree' } | Should -Throw '*PathUnverified*'
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

Describe 'Orca reap independent metadata checks' {
    BeforeEach { New-ReapFixture }
    It 'keeps unknown metadata unverified instead of inventing a green or a blocker' {
        $script:Tree.Remove('isPinned'); $script:Tree.Remove('childWorktreeIds')
        $script:Activity.Remove('hasAttachedPty')
        $audit = Get-OrcaReapMetadataAssessment $script:Tree $script:Activity 30
        $audit.Checks.Unpinned | Should -BeNullOrEmpty
        $audit.Checks.NoChildren | Should -BeNullOrEmpty
        $audit.Checks.Inactive | Should -BeNullOrEmpty
        $audit.Checks.Ready | Should -BeFalse
        $audit.ProtectionReasons -join '; ' | Should -Match 'Unverified isPinned.*Child-worktree metadata unverified'
    }
    It 'uses a strict age boundary at millisecond precision' {
        $now = [DateTimeOffset]::FromUnixTimeMilliseconds([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        $script:Tree.lastActivityAt = $now.AddDays(-30).ToUnixTimeMilliseconds()
        $audit = Get-OrcaReapMetadataAssessment $script:Tree $script:Activity 30 $now
        $audit.Checks.OldEnough | Should -BeFalse
        $audit.Checks.AgeDays | Should -Be 30
        $script:Tree.lastActivityAt--
        $audit = Get-OrcaReapMetadataAssessment $script:Tree $script:Activity 30 $now
        $audit.Checks.OldEnough | Should -BeTrue
        $audit.Checks.AgeDays | Should -Be 30
    }
    It 'never greens invalid timestamps: <Value>' -ForEach @(
        @{Value=0}; @{Value=-1}; @{Value='yesterday'}; @{Value=[long]::MaxValue}
        @{Value=[DateTimeOffset]::UtcNow.AddDays(1).ToUnixTimeMilliseconds()}
    ) {
        $script:Tree.lastActivityAt = $Value
        $audit = Get-OrcaReapMetadataAssessment $script:Tree $script:Activity 30
        $audit.Checks.OldEnough | Should -BeNullOrEmpty
        $audit.Checks.AgeDays | Should -BeNullOrEmpty
        $row = [pscustomobject]@{Worktree='quark'; Checks=$audit.Checks}
        @(Get-OrcaReapSpectreRows ([pscustomobject]@{Results=@($row)}))[0].Age | Should -Be '[red]❌[/]'
    }
    It 'names the actual protection reason, not every possible protection' {
        $script:Tree.isPinned = $true
        $audit = Get-OrcaReapMetadataAssessment $script:Tree $script:Activity 30
        $audit.ProtectionReasons | Should -Be @('Pinned')
        $script:Tree.isPinned = $false; $script:Tree.childWorktreeIds = @('ds9::/tmp/rom', 'ds9::/tmp/nog')
        $audit = Get-OrcaReapMetadataAssessment $script:Tree $script:Activity 30
        $audit.ProtectionReasons | Should -Be @('Has 2 child worktree(s)')
    }
}

Describe 'Orca reap Spectre presentation' {
    BeforeAll { . "$PSScriptRoot/../Common/OrcaReapDisplay.ps1" }
    It 'renders a real Spectre table without polluting the success stream' -Skip:(-not (Get-Module -ListAvailable PwshSpectreConsole)) {
        Initialize-OrcaReapSpectre
        $summary = [pscustomobject]@{
            InactiveDays=30; Force=$true; CoverageComplete=$false; CoverageReason='RuntimeChanged'
            CandidateCount=0; DeletedCount=0; SkippedCount=1; FailedCount=0
            Results=@([pscustomobject]@{Worktree='quark[red]'; IsMainWorktree=$false; Status='Skipped'; Reason='ActiveResources'; Explanation='Literal [green]text[/]'; Checks=@{OldEnough=$true}})
        }
        Mock 'PwshSpectreConsole\Write-SpectreHost' {}
        @(Show-OrcaReapSpectre $summary).Count | Should -Be 0
        Should -Invoke 'PwshSpectreConsole\Write-SpectreHost' -Times 0 -Exactly
        $summary.Results=@()
        @(Show-OrcaReapSpectre $summary).Count | Should -Be 0
    }
    It 'escapes markup and terminal controls while preserving independent checks' {
        $row = [pscustomobject]@{
            Worktree = "quark[red]`e[2J"; Explanation = '[green]Not trusted[/]'
            IsMainWorktree = $false; Status = 'Skipped'; Reason = 'ActiveResources'
            Checks = @{OldEnough=$true; Inactive=$false; Unpinned=$null; NoChildren=$true; Ready=$false}
        }
        $cells = @(Get-OrcaReapSpectreRows ([pscustomobject]@{Results=@($row)}))
        $cells.Count | Should -Be 1
        $cells[0].Worktree | Should -Be 'quark[[red]][[2J'
        $cells[0].Reason | Should -Be '[[green]]Not trusted[[/]]'
        $cells[0].Age | Should -Be '[green]✅[/]'
        $cells[0].Idle | Should -Be '[red]❌[/]'
        $cells[0].Unpinned | Should -Be '[red]❌[/]'
        $cells[0].PSObject.Properties.Name | Should -Not -Contain 'Files'
        $cells[0].PSObject.Properties.Name | Should -Not -Contain 'Commits'
    }
    It 'hides only protected main rows while keeping failures and alphabetical ordering' {
        $rows = @(
            [pscustomobject]@{Worktree='main'; IsMainWorktree=$true; Status='Skipped'; Reason='ProtectedWorktree'; Checks=@{}},
            [pscustomobject]@{Worktree='quark'; IsMainWorktree=$false; Status='Skipped'; Reason='ProtectedWorktree'; Checks=@{}},
            [pscustomobject]@{Worktree='main-failed'; IsMainWorktree=$true; Status='Failed'; Reason='RuntimeChanged'; Checks=@{}}
        )
        @(Get-OrcaReapSpectreRows ([pscustomobject]@{Results=$rows})).Worktree | Should -Be @('main-failed','quark')
    }
}
