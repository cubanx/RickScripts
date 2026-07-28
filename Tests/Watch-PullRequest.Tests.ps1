$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Functions/Watch-PullRequest.ps1"

if ((Get-Alias wpr -ErrorAction SilentlyContinue).Definition -ne 'Watch-PullRequest') { throw 'Expected wpr to alias Watch-PullRequest.' }

$script:Calls = @()
$script:Locations = @()
$script:Scenario = 'success'
$script:ViewCount = 0

function gh {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

    $command = $Arguments -join ' '
    $script:Calls += $command
    $script:Locations += (Get-Location).Path
    $global:LASTEXITCODE = 0

    if ($command -eq 'pr view 42 --json headRefOid --jq .headRefOid') {
        $script:ViewCount++
        if ($script:Scenario -eq 'changed-head' -and $script:ViewCount -gt 1) {
            return 'fedcba9876543210'
        }
        return '0123456789abcdef'
    }
    if ($command -eq 'pr checks 42 --watch --fail-fast') {
        if ($script:Scenario -eq 'failed-checks') { $global:LASTEXITCODE = 1 }
        return
    }
    if ($command -eq 'pr merge 42 --merge --match-head-commit 0123456789abcdef') {
        if ($script:Scenario -eq 'failed-merge') { $global:LASTEXITCODE = 1 }
        return
    }
    if ($command -eq 'pr merge 42 --merge --match-head-commit fedcba9876543210') { return }

    throw "Unexpected gh call: $command"
}

Watch-PullRequest 42
if ($script:Calls -notcontains 'pr merge 42 --merge --match-head-commit 0123456789abcdef') { throw 'Expected a normal merge pinned to the checked head.' }
if (($script:Calls -join ' ') -match '(?:^|\s)--admin(?:\s|$)') { throw 'Watch-PullRequest must never bypass merge requirements.' }

$script:Scenario = 'failed-checks'
$script:Calls = @()
$script:ViewCount = 0
try {
    Watch-PullRequest 42
    throw 'Expected failed checks to stop the merge.'
}
catch {
    if ($_.Exception.Message -eq 'Expected failed checks to stop the merge.') { throw }
}
if (@($script:Calls | Where-Object { $_ -like 'pr merge *' }).Count -ne 0) { throw 'Failed checks must not attempt a merge.' }

$script:Scenario = 'failed-merge'
$script:Calls = @()
$script:ViewCount = 0
try {
    Watch-PullRequest 42
    throw 'Expected a refused merge to surface as an error.'
}
catch {
    if ($_.Exception.Message -eq 'Expected a refused merge to surface as an error.') { throw }
}

$script:Scenario = 'changed-head'
$script:Calls = @()
$script:ViewCount = 0
Watch-PullRequest 42
if (@($script:Calls | Where-Object { $_ -eq 'pr checks 42 --watch --fail-fast' }).Count -ne 2) { throw 'A changed head must restart the check watch.' }
if ($script:Calls -contains 'pr merge 42 --merge --match-head-commit 0123456789abcdef') { throw 'The superseded head must not be merged.' }
if ($script:Calls -notcontains 'pr merge 42 --merge --match-head-commit fedcba9876543210') { throw 'The replacement head must be checked before merging.' }

$originalLocation = (Get-Location).Path
$testRepository = Join-Path ([System.IO.Path]::GetTempPath()) "rickscripts-wpr-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path $testRepository | Out-Null
    $script:PullRequestRepositories.ia = $testRepository

    foreach ($repository in @('ia', $testRepository)) {
        $script:Scenario = 'success'
        $script:Calls = @()
        $script:Locations = @()
        $script:ViewCount = 0
        Watch-PullRequest -Repo $repository 42
        if (@($script:Locations | Where-Object { $_ -ne $testRepository }).Count -ne 0) { throw "Expected '$repository' to run GitHub commands in the selected repository." }
        if ((Get-Location).Path -ne $originalLocation) { throw "Expected '$repository' to restore the original location." }
    }

    $script:Scenario = 'failed-checks'
    $script:ViewCount = 0
    try { Watch-PullRequest -Repo ia 42 } catch {}
    if ((Get-Location).Path -ne $originalLocation) { throw 'A failed watch must restore the original location.' }
}
finally {
    Remove-Item -LiteralPath $testRepository -Recurse -Force
}
