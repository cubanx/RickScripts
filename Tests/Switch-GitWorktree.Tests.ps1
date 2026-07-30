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
        },
        [PSCustomObject]@{
            RepositoryName = "crisp-brains"
            RepositoryRoot = "/tmp/crisp-brains"
            Path           = "/tmp/crisp-brains-detached"
            Branch         = $null
            Head           = "deadbeef1234567890"
            IsBare         = $false
            IsDetached     = $true
        },
        [PSCustomObject]@{
            RepositoryName = "estate-planner"
            RepositoryRoot = "/tmp/estate-planner"
            Path           = "/tmp/estate-planner-feature"
            Branch         = "feature"
            Head           = "decafbad1234567890"
            IsBare         = $false
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

$script:DefaultOutput = Switch-GitWorktree -Roots @("/tmp") | Out-String

if ($script:FzfInput.Count -ne 1) {
    throw "Expected 1 selectable branch worktree by default, found $($script:FzfInput.Count)."
}

if ($script:FzfInput -match '/tmp/repo-feature') {
    throw "Expected detached worktree to be hidden by default."
}

if (-not ($script:FzfInput -match '/tmp/repo-main-worktree')) {
    throw "Expected branch worktree to be selectable by default."
}

if ($script:FzfInput -match '/tmp/repo-bare') {
    throw "Expected bare worktree to be hidden from picker."
}

if ($script:FzfInput -match '/tmp/estate-planner-feature') {
    throw "Expected excluded estate-planner worktree to be hidden."
}

if (-not ($script:DefaultOutput -match '1 bare Git worktree hidden\.')) {
    throw "Expected bare hidden count message."
}

$script:DetachedOutput = Switch-GitWorktree -Roots @("/tmp") -DetachedOnly | Out-String

if ($script:FzfInput.Count -ne 1) {
    throw "Expected 1 selectable detached worktree, found $($script:FzfInput.Count)."
}

if (-not ($script:FzfInput -match '/tmp/repo-feature')) {
    throw "Expected detached worktree to be selectable with -DetachedOnly."
}

if ($script:FzfInput -match '/tmp/repo-main-worktree') {
    throw "Expected branch worktree to be hidden with -DetachedOnly."
}

if ($script:FzfInput -match '/tmp/crisp-brains-detached') {
    throw "Expected excluded crisp-brains worktree to be hidden."
}

if (-not ($script:FzfInput -match '\(detached f00dbab\)')) {
    throw "Expected detached worktree label with short HEAD."
}

if (-not ($script:DetachedOutput -match '1 bare Git worktree hidden\.')) {
    throw "Expected bare hidden count message."
}
