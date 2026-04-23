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
            'pass' { return '' }
            'fail' { return '' }
            'cancel' { return '' }
            'skipping' { return '󰒭' }
            'pending' { return '' }
            'success' { return '' }
            'failure' { return '' }
            'cancelled' { return '' }
            'skipped' { return '󰒭' }
            'neutral' { return '' }
            'timed_out' { return '󰔟' }
            'action_required' { return '' }
            'in_progress' { return '' }
            'queued' { return '' }
            default { return '' }
        }
    }

    function Get-RunStatusColor {
        param(
            [string]$Status
        )

        switch ($Status) {
            'pass' { return 'Green' }
            'success' { return 'Green' }
            'fail' { return 'Red' }
            'failure' { return 'Red' }
            'cancel' { return 'DarkGray' }
            'cancelled' { return 'DarkGray' }
            'skipping' { return 'DarkGray' }
            'skipped' { return 'DarkGray' }
            'neutral' { return 'Gray' }
            'timed_out' { return 'DarkYellow' }
            'action_required' { return 'Yellow' }
            'pending' { return 'Yellow' }
            'in_progress' { return 'Yellow' }
            'queued' { return 'DarkYellow' }
            default { return 'Gray' }
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

        if ($completedAtValue -eq '0001-01-01T00:00:00Z') {
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
        if ($duration.TotalSeconds -lt 0) {
            return $null
        }

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

    $checksOutput = gh pr checks $Branch --json name,state,workflow,bucket,startedAt,completedAt,link 2>&1
    $ghExitCode = $LASTEXITCODE

    if ($ghExitCode -eq 1 -and $checksOutput -match 'no pull requests found for branch') {
        Write-Output "No PR checks found for branch '$Branch'"
        return
    }

    if ($ghExitCode -ne 0 -and $ghExitCode -ne 8) {
        Write-Error "Failed to load PR checks for branch '$Branch'."
        return
    }

    $checksJson = if ($checksOutput -is [System.Array]) {
        $checksOutput -join [Environment]::NewLine
    }
    else {
        [string]$checksOutput
    }

    if (-not $checksJson) {
        Write-Output "No PR checks found for branch '$Branch'"
        return
    }

    try {
        $checks = $checksJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Output "Could not parse PR checks for branch '$Branch'"
        return
    }

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
            Status = $statusValue
            Icon = Get-RunStatusIcon -Status $statusValue
            Check = $check.name
            Result = $resultText
        }
    }

    foreach ($group in ($rows | Group-Object Workflow)) {
        Write-Host $group.Name -ForegroundColor Cyan

        $checkWidth = (($group.Group | ForEach-Object { $_.Check.Length } | Measure-Object -Maximum).Maximum)
        if (-not $checkWidth) {
            $checkWidth = 0
        }

        foreach ($row in $group.Group) {
            $paddedCheck = $row.Check.PadRight($checkWidth)
            $iconColor = Get-RunStatusColor -Status $row.Status
            Write-Host $row.Icon -ForegroundColor $iconColor -NoNewline
            Write-Host ("  {0}  {1}" -f $paddedCheck, $row.Result)
        }
    }
}

Set-Alias glr Get-LatestRun
