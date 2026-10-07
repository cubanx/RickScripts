# Reap old Orca worktrees

`Remove-OldOrcaWorktree` is an exported advanced-function cmdlet. Requires PowerShell 7+,
Git, and a running local Orca runtime. CLI discovery/schema was checked against Orca
1.4.222 and its bundled `orca-cli` guide. Unknown/missing fields fail closed.

**Default invocation deletes safe candidates. Preview with `-WhatIf` first.**

```powershell
# During review, load this checkout explicitly (it is not installed on main yet).
Import-Module ./RickScripts.psd1 -Force
$result = Remove-OldOrcaWorktree -WhatIf
$result.Results | Format-Table Status, Reason, Path

# After reviewing the preview: delete safe candidates, default threshold 30 days.
$result = Remove-OldOrcaWorktree

# Configure the inactivity threshold.
Remove-OldOrcaWorktree -InactiveDays 60 -WhatIf

# Inspect worktrees blocked only by local files, then preview the override.
$result.NeedsForce | Format-Table Reason, Path
Remove-OldOrcaWorktree -Force -WhatIf
# Remove-OldOrcaWorktree -Force  # DESTRUCTIVE: may permanently lose local files.
```

After installation, reload with `Import-Module RickScripts -Force`. `-Confirm` requests
per-candidate confirmation; `-WhatIf` always prevents removal, even with `-Force`.

## Eligibility and Force

The following **all** must be established:

- `lastActivityAt` is a positive valid Unix-millisecond timestamp, strictly older than
  `-InactiveDays` (default 30), and not in the future.
- `worktree ps` reports `status = inactive`, `liveTerminalCount = 0`,
  `hasAttachedPty = false`, and `hasHostSidebarActivity = false`.
- Not main, pinned, bare, currently active, or carrying child worktrees/agent activity.
  A separate complete terminal listing must be empty; browser tabs must also be absent.
- Stable Orca instance identity, path, host, branch, HEAD, base, and timestamp match the
  listing and `show`. The checkout is registered in Git, not main/locked/prunable/detached.
- HEAD and every retained checkout HEAD reflog commit are ancestors of the configured
  **remote** base. The base's cached SHA must equal a fresh `git ls-remote` result.
  Missing/local-only base refs, remote failures, stale refs, stashes, and submodules skip
  the checkout. This is deliberately stricter than “another local branch has the commit.”
- By default, tracked changes, untracked files, and ignored files block removal. Otherwise
  eligible local-file blockers appear under `NeedsForce`, with a warning to preview
  `-Force -WhatIf`. `-Force` permits **only this file-loss override** and passes Orca
  `--force`; it does not override commit safety, activity, identity, scope, or hooks.

`lastActivityAt` is **not a sleep timestamp**; its precise update semantics are undocumented.
These indicators do not prove that explicit Sleep was used. No `isArchived` inference is
made. Checks cover Orca-visible resources, not arbitrary external processes using a folder.

## Removal, scope, and diagnostics

Removal uses `orca worktree rm --worktree identity:<key> --run-hooks --json`, adding
`--force` only with explicit `-Force`. Archive-hook failure is never bypassed. The command
can delete checkout files and attempt local branch deletion; retaining a branch does not
save uncommitted files. No direct filesystem deletion is used.

Eligibility is fully revalidated after ShouldProcess/confirmation and before every removal.
A complete post-removal listing must confirm absence before reporting `Deleted`. Any
uncertain failure is reported without an automatic retry. Inspect Orca before manually
retrying: a timeout/failure may occur after removal has begun. Revalidation reduces but
cannot eliminate the check/remove race; avoid concurrent activity and overlapping runs.

Only the selected runtime's **local execution host** is supported. Inherited
`ORCA_ENVIRONMENT`/`ORCA_PAIRING_CODE` routing is deliberately removed from subprocesses;
this cmdlet does not sweep paired servers or all computers. `-OrcaCommand` selects a CLI
executable, not a shell command string. It follows the Orca skill's executable selection
when omitted. No CLI fallback or auto-launch is attempted.

`-Limit` defaults to 10000. Truncation, count mismatch, unknown scope, omitted hosts, runtime
changes, or ambiguous identities block removal rather than pretending coverage is complete.
Raise `-Limit` only after reviewing an incomplete result. There is no guessed pagination.

The returned summary contains `CandidateCount` (initially eligible, including subsequently
skipped/deleted/failed candidates), `SkippedCount`, `DeletedCount`, `FailedCount`,
`CoverageComplete`, `CoverageReason`, `HostIds`, `OmittedHostIds`, `NeedsForce`, and per-item
`Results`. Candidate rows remain candidates under WhatIf/declined confirmation. Reasons
are fixed codes or sanitized exception types/exit codes; raw Git, terminal, hook, JSON and
stderr payloads are never included. `CommandExit:1` during ancestry checking can mean
unmerged commits; inspect the checkout manually instead of forcing it.

## Unattended scheduling (not installed by this change)

First run the preview under the intended scheduler account/environment. It needs a running
Orca runtime, Git/Orca on PATH (or an absolute `-OrcaCommand`), and already-configured
noninteractive read access to base remotes. Per-command timeout defaults to 60 seconds
(`-TimeoutSeconds`); no credential prompts, runtime startup, or retry loops are used.
Configure the scheduler to **prevent overlapping executions**. Prefer safe mode; never
schedule `-Force` merely to silence a warning.

Example PowerShell job body, initially report-only:

```powershell
$ErrorActionPreference = 'Stop'
Import-Module '/absolute/path/to/RickScripts/RickScripts.psd1' -Force
$r = Remove-OldOrcaWorktree -WhatIf -Confirm:$false
$r | ConvertTo-Json -Depth 8 | Set-Content '/absolute/path/to/reap-summary.json'
if (-not $r.CoverageComplete -or $r.FailedCount -gt 0) { exit 1 }
# Remove -WhatIf only after reviewing scheduler-scope evidence and approving deletion.
```

Use a private log location: the summary contains checkout paths/identities. No scheduled
job is created or enabled here. Implementation validation never removes real Orca worktrees.
