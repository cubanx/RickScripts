## Why

Detached worktrees can crowd the normal `Switch-GitWorktree` picker. The default view should focus on branch worktrees while still providing an explicit detached-only view.

## What Changes

- Add a generic stale Git worktree assessment shared by worktree-switching and stale-worktree cleanup commands.
- Keep bare worktrees out of interactive switching.
- Hide detached worktrees from `Switch-GitWorktree` by default and add `-DetachedOnly` to show only detached non-bare worktrees with a short `HEAD` label.
- Exclude worktrees from repositories listed by name in the switcher, initially `crisp-brains` and `estate-planner`.
- Treat a worktree as stale only when it is detached, clean, has no unique commits, has `HEAD` reachable from an existing ref, and can be removed from another worktree for the same repository.
- Replace Codex-specific stale cleanup behavior with generic Git worktree cleanup behavior while preserving safe removal checks.

## Capabilities

### New Capabilities
- `git-worktree-stale-handling`: Shared behavior for displaying, assessing, and safely cleaning up Git worktrees.

### Modified Capabilities

## Impact

- Affects `Functions/Switch-GitWorktree.ps1`, `Functions/Get-GitWorktrees.ps1`, and `Functions/Remove-StaleCodexWorktree.ps1`.
- May affect manifest exports and aliases if stale cleanup is renamed or given a generic alias.
- Adds focused PowerShell tests for default and detached-only worktree filtering and stale assessment safety.
- No new external dependencies.
