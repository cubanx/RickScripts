## ADDED Requirements

### Requirement: Read-only structured change summary
The module SHALL export `Get-CodexChangeSummary`, which invokes `codex exec` with `gpt-5.6-luna`, low reasoning effort, `--ephemeral`, `--sandbox read-only`, `--output-schema`, and `--output-last-message` to obtain a structured summary of the current Git change. The result SHALL expose what changed, why, user impact, developer impact, validation, and human title fields.

#### Scenario: Summary command uses constrained Codex execution
- **WHEN** a caller invokes `Get-CodexChangeSummary`
- **THEN** it invokes `gpt-5.6-luna` with low reasoning effort in ephemeral read-only sandbox mode with an output schema and last-message output

#### Scenario: Structured summary is returned to caller
- **WHEN** Codex returns a valid structured summary
- **THEN** callers can read what changed, why, user impact, developer impact, validation, and human title without Git or GitHub mutations

### Requirement: Summary command is dependency-free and testable
The module SHALL implement `Get-CodexChangeSummary` with only native PowerShell and the `codex` executable, and SHALL provide dependency-free tests that mock Codex execution.

#### Scenario: Mocked Codex test exercises the command
- **WHEN** focused module tests run without the Codex executable
- **THEN** mocked Codex output verifies the command's invocation and structured result
