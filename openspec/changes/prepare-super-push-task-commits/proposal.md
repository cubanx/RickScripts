## Why

A task branch can fall behind main without its intended commits being unsafe to
publish. Requiring users to sync/rebase manually is especially disruptive for
routine docs publication; merging a whole branch could publish unrelated work.

## What Changes

- Prepare explicitly selected ordinary task commits on fetched main in an
  isolated detached worktree, preserving source work and unrelated history.
- Let `Invoke-SuperPush` own human preparation, validation, evidence and existing
  publication; add exported `New-SuperPushCandidate` for preparation before Pi's
  exact-SHA native approval.
- Docs-only candidates need Git checks, not a test command or typed confirmation.
  Non-doc candidates require a supplied passing validator and `Approved`.
- Classify intermediate commits as well as the final diff; freeze candidate and
  validation receipt across approval. Never rewrite approved detached candidates.
- Preserve fixed main, one non-force push, credentials/revocation/diagnostics,
  no uncertain-push retry and separate native agent approval.

## Capabilities

### New Capabilities

- `super-push-task-preparation`: scope selection, isolated replay, validation,
  docs-only pre-approval recovery and immutable handoff.

### Modified Capabilities

None. `super-push-cmdlet` exists only in the unarchived `add-super-push-script`
change, not in the baseline specs. The new capability explicitly supersedes its
older no-custom-parameter/source-HEAD assumptions for preparation/handoff only;
publication and credential boundaries remain in force as implemented by current
RickScripts policy. No MODIFIED delta targets a nonexistent baseline.

## Impact

RickScripts functions, manifest, docs and local-Git Pester tests. No dependencies,
credentials, real Super Push, deployment or publication. Dotfiles Pi entrypoint,
policy and recipe adaptation remain a separately coordinated task.
