function Switch-MergeRequest {
	param(
		[string[]]$Labels = $env:W50_MERGE_REQUEST_LABELS
	)
	
	$glabCmd = "glab mr list --output json"
	if ($Labels) {
		$labelFilter = $Labels -join ","
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