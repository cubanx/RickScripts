# Dot-source all function files
$FunctionFiles = Get-ChildItem -Path $PSScriptRoot\Functions\*.ps1
foreach ($File in $FunctionFiles) {
	. $File.FullName
}

# Export functions
Export-ModuleMember -Function Switch-Branch, Switch-MergeRequest, Remove-LocalBranchesThatAreMerged, Clear-NodeModules, Open-ProjectFolder, New-MergeRequest, Get-GitStash, Remove-HistoryItem, Remove-HistoryDuplicates, Move-IssueState

# Export aliases
Export-ModuleMember -Alias sb, smr, rlb, cnm, opf, nmr, ggs, rhi, rhd, mis