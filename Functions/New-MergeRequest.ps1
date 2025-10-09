function New-MergeRequest {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [int]$IssueNumber,
        [string]$Title = "",
        [string]$TemplatePath = ".gitlab/merge_request_templates/prospector.md",
        [string]$Description = "",
        [string]$HowToTest = "",
        [ValidateScript({
                $maxWithIssuePrefix = 55 - 5
                if ($_.Length -gt $maxWithIssuePrefix) {
                    throw "Branch name cannot be longer than $maxWithIssuePrefix characters (leaves room for issue prefix). Provided: $($_.Length) characters"
                }
                $true
            })]
        [string]$NewBranchName = ""
    )

    if (-not $IssueNumber) {
        $IssueNumber = Read-Host "Enter issue number"
    }

    if (-not (Test-Path $TemplatePath)) {
        Write-Error "Template file not found: $TemplatePath"
        exit 1
    }

    $TemplateContent = Get-Content $TemplatePath -Raw
    $FinalDescription = $TemplateContent
    $FinalDescription = $FinalDescription -replace "%{issue_id}", "#$IssueNumber"
    $FinalDescription = $FinalDescription -replace "\[issue_number_here\]", $IssueNumber

    if ($Description) {
        $FinalDescription = $FinalDescription.Replace("Enter a brief description of the changes introduced by this merge request.", $Description)
    }

    if ($HowToTest) {
        $FinalDescription = $FinalDescription.Replace("Enter a brief description of how to test the changes introduced by this merge request.", $HowToTest)
    }

    $textToRemove = @(
        "%{issue_id}",
        "(?s)### Environment.*?(?=## Checklist)",
        "- \[ \] Does it run on all platforms \(web/iOS/Android\)\?\n",
        "- \[ \] Have all static strings been translated\?\n",
        "\(except screens\)",
        "\n.*source_branch.*\n\n"
    )

    foreach ($item in $textToRemove) {
        $FinalDescription = $FinalDescription -replace $item, ""
    }


    if (-not $Title) {
        $IssueJson = glab issue view $IssueNumber --output=json | ConvertFrom-Json
        $Title = $IssueJson.title
    }
    $FormattedTitle = "[#${IssueNumber}] $Title"

    $issuePrefix = $IssueNumber.ToString()

    if ($NewBranchName) {
        $branchName = "$issuePrefix-$NewBranchName"
    }
    else {
        $branchSlug = ($Title.ToLower() -replace '[^a-z0-9]+', '-')
        $branchSlug = $branchSlug.Trim('-')
        $branchName = if ($branchSlug) { "$issuePrefix-$branchSlug" } else { $issuePrefix }
    }

    $MaxBranchLength = 55
    if (-not $NewBranchName -and $branchName.Length -gt $MaxBranchLength) {
        $remainingLength = $MaxBranchLength - ($issuePrefix.Length + 1)
        $suggestions = @()

        if ($remainingLength -gt 0) {
            $truncatedSlug = $branchSlug.Substring(0, [Math]::Min($remainingLength, $branchSlug.Length))
            $truncatedSlug = $truncatedSlug.Trim('-')
            if ($truncatedSlug) {
                $suggestions += "$issuePrefix-$truncatedSlug"
            }
        }

        $words = $branchSlug.Split('-', [System.StringSplitOptions]::RemoveEmptyEntries)
        if ($words.Count -gt 1) {
            $initialsSlug = ($words | ForEach-Object { $_[0] }) -join ''
            if ($initialsSlug) {
                $initialBranch = "$issuePrefix-$initialsSlug"
                if ($initialBranch.Length -le $MaxBranchLength) {
                    $suggestions += $initialBranch
                }
            }
        }

        if (-not $suggestions) {
            $suggestions += $issuePrefix
        }

        Write-Error (@(
                "Cannot create merge request because the inferred branch name '$branchName' would be $($branchName.Length) characters (max $MaxBranchLength).",
                "Suggested shorter branch names:",
                ($suggestions | ForEach-Object { "  - $_" } | Out-String).Trim()
            ) -join [Environment]::NewLine)
        return
    }

    glab issue update $IssueNumber --assignee rick.diaz

    $glabArgs = @(
        "mr",
        "create",
        "--yes"
    )

    if ($NewBranchName) {
        $glabArgs += "--source-branch"
        $glabArgs += $branchName
        $glabArgs += "--create-source-branch"
    }

    $glabArgs += @(
        "--related-issue",
        $IssueNumber
        "--copy-issue-labels",
        "--draft",
        "--remove-source-branch",
        "--assignee rick.diaz"
        "--title",
        "`"$FormattedTitle`""
        "--description",
        "`"$FinalDescription`""
    )

    Write-Verbose "Description: $FinalDescription"

    if ($PSCmdlet.ShouldProcess("glab $glabArgs")) {
        $mrOutput = Invoke-Expression "glab $glabArgs" | Out-String
        Write-Output $mrOutput

        if ($mrOutput -match '/merge_requests/(\d+)') {
            $mrNumber = $matches[1]
            glab mr checkout $mrNumber
        }
    }
}

Set-Alias nmr New-MergeRequest








