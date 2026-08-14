## ADDED Requirements

### Requirement: Explicit change selection
The command SHALL accept an explicit OpenSpec change name and SHALL report that change without applying inference.

#### Scenario: Caller names an active change
- **WHEN** the caller supplies an active change name
- **THEN** the command reports status for that named change

#### Scenario: Caller names an unknown change
- **WHEN** the caller supplies a name absent from the active OpenSpec change list
- **THEN** the command fails without selecting another change

### Requirement: Conservative current-change inference
Without an explicit name, the command SHALL evaluate unique dirty OpenSpec paths, the current branch, branch changes, the current commit, and conservative branch-token similarity in descending precedence, and SHALL only select names present in the active OpenSpec change list.

#### Scenario: One dirty OpenSpec change exists
- **WHEN** the worktree contains changes beneath exactly one active `openspec/changes/<name>/` directory
- **THEN** the command selects that change before evaluating branch evidence

#### Scenario: Branch suffix names an active change
- **WHEN** no dirty OpenSpec change exists and the current branch suffix exactly names an active change
- **THEN** the command selects that change

#### Scenario: Git evidence names one active change
- **WHEN** stronger signals do not resolve and either the branch diff or current commit touches exactly one active change
- **THEN** the command selects that change

#### Scenario: Branch wording uniquely resembles a change
- **WHEN** stronger signals do not resolve and exactly one active change has the unique highest score of at least three meaningful tokens shared with the branch suffix
- **THEN** the command selects that change

#### Scenario: Detached worktree has no dirty OpenSpec change
- **WHEN** the worktree is detached and has no unique dirty OpenSpec change
- **THEN** the command does not infer a change from branch or commit history

### Requirement: Ambiguity fails safely
The command SHALL use interactive `fzf` selection when inference is ambiguous and SHALL fail clearly when no selection can be made.

#### Scenario: User selects an ambiguous change
- **WHEN** multiple active changes remain and `fzf` returns one of them
- **THEN** the command reports the selected change

#### Scenario: Picker is unavailable or cancelled
- **WHEN** inference is ambiguous and `fzf` is unavailable or returns no selection
- **THEN** the command fails without guessing

#### Scenario: Multiple dirty changes exist
- **WHEN** the worktree modifies more than one active OpenSpec change
- **THEN** the command bypasses weaker inference and requires selection

### Requirement: Native OpenSpec status reporting
The command SHALL delegate artifact status to `openspec status` and SHALL include the selected change's task counts from `openspec list --json`.

#### Scenario: Status succeeds
- **WHEN** a change is selected and OpenSpec status succeeds
- **THEN** the command emits native artifact status followed by completed and total task counts

#### Scenario: OpenSpec command fails
- **WHEN** listing changes or reporting status exits unsuccessfully or returns invalid data
- **THEN** the command fails with diagnostic context instead of returning partial success

### Requirement: Short shell entry points
The command SHALL be available as `goss` in PowerShell and through a no-argument `goss()` wrapper in the managed zsh profile.

#### Scenario: PowerShell alias
- **WHEN** RickScripts is imported in PowerShell
- **THEN** `goss` resolves to `Get-OpenSpecStatus`

#### Scenario: Zsh wrapper
- **WHEN** the managed zsh profile is loaded and `goss` is invoked
- **THEN** zsh imports RickScripts in a clean PowerShell process and runs `Get-OpenSpecStatus`
