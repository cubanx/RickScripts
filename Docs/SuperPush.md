# Super Push credentials

`Invoke-SuperPush` reads the existing `Super Push GitHub App` item
(`elv65z73smxy4uq5jii57djpge`) from Crisp's Automation vault (`bcxp54juyo54olkp6ysoe4lzky`) using the read-only **Local
Automation** service account. It requires `OP_SERVICE_ACCOUNT_TOKEN` in the
calling process. It never falls back to desktop 1Password authentication.

## One-time setup

The owner moved the canonical item into Automation; Local Automation's
metadata listing confirms its ID and vault. No live key was read during that
verification. Do not duplicate the App key or create a second canonical item.
Keep its existing `client-id` and `private-key` fields. Preserve its governance
metadata; update its recorded vault/destination through the authorized
credential-governance workflow.

Local Automation must have read access to Automation. The cmdlet retrieves the
fixed immutable item ID inside the fixed vault, without title lookup or fallback.
Missing credentials, inaccessible items, unexpected IDs/vaults, or invalid fields
stop execution without a desktop prompt or an automatic retry.

## Approved trust change

The owner explicitly approved Automation-vault storage and service-account
retrieval for this change. This replaces the cmdlet's former
human-vault-only requirement. Any process holding that service-account token
can read the long-lived App key and mint GitHub installation tokens within the
App's permissions; cmdlet confirmations do not constrain independent use of
the key. No plaintext local projection is introduced.

## Documentation and authorized non-doc workflow

```powershell
Import-Module RickScripts -Force
Invoke-SuperPush
```

The no-argument cmdlet skips typed confirmation only for text documentation
under `docs/`, or the existing root
README/CHANGELOG/CONTRIBUTING/SECURITY/LICENSE names. Every outgoing commit is
checked, so code added and later reverted is not treated as docs-only.
`AGENTS.md`, binary files, symlinks, submodules, code and merge commits take the
non-doc path: display the exact candidate evidence, then require typing
`Approved` in an interactive terminal before App credential access. Denied or
cancelled confirmation stops without credential access or a push.
Both paths still authenticate to GitHub using the App; docs-only means no
internal human authorization prompt, not anonymous publication.

On a clean attached branch, it checks the local changes against their common
ancestor with fetched main, then runs `git pull origin main --rebase` with
hooks and autostash disabled. Remote-only code changes do not disqualify local
docs. It rechecks the resulting docs-only fast-forward snapshot before the
existing credential and single non-force push flow. There is no commit selection,
candidate worktree, validation command or receipt.

Non-doc history is never automatically pulled or rebased. It must already be
a clean fast-forward of fetched main; divergence stops before confirmation.
The confirmed snapshot is rechecked before credentials and again before pushing.

A failed pull/rebase stops without pushing. A conflict is left for you to
resolve or cancel with `git rebase --abort`; no automatic push retry occurs.
If rebase leaves nothing to publish, the command stops without credentials.

Detached snapshots used by the native Pi broker are never pulled or rewritten:
a current docs-only fast-forward can publish unchanged; a stale snapshot stops
and requires docs rebasing on an attached branch before fresh native approval.

## Host credential prompt controls

Preflight accepts `GIT_CONFIG_COUNT` only when it describes zero to two unique
entries disabling `credential.interactive` (`false`, `0`, or `never`) or
`credential.guiPrompt` (`false` or `0`). Missing pairs, duplicate or unknown keys,
extra indexed variables, and enabled/invalid values are rejected without
printing their values. Other ambient Git overrides remain forbidden. The push
still replaces ambient indexed configuration with its own isolated settings.

The fixed Crisp main target, selected-repository scope, fast-forward checks,
hook isolation, and short-lived token revocation remain unchanged. Non-docs
changes require typed confirmation; docs-only changes skip it. Agent publication
still requires its separate native Super Push approval. Automation-vault access
removes only runtime 1Password approval. No live push is needed for validation.
