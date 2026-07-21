## Context

`RickScripts` is a PowerShell module. Its existing merge-request commands target GitLab, while the intended publishing path is GitHub pull requests. The new commands must remain thin wrappers around `codex`, `git`, and `gh`, and must be testable by mocking those executables.

## Goals / Non-Goals

**Goals:**
- Provide a read-only, structured Codex change-summary command.
- Provide one exported GitHub publishing command that owns guarded staging, branch selection, commit, push, PR creation, and PR presentation.
- Keep the workflow safe before mutations and explicit about the full-tree staging boundary.

**Non-Goals:**
- Do not modify Bash tooling.
- Do not add a GitHub SDK, configuration file, authentication/version preflight, interactive wizard, or persistent state.
- Do not preserve GitLab merge-request compatibility after the retired command exports are removed.

## Decisions

- `Get-CodexChangeSummary` invokes `codex exec --ephemeral --sandbox read-only` with both `--output-schema` and `--output-last-message`, returning structured fields for what changed, why, user impact, developer impact, validation, and a human title.
- `Publish-GitChanges` uses native PowerShell orchestration over `git` and `gh`; executable calls are isolated behind small command-invocation seams so dependency-free tests can mock them. Adding Pester or a wrapper library is unnecessary.
- Before mutation, the command validates accessible `origin` and queries GitHub for an existing pull request. It does not run standalone `gh --version` or `gh auth status`; a required `gh` failure stops the command with its diagnostic.
- The parameter surface is intentionally small: optional `-BranchName`, optional `-BaseBranch` defaulting to the remote default branch, and `-Ready`, which changes the default draft PR into a ready PR. There are no `-Path` or `-All` staging parameters.
- On an existing non-default feature branch the command remains on that branch. From a detached `HEAD` or default branch it creates the supplied `-BranchName` or derives a branch using the exact repository slug: `dw` for `data-warehouse`, `ia` for `internal-apps`, `ea` for `external-api`; otherwise initials from hyphen-separated or CamelCase repository names. Generic `codex/` names are prohibited.
- Publishing stages with `git add -A`, then runs `git diff --cached --check` and inspects the staged diff before committing. This intentionally includes the complete worktree rather than hiding untracked or unstaged files.
- When every status entry is under exactly one `openspec/changes/<change-name>/` directory, publishing uses `<repo-slug>/<change-name>`, `docs: add <space-separated-change-name-with-leading-add-removed> OpenSpec`, the matching `Add ... OpenSpec` human title, and a deterministic specification-only summary. This path does not invoke Codex. Multiple OpenSpec changes or any non-OpenSpec path use the normal Codex fallback.
- A matching existing PR on the current feature branch selects update mode: stage, validate, commit, and push, then report the existing PR without creating or retitling it.
- Outside the deterministic OpenSpec-only path, `Publish-GitChanges` calls `Get-CodexChangeSummary` exactly once. It writes a temporary Markdown PR body from the selected summary plus actual diff-check evidence, covering what changed, why, user/developer impact, and validation; it cleans up the temporary body after use.
- PR creation defaults to draft; `-Ready` creates a ready PR. After creation, the final title is `[<repo-slug>-#<number>] <human title>`, and final output includes branch, commit SHA, URL, title, and worktree status.
- Failures stop safely: no stash, reset, force operation, destructive cleanup, or swallowed exception is permitted.
- Retired functions and aliases are removed from function loading, manifest exports, and documentation. Other GitLab-oriented functions remain untouched unless they specifically expose the retired commands.

## Risks / Trade-offs

- Full-tree staging can include unrelated local changes → require staged-diff review and make the all-files boundary explicit in command help and docs.
- A failed push or PR request can leave a local commit or remote branch → stop at the failed command and report exact state; do not attempt destructive rollback.
- GitHub query/auth failures can be network or credential failures → fail before mutation rather than guessing that no PR exists.
- Numbering a newly created PR title requires a follow-up GitHub title update → update only after successful creation and stop on update failure.
- Deterministic OpenSpec metadata depends on a clear change ID → use it only for exactly one matching change directory and fall back to Codex for mixed or ambiguous scopes.

## Migration Plan

1. Add functions, aliases, exports, documentation, and mocked tests.
2. Remove `New-MergeRequest`/`nmr` and `Open-MergeRequest`/`omr` from module surface and docs.
3. Validate module import and focused tests before users replace retired commands with `Publish-GitChanges`/`yeet`.

Rollback is a normal Git revert of the module change; no external state migration exists.

## Open Questions

- None.
