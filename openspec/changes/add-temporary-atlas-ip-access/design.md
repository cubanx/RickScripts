## Context

`RickScripts` recursively loads function files and explicitly exports public commands through `RickScripts.psd1`. Atlas CLI normally owns current-public-IP detection, profile authentication, database access-list creation, and database-entry expiry. Atlas CLI's private current-IP endpoint can fail even when ordinary public-IP resolution works. Atlas project service-account API access-list entries support only an IP address or CIDR block plus a creation timestamp; they have no native expiry or label.

## Goals / Non-Goals

**Goals:**
- Require the caller to identify exactly one Atlas project.
- Create one temporary current-IP access-list entry with an eight-hour default.
- Allow bounded expiry configuration and optional Atlas CLI profile selection.
- Optionally add the Atlas-reported IP to one explicitly named project service account.
- Remove temporary database entries and only service-account entries provably created and tracked by RickScripts.
- Preserve native output and turn native failures into actionable PowerShell errors.

**Non-Goals:**
- Do not enumerate Atlas projects or apply one invocation to multiple projects.
- Do not use independent IP discovery unless Atlas returns its exact current-IP detection failure, and do not schedule background cleanup.
- Do not manage Atlas authentication, credentials, project IDs, or secrets.
- Do not infer that a service-account entry is temporary from its age or IP address alone.
- Do not make an Atlas call from tests or validation.

## Decisions

- Add one `Functions/Add-TemporaryAtlasIpAccess.ps1` advanced function and list it in `FunctionsToExport`. No alias or shared helper is needed.
- Require `-ProjectId` and pass it as `--projectId`, overriding any project stored in the Atlas profile. This makes the mutation boundary visible on every invocation.
- Accept `-Hours` as an integer from 1 through 168, defaulting to 8. Convert the expiry once from the current time to an ISO-8601 UTC timestamp for `--deleteAfter`; Atlas's temporary-entry API supports up to seven days.
- First pass `--currentIp`. Capture the native diagnostic and use a fallback only when it contains Atlas's specific inability-to-find-public-IP message; authorization and every other native failure remain terminal.
- For that one failure, call `https://api.ipify.org` with a short timeout, trim and validate the response as a public IPv4 address, then invoke `atlas accessLists create <ip> --type ipAddress` with the same project, expiry, output, and profile arguments. This is a bounded reliability fallback, not a general retry.
- Accept optional `-Profile` and forward it as the inherited `--profile` option. Operators should authenticate a project-scoped principal with `Project Network Access Manager`, the narrow Atlas role that can update access lists.
- Request Atlas JSON output, parse its `ipAddress`, and echo only that address after successful creation. The Atlas response remains authoritative even when the explicit-IP fallback is used.
- Accept optional `-ServiceAccountClientId`. After database creation reports the IP, list that exact service account's project access list, refuse to adopt an existing matching IP, then use `atlas api serviceAccounts createAccessList` with a temporary JSON request file containing only that IP.
- Record the created service-account entry's project ID, client ID, IP, `createdAt`, and intended expiry in `$HOME/.RickScripts/temporary-atlas-ip-access.json`. This local file contains no credential or secret and is never part of the repository.
- Add `Remove-TemporaryAtlasIpAccess` with mandatory `-ProjectId`, optional `-ServiceAccountClientId`, and optional `-Profile`. It lists only the named project's database access list and deletes entries with a non-null `deleteAfterDate`. When a service account is named, it considers only matching local records, verifies both IP and `createdAt` against Atlas, and then deletes the exact service-account access entry.
- Keep local records after a failed service-account deletion so cleanup can be retried. Remove stale records when Atlas confirms the exact recorded entry no longer exists. Refuse deletion when an IP exists with a different creation timestamp.
- Invoke `atlas` directly so Pester can replace the native command with a function and inspect arguments. Preserve native error output; on a nonzero exit, throw an error naming the project, exit code, and likely authentication/authorization checks without exposing credentials.

## Risks / Trade-offs

- The machine clock can skew the computed expiry → use UTC and leave enforcement to Atlas.
- A wrong explicit project ID targets the wrong project → require the ID every time and never infer or enumerate projects.
- Atlas authentication or authorization can fail → preserve native diagnostics and add a concise actionable terminating error.
- Atlas current-IP detection can fail independently of network connectivity → fall back once to `api.ipify.org` only for the exact detection error, validate IPv4 locally, and never retry other Atlas failures.
- Repeated invocation can create redundant requests → rely on Atlas behavior; listing or reconciling entries would add scope and permissions without helping the home-access path.
- Service-account entries do not expire automatically → record only RickScripts-created entries locally and provide an explicit removal command; do not claim Atlas will expire them.
- Local state can drift from Atlas → verify IP and creation timestamp before deletion, fail closed on mismatches, and retain records after native failures.
- A pre-existing service-account entry can be permanent → refuse to adopt or later delete it.
