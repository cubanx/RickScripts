# Local validation — 2026-10-08

- Full suite: `pwsh -NoProfile -File ./Tests/Run-Tests.ps1` — 289 passed,
  0 failed, 0 skipped (16 test files).
- New candidate coverage: 15 local-Git tests, including advanced main,
  selective scope/exclusion, dirty/staged/untracked source preservation,
  conflicts and failed-candidate cleanup, bounded pre-approval docs races,
  invalid/foreign/merge/duplicate/reversed/already-published scope,
  non-doc validation failures and cwd/mutation checks, intermediate executable
  changes hidden in a docs net diff, receipt drift, detached immutability,
  human docs/non-doc orchestration and an approval-time remote race.
- Diagnostics regression: candidate patch display is redacted and patch content
  is omitted from retained diagnostics; original token/revocation/push-failure
  tests remain passing.
- `Import-Module ./RickScripts.psd1 -Force` exposes both `Invoke-SuperPush`
  and `New-SuperPushCandidate` as advanced functions; helpers remain private.
- PowerShell parser reports no errors for both implementation files.
- `git diff --check` passes.
- `openspec validate prepare-super-push-task-commits --strict` passes without
  archival warnings. Existing `add-super-push-script` is unarchived and does not
  cover preparation; this change adds a separate capability rather than a
  MODIFIED delta against its nonexistent baseline spec.
- No PowerShell LSP is configured. Installed CodeGraph 1.6.0's supported-language
  documentation does not include PowerShell; source verification and Pester
  cover the affected `.ps1` files without indexing unsupported code.

No commits, installation, deployment, external provider operations, credential
changes or real Super Push occurred. Local bare remotes and fake provider
boundaries only. The pre-existing suite emits a mocked Claude-start warning;
there are no test failures.

## Diagnostics integration — 2026-10-08

On explicit user authorization, this worktree fast-forwarded from
`12793ff345f55c205b8f29432a4165dc2c18e30d` to the existing published commit
`b4f4c2ede5fdc66ecc9ea76f478ca71eaad3d079`; no new commit was created.
All five modified tracked preparation files were restored using clean three-way
file merges. All pre-existing untracked file contents were verified unchanged
before this evidence update. The shared diagnostics tests retain both preparation
mocks/redaction coverage and the fail-closed offline op stub, credential codes,
Automation/biometric environment restoration and CLI-path restoration.

Combined validation:

- Full offline Pester suite: **301 passed, 0 failed, 0 skipped**, 16 files;
  diagnostics coverage is now 30 cases and candidate coverage remains 15 cases.
- Parser checks pass for both implementation files and the combined diagnostics
  tests; importing this worktree manifest exposes both advanced cmdlets.
- `git diff --check` and strict validation of this OpenSpec change pass.
- No new commit, push, installation/relink, credential access, provider call,
  real Super Push retry or dotfiles integration occurred.

Recoverable pre-movement backup:
`/var/tmp/rickscripts-integration-backup.kFa5GL` contains original HEAD/status,
tracked unstaged/staged binary patches, a tar archive of all modified/untracked
files, extracted originals, three-way base/target/merged files and SHA-256
checksums. Checksum verification passed before movement. The original index was
empty and remains empty. Retain this backup through human review; restoration is
not authorized automatically and must not discard subsequent work.

The original credential failure's precise cause remains unresolved; the integrated
codes improve future diagnosis rather than claiming a successful live credential
read or publication. Local tests do not prove external provider behavior.

## Remaining integration scope

Dotfiles Pi tool/policy/task recipes must explicitly select task commits, call
`New-SuperPushCandidate` (with an appropriate validator for non-docs) before
native approval, review resulting SHA/patch and bind the receipt fingerprint,
then call existing `approved_super_push` with Root/NewSha. The fixed broker stays
no-argument. No dotfiles changes were made; the installed RickScripts module was
not updated. Review these local changes before any commit or publication.
