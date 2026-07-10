$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Functions/Get-GitWorktrees.ps1"

$tempRoot = if ($env:TEMP) { $env:TEMP } else { "/tmp" }
$root = Join-Path $tempRoot "rickscripts-gw-worktrees-test"
$linkedWorktree = Join-Path $root "linked-worktree"
$realRepository = Join-Path $root "real-repo"
$linkedWorktreeGitDir = Join-Path $linkedWorktree ".git"

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $realRepository -Force | Out-Null
New-Item -ItemType Directory -Path $linkedWorktree -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path (Join-Path $realRepository ".git") "worktrees") -Force | Out-Null

Set-Content -LiteralPath $linkedWorktreeGitDir -Value "gitdir: $realRepository/.git/worktrees/linked-worktree"

function git {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Args
    )

    if ($Args[0] -eq "-C") {
        $path = $Args[1]
        $command = ($Args[2..($Args.Length - 1)] -join ' ')

        if ($path -eq $linkedWorktree -and $command -eq "rev-parse --path-format=absolute --git-common-dir") {
            $global:LASTEXITCODE = 0
            return "$realRepository/.git/worktrees/linked-worktree"
        }

        if ($path -eq $realRepository -and $command -eq "worktree list --porcelain") {
            $global:LASTEXITCODE = 0
            return @(
                "worktree $linkedWorktree",
                "HEAD deadbeef",
                "detached",
                "",
                "worktree $root/secondary-worktree",
                "HEAD cafebabe",
                "branch refs/heads/main"
            )
        }
    }

    $global:LASTEXITCODE = 0
    return @()
}

$worktrees = Get-GitWorktrees -Roots @($root)

if (-not $worktrees) {
    throw "Expected worktrees to be discovered from a linked worktree root."
}

if ($worktrees[0].RepositoryRoot -ne $realRepository) {
    throw "Expected repository root to be resolved to the real repository."
}

if ($worktrees.Count -ne 2) {
    throw "Expected 2 porcelain worktrees, found $($worktrees.Count)."
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
