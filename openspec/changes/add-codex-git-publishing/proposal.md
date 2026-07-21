## Why

The module's Git publishing workflow is split between GitLab-oriented merge-request commands and manual GitHub steps. A PowerShell-native Codex summary and GitHub publishing command will make the common workflow repeatable without adding a wrapper framework.

## What Changes

- **BREAKING** Retire `New-MergeRequest`/`nmr` and `Open-MergeRequest`/`omr`; do not alter any Bash tooling.
- Add exported `Get-CodexChangeSummary`, which obtains a structured, read-only change summary from `codex exec`.
- Add exported `Publish-GitChanges` with stable alias `yeet` to stage the complete worktree, choose a safe repository-slug branch, check the staged diff, commit, push, and create a GitHub pull request.
- When every changed path belongs to exactly one `openspec/changes/<change-name>/` directory, derive the branch, commit message, PR title, and PR body without invoking Codex; otherwise retain the Codex summary fallback.
- Update an open pull request on the current feature branch by committing and pushing without creating or retitling it; stop when an open pull request belongs to another selected branch.
- Require GitHub failures that occur before a mutation to stop the workflow, without separate `gh` version or authentication preflight commands.
- Add dependency-free PowerShell tests using mocked `codex`, `git`, and `gh`; update module exports and user-facing documentation.

## Capabilities

### New Capabilities

- `codex-change-summary`: Generate a structured, read-only Codex summary for the current Git change.
- `git-change-publishing`: Publish the complete Git worktree through a guarded GitHub pull-request workflow.

### Modified Capabilities

## Impact

- Affects PowerShell functions, `RickScripts.psm1`, `RickScripts.psd1`, and module documentation.
- Removes GitLab merge-request command exports and aliases.
- Uses only native PowerShell plus the existing `codex`, `git`, and `gh` executables; no new dependencies.
