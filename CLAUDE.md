# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

## Architecture

### Module Structure
The module follows PowerShell best practices:
- Each function is in its own file in `/Functions/`
- Functions are dot-sourced in `RickScripts.psm1`
- Aliases are defined in individual function files and exported in the module file
- Global variables for package filters are defined in the module file

### Key Dependencies
- **fzf** - Required for interactive selection in most functions
- **glab** - GitLab CLI for MR operations
- **fd** - Fast directory search for Open-ProjectFolder
- **jq** - JSON processing for Switch-MergeRequest
- **pnpm** - Package manager for Clear-NodeModules

### Global Variables
The module exports package filter variables for World50 applications:
- `$global:mem` - Member app filter
- `$global:gl` - Group leader app filter  
- `$global:pro` - Prospector app filter
- `$global:auth` - Authentication app filter
- `$global:petl` - Prospector ETL filter

## Function Categories

### Git Workflow Functions
- `Switch-Branch` - Branch management with remote tracking
- `Switch-MergeRequest` - MR-based development workflow
- `Remove-LocalBranchesThatAreMerged` - Branch cleanup
- `New-MergeRequest` - Automated MR creation with templates
- `Get-GitStash` - Stash management

### Development Utilities  
- `Clear-NodeModules` - Node.js project maintenance
- `Open-ProjectFolder` - Project navigation

### Template Processing
`New-MergeRequest` processes GitLab MR templates by:
- Reading template from `.gitlab/merge_request_templates/Default.md`
- Removing mobile-specific content and environment sections
- Auto-populating issue numbers and titles from GitLab API
- Setting consistent MR options (draft, remove source branch, etc.)