function Get-LatestRun {
    [CmdletBinding()]
    param(
        [string]$Branch = $(git branch --show-current 2>$null)
    )

    function Get-RunStatusIcon {
        param(
            [string]$Status
        )

        switch ($Status) {
            'pass' { return '✅' }
            'fail' { return '❌' }
            'cancel' { return '🚫' }
            'skipping' { return '⏭️' }
            'pending' { return '🟡' }
            'success' { return '✅' }
            'failure' { return '❌' }
            'cancelled' { return '🚫' }
            'skipped' { return '⏭️' }
            'neutral' { return '⚪' }
            'timed_out' { return '⏰' }
            'action_required' { return '⚠️' }
            'in_progress' { return '🟡' }
            'queued' { return '🟣' }
            'pending' { return '🟣' }
            default { return '❔' }
        }
    }

    function Get-RunOutcomeText {
        param(
            [string]$Status
        )

        switch ($Status) {
            'pass' { return 'Successful' }
            'fail' { return 'Failed' }
            'cancel' { return 'Cancelled' }
            'skipping' { return 'Skipped' }
            'pending' { return 'In progress' }
            'success' { return 'Successful' }
            'failure' { return 'Failed' }
            'cancelled' { return 'Cancelled' }
            'skipped' { return 'Skipped' }
            'neutral' { return 'Neutral' }
            'timed_out' { return 'Timed out' }
            'action_required' { return 'Action required' }
            'in_progress' { return 'In progress' }
            'queued' { return 'Queued' }
            'pending' { return 'Pending' }
            default { return $Status }
        }
    }

    function Get-JobDurationText {
        param(
            $Job
        )

        $startedAtValue = if ($Job.startedAt) { $Job.startedAt } elseif ($Job.started_at) { $Job.started_at } else { $null }
        $completedAtValue = if ($Job.completedAt) { $Job.completedAt } elseif ($Job.completed_at) { $Job.completed_at } else { $null }

        if (-not $startedAtValue -or -not $completedAtValue) {
            return $null
        }

        try {
            $startedAt = [DateTimeOffset]::Parse($startedAtValue)
            $completedAt = [DateTimeOffset]::Parse($completedAtValue)
        }
        catch {
            return $null
        }

        $duration = $completedAt - $startedAt
        if ($duration.TotalSeconds -lt 60) {
            return ("{0}s" -f [Math]::Max([int][Math]::Round($duration.TotalSeconds), 0))
        }

        if ($duration.TotalMinutes -lt 60) {
            return ("{0}m" -f [Math]::Max([int][Math]::Round($duration.TotalMinutes), 0))
        }

        return ("{0}h {1}m" -f [Math]::Floor($duration.TotalHours), $duration.Minutes)
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI ('gh') is required."
        return
    }

    if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
        Write-Error "Not in a git repository."
        return
    }

    if (-not $Branch) {
        Write-Error "Could not determine a branch name."
        return
    }

    $checksJson = gh pr checks $Branch --json name,state,workflow,bucket,startedAt,completedAt,link 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $checksJson) {
        Write-Error "Failed to load PR checks for branch '$Branch'."
        return
    }

    $checks = $checksJson | ConvertFrom-Json
    if (-not $checks) {
        Write-Output "No PR checks found for branch '$Branch'"
        return
    }

    $rows = foreach ($check in $checks) {
        $durationText = Get-JobDurationText -Job $check
        $statusValue = if ($check.bucket) { $check.bucket } else { $check.state }
        $outcomeText = Get-RunOutcomeText -Status $statusValue
        $resultText = if ($durationText -and $statusValue -in @('pass', 'fail', 'cancel', 'skipping', 'success', 'failure', 'cancelled', 'timed_out', 'neutral', 'skipped')) {
            "{0} in {1}" -f $outcomeText, $durationText
        }
        else {
            $outcomeText
        }

        [PSCustomObject]@{
            Workflow = if ($check.workflow) { $check.workflow } else { 'Other' }
            Icon = Get-RunStatusIcon -Status $statusValue
            Check = $check.name
            Result = $resultText
        }
    }

    foreach ($group in ($rows | Group-Object Workflow)) {
        Write-Host $group.Name -ForegroundColor Cyan

        foreach ($row in $group.Group) {
            "{0,-4} {1,-30} {2}" -f $row.Icon, $row.Check, $row.Result
        }
    }
}

Set-Alias glr Get-LatestRun
