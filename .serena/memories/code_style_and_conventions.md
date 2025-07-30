# PowerShell Code Style and Conventions

## Code Style Patterns

### Function Structure
- Functions use PascalCase naming: `Switch-Branch`, `New-MergeRequest`
- Use approved PowerShell verbs (New-, Get-, Set-, Remove-, etc.)
- Each function is in its own `.ps1` file in the Functions directory

### Parameter Handling
- Use `[CmdletBinding()]` with appropriate attributes:
  - `SupportsShouldProcess = $true` for functions that make changes
- Parameters use typed declarations: `[string]$Title`, `[int]$IssueNumber`
- Use `[ValidateSet()]` for constrained parameter values
- Default parameter values are set in param block

### Aliases
- Aliases are defined at the end of each function file using `Set-Alias`
- Aliases are typically 2-4 character abbreviations of the function name
- All aliases are exported in the module manifest

### Error Handling
- Use `Write-Error` for error conditions with `exit 1`
- Use `Test-Path` to verify file existence before operations
- Use `try/finally` blocks with `Push-Location`/`Pop-Location` for directory changes

### Output
- Use `Write-Output` for informational messages
- Use `Write-Host` with `-ForegroundColor` for colored output
- No extensive inline comments (per CLAUDE.md instructions)

### Module Structure
- All functions are dot-sourced in `RickScripts.psm1`
- Common utilities stored in `Common/` directory
- Environment-specific functions in `Functions/Env/` subdirectory