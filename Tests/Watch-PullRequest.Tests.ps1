BeforeAll {
    . "$PSScriptRoot/../Functions/Watch-PullRequest.ps1"

    function Write-Host {
        param(
            [Parameter(Position = 0, ValueFromRemainingArguments)][object[]]$Object,
            [ConsoleColor]$ForegroundColor,
            [switch]$NoNewline
        )
        $script:HostLines += [PSCustomObject]@{ Text = $Object -join ' '; Color = [string]$ForegroundColor }
    }

    function fzf {
        begin { $lines = @() }
        process { $lines += [string]$_ }
        end {
            $script:FzfItems = $lines
            return $lines | Where-Object { $_ -like "*$script:FzfPick*" } | Select-Object -First 1
        }
    }

    function Start-Sleep {}

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
        if ($command -eq 'pr view 42 --json headRefOid,title,url,statusCheckRollup') {
            $script:ViewCount++
            $head = if ($script:Scenario -eq 'changed-head' -and $script:ViewCount -gt 1) { 'fedcba9876543210' } else { '0123456789abcdef' }
            return @{ headRefOid = $head; title = 'Keep the wormhole open'; url = 'https://github.com/example/internal-apps/pull/42'; statusCheckRollup = @() } | ConvertTo-Json
        }
        if ($command -in @('pr view 61 --json headRefOid,title,url,statusCheckRollup', 'pr view https://github.com/Crisp-Inc/data-warehouse/pull/61 --json headRefOid,title,url,statusCheckRollup')) {
            $checks = @(
                if ($script:Scenario -eq 'automatic-pending' -and -not $script:AutomaticComplete) {
                    @{ __typename = 'CheckRun'; name = 'Python code fitness'; status = 'IN_PROGRESS'; conclusion = '' }
                }
                else {
                    @{ __typename = 'CheckRun'; name = 'Python code fitness'; status = 'COMPLETED'; conclusion = 'SUCCESS' }
                }
                @{ __typename = 'CheckRun'; name = 'dbt CI'; status = 'COMPLETED'; conclusion = 'SUCCESS' }
            )
            if ($script:Scenario -eq 'already-staged' -or $script:StagingComplete) {
                $checks += @{ __typename = 'StatusContext'; context = 'Snowflake PR staging'; state = 'SUCCESS'; targetUrl = 'https://github.com/Crisp-Inc/data-warehouse/actions/runs/1701' }
            }
            elseif ($script:StagingDispatched) {
                $checks += @{ __typename = 'StatusContext'; context = 'Snowflake PR staging'; state = 'PENDING'; targetUrl = 'https://github.com/Crisp-Inc/data-warehouse/actions/runs/1701' }
            }
            return @{ headRefOid = '61abcdef'; title = 'Publish Yoda Gong transcript consumer'; url = 'https://github.com/Crisp-Inc/data-warehouse/pull/61'; statusCheckRollup = $checks } | ConvertTo-Json -Depth 4
        }
        if ($command -eq 'pr checks 42 --watch --fail-fast') {
            if ($script:Scenario -eq 'failed-checks') { $global:LASTEXITCODE = 1 }
            return
        }
        if ($command -eq 'workflow run snowflake-pr-staging.yml --repo Crisp-Inc/data-warehouse --ref main -f pull_request=61') {
            $script:StagingDispatched = $true
            return
        }
        if ($command -in @('pr checks 61 --watch --fail-fast', 'pr checks https://github.com/Crisp-Inc/data-warehouse/pull/61 --watch --fail-fast')) {
            if ($script:StagingDispatched) { $script:StagingComplete = $true } else { $script:AutomaticComplete = $true }
            return
        }
        if ($command -eq 'pr merge 42 --merge --match-head-commit 0123456789abcdef') {
            if ($script:Scenario -eq 'failed-merge') { $global:LASTEXITCODE = 1 }
            return
        }
        if ($command -eq 'pr merge 42 --merge --match-head-commit fedcba9876543210') { return }
        if ($command -eq 'pr merge 61 --merge --match-head-commit 61abcdef') { return }
        if ($command -eq 'pr merge https://github.com/Crisp-Inc/data-warehouse/pull/61 --merge --match-head-commit 61abcdef') { return }
        throw "Unexpected gh call: $command"
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
}

Describe 'Watch-PullRequest' {
    BeforeEach {
        $script:Calls = @()
        $script:Locations = @()
        $script:HostLines = @()
        $script:FzfItems = @()
        $script:FzfPick = $null
        $script:InventoryByRepository = @{}
        $script:Scenario = 'success'
        $script:ViewCount = 0
        $script:StagingDispatched = $false
        $script:StagingComplete = $false
        $script:AutomaticComplete = $false
    }

    It 'exports the wpr alias' {
        (Get-Alias wpr -ErrorAction Stop).Definition | Should -Be 'Watch-PullRequest'
    }

    It 'merges the checked head without bypassing requirements' {
        Watch-PullRequest 42

        $script:Calls | Should -Contain 'pr merge 42 --merge --match-head-commit 0123456789abcdef'
        ($script:Calls -join ' ') | Should -Not -Match '(?:^|\s)--admin(?:\s|$)'
        @($script:HostLines | Where-Object { $_.Text -eq 'Watching Keep the wormhole open — https://github.com/example/internal-apps/pull/42' }).Count | Should -Be 1
        @($script:Calls | Where-Object { $_ -like 'workflow run *' }).Count | Should -Be 0
    }

    It 'dispatches Snowflake staging only for a data-warehouse pull request and waits for its check' {
        Watch-PullRequest 61

        $script:Calls | Should -Contain 'workflow run snowflake-pr-staging.yml --repo Crisp-Inc/data-warehouse --ref main -f pull_request=61'
        $script:Calls | Should -Contain 'pr checks 61 --watch --fail-fast'
        $script:Calls | Should -Contain 'pr merge 61 --merge --match-head-commit 61abcdef'
    }

    It 'does not repeat Snowflake staging already passed on the current head' {
        $script:Scenario = 'already-staged'

        Watch-PullRequest 61

        @($script:Calls | Where-Object { $_ -like 'workflow run *' }).Count | Should -Be 0
    }

    It 'waits for automatic data-warehouse checks before dispatching staging' {
        $script:Scenario = 'automatic-pending'

        Watch-PullRequest 61

        [array]::IndexOf($script:Calls, 'pr checks 61 --watch --fail-fast') | Should -BeLessThan ([array]::IndexOf($script:Calls, 'workflow run snowflake-pr-staging.yml --repo Crisp-Inc/data-warehouse --ref main -f pull_request=61'))
        @($script:Calls | Where-Object { $_ -eq 'pr checks 61 --watch --fail-fast' }).Count | Should -Be 2
    }

    It 'uses the pull request number when invoked by data-warehouse URL' {
        Watch-PullRequest https://github.com/Crisp-Inc/data-warehouse/pull/61

        $script:Calls | Should -Contain 'workflow run snowflake-pr-staging.yml --repo Crisp-Inc/data-warehouse --ref main -f pull_request=61'
    }

    It 'does not merge when checks fail' {
        $script:Scenario = 'failed-checks'

        { Watch-PullRequest 42 } | Should -Throw
        @($script:Calls | Where-Object { $_ -like 'pr merge *' }).Count | Should -Be 0
    }

    It 'surfaces a refused merge' {
        $script:Scenario = 'failed-merge'
        { Watch-PullRequest 42 } | Should -Throw
    }

    It 'restarts checks when the head changes and merges only the replacement' {
        $script:Scenario = 'changed-head'

        Watch-PullRequest 42

        @($script:Calls | Where-Object { $_ -eq 'pr checks 42 --watch --fail-fast' }).Count | Should -Be 2
        $script:Calls | Should -Not -Contain 'pr merge 42 --merge --match-head-commit 0123456789abcdef'
        $script:Calls | Should -Contain 'pr merge 42 --merge --match-head-commit fedcba9876543210'
        @($script:HostLines | Where-Object { $_.Text -like 'Watching *' }).Count | Should -Be 1
    }

    It 'runs in the selected repository and always restores location' {
        $originalLocation = (Get-Location).Path
        $testRepository = Join-Path ([System.IO.Path]::GetTempPath()) "rickscripts-wpr-$([guid]::NewGuid())"
        try {
            New-Item -ItemType Directory -Path $testRepository | Out-Null
            $script:PullRequestRepositories.ia = $testRepository

            foreach ($repository in @('ia', $testRepository)) {
                $script:Locations = @()
                Watch-PullRequest -Repo $repository 42
                @($script:Locations | Where-Object { $_ -ne $testRepository }).Count | Should -Be 0
                (Get-Location).Path | Should -Be $originalLocation
            }

            $script:Locations = @()
            Watch-PullRequest ia 42
            @($script:Locations | Where-Object { $_ -ne $testRepository }).Count | Should -Be 0
            (Get-Location).Path | Should -Be $originalLocation

            $script:Scenario = 'failed-checks'
            { Watch-PullRequest -Repo ia 42 } | Should -Throw
            (Get-Location).Path | Should -Be $originalLocation
        }
        finally {
            Remove-Item -LiteralPath $testRepository -Recurse -Force
        }
    }

    It 'offers only pull requests that can make progress' {
        $runningCheck = [PSCustomObject]@{ __typename = 'CheckRun'; name = 'Wormhole stability'; status = 'IN_PROGRESS'; conclusion = '' }
        $passingCheck = [PSCustomObject]@{ __typename = 'CheckRun'; name = 'Defiant readiness'; status = 'COMPLETED'; conclusion = 'SUCCESS' }
        $failingCheck = [PSCustomObject]@{ __typename = 'CheckRun'; name = 'Self-sealing stem bolts'; status = 'COMPLETED'; conclusion = 'FAILURE' }
        $originalLocation = (Get-Location).Path
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
            $script:FzfPick = '#42'

            Watch-PullRequest

            @($script:FzfItems | Where-Object { $_ -match '#42.+RUNNING' }).Count | Should -Be 1
            @($script:FzfItems | Where-Object { $_ -match '#49.+READY' }).Count | Should -Be 1
            foreach ($excludedNumber in 43..48) {
                @($script:FzfItems | Where-Object { $_ -match "#$excludedNumber(?:\D|$)" }).Count | Should -Be 0
            }
            @($script:HostLines | Where-Object { $_.Text -match '#43' -and $_.Color -eq 'Red' }).Count | Should -BeGreaterThan 0
            foreach ($yellowNumber in @(44, 47, 48)) {
                @($script:HostLines | Where-Object { $_.Text -match "#$yellowNumber(?:\D|$)" -and $_.Color -eq 'Yellow' }).Count | Should -BeGreaterThan 0
            }
            @($script:HostLines | Where-Object { $_.Text -match '#45' -and $_.Color -eq 'DarkGray' }).Count | Should -BeGreaterThan 0
            @($script:HostLines | Where-Object { $_.Text -match '#46' }).Count | Should -Be 0
            (Get-Location).Path | Should -Be $originalLocation
        }
        finally {
            Remove-Item -LiteralPath $pickerRoot -Recurse -Force
        }
    }
}
