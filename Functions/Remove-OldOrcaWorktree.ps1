function Remove-OldOrcaWorktree {
    <#
    .SYNOPSIS
    Removes old, verified-inactive local Orca worktrees conservatively.
    .DESCRIPTION
    Default age is strictly greater than 30 days since lastActivityAt (not a sleep timestamp).
    Safe candidates are deleted by default. Use -WhatIf to preview. -Force permits local
    file loss and passes --force to Orca; it never bypasses commit safety or archive hooks.
    Returns one structured summary. Requires PowerShell 7 and a running local Orca runtime.
    .EXAMPLE
    Remove-OldOrcaWorktree -WhatIf
    .EXAMPLE
    Remove-OldOrcaWorktree -InactiveDays 60
    .EXAMPLE
    Remove-OldOrcaWorktree -Force -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [ValidateRange(1, 36500)][int]$InactiveDays = 30,
        [switch]$Force,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
        [ValidateRange(1, 100000)][int]$Limit = 10000,
        [string]$OrcaCommand
    )
    if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Remove-OldOrcaWorktree requires PowerShell 7 or newer.' }
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
        param($Tree, $Snapshot)
        $shown = Invoke-ReapOrca @('worktree', 'show', '--worktree', "identity:$($Tree.identity.key)")
        if ($shown._meta.runtimeId -cne $Snapshot.Listing._meta.runtimeId) { throw 'RuntimeChanged' }
        Assert-ReapIdentity $Tree $shown.result.worktree
        $rows = @($Snapshot.Activity.result.worktrees | Where-Object { $_.worktreeId -ceq $Tree.id })
        if ($rows.Count -ne 1) { throw 'ActivityUnverified' }
        Assert-OrcaReapMetadata $shown.result.worktree $rows[0] $InactiveDays ([DateTimeOffset]::UtcNow)
        $gitSafety = Get-OrcaReapGitSafety -Tree $shown.result.worktree -TimeoutSeconds $TimeoutSeconds
        if ($gitSafety.HasLocalFiles -isnot [bool]) { throw 'GitUnverified' }
        # Resource checks follow Git/network checks, so a slow remote cannot age this observation.
        $terminals = Invoke-ReapOrca @('terminal', 'list', '--worktree', "identity:$($Tree.identity.key)", '--limit', "$Limit")
        if ($terminals._meta.runtimeId -cne $shown._meta.runtimeId) { throw 'RuntimeChanged' }
        if (-not (Test-OrcaReapCoverage $terminals.result 'terminals')) { throw 'IncompleteCoverage' }
        if ($terminals.result.terminals.Count -ne 0) { throw 'ActiveResources' }
        $tabs = Invoke-ReapOrca @('tab', 'list', '--worktree', "identity:$($Tree.identity.key)")
        if ($tabs._meta.runtimeId -cne $shown._meta.runtimeId) { throw 'RuntimeChanged' }
        if ($tabs.result.tabs -isnot [array] -or $tabs.result.tabs.Count -ne 0) { throw 'ActiveResources' }
        # Fresh ps observation also covers activity that began during Git checks.
        $fresh = Invoke-ReapOrca @('worktree', 'ps', '--limit', "$Limit")
        if ($fresh._meta.runtimeId -cne $shown._meta.runtimeId) { throw 'RuntimeChanged' }
        if (-not (Test-OrcaReapCoverage $fresh.result 'worktrees')) { throw 'IncompleteCoverage' }
        $freshRows = @($fresh.result.worktrees | Where-Object { $_.worktreeId -ceq $Tree.id })
        if ($freshRows.Count -ne 1) { throw 'ActivityUnverified' }
        Assert-OrcaReapMetadata $shown.result.worktree $freshRows[0] $InactiveDays ([DateTimeOffset]::UtcNow)
        if ($gitSafety.HasLocalFiles -and -not $Force) { throw 'GitDirty' }
    }

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
        $results.Add([pscustomobject]@{ Id = ''; Path = ''; Status = 'Failed'; Reason = $coverageReason; NeedsForce = $false })
    }
    if ($snapshot) {
        foreach ($tree in @($snapshot.Listing.result.worktrees)) {
            $entry = [pscustomobject]@{
                Id = ([string]$tree.id -replace '[\x00-\x1f\x7f-\x9f]', '')
                Path = ([string]$tree.path -replace '[\x00-\x1f\x7f-\x9f]', '')
                Status = 'Skipped'; Reason = ''; NeedsForce = $false
            }
            $results.Add($entry)
            try {
                if (-not $coverageComplete) { throw 'IncompleteCoverage' }
                # Cheap metadata screening avoids touching recently-active/protected checkouts.
                $rows = @($snapshot.Activity.result.worktrees | Where-Object { $_.worktreeId -ceq $tree.id })
                if ($rows.Count -ne 1) { throw 'ActivityUnverified' }
                Assert-OrcaReapMetadata $tree $rows[0] $InactiveDays ([DateTimeOffset]::UtcNow)
                Assert-ReapCandidate $tree $snapshot
                $candidateCount++
                $entry.Status = 'Candidate'; $entry.Reason = 'Eligible'
                $action = if ($Force) { 'Remove via Orca --force (local files may be lost)' } else { 'Remove via Orca' }
                if (-not $PSCmdlet.ShouldProcess($entry.Path, $action)) {
                    $entry.Reason = 'WhatIfOrDeclined'
                    continue
                }
                # Recheck after any confirmation wait, using the exact stable instance selector.
                $recheck = Get-ReapSnapshot
                if (-not $recheck.Complete) { throw 'IncompleteCoverage' }
                if ($recheck.Listing._meta.runtimeId -cne $snapshot.Listing._meta.runtimeId) { throw 'RuntimeChanged' }
                $current = @($recheck.Listing.result.worktrees | Where-Object { $_.id -ceq $tree.id })
                if ($current.Count -ne 1) { throw 'IdentityChanged' }
                Assert-ReapIdentity $tree $current[0]
                Assert-ReapCandidate $current[0] $recheck
            }
            catch {
                $entry.Status = 'Skipped'; $entry.Reason = Get-OrcaReapDiagnostic $_
                if ($entry.Reason -in @('IncompleteCoverage', 'RuntimeChanged')) {
                    $coverageComplete = $false; $coverageReason = $entry.Reason
                }
                $entry.NeedsForce = $entry.Reason -eq 'GitDirty' -and -not $Force
                continue
            }
            # Removal/verification failures are distinct from ineligibility. Never retry a mutation.
            try {
                $arguments = @('worktree', 'rm', '--worktree', "identity:$($tree.identity.key)", '--run-hooks')
                if ($Force) { $arguments += '--force' }
                $removed = Invoke-ReapOrca $arguments
                if ($removed._meta.runtimeId -cne $snapshot.Listing._meta.runtimeId) { throw 'RuntimeChanged' }
                $after = Invoke-ReapOrca @('worktree', 'list', '--limit', "$Limit")
                if ($after._meta.runtimeId -cne $snapshot.Listing._meta.runtimeId -or
                    -not (Test-OrcaReapCoverage $after.result 'worktrees')) { throw 'RemovalUnverified' }
                if (@($after.result.worktrees | Where-Object { $_.id -ceq $tree.id -or $_.identity.key -ceq $tree.identity.key }).Count -gt 0) { throw 'RemovalUnverified' }
                $entry.Status = 'Deleted'; $entry.Reason = 'RemovalVerified'
            }
            catch {
                $entry.Status = 'Failed'; $entry.Reason = Get-OrcaReapDiagnostic $_
                if ($entry.Reason -in @('RemovalUnverified', 'RuntimeChanged')) {
                    $coverageComplete = $false; $coverageReason = $entry.Reason
                }
            }
        }
    }
    $needsForce = @($results | Where-Object NeedsForce)
    if ($needsForce.Count -gt 0) {
        Write-Warning "$($needsForce.Count) otherwise eligible worktree(s) have local files. Review Results where NeedsForce is true; preview Remove-OldOrcaWorktree -Force -WhatIf before opting into file loss."
    }
    [pscustomobject]@{
        InactiveDays = $InactiveDays; Force = [bool]$Force
        Scope = 'Local execution host of selected Orca runtime only'
        CoverageComplete = $coverageComplete; CoverageReason = $coverageReason
        HostIds = $hostIds; OmittedHostIds = $omittedHostIds
        CandidateCount = $candidateCount
        SkippedCount = @($results | Where-Object Status -eq 'Skipped').Count
        DeletedCount = @($results | Where-Object Status -eq 'Deleted').Count
        FailedCount = @($results | Where-Object Status -eq 'Failed').Count
        NeedsForce = $needsForce; Results = @($results.ToArray())
    }
}
