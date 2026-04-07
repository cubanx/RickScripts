function Show-JiraBoard {
    [CmdletBinding()]
    param(
        [string[]]$Columns = @('In Progress', 'In Review'),
        [switch]$IncludeUpNext,
        [switch]$Mine,
        [int]$MaxResults = 200,
        [switch]$Raw
    )

    if ($IncludeUpNext -and -not ($Columns -contains 'UP NEXT')) {
        $Columns = @('UP NEXT') + @($Columns)
    }

    $pageSize = [Math]::Min(100, [Math]::Max(1, $MaxResults))
    $jiraArguments = @('issue', 'list', '--raw', '--order-by', 'rank', '--paginate', "0:$pageSize")
    foreach ($columnName in $Columns) {
        $jiraArguments += @('-s', $columnName)
    }

    if ($Mine) {
        $currentUser = (& jira me).Trim()
        if (-not $currentUser) {
            throw 'Could not resolve current Jira user from `jira me`.'
        }

        $jiraArguments += @('-a', $currentUser)
    }

    $rawJson = & jira @jiraArguments
    if ($LASTEXITCODE -ne 0) {
        throw "jira issue list failed with exit code $LASTEXITCODE"
    }

    $boardIssues = @()
    if (-not [string]::IsNullOrWhiteSpace($rawJson)) {
        $boardIssues = @($rawJson | ConvertFrom-Json)
    }

    $cards = foreach ($issue in $boardIssues) {
        $columnName = $issue.fields.status.name

        if (-not ($Columns -contains $columnName)) {
            continue
        }

        [pscustomobject]@{
            Column   = $columnName
            Key      = $issue.key
            Summary  = $issue.fields.summary
            Assignee = $issue.fields.assignee.displayName
            Priority = $issue.fields.priority.name
            Status   = $issue.fields.status.name
        }
    }

    if ($Raw) {
        return $cards | Sort-Object Column, Key
    }

    $totalWidth = 120
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 0) {
            $totalWidth = [Math]::Max(60, [int]$Host.UI.RawUI.WindowSize.Width)
        }
    } catch {
    }

    $gutter = '  '
    $columnCount = [Math]::Max(1, $Columns.Count)
    $availableWidth = $totalWidth - ($gutter.Length * ($columnCount - 1))
    $columnWidth = [Math]::Min(48, [Math]::Max(20, [Math]::Floor($availableWidth / $columnCount)))
    $innerWidth = [Math]::Max(16, $columnWidth - 2)
    $contentWidth = [Math]::Max(8, $innerWidth - 2)
    $summaryWidth = [Math]::Max(8, $contentWidth - 11)
    $assigneeWidth = $contentWidth

    function Format-JiraBoardCellText {
        param(
            [string]$Text,
            [int]$Width
        )

        if ($null -eq $Text) {
            $Text = ''
        }

        if ($Text.Length -gt $Width) {
            if ($Width -le 1) {
                return '…'
            }

            return $Text.Substring(0, [Math]::Max(0, $Width - 1)).TrimEnd() + '…'
        }

        return $Text.PadRight($Width)
    }

    $renderedColumns = foreach ($columnName in $Columns) {
        $columnCards = @($cards | Where-Object { $_.Column -eq $columnName })
        $lines = New-Object System.Collections.Generic.List[string]
        $header = '{0} ({1})' -f $columnName.ToUpper(), $columnCards.Count
        $lines.Add($header)
        $lines.Add(('-' * [Math]::Min($columnWidth, $header.Length)))

        if ($columnCards.Count -eq 0) {
            $lines.Add('(empty)')
        } else {
            foreach ($card in $columnCards) {
                $assignee = if ($card.Assignee) { $card.Assignee } else { 'Unassigned' }
                $summary = Format-JiraBoardCellText -Text $card.Summary -Width $summaryWidth
                $assigneeDisplay = Format-JiraBoardCellText -Text $assignee -Width $assigneeWidth

                $topBorder = '+' + ('-' * $innerWidth) + '+'
                $emptyLine = '|' + (' ' * $innerWidth) + '|'
                $titleLine = '| ' + (Format-JiraBoardCellText -Text ('{0} {1}' -f $card.Key, $summary) -Width $contentWidth) + ' |'
                $assigneeLine = '| ' + (Format-JiraBoardCellText -Text $assigneeDisplay -Width $contentWidth) + ' |'

                $lines.Add($topBorder)
                $lines.Add($titleLine)
                $lines.Add($assigneeLine)
                $lines.Add($emptyLine)
                $lines.Add($topBorder)
                $lines.Add('')
            }
        }

        [pscustomobject]@{
            Name  = $columnName
            Lines = @($lines)
        }
    }

    $maxLineCount = ($renderedColumns | ForEach-Object { $_.Lines.Count } | Measure-Object -Maximum).Maximum

    for ($lineIndex = 0; $lineIndex -lt $maxLineCount; $lineIndex++) {
        $row = foreach ($column in $renderedColumns) {
            $line = if ($lineIndex -lt $column.Lines.Count) { $column.Lines[$lineIndex] } else { '' }
            $line.PadRight($columnWidth)
        }

        Write-Host ($row -join $gutter)
    }
}
