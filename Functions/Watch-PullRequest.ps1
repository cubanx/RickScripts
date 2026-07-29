$script:PullRequestRepositories = @{
    dw = Join-Path $HOME 'code/crisp/data-warehouse'
    ia = Join-Path $HOME 'code/crisp/internal-apps'
    ea = Join-Path $HOME 'code/crisp/external-api'
    rs = Join-Path $HOME 'code/RickScripts'
}

function Resolve-PullRequestRepository {
    param([Parameter(Mandatory)][string]$Repo)

    $isToken = $script:PullRequestRepositories.ContainsKey($Repo)
    $repository = if ($isToken) { $script:PullRequestRepositories[$Repo] } else { $Repo }
    $repository = (Resolve-Path -LiteralPath $repository -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $repository -PathType Container)) { throw "Repository '$Repo' is not a directory." }

    [PSCustomObject]@{
        Token = if ($isToken) { $Repo.ToLowerInvariant() } else { Split-Path -Leaf $repository }
        Path = $repository
    }
}

function Get-PullRequestInventory {
    param([Parameter(Mandatory)][object[]]$Repositories)

    foreach ($repository in $Repositories) {
        Push-Location -LiteralPath $repository.Path
        try {
            $json = & gh pr list --state open --limit 100 --json 'number,title,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,url'
            if ($LASTEXITCODE -ne 0) { throw "Could not list pull requests for '$($repository.Token)'." }
        }
        finally {
            Pop-Location
        }

        try {
            $pullRequests = @($json | ConvertFrom-Json)
        }
        catch {
            throw "Could not parse pull requests for '$($repository.Token)': $($_.Exception.Message)"
        }

        foreach ($pullRequest in $pullRequests) {
            if ($pullRequest.isDraft) { continue }

            $checks = @($pullRequest.statusCheckRollup)
            $failedChecks = @($checks | Where-Object {
                if ($_.__typename -eq 'StatusContext') {
                    $_.state -in @('ERROR', 'FAILURE')
                }
                else {
                    $_.conclusion -in @('ACTION_REQUIRED', 'CANCELLED', 'FAILURE', 'STALE', 'STARTUP_FAILURE', 'TIMED_OUT')
                }
            } | ForEach-Object {
                if ($_.name) { $_.name } else { $_.context }
            })
            $hasRunningChecks = @($checks | Where-Object {
                if ($_.__typename -eq 'StatusContext') {
                    $_.state -in @('EXPECTED', 'PENDING')
                }
                else {
                    $_.status -ne 'COMPLETED'
                }
            }).Count -gt 0

            $blockers = @()
            if ($pullRequest.mergeable -eq 'CONFLICTING' -or $pullRequest.mergeStateStatus -eq 'DIRTY') { $blockers += 'merge conflict' }
            if ($pullRequest.mergeStateStatus -eq 'BEHIND') { $blockers += 'branch behind' }
            if ($pullRequest.reviewDecision -eq 'CHANGES_REQUESTED') { $blockers += 'changes requested' }
            if ($pullRequest.reviewDecision -eq 'REVIEW_REQUIRED') { $blockers += 'required review missing' }

            $reasons = @()
            if ($failedChecks) { $reasons += "CI: $($failedChecks -join ', ')" }
            $reasons += $blockers
            $disposition = if ($failedChecks) {
                'Red'
            }
            elseif ($blockers) {
                'Yellow'
            }
            elseif (-not $checks) {
                $reasons += 'no checks reported'
                'Gray'
            }
            else {
                'Eligible'
            }
            $status = if ($hasRunningChecks) { 'RUNNING' } else { 'READY' }

            [PSCustomObject]@{
                Repo = $repository.Token
                RepositoryPath = $repository.Path
                Number = [int]$pullRequest.number
                Title = [string]$pullRequest.title
                Disposition = $disposition
                Status = $status
                Reasons = $reasons
                Display = "$($repository.Token)`t#$($pullRequest.number)`t$status`t$($pullRequest.title)"
            }
        }
    }
}

function Show-PullRequestInventoryReport {
    param([object[]]$Inventory)

    $report = @($Inventory | Where-Object { $_.Disposition -in @('Red', 'Yellow', 'Gray') } | Sort-Object Repo, Number)
    if (-not $report) { return }

    Write-Host ''
    Write-Host 'Other non-draft pull requests:'
    foreach ($pullRequest in $report) {
        $color = switch ($pullRequest.Disposition) {
            'Red' { 'Red' }
            'Yellow' { 'Yellow' }
            default { 'DarkGray' }
        }
        $label = $pullRequest.Disposition.ToUpperInvariant()
        Write-Host ("{0,-6} {1} #{2} — {3}: {4}" -f $label, $pullRequest.Repo, $pullRequest.Number, $pullRequest.Title, ($pullRequest.Reasons -join '; ')) -ForegroundColor $color
    }
}

function Get-PullRequestDetails {
    param([Parameter(Mandatory)][string]$PullRequest)

    $json = & gh pr view $PullRequest --json 'headRefOid,title,url'
    if ($LASTEXITCODE -ne 0) { throw "Could not read pull request '$PullRequest'." }
    try {
        $details = $json | ConvertFrom-Json
    }
    catch {
        throw "Could not parse pull request '$PullRequest': $($_.Exception.Message)"
    }
    if (-not $details.headRefOid -or -not $details.title -or -not $details.url) { throw "Pull request '$PullRequest' did not return its head, title, and URL." }
    return $details
}

function Watch-PullRequest {
    <#
    .SYNOPSIS
    Watches a pull request's checks and merges its checked head when they pass.

    .EXAMPLE
    Watch-PullRequest 42

    .EXAMPLE
    Watch-PullRequest https://github.com/Crisp-Inc/data-warehouse/pull/42

    .EXAMPLE
    Watch-PullRequest -Repo ia 42

    .EXAMPLE
    Watch-PullRequest

    Lists eligible non-draft pull requests from the configured repositories.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$PullRequest,

        [string]$Repo
    )

    if (-not $PullRequest) {
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { throw "Required dependency 'fzf' was not found in PATH." }

        $repositories = if ($Repo) {
            @(Resolve-PullRequestRepository -Repo $Repo)
        }
        else {
            @($script:PullRequestRepositories.Keys | Sort-Object | ForEach-Object { Resolve-PullRequestRepository -Repo $_ })
        }
        $inventory = @(Get-PullRequestInventory -Repositories $repositories)

        try {
            $eligible = @($inventory | Where-Object { $_.Disposition -eq 'Eligible' })
            if ($eligible) {
                $selection = $eligible.Display | fzf --height 50% --reverse --prompt 'Pick a PR to watch: '
                if ($selection) {
                    $selected = $eligible | Where-Object { $_.Display -eq $selection } | Select-Object -First 1
                    Watch-PullRequest -Repo $selected.RepositoryPath -PullRequest $selected.Number
                }
            }
            else {
                Write-Host 'No pull requests are currently eligible to watch.'
            }
        }
        finally {
            try {
                Show-PullRequestInventoryReport -Inventory @(Get-PullRequestInventory -Repositories $repositories)
            }
            catch {
                Write-Warning "Could not refresh the pull request report: $($_.Exception.Message)"
            }
        }
        return
    }

    $repository = if ($Repo) { Resolve-PullRequestRepository -Repo $Repo } else { $null }
    if ($repository) { Push-Location -LiteralPath $repository.Path }

    try {
        $details = Get-PullRequestDetails -PullRequest $PullRequest
        Write-Host "Watching $($details.title) — $($details.url)"

        while ($true) {
            $head = $details.headRefOid

            & gh pr checks $PullRequest --watch --fail-fast
            $checksExitCode = $LASTEXITCODE
            $details = Get-PullRequestDetails -PullRequest $PullRequest
            $currentHead = $details.headRefOid
            if ($currentHead -ne $head) {
                Write-Host "Pull request head changed from $head to $currentHead; restarting checks."
                continue
            }
            if ($checksExitCode -ne 0) { throw "Pull request '$PullRequest' checks did not pass; not merging." }

            & gh pr merge $PullRequest --merge --match-head-commit $head
            if ($LASTEXITCODE -eq 0) { return }

            $details = Get-PullRequestDetails -PullRequest $PullRequest
            $currentHead = $details.headRefOid
            if ($currentHead -ne $head) {
                Write-Host "Pull request head changed from $head to $currentHead; restarting checks."
                continue
            }
            throw "GitHub did not merge pull request '$PullRequest'; no requirements were bypassed."
        }
    }
    finally {
        if ($repository) { Pop-Location }
    }
}

Set-Alias wpr Watch-PullRequest
