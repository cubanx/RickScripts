function New-MergeRequest {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[int]$IssueNumber,
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
	$FinalDescription = $TemplateContent -replace "%{issue_id}", "#$IssueNumber"
	$FinalDescription = $FinalDescription -replace "(?s)### Environment.*?(?=## Checklist)", ""
	$checklistItemsToRemove = @(
		"- \[ \] Does it run on all platforms \(web/iOS/Android\)\?\n",
		"- \[ \] Have all static strings been translated\?\n",
		"\(except screens\)"
	)

	foreach ($item in $checklistItemsToRemove) {
		$FinalDescription = $FinalDescription -replace $item, ""
	}

	if ($Description) {
		$FinalDescription = $FinalDescription.Replace("Enter a brief description of the changes introduced by this merge request.", $Description)
	}

	if ($HowToTest) {
		$FinalDescription = $FinalDescription.Replace("Enter a brief description of how to test the changes introduced by this merge request.", $HowToTest)
	}


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
		"--description",
		"`"$FinalDescription`""
	)

	Write-Verbose "Description: $FinalDescription"

	if ($PSCmdlet.ShouldProcess("glab $glabArgs")) {
		Invoke-Expression "glab $glabArgs"
	}
}

Set-Alias nmr New-MergeRequest