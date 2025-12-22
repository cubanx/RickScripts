. $PSScriptRoot\Switch-MergeRequest.Labels.ps1

function New-MergeRequest {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string[]]$SetProjectForPath,
        [switch]$ResetProjectForPath,
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

    $currentFolder = Split-Path -Leaf (Get-Location)

    if ($SetProjectForPath) {
        Set-ProjectLabels -Labels $SetProjectForPath
        Write-Host "✅ Set labels for folder '$currentFolder': $($SetProjectForPath -join ', ')" -ForegroundColor Green
    }

    if ($ResetProjectForPath) {
        Remove-ProjectLabels
        Write-Host "✅ Cleared labels for folder '$currentFolder'" -ForegroundColor Green
    }

    $labels = Get-ProjectLabels

    if (-not $IssueNumber) {
        $projectId = (glab repo view --output json | ConvertFrom-Json).id
        $createdAfter = (Get-Date).AddMonths(-2).ToUniversalTime().ToString("o")

        $queryParams = @{
            created_after = $createdAfter
            order_by      = "created_at"
            sort          = "desc"
            per_page      = "100"
        }
        if ($labels) {
            $queryParams.labels = ($labels -join ",")
        }

        $queryString = ($queryParams.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$([System.Uri]::EscapeDataString($_.Value))"
            }) -join "&"

        $glabArgs = @(
            "api",
            "/projects/$projectId/issues?$queryString"
        )

        $issueList = (& glab @glabArgs) | ConvertFrom-Json
        $selectedIssue = $issueList | ForEach-Object { "$($_.iid)`t$($_.title)" } | fzf

        if (-not $selectedIssue) {
            Write-Output "No issue selected"
            return
        }

        $issueParts = $selectedIssue -split "`t", 2
        $IssueNumber = [int]$issueParts[0]
        if (-not $Title -and $issueParts.Count -gt 1) {
            $Title = $issueParts[1]
        }
    }

    if (-not (Test-Path $TemplatePath)) {
        Write-Error "Template file not found: $TemplatePath"
        exit 1
    }

    $TemplateContent = Get-Content $TemplatePath -Raw
    $FinalDescription = $TemplateContent
    $FinalDescription = $FinalDescription -replace "\[issue_number_here\]", $IssueNumber
    $FinalDescription = $FinalDescription -replace "<issue-number>", $IssueNumber

    if ($Description) {
        $FinalDescription = $FinalDescription.Replace("Seriously dude, you have to put _SOMETHING_ here!", $Description)
    }

    if ($HowToTest) {
        $FinalDescription = $FinalDescription -replace "(?s)### How to test\n\n<!-- OPTIONAL.*?-->", "### How to test`n`n$HowToTest"
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


