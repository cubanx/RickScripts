# Dot-source common files
$CommonFiles = Get-ChildItem -Path $PSScriptRoot\Common\*.ps1 -ErrorAction SilentlyContinue
foreach ($File in $CommonFiles) {
	. $File.FullName
}

# Dot-source all function files
$FunctionFiles = Get-ChildItem -Path $PSScriptRoot\Functions\*.ps1
foreach ($File in $FunctionFiles) {
	. $File.FullName
}

# Export all functions and aliases
Export-ModuleMember -Function * -Alias *