# Reap old Orca worktrees

`Remove-OldOrcaWorktree` is an exported advanced-function cmdlet. Requires PowerShell 7+,
Git, and a running local Orca runtime. CLI discovery/schema was checked against Orca
1.4.222 and its bundled `orca-cli` guide. Unknown/missing fields fail closed.

**Default invocation deletes safe candidates. Preview with `-WhatIf` first.**

```powershell
# During review, load this checkout explicitly (it is not installed on main yet).
Import-Module ./RickScripts.psd1 -Force
$result = Remove-OldOrcaWorktree -WhatIf
$result  # Safety-check matrix, using each worktree's final folder name.
$result.Results  # The same checks, plus the per-worktree outcome/status.
$result.Results | Select-Object Worktree, Path, Reason  # Full diagnostic details.

# After reviewing the preview: delete safe candidates, default threshold 14 days.
$result = Remove-OldOrcaWorktree

# Override the inactivity threshold on the command line.
Remove-OldOrcaWorktree -InactiveDays 30 -WhatIf
Remove-OldOrcaWorktree -InactiveDays 7 -WhatIf

# Preview an explicitly requested Orca force override.
Remove-OldOrcaWorktree -Force -WhatIf
# Remove-OldOrcaWorktree -Force  # DESTRUCTIVE: may permanently lose local files.
```

After installation, reload with `Import-Module RickScripts -Force`. `-Confirm` requests
per-candidate confirmation; `-WhatIf` always prevents removal, even with `-Force`.

## Spectre.Console display (optional)

By default, the cmdlet renders only the safety matrix with
[PwshSpectreConsole](https://pwshspectreconsole.com/) (tested with 2.6.3).
Install it explicitly; this cmdlet never installs dependencies:

```powershell
Install-Module PwshSpectreConsole -Scope CurrentUser
$result = Remove-OldOrcaWorktree -WhatIf
# Optional: disable rich output, including for unattended/script-only runs.
# $result = Remove-OldOrcaWorktree -Spectre:$false -WhatIf
$result.Results | ConvertTo-Json -Depth 8
```

The optional dependency is checked before any Orca inspection or removal. If it is
missing or cannot be loaded, a sanitized warning is emitted and plain output is used;
removal safety and structured results are unchanged. `-Spectre:$false` explicitly uses
plain output without loading Spectre. The colored display is host
output; the success pipeline still contains exactly one structured summary. The
summary's default view is suppressed after successful Spectre rendering to avoid
a duplicate table; inspect `$result.Results` for details. `SpectreRendered` records
presentation success only, not deletion success. A rendering failure warns and retains
the summary/default view without repeating removal. Worktree names and explanations
are escaped as literal text. No per-worktree explanations, legend, or footer are printed
below the table. Inspect `$result.Results` for status/reason details and the summary for
counts and coverage. An empty display reports no visible rows, or incomplete coverage
when applicable. Safety warnings and WhatIf messages remain; no safety checks or
`-Force`/`-WhatIf` semantics change.

## Eligibility and Force

For existing directories, the following **all** must be established:

- `lastActivityAt` is a positive valid Unix-millisecond timestamp, strictly older than
  `-InactiveDays` (default 14), and not in the future.
- `worktree ps` reports `status = inactive`, `liveTerminalCount = 0`,
  `hasAttachedPty = false`, and `hasHostSidebarActivity = false`.
- Not main, pinned, bare, currently active, or carrying child worktrees/agent activity.
  A separate complete terminal listing must be empty; associated browser tabs must also
  be absent. Browser checks use `orca tab list --worktree all`, matched by exact worktree
  ID and refreshed during each candidate validation and pre-removal revalidation.
  Per-worktree tab queries are avoided because they hang for absent directories.
  Malformed/unassignable tab records and runtime drift block removal; tabs associated
  with other worktrees do not.
- Stable Orca instance identity, path, host, branch, HEAD, base, and timestamp match the
  listing and `show`. The checkout is registered in Git, not main/locked/prunable/detached.
- Stashes and submodules still block removal. Git registration, current HEAD/branch,
  and path are verified locally; no remote access or base-ref validation is required.
- Local files are **not checked by this cmdlet**: tracked changes, untracked files, and
  ignored files do not gate candidate selection. File protection is delegated to Orca's
  guarded removal command and archive hooks; an Orca refusal is reported as a failure,
  without retrying or automatically escalating to force. `Ready` does not guarantee
  that Orca will permit removal or that local files are backed up.
- `-Force` passes Orca `--force` only when explicitly requested. It does not override
  Git registration, activity, identity, scope, or archive hooks for existing directories.

**Commit safety is deliberately not checked.** Unpushed/unmerged commits, abandoned
reflog commits, and stale/missing remote base refs do not block removal. This supports
workflows such as Super Push without requiring equivalent commit history. Removal may
attempt branch deletion and make local-only commits difficult to recover; review anything
you want to keep before deleting. `Ready` means the remaining criteria passed, not that
commits have been backed up or merged.

`lastActivityAt` is **not a sleep timestamp**; its precise update semantics are undocumented.
These indicators do not prove that explicit Sleep was used. No `isArchived` inference is
made. Checks cover Orca-visible resources, not arbitrary external processes using a folder.

## Automatic missing-directory cleanup

Confirmed missing directories are candidates for deregistration on every run, regardless
of age or missing/invalid activity timestamps. No Git inspection is attempted for an absent
checkout. Identity and matching activity metadata, local scope, inactivity, protection flags,
no children, complete terminal listings, and empty browser-tab listings are still required.
Main, pinned, bare, active, or unverifiable entries are never automatically cleaned up.

Absence is established with filesystem attributes and an existing directory ancestor, not
`Test-Path`/`Exists` (which can hide errors). Existing files and dangling symlinks are not
classified as missing. Access/I/O errors and absent descendants through symlinks or files
fail closed as `PathUnverified`; they never authorize a hook waiver.

`Results[].MissingPath` identifies this route. Its `Age` cell can show a recent age or
be unverified while `Ready` is green: age is not required for missing-directory cleanup. `Explanation` describes the
conditional archive-hook waiver, including under `-WhatIf`.

The route uses Orca removal with `--run-hooks --allow-failed-archive-hook`, without adding
`--force` unless explicitly requested. Hooks are still attempted; their failure may be
waived **only for confirmed missing paths**. `-WhatIf` and confirmation still apply.
Identity/resources and absence are revalidated, with a final absence check immediately
before removal. If the path reappears or its existence changes, removal is not requested
(`PathChanged`). No automatic retry or escalation occurs. A complete post-removal listing
must confirm deregistration. As with ordinary removal, checks cannot eliminate concurrent
filesystem changes between observation and the Orca command; avoid overlapping activity.

## Removal, scope, and diagnostics

Removal uses `orca worktree rm --worktree identity:<key> --run-hooks --json`, adding
`--force` only with explicit `-Force`. Existing directories never receive an archive-hook
waiver; confirmed missing directories use the conditional waiver described above. The command
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
`CoverageComplete`, `CoverageReason`, `HostIds`, `OmittedHostIds`, and per-item
`Results` (including each row's `MissingPath` flag). Both displays use the final folder name for the `Worktree` label, matching
`Results`. Protected main/root checkouts are hidden from the summary tables but retained
in structured `Results` and the skipped count.
A folder named `worktree` stays `worktree`; it does not imply a default branch.
This changes presentation only; full paths, identities, and branch validation remain
unchanged.
The default display is a worktree table with reason/check columns:

| Column | Green means |
| --- | --- |
| Age | ✅ when strictly old enough; otherwise completed days since activity (e.g. `3d`); ❌ for an invalid/unverified timestamp |
| Idle | All four inactivity indicators pass, with no known agent/current activity |
| Unpinned | Pinned state is verified false |
| NoKids | Child-worktree list is verified empty |
| Ready | Full eligibility validation passed, including identity, scope, and resource checks |

Age in days is floored, not rounded; eligibility still uses the exact timestamp with a
strict cutoff. `Checks.AgeDays` records that numeric age for valid, non-future timestamps.
Spectre shows recent ages in yellow. This is presentation only; no eligibility changes.

**✅ means passed; ❌ means blocked OR not yet verified. All green means eligible under
these criteria, not proof that commits are preserved.** Missing-directory cleanup can be
ready without a green Age cell, as described above.
`Idle` alone does not prove the separate terminal/browser checks; `Ready` requires those
checks too. Cheap metadata checks are independent: a pinned row can show both Unpinned
and NoKids red. There is no Files check or local-file force-hint collection.
Eligibility is still revalidated immediately before removal; a preview is not a future
safety guarantee. Readiness is cleared on revalidation/removal failure.

Structured `Results[].Checks` retains true/false/null values; `Explanation` and diagnostic
`Reason` retain details. Protection explanations name the actual blocker (pinned, bare,
child worktrees, or unverified metadata), not a combined list of possibilities. Protected
main-worktree rows skipped as `ProtectedWorktree` are omitted from the summary tables,
but remain in the skipped count and structured `Results` with `IsMainWorktree`.
They are never eligible for deletion. Main rows with failed/unverified checks remain
visible, as do pinned and other blocked worktrees. Visible rows stay alphabetized. `Results` also has a matrix view. Full `Path`, `Id`, `Status`,
and all structured properties remain intact for scripts/JSON.
Names may repeat across repositories; use `Path`/`Id` to distinguish those rows. This is
presentation only: selection, validation, ShouldProcess confirmation targets, and removal
still use the full path/stable identity. Save the result first (`$result = ...`) to inspect
its properties; do not pipe to `Format-Table` before exporting JSON or scripting against it.

Candidate rows remain candidates under WhatIf/declined confirmation. Reasons
are fixed codes or sanitized exception types/exit codes; raw Git, terminal, hook, JSON and
stderr payloads are never included. Inspect the checkout manually when Git verification
fails instead of assuming `-Force` can bypass it.

## Unattended scheduling (not installed by this change)

First run the preview under the intended scheduler account/environment. It needs a running
Orca runtime, Git/Orca on PATH (or an absolute `-OrcaCommand`), and already-configured
local access to the checkouts. Per-command timeout defaults to 60 seconds
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
