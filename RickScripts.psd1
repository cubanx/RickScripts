@{
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Rick Diaz'
    Description = 'Personal PowerShell scripts and utilities'
    PowerShellVersion = '5.1'
    
    # Script module or binary module file associated with this manifest
    RootModule = 'RickScripts.psm1'
    
    # Functions to export from this module
    FunctionsToExport = @(
        'Switch-Branch',
        'Switch-MergeRequest', 
        'Remove-LocalBranchesThatAreMerged',
        'Clear-NodeModules',
        'Open-ProjectFolder',
        'New-MergeRequest',
        'Copy-MergeRequest',
        'Get-GitStash',
        'Remove-HistoryItem',
        'Remove-HistoryDuplicates',
        'Move-IssueState',
        'New-CalendarEvent',
        'Invoke-ValidationScript',
        'Invoke-ValidationSuite',
        'Add-EnvTo1Password',
        'Get-EnvFrom1Password',
        'New-ClaudeAgent',
        'Add-MeetingRoom',
        'Publish-Config',
        'Open-MergeRequest',
        'Edit-Config',
        'Convert-MarkdownToPdf'
    )
    
    # Aliases to export from this module
    AliasesToExport = @('sb', 'smr', 'rlb', 'cnm', 'opf', 'nmr', 'cmr', 'ggs', 'rhi', 'rhd', 'mis', 'ivs', 'ae1p', 'ge1p', 'nca', 'ivsuite', 'amr', 'omr', 'ec')
    
    # Variables to export from this module
    VariablesToExport = @('mem', 'gl', 'pro', 'auth', 'petl')
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            Tags = @('Git', 'Development', 'Utilities')
            ProjectUri = ''
            LicenseUri = ''
            ReleaseNotes = 'Initial release of RickScripts module'
        }
    }
}
