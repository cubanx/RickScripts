function New-MergeRequest {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [int]$IssueNumber,
        [string]$Title = "",
        [string]$TemplatePath = ".gitlab/merge_request_templates/Default.md",
        [string]$Description = "",
        [string]$HowToTest = ""
    )

    if (-not $IssueNumber) {
        $IssueNumber = Read-Host "Enter issue number"
    }

    if (-not (Test-Path $TemplatePath)) {
        Write-Error "Template file not found: $TemplatePath"
        exit 1
    }

    $TemplateContent = Get-Content $TemplatePath -Raw
    $textToRemove = @(
        "%{issue_id}",
        "(?s)### Environment.*?(?=## Checklist)",
        "- \[ \] Does it run on all platforms \(web/iOS/Android\)\?\n",
        "- \[ \] Have all static strings been translated\?\n",
        "\(except screens\)",
        "\n.*source_branch.*\n\n"
    )
    $FinalDescription = $TemplateContent
    foreach ($item in $textToRemove) {
        $FinalDescription = $FinalDescription -replace $item, ""
    }
    $FinalDescription = $FinalDescription -replace "%{issue_id}", "#$IssueNumber"

    if ($Description) {
        $FinalDescription = $FinalDescription.Replace("Enter a brief description of the changes introduced by this merge request.", $Description)
    }

    if ($HowToTest) {
        $FinalDescription = $FinalDescription.Replace("Enter a brief description of how to test the changes introduced by this merge request.", $HowToTest)
    }


    if (-not $Title) {
        $IssueJson = glab issue view $IssueNumber --output=json | ConvertFrom-Json
        $Title = $IssueJson.title
    }
    $FormattedTitle = "[#${IssueNumber}] $Title"

    $glabArgs = @(
        "mr",
        "create",
        "--yes",
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
        Invoke-Expression "glab $glabArgs"
    }
}

Set-Alias nmr New-MergeRequest
