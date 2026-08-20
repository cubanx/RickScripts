function Get-GitPublishingSlug {
    param([Parameter(Mandatory = $true)][string]$RepositoryName)

    switch ($RepositoryName) {
        'data-warehouse' { return 'dw' }
        'yoda' { return 'ia' }
        'external-api' { return 'ea' }
    }

    $words = $RepositoryName -split '[-_ ]+' | ForEach-Object { $_ -csplit '(?<=[a-z0-9])(?=[A-Z])' } | Where-Object { $_ }
    return (($words | ForEach-Object { $_.Substring(0, 1).ToLowerInvariant() }) -join '')
}

function Get-GitPublishingBranchDescription {
    param([Parameter(Mandatory = $true)][string]$CommitMessage)

    $description = $CommitMessage -replace '^[A-Za-z]+(?:\([^)]+\))?!?:\s*', ''
    return ($description -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
}

function Get-OpenSpecProposalSection {
    param(
        [Parameter(Mandatory = $true)][string]$Markdown,
        [Parameter(Mandatory = $true)][string]$Heading
    )

    $match = [regex]::Match(
        $Markdown,
        "(?ms)^##\s+$([regex]::Escape($Heading))\s*\r?\n(?<Content>.*?)(?=^##\s+|\z)"
    )
    if (-not $match.Success -or [string]::IsNullOrWhiteSpace($match.Groups['Content'].Value)) {
        throw "OpenSpec proposal is missing a non-empty '$Heading' section."
    }

    return $match.Groups['Content'].Value.Trim()
}

function Publish-GitChanges {
    <#
    .SYNOPSIS
    Stages the complete worktree and creates or updates a GitHub pull request.

    .DESCRIPTION
    Stops before mutation when origin, GitHub, worktree checks, or an existing pull request
    for another branch are found. A pull request already open for the current feature branch
    is updated by committing and pushing without creating or retitling it. This command runs
    git add -A, so all tracked, unstaged, and untracked changes are included. A single
    OpenSpec-only change uses deterministic metadata and does not invoke Codex.

    .EXAMPLE
    Publish-GitChanges

    Creates a draft pull request against origin's default branch.

    .EXAMPLE
    Publish-GitChanges -BranchName dw/fix-report -BaseBranch main -Ready

    Creates or uses the named branch and opens a ready pull request.

    .EXAMPLE
    yeet

    Uses the stable alias to create a draft PR or update the current feature branch's open PR.
    #>
    [CmdletBinding()]
    param(
        [string]$BranchName,
        [string]$BaseBranch,
        [switch]$Ready
    )

    $root = (Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
    $repositoryName = Split-Path -Leaf $root
    $slug = Get-GitPublishingSlug -RepositoryName $repositoryName
    if ([string]::IsNullOrWhiteSpace($slug)) { throw "Cannot derive a repository slug from '$repositoryName'." }

    $originHead = @(Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('ls-remote', '--symref', 'origin', 'HEAD'))
    $defaultRef = @($originHead | Where-Object { $_ -match '^ref:\s+refs/heads/(.+)\s+HEAD$' } | Select-Object -First 1)
    if (-not $defaultRef) { throw "Cannot determine origin's default branch." }
    $defaultBranch = ([regex]::Match([string]$defaultRef[0], '^ref:\s+refs/heads/(.+)\s+HEAD$')).Groups[1].Value
    if (-not $BaseBranch) { $BaseBranch = $defaultBranch }

    $currentBranch = Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('branch', '--show-current') | Select-Object -First 1
    $currentBranch = [Convert]::ToString($currentBranch).Trim()
    $publishingBranch = if ($BranchName) { $BranchName } elseif ($currentBranch -and $currentBranch -ne $defaultBranch) { $currentBranch } else { $null }

    $status = @(Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('status', '--porcelain'))
    $staged = @($status | Where-Object { $_.Length -ge 2 -and $_[0] -ne ' ' -and $_[0] -ne '?' })
    $unstagedOrUntracked = @($status | Where-Object { ($_.Length -ge 2 -and $_[1] -ne ' ') -or $_ -like '??*' })
    Write-Host "Staged scope: $($staged.Count) file(s)."
    Write-Host "Unstaged/untracked scope: $($unstagedOrUntracked.Count) file(s)."
    $status | ForEach-Object { Write-Host "  $_" }
    if (-not $status) { throw 'No worktree changes to publish.' }

    $changedPaths = @($status | ForEach-Object { ([string]$_).Substring(3) })
    $openSpecChanges = @($changedPaths | ForEach-Object {
        if ($_ -match '^openspec/changes/([^/]+)/') { $Matches[1] }
    } | Select-Object -Unique)
    $isOpenSpecOnly = $currentBranch -eq $defaultBranch -and $openSpecChanges.Count -eq 1 -and @($changedPaths | Where-Object { $_ -notmatch '^openspec/changes/[^/]+/' }).Count -eq 0
    $summary = if ($isOpenSpecOnly) {
        $changeName = $openSpecChanges[0]
        $titleChangeName = $changeName -replace '^add-', ''
        $humanChangeName = $titleChangeName -replace '-', ' '
        $proposalPath = Join-Path $root "openspec/changes/$changeName/proposal.md"
        if (-not (Test-Path -LiteralPath $proposalPath -PathType Leaf)) {
            throw "OpenSpec proposal not found at '$proposalPath'."
        }
        $proposal = Get-Content -LiteralPath $proposalPath -Raw
        [PSCustomObject]@{
            CommitMessage = "docs: add $humanChangeName OpenSpec"
            HumanTitle = "Add $humanChangeName OpenSpec"
            WhatChanged = Get-OpenSpecProposalSection -Markdown $proposal -Heading 'What Changes'
            Why = Get-OpenSpecProposalSection -Markdown $proposal -Heading 'Why'
            Impact = Get-OpenSpecProposalSection -Markdown $proposal -Heading 'Impact'
            Validation = 'Not run by yeet.'
        }
    }
    else {
        Get-CodexChangeSummary
    }
    if (-not $publishingBranch) {
        $description = if ($isOpenSpecOnly) { $openSpecChanges[0] } else { Get-GitPublishingBranchDescription -CommitMessage $summary.CommitMessage }
        if (-not $description) { throw 'Codex commit message cannot be converted to a branch name.' }
        $publishingBranch = "$slug/$description"
    }

    $existingPrOutput = (Invoke-CodexGitPublishingCommand -FileName 'gh' -Arguments @('pr', 'list', '--head', $publishingBranch, '--state', 'open', '--json', 'number,url,title', '--limit', '1') | Out-String).Trim()
    $existingPr = $null
    if ($existingPrOutput -notin @('', '[]')) {
        $existingPr = @($existingPrOutput | ConvertFrom-Json | Select-Object -First 1)[0]
        if (-not $existingPr.number -or [string]::IsNullOrWhiteSpace($existingPr.url) -or [string]::IsNullOrWhiteSpace($existingPr.title)) {
            throw "Could not parse the existing pull request for '$publishingBranch'."
        }
        if ($currentBranch -ne $publishingBranch -or $currentBranch -eq $defaultBranch) {
            throw "An open pull request already exists for '$publishingBranch', but the current branch is '$currentBranch'. Switch to that branch before publishing."
        }
    }

    if ($currentBranch -ne $publishingBranch) {
        Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('switch', '-c', $publishingBranch) | Out-Null
    }

    Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('add', '-A') | Out-Null
    Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('-c', 'core.whitespace=-blank-at-eof', 'diff', '--cached', '--check') | Out-Null
    $stagedDiff = Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('diff', '--cached', '--name-status')
    $stagedDiff | ForEach-Object { Write-Host $_ }
    if (-not $stagedDiff) { throw 'Staging produced no changes to commit.' }

    Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('commit', '-m', $summary.CommitMessage) | Out-Null
    Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('push', '-u', 'origin', $publishingBranch) | Out-Null
    $commitSha = (Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()

    if ($existingPr) {
        return [PSCustomObject]@{
            Branch = $publishingBranch
            CommitSha = $commitSha
            Url = $existingPr.url
            Title = $existingPr.title
            Status = (Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('status', '--short'))
        }
    }

    $bodyPath = [System.IO.Path]::GetTempFileName()
    try {
        $body = if ($isOpenSpecOnly) {
            @(
                '## Why', $summary.Why, '', '## What changes', $summary.WhatChanged, '',
                '## Impact', $summary.Impact, '', '## Validation', $summary.Validation, '',
                '## Staged diff check', 'git diff --cached --check passed.'
            )
        }
        else {
            @(
                '## What changed', $summary.WhatChanged, '', '## Why', $summary.Why, '',
                '## User impact', $summary.UserImpact, '', '## Developer impact', $summary.DeveloperImpact, '',
                '## Validation', $summary.Validation, '', '## Staged diff check', 'git diff --cached --check passed.'
            )
        }
        $body | Set-Content -LiteralPath $bodyPath -Encoding UTF8
        $createArguments = @('pr', 'create', '--base', $BaseBranch, '--head', $publishingBranch, '--title', $summary.HumanTitle, '--body-file', $bodyPath)
        if (-not $Ready) { $createArguments += '--draft' }
        $url = (Invoke-CodexGitPublishingCommand -FileName 'gh' -Arguments $createArguments | Select-Object -First 1).Trim()
        if ($url -notmatch '/pull/(\d+)$') { throw "Could not parse pull request number from '$url'." }
        $number = $Matches[1]
        $title = "[$slug-#$number] $($summary.HumanTitle)"
        Invoke-CodexGitPublishingCommand -FileName 'gh' -Arguments @('pr', 'edit', $url, '--title', $title) | Out-Null
    }
    finally {
        Remove-CodexGitPublishingTemporaryFile -Path $bodyPath -Label 'pull request body'
    }

    return [PSCustomObject]@{
        Branch = $publishingBranch
        CommitSha = $commitSha
        Url = $url
        Title = $title
        Status = (Invoke-CodexGitPublishingCommand -FileName 'git' -Arguments @('status', '--short'))
    }
}

Set-Alias yeet Publish-GitChanges
