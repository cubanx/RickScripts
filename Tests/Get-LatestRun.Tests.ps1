$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Functions/Get-LatestRun.ps1"

$script:GhCalls = @()
$script:HostOutput = @()

function git {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Args
    )

    $command = $Args -join ' '

    switch -Regex ($command) {
        '^rev-parse --is-inside-work-tree$' { return 'true' }
        '^branch --show-current$' { return 'main' }
        default { throw "Unexpected git call: $command" }
    }
}

function gh {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Args
    )

    $command = $Args -join ' '
    $script:GhCalls += $command

    switch -Regex ($command) {
        '^pr checks main ' {
            $global:LASTEXITCODE = 1
            return 'no pull requests found for branch "main"'
        }
        '^run list --branch main ' {
            $global:LASTEXITCODE = 0
            return @'
[
  {
    "workflowName": "CI - Quality",
    "displayTitle": "Newest CI",
    "status": "completed",
    "conclusion": "success",
    "startedAt": "2026-07-01T00:00:00Z",
    "updatedAt": "2026-07-01T00:02:00Z"
  },
  {
    "workflowName": "CI - Quality",
    "displayTitle": "Older CI",
    "status": "completed",
    "conclusion": "failure",
    "startedAt": "2026-06-30T00:00:00Z",
    "updatedAt": "2026-06-30T00:02:00Z"
  },
  {
    "workflowName": "Deploy",
    "displayTitle": "Deploy",
    "status": "in_progress",
    "conclusion": null,
    "startedAt": "2026-07-01T00:03:00Z",
    "updatedAt": "2026-07-01T00:03:30Z"
  }
]
'@
        }
        default { throw "Unexpected gh call: $command" }
    }
}

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [object[]]$Object,
        [ConsoleColor]$ForegroundColor,
        [switch]$NoNewline
    )

    $script:HostOutput += ($Object -join ' ')
}

Get-LatestRun -Branch main | Out-Null

if (-not ($script:GhCalls -match '^run list --branch main ')) {
    throw 'Expected main branch fallback to load workflow runs.'
}

$output = $script:HostOutput -join "`n"

if ($output -notmatch 'CI - Quality') {
    throw 'Expected latest CI workflow output.'
}

if ($output -notmatch 'Newest CI') {
    throw 'Expected newest run to be shown.'
}

if ($output -match 'Older CI') {
    throw 'Expected older run for the same workflow to be hidden.'
}

if ($output -notmatch 'Deploy') {
    throw 'Expected in-progress workflow output.'
}
