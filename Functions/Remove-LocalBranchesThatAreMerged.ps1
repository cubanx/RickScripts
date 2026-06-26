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
            [bool]$CanDelete,
            [string]$LastCommitDate,
            [string]$RemoteState,
            [string]$MainDelta
        )

        [PSCustomObject]@{
            Branch = $Branch
            Status = $Status
            DeleteFlag = $DeleteFlag
            LastCommitDate = $LastCommitDate
            RemoteState = $RemoteState
            MainDelta = $MainDelta
            Reason = $Reason
            Tier = $Tier
            CanDelete = $CanDelete
        }
    }

    function Get-BranchMetadata {
        param(
            [string]$Branch,
            [string]$MainBranch
        )

        $lastCommitRaw = git log -1 --format=%cI $Branch 2>$null
        $lastCommitDate = 'unknown'
        if ($lastCommitRaw) {
            try {
                $lastCommitDate = ([datetimeoffset]::Parse($lastCommitRaw)).LocalDateTime.ToString('yyyy-MM-dd')
            }
            catch {
                $lastCommitDate = ($lastCommitRaw -split 'T')[0]
            }
        }

        $upstreamInfo = git for-each-ref --format='%(upstream:short)|%(upstream:track)' "refs/heads/$Branch" 2>$null | Select-Object -First 1
        $remoteState = 'never-pushed'
        if ($upstreamInfo) {
            $upstreamParts = $upstreamInfo -split '\|', 2
            if ($upstreamParts[0]) {
                $remoteState = if ($upstreamParts.Count -gt 1 -and $upstreamParts[1] -match '\[gone\]') { 'gone' } else { 'exists' }
            }
        }

        $aheadCount = 0
        $behindCount = 0
        $revCounts = git rev-list --left-right --count "$MainBranch...$Branch" 2>$null
        if ($revCounts) {
            $parts = @($revCounts -split '\s+' | Where-Object { $_ -ne '' })
            if ($parts.Count -ge 2) {
                $behindCount = [int]$parts[0]
                $aheadCount = [int]$parts[1]
            }
        }

        [PSCustomObject]@{
            LastCommitDate = $lastCommitDate
            RemoteState = $remoteState
            MainDelta = '+{0}/-{1}' -f $aheadCount, $behindCount
            AheadCount = $aheadCount
            BehindCount = $behindCount
        }
    }

    function Get-ManualReviewStatus {
        param(
            [object]$Metadata
        )

        if ($Metadata.RemoteState -eq 'gone') {
            return 'stale'
        }

        if ($Metadata.AheadCount -gt 0) {
            return 'risky'
        }

        return 'unknown'
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

    function Get-OpenPullRequestsByBranch {
        param(
            [string[]]$Branches
        )

        $matches = @{}
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            return $matches
        }

        $ghOutput = gh pr list --state open --limit 200 --json number,headRefName,isDraft 2>$null
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

        $selectableAssessments = @($Assessments | Where-Object { $_.CanDelete -and $_.Status -ne 'auto' })
        if (-not $selectableAssessments) {
            return @()
        }

        $branchWidth = [Math]::Max(6, (($selectableAssessments | ForEach-Object { $_.Branch.Length } | Measure-Object -Maximum).Maximum))
        $statusWidth = [Math]::Max(6, (($selectableAssessments | ForEach-Object { $_.Status.Length } | Measure-Object -Maximum).Maximum))
        $deleteWidth = [Math]::Max(2, (($selectableAssessments | ForEach-Object { $_.DeleteFlag.Length } | Measure-Object -Maximum).Maximum))
        $dateWidth = [Math]::Max(10, (($selectableAssessments | ForEach-Object { $_.LastCommitDate.Length } | Measure-Object -Maximum).Maximum))
        $remoteWidth = [Math]::Max(6, (($selectableAssessments | ForEach-Object { $_.RemoteState.Length } | Measure-Object -Maximum).Maximum))
        $deltaWidth = [Math]::Max(5, (($selectableAssessments | ForEach-Object { $_.MainDelta.Length } | Measure-Object -Maximum).Maximum))
        $header = "{0}  {1}  {2}  {3}  {4}  {5}  {6}" -f `
            'Branch'.PadRight($branchWidth), `
            'Status'.PadRight($statusWidth), `
            'Del'.PadRight($deleteWidth), `
            'Last commit'.PadRight($dateWidth), `
            'Remote'.PadRight($remoteWidth), `
            'Delta'.PadRight($deltaWidth), `
            'Reason'

        $selectedLines = $selectableAssessments |
            ForEach-Object {
                $deleteLabel = if ($_.DeleteFlag) { $_.DeleteFlag } else { '--' }
                "{0}  {1}  {2}  {3}  {4}  {5}  {6}" -f `
                    $_.Branch.PadRight($branchWidth), `
                    $_.Status.PadRight($statusWidth), `
                    $deleteLabel.PadRight($deleteWidth), `
                    $_.LastCommitDate.PadRight($dateWidth), `
                    $_.RemoteState.PadRight($remoteWidth), `
                    $_.MainDelta.PadRight($deltaWidth), `
                    $_.Reason
            } |
            fzf --multi --ansi --height 50% --reverse --header $header --prompt 'Inspect branches / pick candidates to delete: '

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

        return @($selectableAssessments | Where-Object { $selectedByBranch.ContainsKey($_.Branch) })
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
    $openPullRequestsByBranch = Get-OpenPullRequestsByBranch -Branches $LOCAL_BRANCHES
    $branchMetadata = @{}
    foreach ($branch in $LOCAL_BRANCHES) {
        $branchMetadata[$branch] = Get-BranchMetadata -Branch $branch -MainBranch $MAIN_BRANCH
    }

    $strictCandidates = @()
    $softCandidates = @()
    $nonCandidates = @()

    foreach ($branch in $LOCAL_BRANCHES) {
        $metadata = $branchMetadata[$branch]
        if ($openPullRequestsByBranch.ContainsKey($branch)) {
            $openPullRequest = $openPullRequestsByBranch[$branch] | Sort-Object number -Descending | Select-Object -First 1
            $prState = if ($openPullRequest.isDraft) { 'draft' } else { 'open' }
            $nonCandidates += New-BranchAssessment `
                -Branch $branch `
                -Status 'pr-open' `
                -DeleteFlag '' `
                -Reason ('{0} PR #{1} is still active' -f $prState, $openPullRequest.number) `
                -Tier 'Protected' `
                -CanDelete $false `
                -LastCommitDate $metadata.LastCommitDate `
                -RemoteState $metadata.RemoteState `
                -MainDelta $metadata.MainDelta
            continue
        }

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

        $status = Get-ManualReviewStatus -Metadata $metadata
        $reason = "not integrated into $MAIN_BRANCH"
        if ($metadata.RemoteState -eq 'gone') {
            $reason = "remote gone, but branch is not proven integrated into $MAIN_BRANCH"
        }
        elseif ($metadata.AheadCount -gt 0) {
            $reason = "branch has unique commits not in $MAIN_BRANCH"
        }

        $nonCandidates += New-BranchAssessment `
            -Branch $branch `
            -Status $status `
            -DeleteFlag '' `
            -Reason $reason `
            -Tier 'Manual' `
            -CanDelete $false `
            -LastCommitDate $metadata.LastCommitDate `
            -RemoteState $metadata.RemoteState `
            -MainDelta $metadata.MainDelta
    }

    foreach ($candidate in $strictCandidates) {
        Remove-BranchCandidate -Candidate $candidate
    }

    $allAssessments = @(
        $strictCandidates | ForEach-Object {
            $metadata = $branchMetadata[$_.Branch]
            New-BranchAssessment `
                -Branch $_.Branch `
                -Status 'auto' `
                -DeleteFlag $_.DeleteFlag `
                -Reason $_.Reason `
                -Tier $_.Tier `
                -CanDelete $true `
                -LastCommitDate $metadata.LastCommitDate `
                -RemoteState $metadata.RemoteState `
                -MainDelta $metadata.MainDelta
        }
        $softCandidates | ForEach-Object {
            $metadata = $branchMetadata[$_.Branch]
            New-BranchAssessment `
                -Branch $_.Branch `
                -Status 'candidate' `
                -DeleteFlag $_.DeleteFlag `
                -Reason $_.Reason `
                -Tier $_.Tier `
                -CanDelete $true `
                -LastCommitDate $metadata.LastCommitDate `
                -RemoteState $metadata.RemoteState `
                -MainDelta $metadata.MainDelta
        }
        $nonCandidates
    ) | Sort-Object Branch

    if ($allAssessments) {
        Write-Output ''
        Write-Output 'Branch review:'
        $branchWidth = [Math]::Max(6, (($allAssessments | ForEach-Object { $_.Branch.Length } | Measure-Object -Maximum).Maximum))
        $statusWidth = [Math]::Max(6, (($allAssessments | ForEach-Object { $_.Status.Length } | Measure-Object -Maximum).Maximum))
        $deleteWidth = [Math]::Max(2, (($allAssessments | ForEach-Object { if ($_.DeleteFlag) { $_.DeleteFlag.Length } else { 2 } } | Measure-Object -Maximum).Maximum))
        $dateWidth = [Math]::Max(10, (($allAssessments | ForEach-Object { $_.LastCommitDate.Length } | Measure-Object -Maximum).Maximum))
        $remoteWidth = [Math]::Max(6, (($allAssessments | ForEach-Object { $_.RemoteState.Length } | Measure-Object -Maximum).Maximum))
        $deltaWidth = [Math]::Max(5, (($allAssessments | ForEach-Object { $_.MainDelta.Length } | Measure-Object -Maximum).Maximum))
        Write-Output ('  {0}  {1}  {2}  {3}  {4}  {5}  {6}' -f `
            'Branch'.PadRight($branchWidth), `
            'Status'.PadRight($statusWidth), `
            'Del'.PadRight($deleteWidth), `
            'Last commit'.PadRight($dateWidth), `
            'Remote'.PadRight($remoteWidth), `
            'Delta'.PadRight($deltaWidth), `
            'Reason')
        $allAssessments |
            ForEach-Object {
                $deleteLabel = if ($_.DeleteFlag) { $_.DeleteFlag } else { '--' }
                Write-Output ('  {0}  {1}  {2}  {3}  {4}  {5}  {6}' -f `
                    $_.Branch.PadRight($branchWidth), `
                    $_.Status.PadRight($statusWidth), `
                    $deleteLabel.PadRight($deleteWidth), `
                    $_.LastCommitDate.PadRight($dateWidth), `
                    $_.RemoteState.PadRight($remoteWidth), `
                    $_.MainDelta.PadRight($deltaWidth), `
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
