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
            if (Test-Path -LiteralPath $gitPath -PathType Container) {
                Write-Debug "Found Git repository root '$Root'"
                $Root
                return
            }

            $gitCommonDir = git -C $Root rev-parse --path-format=absolute --git-common-dir 2>$null
            if ($LASTEXITCODE -eq 0 -and $gitCommonDir) {
                $gitCommonDir = Get-NormalizedPath -Path $gitCommonDir
                $commonDirSegments = $gitCommonDir -split "[\\/]"
                $gitDirIndex = [Array]::IndexOf($commonDirSegments, ".git")
                if (
                    $gitDirIndex -ge 0 -and
                    $gitDirIndex -lt ($commonDirSegments.Length - 1) -and
                    $commonDirSegments[$gitDirIndex + 1] -eq "worktrees"
                ) {
                    $gitCommonDir = ($commonDirSegments[0..$gitDirIndex] -join [System.IO.Path]::DirectorySeparatorChar)
                }

                $repositoryRoot = Split-Path -Parent $gitCommonDir
                Write-Debug "Resolved linked-worktree root '$Root' to repository '$repositoryRoot'"
                Get-NormalizedPath -Path $repositoryRoot
                return
            }
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

    function Add-CurrentGitRepositoryRoot {
        param(
            [System.Collections.Generic.HashSet[string]]$RepositoryRoots,
            [string[]]$ScanRoots
        )

        $currentRepositoryRoot = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $currentRepositoryRoot) {
            return $false
        }

        $currentRepositoryRoot = Get-NormalizedPath -Path $currentRepositoryRoot
        $isUnderScanRoot = $false
        foreach ($scanRoot in $ScanRoots) {
            if (
                [string]::Equals($currentRepositoryRoot, $scanRoot, $pathComparison) -or
                $currentRepositoryRoot.StartsWith($scanRoot + [System.IO.Path]::DirectorySeparatorChar, $pathComparison)
            ) {
                $isUnderScanRoot = $true
                break
            }
        }

        if (-not $isUnderScanRoot) {
            return $false
        }

        return $RepositoryRoots.Add($currentRepositoryRoot)
    }

    function Save-RepositoryRootCache {
        param(
            [System.Collections.Generic.HashSet[string]]$RepositoryRoots,
            [string]$CachePath
        )

        New-Item -ItemType Directory -Path (Split-Path -Parent $CachePath) -Force | Out-Null
        @($RepositoryRoots | Sort-Object) | ConvertTo-Json | Set-Content -LiteralPath $CachePath -Encoding UTF8
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

        if (Add-CurrentGitRepositoryRoot -RepositoryRoots $repositoryRoots -ScanRoots $resolvedRoots) {
            Save-RepositoryRootCache -RepositoryRoots $repositoryRoots -CachePath $cachePath
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
            Save-RepositoryRootCache -RepositoryRoots $repositoryRoots -CachePath $cachePath
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
