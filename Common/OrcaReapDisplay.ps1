# Optional presentation only; never used for eligibility or removal decisions.
function Initialize-OrcaReapSpectre {
    try {
        Import-Module PwshSpectreConsole -MinimumVersion 2.0.0 -ErrorAction Stop
        foreach ($name in @('Format-SpectreTable', 'Out-SpectreHost', 'Write-SpectreHost')) {
            $null = Get-Command "PwshSpectreConsole\$name" -ErrorAction Stop
        }
    }
    catch {
        throw "SpectreUnavailable ($($_.Exception.GetType().Name)). Install PwshSpectreConsole 2.x before using -Spectre."
    }
}

function ConvertTo-OrcaReapMarkupLiteral {
    param([AllowNull()][string]$Text)
    ($Text -replace '[\x00-\x1f\x7f-\x9f]', '').Replace('[', '[[').Replace(']', ']]')
}

function Get-OrcaReapSpectreRows {
    param($Summary)
    foreach ($entry in @($Summary.Results | Where-Object {
        -not ($_.IsMainWorktree -and $_.Status -eq 'Skipped' -and $_.Reason -eq 'ProtectedWorktree')
    } | Sort-Object Worktree)) {
        $row = [ordered]@{ Worktree = ConvertTo-OrcaReapMarkupLiteral $entry.Worktree }
        $row.Age = if ($entry.Checks.OldEnough -eq $true) { '[green]✅[/]' }
            elseif ($entry.Checks.AgeDays -is [int] -and $entry.Checks.AgeDays -ge 0) { "[yellow]$($entry.Checks.AgeDays)d[/]" }
            else { '[red]❌[/]' }
        foreach ($column in @(
            @('Idle', 'Inactive'), @('Unpinned', 'Unpinned'),
            @('NoKids', 'NoChildren'), @('Ready', 'Ready')
        )) {
            $row[$column[0]] = if ($entry.Checks.($column[1]) -eq $true) { '[green]✅[/]' } else { '[red]❌[/]' }
        }
        $row.Status = ConvertTo-OrcaReapMarkupLiteral $entry.Status
        $row.Reason = ConvertTo-OrcaReapMarkupLiteral $entry.Explanation
        [pscustomobject]$row
    }
}

function Show-OrcaReapSpectre {
    param($Summary)
    $rows = @(Get-OrcaReapSpectreRows $Summary)
    if ($rows.Count -gt 0) {
        $table = $rows | PwshSpectreConsole\Format-SpectreTable -Property Worktree,Age,Idle,Unpinned,NoKids,Ready -AllowMarkup -ErrorAction Stop
        # Emoji need two cells; prevent narrow-terminal wrapping inside check cells.
        foreach ($column in $table.Columns) { $column.NoWrap = $true }
        # The adapter can return rendered strings when called inside a pipeline.
        # Route those to the host too, never the cmdlet's structured success stream.
        $table | PwshSpectreConsole\Out-SpectreHost -ErrorAction Stop | ForEach-Object { Write-Host $_ }
    }
    else {
        $message = if ($Summary.CoverageComplete) { 'No visible worktrees in this summary.' }
            else { "[red]INCOMPLETE[/] ($(ConvertTo-OrcaReapMarkupLiteral $Summary.CoverageReason))" }
        PwshSpectreConsole\Write-SpectreHost $message -ErrorAction Stop
    }
}
