function Move-JiraItemToBoard {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Issue', 'Key')]
        [string]$IssueKey,

        [int]$BoardId = 1,

        [switch]$DryRun
    )

    begin {
        $scriptPath = Join-Path $PSScriptRoot '..' 'Bash' 'jira-move-item-to-board.sh'
        $resolvedScriptPath = [System.IO.Path]::GetFullPath($scriptPath)

        if (-not (Test-Path $resolvedScriptPath)) {
            throw "Could not find Jira board move script at $resolvedScriptPath"
        }
    }

    process {
        $arguments = @($resolvedScriptPath, $IssueKey)

        if ($PSBoundParameters.ContainsKey('BoardId')) {
            $arguments += @('--board-id', $BoardId)
        }

        if ($DryRun) {
            $arguments += '--dry-run'
        }

        $commandDisplay = 'bash ' + (($arguments | ForEach-Object {
                if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ }
            }) -join ' ')

        if (-not $PSCmdlet.ShouldProcess($IssueKey, "Move Jira issue onto board $BoardId")) {
            return
        }

        Write-Verbose $commandDisplay
        & bash @arguments

        if ($LASTEXITCODE -ne 0) {
            throw "jira-move-item-to-board.sh failed with exit code $LASTEXITCODE"
        }
    }
}

Set-Alias jmib Move-JiraItemToBoard
