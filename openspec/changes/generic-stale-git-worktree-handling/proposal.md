## Why

`Switch-GitWorktree` currently hides detached worktrees because it inherited Codex-specific stale-worktree behavior. Detached worktrees are not inherently stale, and the generic Git switcher should let intentional detached checkouts appear while cleanup uses a stricter safety rubric.

## What Changes

- Add a generic stale Git worktree assessment shared by worktree-switching and stale-worktree cleanup commands.
- Keep bare worktrees out of interactive switching.
- Include detached non-bare worktrees in `Switch-GitWorktree` with a clear display label based on branch name or short `HEAD`.
- Treat a worktree as stale only when it is detached, clean, has no unique commits, has `HEAD` reachable from an existing ref, and can be removed from another worktree for the same repository.
- Replace Codex-specific stale cleanup behavior with generic Git worktree cleanup behavior while preserving safe removal checks.

## Capabilities

### New Capabilities
- `git-worktree-stale-handling`: Shared behavior for displaying, assessing, and safely cleaning up Git worktrees.

### Modified Capabilities

## Impact

- Affects `Functions/Switch-GitWorktree.ps1`, `Functions/Get-GitWorktrees.ps1`, and `Functions/Remove-StaleCodexWorktree.ps1`.
- May affect manifest exports and aliases if stale cleanup is renamed or given a generic alias.
- Adds focused PowerShell tests for detached worktree display and stale assessment safety.
- No new external dependencies.
