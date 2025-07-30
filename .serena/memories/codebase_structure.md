# RickScripts Codebase Structure

## Directory Layout
```
RickScripts/
├── .serena/                    # Serena configuration
├── Bash/                       # Legacy bash translations (unmaintained)
├── Common/                     # Shared utility files
│   ├── Config.ps1             # Configuration utilities
│   ├── GoogleCalendarAuth.ps1 # Calendar authentication
│   └── DateParser.ps1         # Date parsing utilities
├── Functions/                  # Main function implementations
│   ├── Env/                   # Environment management functions
│   │   ├── Add-EnvTo1Password.ps1
│   │   └── Get-EnvFrom1Password.ps1
│   ├── Switch-Branch.ps1
│   ├── Switch-MergeRequest.ps1
│   ├── New-MergeRequest.ps1
│   ├── Remove-LocalBranchesThatAreMerged.ps1
│   ├── Clear-NodeModules.ps1
│   ├── Open-ProjectFolder.ps1
│   ├── Get-GitStash.ps1
│   ├── Remove-HistoryItem.ps1
│   ├── Remove-HistoryDuplicates.ps1
│   ├── Move-IssueState.ps1
│   ├── New-CalendarEvent.ps1
│   ├── Invoke-ValidationScript.ps1
│   └── Switch-MergeRequest.Labels.ps1
├── RickScripts.psd1           # Module manifest
├── RickScripts.psm1           # Module loader
└── CLAUDE.md                  # Development guidelines
```

## Function Categories

### Git Workflow (6 functions)
- Branch management, MR operations, stash handling, issue tracking

### Development Utilities (3 functions)  
- Node.js project maintenance, project navigation, validation scripts

### History Management (2 functions)
- PowerShell command history cleanup and management

### Environment Management (2 functions)
- 1Password integration for environment variables

### Productivity (1 function)
- Calendar event creation

## Module Loading Process
1. `RickScripts.psm1` dot-sources all files in `Common/` directory
2. Recursively dot-sources all `.ps1` files in `Functions/` directory  
3. Exports all functions and aliases with `Export-ModuleMember -Function * -Alias *`