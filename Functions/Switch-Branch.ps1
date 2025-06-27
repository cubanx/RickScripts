function Switch-Branch {
	git fetch
	$branchName = git branch --all | fzf | ForEach-Object { $_ -replace '\s', '' }
	Write-Output "Checking out $branchName"

	if ($branchName -match "origin") {
		git checkout -t $branchName
	} else {
		git switch $branchName
	}
}

Set-Alias sb Switch-Branch