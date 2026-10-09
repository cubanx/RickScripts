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

## Host credential prompt controls

Preflight accepts `GIT_CONFIG_COUNT` only when it describes zero to two unique
entries disabling `credential.interactive` (`false`, `0`, or `never`) or
`credential.guiPrompt` (`false` or `0`). Missing pairs, duplicate or unknown keys,
extra indexed variables, and enabled/invalid values are rejected without
printing their values. Other ambient Git overrides remain forbidden. The push
still replaces ambient indexed configuration with its own isolated settings.

The fixed Crisp main target, selected-repository scope, fast-forward checks,
existing push confirmation rules, hook isolation, and short-lived token
revocation remain unchanged. Agent publication still requires its separate
native Super Push approval; this change removes only runtime 1Password
approval. No live push is needed to test credential selection.
