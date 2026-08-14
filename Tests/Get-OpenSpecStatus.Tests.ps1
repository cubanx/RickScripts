BeforeAll {
    $module = Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force -PassThru
    $script:ExportedCommands = @($module.ExportedCommands.Keys)
    $script:ExportedAliases = @($module.ExportedAliases.Keys)
    Remove-Module $module -Force

    . "$PSScriptRoot/../Functions/Get-OpenSpecStatus.ps1"

    function openspec {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $command = $Arguments -join ' '
        $script:Calls += "openspec $command"
        $global:LASTEXITCODE = 0
        switch ($command) {
            'list --json' {
                if ($script:Scenario -eq 'list-failure') {
                    $global:LASTEXITCODE = 1
                    return 'OpenSpec list failed'
                }
                if ($script:Scenario -eq 'invalid-list') { return 'not json' }
                return $script:ChangeList | ConvertTo-Json -Depth 4
            }
            default {
                if ($command -notmatch '^status --change (.+)$') { throw "Unexpected openspec call: $command" }
                if ($script:Scenario -eq 'status-failure') {
                    $global:LASTEXITCODE = 1
                    return 'OpenSpec status failed'
                }
                return "Change: $($Matches[1])"
            }
        }
    }

    function git {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $command = $Arguments -join ' '
        $script:Calls += "git $command"
        $global:LASTEXITCODE = 0
        switch ($command) {
            'status --porcelain=v1 --untracked-files=all' { return $script:GitStatus }
            'branch --show-current' { return $script:CurrentBranch }
            'symbolic-ref --quiet --short refs/remotes/origin/HEAD' { return 'origin/main' }
            'merge-base HEAD origin/main' { return 'base-sha' }
            'diff --name-only base-sha HEAD' { return $script:BranchPaths }
            'show --format= --name-only HEAD openspec/changes :(exclude)openspec/changes/archive/**' { return $script:HeadPaths }
            default { throw "Unexpected git call: $command" }
        }
    }

    function fzf {
        $script:PickerItems = @($input)
        return $script:PickerSelection
    }
}

Describe 'Get-OpenSpecStatus' {
    BeforeEach {
        $script:Calls = @()
        $script:Scenario = 'success'
        $script:GitStatus = @()
        $script:CurrentBranch = 'ia/unrelated-work'
        $script:BranchPaths = @()
        $script:HeadPaths = @()
        $script:PickerItems = @()
        $script:PickerSelection = $null
        $script:ChangeList = @{
            changes = @(
                @{ name = 'add-wormhole-routing'; completedTasks = 3; totalTasks = 5; status = 'in-progress' }
                @{ name = 'improve-replicator-rations'; completedTasks = 4; totalTasks = 4; status = 'complete' }
                @{ name = 'use-ephemeral-mongo-for-authenticated-e2e'; completedTasks = 2; totalTasks = 6; status = 'in-progress' }
            )
        }
    }

    It 'is exported by the module' {
        $script:ExportedCommands | Should -Contain 'Get-OpenSpecStatus'
        $script:ExportedAliases | Should -Contain 'goss'
    }

    It 'uses an explicit active change without Git inference' {
        $previousTelemetry = $env:OPENSPEC_TELEMETRY
        $env:OPENSPEC_TELEMETRY = 'restore-me'
        try { $output = @(Get-OpenSpecStatus -Change 'add-wormhole-routing') }
        finally {
            $env:OPENSPEC_TELEMETRY | Should -Be 'restore-me'
            $env:OPENSPEC_TELEMETRY = $previousTelemetry
        }

        $output | Should -Contain 'Change: add-wormhole-routing'
        $output | Should -Contain 'Tasks: 3/5 complete (in-progress)'
        @($script:Calls | Where-Object { $_ -like 'git *' }).Count | Should -Be 0
    }

    It 'rejects an explicit unknown change' {
        { Get-OpenSpecStatus -Change 'commandeer-defiant' } | Should -Throw "*not an active OpenSpec change*"
        @($script:Calls | Where-Object { $_ -like 'openspec status *' }).Count | Should -Be 0
    }

    It 'prefers one dirty OpenSpec change over branch evidence' {
        $script:GitStatus = ' M openspec/changes/add-wormhole-routing/tasks.md'
        $script:CurrentBranch = 'ia/improve-replicator-rations'

        @(Get-OpenSpecStatus) | Should -Contain 'Change: add-wormhole-routing'
        @($script:Calls | Where-Object { $_ -eq 'git branch --show-current' }).Count | Should -Be 0
    }

    It 'uses fzf instead of weaker evidence when multiple dirty changes exist' {
        $script:GitStatus = @(
            ' M openspec/changes/add-wormhole-routing/tasks.md',
            ' M openspec/changes/improve-replicator-rations/design.md'
        )
        $script:CurrentBranch = 'ia/add-wormhole-routing'
        $script:PickerSelection = 'improve-replicator-rations'

        @(Get-OpenSpecStatus) | Should -Contain 'Change: improve-replicator-rations'
        $script:PickerItems | Should -Contain 'add-wormhole-routing'
        @($script:Calls | Where-Object { $_ -eq 'git branch --show-current' }).Count | Should -Be 0
    }

    It 'matches the branch suffix exactly' {
        $script:CurrentBranch = 'ia/add-wormhole-routing'

        @(Get-OpenSpecStatus) | Should -Contain 'Change: add-wormhole-routing'
    }

    It 'uses a unique OpenSpec change from the branch diff' {
        $script:BranchPaths = @(
            'src/routes/wormhole.ts',
            'openspec/changes/add-wormhole-routing/tasks.md'
        )

        @(Get-OpenSpecStatus) | Should -Contain 'Change: add-wormhole-routing'
    }

    It 'uses a unique OpenSpec change touched by HEAD' {
        $script:HeadPaths = 'openspec/changes/improve-replicator-rations/tasks.md'

        @(Get-OpenSpecStatus) | Should -Contain 'Change: improve-replicator-rations'
    }

    It 'uses a unique conservative branch token match' {
        $script:CurrentBranch = 'ia/ephemeral-mongo-authenticated-e2e'

        @(Get-OpenSpecStatus) | Should -Contain 'Change: use-ephemeral-mongo-for-authenticated-e2e'
    }

    It 'does not use branch or commit inference from detached HEAD' {
        $script:CurrentBranch = $null
        $script:HeadPaths = 'openspec/changes/add-wormhole-routing/tasks.md'
        $script:PickerSelection = 'improve-replicator-rations'

        @(Get-OpenSpecStatus) | Should -Contain 'Change: improve-replicator-rations'
        @($script:Calls | Where-Object { $_ -like 'git symbolic-ref *' -or $_ -like 'git show *' }).Count | Should -Be 0
    }

    It 'fails when ambiguity is not resolved by the picker' {
        { Get-OpenSpecStatus } | Should -Throw '*Could not determine the current OpenSpec change*'
        @($script:Calls | Where-Object { $_ -like 'openspec status *' }).Count | Should -Be 0
    }

    It 'fails clearly when ambiguity requires unavailable fzf' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'fzf' }

        { Get-OpenSpecStatus } | Should -Throw '*fzf is unavailable*Use -Change*'
        @($script:Calls | Where-Object { $_ -like 'openspec status *' }).Count | Should -Be 0
    }

    It 'surfaces OpenSpec list and status failures' -TestCases @(
        @{ Scenario = 'list-failure'; Expected = '*Could not list OpenSpec changes*' }
        @{ Scenario = 'invalid-list'; Expected = '*Could not parse OpenSpec change list*' }
        @{ Scenario = 'status-failure'; Expected = '*Could not report OpenSpec status*'; Change = 'add-wormhole-routing' }
    ) {
        param($Scenario, $Expected, $Change)
        $script:Scenario = $Scenario

        { Get-OpenSpecStatus -Change $Change } | Should -Throw $Expected
    }
}
