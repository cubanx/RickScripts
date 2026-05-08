function Remove-StaleCodexWorktree {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$WorktreeRoot = "~/.codex/worktrees",
        [switch]$Force
    )

    function Get-FirstOtherWorktreePath {
        param(
            [string]$CandidatePath
        )

        $worktreeLines = git -C $CandidatePath worktree list --porcelain 2>$null
        $candidateFullPath = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

        foreach ($line in $worktreeLines) {
            if (-not $line.StartsWith("worktree ")) {
                continue
            }

            $worktreePath = $line.Substring("worktree ".Length)
            $worktreeFullPath = [System.IO.Path]::GetFullPath($worktreePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $pathComparison = [System.StringComparison]::Ordinal
            if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
                $pathComparison = [System.StringComparison]::OrdinalIgnoreCase
            }

            if (-not [string]::Equals($worktreeFullPath, $candidateFullPath, $pathComparison)) {
                return $worktreePath
            }
        }

        return $null
    }

    function New-StaleCodexWorktreeCandidate {
        param(
            [string]$HexFolder,
            [string]$ProjectName,
            [string]$Path
        )

        $branchName = git -C $Path branch --show-current 2>$null
        if ($branchName) {
            Write-Debug "Skipping '$Path' because it is on branch '$($branchName.Trim())'"
            return $null
        }

        $status = git -C $Path status --porcelain=v1 --untracked-files=all 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Debug "Skipping '$Path' because git status failed"
            return $null
        }

        if ($status) {
            Write-Debug "Skipping '$Path' because it has local changes"
            return $null
        }

        $uniqueCommits = git -C $Path log --oneline HEAD --not --branches --remotes --tags 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Debug "Skipping '$Path' because unique commit check failed"
            return $null
        }

        if ($uniqueCommits) {
            Write-Debug "Skipping '$Path' because it has commits not reachable from branches, remotes, or tags"
            return $null
        }

        $containingRefs = @(git -C $Path for-each-ref --contains HEAD --format='%(refname:short)' refs/heads refs/remotes refs/tags 2>$null)
        if ($LASTEXITCODE -ne 0) {
            Write-Debug "Skipping '$Path' because ref reachability check failed"
            return $null
        }

        if (-not $containingRefs) {
            Write-Debug "Skipping '$Path' because HEAD is not reachable from a branch, remote, or tag"
            return $null
        }

        $ownerPath = Get-FirstOtherWorktreePath -CandidatePath $Path
        if (-not $ownerPath) {
            Write-Debug "Skipping '$Path' because no owning worktree was found"
            return $null
        }

        $head = git -C $Path rev-parse HEAD 2>$null
        $shortHead = git -C $Path rev-parse --short HEAD 2>$null
        if (-not $head -or -not $shortHead) {
            Write-Debug "Skipping '$Path' because HEAD could not be resolved"
            return $null
        }

        [PSCustomObject]@{
            HexFolder   = $HexFolder
            ProjectName = $ProjectName
            Path        = $Path
            OwnerPath   = $ownerPath
            Head        = $head.Trim()
            ShortHead   = $shortHead.Trim()
            Refs        = @($containingRefs | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            Display     = $null
        }
    }

    function Show-StaleCodexWorktreeList {
        param(
            [object[]]$Candidates
        )

        if (-not $Candidates) {
            return @()
        }

        $projectWidth = [Math]::Max(7, (($Candidates | ForEach-Object { $_.ProjectName.Length } | Measure-Object -Maximum).Maximum))
        $headWidth = [Math]::Max(4, (($Candidates | ForEach-Object { $_.ShortHead.Length } | Measure-Object -Maximum).Maximum))

        Write-Output "Stale Codex worktrees safe to remove:"
        foreach ($candidate in $Candidates) {
            $refSummary = ($candidate.Refs | Select-Object -First 2) -join ", "
            if ($candidate.Refs.Count -gt 2) {
                $refSummary = "$refSummary, ..."
            }

            Write-Output ("{0}  {1}  {2}  {3}" -f $candidate.ProjectName.PadRight($projectWidth), $candidate.ShortHead.PadRight($headWidth), $refSummary, $candidate.Path)
        }
    }

    function Remove-StaleCodexWorktreeCandidate {
        param(
            [object]$Candidate
        )

        $action = "git worktree remove $($Candidate.Path)"
        if (-not $PSCmdlet.ShouldProcess($Candidate.Path, $action)) {
            return
        }

        Write-Output ("Removing stale Codex worktree <{0}> at {1}" -f $Candidate.ProjectName, $Candidate.Path)
        git -C $Candidate.OwnerPath worktree remove $Candidate.Path
    }

    $resolvedWorktreeRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorktreeRoot)
    Write-Debug "Scanning Codex worktrees under '$resolvedWorktreeRoot'"

    if (-not (Test-Path -LiteralPath $resolvedWorktreeRoot -PathType Container)) {
        Write-Error "Codex worktree root not found: $resolvedWorktreeRoot"
        return
    }

    $candidates = @(Get-ChildItem -LiteralPath $resolvedWorktreeRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $hexFolder = $_
            Write-Debug "Inspecting worktree folder '$($hexFolder.FullName)'"

            $repoFolder = Get-ChildItem -LiteralPath $hexFolder.FullName -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name |
                Select-Object -First 1

            if (-not $repoFolder) {
                Write-Debug "Skipping '$($hexFolder.FullName)' because it does not contain a project folder"
                return
            }

            $gitMetadataPath = Join-Path $repoFolder.FullName ".git"
            if (-not (Test-Path -LiteralPath $gitMetadataPath)) {
                Write-Debug "Skipping '$($repoFolder.FullName)' because '.git' was not found"
                return
            }

            New-StaleCodexWorktreeCandidate -HexFolder $hexFolder.Name -ProjectName $repoFolder.Name -Path $repoFolder.FullName
        } |
        Where-Object { $_ })

    if (-not $candidates) {
        Write-Output "No stale Codex worktrees found in $resolvedWorktreeRoot"
        return
    }

    Show-StaleCodexWorktreeList -Candidates $candidates

    if (-not $Force -and -not $WhatIfPreference) {
        $prompt = "Remove $($candidates.Count) stale Codex worktree"
        if ($candidates.Count -ne 1) {
            $prompt = "$prompt" + "s"
        }

        if (-not $PSCmdlet.ShouldContinue($prompt, "Confirm stale Codex worktree cleanup")) {
            Write-Debug "Stale Codex worktree cleanup was not confirmed"
            return
        }
    }

    foreach ($candidate in $candidates) {
        Remove-StaleCodexWorktreeCandidate -Candidate $candidate
    }
}

Set-Alias rcw Remove-StaleCodexWorktree
