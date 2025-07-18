function Switch-MergeRequest {
	$mr = glab mr list --output json | jq -r '.[] | "\(.iid) \(.title)"' | fzf | ForEach-Object { ($_ -split ' ')[0] }

	if ($mr) {
		Write-Host "✅ Switching to merge request $mr" -ForegroundColor Green
		glab mr checkout $mr
	} else {
		Write-Output "No merge request selected"
	}
}

Set-Alias smr Switch-MergeRequest