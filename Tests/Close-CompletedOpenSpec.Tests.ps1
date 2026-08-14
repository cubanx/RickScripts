BeforeAll {
    $module = Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force -PassThru
    $script:ExportedCommands = @($module.ExportedCommands.Keys)
    Remove-Module $module -Force

    . "$PSScriptRoot/../Functions/Close-CompletedOpenSpec.ps1"

    function git {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $command = $Arguments -join ' '
        $script:Calls += "git $command"
        $global:LASTEXITCODE = 0

        if ($script:Scenario -eq 'status-failure' -and $command -eq 'status --porcelain') {
            $global:LASTEXITCODE = 1
            return
        }

        switch ($command) {
            'rev-parse --show-toplevel' { return $script:RepositoryRoot }
            'branch --show-current' { return $script:CurrentBranch }
            'worktree list --porcelain' { return $script:WorktreeList }
            'status --porcelain' { return $script:GitStatus }
            'fetch origin main' { return }
            'rev-list --left-right --count origin/main...HEAD' { return $script:AheadBehind }
            'merge --ff-only origin/main' { return }
            'add -A -- openspec' { return }
            '-c core.whitespace=-blank-at-eof diff --cached --check' { return }
            'diff --cached --name-only' { return @('openspec/changes/older-change/tasks.md', 'openspec/specs/warp-drive/spec.md') }
            'commit -m chore: Archived completed OpenSpecs' { return }
            'rev-parse HEAD' { return '0123456789abcdef' }
            default { throw "Unexpected git call: $command" }
        }
    }

    function openspec {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $command = $Arguments -join ' '
        $script:Calls += "openspec $command"
        $global:LASTEXITCODE = 0

        switch ($command) {
            'list --json' { return $script:ChangeList | ConvertTo-Json -Depth 4 }
            'validate --specs --strict' {
                if ($script:Scenario -eq 'validation-failure') { $global:LASTEXITCODE = 1 }
                return
            }
            'validate --changes --strict' { return }
            default {
                if ($command -notmatch '^archive (.+) -y$') { throw "Unexpected openspec call: $command" }
                $changeName = $Matches[1]
                if ($script:Scenario -like '*archive-false-success*' -and $changeName -eq 'older-change') {
                    return 'Aborted. No files were changed.'
                }

                $source = Join-Path $script:RepositoryRoot "openspec/changes/$changeName"
                $destination = Join-Path $script:RepositoryRoot "openspec/changes/archive/$($script:ArchiveDate)-$changeName"
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                Move-Item -LiteralPath $source -Destination $destination
                return "Change '$changeName' archived."
            }
        }
    }

    function Set-Clipboard {
        [CmdletBinding()]
        param([string]$Value)

        $script:Clipboard = $Value
    }

    function claude {
        param([string]$Prompt)

        $script:ClaudePrompts += $Prompt
        if ($script:Scenario -like '*claude-launch-failure*') {
            throw 'Claude Code did not start.'
        }
    }
}

Describe 'Close-CompletedOpenSpec' {
    BeforeEach {
        $script:Calls = @()
        $script:Clipboard = $null
        $script:ClaudePrompts = @()
        $script:Scenario = 'success'
        $script:CurrentBranch = 'main'
        $script:GitStatus = @()
        $script:AheadBehind = '0 0'
        $script:WorktreeList = @()
        $script:ArchiveDate = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
        $script:RepositoryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "close-openspec-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path (Join-Path $script:RepositoryRoot 'openspec/changes/older-change') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:RepositoryRoot 'openspec/changes/newer-change') -Force | Out-Null
        $script:ChangeList = @{
            changes = @(
                @{ name = 'newer-change'; status = 'complete'; completedTasks = 2; totalTasks = 2; lastModified = '2026-08-05T00:00:00Z' }
                @{ name = 'older-change'; status = 'complete'; completedTasks = 1; totalTasks = 1; lastModified = '2026-08-01T00:00:00Z' }
                @{ name = 'unfinished-change'; status = 'in-progress'; completedTasks = 1; totalTasks = 2; lastModified = '2026-08-06T00:00:00Z' }
            )
        }
        Push-Location -LiteralPath $script:RepositoryRoot
    }

    It 'is exported by the module' {
        $script:ExportedCommands | Should -Contain 'Close-CompletedOpenSpec'
    }

    AfterEach {
        Pop-Location
        Remove-Item -LiteralPath $script:RepositoryRoot -Recurse -Force
    }

    It 'archives every completed change oldest-first, commits once, and returns table-ready rows' {
        $result = @(Close-CompletedOpenSpec)

        $archiveCalls = @($script:Calls | Where-Object { $_ -like 'openspec archive *' })
        $archiveCalls | Should -Be @('openspec archive older-change -y', 'openspec archive newer-change -y')
        $script:Calls | Should -Contain 'git fetch origin main'
        $script:Calls | Should -Contain 'openspec validate --specs --strict'
        $script:Calls | Should -Contain 'openspec validate --changes --strict'
        $script:Calls | Should -Contain 'git add -A -- openspec'
        $script:Calls | Should -Contain 'git commit -m chore: Archived completed OpenSpecs'
        @($script:Calls | Where-Object { $_ -like 'git push *' }).Count | Should -Be 0
        $result.OpenSpec | Should -Be @('older-change', 'newer-change')
        $result.Status | Should -Be @('Committed', 'Committed')
        $result.Details | Should -Be @('0123456789abcdef', '0123456789abcdef')
    }

    It 'fast-forwards a behind main before listing changes' {
        $script:AheadBehind = '1 0'

        Close-CompletedOpenSpec | Out-Null

        [array]::IndexOf($script:Calls, 'git merge --ff-only origin/main') |
            Should -BeLessThan ([array]::IndexOf($script:Calls, 'openspec list --json'))
    }

    It 'suggests the existing main worktree when invoked elsewhere' {
        $script:CurrentBranch = 'rs/feature'
        $script:WorktreeList = @(
            'worktree /tmp/feature', 'HEAD abc', 'branch refs/heads/rs/feature', '',
            'worktree /tmp/main', 'HEAD def', 'branch refs/heads/main', ''
        )

        { Close-CompletedOpenSpec } | Should -Throw '*Set-Location -LiteralPath ''/tmp/main''*'
        @($script:Calls | Where-Object { $_ -match '^(git (fetch|merge|add|commit)|openspec )' }).Count | Should -Be 0
    }

    It 'suggests switching to main from a detached checkout' {
        $script:CurrentBranch = $null

        { Close-CompletedOpenSpec } | Should -Throw '*git switch main*'
        @($script:Calls | Where-Object { $_ -match '^(git (fetch|merge|add|commit)|openspec )' }).Count | Should -Be 0
    }

    It 'stops on dirty or unpublished main without archiving' -TestCases @(
        @{ GitStatus = ' M Functions/SevenOfNine.ps1'; AheadBehind = '0 0'; Expected = '*worktree must be clean*' }
        @{ GitStatus = @(); AheadBehind = '0 1'; Expected = '*ahead of origin/main*' }
        @{ GitStatus = @(); AheadBehind = '1 1'; Expected = '*diverged from origin/main*' }
    ) {
        param($GitStatus, $AheadBehind, $Expected)
        $script:GitStatus = $GitStatus
        $script:AheadBehind = $AheadBehind

        { Close-CompletedOpenSpec } | Should -Throw $Expected
        @($script:Calls | Where-Object { $_ -like 'openspec archive *' -or $_ -like 'git commit *' }).Count | Should -Be 0
    }

    It 'stops when Git status cannot be read' {
        $script:Scenario = 'status-failure'

        { Close-CompletedOpenSpec } | Should -Throw '*Could not read Git status*'
        @($script:Calls | Where-Object { $_ -like 'openspec archive *' -or $_ -like 'git commit *' }).Count | Should -Be 0
    }

    It 'continues after a false-success archive and copies the LLM repair prompt' {
        $script:Scenario = 'archive-false-success'

        { Close-CompletedOpenSpec } | Should -Throw '*LLM repair prompt copied to the clipboard*'
        $script:Clipboard | Should -Match "Repair only the failed OpenSpec changes below in repository '$([regex]::Escape($script:RepositoryRoot))'"
        $script:Clipboard | Should -Match 'older-change: Aborted\. No files were changed\.'
        $script:ClaudePrompts | Should -Be @($script:Clipboard)
        @($script:Calls | Where-Object { $_ -like 'openspec archive *' }) |
            Should -Be @('openspec archive older-change -y', 'openspec archive newer-change -y')
        @($script:Calls | Where-Object { $_ -like 'git commit *' }).Count | Should -Be 0
        @($script:Calls | Where-Object { $_ -like 'git push *' }).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'openspec/changes/older-change') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot "openspec/changes/archive/$($script:ArchiveDate)-newer-change") | Should -BeTrue
    }

    It 'copies and launches the LLM repair prompt when strict validation fails' {
        $script:Scenario = 'validation-failure'

        { Close-CompletedOpenSpec } | Should -Throw '*strict OpenSpec validation failed*'
        $script:Clipboard | Should -Match "Repair strict OpenSpec validation failures in repository '$([regex]::Escape($script:RepositoryRoot))'"
        $script:ClaudePrompts | Should -Be @($script:Clipboard)
        @($script:Calls | Where-Object { $_ -like 'git commit *' }).Count | Should -Be 0
    }

    It 'keeps the clipboard repair prompt when Claude Code cannot start' {
        $script:Scenario = 'archive-false-success-claude-launch-failure'

        { Close-CompletedOpenSpec } | Should -Throw '*LLM repair prompt copied to the clipboard*'
        $script:Clipboard | Should -Not -BeNullOrEmpty
        $script:ClaudePrompts | Should -Be @($script:Clipboard)
    }

    It 'does nothing when no completed changes exist' {
        $script:ChangeList.changes = @($script:ChangeList.changes | Where-Object { $_.status -ne 'complete' })

        $result = Close-CompletedOpenSpec

        @($result) | Should -HaveCount 0
        @($script:Calls | Where-Object { $_ -like 'openspec archive *' -or $_ -like 'git commit *' }).Count | Should -Be 0
    }
}
