# Dependencies and Requirements

## System Requirements
- **PowerShell Version**: 5.1 or higher
- **Operating System**: Cross-platform (developed on macOS Darwin)

## External CLI Dependencies
- **fzf** - Required for interactive selection in most functions
- **glab** - GitLab CLI for MR operations (`New-MergeRequest`, `Move-IssueState`)
- **fd** - Fast directory search for `Open-ProjectFolder`
- **jq** - JSON processing for `Switch-MergeRequest`
- **pnpm** - Package manager for `Clear-NodeModules`
- **1Password CLI (op)** - Required for `Add-EnvTo1Password` and `Get-EnvFrom1Password`
- **git** - Git operations for branch management functions

## Optional Dependencies
- **VS Code (code)** - For `Open-ProjectFolder` function
- **World50 validation scripts** - For `Invoke-ValidationScript` function

## Installation Method
- Copy entire module directory to PowerShell modules path
- OR use `Import-Module` with module path
- Individual functions can be loaded with `. ./Functions/FunctionName.ps1`

## Module Loading
- Functions are automatically loaded from `Functions/` directory (including subdirectories)
- Common utilities loaded from `Common/` directory
- All functions and aliases exported using `Export-ModuleMember -Function * -Alias *`