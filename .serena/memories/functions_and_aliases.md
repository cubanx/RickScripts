# RickScripts Functions and Aliases

## Available Functions and Corresponding Aliases

### Git Workflow Functions
- `Switch-Branch` (`sb`) - Interactive branch switching with fzf
- `Switch-MergeRequest` (`smr`) - Interactive MR checkout with fzf  
- `Remove-LocalBranchesThatAreMerged` (`rlb`) - Clean up merged branches
- `New-MergeRequest` (`nmr`) - Create GitLab MR with template
- `Get-GitStash` (`ggs`) - Interactive stash selection and pop with fzf
- `Move-IssueState` (`mis`) - Move GitLab issues between states

### Development Utilities  
- `Clear-NodeModules` (`cnm`) - Remove node_modules and reinstall with pnpm
- `Open-ProjectFolder` (`opf`) - Open directory in VS Code using fzf
- `Invoke-ValidationScript` (`ivs`) - Run World50 validation scripts interactively

### PowerShell History Management
- `Remove-HistoryItem` (`rhi`) - Remove items from PowerShell history interactively
- `Remove-HistoryDuplicates` (`rhd`) - Remove duplicate entries from PowerShell history

### Environment & Secrets Management
- `Add-EnvTo1Password` (`ae1p`) - Add environment variables to 1Password
- `Get-EnvFrom1Password` (`ge1p`) - Retrieve environment variables from 1Password

### Productivity Tools
- `New-CalendarEvent` - Create calendar events programmatically

## Exported Variables
- `mem`, `gl`, `pro`, `auth`, `petl` - World50 application package filters