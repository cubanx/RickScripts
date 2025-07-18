function Open-ProjectFolder {
	[CmdletBinding()]
	param()
	
	Get-ChildItem -Path "apps", "packages" -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | fzf | ForEach-Object { 
		$selectedName = $_
		$fullPath = Get-ChildItem -Path "apps", "packages" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $selectedName } | Select-Object -First 1 -ExpandProperty FullName
		Write-Debug "Opening: $fullPath"
		code $fullPath
	}
}

Set-Alias opf Open-ProjectFolder