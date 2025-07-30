# RickScripts PowerShell Module Overview

## Purpose
RickScripts is a personal PowerShell module containing development utilities and Git workflow helpers designed to streamline common development tasks and workflows.

## Module Structure
- **Module Manifest**: `RickScripts.psd1` - defines exported functions, aliases, and variables
- **Module File**: `RickScripts.psm1` - auto-loads all functions from Functions directory
- **Functions Directory**: Contains individual `.ps1` files for each function
- **Common Directory**: Shared utility files (Config, Auth, DateParser)
- **Bash Directory**: Legacy bash translations (no longer maintained)

## Tech Stack
- **Language**: PowerShell 5.1+
- **Module Type**: Script module
- **Dependencies**: External CLI tools (fzf, glab, fd, jq, pnpm, 1Password CLI)

## Key Features
- Git workflow automation (branch switching, MR creation, stash management)
- Development utilities (node_modules cleanup, project navigation)
- PowerShell history management
- Environment variable management with 1Password integration
- GitLab issue management
- Calendar event creation