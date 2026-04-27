function Show-JiraBoard {
    [CmdletBinding()]
    param(
        [string[]]$Columns = @('In Progress', 'In Review'),
        [switch]$IncludeUpNext,
        [switch]$All,
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

    if (-not $All) {
        $currentUser = (& jira me).Trim()
        if (-not $currentUser) {
            throw 'Could not resolve current Jira user from `jira me`.'
        }

        $jiraArguments += @('-a', $currentUser)
    }

    function ConvertFrom-JiraIssueJson {
        param(
            [AllowEmptyString()]
            [string]$Json
        )

        if ([string]::IsNullOrWhiteSpace($Json)) {
            return [pscustomobject]@{
                Success = $true
                Value   = @()
                Error   = $null
            }
        }

        try {
            return [pscustomobject]@{
                Success = $true
                Value   = ($Json | ConvertFrom-Json -ErrorAction Stop)
                Error   = $null
            }
        }
        catch {
            return [pscustomobject]@{
                Success = $false
                Value   = $null
                Error   = $_
            }
        }
    }

    $rawJson = & jira @jiraArguments
    if ($LASTEXITCODE -ne 0) {
        throw "jira issue list failed with exit code $LASTEXITCODE"
    }

    $boardIssueParse = ConvertFrom-JiraIssueJson -Json $rawJson
    if (-not $boardIssueParse.Success) {
        $parseError = $boardIssueParse.Error | Select-Object -First 1
        $parseMessage = ([string]$parseError -split '\r?\n' | Select-Object -First 1)

        Write-Error "Could not parse Jira issue list JSON: $parseMessage"
        return
    }

    $boardIssues = @($boardIssueParse.Value)

    function Get-JiraCliConfigValue {
        param(
            [Parameter(Mandatory = $true)]
            [string[]]$Names
        )

        $configPath = Join-Path $HOME '.config/.jira/.config.yml'
        if (-not (Test-Path $configPath)) {
            return $null
        }

        foreach ($line in Get-Content $configPath) {
            if ($line -notmatch '^\s*(?<key>[^:#]+):\s*(?<value>.+?)\s*$') {
                continue
            }

            $key = $Matches.key.Trim()
            if ($key -notin $Names) {
                continue
            }

            return $Matches.value.Trim().Trim('"').Trim("'").TrimEnd('/')
        }

        return $null
    }

    function Get-JiraApiCredential {
        $baseUrl = $env:JIRA_BASE_URL
        if (-not $baseUrl) {
            $baseUrl = Get-JiraCliConfigValue -Names @('endpoint', 'server', 'url')
        }

        $email = $env:JIRA_EMAIL
        if (-not $email) {
            $email = (& jira me).Trim()
        }

        $apiToken = $env:JIRA_API_TOKEN
        if (-not $apiToken -and (Test-Path "$HOME/.jira-env")) {
            foreach ($line in Get-Content "$HOME/.jira-env") {
                if ($line -notmatch '^\s*JIRA_KEYCHAIN_SERVICE=(?<service>.+?)\s*$') {
                    continue
                }

                $apiToken = security find-generic-password -a $env:USER -s $Matches.service -w
                break
            }
        }

        if (-not $baseUrl -or -not $email -or -not $apiToken) {
            return $null
        }

        [pscustomobject]@{
            BaseUrl  = $baseUrl.TrimEnd('/')
            Email    = $email
            ApiToken = $apiToken
        }
    }

    $jiraApiCredential = Get-JiraApiCredential

    function New-TerminalHyperlink {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Text,

            [string]$Url
        )

        if ([string]::IsNullOrWhiteSpace($Url)) {
            return $Text
        }

        $escape = [char]27
        return "$escape]8;;$Url$escape\$Text$escape]8;;$escape\"
    }

    function Get-JiraPullRequestStatus {
        param(
            [Parameter(Mandatory = $true)]
            $Issue
        )

        $issueJson = & jira issue view $Issue.key --raw
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($issueJson)) {
            return [pscustomobject]@{
                Text = 'PR: unknown'
                Url  = $null
            }
        }

        $issueDetailParse = ConvertFrom-JiraIssueJson -Json $issueJson
        if (-not $issueDetailParse.Success) {
            return [pscustomobject]@{
                Text = 'PR: unknown'
                Url  = $null
            }
        }

        $issueDetail = $issueDetailParse.Value
        $developmentField = [string]$issueDetail.fields.customfield_10000

        if ([string]::IsNullOrWhiteSpace($developmentField) -or $developmentField -eq '{}') {
            return [pscustomobject]@{
                Text = 'PR: none'
                Url  = $null
            }
        }

        if ($developmentField -notmatch 'pullrequest') {
            return [pscustomobject]@{
                Text = 'PR: none'
                Url  = $null
            }
        }

        $count = $null
        $state = $null

        if ($developmentField -match 'count\\":(?<count>\d+)') {
            $count = [int]$Matches.count
        }
        elseif ($developmentField -match 'stateCount=(?<count>\d+)') {
            $count = [int]$Matches.count
        }

        if ($developmentField -match 'state\\":\\"(?<state>[^\\"]+)') {
            $state = $Matches.state.ToLowerInvariant()
        }
        elseif ($developmentField -match 'state=(?<state>[A-Z_]+)') {
            $state = $Matches.state.ToLowerInvariant()
        }

        $url = $null
        if ($jiraApiCredential -and $issueDetail.id) {
            $pair = "{0}:{1}" -f $jiraApiCredential.Email, $jiraApiCredential.ApiToken
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
            $detailUri = '{0}/rest/dev-status/latest/issue/detail?issueId={1}&applicationType=GitHub&dataType=pullrequest' -f $jiraApiCredential.BaseUrl, $issueDetail.id

            try {
                $detail = Invoke-RestMethod -Method GET -Uri $detailUri -Headers @{
                    Authorization = "Basic $encoded"
                    Accept        = 'application/json'
                } -ErrorAction Stop

                $pullRequests = @($detail.detail | ForEach-Object { $_.pullRequests } | Where-Object { $_ })
                $url = $pullRequests | Select-Object -ExpandProperty url -First 1
            }
            catch {
                $url = $null
            }
        }

        $text = if ($count -and $state) {
            "PR: $count $state"
        }
        elseif ($count) {
            "PR: $count connected"
        }
        else {
            'PR: connected'
        }

        [pscustomobject]@{
            Text = $text
            Url  = $url
        }
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
            PullRequest = Get-JiraPullRequestStatus -Issue $issue
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
                $pullRequestText = Format-JiraBoardCellText -Text $card.PullRequest.Text -Width $contentWidth
                $pullRequestDisplay = New-TerminalHyperlink -Text $pullRequestText -Url $card.PullRequest.Url

                $topBorder = '+' + ('-' * $innerWidth) + '+'
                $emptyLine = '|' + (' ' * $innerWidth) + '|'
                $titleLine = '| ' + (Format-JiraBoardCellText -Text ('{0} {1}' -f $card.Key, $summary) -Width $contentWidth) + ' |'
                $assigneeLine = '| ' + (Format-JiraBoardCellText -Text $assigneeDisplay -Width $contentWidth) + ' |'
                $pullRequestLine = '| ' + $pullRequestDisplay + ' |'

                $lines.Add($topBorder)
                $lines.Add($titleLine)
                $lines.Add($assigneeLine)
                $lines.Add($pullRequestLine)
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

Set-Alias sjb Show-JiraBoard
