$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Functions/Watch-PullRequest.ps1"

if ((Get-Alias wpr -ErrorAction SilentlyContinue).Definition -ne 'Watch-PullRequest') { throw 'Expected wpr to alias Watch-PullRequest.' }

$script:Calls = @()
$script:Locations = @()
$script:HostLines = @()
$script:FzfItems = @()
$script:FzfPick = $null
$script:InventoryByRepository = @{}
$script:Scenario = 'success'
$script:ViewCount = 0

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [object[]]$Object,
        [ConsoleColor]$ForegroundColor,
        [switch]$NoNewline
    )

    $script:HostLines += [PSCustomObject]@{
        Text = $Object -join ' '
        Color = [string]$ForegroundColor
    }
}

function fzf {
    begin { $lines = @() }
    process { $lines += [string]$_ }
    end {
        $script:FzfItems = $lines
        return $lines | Where-Object { $_ -like "*$script:FzfPick*" } | Select-Object -First 1
    }
}

function gh {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

    $command = $Arguments -join ' '
    $script:Calls += $command
    $script:Locations += (Get-Location).Path
    $global:LASTEXITCODE = 0

    if ($command -eq 'pr list --state open --limit 100 --json number,title,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,url') {
        $repository = Split-Path -Leaf (Get-Location)
        return ConvertTo-Json -InputObject @($script:InventoryByRepository[$repository]) -Depth 8
    }
    if ($command -eq 'pr view 42 --json headRefOid,title,url') {
        $script:ViewCount++
        $head = if ($script:Scenario -eq 'changed-head' -and $script:ViewCount -gt 1) { 'fedcba9876543210' } else { '0123456789abcdef' }
        return @{ headRefOid = $head; title = 'Keep the wormhole open'; url = 'https://github.com/example/internal-apps/pull/42' } | ConvertTo-Json
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
if (@($script:HostLines | Where-Object { $_.Text -eq 'Watching Keep the wormhole open — https://github.com/example/internal-apps/pull/42' }).Count -ne 1) { throw 'Expected the watched PR title and URL.' }

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
$script:HostLines = @()
$script:ViewCount = 0
Watch-PullRequest 42
if (@($script:Calls | Where-Object { $_ -eq 'pr checks 42 --watch --fail-fast' }).Count -ne 2) { throw 'A changed head must restart the check watch.' }
if ($script:Calls -contains 'pr merge 42 --merge --match-head-commit 0123456789abcdef') { throw 'The superseded head must not be merged.' }
if ($script:Calls -notcontains 'pr merge 42 --merge --match-head-commit fedcba9876543210') { throw 'The replacement head must be checked before merging.' }
if (@($script:HostLines | Where-Object { $_.Text -like 'Watching *' }).Count -ne 1) { throw 'A restarted watch must not repeat the PR title and URL.' }

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

function New-TestPullRequest {
    param(
        [int]$Number,
        [string]$Title,
        [bool]$IsDraft = $false,
        [string]$Mergeable = 'MERGEABLE',
        [string]$MergeStateStatus = 'CLEAN',
        [string]$ReviewDecision = '',
        [object[]]$Checks = @()
    )

    [PSCustomObject]@{
        number = $Number
        title = $Title
        isDraft = $IsDraft
        mergeable = $Mergeable
        mergeStateStatus = $MergeStateStatus
        reviewDecision = $ReviewDecision
        statusCheckRollup = $Checks
        url = "https://github.com/example/internal-apps/pull/$Number"
    }
}

$runningCheck = [PSCustomObject]@{ __typename = 'CheckRun'; name = 'Wormhole stability'; status = 'IN_PROGRESS'; conclusion = '' }
$passingCheck = [PSCustomObject]@{ __typename = 'CheckRun'; name = 'Defiant readiness'; status = 'COMPLETED'; conclusion = 'SUCCESS' }
$failingCheck = [PSCustomObject]@{ __typename = 'CheckRun'; name = 'Self-sealing stem bolts'; status = 'COMPLETED'; conclusion = 'FAILURE' }
$pickerRoot = Join-Path ([System.IO.Path]::GetTempPath()) "rickscripts-wpr-picker-$([guid]::NewGuid())"
try {
    foreach ($token in @('dw', 'ia', 'ea', 'rs')) {
        $repository = Join-Path $pickerRoot $token
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $script:PullRequestRepositories[$token] = $repository
        $script:InventoryByRepository[$token] = @()
    }

    $script:InventoryByRepository.ia = @(
        New-TestPullRequest -Number 42 -Title 'Keep the wormhole open' -MergeStateStatus 'BLOCKED' -Checks @($runningCheck)
        New-TestPullRequest -Number 43 -Title 'Count the self-sealing stem bolts' -Checks @($failingCheck)
        New-TestPullRequest -Number 44 -Title 'Resolve the promenade conflict' -Mergeable 'CONFLICTING' -MergeStateStatus 'DIRTY' -Checks @($passingCheck)
        New-TestPullRequest -Number 45 -Title 'Correct Quark menu typography'
        New-TestPullRequest -Number 46 -Title 'Draft treaty language' -IsDraft $true -Checks @($passingCheck)
        New-TestPullRequest -Number 47 -Title 'Bring the branch current' -MergeStateStatus 'BEHIND' -Checks @($passingCheck)
        New-TestPullRequest -Number 48 -Title 'Await Bajoran review' -ReviewDecision 'REVIEW_REQUIRED' -Checks @($passingCheck)
        New-TestPullRequest -Number 49 -Title 'Ready the Defiant' -Checks @($passingCheck)
    )

    $script:Scenario = 'success'
    $script:Calls = @()
    $script:Locations = @()
    $script:HostLines = @()
    $script:FzfItems = @()
    $script:FzfPick = '#42'
    $script:ViewCount = 0
    Watch-PullRequest

    if (@($script:FzfItems | Where-Object { $_ -match '#42.+RUNNING' }).Count -ne 1) { throw 'Running checks without failures must be selectable.' }
    if (@($script:FzfItems | Where-Object { $_ -match '#49.+READY' }).Count -ne 1) { throw 'Passing checks must be selectable.' }
    foreach ($excludedNumber in 43..48) {
        if (@($script:FzfItems | Where-Object { $_ -match "#$excludedNumber(?:\D|$)" }).Count -ne 0) { throw "PR #$excludedNumber must not be selectable." }
    }
    if (@($script:HostLines | Where-Object { $_.Text -match '#43' -and $_.Color -eq 'Red' }).Count -eq 0) { throw 'Failed CI must be reported in red.' }
    foreach ($yellowNumber in @(44, 47, 48)) {
        if (@($script:HostLines | Where-Object { $_.Text -match "#$yellowNumber(?:\D|$)" -and $_.Color -eq 'Yellow' }).Count -eq 0) { throw "PR #$yellowNumber must be reported in yellow." }
    }
    if (@($script:HostLines | Where-Object { $_.Text -match '#45' -and $_.Color -eq 'DarkGray' }).Count -eq 0) { throw 'PRs without checks must be reported in gray.' }
    if (@($script:HostLines | Where-Object { $_.Text -match '#46' }).Count -ne 0) { throw 'Draft PRs must not be reported.' }
    if ((Get-Location).Path -ne $originalLocation) { throw 'Interactive selection must restore the original location.' }
}
finally {
    Remove-Item -LiteralPath $pickerRoot -Recurse -Force
}
