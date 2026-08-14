## 1. Focused Tests

- [x] 1.1 Add Pester coverage for explicit selection, each inference signal, detached and ambiguous fallbacks, command failures, task progress, and module export.

## 2. Implementation

- [x] 2.1 Implement conservative active-change discovery in `Get-OpenSpecStatus` using native PowerShell and Git.
- [x] 2.2 Delegate artifact reporting to OpenSpec and append its listed task progress with complete error handling.
- [x] 2.3 Export the command and add comment-based help.

## 3. Validation

- [x] 3.1 Run focused Pester tests, the full Pester suite, module import/export checks, strict OpenSpec validation, and `git diff --check`.

## 4. Shell Aliases

- [x] 4.1 Add focused export coverage for the `goss` PowerShell alias.
- [x] 4.2 Export `goss`, mirror the existing zsh `yeet()` wrapper, and validate both shell entry points.
