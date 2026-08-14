## Why

OpenSpec reports a named change's progress but does not identify which change belongs to the current Git worktree. A RickScripts command can infer that association from existing Git and OpenSpec state while refusing ambiguous guesses.

## What Changes

- Add an exported `Get-OpenSpecStatus` PowerShell command that accepts an optional explicit change name.
- Infer the current change from unique dirty OpenSpec paths, the current branch, branch changes, the current commit, or a conservative branch-token match.
- Fall back to interactive `fzf` selection when inference is ambiguous and fail clearly when interaction is unavailable.
- Delegate status reporting to the OpenSpec CLI instead of reproducing its progress logic.
- Export `goss` as the PowerShell alias and add a matching no-argument zsh wrapper beside `yeet`.

## Capabilities

### New Capabilities
- `openspec-current-status`: Conservative current-change inference and native OpenSpec status reporting for the current Git worktree.

### Modified Capabilities

## Impact

- Adds `Functions/Get-OpenSpecStatus.ps1` and focused Pester coverage.
- Updates module exports and user documentation.
- Updates the managed dotfiles `.zshrc` wrapper surface.
- Reuses Git, OpenSpec, and the module's existing `fzf` dependency; adds no dependency or persisted current-change state.
