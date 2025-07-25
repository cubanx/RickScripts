function Get-RickScriptsConfig {
    $configPath = "$env:HOME/.RickScripts/config.json"
	
    $configDir = Split-Path -Parent $configPath
    if (!(Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
	
    if (Test-Path $configPath) {
        return Get-Content $configPath | ConvertFrom-Json
    }
    else {
        return @{ projectForPath = @{} }
    }
}

function Set-RickScriptsConfig {
    param(
        [Parameter(Mandatory)]
        $Config
    )
	
    $configPath = "$env:HOME/.RickScripts/config.json"
    $Config | ConvertTo-Json -Depth 3 | Set-Content $configPath
}
