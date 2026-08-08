## Context

The current dotfiles prototype combines the security broker with the Super Push implementation. The intended boundary is one exported RickScripts cmdlet and a later dotfiles-only broker that accepts no arguments, starts fixed PowerShell with `-NoProfile`, imports the fixed RickScripts manifest, invokes `Invoke-SuperPush`, and remains the only approved Codex entrypoint. Humans may invoke the cmdlet directly from their RickScripts-enabled PowerShell CLI.

Super Push is an exceptional production mutation. Normal credentials retain the feature-branch and pull-request path; the dedicated selected-repository GitHub App is the only bypass principal. Local validation must not access credentials, GitHub settings, protected refs, or external systems.

## Goals / Non-Goals

**Goals:**

- Own all Super Push behavior and focused behavioral tests in one exported RickScripts advanced function.
- Fix the operation to a clean, non-empty fast-forward from local `HEAD` to `refs/heads/main` in the current `Crisp-Inc/*` checkout.
- Show immutable evidence, require exact interactive confirmation, detect drift three times, isolate the least-privilege token, push once, revoke it, and report sanitized evidence.
- Use only PowerShell/.NET, fixed Git and 1Password executables, and GitHub REST APIs.

**Non-Goals:**

- Direct Codex invocation of the cmdlet outside the fixed broker.
- Force pushes, arbitrary arguments, repositories, refs, credentials, retries, fallbacks, unattended use, or a general elevated shell.
- Dotfiles broker/hook/policy/install changes or any real GitHub App, installation, ruleset, 1Password, credential, or push operation.

## Decisions

### Make the canonical artifact an exported advanced function

Add `Functions/Invoke-SuperPush.ps1`, loaded by the existing module convention and explicitly exported from `RickScripts.psd1`. `Invoke-SuperPush` is an advanced function with no custom parameters; its internal helpers remain in the same file so Pester can fake process and API boundaries without creating a helper module. The future dotfiles broker will contain only fixed PowerShell/module invocation and no behavior to drift.

Humans may invoke the cmdlet from an ordinary RickScripts-enabled PowerShell session. Codex may invoke it only through the fixed no-argument broker, whose no-profile child imports `/Users/cubanx/code/RickScripts/RickScripts.psd1` and calls the cmdlet. Keeping a standalone implementation plus an exported wrapper was rejected because the wrapper adds a second artifact without improving the boundary.

### Derive and freeze one immutable Git update

Use fixed `/usr/bin/git`. Reject Git repository/config environment overrides and effective URL rewrites, resolve the checkout root and canonical `Crisp-Inc/<repository>` origin, require a clean worktree, resolve full `HEAD^{commit}`, and fetch exactly `refs/heads/main` into `refs/remotes/origin/main`. Reject missing main, equal SHAs, or failed ancestry.

Display the repository, fixed ref, full old/new SHAs, fast-forward result, commit list, raw diff stat, raw no-color/no-ext-diff/no-textconv diff, and the fact that local hooks are disabled. Require the case-sensitive phrase `SUPER PUSH <repository> <new-sha> TO refs/heads/main` from an interactive, non-redirected terminal.

Run the same complete state read before credential access and after token minting. Compare repository, root, origin, old SHA, new SHA, target ref, cleanliness, and ancestry to the confirmed snapshot. Any drift requires a fresh invocation. GitHub remains the final compare-and-update guard because the exact non-force refspec fails if remote main races again.

### Isolate the human-only App credential and smallest token

Use fixed Crisp account `2KC5FVMXXJGKDG7LGHWF2OJ2N4`, fixed `/opt/homebrew/bin/op`, and fixed item title `Super Push GitHub App`. Clear service-account/session selectors only inside the invoking PowerShell process, select the Crisp human account, and load exactly one `client-id` and `private-key`. Reject the `Automation` vault; external provisioning must additionally keep the item outside every Local Automation scope because the cmdlet cannot safely introspect service-account grants. A direct human invocation keeps credentials only in that current process; brokered Codex invocation keeps them out of the ordinary Codex process by using the fixed no-profile child.

Sign a short-lived RS256 App JWT using built-in .NET RSA. Verify the repository installation is owned by `Crisp-Inc`, uses selected repositories, and has no permission beyond `contents: write` plus implicit `metadata: read`. Request and verify a token limited to the current repository and `contents: write`. No SDK or JWT package is needed.

### Perform one credential-isolated push and always clean up

The only remote Git mutation is one `/usr/bin/git push --porcelain --no-verify <fixed-https-url> <verified-sha>:refs/heads/main`. Inject authentication as a process-only HTTP header, not a URL, argument, helper, file, or persistent config. Reset extra headers and credential helpers, disable hooks, prompts, redirects, trace output, global/system config, and repository-configured token-sensitive HTTP overrides before the child can receive the token. Never force, retry, loop, or fall back.

Attempt installation-token revocation in `finally`, clear credential/auth variables, and sanitize API and Git failures. Report repository, ref, old/new SHAs, installation ID, UTC timestamp, whether the push was accepted, whether revocation was confirmed, and bounded expiry when revocation fails. GitHub's App actor and pushed SHA remain authoritative audit evidence; no local audit database is added.

## Risks / Trade-offs

- A selected GitHub App is a bypass principal -> keep it selected-repository only, contents-write only, and ruleset-bound per repository.
- Remote main can move after confirmation -> repeat fetch/identity/ancestry verification twice and use a non-force exact-SHA refspec as the final guard.
- A repository-controlled config or hook could leak a token -> reject/override token-sensitive Git config, disable hooks and prompts, and use a fixed HTTPS destination.
- Process termination can prevent explicit revocation -> limit every token to one repository and one permission with GitHub's maximum one-hour expiry.
- Full diffs can be long -> keep them raw and mandatory because this path deliberately trades convenience for visible evidence.

## Migration Plan

1. Merge RickScripts through the normal pull-request path after local review and validation; the installed module symlink then exposes `Invoke-SuperPush` after module reload.
2. In the dependent dotfiles task, replace the prototype with the tiny fixed no-argument broker that imports the fixed RickScripts manifest and invokes the cmdlet, plus hook/policy/install wiring only.
3. Under separate task-scoped approvals, provision or modify the GitHub App, selected-repository installation, per-repository Always-allow ruleset actor, and human-only 1Password item.
4. Authorize each credential access and real push independently when a concrete exceptional push is required.

Rollback is server-first: remove ruleset bypass entries, suspend or uninstall the App, revoke its key, and remove the 1Password item. The RickScripts cmdlet can then remain inert or be reverted normally.

## Open Questions

None. Dotfiles integration and every external activation step are explicit follow-up authorization gates, not implementation tasks in this change.
