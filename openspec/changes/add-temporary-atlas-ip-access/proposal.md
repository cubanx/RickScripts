## Why

Working from home is blocked when the operator's public IP is absent from an Atlas project's database IP access list or from a project service account's API access list. A single explicit command should grant both forms of access without manual IP discovery.

## What Changes

- Add exported `Add-TemporaryAtlasIpAccess`, requiring one Atlas project ID per invocation.
- Use `atlas accessLists create --currentIp --deleteAfter` first. If and only if Atlas reports that it cannot detect the public IP, resolve it through `api.ipify.org`, validate it locally, and retry the Atlas creation with that explicit IP.
- Default access to eight hours, allow an explicit duration up to Atlas's seven-day temporary-entry limit, and forward an optional Atlas CLI profile.
- Echo the public IP address reported by Atlas after successful creation.
- Optionally add that same Atlas-reported IP to one explicitly named project service account. Because Atlas service-account access-list entries have no native expiry or labels, record only entries created by RickScripts in a local state file with their intended expiry and Atlas creation timestamp.
- Add exported `Remove-TemporaryAtlasIpAccess`, requiring one project ID and optionally one service-account client ID. It removes every database entry Atlas marks with `deleteAfterDate` in that project and only locally tracked, identity-matched service-account entries.
- Surface native Atlas CLI failures with an actionable error.
- Do not enumerate projects or service accounts, store project IDs or credentials in the repository, use the fallback for authorization or other Atlas failures, or infer temporary service-account entries from age or address alone.

## Capabilities

### New Capabilities

- `temporary-atlas-ip-access`: Explicitly add or remove the operator's current public IP for one Atlas project and, when named, one project service account.

### Modified Capabilities

None.

## Impact

- Adds two functions under `Functions/`, two explicit exports in `RickScripts.psd1`, and focused mocked Pester coverage.
- Requires the existing Atlas CLI. Database access-list changes need project network-access permission; project service-account access-list changes need `Project Access Manager`.
- Stores non-secret local cleanup metadata under the user's `.RickScripts` directory; no identifiers or credentials are stored in the repository.
- Makes no real Atlas call during implementation or validation and adds no dependencies or stored configuration.
