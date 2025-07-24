function Get-ProjectLabels {
	param(
		[string]$FolderName = (Split-Path -Leaf (Get-Location))
	)
	
	$config = Get-RickScriptsConfig
	if ($config.projectForPath -and $config.projectForPath.$FolderName) {
		return $config.projectForPath.$FolderName
	}
	return $null
}

function Set-ProjectLabels {
	param(
		[Parameter(Mandatory)]
		[string[]]$Labels,
		[string]$FolderName = (Split-Path -Leaf (Get-Location))
	)
	
	$config = Get-RickScriptsConfig
	if (!$config.projectForPath) {
		$config.projectForPath = @{}
	}
	
	# Convert to hashtable to avoid PSObject property issues
	$projectForPath = @{}
	if ($config.projectForPath -is [PSCustomObject]) {
		$config.projectForPath.PSObject.Properties | ForEach-Object {
			$projectForPath[$_.Name] = $_.Value
		}
	} else {
		$projectForPath = $config.projectForPath
	}
	
	$projectForPath[$FolderName] = $Labels
	$config.projectForPath = $projectForPath
	Set-RickScriptsConfig -Config $config
}

function Remove-ProjectLabels {
	param(
		[string]$FolderName = (Split-Path -Leaf (Get-Location))
	)
	
	$config = Get-RickScriptsConfig
	if ($config.projectForPath) {
		# Convert to hashtable to avoid PSObject property issues
		$projectForPath = @{}
		if ($config.projectForPath -is [PSCustomObject]) {
			$config.projectForPath.PSObject.Properties | ForEach-Object {
				if ($_.Name -ne $FolderName) {
					$projectForPath[$_.Name] = $_.Value
				}
			}
		} else {
			$projectForPath = $config.projectForPath.Clone()
			$projectForPath.Remove($FolderName)
		}
		
		$config.projectForPath = $projectForPath
		Set-RickScriptsConfig -Config $config
	}
}