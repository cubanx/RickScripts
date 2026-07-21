## ADDED Requirements

### Requirement: GitHub publishing command is exported
The module SHALL export `Publish-GitChanges` and the stable `yeet` alias.

#### Scenario: Module import exposes publishing command
- **WHEN** the module is imported
- **THEN** `Publish-GitChanges` and `yeet` are available to callers

### Requirement: Publishing parameters have safe defaults
`Publish-GitChanges` SHALL accept optional `-BranchName` and `-BaseBranch`, SHALL default `-BaseBranch` to the remote default branch, and SHALL create draft pull requests unless `-Ready` is supplied. The command SHALL not expose `-Path` or `-All` parameters.

#### Scenario: Default invocation creates a draft PR
- **WHEN** a caller invokes `Publish-GitChanges` without `-Ready`
- **THEN** it requests a draft pull request against the remote default branch

#### Scenario: Ready invocation creates a ready PR
- **WHEN** a caller invokes `Publish-GitChanges -Ready`
- **THEN** it requests a ready pull request

### Requirement: Publishing stages and checks the complete worktree
Before mutation, `Publish-GitChanges` SHALL display the staged and unstaged/untracked scope and stop when the worktree has no changes. It SHALL stage the complete worktree with `git add -A`, run `git diff --cached --check`, inspect the staged paths, and stop without committing when the staged diff is empty or invalid.

#### Scenario: Scope is shown before mutation
- **WHEN** the worktree contains changes
- **THEN** the command displays staged and unstaged/untracked paths before creating a branch or staging files

#### Scenario: Clean worktree stops publishing
- **WHEN** the worktree contains no changes
- **THEN** the command stops before branch creation, staging, committing, pushing, or pull-request creation

#### Scenario: Unstaged and untracked changes are included
- **WHEN** the worktree contains tracked, untracked, or unstaged changes
- **THEN** the publishing command stages all of them before checking the staged diff

#### Scenario: Staged diff passes Git's cached check
- **WHEN** the complete worktree has been staged
- **THEN** the command runs `git diff --cached --check` before committing

#### Scenario: Empty staged diff is not committed
- **WHEN** staging produces no staged changes
- **THEN** the publishing command stops before creating a commit, pushing, or creating a pull request

### Requirement: Publishing uses repository-slug branch names
`Publish-GitChanges` SHALL stay on an existing non-default feature branch. From a detached `HEAD` or default branch, it SHALL create the supplied `-BranchName` or derive a publishing branch name from the repository slug conventions: `dw` for `data-warehouse`, `ia` for `internal-apps`, `ea` for `external-api`, and initials from hyphen-separated or CamelCase names for unlisted repositories. It SHALL not use a generic `codex/` branch prefix.

#### Scenario: Known repository slug is used
- **WHEN** the current repository has a known slug convention
- **THEN** the command creates a branch prefixed by that slug

#### Scenario: Existing feature branch is retained
- **WHEN** the current branch is a non-default feature branch and no `-BranchName` is supplied
- **THEN** the command remains on that branch

#### Scenario: Default or detached branch creates a publishing branch
- **WHEN** `HEAD` is detached or on the default branch
- **THEN** the command creates the supplied `-BranchName` or derived slug-prefixed branch

### Requirement: Single-OpenSpec publishing is deterministic
When every changed path belongs to exactly one `openspec/changes/<change-name>/` directory, `Publish-GitChanges` SHALL avoid Codex and use `<repo-slug>/<change-name>` when it must create a branch, `docs: add <space-separated-change-name-with-leading-add-removed> OpenSpec` as the commit message, the matching `Add ... OpenSpec` human title, and deterministic specification-only PR summary fields. Multiple OpenSpec change directories or any changed path outside that directory SHALL use the normal Codex summary path.

#### Scenario: One OpenSpec change avoids Codex
- **WHEN** all worktree changes belong to one OpenSpec change directory
- **THEN** publishing uses deterministic branch, commit, title, and body metadata without invoking Codex

#### Scenario: Mixed or ambiguous changes use Codex
- **WHEN** changes span multiple OpenSpec directories or include any non-OpenSpec path
- **THEN** publishing invokes `Get-CodexChangeSummary` exactly once

### Requirement: Existing pull requests are updated without duplication
`Publish-GitChanges` SHALL validate an accessible `origin` and query GitHub for an existing pull request for the publishing branch before any mutation. It SHALL not run separate GitHub version or authentication preflight commands. When the current non-default branch already has an open pull request, the command SHALL stage, validate, commit, and push the complete worktree, then report that pull request without creating or retitling it.

#### Scenario: Existing branch pull request is found
- **WHEN** GitHub reports an existing pull request for the publishing branch
- **THEN** the command commits and pushes the complete worktree, skips pull-request creation and title editing, and reports the existing pull request

### Requirement: Pre-mutation validation failures stop publishing
`Publish-GitChanges` SHALL stop before Git mutation when origin validation or a required GitHub query/auth command fails before the first mutation.

#### Scenario: GitHub query or authentication fails before staging
- **WHEN** the GitHub pull-request query or authentication fails before staging or committing
- **THEN** the command stops and surfaces the failure without mutating Git state

#### Scenario: Origin is inaccessible
- **WHEN** the `origin` remote is missing or inaccessible
- **THEN** the command stops before branch creation, staging, committing, or pushing

### Requirement: Pull requests have explicit mode, numbered title, and summary
`Publish-GitChanges` SHALL call `Get-CodexChangeSummary` exactly once unless the deterministic single-OpenSpec path applies. It SHALL create a temporary Markdown PR body containing the selected summary's what changed, why, user impact, developer impact, and validation plus actual staged diff-check evidence. It SHALL create a draft or ready GitHub pull request according to its command option, set the final title to `[<repo-slug>-#<number>] <human title>`, and report the branch, commit SHA, PR URL, title, and final worktree status.

#### Scenario: Draft pull request is requested
- **WHEN** a caller requests draft publishing
- **THEN** the command creates a draft pull request and reports its branch, commit SHA, URL, `[<repo-slug>-#<number>] <human title>` title, summary, and final worktree status

#### Scenario: Ready pull request is requested
- **WHEN** a caller requests ready publishing
- **THEN** the command creates a ready pull request and reports its branch, commit SHA, URL, `[<repo-slug>-#<number>] <human title>` title, summary, and final worktree status

#### Scenario: Summary is called once for non-OpenSpec publishing
- **WHEN** a caller invokes `Publish-GitChanges` for changes outside the deterministic OpenSpec-only path
- **THEN** it invokes `Get-CodexChangeSummary` exactly once

### Requirement: Legacy GitLab merge-request entrypoints are retired
The module SHALL remove `New-MergeRequest`/`nmr` and `Open-MergeRequest`/`omr` from its exported function and alias surface, documentation, and function loading, while leaving Bash tooling unchanged.

#### Scenario: Retired entrypoints are absent after import
- **WHEN** the updated module is imported
- **THEN** `New-MergeRequest`, `nmr`, `Open-MergeRequest`, and `omr` are not exported by the module

### Requirement: Publishing is dependency-free, documented, and testable
The module SHALL use only native PowerShell plus `git`, `gh`, and `codex`, SHALL provide comment-based help and PowerShell examples documenting complete-tree staging, branch/base selection, draft/ready behavior, and safe stops, and SHALL provide dependency-free focused tests with mocked executables.

#### Scenario: Mocked workflow verifies required behavior
- **WHEN** focused tests run without GitHub or Codex access
- **THEN** mocked calls verify auth failure causes no mutation, default/detached branch handling, deterministic OpenSpec-only publishing without Codex, mixed-change Codex fallback, complete-tree staging, existing-PR commit/push without duplicate creation, successful draft numbered title, and the single fallback summary call

### Requirement: Failures are surfaced without destructive recovery
Failures SHALL stop without stash, reset, force operations, destructive cleanup, or swallowed exceptions.

#### Scenario: Failure preserves worktree changes
- **WHEN** validation, Git, GitHub, Codex, commit, push, or PR creation fails
- **THEN** the command surfaces the error and does not stash, reset, force, destructively clean, or suppress the failure
