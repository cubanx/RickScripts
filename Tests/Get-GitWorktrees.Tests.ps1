BeforeAll {
    . "$PSScriptRoot/../Functions/Get-GitWorktrees.ps1"

    $tempRoot = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
    $script:Root = Join-Path $tempRoot 'rickscripts-gw-worktrees-test'
    $script:LinkedWorktree = Join-Path $script:Root 'linked-worktree'
    $script:RealRepository = Join-Path $script:Root 'real-repo'

    Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $script:RealRepository -Force | Out-Null
    New-Item -ItemType Directory -Path $script:LinkedWorktree -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:RealRepository '.git') 'worktrees') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:LinkedWorktree '.git') -Value "gitdir: $script:RealRepository/.git/worktrees/linked-worktree"

    function git {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

        if ($Args[0] -eq '-C') {
            $path = $Args[1]
            $command = $Args[2..($Args.Length - 1)] -join ' '
            if ($path -eq $script:LinkedWorktree -and $command -eq 'rev-parse --path-format=absolute --git-common-dir') {
                $global:LASTEXITCODE = 0
                return "$script:RealRepository/.git/worktrees/linked-worktree"
            }
            if ($path -eq $script:RealRepository -and $command -eq 'worktree list --porcelain') {
                $global:LASTEXITCODE = 0
                return @(
                    "worktree $script:LinkedWorktree"
                    'HEAD deadbeef'
                    'detached'
                    ''
                    "worktree $script:Root/secondary-worktree"
                    'HEAD cafebabe'
                    'branch refs/heads/main'
                )
            }
        }

        $global:LASTEXITCODE = 0
        return @()
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-GitWorktrees' {
    It 'discovers registered worktrees from a linked worktree root' {
        $worktrees = Get-GitWorktrees -Roots @($script:Root)

        $worktrees | Should -Not -BeNullOrEmpty
        $worktrees[0].RepositoryRoot | Should -Be $script:RealRepository
        $worktrees.Count | Should -Be 2
    }
}
