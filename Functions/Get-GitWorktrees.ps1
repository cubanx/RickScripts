function Get-GitWorktrees {
    [CmdletBinding()]
    param(
        [string[]]$Roots = @("~/code"),
        [switch]$RefreshCache
    )

    function Get-NormalizedPath {
        param(
            [string]$Path
        )

        return [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }

    function Find-GitRepositoryRoot {
        param(
            [string]$Root
        )

        $gitPath = Join-Path $Root ".git"
        if (Test-Path -LiteralPath $gitPath) {
            Write-Debug "Found Git repository root '$Root'"
            $Root
            return
        }

        Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                Find-GitRepositoryRoot -Root $_.FullName
            }
    }

    function ConvertFrom-GitWorktreePorcelain {
        param(
            [string]$RepositoryRoot,
            [string[]]$Lines
        )

        $current = $null
        foreach ($line in ($Lines + "")) {
            if (-not $line) {
                if ($current) {
                    $branch = $null
                    if ($current.BranchRef -and $current.BranchRef.StartsWith("refs/heads/")) {
                        $branch = $current.BranchRef.Substring("refs/heads/".Length)
                    }

                    [PSCustomObject]@{
                        RepositoryName = Split-Path -Leaf $RepositoryRoot
                        RepositoryRoot = $RepositoryRoot
                        Path           = $current.Path
                        Branch         = $branch
                        BranchRef      = $current.BranchRef
                        Head           = $current.Head
                        IsBare         = $current.IsBare
                        IsDetached     = $current.IsDetached -or -not $branch
                    }

                    $current = $null
                }

                continue
            }

            if ($line.StartsWith("worktree ")) {
                $current = [PSCustomObject]@{
                    Path       = $line.Substring("worktree ".Length)
                    Head       = $null
                    BranchRef  = $null
                    IsBare     = $false
                    IsDetached = $false
                }
                continue
            }

            if (-not $current) {
                continue
            }

            if ($line.StartsWith("HEAD ")) {
                $current.Head = $line.Substring("HEAD ".Length)
            }
            elseif ($line.StartsWith("branch ")) {
                $current.BranchRef = $line.Substring("branch ".Length)
            }
            elseif ($line -eq "bare") {
                $current.IsBare = $true
            }
            elseif ($line -eq "detached") {
                $current.IsDetached = $true
            }
        }
    }

    function Get-GitWorktreeEntries {
        param(
            [string]$RepositoryRoot
        )

        $worktreeLines = git -C $RepositoryRoot worktree list --porcelain 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $worktreeLines) {
            Write-Debug "Skipping '$RepositoryRoot' because git worktree list failed"
            return @()
        }

        return @(ConvertFrom-GitWorktreePorcelain -RepositoryRoot $RepositoryRoot -Lines $worktreeLines)
    }

    $pathComparison = [System.StringComparison]::Ordinal
    $pathComparer = [System.StringComparer]::Ordinal
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        $pathComparison = [System.StringComparison]::OrdinalIgnoreCase
        $pathComparer = [System.StringComparer]::OrdinalIgnoreCase
    }

    $resolvedRoots = @(
        foreach ($root in $Roots) {
            $resolvedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($root)
            Get-NormalizedPath -Path $resolvedRoot
        }
    )
    $defaultRoot = Get-NormalizedPath -Path $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("~/code")
    $useCache = $resolvedRoots.Count -eq 1 -and [string]::Equals($resolvedRoots[0], $defaultRoot, $pathComparison)
    $cachePath = Join-Path $HOME ".cache/RickScripts/git-repo-roots.json"
    $repositoryRoots = [System.Collections.Generic.HashSet[string]]::new($pathComparer)

    if ($useCache -and -not $RefreshCache -and (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        foreach ($repositoryRoot in @(Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json)) {
            if (Test-Path -LiteralPath $repositoryRoot -PathType Container) {
                [void]$repositoryRoots.Add((Get-NormalizedPath -Path $repositoryRoot))
            }
        }
    }

    if ($repositoryRoots.Count -eq 0) {
        foreach ($resolvedRoot in $resolvedRoots) {
            if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
                Write-Warning "Git repository scan root not found: $resolvedRoot"
                continue
            }

            Find-GitRepositoryRoot -Root $resolvedRoot |
                ForEach-Object {
                    [void]$repositoryRoots.Add((Get-NormalizedPath -Path $_))
                }
        }

        if ($useCache) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $cachePath) -Force | Out-Null
            @($repositoryRoots | Sort-Object) | ConvertTo-Json | Set-Content -LiteralPath $cachePath -Encoding UTF8
        }
    }

    $seenWorktreePaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    foreach ($repositoryRoot in ($repositoryRoots | Sort-Object)) {
        $worktreeMetadataPath = Join-Path (Join-Path $repositoryRoot ".git") "worktrees"
        if (-not (Test-Path -LiteralPath $worktreeMetadataPath -PathType Container)) {
            continue
        }

        Get-GitWorktreeEntries -RepositoryRoot $repositoryRoot |
            Where-Object {
                $normalizedWorktreePath = Get-NormalizedPath -Path $_.Path
                if ($seenWorktreePaths.Contains($normalizedWorktreePath)) {
                    $false
                }
                else {
                    [void]$seenWorktreePaths.Add($normalizedWorktreePath)
                    $true
                }
            }
    }
}
