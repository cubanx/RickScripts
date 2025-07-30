# Suggested Commands for RickScripts Development

## Module Management Commands

### Install/Import Module
```powershell
# Import module from current directory
Import-Module ./RickScripts.psd1

# Copy to PowerShell modules directory (for permanent installation)
Copy-Item -Recurse ./RickScripts $env:PSModulePath.Split(';')[0]
```

### Test Individual Functions
```powershell
# Load and test a single function
. ./Functions/Switch-Branch.ps1
Switch-Branch
```

### Verify Module Structure
```powershell
# Check exported functions and aliases
Get-Module RickScripts | Select-Object ExportedFunctions, ExportedAliases
```

## Development Commands

### Git Operations (no specific build/test/lint process)
```bash
# Standard git workflow
git status
git add .
git commit -m "feat:Your change description"
git push -u origin branch-name
```

### Verify Dependencies
```powershell
# Check for required external tools
Get-Command fzf, glab, fd, jq, pnpm, op -ErrorAction SilentlyContinue
```

## macOS (Darwin) System Commands
- `ls` - List directory contents
- `find` - Search for files and directories  
- `grep` - Search text patterns
- `cd` - Change directory
- `git` - Git version control
- `code` - VS Code editor

## No Build Process
This is a simple PowerShell module with no formal build, test, or lint commands. Functions are loaded directly via dot-sourcing.