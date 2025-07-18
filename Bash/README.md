# RickScripts - Bash Version

This directory contains bash translations of all the PowerShell functions in the parent `Functions` directory.

## ⚠️ Important Disclaimer

**These are AI-generated translations of PowerShell functions and are completely untested.** 

We have no idea if they actually work correctly. Use at your own risk and expect bugs, errors, and potentially broken functionality. These translations were created as a learning exercise and proof of concept, not as production-ready tools.

Please test thoroughly before using in any important workflows!

## Installation

To use these bash functions, source the main script in your shell profile:

```bash
# Add to ~/.bashrc or ~/.zshrc
source /path/to/RickScripts/Bash/rick-scripts.sh
```

Or source it manually in your current session:

```bash
source ./rick-scripts.sh
```

## Bash Completion

The functions include full bash completion support for parameters and options. Tab completion is automatically loaded when you source the main script and provides:

- Function name completion (try typing `move_` and press Tab)
- Parameter completion (try typing `mis -` and press Tab)
- Value completion for specific parameters:
  - `--state` parameter completes with valid states: `ToDo`, `InDev`, `AwaitingReview`, `Done`
  - `--template` parameter completes with file paths
  - All functions support `--help` completion

### Examples of Tab Completion:

```bash
# Complete function names
move_<TAB>          # Completes to move_issue_state
mis <TAB>           # Shows available parameters: -i, --issue, -s, --state, etc.
mis --state <TAB>   # Shows: ToDo InDev AwaitingReview Done
nmr --<TAB>         # Shows all new_merge_request parameters
```

## Available Functions

### Git Workflow Functions

- **`switch_branch` (alias: `sb`)** - Interactive branch switching with fzf
- **`switch_merge_request` (alias: `smr`)** - Interactive MR checkout with fzf  
- **`remove_local_branches_that_are_merged` (alias: `rlb`)** - Clean up merged branches
- **`move_issue_state` (alias: `mis`)** - Move GitLab issues between workflow states
- **`new_merge_request` (alias: `nmr`)** - Create GitLab MR with template
- **`get_git_stash` (alias: `ggs`)** - Interactive stash selection and pop with fzf

### Development Utilities

- **`clear_node_modules` (alias: `cnm`)** - Remove node_modules and reinstall with pnpm
- **`open_project_folder` (alias: `opf`)** - Open directory in VS Code using fzf

### History Management

- **`remove_history_duplicates` (alias: `rhd`)** - Remove duplicate entries from bash history
- **`remove_history_item` (alias: `rhi`)** - Remove specific items from bash history

## Dependencies

These functions require the following external tools:

- **fzf** - Required for interactive selection in most functions
- **glab** - GitLab CLI for MR operations
- **fd** - Fast directory search for open_project_folder
- **jq** - JSON processing for switch_merge_request
- **pnpm** - Package manager for clear_node_modules
- **code** - VS Code CLI for opening projects

## Global Variables

The following package filter variables are exported for World50 applications:

- `$mem` - Member app filter
- `$gl` - Group leader app filter  
- `$pro` - Prospector app filter
- `$auth` - Authentication app filter
- `$petl` - Prospector ETL filter

## Usage Examples

```bash
# Switch to a different branch interactively
sb

# Create a new merge request
nmr -i 123 -t "Fix user authentication"

# Move an issue to "In Dev" state
mis -s InDev -i 456

# Remove duplicate history entries
rhd

# Clean up merged branches
rlb

# Pop a stash interactively
ggs
```

## Differences from PowerShell Version

1. **Command-line Arguments**: Bash versions use traditional CLI arguments (`-i`, `-s`, etc.) instead of PowerShell parameters
2. **Debug Output**: Controlled by explicit `--debug` flags instead of `Write-Debug`
3. **Confirmation**: Uses `read -p` prompts instead of PowerShell's `ShouldProcess`
4. **History Files**: Works with `$HISTFILE` (bash history) instead of PowerShell's history system
5. **JSON Parsing**: Uses `jq` instead of PowerShell's `ConvertFrom-Json`

## Individual Function Files

Each function is implemented in its own `.sh` file for modularity:

- `clear-node-modules.sh`
- `get-git-stash.sh`
- `move-issue-state.sh`
- `new-merge-request.sh`
- `open-project-folder.sh`
- `remove-history-duplicates.sh`
- `remove-history-item.sh`
- `remove-local-branches-that-are-merged.sh`
- `switch-branch.sh`
- `switch-merge-request.sh`

You can also source individual function files if you only need specific functionality.