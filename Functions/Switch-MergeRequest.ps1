function Switch-MergeRequest {
	$mr = glab mr list --output json | jq -r '.[] | "\(.iid) \(.title)"' | fzf | ForEach-Object { ($_ -split ' ')[0] }

	if ($mr) {
		Write-Output "Switching to merge request $mr"
		glab mr checkout $mr
	} else {
		Write-Output "No merge request selected"
	}
}

Set-Alias smr Switch-MergeRequest