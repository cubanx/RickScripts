BeforeAll {
    . "$PSScriptRoot/../Functions/Get-LatestRun.ps1"

    function git {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

        switch -Regex ($Args -join ' ') {
            '^rev-parse --is-inside-work-tree$' { return 'true' }
            '^branch --show-current$' { return 'main' }
            default { throw "Unexpected git call: $($Args -join ' ')" }
        }
    }

    function gh {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

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
            [Parameter(Position = 0, ValueFromRemainingArguments)][object[]]$Object,
            [ConsoleColor]$ForegroundColor,
            [switch]$NoNewline
        )
        $script:HostOutput += ($Object -join ' ')
    }
}

Describe 'Get-LatestRun' {
    BeforeEach {
        $script:GhCalls = @()
        $script:HostOutput = @()
    }

    It 'falls back to the newest workflow run for the main branch' {
        Get-LatestRun -Branch main | Out-Null
        $output = $script:HostOutput -join "`n"

        ($script:GhCalls -join "`n") | Should -Match '(?m)^run list --branch main '
        $output | Should -Match 'CI - Quality'
        $output | Should -Match 'Newest CI'
        $output | Should -Not -Match 'Older CI'
        $output | Should -Match 'Deploy'
    }
}
