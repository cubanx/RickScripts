## 1. Isolated docs publication slice

- [x] 1.1 Add local-bare-remote Pester coverage for selected docs replay onto advanced main, excluding unrelated history and preserving source HEAD/branch/index/dirty/untracked work.
- [x] 1.2 Implement exported advanced `New-SuperPushCandidate` and integrate the human preparation flow in `Invoke-SuperPush` without whole-branch merge or source rewrite.
- [x] 1.3 Prove docs skip typed confirmation and preparation/validation do not access credentials or push; use fake provider boundaries for orchestration tests.

## 2. Fail-closed validation and approval boundary

- [x] 2.1 Reject missing/invalid/foreign/duplicate/reversed/merge/already-published scope and conflicts with cleanup of failed isolated candidates.
- [x] 2.2 Require passing explicit non-doc validation in candidate cwd and reject failed or mutating validators; classify intermediate commits as well as net diff.
- [x] 2.3 Bind candidate receipts and fingerprints; reject remote/candidate/receipt drift after preparation/approval and prohibit rewriting detached broker candidates.
- [x] 2.4 Bound pre-approval docs main-race recovery to three attempts with unchanged selected scope, no push retry and retained successful recovery candidate.

## 3. Evidence and coordinated handoff

- [x] 3.1 Run final full Pester suite, module export/parser checks, whitespace checks and strict OpenSpec validation; record actual results in validation.md.
- [x] 3.2 Document the human flow, caller-owned candidate cleanup and Root/NewSha pre-approval Pi preparation contract.
- [x] 3.3 Report that dotfiles tool/policy/recipe changes are a separate coordinated scope; make no deployment, credentials, commit, publication or real Super Push claims.
