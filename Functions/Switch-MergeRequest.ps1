. $PSScriptRoot\Switch-MergeRequest.Labels.ps1

function Switch-MergeRequest {
	param(
		[string[]]$SetProjectForPath,
		[switch]$ResetProjectForPath
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
	if (!$labels) {
		$labels = $env:W50_MERGE_REQUEST_LABELS
	}
	
	$glabCmd = "glab mr list --output json"
	if ($labels) {
		$labelFilter = $labels -join ","
		$glabCmd += " --label `"$labelFilter`""
	}
	
	$jsonOutput = Invoke-Expression $glabCmd
	$mrList = $jsonOutput | ConvertFrom-Json
	$mr = $mrList | ForEach-Object { "$($_.iid) $($_.title)" } | fzf | ForEach-Object { ($_ -split ' ')[0] }

	if ($mr) {
		Write-Host "✅ Switching to merge request $mr" -ForegroundColor Green
		glab mr checkout $mr
	} else {
		Write-Output "No merge request selected"
	}
}

Set-Alias smr Switch-MergeRequest