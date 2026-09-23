function Get-OpenSpecStatus {
    <#
    .SYNOPSIS
    Reports progress for the most recently modified active OpenSpec change.

    .DESCRIPTION
    Uses the latest OpenSpec modification time by default, or selects an active
    change with -Choose. Shows unfinished task groups through the first group
    where every task is open.

    .EXAMPLE
    Get-OpenSpecStatus

    Reports the most recently modified active change.

    .EXAMPLE
    Get-OpenSpecStatus -Choose

    Picks an active change with fzf.

    .EXAMPLE
    Get-OpenSpecStatus -Change add-wormhole-routing

    Reports a specific active change.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Latest')]
    param(
        [Parameter(ParameterSetName = 'Named')]
        [string]$Change,

        [Parameter(ParameterSetName = 'Pick')]
        [switch]$Choose
    )

    $previousTelemetry = [Environment]::GetEnvironmentVariable('OPENSPEC_TELEMETRY', 'Process')
    $env:OPENSPEC_TELEMETRY = '0'
    try {
    $listOutput = (& openspec list --json | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not list OpenSpec changes: $listOutput" }
    try { $changeList = $listOutput | ConvertFrom-Json }
    catch { throw "Could not parse OpenSpec change list: $($_.Exception.Message)" }

    $changes = @($changeList.changes)
    if (-not $changes) { throw 'No active OpenSpec changes found.' }
    $orderedChanges = @($changes | Sort-Object -Property lastModified -Descending)
    if ($Change) {
        $selected = $changes | Where-Object { $_.name -eq $Change } | Select-Object -First 1
        if (-not $selected) { throw "'$Change' is not an active OpenSpec change." }
    }
    elseif ($Choose) {
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            throw 'fzf is unavailable. Use -Change instead.'
        }
        $picked = [Convert]::ToString(($orderedChanges.name | fzf --prompt 'Pick an OpenSpec change: ' | Select-Object -First 1)).Trim()
        if (-not $picked) { throw 'No OpenSpec change selected.' }
        $selected = $changes | Where-Object { $_.name -eq $picked } | Select-Object -First 1
        if (-not $selected) { throw "fzf returned unknown OpenSpec change '$picked'." }
    }
    else {
        $selected = $orderedChanges[0]
    }

    "Change: $($selected.name)"
    $tasksPath = Join-Path $changeList.root.path "openspec/changes/$($selected.name)/tasks.md"
    if (Test-Path -LiteralPath $tasksPath) {
        $tasks = Get-Content -LiteralPath $tasksPath -Raw -ErrorAction Stop
        foreach ($group in [regex]::Split($tasks, '(?m)(?=^## )')) {
            if (-not $group.StartsWith('## ')) { continue }
            $checks = @([regex]::Matches($group, '(?m)^[ \t]*- [ \t]*\[([ xX])\]'))
            $open = @($checks | Where-Object { $_.Groups[1].Value -eq ' ' }).Count
            if ($open -eq 0) { continue }
            ($group.TrimEnd() -split '\r?\n')
            if ($open -eq $checks.Count) { break }
        }
    }
    "Tasks: $($selected.completedTasks)/$($selected.totalTasks) complete ($($selected.status))"
    }
    finally {
        [Environment]::SetEnvironmentVariable('OPENSPEC_TELEMETRY', $previousTelemetry, 'Process')
    }
}

Set-Alias goss Get-OpenSpecStatus
