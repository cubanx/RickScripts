## 1. Module Surface and Test Seams

- [x] 1.1 Inventory current GitLab merge-request exports, aliases, function loading, and documentation references.
- [x] 1.2 Add dependency-free focused PowerShell test coverage with mocked `codex`, `git`, and `gh` command calls.
- [x] 1.3 Add small native-PowerShell executable invocation seams needed by focused tests without dependencies.

## 2. Codex Change Summary

- [x] 2.1 Implement exported `Get-CodexChangeSummary` using ephemeral read-only `codex exec` with required output-schema and last-message flags.
- [x] 2.2 Return structured what-changed, why, user-impact, developer-impact, validation, and human-title fields.
- [x] 2.3 Verify mocked Codex tests cover arguments, structured output, and no mutation behavior.
- [x] 2.4 Pin Codex summary generation to `gpt-5.6-luna` with low reasoning effort and verify the CLI arguments.

## 3. GitHub Publishing Workflow

- [x] 3.1 Implement exported `Publish-GitChanges` and stable `yeet` with optional `-BranchName`, remote-default `-BaseBranch`, and draft-by-default `-Ready` behavior.
- [x] 3.2 Validate accessible `origin` and GitHub PR query/auth before mutation, stopping on failure without standalone `gh` auth/version preflights.
- [x] 3.3 Implement exact slug derivation, retaining existing non-default branches and creating supplied/derived branches from default or detached `HEAD`.
- [x] 3.4 Implement complete-tree `git add -A`, `git diff --cached --check`, staged-diff inspection, empty-diff stopping, commit, and push without `-Path` or `-All` parameters.
- [x] 3.5 Update a matching existing PR branch by committing and pushing without duplicate PR creation or title editing.
- [x] 3.6 Call `Get-CodexChangeSummary` once, build and clean up the temporary Markdown PR body, create draft/ready PRs, set `[<repo-slug>-#<number>] <human title>`, and report branch, commit SHA, URL/title, and final worktree status.
- [x] 3.7 Add comment-based help and PowerShell examples; ensure failures are surfaced without stash/reset/force/destructive cleanup or swallowed exceptions.
- [x] 3.8 Verify mocked tests cover origin/auth failure with no mutation, default/zero-output detached branch derivation, complete-tree staging, mismatched existing-PR stop, existing-PR update, successful draft numbered title, and single summary call.
- [x] 3.9 Add a deterministic single-OpenSpec path for branch, commit, PR title, and PR body metadata that makes no Codex call; retain Codex fallback for mixed or ambiguous changes.

## 4. Retire Legacy Commands and Validate

- [x] 4.1 Remove `New-MergeRequest`/`nmr` and `Open-MergeRequest`/`omr` from function loading, manifest exports, aliases, and documentation while leaving Bash untouched.
- [x] 4.2 Update module documentation for `Get-CodexChangeSummary`, `Publish-GitChanges`, and `yeet`, including complete-worktree staging and safe stop boundaries.
- [x] 4.3 Run focused PowerShell tests, module import/export checks, `git diff --check`, and strict OpenSpec validation.
- [x] 4.4 Validate both fresh-publication and existing-PR update modes.
- [x] 4.5 Add focused coverage for the zero-Codex OpenSpec-only path and the mixed-change Codex fallback, then rerun normal validation.
