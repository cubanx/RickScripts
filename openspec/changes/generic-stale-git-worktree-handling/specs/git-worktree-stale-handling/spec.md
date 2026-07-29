## ADDED Requirements

### Requirement: Branch and detached worktrees have separate picker views
`Switch-GitWorktree` SHALL exclude detached worktrees by default and SHALL show only detached non-bare worktrees when invoked with `-DetachedOnly`.

#### Scenario: Default picker excludes detached worktree
- **WHEN** Git reports a non-bare worktree with detached `HEAD`
- **THEN** `Switch-GitWorktree` excludes the worktree from the default picker

#### Scenario: Detached-only picker
- **WHEN** `Switch-GitWorktree` is invoked with `-DetachedOnly`
- **THEN** it lists only detached non-bare worktrees with a detached `HEAD` label and path

#### Scenario: Bare worktree stays hidden
- **WHEN** Git reports a bare worktree
- **THEN** `Switch-GitWorktree` excludes the worktree from the picker

### Requirement: Listed repositories are excluded
`Switch-GitWorktree` SHALL exclude every worktree whose repository name appears in its exclusion list from both picker views. The list SHALL include `crisp-brains` and `estate-planner`.

#### Scenario: Excluded repository has a branch worktree
- **WHEN** Git reports a branch worktree for an excluded repository
- **THEN** `Switch-GitWorktree` excludes it from the default picker

#### Scenario: Excluded repository has a detached worktree
- **WHEN** Git reports a detached worktree for an excluded repository
- **THEN** `Switch-GitWorktree -DetachedOnly` excludes it from the picker

### Requirement: Stale assessment is shared
The module SHALL use one shared stale-worktree assessment for worktree switching and stale cleanup behavior.

#### Scenario: Shared stale result is reused
- **WHEN** a cmdlet needs to decide whether a worktree is stale
- **THEN** it uses the shared stale-worktree assessment instead of duplicating the rubric

### Requirement: Stale worktree requires full safety rubric
A worktree SHALL be considered stale only when it is detached, clean, has no unique commits, has `HEAD` reachable from an existing branch, remote, or tag, and has another worktree from the same repository available to remove it.

#### Scenario: Branched worktree is not stale
- **WHEN** a worktree has a checked-out branch
- **THEN** the stale assessment marks it as not stale

#### Scenario: Dirty detached worktree is not stale
- **WHEN** a detached worktree has tracked or untracked changes
- **THEN** the stale assessment marks it as not stale

#### Scenario: Detached worktree with unique commits is not stale
- **WHEN** a detached worktree has commits not reachable from branches, remotes, or tags
- **THEN** the stale assessment marks it as not stale

#### Scenario: Reachable clean detached worktree is stale
- **WHEN** a detached worktree is clean, has no unique commits, has `HEAD` reachable from a branch, remote, or tag, and has another worktree owner path
- **THEN** the stale assessment marks it as stale

### Requirement: Generic cleanup preserves safety
The stale cleanup command SHALL remove only worktrees that satisfy the shared stale-worktree assessment and SHALL preserve confirmation and `ShouldProcess` safeguards.

#### Scenario: Cleanup skips intentional detached checkout
- **WHEN** a detached worktree fails any stale safety check
- **THEN** stale cleanup does not offer it for removal

#### Scenario: Cleanup removes only confirmed stale candidates
- **WHEN** stale cleanup finds removable candidates
- **THEN** it lists them before removal and requires the existing confirmation flow unless forced or running under `WhatIf`
