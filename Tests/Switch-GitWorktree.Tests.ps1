$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Functions/Switch-GitWorktree.ps1"

$script:FzfInput = @()
$script:FzfSelection = $null
$script:PushLocations = @()

function Get-GitWorktrees {
    return @(
        [PSCustomObject]@{
            RepositoryName = "main-repo"
            RepositoryRoot = "/tmp/repo-main"
            Path           = "/tmp/repo-main-worktree"
            Branch         = "main"
            Head           = "abcde12345"
            IsBare         = $false
            IsDetached     = $false
        },
        [PSCustomObject]@{
            RepositoryName = "feature-repo"
            RepositoryRoot = "/tmp/repo-main"
            Path           = "/tmp/repo-feature"
            Branch         = $null
            Head           = "f00dbabe1234567890"
            IsBare         = $false
            IsDetached     = $true
        },
        [PSCustomObject]@{
            RepositoryName = "ignored-bare"
            RepositoryRoot = "/tmp/repo-main"
            Path           = "/tmp/repo-bare"
            Branch         = $null
            Head           = "1234567890"
            IsBare         = $true
            IsDetached     = $false
        }
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
            $line = if ($inputItem.PSObject.Properties["Display"]) {
                $inputItem.Display
            } else {
                $inputItem
            }

            $script:FzfInput += $line
            if (-not $script:FzfSelection) {
                $script:FzfSelection = $line
            }
        }
    }

    end {
        if ($script:FzfSelection) {
            return $script:FzfSelection
        }
    }
}

function Push-Location {
    param(
        [string]$LiteralPath
    )

    $script:PushLocations += $LiteralPath
}

$script:Output = Switch-GitWorktree -Roots @("/tmp") | Out-String

if ($script:FzfInput.Count -ne 2) {
    throw "Expected 2 selectable worktrees (branch + detached), found $($script:FzfInput.Count)."
}

if (-not ($script:FzfInput -match '/tmp/repo-feature')) {
    throw "Expected detached worktree to be selectable."
}

if ($script:FzfInput -match '/tmp/repo-bare') {
    throw "Expected bare worktree to be hidden from picker."
}

if (-not ($script:FzfInput -match '\(detached f00dbab\)')) {
    throw "Expected detached worktree label with short HEAD."
}

if (-not ($script:Output -match '1 bare Git worktree hidden\.')) {
    throw "Expected bare hidden count message."
}
