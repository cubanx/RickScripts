## Context

OpenSpec 1.x exposes change lists, task counts, and artifact status, but requires callers to name a change when several unarchived changes exist. RickScripts already depends on Git worktrees and `fzf`, and its OpenSpec publishing path already extracts change names from `openspec/changes/<name>/` paths.

## Goals / Non-Goals

**Goals:**
- Resolve the change associated with the current worktree from conservative, explainable evidence.
- Preserve an explicit override and an interactive escape hatch.
- Reuse OpenSpec's own status output and task counts.
- Remain PowerShell-only and dependency-free beyond existing tools.

**Non-Goals:**
- Do not persist a current-change marker.
- Do not inspect Codex task metadata, GitHub, or network state.
- Do not select from arbitrary historical OpenSpec commits in detached worktrees.
- Do not reproduce OpenSpec's artifact or task parser.

## Decisions

- Load candidates once from `openspec list --json`; every inferred name must exist in that list.
- Resolve in this order: explicit parameter, one dirty OpenSpec path, exact branch suffix, one OpenSpec path changed since the local `origin/HEAD` merge base, one OpenSpec path touched by `HEAD`, then a unique branch/change match sharing at least three meaningful hyphen-delimited tokens.
- Treat multiple dirty OpenSpec paths as immediately ambiguous instead of allowing weaker signals to hide concurrent work.
- Skip signals whose Git prerequisites are unavailable. Detached worktrees may resolve from dirty paths but do not use branch or history inference.
- When inference produces no unique change, send active change names to `fzf`. Missing `fzf` or cancelled selection produces a clear error.
- Run `openspec status --change <name>` for artifact output and append task progress already returned by `openspec list --json`.
- Disable OpenSpec telemetry only around those read-only CLI calls and restore the caller's process environment, avoiding OpenSpec 1.2 network-error noise.
- Export `goss` with `Set-Alias` and mirror the existing `yeet()` zsh wrapper rather than adding cross-shell argument plumbing.
- Keep the inference inside `Get-OpenSpecStatus`; a second consumer can justify extraction later.

## Risks / Trade-offs

- Branch names can resemble several changes -> require a unique highest token score and at least three shared meaningful tokens.
- Local `origin/HEAD` may be absent -> skip branch-diff inference and continue safely.
- Complete but unarchived changes remain candidates -> report their complete state because that is OpenSpec's active-change model.
- Interactive fallback is unsuitable for automation -> explicit `-Change` remains deterministic, and ambiguity without a usable picker fails closed.
