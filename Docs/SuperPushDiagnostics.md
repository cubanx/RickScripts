# Super Push diagnostics

`Invoke-SuperPush` retains a redacted diagnostic file on success and failure,
including failures before credential access. It prints `Diagnostics: <path>` and
includes the path in failure text. No broker, confirmation, target, ancestry,
credential route, retry, or force-push authorization is changed.

## Retained evidence

- Actual PowerShell invocation location, timestamps, operation phase and Git arguments.
- Separate Git stdout/stderr and exit status, including successful fetch output
  previously discarded. Only stdout participates in internal SHA/path parsing.
- Repository root, target ref, old/new SHAs when preflight completes; partial
  preflight command results remain available if it does not.
- Push acceptance, whether the push helper was entered, token revocation and Git
  environment restoration outcomes. An entered helper with no confirmed acceptance
  is explicitly uncertain; it is not proof that Git transmitted a push.
- Allowlisted provider context: operation, HTTP/CLI status where available,
  exception type and validated expiry. Arbitrary provider response/exception text
  is omitted, especially when a key or minted token has not yet been returned.

Failures still require reconciliation and fresh authorization before any retry.
These diagnostics do not identify the cause of either historical failure.

## Redaction and limits

The Automation token is not the only secret: private keys (including PEM body
lines), App JWTs, installation tokens and Basic/Bearer headers must also stay out
of diagnostics. Known values are registered before use and redacted together with
UTF-8 Base64/Base64URL, URL-escaped and JSON-escaped forms. Credential-bearing HTTP
URLs, query strings, authorization headers, private-key blocks and recognizable
GitHub token/JWT forms receive additional redaction. Token-sensitive Git config
values are omitted altogether. Visible Git evidence uses the same redactor.

This is not a transcript: confirmation input, environment dumps, provider bodies,
raw ErrorRecords and stacks are never recorded. stdout/stderr are individually
preserved, but their cross-stream timing/order is not. Unrelated secrets printed
as unrecognizable bare text or arbitrary unsupported encodings cannot be reliably
classified; this is not a general-purpose secret scanner. Do not enable secret
tracing or treat arbitrary provider payloads as safe to log.

## Retention boundary

On macOS, .NET exclusively creates an unpredictable current-user-owned temporary
subdirectory (0700); the file is created exclusively with mode 0600. The destination
must not be a symlink. Ancestor ownership and permissions are checked; directories
owned by another user or publicly writable without the sticky bit are rejected.
There is no configurable destination and no caller-supplied filename.

Files remain after normal process exit, but OS temporary-directory cleanup can
remove them. Copy redacted evidence to an appropriate private location when needed,
and remove the temporary directory when finished. No automatic upload occurs.
Retention uses .NET APIs available in current PowerShell; older runtimes lacking
those APIs report retention failure rather than falling back to unsafe file creation.
Hard termination before finalization cannot produce a retained file. Retention
failure is reported only after token cleanup, and never authorizes another push.

## Validation

Run `pwsh -NoProfile -File ./Tests/Run-Tests.ps1`. The diagnostic regression tests
mock all push, credential and provider operations; the native capture test runs
only a harmless invalid local Git option. Never run a real Super Push to test
logging. Implementation in an isolated worktree is not an installed-module update.
