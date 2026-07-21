function Invoke-CodexGitPublishingCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & $FileName @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = if ($output) { ($output | Out-String).Trim() } else { "$FileName $($Arguments -join ' ') failed." }
        throw $message
    }

    return @($output)
}

function Remove-CodexGitPublishingTemporaryFile {
    param(
        [string]$Path,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to remove temporary $Label file."
    }
}

function Get-CodexChangeSummary {
    <#
    .SYNOPSIS
    Generates a read-only structured summary of the current Git change.

    .EXAMPLE
    Get-CodexChangeSummary

    Uses ephemeral, read-only Codex execution. No Git or GitHub mutation is performed.
    #>
    [CmdletBinding()]
    param()

    $schemaPath = $null
    $outputPath = $null

    try {
        $schemaPath = [System.IO.Path]::GetTempFileName()
        $outputPath = [System.IO.Path]::GetTempFileName()
        @{
            type = 'object'
            additionalProperties = $false
            required = @('CommitMessage', 'HumanTitle', 'WhatChanged', 'Why', 'UserImpact', 'DeveloperImpact', 'Validation')
            properties = @{
                CommitMessage = @{ type = 'string' }
                HumanTitle = @{ type = 'string' }
                WhatChanged = @{ type = 'string' }
                Why = @{ type = 'string' }
                UserImpact = @{ type = 'string' }
                DeveloperImpact = @{ type = 'string' }
                Validation = @{ type = 'string' }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $schemaPath -Encoding UTF8

        Invoke-CodexGitPublishingCommand -FileName 'codex' -Arguments @(
            'exec', '-m', 'gpt-5.6-luna', '-c', 'model_reasoning_effort="low"', '--ephemeral', '--sandbox', 'read-only', '--output-schema', $schemaPath,
            '--output-last-message', $outputPath,
            'Inspect the complete current worktree diff, including staged, unstaged, and untracked changes. Follow repository AGENTS.md instructions. Return JSON only: a terse spaced conventional CommitMessage, a human PR title, grounded what/why/user/developer impact, and validation claims only for evidence actually present. Do not mutate anything.'
        ) | Out-Null

        $json = Get-Content -LiteralPath $outputPath -Raw
        $summary = $json | ConvertFrom-Json -ErrorAction Stop
        foreach ($field in @('CommitMessage', 'HumanTitle', 'WhatChanged', 'Why', 'UserImpact', 'DeveloperImpact', 'Validation')) {
            if (-not ($summary.PSObject.Properties.Name -contains $field) -or [string]::IsNullOrWhiteSpace([string]$summary.$field)) {
                throw "Codex summary is missing required field '$field'."
            }
        }

        return [PSCustomObject]@{
            CommitMessage = [string]$summary.CommitMessage
            PullRequestTitle = [string]$summary.HumanTitle
            HumanTitle = [string]$summary.HumanTitle
            WhatChanged = [string]$summary.WhatChanged
            Why = [string]$summary.Why
            UserImpact = [string]$summary.UserImpact
            DeveloperImpact = [string]$summary.DeveloperImpact
            Validation = [string]$summary.Validation
        }
    }
    finally {
        Remove-CodexGitPublishingTemporaryFile -Path $schemaPath -Label 'Codex schema'
        Remove-CodexGitPublishingTemporaryFile -Path $outputPath -Label 'Codex output'
    }
}
