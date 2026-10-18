function Remove-OrcaWorktrees {
    <#
    .SYNOPSIS
    Removes old, verified-inactive local Orca worktrees conservatively.
    .DESCRIPTION
    Default age is strictly greater than 14 days since lastActivityAt (not a sleep timestamp).
    By default, only eligible candidates are shown, then deletion requires confirmation.
    -All shows every worktree and never offers or performs deletion. Use -WhatIf to preview.
    -Confirm:$false explicitly skips the deletion prompt. Confirmed missing
    directories are deregistered without an age/Git gate, with a conditional archive-hook
    waiver. Existing directories never receive that waiver. -Force passes --force to Orca;
    it never bypasses identity/resource checks.
    After verified removal, also deletes the associated merged local branch and,
    when verified merged into its origin base, the same-named origin branch. Unmerged,
    protected, changed, or unverifiable branches are retained. Missing checkouts use
    an inventoried local main checkout to verify Git identity when available.
    BranchCleanup reports outcomes separately from worktree removal; -Force never forces
    branch deletion.
    Returns one structured summary. Uses Spectre.Console when available, otherwise plain
    output. Use -Spectre:$false to disable rich output. Requires PowerShell 7 and a running
    local Orca runtime. Git-locked worktrees are kept and shown with a lock icon.
    -Unlock opens an fzf multi-select picker for locked local Orca worktrees, regardless
    of age or activity. Tab selects multiple; Enter unlocks; Esc cancels. Unlock mode
    supports -WhatIf/-Confirm and never performs cleanup or deletes a worktree.
    .EXAMPLE
    Remove-OrcaWorktrees -WhatIf
    .EXAMPLE
    Remove-OrcaWorktrees -InactiveDays 60
    .EXAMPLE
    Remove-OrcaWorktrees -Force -WhatIf
    .EXAMPLE
    Remove-OrcaWorktrees -Unlock
    Select locked local Orca worktrees with fzf and unlock them. Never removes worktrees.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Cleanup')]
    param(
        [Parameter(ParameterSetName = 'Cleanup')][ValidateRange(1, 36500)][int]$InactiveDays = 14,
        [Parameter(ParameterSetName = 'Cleanup')][switch]$Force,
        [Parameter(ParameterSetName = 'Cleanup')][switch]$All,
        [Parameter(ParameterSetName = 'Cleanup')][switch]$Spectre = $true,
        [Parameter(Mandatory, ParameterSetName = 'Unlock')][switch]$Unlock,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
        [ValidateRange(1, 100000)][int]$Limit = 10000,
        [string]$OrcaCommand
    )
    if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Remove-OrcaWorktrees requires PowerShell 7 or newer.' }
    $unlockMode = $PSCmdlet.ParameterSetName -eq 'Unlock'
    # Resolve the optional renderer before any inspection or destructive operation.
    $useSpectre = [bool]$Spectre
    if ($useSpectre -and -not $unlockMode) {
        try { Initialize-OrcaReapSpectre }
        catch {
            Write-Warning "Spectre unavailable ($($_.Exception.GetType().Name)); using plain output. Install PwshSpectreConsole or use -Spectre:`$false."
            $useSpectre = $false
        }
    }
    if (-not $OrcaCommand) {
        $OrcaCommand = if ($env:ORCA_CLI_COMMAND) { $env:ORCA_CLI_COMMAND }
            elseif ($env:ORCA_DEV_REPO_ROOT) { 'orca-dev' }
            elseif ($IsLinux -and -not $env:ORCA_TERMINAL_ID) { 'orca-ide' }
            else { 'orca' }
    }

    function Invoke-ReapOrca {
        param([string[]]$CommandArguments)
        $text = Invoke-OrcaReapCommand -Executable $OrcaCommand -Arguments ($CommandArguments + @('--json')) -TimeoutSeconds $TimeoutSeconds
        ConvertFrom-OrcaReapResponse -Text $text
    }
    function Get-ReapSnapshot {
        $listing = Invoke-ReapOrca @('worktree', 'list', '--limit', "$Limit")
        $activity = Invoke-ReapOrca @('worktree', 'ps', '--limit', "$Limit")
        if ($listing._meta.runtimeId -cne $activity._meta.runtimeId) { throw 'RuntimeChanged' }
        $complete = (Test-OrcaReapCoverage $listing.result 'worktrees') -and
            (Test-OrcaReapCoverage $activity.result 'worktrees')
        # Duplicate/missing addresses make coverage untrustworthy, even when counts match.
        $trees = @($listing.result.worktrees)
        $rows = @($activity.result.worktrees)
        foreach ($group in @(@{ Items = $trees; Key = 'id' }, @{ Items = $rows; Key = 'worktreeId' })) {
            $keys = @($group.Items | ForEach-Object { $_[$group.Key] })
            if (@($keys | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or
                @($keys | Select-Object -Unique).Count -ne $keys.Count) { $complete = $false }
        }
        [pscustomobject]@{ Listing = $listing; Activity = $activity; Complete = $complete }
    }
    function Assert-ReapIdentity {
        param($Expected, $Actual)
        foreach ($key in @('id', 'path', 'repoId', 'hostId', 'instanceId', 'head', 'branch', 'baseRef', 'lastActivityAt')) {
            if ($Expected[$key] -cne $Actual[$key]) { throw 'IdentityChanged' }
        }
        if ($Expected.identity.key -cne $Actual.identity.key) { throw 'IdentityChanged' }
    }
    function Assert-ReapCandidate {
        param($Tree, $Snapshot, $Entry)
        $shown = Invoke-ReapOrca @('worktree', 'show', '--worktree', "identity:$($Tree.identity.key)")
        if ($shown._meta.runtimeId -cne $Snapshot.Listing._meta.runtimeId) { throw 'RuntimeChanged' }
        Assert-ReapIdentity $Tree $shown.result.worktree
        $rows = @($Snapshot.Activity.result.worktrees | Where-Object { $_.worktreeId -ceq $Tree.id })
        if ($rows.Count -ne 1) { throw 'ActivityUnverified' }
        $assessment = Get-OrcaReapMetadataAssessment $shown.result.worktree $rows[0] $InactiveDays
        $Entry.Checks = $assessment.Checks; $Entry.ProtectionReasons = $assessment.ProtectionReasons
        $Entry.IsMainWorktree = $shown.result.worktree.isMainWorktree -is [bool] -and $shown.result.worktree.isMainWorktree
        Assert-OrcaReapMetadata $shown.result.worktree $rows[0] $InactiveDays ([DateTimeOffset]::UtcNow) -SkipAge:$Entry.MissingPath
        if ((Get-OrcaReapPathMissing -Path $shown.result.worktree.path) -ne $Entry.MissingPath) { throw 'PathChanged' }
        if (-not $Entry.MissingPath) {
            $gitSafety = Get-OrcaReapGitSafety -Tree $shown.result.worktree -TimeoutSeconds $TimeoutSeconds
            if ($gitSafety.Verified -ne $true) { throw 'GitUnverified' }
        }
        # Resource checks follow local Git identity checks.
        $terminals = Invoke-ReapOrca @('terminal', 'list', '--worktree', "identity:$($Tree.identity.key)", '--limit', "$Limit")
        if ($terminals._meta.runtimeId -cne $shown._meta.runtimeId) { throw 'RuntimeChanged' }
        if (-not (Test-OrcaReapCoverage $terminals.result 'terminals')) { throw 'IncompleteCoverage' }
        if ($terminals.result.terminals.Count -ne 0) { throw 'ActiveResources' }
        # Scoped tab queries hang for absent checkouts. The global inventory carries
        # exact worktree IDs; refresh it on every candidate validation, including recheck.
        $tabs = Invoke-ReapOrca @('tab', 'list', '--worktree', 'all')
        if ($tabs._meta.runtimeId -cne $shown._meta.runtimeId) { throw 'RuntimeChanged' }
        if ($tabs.result.tabs -isnot [array]) { throw 'ActiveResources' }
        foreach ($tab in $tabs.result.tabs) {
            if ($tab -isnot [System.Collections.IDictionary] -or
                $tab.worktreeId -isnot [string] -or [string]::IsNullOrWhiteSpace($tab.worktreeId) -or
                $tab.worktreeId -ceq $Tree.id) { throw 'ActiveResources' }
        }
        # Fresh ps observation also covers activity that began during Git checks.
        $fresh = Invoke-ReapOrca @('worktree', 'ps', '--limit', "$Limit")
        if ($fresh._meta.runtimeId -cne $shown._meta.runtimeId) { throw 'RuntimeChanged' }
        if (-not (Test-OrcaReapCoverage $fresh.result 'worktrees')) { throw 'IncompleteCoverage' }
        $freshRows = @($fresh.result.worktrees | Where-Object { $_.worktreeId -ceq $Tree.id })
        if ($freshRows.Count -ne 1) { throw 'ActivityUnverified' }
        $freshAssessment = Get-OrcaReapMetadataAssessment $shown.result.worktree $freshRows[0] $InactiveDays
        $Entry.Checks.Inactive = $freshAssessment.Checks.Inactive
        $Entry.Checks.Unpinned = $freshAssessment.Checks.Unpinned
        Assert-OrcaReapMetadata $shown.result.worktree $freshRows[0] $InactiveDays ([DateTimeOffset]::UtcNow) -SkipAge:$Entry.MissingPath
    }

    if ($unlockMode) {
        $listing = Invoke-ReapOrca @('worktree', 'list', '--limit', "$Limit")
        if (-not (Test-OrcaReapCoverage $listing.result 'worktrees')) { throw 'IncompleteCoverage' }
        $choices = @(
            foreach ($tree in $listing.result.worktrees) {
                if ($tree.isMainWorktree -ne $false -or $tree.hostId -cne 'local') { continue }
                try {
                    if (Get-OrcaReapPathMissing -Path $tree.path) { continue }
                    $lock = Get-OrcaReapLockState -Path $tree.path -TimeoutSeconds $TimeoutSeconds
                    if ($lock.IsLocked) { [pscustomobject]@{ Tree = $tree; Lock = $lock; Display = '' } }
                }
                catch {
                    $safePath = [string]$tree.path -replace '[\x00-\x1f\x7f-\x9f]', ''
                    Write-Warning "Lock inspection skipped for '$safePath': $(Get-OrcaReapDiagnostic $_)"
                }
            }
        )
        if (-not $choices.Count) { Write-Host 'No locked local Orca worktrees found.'; return }
        $null = Get-Command fzf -ErrorAction Stop
        for ($i = 0; $i -lt $choices.Count; $i++) {
            $choice = $choices[$i]
            $label = "$i  $(Split-Path -Leaf $choice.Tree.path) | $($choice.Tree.path) | $($choice.Lock.LockReason)"
            $choice.Display = $label -replace '[\x00-\x1f\x7f-\x9f]', ''
        }
        $global:LASTEXITCODE = 0
        $selected = @($choices.Display | fzf --multi --prompt 'Unlock worktrees: ' --header 'Tab selects multiple; Enter unlocks; Esc cancels')
        $pickerExit = $LASTEXITCODE
        if ($pickerExit -in @(1, 130)) { return }
        if ($pickerExit -ne 0) { throw "fzf failed (exit $pickerExit)" }
        # Validate the entire selection before changing any lock.
        $targets = @(
            foreach ($label in ($selected | Select-Object -Unique)) {
                $match = @($choices | Where-Object { $_.Display -ceq $label })
                if ($match.Count -ne 1) { throw 'Invalid fzf selection' }
                $match[0]
            }
        )
        foreach ($choice in $targets) {
            $tree = $choice.Tree
            if (-not $PSCmdlet.ShouldProcess($tree.path, 'Unlock Git worktree (does not remove it)')) { continue }
            $shown = Invoke-ReapOrca @('worktree', 'show', '--worktree', "identity:$($tree.identity.key)")
            if ($shown._meta.runtimeId -cne $listing._meta.runtimeId) { throw 'RuntimeChanged' }
            Assert-ReapIdentity $tree $shown.result.worktree
            $lock = Get-OrcaReapLockState -Path $tree.path -TimeoutSeconds $TimeoutSeconds
            if (-not $lock.IsLocked -or $lock.LockReason -cne $choice.Lock.LockReason) { throw 'Worktree lock changed during selection' }
            $null = Invoke-OrcaReapCommand -Executable 'git' -Arguments @('-C', $tree.path,
                'worktree', 'unlock', $tree.path) -TimeoutSeconds $TimeoutSeconds
            if ((Get-OrcaReapLockState -Path $tree.path -TimeoutSeconds $TimeoutSeconds).IsLocked) { throw 'Worktree unlock unverified' }
            [pscustomobject]@{ Worktree = Split-Path -Leaf $tree.path; Path = $tree.path; Status = 'Unlocked' }
        }
        return
    }

    function Get-ReapSummary {
        foreach ($entry in $results) {
            if (-not $coverageComplete) { $entry.Checks.Ready = $false }
            $explanation = switch ($entry.Reason) {
                'ProtectedWorktree' { $entry.ProtectionReasons -join '; ' }
                'RecentlyActive' { "Activity is not older than $InactiveDays days" }
                'TimestampInvalid' { 'Missing, invalid, or future activity timestamp' }
                'ActiveResources' { 'Activity, terminals, agents, or browser resources detected/unverified' }
                'GitUnverified' { 'Git registration, branch, or submodule safety unverified' }
                'WorktreeLocked' { 'Git worktree is locked; use -Unlock to select worktrees to unlock' }
                'IdentityUnverified' { 'Local worktree identity or path unverified' }
                'IdentityChanged' { 'Worktree changed during validation' }
                'ActivityUnverified' { 'Activity metadata missing or changed during validation' }
                'IncompleteCoverage' { 'Listing is partial or scope is unverified' }
                'RuntimeChanged' { 'Orca runtime changed during validation' }
                'PathChanged' { 'Directory existence changed during validation; no removal requested' }
                'PathUnverified' { 'Directory absence could not be safely verified' }
                'WhatIfOrDeclined' {
                    if ($entry.MissingPath) { 'Missing directory; would deregister with archive-hook waiver' }
                    else { 'Would delete; WhatIf or confirmation declined' }
                }
                'RemovalVerified' {
                    if ($entry.MissingPath) { 'Missing-directory registration removed with conditional archive-hook waiver' }
                    else { 'Removal confirmed by Orca listing' }
                }
                'RemovalUnverified' { 'Removal may have occurred; inspect Orca before retrying' }
                'Eligible' {
                    if ($entry.MissingPath) { 'Missing directory; eligible for deregistration with archive-hook waiver' }
                    else { 'Passed safety checks' }
                }
                default { $entry.Reason }
            }
            $entry | Add-Member -Force -NotePropertyName Explanation -NotePropertyValue $explanation
        }
        $summary = [pscustomobject]@{
            PSTypeName = 'RickScripts.OrcaReapSummary'
            SpectreRendered = $false
            All = [bool]$All
            InactiveDays = $InactiveDays; Force = [bool]$Force
            Scope = 'Local execution host of selected Orca runtime only'
            CoverageComplete = $coverageComplete; CoverageReason = $coverageReason
            HostIds = $hostIds; OmittedHostIds = $omittedHostIds
            CandidateCount = $candidateCount
            SkippedCount = @($results | Where-Object Status -eq 'Skipped').Count
            DeletedCount = @($results | Where-Object Status -eq 'Deleted').Count
            FailedCount = @($results | Where-Object Status -eq 'Failed').Count
            Results = @($results.ToArray())
        }
        $summary | Add-Member -NotePropertyName VisibleResults -NotePropertyValue @(
            if ($All) { $results.ToArray() } else { $candidates | ForEach-Object { $_.Entry } }
        )
        $summary
    }
    function Show-ReapSummary {
        param($Summary)
        if ($useSpectre) {
            try {
                Show-OrcaReapSpectre $Summary
                $Summary.SpectreRendered = $true
                return
            }
            catch {
                Write-Warning "Spectre display failed ($($_.Exception.GetType().Name)); using plain output. Do not rerun removal merely to refresh the display."
            }
        }
        # Render immediately to the host: pipeline formatting may otherwise happen after the prompt.
        $Summary | Out-String | ForEach-Object { Write-Host $_ }
    }

    $candidates = [System.Collections.Generic.List[object]]::new()
    $results = [System.Collections.Generic.List[object]]::new()
    $candidateCount = 0; $coverageComplete = $false; $coverageReason = 'IncompleteCoverage'
    $hostIds = @(); $omittedHostIds = @(); $snapshot = $null
    try {
        $snapshot = Get-ReapSnapshot
        $hostIds = @($snapshot.Listing.result.hostScope.hostIds)
        $omittedHostIds = @($snapshot.Listing.result.hostScope.omittedHostIds)
        $coverageComplete = $snapshot.Complete
        if ($coverageComplete) { $coverageReason = 'CompleteLocalRuntimeListing' }
    }
    catch {
        $coverageReason = Get-OrcaReapDiagnostic $_
        $results.Add([pscustomobject]@{
            PSTypeName = 'RickScripts.OrcaReapResult'
            Worktree = '(listing)'; Id = ''; Path = ''; IsMainWorktree = $false
            MissingPath = $false; IsLocked = $null; LockReason = ''; Status = 'Failed'; Reason = $coverageReason
            Checks = (Get-OrcaReapMetadataAssessment -InactiveDays $InactiveDays).Checks
            ProtectionReasons = @()
        })
    }
    if ($snapshot) {
        foreach ($tree in @($snapshot.Listing.result.worktrees)) {
            $displayPath = [string]$tree.path -replace '[\x00-\x1f\x7f-\x9f]', ''
            $folder = ($displayPath.TrimEnd([char[]]'/\') -split '[/\\]')[-1]
            $displayName = if ($folder) { $folder } else { '(unknown)' }
            $rows = @($snapshot.Activity.result.worktrees | Where-Object { $_.worktreeId -ceq $tree.id })
            $activityRow = if ($rows.Count -eq 1) { $rows[0] } else { $null }
            $assessment = Get-OrcaReapMetadataAssessment $tree $activityRow $InactiveDays
            $entry = [pscustomobject]@{
                PSTypeName = 'RickScripts.OrcaReapResult'
                Worktree = $displayName
                Id = ([string]$tree.id -replace '[\x00-\x1f\x7f-\x9f]', '')
                Path = $displayPath
                IsMainWorktree = $tree.isMainWorktree -is [bool] -and $tree.isMainWorktree
                MissingPath = $false; IsLocked = $null; LockReason = ''; Status = 'Skipped'; Reason = ''
                BranchCleanup = $null
                Checks = $assessment.Checks; ProtectionReasons = $assessment.ProtectionReasons
            }
            $results.Add($entry)
            try {
                if (-not $coverageComplete) { throw 'IncompleteCoverage' }
                # Observe locks independently of age/activity so kept worktrees remain visible.
                if (-not $entry.IsMainWorktree -and -not (Get-OrcaReapPathMissing -Path $tree.path)) {
                    $lock = Get-OrcaReapLockState -Path $tree.path -TimeoutSeconds $TimeoutSeconds
                    $entry.IsLocked = $lock.IsLocked; $entry.LockReason = $lock.LockReason
                    if ($entry.IsLocked) { throw 'WorktreeLocked' }
                }
                # Identity, protection and inactivity must pass even for missing paths.
                if ($rows.Count -ne 1) { throw 'ActivityUnverified' }
                Assert-OrcaReapMetadata $tree $rows[0] $InactiveDays ([DateTimeOffset]::UtcNow) -SkipAge
                $entry.MissingPath = Get-OrcaReapPathMissing -Path $tree.path
                if (-not $entry.MissingPath) {
                    Assert-OrcaReapMetadata $tree $rows[0] $InactiveDays ([DateTimeOffset]::UtcNow)
                }
                Assert-ReapCandidate $tree $snapshot $entry
                $entry.Checks.Ready = $true
                $candidateCount++
                $entry.Status = 'Candidate'; $entry.Reason = 'Eligible'
                $candidates.Add([pscustomobject]@{ Tree = $tree; Entry = $entry })
            }
            catch {
                $entry.Status = 'Skipped'; $entry.Reason = Get-OrcaReapDiagnostic $_
                $entry.Checks.Ready = $false
                if ($entry.Reason -eq 'WorktreeLocked') { $entry.IsLocked = $true }
                if ($entry.Reason -eq 'ActiveResources') { $entry.Checks.Inactive = $false }
                if ($entry.Reason -eq 'ActivityUnverified') { $entry.Checks.Inactive = $null }
                if ($entry.Reason -in @('IncompleteCoverage', 'RuntimeChanged')) {
                    $coverageComplete = $false; $coverageReason = $entry.Reason
                }
                continue
            }
        }
    }

    # Finish inspecting and display the selected list before requesting any mutation.
    $preview = Get-ReapSummary
    Show-ReapSummary $preview
    if ($All -or -not $coverageComplete -or $candidates.Count -eq 0) { return $preview }
    $action = if ($Force) { 'Remove listed worktrees via Orca --force and delete merged local/origin branches (local files may be lost)' }
        else { 'Remove listed worktrees via Orca and delete merged local/origin branches (including missing-directory deregistration)' }
    if (-not (Confirm-OrcaReapRemoval -Cmdlet $PSCmdlet -Target "$($candidates.Count) eligible worktree(s)" -Action $action)) {
        foreach ($candidate in $candidates) { $candidate.Entry.Reason = 'WhatIfOrDeclined' }
        $declined = Get-ReapSummary
        $declined.SpectreRendered = $preview.SpectreRendered
        return $declined
    }
    foreach ($candidate in $candidates) {
        $tree = $candidate.Tree; $entry = $candidate.Entry
        try {
            # Recheck after any confirmation wait, using the exact stable instance selector.
            $entry.Checks.Ready = $false
            $recheck = Get-ReapSnapshot
            if (-not $recheck.Complete) { throw 'IncompleteCoverage' }
            if ($recheck.Listing._meta.runtimeId -cne $snapshot.Listing._meta.runtimeId) { throw 'RuntimeChanged' }
            $current = @($recheck.Listing.result.worktrees | Where-Object { $_.id -ceq $tree.id })
            if ($current.Count -ne 1) { throw 'IdentityChanged' }
            $currentRows = @($recheck.Activity.result.worktrees | Where-Object { $_.worktreeId -ceq $tree.id })
            $currentActivity = if ($currentRows.Count -eq 1) { $currentRows[0] } else { $null }
            $assessment = Get-OrcaReapMetadataAssessment $current[0] $currentActivity $InactiveDays
            $entry.Checks = $assessment.Checks; $entry.ProtectionReasons = $assessment.ProtectionReasons
            Assert-ReapIdentity $tree $current[0]
            Assert-ReapCandidate $current[0] $recheck $entry
            $entry.Checks.Ready = $true
        }
        catch {
            $entry.Status = 'Skipped'; $entry.Reason = Get-OrcaReapDiagnostic $_
            $entry.Checks.Ready = $false
            if ($entry.Reason -eq 'WorktreeLocked') { $entry.IsLocked = $true }
            if ($entry.Reason -eq 'ActiveResources') { $entry.Checks.Inactive = $false }
            if ($entry.Reason -eq 'ActivityUnverified') { $entry.Checks.Inactive = $null }
            if ($entry.Reason -in @('IncompleteCoverage', 'RuntimeChanged')) {
                $coverageComplete = $false; $coverageReason = $entry.Reason
            }
            continue
        }
        # Capture the repository before Orca removes the directory. Failure to prove
        # branch safety must not weaken or prevent the existing worktree workflow.
        $branchPlan = $null
        $entry.BranchCleanup = [pscustomobject]@{ Branch=$tree.branch; Local='Retained'; Origin='Retained'; LocalReason='RemovalNotVerified'; OriginReason='RemovalNotVerified' }
        try {
            $repositoryPath = $tree.path
            if ($entry.MissingPath) {
                $mainTrees = @($recheck.Listing.result.worktrees | Where-Object {
                    $_.repoId -ceq $tree.repoId -and $_.hostId -ceq 'local' -and $_.isMainWorktree -eq $true
                })
                if ($mainTrees.Count -ne 1) { throw 'BranchUnverified' }
                $repositoryPath = $mainTrees[0].path
            }
            $branchPlan = Get-OrcaReapBranchPlan $tree -TimeoutSeconds $TimeoutSeconds -RepositoryPath $repositoryPath
        }
        catch {
            $diagnostic = Get-OrcaReapDiagnostic $_
            $entry.BranchCleanup.LocalReason = $diagnostic
            $entry.BranchCleanup.OriginReason = $diagnostic
        }
        # Removal/verification failures are distinct from ineligibility. Never retry a mutation.
        try {
            # Last absence check before issuing the one-shot mutation; never retry on failure.
            if ((Get-OrcaReapPathMissing -Path $tree.path) -ne $entry.MissingPath) { throw 'PathChanged' }
            $arguments = @('worktree', 'rm', '--worktree', "identity:$($tree.identity.key)", '--run-hooks')
            if ($entry.MissingPath) { $arguments += '--allow-failed-archive-hook' }
            if ($Force) { $arguments += '--force' }
            $removed = Invoke-ReapOrca $arguments
            if ($removed._meta.runtimeId -cne $snapshot.Listing._meta.runtimeId) { throw 'RuntimeChanged' }
            $after = Invoke-ReapOrca @('worktree', 'list', '--limit', "$Limit")
            if ($after._meta.runtimeId -cne $snapshot.Listing._meta.runtimeId -or
                -not (Test-OrcaReapCoverage $after.result 'worktrees')) { throw 'RemovalUnverified' }
            if (@($after.result.worktrees | Where-Object { $_.id -ceq $tree.id -or $_.identity.key -ceq $tree.identity.key }).Count -gt 0) { throw 'RemovalUnverified' }
            $entry.Status = 'Deleted'; $entry.Reason = 'RemovalVerified'
            if ($branchPlan) {
                $entry.BranchCleanup = Remove-OrcaReapBranches $branchPlan -TimeoutSeconds $TimeoutSeconds
            }
            if ($entry.BranchCleanup.Local -notin @('Deleted', 'Absent') -or
                $entry.BranchCleanup.Origin -notin @('Deleted', 'Absent')) {
                Write-Warning "Branch cleanup for '$($entry.Worktree)': local=$($entry.BranchCleanup.Local) ($($entry.BranchCleanup.LocalReason)); origin=$($entry.BranchCleanup.Origin) ($($entry.BranchCleanup.OriginReason)). See Results.BranchCleanup."
            }
        }
        catch {
            $entry.Status = 'Failed'; $entry.Reason = Get-OrcaReapDiagnostic $_
            $entry.Checks.Ready = $false
            if ($entry.Reason -in @('RemovalUnverified', 'RuntimeChanged')) {
                $coverageComplete = $false; $coverageReason = $entry.Reason
            }
        }
    }
    $summary = Get-ReapSummary
    Show-ReapSummary $summary
    $summary
}
