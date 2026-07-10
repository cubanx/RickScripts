$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Common/Get-StaleGitWorktreeAssessment.ps1"

$script:GitCallLog = @()

function git {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Args
    )

    $path = $null
    $commandParts = @()
    for ($i = 0; $i -lt $Args.Length; $i++) {
        if ($Args[$i] -eq "-C" -and ($i + 1) -lt $Args.Length) {
            $path = $Args[$i + 1]
            $i++
            continue
        }

        $commandParts += $Args[$i]
    }

    $command = $commandParts -join ' '
    $script:GitCallLog += "$path|$command"

    if ($path -eq "/tmp/stale" -and $command -like 'status --porcelain=v1 --untracked-files=all') {
        $global:LASTEXITCODE = 0
        return @()
    }

    if ($path -eq "/tmp/stale" -and $command -like 'log --oneline HEAD --not --branches --remotes --tags') {
        $global:LASTEXITCODE = 0
        return @()
    }

    if ($path -eq "/tmp/stale" -and $command -like 'for-each-ref --contains HEAD --format=*') {
        $global:LASTEXITCODE = 0
        return @("main", "origin/main")
    }

    if ($path -eq "/tmp/stale" -and $command -like 'rev-parse HEAD') {
        $global:LASTEXITCODE = 0
        return "abcdef1234567890"
    }

    if ($path -eq "/tmp/stale" -and $command -like 'rev-parse --short HEAD') {
        $global:LASTEXITCODE = 0
        return "abcdef1"
    }

    if ($path -eq "/tmp/dirty" -and $command -like 'status --porcelain=v1 --untracked-files=all') {
        $global:LASTEXITCODE = 0
        return @(" M file.txt")
    }

    if ($path -eq "/tmp/unique" -and $command -like 'status --porcelain=v1 --untracked-files=all') {
        $global:LASTEXITCODE = 0
        return @()
    }

    if ($path -eq "/tmp/unique" -and $command -like 'log --oneline HEAD --not --branches --remotes --tags') {
        $global:LASTEXITCODE = 0
        return @("deadbeef unique")
    }

    if ($path -eq "/tmp/unique" -and $command -like 'rev-parse HEAD') {
        $global:LASTEXITCODE = 0
        return "cafebabe12345678"
    }

    if ($path -eq "/tmp/unique" -and $command -like 'rev-parse --short HEAD') {
        $global:LASTEXITCODE = 0
        return "cafebab"
    }

    $global:LASTEXITCODE = 0
    return @()
}

$worktrees = @(
    [PSCustomObject]@{
        Path           = "/tmp/stale"
        RepositoryRoot = "/tmp/repo"
        IsDetached     = $true
        IsBare         = $false
    },
    [PSCustomObject]@{
        Path           = "/tmp/stay"
        RepositoryRoot = "/tmp/repo"
        IsDetached     = $false
        IsBare         = $false
    },
    [PSCustomObject]@{
        Path           = "/tmp/dirty"
        RepositoryRoot = "/tmp/repo2"
        IsDetached     = $true
        IsBare         = $false
    },
    [PSCustomObject]@{
        Path           = "/tmp/unique"
        RepositoryRoot = "/tmp/repo3"
        IsDetached     = $true
        IsBare         = $false
    }
)

$staleAssessment = Get-StaleGitWorktreeAssessment -Worktree $worktrees[0] -AllWorktrees $worktrees
if (-not $staleAssessment.IsStale) {
    throw "Expected detached clean worktree with shared refs and an owner to be stale."
}

if ($staleAssessment.OwnerPath -ne "/tmp/stay") {
    throw "Expected owner path to be '/tmp/stay'."
}

if ($staleAssessment.ShortHead -ne "abcdef1") {
    throw "Expected short HEAD to resolve."
}

$attachedWorktree = $worktrees[1]
$attachedAssessment = Get-StaleGitWorktreeAssessment -Worktree $attachedWorktree -AllWorktrees $worktrees
if ($attachedAssessment.IsStale) {
    throw "Expected non-detached worktree to be non-stale."
}

$dirtyWorktree = $worktrees[2]
$dirtyAssessment = Get-StaleGitWorktreeAssessment -Worktree $dirtyWorktree -AllWorktrees $worktrees
if ($dirtyAssessment.IsStale) {
    throw "Expected dirty detached worktree to be non-stale."
}

$uniqueWorktree = $worktrees[3]
$uniqueAssessment = Get-StaleGitWorktreeAssessment -Worktree $uniqueWorktree -AllWorktrees $worktrees
if ($uniqueAssessment.IsStale) {
    throw "Expected detached worktree with unique commits to be non-stale."
}

