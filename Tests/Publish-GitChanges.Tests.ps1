BeforeAll {
    $module = Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force -PassThru
    $script:ExportedCommands = @($module.ExportedCommands.Keys)
    $script:ExportedAliases = @($module.ExportedAliases.Keys)
    Remove-Module $module -Force

    . "$PSScriptRoot/../Functions/Get-CodexChangeSummary.ps1"
    . "$PSScriptRoot/../Functions/Publish-GitChanges.ps1"

    $script:GitExecutable = Get-Command git -CommandType Application | Select-Object -First 1 -ExpandProperty Source

    function codex {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $script:Calls += "codex $($Arguments -join ' ')"
        if ($script:Scenario -eq 'codex-failure') {
            $global:LASTEXITCODE = 1
            return 'Codex failed'
        }

        $outputIndex = [Array]::IndexOf($Arguments, '--output-last-message')
        @{
            CommitMessage = $script:CommitMessage
            HumanTitle = 'Publish Git changes'
            WhatChanged = 'Added publishing.'
            Why = 'Make the workflow repeatable.'
            UserImpact = 'Faster publishing.'
            DeveloperImpact = 'One command.'
            Validation = 'Mocked test.'
        } | ConvertTo-Json | Set-Content -LiteralPath $Arguments[$outputIndex + 1] -Encoding UTF8
        $global:LASTEXITCODE = 0
    }

    function git {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $command = $Arguments -join ' '
        $script:Calls += "git $command"
        if ($script:Scenario -eq 'origin-failure' -and $command -eq 'ls-remote --symref origin HEAD') {
            $global:LASTEXITCODE = 1
            return 'origin is inaccessible'
        }
        if ($script:Scenario -eq 'diff-check-failure' -and $command -eq '-c core.whitespace=-blank-at-eof diff --cached --check') {
            $global:LASTEXITCODE = 1
            return 'whitespace error'
        }

        $global:LASTEXITCODE = 0
        switch -Wildcard ($command) {
            'rev-parse --show-toplevel' { return $script:RepositoryRoot }
            'ls-remote --symref origin HEAD' { return @("ref: refs/heads/main`tHEAD", "0123456789abcdef`tHEAD") }
            'branch --show-current' { return $script:CurrentBranch }
            'status --porcelain' {
                if ($script:Scenario -in @('openspec-only', 'openspec-with-committed-code')) { return '?? openspec/changes/add-daily-dash-renewals/proposal.md' }
                if ($script:Scenario -eq 'mixed-openspec') { return @('?? openspec/changes/add-daily-dash-renewals/proposal.md', ' M Functions/Publish-GitChanges.ps1') }
                if ($script:Scenario -eq 'multiple-openspec') { return @('?? openspec/changes/add-daily-dash-renewals/proposal.md', '?? openspec/changes/add-other-change/proposal.md') }
                if ($script:Scenario -ne 'clean') { return @(' M changed.ps1', '?? new.ps1') }
                return
            }
            'switch -c *' { return }
            'add -A' { return }
            '-c core.whitespace=-blank-at-eof diff --cached --check' { return }
            'diff --cached --name-status' { if ($script:Scenario -eq 'empty-staged') { return }; return "M`tchanged.ps1" }
            'commit -m *' { return }
            'push -u origin *' { return }
            'rev-parse HEAD' { return '0123456789abcdef' }
            'status --short' { return }
            default { throw "Unexpected git call: $command" }
        }
    }

    function gh {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $command = $Arguments -join ' '
        $script:Calls += "gh $command"
        if ($script:Scenario -eq 'gh-failure' -and $command -like 'pr list *') {
            $global:LASTEXITCODE = 1
            return 'GitHub query failed'
        }

        $global:LASTEXITCODE = 0
        if ($script:Scenario -in @('existing-pr', 'mismatched-existing-pr') -and $command -like 'pr list *') {
            return '[{"number":42,"url":"https://github.com/example/data-warehouse/pull/42","title":"Existing PR title"}]'
        }
        if ($command -like 'pr list *') { return '[]' }
        if ($command -like 'pr create *') {
            $bodyIndex = [Array]::IndexOf($Arguments, '--body-file')
            $script:LastBodyPath = $Arguments[$bodyIndex + 1]
            $script:LastBody = Get-Content -LiteralPath $script:LastBodyPath -Raw
            return 'https://github.com/example/data-warehouse/pull/42'
        }
        if ($command -match '^pr edit https://github\.com/example/data-warehouse/pull/42 --title \[dw-#42\] ') { return }
        throw "Unexpected gh call: $command"
    }
}

Describe 'Publish-GitChanges' {
    BeforeEach {
        $script:Calls = @()
        $script:Scenario = 'success'
        $script:CurrentBranch = 'main'
        $script:CommitMessage = 'feat(scope)!: Publish Git changes'
        $script:LastBody = $null
        $script:LastBodyPath = $null
        $script:RepositoryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "rickscripts-publish-$([guid]::NewGuid())/data-warehouse"
    }

    It 'exports only the supported publishing surface' {
        $script:ExportedCommands | Should -Contain 'Publish-GitChanges'
        $script:ExportedCommands | Should -Contain 'Get-CodexChangeSummary'
        $script:ExportedAliases | Should -Contain 'yeet'
        $script:ExportedCommands | Should -Not -Contain 'New-MergeRequest'
        $script:ExportedCommands | Should -Not -Contain 'Open-MergeRequest'
        $script:ExportedAliases | Should -Not -Contain 'nmr'
        $script:ExportedAliases | Should -Not -Contain 'omr'

        $publisherParameters = (Get-Command Publish-GitChanges).Parameters.Keys
        $publisherParameters | Should -Not -Contain 'Path'
        $publisherParameters | Should -Not -Contain 'All'
        $publisherParameters | Should -Not -Contain 'Message'
        (Get-GitPublishingSlug -RepositoryName 'RickScripts') | Should -Be 'rs'
        (Get-GitPublishingSlug -RepositoryName 'yoda') | Should -Be 'ia'
    }

    It 'allows blank lines at EOF but rejects trailing whitespace' {
        $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "rickscripts-diff-check-$([guid]::NewGuid())"
        try {
            New-Item -ItemType Directory -Path $testRoot | Out-Null
            & $script:GitExecutable -C $testRoot init --quiet
            [System.IO.File]::WriteAllText((Join-Path $testRoot 'blank.md'), "content`n`n")
            & $script:GitExecutable -C $testRoot add blank.md
            & $script:GitExecutable -C $testRoot -c core.whitespace=-blank-at-eof diff --cached --check
            $LASTEXITCODE | Should -Be 0

            [System.IO.File]::WriteAllText((Join-Path $testRoot 'trailing.md'), "content  `n")
            & $script:GitExecutable -C $testRoot add trailing.md
            $null = & $script:GitExecutable -C $testRoot -c core.whitespace=-blank-at-eof diff --cached --check 2>&1
            $LASTEXITCODE | Should -Not -Be 0
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }

    It 'gets one constrained read-only Codex summary' {
        $summary = Get-CodexChangeSummary

        foreach ($field in @('CommitMessage', 'HumanTitle', 'PullRequestTitle', 'WhatChanged', 'Why', 'UserImpact', 'DeveloperImpact', 'Validation')) {
            [string]$summary.$field | Should -Not -BeNullOrEmpty
        }
        $codexCalls = @($script:Calls | Where-Object { $_ -like 'codex *' })
        $codexCalls.Count | Should -Be 1
        $codexCalls[0] | Should -Match 'exec -m gpt-5\.6-luna -c model_reasoning_effort="low" --ephemeral --sandbox read-only --output-schema .+ --output-last-message .+'
        $codexCalls[0] | Should -Match 'current branch relative to origin.s default branch'
        $codexCalls[0] | Should -Match 'staged, unstaged, and untracked worktree changes'
        $codexCalls[0] | Should -Match 'Follow repository AGENTS.md instructions'
        $codexCalls[0] | Should -Match 'Do not mutate anything'
        @($script:Calls | Where-Object { $_ -match '^(git|gh) ' }).Count | Should -Be 0
    }

    It 'creates a numbered draft pull request from the default branch' {
        $result = Publish-GitChanges

        $result.Branch | Should -Be 'dw/publish-git-changes'
        $result.Title | Should -Be '[dw-#42] Publish Git changes'
        ($script:Calls -join "`n") | Should -Match 'git ls-remote --symref origin HEAD'
        ($script:Calls -join "`n") | Should -Match 'git add -A'
        $script:Calls | Should -Contain 'git -c core.whitespace=-blank-at-eof diff --cached --check'
        @($script:Calls | Where-Object { $_ -like 'codex *' }).Count | Should -Be 1
        ($script:Calls -join "`n") | Should -Match 'gh pr create .*--draft'
        foreach ($section in @('## What changed', '## Why', '## User impact', '## Developer impact', '## Validation', 'git diff --cached --check passed.')) {
            $script:LastBody | Should -Match ([regex]::Escape($section))
        }
        $script:LastBodyPath | Should -Not -Exist
    }

    It 'uses deterministic metadata for a single OpenSpec change on the default branch' {
        $script:Scenario = 'openspec-only'
        $proposalPath = Join-Path $script:RepositoryRoot 'openspec/changes/add-daily-dash-renewals/proposal.md'
        try {
            New-Item -ItemType Directory -Path (Split-Path -Parent $proposalPath) -Force | Out-Null
            @'
## Why

Daily renewal signals are hard to spot.

## What Changes

- Add a daily renewal dashboard.

## Impact

- Account teams get a focused renewal view.
'@ | Set-Content -LiteralPath $proposalPath -Encoding UTF8

            $result = Publish-GitChanges

            $result.Branch | Should -Be 'dw/add-daily-dash-renewals'
            $result.Title | Should -Be '[dw-#42] Add daily dash renewals OpenSpec'
            $script:Calls | Should -Contain 'git commit -m docs: add daily dash renewals OpenSpec'
            @($script:Calls | Where-Object { $_ -like 'codex *' }).Count | Should -Be 0
            foreach ($bodyText in @('Daily renewal signals are hard to spot.', '- Add a daily renewal dashboard.', '- Account teams get a focused renewal view.', 'Not run by yeet.')) {
                $script:LastBody | Should -Match ([regex]::Escape($bodyText))
            }
            $script:LastBody | Should -Not -Match 'specification-only|Capture the proposed change'
        }
        finally {
            Remove-Item -LiteralPath (Split-Path -Parent $script:RepositoryRoot) -Recurse -Force
        }
    }

    It 'summarizes the complete PR when only OpenSpec files remain dirty on a feature branch' {
        $script:Scenario = 'openspec-with-committed-code'
        $script:CurrentBranch = 'dw/implemented-change'

        $result = Publish-GitChanges

        @($script:Calls | Where-Object { $_ -like 'codex *' }).Count | Should -Be 1
        $result.Branch | Should -Be 'dw/implemented-change'
    }

    It 'uses Codex for mixed OpenSpec changes' {
        $script:Scenario = 'mixed-openspec'

        $result = Publish-GitChanges

        @($script:Calls | Where-Object { $_ -like 'codex *' }).Count | Should -Be 1
        $result.Branch | Should -Be 'dw/publish-git-changes'
    }

    It 'uses Codex for multiple OpenSpec changes' {
        $script:Scenario = 'multiple-openspec'

        $result = Publish-GitChanges

        @($script:Calls | Where-Object { $_ -like 'codex *' }).Count | Should -Be 1
        $result.Branch | Should -Be 'dw/publish-git-changes'
    }

    It 'retains the current feature branch' {
        $script:CurrentBranch = 'dw/existing-work'

        $result = Publish-GitChanges

        $result.Branch | Should -Be 'dw/existing-work'
        @($script:Calls | Where-Object { $_ -like 'git switch *' }).Count | Should -Be 0
    }

    It 'creates a derived branch from detached HEAD' {
        $script:CurrentBranch = $null

        $result = Publish-GitChanges

        $result.Branch | Should -Be 'dw/publish-git-changes'
        @($script:Calls | Where-Object { $_ -eq 'git switch -c dw/publish-git-changes' }).Count | Should -Be 1
    }

    It 'creates an explicit ready branch without a draft pull request' {
        $result = Publish-GitChanges -BranchName 'dw/explicit' -Ready

        $result.Branch | Should -Be 'dw/explicit'
        @($script:Calls | Where-Object { $_ -eq 'git switch -c dw/explicit' }).Count | Should -Be 1
        ($script:Calls -join "`n") | Should -Not -Match 'gh pr create .*--draft'
    }

    It 'uses an explicit base branch' {
        $result = Publish-GitChanges -BaseBranch 'develop'

        $result.Branch | Should -Be 'dw/publish-git-changes'
        ($script:Calls -join "`n") | Should -Match 'gh pr create --base develop --head dw/publish-git-changes'
    }

    It 'updates an existing pull request without creating, editing, or switching' {
        $script:Scenario = 'existing-pr'
        $script:CurrentBranch = 'dw/existing-work'

        $result = Publish-GitChanges

        $result.Branch | Should -Be 'dw/existing-work'
        $result.CommitSha | Should -Be '0123456789abcdef'
        $result.Url | Should -Be 'https://github.com/example/data-warehouse/pull/42'
        $result.Title | Should -Be 'Existing PR title'
        foreach ($requiredCall in @('git add -A', 'git -c core.whitespace=-blank-at-eof diff --cached --check', 'git commit -m feat(scope)!: Publish Git changes', 'git push -u origin dw/existing-work')) {
            $script:Calls | Should -Contain $requiredCall
        }
        @($script:Calls | Where-Object { $_ -like 'codex *' }).Count | Should -Be 1
        @($script:Calls | Where-Object { $_ -like 'gh pr create *' -or $_ -like 'gh pr edit *' -or $_ -like 'git switch *' }).Count | Should -Be 0
    }

    It 'stops before mutation for a pull request on another branch' {
        $script:Scenario = 'mismatched-existing-pr'
        $script:CurrentBranch = 'dw/current-work'

        { Publish-GitChanges -BranchName 'dw/other-work' | Out-Null } | Should -Throw

        @($script:Calls | Where-Object { $_ -match '^git (switch|add|commit|push)' }).Count | Should -Be 0
        @($script:Calls | Where-Object { $_ -like 'gh pr list *' }).Count | Should -Be 1
    }

    It 'stops safely for <Scenario>' -TestCases @(
        @{ Scenario = 'origin-failure' }
        @{ Scenario = 'gh-failure' }
        @{ Scenario = 'clean' }
        @{ Scenario = 'empty-staged' }
        @{ Scenario = 'diff-check-failure' }
        @{ Scenario = 'codex-failure' }
    ) {
        param($Scenario)
        $script:Scenario = $Scenario

        { Publish-GitChanges | Out-Null } | Should -Throw

        if ($Scenario -eq 'gh-failure') {
            @($script:Calls | Where-Object { $_ -like 'gh pr list *' }).Count | Should -Be 1
        }
        if ($Scenario -in @('empty-staged', 'diff-check-failure')) {
            @($script:Calls | Where-Object { $_ -match '^git (commit|push)' }).Count | Should -Be 0
        }
        else {
            @($script:Calls | Where-Object { $_ -match '^git (switch|add|commit|push)' }).Count | Should -Be 0
        }
        if ($Scenario -eq 'codex-failure') {
            @($script:Calls | Where-Object { $_ -like 'codex *' }).Count | Should -Be 1
        }
    }
}
