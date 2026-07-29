## 1. Shared Assessment

- [x] 1.1 Add a shared stale Git worktree assessment helper under `Common/`.
- [x] 1.2 Return stale status, skip reason, owner path, refs, `HEAD`, and short `HEAD` from the helper.

## 2. Switcher Behavior

- [x] 2.1 Update `Switch-GitWorktree` to show branch worktrees by default and detached non-bare worktrees only with `-DetachedOnly`.
- [x] 2.2 Display detached worktrees with a stable short-`HEAD` label.
- [x] 2.3 Exclude `crisp-brains` and `estate-planner` through one repository-name list.

## 3. Cleanup Behavior

- [x] 3.1 Update stale cleanup to use `Get-GitWorktrees` and the shared stale assessment.
- [x] 3.2 Preserve `ShouldProcess`, confirmation, and compatibility for the existing `Remove-StaleCodexWorktree` entrypoint.

## 4. Validation

- [x] 4.1 Add focused PowerShell checks for default and detached-only filtering and bare exclusion.
- [x] 4.2 Verify repository exclusions in both picker modes.
- [x] 4.3 Add focused PowerShell checks for stale assessment safety cases.
- [x] 4.4 Run the focused tests and strict OpenSpec validation.
