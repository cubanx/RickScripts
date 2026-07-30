BeforeAll {
    . "$PSScriptRoot/../Functions/Switch-GitWorktree.ps1"

    function Get-GitWorktrees {
        return @(
            [PSCustomObject]@{ RepositoryName = 'main-repo'; RepositoryRoot = '/tmp/repo-main'; Path = '/tmp/repo-main-worktree'; Branch = 'main'; Head = 'abcde12345'; IsBare = $false; IsDetached = $false }
            [PSCustomObject]@{ RepositoryName = 'feature-repo'; RepositoryRoot = '/tmp/repo-main'; Path = '/tmp/repo-feature'; Branch = $null; Head = 'f00dbabe1234567890'; IsBare = $false; IsDetached = $true }
            [PSCustomObject]@{ RepositoryName = 'ignored-bare'; RepositoryRoot = '/tmp/repo-main'; Path = '/tmp/repo-bare'; Branch = $null; Head = '1234567890'; IsBare = $true; IsDetached = $false }
            [PSCustomObject]@{ RepositoryName = 'crisp-brains'; RepositoryRoot = '/tmp/crisp-brains'; Path = '/tmp/crisp-brains-detached'; Branch = $null; Head = 'deadbeef1234567890'; IsBare = $false; IsDetached = $true }
            [PSCustomObject]@{ RepositoryName = 'estate-planner'; RepositoryRoot = '/tmp/estate-planner'; Path = '/tmp/estate-planner-feature'; Branch = 'feature'; Head = 'decafbad1234567890'; IsBare = $false; IsDetached = $false }
        )
    }

    if (Get-Alias fzf -ErrorAction SilentlyContinue) {
        Remove-Item Alias:fzf -Force
    }

    function fzf {
        begin {
            $script:FzfInput = @()
            $script:FzfSelection = $null
        }
        process {
            foreach ($inputItem in $input) {
                $line = if ($inputItem.PSObject.Properties['Display']) { $inputItem.Display } else { $inputItem }
                $script:FzfInput += $line
                if (-not $script:FzfSelection) { $script:FzfSelection = $line }
            }
        }
        end {
            if ($script:FzfSelection) { return $script:FzfSelection }
        }
    }

    function Push-Location {
        param([string]$LiteralPath)
        $script:PushLocations += $LiteralPath
    }
}

Describe 'Switch-GitWorktree' {
    BeforeEach {
        $script:FzfInput = @()
        $script:FzfSelection = $null
        $script:PushLocations = @()
    }

    It 'shows only selectable branch worktrees by default' {
        $output = Switch-GitWorktree -Roots @('/tmp') | Out-String

        $script:FzfInput.Count | Should -Be 1
        $script:FzfInput | Should -Match '/tmp/repo-main-worktree'
        $script:FzfInput | Should -Not -Match '/tmp/repo-feature'
        $script:FzfInput | Should -Not -Match '/tmp/repo-bare'
        $script:FzfInput | Should -Not -Match '/tmp/estate-planner-feature'
        $output | Should -Match '1 bare Git worktree hidden\.'
    }

    It 'shows only eligible detached worktrees with DetachedOnly' {
        $output = Switch-GitWorktree -Roots @('/tmp') -DetachedOnly | Out-String

        $script:FzfInput.Count | Should -Be 1
        $script:FzfInput | Should -Match '/tmp/repo-feature'
        $script:FzfInput | Should -Not -Match '/tmp/repo-main-worktree'
        $script:FzfInput | Should -Not -Match '/tmp/crisp-brains-detached'
        $script:FzfInput | Should -Match '\(detached f00dbab\)'
        $output | Should -Match '1 bare Git worktree hidden\.'
    }
}
