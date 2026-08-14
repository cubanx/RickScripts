## 1. Tests First

- [x] 1.1 Add focused mocked Pester coverage for exact Atlas command construction, explicit project targeting, and the eight-hour default expiry.
- [x] 1.2 Add focused mocked Pester coverage for configured expiry, optional profile forwarding, manifest export, and actionable native-command failure.
- [x] 1.3 Run the focused tests and confirm they fail because the command is not implemented.

## 2. Command Implementation

- [x] 2.1 Add `Add-TemporaryAtlasIpAccess` as a thin Atlas CLI wrapper with mandatory project ID, validated hours, and optional profile.
- [x] 2.2 Export `Add-TemporaryAtlasIpAccess` through `RickScripts.psd1`.

## 3. Validation

- [x] 3.1 Run the focused Pester tests.
- [x] 3.2 Run the repository-required Pester suite.
- [x] 3.3 Strictly validate `add-temporary-atlas-ip-access` after implementation and inspect the final diff for scope and secret safety.

## 4. Current IP Output

- [x] 4.1 Update focused mocked Pester coverage to require Atlas JSON output and the reported public IP.
- [x] 4.2 Parse successful Atlas JSON output and echo only its `ipAddress` value.
- [x] 4.3 Run focused and repository-required Pester tests plus strict OpenSpec validation.

## 5. Atlas Response Envelope

- [x] 5.1 Update focused coverage to match Atlas's `results` response envelope.
- [x] 5.2 Read the echoed IP from the created entry in `results`.
- [x] 5.3 Run focused and repository-required Pester tests plus strict OpenSpec validation.

## 6. Service-Account and Removal Tests First

- [x] 6.1 Add focused mocked Pester coverage for optional explicit service-account targeting, Atlas-reported IP reuse, profile forwarding, pre-existing entry refusal, and local record creation.
- [x] 6.2 Add focused mocked Pester coverage proving removal deletes native temporary database entries but not permanent ones, and deletes only identity-matched locally tracked service-account entries.
- [x] 6.3 Add failure coverage proving service-account create/delete failures are actionable and failed deletion retains its local record.
- [x] 6.4 Run the focused tests and confirm they fail because the new behavior is not implemented.

## 7. Service-Account and Removal Implementation

- [x] 7.1 Extend `Add-TemporaryAtlasIpAccess` with optional explicit project service-account access and non-secret local cleanup records.
- [x] 7.2 Add `Remove-TemporaryAtlasIpAccess` with explicit project/service-account scope and fail-closed temporary-entry filtering.
- [x] 7.3 Export `Remove-TemporaryAtlasIpAccess` through `RickScripts.psd1`.

## 8. Validation

- [x] 8.1 Run focused Pester coverage for both temporary Atlas IP commands.
- [x] 8.2 Run the repository-required Pester suite.
- [x] 8.3 Strictly validate `add-temporary-atlas-ip-access` and inspect the final diff for scope and secret safety.

## 9. Atlas IP Detection Fallback Tests First

- [x] 9.1 Add focused mocked Pester coverage proving the fallback runs only for Atlas's exact current-IP detection failure and reuses the validated IP for database and service-account access.
- [x] 9.2 Add focused mocked Pester coverage for unavailable or invalid fallback responses and for non-detection Atlas failures that must not retry.
- [x] 9.3 Run the focused tests and confirm they fail because fallback behavior is not implemented.

## 10. Atlas IP Detection Fallback Implementation

- [x] 10.1 Add the bounded `api.ipify.org` fallback with timeout and public-IPv4 validation.
- [x] 10.2 Retry one explicit-IP Atlas creation with the original project, expiry, profile, and output arguments, then continue with Atlas's confirmed response IP.

## 11. Fallback Validation

- [x] 11.1 Run focused Pester coverage for both temporary Atlas IP commands.
- [x] 11.2 Run the repository-required Pester suite.
- [x] 11.3 Strictly validate `add-temporary-atlas-ip-access` and inspect the final diff for scope and secret safety.
