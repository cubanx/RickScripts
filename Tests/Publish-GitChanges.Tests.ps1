$ErrorActionPreference = 'Stop'

$module = Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force -PassThru
if ($module.ExportedCommands.Keys -notcontains 'Publish-GitChanges' -or $module.ExportedCommands.Keys -notcontains 'Get-CodexChangeSummary') { throw 'Expected new commands to be exported.' }
if ($module.ExportedAliases.Keys -notcontains 'yeet') { throw 'Expected yeet to be exported.' }
if ($module.ExportedCommands.Keys -contains 'New-MergeRequest' -or $module.ExportedCommands.Keys -contains 'Open-MergeRequest' -or $module.ExportedAliases.Keys -contains 'nmr' -or $module.ExportedAliases.Keys -contains 'omr') { throw 'Retired merge-request entrypoints must not be exported.' }
Remove-Module $module -Force

. "$PSScriptRoot/../Functions/Get-CodexChangeSummary.ps1"
. "$PSScriptRoot/../Functions/Publish-GitChanges.ps1"

$publisherParameters = (Get-Command Publish-GitChanges).Parameters.Keys
if ($publisherParameters -contains 'Path' -or $publisherParameters -contains 'All' -or $publisherParameters -contains 'Message') { throw 'Publish-GitChanges must not expose Path, All, or Message parameters.' }
if ((Get-GitPublishingSlug -RepositoryName 'RickScripts') -ne 'rs') { throw 'Expected CamelCase repository slug.' }

$gitExecutable = Get-Command git -CommandType Application | Select-Object -First 1 -ExpandProperty Source
$whitespaceTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "rickscripts-diff-check-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path $whitespaceTestRoot | Out-Null
    & $gitExecutable -C $whitespaceTestRoot init --quiet
    [System.IO.File]::WriteAllText((Join-Path $whitespaceTestRoot 'blank.md'), "content`n`n")
    & $gitExecutable -C $whitespaceTestRoot add blank.md
    & $gitExecutable -C $whitespaceTestRoot -c core.whitespace=-blank-at-eof diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw 'Blank lines at EOF must pass the softened diff check.' }
    [System.IO.File]::WriteAllText((Join-Path $whitespaceTestRoot 'trailing.md'), "content  `n")
    & $gitExecutable -C $whitespaceTestRoot add trailing.md
    $null = & $gitExecutable -C $whitespaceTestRoot -c core.whitespace=-blank-at-eof diff --cached --check 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'Trailing whitespace must still fail the softened diff check.' }
}
finally {
    Remove-Item -LiteralPath $whitespaceTestRoot -Recurse -Force
}

$script:Calls = @()
$script:Scenario = 'success'
$script:CurrentBranch = 'main'
$script:CommitMessage = 'feat(scope)!: Publish Git changes'
$script:LastBody = $null
$script:LastBodyPath = $null

function Assert-NoGitMutation {
    param([string]$Message)
    if (@($script:Calls | Where-Object { $_ -match '^git (switch|add|commit|push)' }).Count -ne 0) { throw $Message }
}

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
        'rev-parse --show-toplevel' { return '/tmp/data-warehouse' }
        'ls-remote --symref origin HEAD' { return @("ref: refs/heads/main`tHEAD", "0123456789abcdef`tHEAD") }
        'branch --show-current' { return $script:CurrentBranch }
        'status --porcelain' {
            if ($script:Scenario -eq 'openspec-only') { return '?? openspec/changes/add-daily-dash-renewals/proposal.md' }
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
    if ($script:Scenario -in @('existing-pr', 'mismatched-existing-pr') -and $command -like 'pr list *') { return '[{"number":42,"url":"https://github.com/example/data-warehouse/pull/42","title":"Existing PR title"}]' }
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

$script:Calls = @()
$summary = Get-CodexChangeSummary
$summaryFields = @('CommitMessage', 'HumanTitle', 'PullRequestTitle', 'WhatChanged', 'Why', 'UserImpact', 'DeveloperImpact', 'Validation')
foreach ($field in $summaryFields) { if ([string]::IsNullOrWhiteSpace([string]$summary.$field)) { throw "Expected summary field '$field'." } }
$codexCall = @($script:Calls | Where-Object { $_ -like 'codex *' })
if ($codexCall.Count -ne 1 -or $codexCall[0] -notmatch 'exec -m gpt-5\.6-luna -c model_reasoning_effort="low" --ephemeral --sandbox read-only --output-schema .+ --output-last-message .+' -or $codexCall[0] -notmatch 'Inspect the complete current worktree diff' -or $codexCall[0] -notmatch 'Follow repository AGENTS.md instructions' -or $codexCall[0] -notmatch 'Do not mutate anything') { throw 'Expected constrained, explicit Codex invocation.' }
if (@($script:Calls | Where-Object { $_ -match '^(git|gh) ' }).Count -ne 0) { throw 'Standalone summary must not invoke Git or GitHub.' }

$script:Scenario = 'success'
$script:CurrentBranch = 'main'
$script:Calls = @()
$result = Publish-GitChanges
if ($result.Branch -ne 'dw/publish-git-changes' -or $result.Title -ne '[dw-#42] Publish Git changes') { throw 'Expected numbered draft PR result.' }
if (($script:Calls -join "`n") -notmatch 'git ls-remote --symref origin HEAD') { throw 'Expected read-only origin accessibility check.' }
if (($script:Calls -join "`n") -notmatch 'git add -A') { throw 'Expected complete-tree staging.' }
if ($script:Calls -notcontains 'git -c core.whitespace=-blank-at-eof diff --cached --check') { throw 'Expected cached diff check to ignore blank lines at EOF.' }
if (($script:Calls | Where-Object { $_ -like 'codex *' }).Count -ne 1) { throw 'Expected exactly one Codex summary call.' }
if (($script:Calls -join "`n") -notmatch 'gh pr create .*--draft') { throw 'Expected draft PR creation.' }
foreach ($section in @('## What changed', '## Why', '## User impact', '## Developer impact', '## Validation', 'git diff --cached --check passed.')) {
    if ($script:LastBody -notmatch [regex]::Escape($section)) { throw "Expected PR body section '$section'." }
}
if (Test-Path -LiteralPath $script:LastBodyPath) { throw 'Expected temporary PR body cleanup.' }

$script:Scenario = 'openspec-only'
$script:CurrentBranch = $null
$script:Calls = @()
$script:LastBody = $null
$result = Publish-GitChanges
if ($result.Branch -ne 'dw/add-daily-dash-renewals' -or $result.Title -ne '[dw-#42] Add daily dash renewals OpenSpec') { throw 'Expected deterministic OpenSpec-only branch and title.' }
if ($script:Calls -notcontains 'git commit -m docs: add daily dash renewals OpenSpec') { throw 'Expected deterministic OpenSpec-only commit message.' }
if (@($script:Calls | Where-Object { $_ -like 'codex *' }).Count -ne 0) { throw 'OpenSpec-only publishing must not invoke Codex.' }
foreach ($bodyText in @('specification-only', 'Not run; this is a specification-only change.')) {
    if ($script:LastBody -notmatch [regex]::Escape($bodyText)) { throw "Expected deterministic OpenSpec PR body text '$bodyText'." }
}
if ($script:LastBody -match 'strict validation') { throw 'OpenSpec-only PR body must not claim strict validation ran.' }

$script:Scenario = 'mixed-openspec'
$script:CurrentBranch = 'main'
$script:Calls = @()
$result = Publish-GitChanges
if (@($script:Calls | Where-Object { $_ -like 'codex *' }).Count -ne 1 -or $result.Branch -ne 'dw/publish-git-changes') { throw 'Mixed OpenSpec changes must retain the Codex fallback.' }

$script:Scenario = 'multiple-openspec'
$script:CurrentBranch = 'main'
$script:Calls = @()
$result = Publish-GitChanges
if (@($script:Calls | Where-Object { $_ -like 'codex *' }).Count -ne 1 -or $result.Branch -ne 'dw/publish-git-changes') { throw 'Multiple OpenSpec changes must retain the Codex fallback.' }

$script:Scenario = 'success'
$script:CurrentBranch = 'dw/existing-work'
$script:Calls = @()
$result = Publish-GitChanges
if ($result.Branch -ne 'dw/existing-work' -or @($script:Calls | Where-Object { $_ -like 'git switch *' }).Count -ne 0) { throw 'Expected existing feature branch to be retained.' }

$script:Scenario = 'success'
$script:CurrentBranch = $null
$script:Calls = @()
$result = Publish-GitChanges
if ($result.Branch -ne 'dw/publish-git-changes' -or @($script:Calls | Where-Object { $_ -eq 'git switch -c dw/publish-git-changes' }).Count -ne 1) { throw 'Expected detached HEAD to create derived branch.' }

$script:Scenario = 'success'
$script:CurrentBranch = 'main'
$script:Calls = @()
$result = Publish-GitChanges -BranchName 'dw/explicit' -Ready
if ($result.Branch -ne 'dw/explicit' -or @($script:Calls | Where-Object { $_ -eq 'git switch -c dw/explicit' }).Count -ne 1) { throw 'Expected explicit branch name to be created.' }
if (($script:Calls -join "`n") -match 'gh pr create .*--draft') { throw 'Ready publishing must omit --draft.' }

$script:Scenario = 'base-branch'
$script:CurrentBranch = 'main'
$script:Calls = @()
$result = Publish-GitChanges -BaseBranch 'develop'
if ($result.Branch -ne 'dw/publish-git-changes' -or ($script:Calls -join "`n") -notmatch 'gh pr create --base develop --head dw/publish-git-changes') { throw 'Expected explicit base branch to create a derived branch and reach GitHub.' }

$script:Scenario = 'existing-pr'
$script:CurrentBranch = 'dw/existing-work'
$script:Calls = @()
$result = Publish-GitChanges
if ($result.Branch -ne 'dw/existing-work' -or $result.CommitSha -ne '0123456789abcdef' -or $result.Url -ne 'https://github.com/example/data-warehouse/pull/42' -or $result.Title -ne 'Existing PR title') { throw 'Expected existing PR update result.' }
foreach ($requiredCall in @('git add -A', 'git -c core.whitespace=-blank-at-eof diff --cached --check', 'git commit -m feat(scope)!: Publish Git changes', 'git push -u origin dw/existing-work')) {
    if ($script:Calls -notcontains $requiredCall) { throw "Expected existing PR update to call '$requiredCall'." }
}
if (@($script:Calls | Where-Object { $_ -like 'codex *' }).Count -ne 1) { throw 'Expected exactly one Codex summary call for existing PR update.' }
if (@($script:Calls | Where-Object { $_ -like 'gh pr create *' -or $_ -like 'gh pr edit *' -or $_ -like 'git switch *' }).Count -ne 0) { throw 'Existing PR update must not create, edit, or switch.' }

$script:Scenario = 'mismatched-existing-pr'
$script:CurrentBranch = 'dw/current-work'
$script:Calls = @()
try {
    Publish-GitChanges -BranchName 'dw/other-work' | Out-Null
    throw 'Expected mismatched existing PR to stop publishing.'
}
catch {
    if ($_.Exception.Message -like 'Expected mismatched existing PR*') { throw }
}
Assert-NoGitMutation -Message 'Mismatched existing PR must stop before mutation.'
if (@($script:Calls | Where-Object { $_ -like 'gh pr list *' }).Count -ne 1) { throw 'Expected one existing PR query for mismatched branch.' }

foreach ($failure in @('origin-failure', 'gh-failure', 'clean', 'empty-staged', 'diff-check-failure', 'codex-failure')) {
    $script:Scenario = $failure
    $script:CurrentBranch = 'main'
    $script:Calls = @()
    try {
        Publish-GitChanges | Out-Null
        throw "Expected '$failure' to stop publishing."
    }
    catch {
        if ($_.Exception.Message -like "Expected '$failure'*") { throw }
    }
    if ($failure -eq 'gh-failure' -and @($script:Calls | Where-Object { $_ -like 'gh pr list *' }).Count -ne 1) { throw 'Expected GitHub query failure before mutation.' }
    if ($failure -in @('empty-staged', 'diff-check-failure')) {
        if (@($script:Calls | Where-Object { $_ -match '^git (commit|push)' }).Count -ne 0) { throw "'$failure' must not commit or push." }
    }
    else {
        Assert-NoGitMutation -Message "'$failure' must not mutate Git."
    }
}

if (@($script:Calls | Where-Object { $_ -like 'codex *' }).Count -ne 1) { throw 'Codex failure test should invoke Codex once before stopping.' }
