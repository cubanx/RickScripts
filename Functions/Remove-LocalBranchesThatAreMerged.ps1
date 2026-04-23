function Remove-LocalBranchesThatAreMerged {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    function New-DeleteCandidate {
        param(
            [string]$Branch,
            [string]$DeleteFlag,
            [string]$Reason,
            [string]$Tier
        )

        [PSCustomObject]@{
            Branch = $Branch
            DeleteFlag = $DeleteFlag
            Reason = $Reason
            Tier = $Tier
        }
    }

    function New-BranchAssessment {
        param(
            [string]$Branch,
            [string]$Status,
            [string]$DeleteFlag,
            [string]$Reason,
            [string]$Tier,
            [bool]$CanDelete
        )

        [PSCustomObject]@{
            Branch = $Branch
            Status = $Status
            DeleteFlag = $DeleteFlag
            Reason = $Reason
            Tier = $Tier
            CanDelete = $CanDelete
        }
    }

    function Get-ExactMergedPullRequestMatches {
        param(
            [string[]]$Branches,
            [string]$MainBranch
        )

        $matches = @{}
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            return $matches
        }

        $ghOutput = gh pr list --state merged --limit 200 --json number,headRefName,headRefOid,baseRefName,mergedAt 2>$null
        if (-not $ghOutput) {
            return $matches
        }

        try {
            $pullRequests = $ghOutput | ConvertFrom-Json
        }
        catch {
            return $matches
        }

        $branchSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($branch in $Branches) {
            [void]$branchSet.Add($branch)
        }

        foreach ($pullRequest in $pullRequests) {
            if ($pullRequest.baseRefName -ne $MainBranch) {
                continue
            }

            if (-not $branchSet.Contains($pullRequest.headRefName)) {
                continue
            }

            if (-not $matches.ContainsKey($pullRequest.headRefName)) {
                $matches[$pullRequest.headRefName] = @()
            }

            $matches[$pullRequest.headRefName] += $pullRequest
        }

        return $matches
    }

    function Show-CandidatePicker {
        param(
            [object[]]$Assessments
        )

        if (-not $Assessments) {
            return @()
        }

        $branchWidth = [Math]::Max(6, (($Assessments | ForEach-Object { $_.Branch.Length } | Measure-Object -Maximum).Maximum))
        $statusWidth = [Math]::Max(6, (($Assessments | ForEach-Object { $_.Status.Length } | Measure-Object -Maximum).Maximum))
        $deleteWidth = [Math]::Max(2, (($Assessments | ForEach-Object { $_.DeleteFlag.Length } | Measure-Object -Maximum).Maximum))

        $selectedLines = $Assessments |
            ForEach-Object {
                $deleteLabel = if ($_.DeleteFlag) { $_.DeleteFlag } else { '--' }
                "{0}  {1}  {2}  {3}" -f `
                    $_.Branch.PadRight($branchWidth), `
                    $_.Status.PadRight($statusWidth), `
                    $deleteLabel.PadRight($deleteWidth), `
                    $_.Reason
            } |
            fzf --multi --ansi --height 50% --reverse --prompt 'Inspect branches / pick candidates to delete: '

        if (-not $selectedLines) {
            return @()
        }

        $selectedByBranch = @{}
        foreach ($line in @($selectedLines)) {
            $branch = $line.Substring(0, $branchWidth).Trim()
            if (-not $branch) {
                continue
            }

            $selectedByBranch[$branch] = $true
        }

        return @($Assessments | Where-Object { $selectedByBranch.ContainsKey($_.Branch) })
    }

    function Remove-BranchCandidate {
        param(
            [object]$Candidate
        )

        $action = 'git branch {0} {1} ({2})' -f $Candidate.DeleteFlag, $Candidate.Branch, $Candidate.Reason
        if (-not $PSCmdlet.ShouldProcess($Candidate.Branch, $action)) {
            return
        }

        Write-Output ('Removing branch <{0}> with git branch {1} ({2})' -f $Candidate.Branch, $Candidate.DeleteFlag, $Candidate.Reason)
        if ($Candidate.DeleteFlag -ceq '-d') {
            git branch -d $Candidate.Branch
            return
        }

        git branch -D $Candidate.Branch
    }

    function Test-StrictIntegration {
        param(
            [string]$Branch,
            [string]$MainBranch
        )

        $mergedBranches = git branch --format='%(refname:short)' --merged $MainBranch
        if ($mergedBranches -contains $Branch) {
            return New-DeleteCandidate -Branch $Branch -DeleteFlag '-d' -Reason "merged into $MainBranch" -Tier 'Strict'
        }

        $tempWorktreeRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'rickscripts-rlb'
        $tempWorktreePath = Join-Path $tempWorktreeRoot ([System.Guid]::NewGuid().ToString())

        New-Item -ItemType Directory -Path $tempWorktreeRoot -Force -WhatIf:$false | Out-Null

        try {
            git worktree add --quiet --detach $tempWorktreePath $MainBranch | Out-Null

            git -C $tempWorktreePath merge --squash --no-commit $Branch 2>$null | Out-Null
            $hasChanges = [bool](git -C $tempWorktreePath status --porcelain)
            git -C $tempWorktreePath reset --hard HEAD | Out-Null

            if (-not $hasChanges) {
                return New-DeleteCandidate -Branch $Branch -DeleteFlag '-D' -Reason "squash-equivalent no-op against $MainBranch" -Tier 'Strict'
            }

            return $null
        }
        finally {
            git worktree remove --force $tempWorktreePath 2>$null | Out-Null
            if (Test-Path $tempWorktreePath) {
                Remove-Item -Path $tempWorktreePath -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false
            }
        }
    }

    function Get-SoftCandidate {
        param(
            [string]$Branch,
            [string]$MainBranch,
            [hashtable]$MergedPullRequestsByBranch
        )

        $reasons = @()
        $branchSha = git rev-parse $Branch 2>$null
        $cherryOutput = @(git cherry $MainBranch $Branch 2>$null)

        if ($cherryOutput.Count -gt 0 -and -not ($cherryOutput | Where-Object { $_ -like '+ *' })) {
            $reasons += "patch-equivalent to $MainBranch"
        }

        if ($MergedPullRequestsByBranch.ContainsKey($Branch)) {
            $matchingPullRequest = $MergedPullRequestsByBranch[$Branch] |
                Where-Object { $_.headRefOid -eq $branchSha } |
                Sort-Object mergedAt -Descending |
                Select-Object -First 1

            if ($matchingPullRequest) {
                $reasons += 'merged PR #{0} matched branch head' -f $matchingPullRequest.number
            }
        }

        if (-not $reasons) {
            return $null
        }

        return New-DeleteCandidate -Branch $Branch -DeleteFlag '-D' -Reason ($reasons -join '; ') -Tier 'Candidate'
    }

    # Fetch the latest updates from the remote repository, including pruning deleted branches
    git fetch --all --prune

    # Get the name of the main branch
    $MAIN_BRANCH = git remote show origin | Select-String -Pattern 'HEAD branch' | ForEach-Object { ($_ -split ': ')[1].Trim() }

    $CURRENT_BRANCH = git branch --show-current
    $LOCAL_BRANCHES = @(git branch --format='%(refname:short)' |
        Where-Object { $_ -and $_ -ne $MAIN_BRANCH -and $_ -ne $CURRENT_BRANCH })

    $mergedPullRequestsByBranch = Get-ExactMergedPullRequestMatches -Branches $LOCAL_BRANCHES -MainBranch $MAIN_BRANCH

    $strictCandidates = @()
    $softCandidates = @()
    $nonCandidates = @()

    foreach ($branch in $LOCAL_BRANCHES) {
        $strictCandidate = Test-StrictIntegration -Branch $branch -MainBranch $MAIN_BRANCH
        if ($strictCandidate) {
            $strictCandidates += $strictCandidate
            continue
        }

        $softCandidate = Get-SoftCandidate -Branch $branch -MainBranch $MAIN_BRANCH -MergedPullRequestsByBranch $mergedPullRequestsByBranch
        if ($softCandidate) {
            $softCandidates += $softCandidate
            continue
        }

        $nonCandidates += New-BranchAssessment -Branch $branch -Status 'skip' -DeleteFlag '' -Reason "not integrated into $MAIN_BRANCH" -Tier 'None' -CanDelete $false
    }

    foreach ($candidate in $strictCandidates) {
        Remove-BranchCandidate -Candidate $candidate
    }

    $allAssessments = @(
        $strictCandidates | ForEach-Object {
            New-BranchAssessment -Branch $_.Branch -Status 'auto' -DeleteFlag $_.DeleteFlag -Reason $_.Reason -Tier $_.Tier -CanDelete $true
        }
        $softCandidates | ForEach-Object {
            New-BranchAssessment -Branch $_.Branch -Status 'candidate' -DeleteFlag $_.DeleteFlag -Reason $_.Reason -Tier $_.Tier -CanDelete $true
        }
        $nonCandidates
    ) | Sort-Object Branch

    if ($allAssessments) {
        Write-Output ''
        Write-Output 'Branch review:'
        $branchWidth = [Math]::Max(6, (($allAssessments | ForEach-Object { $_.Branch.Length } | Measure-Object -Maximum).Maximum))
        $statusWidth = [Math]::Max(6, (($allAssessments | ForEach-Object { $_.Status.Length } | Measure-Object -Maximum).Maximum))
        $deleteWidth = [Math]::Max(2, (($allAssessments | ForEach-Object { if ($_.DeleteFlag) { $_.DeleteFlag.Length } else { 2 } } | Measure-Object -Maximum).Maximum))
        $allAssessments |
            ForEach-Object {
                $deleteLabel = if ($_.DeleteFlag) { $_.DeleteFlag } else { '--' }
                Write-Output ('  {0}  {1}  {2}  {3}' -f `
                    $_.Branch.PadRight($branchWidth), `
                    $_.Status.PadRight($statusWidth), `
                    $deleteLabel.PadRight($deleteWidth), `
                    $_.Reason)
            }

        $selectedAssessments = Show-CandidatePicker -Assessments $allAssessments
        foreach ($assessment in $selectedAssessments) {
            if (-not $assessment.CanDelete) {
                Write-Output ('Skipping branch <{0}> because it is not a deletion candidate ({1})' -f $assessment.Branch, $assessment.Reason)
                continue
            }

            if ($assessment.Status -eq 'auto') {
                continue
            }

            Remove-BranchCandidate -Candidate (New-DeleteCandidate -Branch $assessment.Branch -DeleteFlag $assessment.DeleteFlag -Reason $assessment.Reason -Tier $assessment.Tier)
        }
    }

    # Prune remote-tracking branches that no longer exist on the remote
    git remote prune origin
}

Set-Alias rlb Remove-LocalBranchesThatAreMerged
