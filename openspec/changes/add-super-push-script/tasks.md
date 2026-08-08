## 1. Focused safety tests

- [x] 1.1 Add Pester coverage for no-argument invocation, Crisp origin parsing, clean/non-empty fast-forward state, immutable evidence, exact interactive confirmation, and drift rejection.
- [x] 1.2 Add Pester coverage for selected-repository permission validation, standard-library JWT shape, exact one-push command and isolated Git environment, token revocation, sanitized outcomes, and no retry.
- [x] 1.3 Prove focused tests use only fakes and temporary local Git repositories and never access 1Password, GitHub, or an external remote.

## 2. Canonical standalone implementation

- [x] 2.1 Add the unexported no-argument `Scripts/Invoke-SuperPush.ps1` preflight, raw evidence, exact confirmation, and three-read drift boundary.
- [x] 2.2 Add fixed human-account credential loading, built-in RS256 JWT signing, selected-repository installation-token minting and verification, and sanitized API failures.
- [x] 2.3 Add exactly one fixed HTTPS non-force push with hook, helper, rewrite, prompt, config, redirect, and trace isolation; revoke the token and clear credential state in cleanup.
- [x] 2.4 Keep `RickScripts.psd1` and `RickScripts.psm1` unchanged and verify the script contains the sole implementation expected by the dependent dotfiles broker.

## 3. Validation and handoff boundary

- [x] 3.1 Run focused Pester tests, the full repository Pester suite, module import/export checks, and `git diff --check`.
- [x] 3.2 Strictly validate the complete `add-super-push-script` OpenSpec and confirm all tasks are complete.
- [x] 3.3 Confirm no dotfiles, credentials, GitHub settings, rulesets, refs, or external systems were accessed or mutated and document dotfiles integration as dependent follow-up only.
