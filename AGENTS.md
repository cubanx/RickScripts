# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

This is a PowerShell module called `RickScripts` containing personal development utilities and Git workflow helpers. The module is structured as a standard PowerShell module with:

- **Module manifest**: `RickScripts.psd1` - defines exported functions, aliases, and variables
- **Module file**: `RickScripts.psm1` - auto-loads all functions from the Functions directory
- **Functions directory**: Contains individual `.ps1` files for each function

## Commands

### Module Management
- **Install module**: Copy the entire directory to PowerShell modules path or use `Import-Module`
- **Test functions**: Load individual functions with `. ./Functions/FunctionName.ps1`
- **No build/test/lint commands**: This is a simple PowerShell module with no formal build process

### Available Functions and Aliases
- `Switch-Branch` (`sb`) - Interactive branch switching with fzf
- `Switch-MergeRequest` (`smr`) - Interactive MR checkout with fzf  
- `Remove-LocalBranchesThatAreMerged` (`rlb`) - Clean up merged branches
- `Clear-NodeModules` (`cnm`) - Remove node_modules and reinstall with pnpm
- `Open-ProjectFolder` (`opf`) - Open directory in VS Code using fzf
- `New-MergeRequest` (`nmr`) - Create GitLab MR with template
- `Get-GitStash` (`ggs`) - Interactive stash selection and pop with fzf
- `Remove-HistoryItem` (`rhi`) - Remove items from PowerShell history interactively
- `Remove-HistoryDuplicates` (`rhd`) - Remove duplicate entries from PowerShell history
- `Move-IssueState` (`mis`) - Move GitLab issues between states
- `New-CalendarEvent` - Create calendar events
- `Invoke-ValidationScript` (`ivs`) - Run World50 validation scripts interactively
- `Add-EnvTo1Password` (`ae1p`) - Add environment variables to 1Password
- `Get-EnvFrom1Password` (`ge1p`) - Retrieve environment variables from 1Password

## Architecture

### Module Structure
The module follows PowerShell best practices:
- Each function is in its own file in `/Functions/`
- Functions are dot-sourced in `RickScripts.psm1`
- Aliases are defined in individual function files and exported in the module file

### Key Dependencies
- **fzf** - Required for interactive selection in most functions
- **glab** - GitLab CLI for MR operations
- **fd** - Fast directory search for Open-ProjectFolder
- **jq** - JSON processing for Switch-MergeRequest
- **pnpm** - Package manager for Clear-NodeModules
- **1Password CLI (op)** - Required for Add-EnvTo1Password and Get-EnvFrom1Password

## Function Categories

### Git Workflow Functions
- `Switch-Branch` - Branch management with remote tracking
- `Switch-MergeRequest` - MR-based development workflow
- `Remove-LocalBranchesThatAreMerged` - Branch cleanup
- `New-MergeRequest` - Automated MR creation with templates
- `Get-GitStash` - Stash management
- `Move-IssueState` - Move GitLab issues between workflow states

### Development Utilities  
- `Clear-NodeModules` - Node.js project maintenance
- `Open-ProjectFolder` - Project navigation
- `Invoke-ValidationScript` - Run validation scripts interactively for World50 projects

### PowerShell History Management
- `Remove-HistoryItem` - Remove specific items from PowerShell command history
- `Remove-HistoryDuplicates` - Clean up duplicate entries in PowerShell history

### Environment & Secrets Management
- `Add-EnvTo1Password` - Store environment variables in 1Password with hierarchical tags
- `Get-EnvFrom1Password` - Retrieve environment variables from 1Password

### Productivity Tools
- `New-CalendarEvent` - Create calendar events programmatically

### Template Processing
`New-MergeRequest` processes GitLab MR templates by:
- Reading template from `.gitlab/merge_request_templates/prospector.md` (changed from Default.md)
- Removing mobile-specific content and environment sections
- Auto-populating issue numbers and titles from GitLab API
- Setting consistent MR options (draft, remove source branch, etc.)

### Environment Files Structure
The module includes an `Env/` subdirectory containing:
- `Add-EnvTo1Password.ps1` - Function for storing environment variables in 1Password
- `Get-EnvFrom1Password.ps1` - Function for retrieving environment variables from 1Password

### Supporting Files
- `Switch-MergeRequest.Labels.ps1` - Label configuration support for merge request functions