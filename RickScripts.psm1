# Dot-source all function files
$FunctionFiles = Get-ChildItem -Path $PSScriptRoot\Functions\*.ps1
foreach ($File in $FunctionFiles) {
    . $File.FullName
}

# Export functions
Export-ModuleMember -Function Switch-Branch, Switch-MergeRequest, Remove-LocalBranchesThatAreMerged, Clear-NodeModules, Open-ProjectFolder, New-MergeRequest, Get-GitStash

# Export aliases
Export-ModuleMember -Alias sb, smr, rlb, cnm, opf, nmr, ggs

# Export global variables for package filters
$global:mem = "--filter=@world50/member-app"
$global:gl = "--filter=@world50/group-leader-app"
$global:pro = "--filter=@world50/prospector-app"
$global:auth = "--filter=@world50/authentication-app"
$global:petl = "--filter=@world50/prospector-etl"
