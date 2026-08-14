## ADDED Requirements

### Requirement: Temporary Atlas IP access command is exported
The module SHALL export `Add-TemporaryAtlasIpAccess` through its existing manifest conventions.

#### Scenario: Module exposes the command
- **WHEN** a caller imports the RickScripts module
- **THEN** `Add-TemporaryAtlasIpAccess` is available as an exported function

### Requirement: Every invocation targets one explicit project
`Add-TemporaryAtlasIpAccess` SHALL require a non-empty Atlas project ID and SHALL pass it to one `atlas accessLists create` operation using `--projectId`. The command SHALL NOT enumerate projects or implicitly mutate more than one project.

#### Scenario: Explicit project is targeted
- **WHEN** the caller supplies a project ID
- **THEN** the command invokes Atlas once with that project ID

#### Scenario: Project ID is omitted
- **WHEN** the caller omits the project ID
- **THEN** PowerShell rejects the invocation before Atlas runs

### Requirement: Current-IP detection is Atlas-first with one bounded fallback
`Add-TemporaryAtlasIpAccess` SHALL first invoke `atlas accessLists create` with `--currentIp` and an ISO-8601 UTC `--deleteAfter` value. If and only if Atlas reports that it cannot find the caller's public IP, the command SHALL request `https://api.ipify.org`, validate a public IPv4 response, and retry creation once with that explicit IP and `--type ipAddress`. It SHALL default expiry to eight hours from invocation and SHALL accept an explicit duration from 1 through 168 hours.

#### Scenario: Default expiry
- **WHEN** the caller omits the duration
- **THEN** the command requests automatic deletion approximately eight hours after invocation

#### Scenario: Configured expiry
- **WHEN** the caller supplies an allowed hour value
- **THEN** the command requests automatic deletion approximately that many hours after invocation

#### Scenario: Successful current-IP creation
- **WHEN** Atlas creates the temporary access-list entry
- **THEN** the command outputs the public IP address reported by Atlas

#### Scenario: Atlas cannot detect the current IP
- **WHEN** Atlas returns its specific public-IP detection failure
- **THEN** the command resolves and validates the IP through the bounded fallback and retries the same project mutation once with that explicit IP

#### Scenario: Fallback response is unavailable or invalid
- **WHEN** Atlas current-IP detection fails and the fallback cannot return a valid public IPv4 address
- **THEN** the command throws an actionable error and performs no explicit-IP Atlas mutation

#### Scenario: Duration is outside the Atlas temporary-entry limit
- **WHEN** the caller supplies fewer than 1 or more than 168 hours
- **THEN** PowerShell rejects the invocation before Atlas runs

### Requirement: Atlas CLI profile can be explicit
`Add-TemporaryAtlasIpAccess` SHALL accept an optional Atlas CLI profile and SHALL forward it using `--profile` without reading or storing credentials.

#### Scenario: Profile is supplied
- **WHEN** the caller supplies an Atlas CLI profile
- **THEN** the command invokes Atlas with that profile

#### Scenario: Profile is omitted
- **WHEN** the caller omits the profile
- **THEN** the command does not add a profile argument and allows Atlas CLI to use its normal authentication resolution

### Requirement: Native command failures are actionable
`Add-TemporaryAtlasIpAccess` SHALL terminate on an Atlas CLI failure with an error that identifies the target project and directs the operator to check Atlas CLI authentication and project network-access authorization without disclosing credentials.

#### Scenario: Atlas CLI returns a non-detection nonzero exit code
- **WHEN** the native Atlas operation fails for authorization or any reason other than current-IP detection
- **THEN** the command throws an actionable sanitized error and does not invoke the fallback or attempt another Atlas operation

### Requirement: One explicit project service account can receive the resolved IP
`Add-TemporaryAtlasIpAccess` SHALL accept an optional project service-account client ID. When supplied, it SHALL use the IP confirmed by the successful `atlas accessLists create` response, SHALL target only that service account and the mandatory project, and SHALL forward the selected profile. It SHALL NOT perform another IP discovery or enumerate service accounts.

#### Scenario: Service account is supplied
- **WHEN** the caller supplies a service-account client ID and Atlas reports the current IP
- **THEN** the command checks and adds that IP to exactly that project service account

#### Scenario: Service account is omitted
- **WHEN** the caller omits the service-account client ID
- **THEN** the command creates only the native temporary database access-list entry

#### Scenario: IP already exists for the service account
- **WHEN** the exact Atlas-reported IP already appears in the named service account's access list
- **THEN** the command does not adopt, track, or mutate that service-account entry and reports that it cannot safely treat the existing entry as temporary

### Requirement: RickScripts tracks only service-account entries it creates
After Atlas creates a service-account access-list entry, `Add-TemporaryAtlasIpAccess` SHALL store its project ID, service-account client ID, IP address, Atlas creation timestamp, and intended expiry in a local RickScripts state file. It SHALL NOT store credentials, access tokens, or resolved secrets, and the state file SHALL NOT be stored in the repository.

#### Scenario: Service-account entry is created
- **WHEN** Atlas successfully creates the service-account access-list entry
- **THEN** the command records enough non-secret identity metadata for fail-closed removal

#### Scenario: Service-account creation fails
- **WHEN** Atlas fails to create the service-account entry
- **THEN** the command throws an actionable error and does not record the failed entry

### Requirement: Temporary Atlas IP removal is exported and explicitly scoped
The module SHALL export `Remove-TemporaryAtlasIpAccess`. The command SHALL require one project ID, SHALL accept an optional service-account client ID and profile, and SHALL NOT enumerate or mutate other projects or service accounts.

#### Scenario: Removal command is imported
- **WHEN** a caller imports RickScripts
- **THEN** `Remove-TemporaryAtlasIpAccess` is available as an exported function

#### Scenario: Project ID is omitted from removal
- **WHEN** the caller omits the project ID
- **THEN** PowerShell rejects the invocation before Atlas runs

### Requirement: Removal deletes only provably temporary entries
`Remove-TemporaryAtlasIpAccess` SHALL delete every database access-list entry in the named project whose Atlas response has a non-null `deleteAfterDate`. When a service account is named, it SHALL consider only local records for that exact project and service account and SHALL delete an Atlas entry only when both its IP and creation timestamp match the record.

#### Scenario: Database access list contains temporary and permanent entries
- **WHEN** removal lists the named project's database access list
- **THEN** it deletes entries with `deleteAfterDate` and leaves permanent entries unchanged

#### Scenario: Tracked service-account entry matches Atlas
- **WHEN** a local record and Atlas entry have the same project, client ID, IP, and creation timestamp
- **THEN** removal deletes that exact service-account entry and removes its local record

#### Scenario: Service-account entry identity differs
- **WHEN** Atlas has the recorded IP with a different creation timestamp
- **THEN** removal refuses to delete it and retains the local record

#### Scenario: Native service-account deletion fails
- **WHEN** Atlas fails to delete a matching tracked entry
- **THEN** removal throws an actionable error and retains the local record for retry
