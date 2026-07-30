## Context

`Switch-GitWorktree` discovers registered Git worktrees through `Get-GitWorktrees`. Branch and detached worktrees need separate picker views, while bare worktrees remain hidden. `Remove-StaleCodexWorktree` already has the safer stale rubric, but that logic is embedded in a Codex-specific command.

## Goals / Non-Goals

**Goals:**
- Share one stale-worktree assessment between switching and cleanup.
- Show branch worktrees by default and detached non-bare worktrees only with `-DetachedOnly`.
- Keep intentionally unused repositories out of every picker view.
- Keep cleanup conservative enough that detached review checkouts are not removed just because they are detached.
- Keep the implementation PowerShell-only and dependency-free.

**Non-Goals:**
- Do not change `Get-GitWorktrees` into a full Git inventory system.
- Do not remove worktrees from `Switch-GitWorktree`.
- Do not add new prompts, persistence, or configuration unless the existing command already needs a confirmation.

## Decisions

- Add a small shared helper in `Common/` for stale assessment. `RickScripts.psm1` already dot-sources `Common/*.ps1`, so both cmdlets can reuse it without import ceremony.
- Keep `Get-GitWorktrees` focused on listing metadata from `git worktree list --porcelain`. Stale assessment needs extra Git checks and should stay outside the metadata parser.
- Filter on existing `IsDetached` metadata in `Switch-GitWorktree`; `-DetachedOnly` selects detached entries and the default selects branch entries.
- Keep excluded repository names in one local list in `Switch-GitWorktree`; another repository requires adding one name, not another condition.
- Display detached worktrees with a stable label such as `(detached <short-sha>)`.
- Generalize cleanup by reusing the shared assessment and Git porcelain metadata, while preserving the existing safe-removal checks and `SupportsShouldProcess` behavior.
- Keep `Remove-StaleCodexWorktree` as a compatibility wrapper or alias if the implementation renames the generic cleanup command.

## Risks / Trade-offs

- Generic cleanup may expose more worktrees than the Codex-only scan did -> limit stale candidates to worktrees returned by Git and require the full safety rubric.
- Detached labels are less descriptive than branch names -> include repository name and path in the detached-only picker row.
- Shared helper can become overbuilt -> return a simple object with `IsStale`, `Reason`, owner path, refs, and `HEAD` details only.
