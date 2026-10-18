BeforeAll {
    . "$PSScriptRoot/../Common/OrcaReap.ps1"
    . "$PSScriptRoot/../Common/OrcaReapBranches.ps1"
    . "$PSScriptRoot/../Common/OrcaReapDisplay.ps1"
    . "$PSScriptRoot/../Functions/Remove-OrcaWorktrees.ps1"
    $script:realBranchCommand = (Get-Command Invoke-OrcaReapCommand).ScriptBlock
    function Invoke-BranchGit {
        param([string[]]$Arguments)
        Invoke-OrcaReapCommand git $Arguments 10
    }
}

Describe 'Merged Orca branch cleanup with disposable origin' {
    BeforeEach {
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $origin = "$repo-origin.git"
        $checkout = "$repo-quark"
        $null = Invoke-BranchGit @('init', '-b', 'main', $repo)
        $null = Invoke-BranchGit @('-C', $repo, 'config', 'user.name', 'Quark')
        $null = Invoke-BranchGit @('-C', $repo, 'config', 'user.email', 'quark@example.invalid')
        $null = Invoke-BranchGit @('-C', $repo, 'config', 'commit.gpgSign', 'false')
        $null = Invoke-BranchGit @('-C', $repo, 'commit', '--allow-empty', '-m', 'seed')
        $null = Invoke-BranchGit @('clone', '--bare', $repo, $origin)
        $null = Invoke-BranchGit @('-C', $repo, 'remote', 'add', 'origin', $origin)
        $null = Invoke-BranchGit @('-C', $repo, 'fetch', 'origin')
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'add', '-b', 'quark', $checkout)
        $tree = @{path=$checkout; branch='refs/heads/quark'; baseRef='refs/remotes/origin/main'; head=(Invoke-BranchGit @('-C', $checkout, 'rev-parse', 'HEAD')).Trim()}
    }
    It 'deletes merged local and origin branches after removal' {
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        $plan = Get-OrcaReapBranchPlan $tree
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        $result = Remove-OrcaReapBranches $plan
        $result.Local | Should -Be 'Deleted'
        $result.Origin | Should -Be 'Deleted'
        (Invoke-BranchGit @('-C', $repo, 'branch', '--list', 'quark')).Trim() | Should -BeNullOrEmpty
        (Invoke-BranchGit @('-C', $repo, 'ls-remote', '--heads', 'origin', 'refs/heads/quark')).Trim() | Should -BeNullOrEmpty
    }
    It 'handles branches already removed by Orca and absent on origin' {
        $plan = Get-OrcaReapBranchPlan $tree
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        $null = Invoke-BranchGit @('-C', $repo, 'branch', '-d', 'quark')
        $result = Remove-OrcaReapBranches $plan
        $result.Local | Should -Be 'Absent'
        $result.Origin | Should -Be 'Absent'
    }
    It 'removes a selected dirty locked checkout and its unmerged branches through the cmdlet' {
        $null = Invoke-BranchGit @('-C', $checkout, 'commit', '--allow-empty', '-m', 'unmerged')
        $tree.head = (Invoke-BranchGit @('-C', $checkout, 'rev-parse', 'HEAD')).Trim()
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        Set-Content (Join-Path $checkout 'latinum.txt') 'Untracked cargo'
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'lock', $checkout)
        $script:pickRepo = $repo; $script:pickCheckout = $checkout; $script:pickRemoved = $false
        $script:pickTree = @{
            id="ds9::$checkout"; path=$checkout; repoId='ds9'; hostId='local'; instanceId='quark-1'
            identity=@{key='wt2:local:quark-1'; executionHostId='local'; instanceId='quark-1'}
            isMainWorktree=$false; isPinned=$true; isBare=$false; childWorktreeIds=@('rom')
            head=$tree.head; branch=$tree.branch; baseRef=$tree.baseRef
            lastActivityAt=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        }
        function fzf { process { $_ } end { $global:LASTEXITCODE = 0 } }
        Mock Initialize-OrcaReapSpectre {}
        Mock Show-OrcaReapSpectre {}
        Mock Invoke-OrcaReapCommand {
            param($Executable, $Arguments, $TimeoutSeconds)
            & $script:realBranchCommand $Executable $Arguments $TimeoutSeconds
        }
        Mock Invoke-OrcaReapCommand {
            param($Arguments)
            $command = $Arguments -join ' '
            $result = switch -Wildcard ($command) {
                'worktree list *' { @{worktrees=@(if(-not $script:pickRemoved){$script:pickTree}); totalCount=$(if($script:pickRemoved){0}else{1}); truncated=$false; hostScope=@{hostIds=@('local'); omittedHostIds=@()}} }
                'worktree show *' { @{worktree=$script:pickTree} }
                'worktree rm *' {
                    $Arguments | Should -Contain '--force'
                    $Arguments | Should -Contain '--allow-failed-archive-hook'
                    $null = & $script:realBranchCommand git @('-C', $script:pickRepo, 'worktree', 'remove', '--force', $script:pickCheckout) 10
                    $script:pickRemoved = $true
                    @{removed=$true}
                }
                default { throw "Unexpected fixture command: $command" }
            }
            @{ok=$true; result=$result; _meta=@{runtimeId='ds9'}} | ConvertTo-Json -Depth 12 -Compress
        } -ParameterFilter { $Executable -eq 'orca-pick-fixture' }
        $result = Remove-OrcaWorktrees -Pick -OrcaCommand 'orca-pick-fixture' -Confirm:$false
        $result.DeletedCount | Should -Be 1
        $result.Results[0].BranchCleanup.Local | Should -Be 'Deleted'
        $result.Results[0].BranchCleanup.Origin | Should -Be 'Deleted'
        Test-Path $checkout | Should -BeFalse
        (Invoke-BranchGit @('-C', $repo, 'branch', '--list', 'quark')).Trim() | Should -BeNullOrEmpty
        (Invoke-BranchGit @('-C', $repo, 'ls-remote', '--heads', 'origin', 'refs/heads/quark')).Trim() | Should -BeNullOrEmpty
    }
    It 'force deletes captured unmerged branches without a usable base' {
        $null = Invoke-BranchGit @('-C', $checkout, 'commit', '--allow-empty', '-m', 'unmerged latinum')
        $tree.head = (Invoke-BranchGit @('-C', $checkout, 'rev-parse', 'HEAD')).Trim()
        $tree.baseRef = 'refs/remotes/origin/missing'
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        $plan = Get-OrcaReapBranchPlan $tree -Force
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        $result = Remove-OrcaReapBranches $plan -Force
        $result.Local | Should -Be 'Deleted'
        $result.Origin | Should -Be 'Deleted'
        (Invoke-BranchGit @('-C', $repo, 'branch', '--list', 'quark')).Trim() | Should -BeNullOrEmpty
        (Invoke-BranchGit @('-C', $repo, 'ls-remote', '--heads', 'origin', 'refs/heads/quark')).Trim() | Should -BeNullOrEmpty
    }
    It 'does not force delete an origin branch changed since selection' {
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        $plan = Get-OrcaReapBranchPlan $tree -Force
        $null = Invoke-BranchGit @('-C', $checkout, 'commit', '--allow-empty', '-m', 'new remote work')
        $newTip = (Invoke-BranchGit @('-C', $checkout, 'rev-parse', 'HEAD')).Trim()
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        $result = Remove-OrcaReapBranches $plan -Force
        $result.Origin | Should -Be 'Retained'
        $result.OriginReason | Should -Be 'BranchChanged'
        (Invoke-BranchGit @('--git-dir', $origin, 'rev-parse', 'refs/heads/quark')).Trim() | Should -Be $newTip
    }
    It 'can force delete a local branch with no origin' {
        $null = Invoke-BranchGit @('-C', $repo, 'remote', 'remove', 'origin')
        $plan = Get-OrcaReapBranchPlan $tree -Force
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        $result = Remove-OrcaReapBranches $plan -Force
        $result.Local | Should -Be 'Deleted'
        $result.Origin | Should -Be 'Absent'
    }
    It 'retains unmerged commits locally and on origin' {
        $null = Invoke-BranchGit @('-C', $checkout, 'commit', '--allow-empty', '-m', 'unmerged')
        $tree.head = (Invoke-BranchGit @('-C', $checkout, 'rev-parse', 'HEAD')).Trim()
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        $plan = Get-OrcaReapBranchPlan $tree
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        $result = Remove-OrcaReapBranches $plan
        $result.Local | Should -Be 'Retained'
        $result.Origin | Should -Be 'Retained'
    }
    It 'does not trust a stale origin base when the server has moved backwards' {
        $seed = $tree.head
        $null = Invoke-BranchGit @('-C', $checkout, 'commit', '--allow-empty', '-m', 'latinum')
        $tree.head = (Invoke-BranchGit @('-C', $checkout, 'rev-parse', 'HEAD')).Trim()
        $null = Invoke-BranchGit @('-C', $repo, 'merge', '--ff-only', 'quark')
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'main', 'quark')
        $null = Invoke-BranchGit @('-C', $repo, 'fetch', 'origin')
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', "${seed}:refs/heads/main", '--force')
        $plan = Get-OrcaReapBranchPlan $tree
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        (Remove-OrcaReapBranches $plan).Origin | Should -Be 'Retained'
    }
    It 'retains a local branch that moved after capture' {
        $plan = Get-OrcaReapBranchPlan $tree
        $null = Invoke-BranchGit @('-C', $checkout, 'commit', '--allow-empty', '-m', 'changed')
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        (Remove-OrcaReapBranches $plan).Local | Should -Be 'Retained'
    }
    It 'can recover Git identity for an absent checkout through its inventoried main checkout' {
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        Remove-Item $checkout -Recurse -Force
        $plan = Get-OrcaReapBranchPlan $tree -RepositoryPath $repo
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'prune')
        $result = Remove-OrcaReapBranches $plan
        $result.Local | Should -Be 'Deleted'
        $result.Origin | Should -Be 'Deleted'
    }
    It 'refuses a distinct push destination' {
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        $null = Invoke-BranchGit @('-C', $repo, 'remote', 'set-url', '--push', 'origin', "$repo-other.git")
        $plan = Get-OrcaReapBranchPlan $tree
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        $result = Remove-OrcaReapBranches $plan
        $result.Origin | Should -Be 'Failed'
        $result.OriginReason | Should -Be 'OriginTargetUnverified'
        (Invoke-BranchGit @('-C', $repo, 'ls-remote', '--heads', 'origin', 'refs/heads/quark')).Trim() | Should -Not -BeNullOrEmpty
    }
    It 'retains a branch still checked out elsewhere' {
        $plan = Get-OrcaReapBranchPlan $tree
        (Remove-OrcaReapBranches $plan).Local | Should -Be 'Failed'
        (Invoke-BranchGit @('-C', $checkout, 'symbolic-ref', 'HEAD')).Trim() | Should -Be 'refs/heads/quark'
    }
    It 'does not delete an origin branch that advances during deletion' {
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        $plan = Get-OrcaReapBranchPlan $tree
        $null = Invoke-BranchGit @('-C', $checkout, 'commit', '--allow-empty', '-m', 'concurrent tip')
        $script:concurrentTip = (Invoke-BranchGit @('-C', $checkout, 'rev-parse', 'HEAD')).Trim()
        $script:originPath = $origin
        $script:nativeBranchCommand = (Get-Command Invoke-OrcaReapCommand).ScriptBlock
        $script:branchPushes = 0
        Mock Invoke-OrcaReapCommand {
            param($Executable, $Arguments, $TimeoutSeconds)
            & $script:nativeBranchCommand $Executable $Arguments $TimeoutSeconds
        }
        Mock Invoke-OrcaReapCommand {
            param($Executable, $Arguments, $TimeoutSeconds)
            $script:branchPushes++
            $null = & $script:nativeBranchCommand git @('--git-dir', $script:originPath, 'update-ref', 'refs/heads/quark', $script:concurrentTip) 10
            & $script:nativeBranchCommand $Executable $Arguments $TimeoutSeconds
        } -ParameterFilter { $Executable -eq 'git' -and $Arguments -contains 'push' }
        # Copy the new object to origin without changing quark, so the concurrent
        # update above is a real ref advance, not a simulated Git error.
        $null = Invoke-BranchGit @('-C', $repo, 'fetch', '--no-write-fetch-head', $checkout, 'quark')
        $null = & $script:nativeBranchCommand git @('-C', $repo, 'push', 'origin', "$($script:concurrentTip):refs/heads/rom") 10
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        $result = Remove-OrcaReapBranches $plan
        $result.Origin | Should -Be 'Failed'
        $script:branchPushes | Should -Be 1
        (Invoke-BranchGit @('--git-dir', $origin, 'rev-parse', 'refs/heads/quark')).Trim() | Should -Be $script:concurrentTip
    }
    It 'protects the server default branch even with a nonstandard name' {
        $null = Invoke-BranchGit @('-C', $repo, 'push', 'origin', 'quark')
        $null = Invoke-BranchGit @('--git-dir', $origin, 'symbolic-ref', 'HEAD', 'refs/heads/quark')
        $plan = Get-OrcaReapBranchPlan $tree
        $null = Invoke-BranchGit @('-C', $repo, 'worktree', 'remove', $checkout)
        $result = Remove-OrcaReapBranches $plan
        $result.OriginReason | Should -Be 'BranchProtected'
        (Invoke-BranchGit @('--git-dir', $origin, 'rev-parse', 'HEAD')).Trim() | Should -Be $tree.head
    }
    It 'protects base and conventional primary branches' {
        $tree.branch = 'refs/heads/main'
        { Get-OrcaReapBranchPlan $tree } | Should -Throw '*BranchProtected*'
        $tree.branch = 'refs/heads/quark'; $tree.baseRef = 'refs/remotes/origin/quark'
        { Get-OrcaReapBranchPlan $tree } | Should -Throw '*BranchProtected*'
    }
}
