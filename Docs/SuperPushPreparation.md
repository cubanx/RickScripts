# Task-scoped Super Push preparation

Super Push does not merge the source branch, pull into your checkout, or assume
branch-only history belongs to the task. Supply only the intended full commit
SHAs, oldest first. Root/merge commits, duplicates, reversed ancestry, commits
outside source HEAD, and commits already on remote main are rejected.

## Human flow

```powershell
Import-Module RickScripts -Force
Invoke-SuperPush -TaskCommit @('<full-task-commit-sha>')
```

On an attached branch, the cmdlet fetches current `origin/main`, allocates an
isolated detached worktree, and cherry-picks exactly those commits. The source
branch, HEAD, index, tracked edits and untracked files are not modified. Calling
without `-TaskCommit` asks for explicit full SHAs with no default selection;
redirected/unattended scope selection is forbidden.

The resulting candidate is classified using both the net diff and every replayed
commit. Existing fail-closed docs rules still apply: `AGENTS.md`, binaries,
symlinks, submodules, mixed paths and uncertain metadata are not docs-only.
Intermediate non-doc changes cannot hide behind a final docs-only net diff.

- **Docs-only:** Git safety/cleanliness/ancestry checks; no validator required and
  no typed `Approved`. If main advances during preparation, rebuild the same
  selected scope, with at most three preparation attempts. Conflicts still stop.
- **Non-docs:** require an explicit validation executable and argument array,
  successful exit, unchanged candidate HEAD and clean worktree. Then show exact
  SHA, commit list, stat, paths and patch, and require `Approved`.

```powershell
Invoke-SuperPush -TaskCommit @('<full-task-commit-sha>') -ValidationCommand @(
    'pwsh', '-NoProfile', '-File', './Tests/Run-Tests.ps1'
)
```

Validation runs in the candidate directory without shell interpolation, times
out after ten minutes, and omits stdout/stderr to avoid emitting credentials.
The caller must choose an appropriate command and separately authorize any
external effects that command would cause. Do not use production operations as
an incidental validator. No test command is guessed or auto-discovered.

After preparation returns a candidate, any remote-main, candidate, origin,
cleanliness or validation-receipt drift stops publication. Rebuild/revalidate and
obtain fresh approval; never silently rewrite an approved candidate. There is
still one non-force push to fixed `refs/heads/main`, using the existing token,
revocation and sanitized diagnostics boundaries. An uncertain push is never
retried automatically.

## Pi preparation contract — separate from publication

```powershell
$candidate = New-SuperPushCandidate -SourcePath '/absolute/source/worktree' `
    -TaskCommit @('<full-task-commit-sha>')
$candidate | Select-Object Root, OldSha, NewSha, TaskCommits, DocumentationOnly, ValidationPassed
```

For non-docs, also supply `-ValidationCommand` as above. This exported advanced
cmdlet only prepares and validates: no App credential access or push. It returns
an absolute clean detached `Root`, fetched `OldSha`, exact candidate `NewSha`,
source provenance, selected commits and classification/validation outcome. A
non-secret receipt is written inside the detached worktree's Git administrative
directory, bound to root, origin, repository and old/new SHAs. It is local
validation evidence, not a credential, signature or authorization grant.

The separate dotfiles Pi integration must:

1. Obtain explicit task commit scope and a validator for non-docs; call this
   preparation contract **before** native approval, not from inside the broker.
2. Review the exact resulting SHAs, selected/replayed commits and patch. Bind
   validation-receipt identity as well as the candidate SHA across native approval.
3. Pass `Root` and `NewSha` to the existing `approved_super_push` tool. Keep its
   pre/post-approval fetch and exact-snapshot checks and the fixed no-argument
   `llm-super-push` invocation. Native approval remains required for docs too.

A detached invocation never prepares, cherry-picks, rebases or merges. A non-docs
candidate without a matching passing receipt must be validated explicitly for
human use, or prepared correctly before Pi approval; the no-argument broker does
not run a missing validator or bypass it. Existing docs-only detached snapshots
remain usable without a preparation receipt, subject to all Git checks.

**Integration gap:** this RickScripts change does not update the dotfiles tool,
policy or task recipes to call preparation or bind its receipt. Those are a
separate coordinated scope; do not claim the Pi entrypoint is end-to-end updated.

## Retained candidates and cleanup

Successful preparation retains its worktree, including after a publication
failure, for exact review/recovery. The human flow prints the path and restores
the original PowerShell location. Failed preparation removes only its newly
allocated isolated worktree. The caller owns successful-candidate cleanup:

```powershell
git -C '/absolute/source/worktree' worktree remove -- $candidate.Root
```

Inspect first; do not force-delete work added afterward. Remove the now-empty
parent temporary directory afterward if desired. Never retry publication solely
because the command failed: reconcile the remote and the audit's attempted/push
outcomes first.
