function Remove-StaleCodexWorktree {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$WorktreeRoot = "~/.codex/worktrees",
        [switch]$Force
    )

    function New-StaleCodexWorktreeCandidate {
        param(
            [object]$Worktree,
            [object]$Assessment
        )

        if (-not $Assessment.IsStale) {
            Write-Debug "Skipping '$($Worktree.Path)' because $($Assessment.Reason)"
            return $null
        }

        $projectName = Split-Path -Leaf $Worktree.Path
        $hexFolder = Split-Path -Leaf (Split-Path -Parent $Worktree.Path)

        [PSCustomObject]@{
            HexFolder   = $HexFolder
            ProjectName = $projectName
            Path        = $Worktree.Path
            OwnerPath   = $Assessment.OwnerPath
            Head        = $Assessment.Head
            ShortHead   = $Assessment.ShortHead
            Refs        = $Assessment.Refs
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

    $allWorktrees = Get-GitWorktrees -Roots @($WorktreeRoot)
    $candidates = @($allWorktrees | ForEach-Object {
        $assessment = Get-StaleGitWorktreeAssessment -Worktree $_ -AllWorktrees $allWorktrees
        New-StaleCodexWorktreeCandidate -Worktree $_ -Assessment $assessment
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
