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
                throw "Unexpected openspec call: $command"
            }
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
        $script:PickerItems = @()
        $script:PickerSelection = $null
        $script:ChangeList = @{
            root = @{ path = $TestDrive }
            changes = @(
                @{ name = 'add-wormhole-routing'; completedTasks = 3; totalTasks = 5; status = 'in-progress'; lastModified = '2026-09-21T12:00:00.000Z' }
                @{ name = 'improve-replicator-rations'; completedTasks = 4; totalTasks = 4; status = 'complete'; lastModified = '2026-09-23T12:00:00.000Z' }
                @{ name = 'use-ephemeral-mongo-for-authenticated-e2e'; completedTasks = 2; totalTasks = 6; status = 'in-progress'; lastModified = '2026-09-22T12:00:00.000Z' }
            )
        }
        New-Item -ItemType Directory -Force -Path "$TestDrive/openspec/changes/add-wormhole-routing" | Out-Null
        Set-Content -Path "$TestDrive/openspec/changes/add-wormhole-routing/tasks.md" -Value @'
## 1. First Group

- [x] 1.1 First Item
- [x] 1.2 Second Item

## 2. Second Group

- [ ] 2.1 First Item
- [ ] 2.2 Second Item

## 3. Third Group

- [ ] 3.1 First Item
- [ ] 3.2 Second Item
'@
    }

    It 'is exported by the module' {
        $script:ExportedCommands | Should -Contain 'Get-OpenSpecStatus'
        $script:ExportedAliases | Should -Contain 'goss'
    }

    It 'uses an explicit active change' {
        $previousTelemetry = $env:OPENSPEC_TELEMETRY
        $env:OPENSPEC_TELEMETRY = 'restore-me'
        try { $output = @(Get-OpenSpecStatus -Change 'add-wormhole-routing') }
        finally {
            $env:OPENSPEC_TELEMETRY | Should -Be 'restore-me'
            $env:OPENSPEC_TELEMETRY = $previousTelemetry
        }

        $output | Should -Contain 'Change: add-wormhole-routing'
        $output | Should -Contain '## 2. Second Group'
        $output | Should -Contain '- [ ] 2.1 First Item'
        $output | Should -Contain '- [ ] 2.2 Second Item'
        $output | Should -Not -Contain '## 3. Third Group'
        $output | Should -Contain 'Tasks: 3/5 complete (in-progress)'
        $script:PickerItems.Count | Should -Be 0
    }

    It 'shows whole partial groups and stops after the first fully open group' {
        Set-Content -Path "$TestDrive/openspec/changes/add-wormhole-routing/tasks.md" -Value @'
## 1. First Group
- [x] 1.1 First Item
- [ ] 1.2 Second Item
## 2. Second Group
- [x] 2.1 First Item
- [x] 2.2 Second Item
## 3. Third Group
- [ ] 3.1 First Item
- [ ] 3.2 Second Item
## 4. Fourth Group
- [ ] 4.1 Future Item
'@

        $output = @(Get-OpenSpecStatus -Change 'add-wormhole-routing')

        $output | Should -Contain '## 1. First Group'
        $output | Should -Contain '- [x] 1.1 First Item'
        $output | Should -Contain '- [ ] 1.2 Second Item'
        $output | Should -Not -Contain '## 2. Second Group'
        $output | Should -Contain '## 3. Third Group'
        $output | Should -Contain '- [ ] 3.1 First Item'
        $output | Should -Not -Contain '## 4. Fourth Group'
    }

    It 'shows every partial group before the first fully open group' {
        Set-Content -Path "$TestDrive/openspec/changes/add-wormhole-routing/tasks.md" -Value @'
## 1. First Group
- [x] 1.1 Done
- [ ] 1.2 Open
## 2. Second Group
- [ ] 2.1 Open
- [x] 2.2 Done
## 3. Third Group
- [ ] 3.1 Open
## 4. Fourth Group
- [ ] 4.1 Future
'@

        $output = @(Get-OpenSpecStatus -Change 'add-wormhole-routing')

        $output | Should -Contain '## 1. First Group'
        $output | Should -Contain '## 2. Second Group'
        $output | Should -Contain '- [x] 2.2 Done'
        $output | Should -Contain '## 3. Third Group'
        $output | Should -Not -Contain '## 4. Fourth Group'
    }

    It 'rejects an explicit unknown change' {
        { Get-OpenSpecStatus -Change 'commandeer-defiant' } | Should -Throw "*not an active OpenSpec change*"
        @($script:Calls | Where-Object { $_ -like 'openspec status *' }).Count | Should -Be 0
    }

    It 'defaults to the change with the latest OpenSpec modification time' {
        @(Get-OpenSpecStatus) | Should -Contain 'Change: improve-replicator-rations'
        $script:PickerItems.Count | Should -Be 0
    }

    It 'chooses from the active changes when requested' {
        $script:PickerSelection = 'add-wormhole-routing'

        @(Get-OpenSpecStatus -Choose) | Should -Contain 'Change: add-wormhole-routing'
        $script:PickerItems | Should -Be @('improve-replicator-rations', 'use-ephemeral-mongo-for-authenticated-e2e', 'add-wormhole-routing')
    }

    It 'fails when the requested picker is cancelled' {
        { Get-OpenSpecStatus -Choose } | Should -Throw '*No OpenSpec change selected*'
    }

    It 'fails clearly when the requested picker is unavailable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'fzf' }

        { Get-OpenSpecStatus -Choose } | Should -Throw '*fzf is unavailable*'
    }

    It 'rejects combining explicit selection with the picker' {
        { Get-OpenSpecStatus -Change 'add-wormhole-routing' -Choose } | Should -Throw
    }

    It 'surfaces OpenSpec list failures' -TestCases @(
        @{ Scenario = 'list-failure'; Expected = '*Could not list OpenSpec changes*' }
        @{ Scenario = 'invalid-list'; Expected = '*Could not parse OpenSpec change list*' }
    ) {
        param($Scenario, $Expected, $Change)
        $script:Scenario = $Scenario

        { Get-OpenSpecStatus -Change $Change } | Should -Throw $Expected
    }
}
