## 1. Focused safety tests

- [x] 1.1 Add Pester coverage for no-argument invocation, Crisp origin parsing, clean/non-empty fast-forward state, immutable evidence, exact interactive confirmation, and drift rejection.
- [x] 1.2 Add Pester coverage for selected-repository permission validation, standard-library JWT shape, exact one-push command and isolated Git environment, token revocation, sanitized outcomes, and no retry.
- [x] 1.3 Prove focused tests use only fakes and temporary local Git repositories and never access 1Password, GitHub, or an external remote.

## 2. Canonical cmdlet implementation

- [x] 2.1 Move the canonical implementation to no-argument advanced function `Functions/Invoke-SuperPush.ps1` while preserving preflight, raw evidence, exact confirmation, and three-read drift behavior.
- [x] 2.2 Add fixed human-account credential loading, built-in RS256 JWT signing, selected-repository installation-token minting and verification, and sanitized API failures.
- [x] 2.3 Add exactly one fixed HTTPS non-force push with hook, helper, rewrite, prompt, config, redirect, and trace isolation; revoke the token and clear credential state in cleanup.
- [x] 2.4 Export `Invoke-SuperPush` from `RickScripts.psd1` without adding an alias or duplicating implementation for the dependent dotfiles broker.

## 3. Validation and handoff boundary

- [x] 3.1 Run focused Pester tests, the full repository Pester suite, module import/export checks, and `git diff --check`.
- [x] 3.2 Strictly validate the complete `add-super-push-script` OpenSpec and confirm all tasks are complete.
- [x] 3.3 Confirm no dotfiles, credentials, GitHub settings, rulesets, refs, or external systems were accessed or mutated and document dotfiles integration as dependent follow-up only.

## 4. CLI availability

- [x] 4.1 Add focused coverage that `Invoke-SuperPush` is exported as an advanced function with no repository, ref, force, credential, or unattended parameters.
- [x] 4.2 Verify the installed RickScripts symlink exposes `Invoke-SuperPush` after `Import-Module RickScripts -Force` and document the fixed no-profile dotfiles broker call shape without editing dotfiles.

## 5. Simple confirmation

- [x] 5.1 Add focused coverage requiring exactly case-sensitive `Approved` and rejecting the previous long phrase.
- [x] 5.2 Update the cmdlet and OpenSpec contract to use only the exact `Approved` confirmation while preserving full evidence and drift verification.
- [x] 5.3 Run focused and full Pester validation, strict OpenSpec validation, and `git diff --check`.

## 6. Post-push tracking refresh

- [x] 6.1 Add focused coverage for the exact post-push `origin/main` refresh, pushed-SHA verification, and accepted-push audit on refresh failure.
- [x] 6.2 Refresh the local `origin/main` tracking ref after the accepted push and require it to equal the pushed SHA without pulling, retrying, or performing another push.
- [x] 6.3 Run focused and full Pester validation, strict OpenSpec validation, module reload verification, and `git diff --check`.

## 7. Compact preflight evidence

- [x] 7.1 Add focused coverage that preflight shows changed-file names and does not request or print the raw full diff.
- [x] 7.2 Replace raw full-diff output with compact changed-file names and update the OpenSpec evidence contract.
- [x] 7.3 Run focused and full Pester validation, strict OpenSpec validation, module reload verification, and `git diff --check`.

## 8. PTY-safe confirmation input

- [x] 8.1 Add focused regression coverage requiring direct console confirmation input and forbidding `Read-Host`.
- [x] 8.2 Read the exact `Approved` confirmation through `[Console]::ReadLine()` with an explicit prompt.
- [x] 8.3 Run focused and full Pester validation, strict OpenSpec validation, module import verification, and `git diff --check`.

## 9. Documentation-only internal confirmation exemption

- [x] 9.1 Add focused coverage for accepted ordinary text documentation entries and fail-closed mixed, binary, symlink, rename, and `AGENTS.md` entries.
- [x] 9.2 Classify Git-native raw and numstat changed-entry metadata and skip only the cmdlet's internal confirmation for eligible documentation-only updates.
- [x] 9.3 Preserve the native Codex broker approval requirement and validate focused/full Pester, strict OpenSpec, and whitespace checks.
