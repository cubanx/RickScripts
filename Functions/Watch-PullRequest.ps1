$script:PullRequestRepositories = @{
    dw = Join-Path $HOME 'code/crisp/data-warehouse'
    ia = Join-Path $HOME 'code/crisp/internal-apps'
    ea = Join-Path $HOME 'code/crisp/external-api'
    rs = Join-Path $HOME 'code/RickScripts'
}

function Get-PullRequestHeadCommit {
    param([Parameter(Mandatory)][string]$PullRequest)

    $head = & gh pr view $PullRequest --json headRefOid --jq .headRefOid
    if ($LASTEXITCODE -ne 0) { throw "Could not read pull request '$PullRequest'." }
    $head = [Convert]::ToString(($head | Select-Object -First 1)).Trim()
    if (-not $head) { throw "Pull request '$PullRequest' did not return a head commit." }
    return $head
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$PullRequest,

        [string]$Repo
    )

    if ($Repo) {
        $repository = if ($script:PullRequestRepositories.ContainsKey($Repo)) { $script:PullRequestRepositories[$Repo] } else { $Repo }
        $repository = (Resolve-Path -LiteralPath $repository -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $repository -PathType Container)) { throw "Repository '$Repo' is not a directory." }
        Push-Location -LiteralPath $repository
    }

    try {
        while ($true) {
            $head = Get-PullRequestHeadCommit -PullRequest $PullRequest

            & gh pr checks $PullRequest --watch --fail-fast
            $checksExitCode = $LASTEXITCODE
            $currentHead = Get-PullRequestHeadCommit -PullRequest $PullRequest
            if ($currentHead -ne $head) {
                Write-Host "Pull request head changed from $head to $currentHead; restarting checks."
                continue
            }
            if ($checksExitCode -ne 0) { throw "Pull request '$PullRequest' checks did not pass; not merging." }

            & gh pr merge $PullRequest --merge --match-head-commit $head
            if ($LASTEXITCODE -eq 0) { return }

            $currentHead = Get-PullRequestHeadCommit -PullRequest $PullRequest
            if ($currentHead -ne $head) {
                Write-Host "Pull request head changed from $head to $currentHead; restarting checks."
                continue
            }
            throw "GitHub did not merge pull request '$PullRequest'; no requirements were bypassed."
        }
    }
    finally {
        if ($Repo) { Pop-Location }
    }
}

Set-Alias wpr Watch-PullRequest
