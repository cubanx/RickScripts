## ADDED Requirements

### Requirement: Canonical exported cmdlet ownership
RickScripts SHALL own Super Push behavior and focused behavioral tests in exported advanced function `Invoke-SuperPush`. The cmdlet SHALL expose no custom parameters. The dependent dotfiles integration SHALL contain only the fixed no-argument security broker and Codex hook, policy, and install wiring; it SHALL use fixed PowerShell with `-NoProfile`, import the fixed RickScripts manifest, invoke the cmdlet, and SHALL NOT copy implementation behavior.

#### Scenario: RickScripts module is installed
- **WHEN** this change is applied
- **THEN** `Import-Module RickScripts -Force` exposes `Invoke-SuperPush` and focused tests exercise that one implementation

#### Scenario: Dotfiles integration follows
- **WHEN** the calling dotfiles task adapts its broker after this implementation is reviewable
- **THEN** the broker imports the fixed RickScripts manifest and invokes the cmdlet without duplicating its behavior

### Requirement: Exceptional path preserves ordinary protection
The default GitHub workflow SHALL remain feature branch plus pull request. Ordinary human, administrator, and Codex credentials SHALL receive no bypass capability; only the dedicated GitHub App MAY be an Always-allow ruleset bypass actor for explicitly selected Crisp repositories. Humans MAY invoke `Invoke-SuperPush` directly; Codex SHALL enter through `llm-super-push` and SHALL NOT invoke the cmdlet directly.

#### Scenario: Ordinary direct push
- **WHEN** a person or ordinary Codex credential pushes directly to protected `main`
- **THEN** GitHub continues to enforce repository rules without bypass

#### Scenario: Repository is onboarded
- **WHEN** another Crisp repository is explicitly authorized
- **THEN** the App installation selects that repository and its `main` ruleset names the App as the bypass actor

### Requirement: Fixed invocation, repository, and ref boundary
The cmdlet SHALL expose no repository, ref, force, credential, confirmation-bypass, or unattended parameters and SHALL derive the repository from the current checkout's `origin`. It SHALL accept only supported GitHub origin forms owned by `Crisp-Inc`, fix the candidate to local `HEAD` and the target to `refs/heads/main`, and reject non-Crisp origins, arbitrary input, missing remote main, dirty worktrees, ambient Git repository/config overrides, and Git URL rewrites.

#### Scenario: Onboarded Crisp repository is selected
- **WHEN** the current checkout is an explicitly onboarded `Crisp-Inc/*` repository with a supported origin
- **THEN** the cmdlet derives its canonical repository and fixed HTTPS push URL without caller input

#### Scenario: Invocation boundary is invalid
- **WHEN** an argument, non-Crisp origin, dirty worktree, missing remote main, ambient override, or URL rewrite is present
- **THEN** parameter binding or the cmdlet fails before credential access or remote mutation

### Requirement: Exact fast-forward evidence and confirmation
The cmdlet SHALL resolve local `HEAD` and fetched remote main to full commit SHAs, reject a no-op or non-fast-forward candidate, and display the exact repository, fixed ref, old/new full SHAs, ancestry, commits, raw diff stat, changed-file names, and disabled local-hook behavior. It SHALL require the case-sensitive exact interactive confirmation `Approved`, with no unattended or bypass mode.

#### Scenario: Candidate is reviewable
- **WHEN** local `HEAD` is a non-empty fast-forward of remote main
- **THEN** the complete immutable update evidence and disabled-hook disclosure appear before confirmation

#### Scenario: Confirmation is unavailable or wrong
- **WHEN** input is redirected, non-interactive, absent, or differs from the exact phrase
- **THEN** the cmdlet fails before credential access or remote mutation

#### Scenario: Candidate rewrites history
- **WHEN** fetched remote main is not an ancestor of local `HEAD`
- **THEN** the cmdlet fails without minting a token or pushing

### Requirement: Repeated immediate state verification
The cmdlet SHALL perform complete fetch, identity, cleanliness, and fast-forward reads before confirmation, again immediately after confirmation and before credential access, and again after token minting immediately before the push. Each later read SHALL exactly match the confirmed repository, root, origin, target, old SHA, and new SHA; any drift SHALL abort and require a fresh invocation.

#### Scenario: State drifts after confirmation
- **WHEN** local HEAD, remote main, origin identity, repository root, cleanliness, target, or ancestry changes
- **THEN** the cmdlet aborts before pushing and does not retry

#### Scenario: State remains exact
- **WHEN** both repeated reads match the confirmed state
- **THEN** the cmdlet may perform the one exact non-force push

### Requirement: Human-gated credential isolation
The App client ID and private key SHALL be read only within the invoking PowerShell process through fixed Crisp human account `2KC5FVMXXJGKDG7LGHWF2OJ2N4` and a human-only item outside the `Automation` vault and every Local Automation service-account scope. Credentials SHALL NOT reach a parent process, disk, output, logs, command arguments, or tests. Direct human use MAY run in the current RickScripts-enabled process; Codex use SHALL run in the fixed broker-started no-profile child after fresh native task-scoped approval naming the repository, SHA, and mutating push.

#### Scenario: Human terminal use
- **WHEN** a human deliberately invokes `Invoke-SuperPush`
- **THEN** the same evidence, confirmation, human 1Password authorization, token, and push boundary applies

#### Scenario: Codex use
- **WHEN** Codex is asked to perform Super Push
- **THEN** the exact no-argument broker uses a TTY, imports the fixed RickScripts manifest in a no-profile child, and invokes the cmdlet after fresh native approval while the ordinary Codex process cannot read the App item

#### Scenario: Credential item is unsafe
- **WHEN** the item is absent, ambiguous, malformed, in the `Automation` vault, or inside any Local Automation scope
- **THEN** activation fails before token creation without exposing item contents

### Requirement: Least-privilege App token
The cmdlet SHALL mint an RS256 GitHub App JWT with built-in .NET cryptography, verify that the repository installation belongs to `Crisp-Inc`, uses selected repositories, and grants only contents write plus implicit metadata read, then request and verify an installation token naming exactly the current repository and `contents: write`. It SHALL reject all-repository selection, mismatched repositories, missing permissions, extra permissions, and reusable ambient tokens.

#### Scenario: Installation is narrow
- **WHEN** GitHub reports the selected current repository and only the required permissions
- **THEN** the cmdlet accepts a one-repository contents-write installation token

#### Scenario: Installation or token is broad
- **WHEN** installation or token scope includes all repositories, another repository, a missing permission, or an extra permission
- **THEN** the cmdlet fails before Git mutation

### Requirement: Exactly one isolated non-force push
The only remote Git mutation SHALL be one push of the verified full SHA to `refs/heads/main` at the fixed HTTPS repository URL. The cmdlet SHALL NOT force, rewrite, retry, loop, change repository or ref, or use a fallback credential. It SHALL disable local hooks and prevent credential helpers, URL rewrites, trace output, ambient configuration, transport redirects, or prompts from receiving or leaking the installation token.

#### Scenario: Push succeeds
- **WHEN** GitHub accepts the exact fast-forward update through the App actor
- **THEN** the cmdlet reports the immutable update once and performs no other push
- **AND** it fetches the fixed remote `main` into local `origin/main` and requires that tracking ref to equal the pushed SHA
- **AND** it does not pull, merge, retry, or perform another remote mutation

#### Scenario: Push is rejected
- **WHEN** GitHub rejects the update or a race makes it non-fast-forward
- **THEN** the cmdlet reports sanitized failure and does not retry or weaken protection

#### Scenario: Accepted push cannot be reflected locally
- **WHEN** GitHub accepts the push but the post-push tracking refresh fails or resolves another SHA
- **THEN** the cmdlet reports the push as accepted, fails local confirmation, and still revokes the token

### Requirement: Credential disposal and sanitized audit evidence
The cmdlet SHALL attempt to revoke every minted installation token in cleanup, clear credential and Git authentication state, and never persist secret material. It SHALL report repository, fixed ref, old/new SHAs, installation identity, timestamp, push outcome, and revocation outcome without secrets. Revocation failure SHALL fail the command and report bounded server expiry; GitHub's App actor and pushed SHA SHALL remain authoritative audit evidence.

#### Scenario: Cleanup completes
- **WHEN** the push succeeds or fails after token minting
- **THEN** cleanup revokes the token, clears process credential state, and emits sanitized evidence

#### Scenario: Revocation cannot be confirmed
- **WHEN** token revocation fails
- **THEN** the command fails, reports the token expiry, and performs no further mutation

### Requirement: External activation remains separately authorized
GitHub App provisioning or modification, selected-repository installation, ruleset changes, 1Password item creation or modification or access, and every real push SHALL remain external mutations requiring later explicit task-scoped authorization. This change's validation SHALL use only fakes and local repositories.

#### Scenario: Local implementation is validated
- **WHEN** this OpenSpec change is implemented and tested
- **THEN** no credential, GitHub setting, protected ref, ruleset, 1Password item, or external system is accessed or changed

#### Scenario: Activation is requested later
- **WHEN** a human later authorizes one external setup, credential, or push operation
- **THEN** only that displayed operation is performed within its task scope
