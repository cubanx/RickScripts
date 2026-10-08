## ADDED Requirements

### Requirement: Explicit isolated task scope
RickScripts SHALL expose advanced function `New-SuperPushCandidate` and SHALL
prepare only explicitly selected full ordinary commit SHAs in oldest-first
ancestry order, reachable from source HEAD and not already on fetched main.
It SHALL fetch current main and replay the selected commits in a clean isolated
detached worktree, without merging the source branch or altering source HEAD,
branch, index, tracked edits or untracked files. Missing scope, duplicates,
merges, root commits, foreign commits, wrong order, conflicts and empty replays
SHALL fail closed without credential access or publication.

#### Scenario: Docs task trails advanced main
- **WHEN** main advanced, the source has unrelated history and dirty/staged/untracked work, and one docs task commit is explicitly selected
- **THEN** preparation yields only that selected commit on current main in a clean detached worktree and preserves the source

#### Scenario: Scope or replay is invalid
- **WHEN** scope is absent, ambiguous or unsupported, or cherry-picking conflicts
- **THEN** preparation stops and removes only its newly allocated isolated worktree

### Requirement: Docs convenience and non-doc validation
Preparation SHALL classify the net diff and every introduced commit with existing
fail-closed documentation metadata rules. Docs-only preparation SHALL require Git
safety, identity, cleanliness and fast-forward checks, but not a validator or
internal typed confirmation. Non-doc preparation SHALL require a supplied
validation executable/argument array, successful bounded execution in candidate
cwd, unchanged HEAD and clean worktree before exact evidence and `Approved`.
Validation SHALL NOT imply authorization for external effects.

#### Scenario: Intermediate code is hidden in a docs net diff
- **WHEN** intermediate introduced commits add/revert executable content while the final diff is docs-only
- **THEN** validation and typed approval are required

#### Scenario: Validator is missing, fails or changes the candidate
- **WHEN** a non-doc candidate lacks a validator, the validator fails or candidate HEAD/files change
- **THEN** preparation stops before approval, credential access or a push

### Requirement: Bounded pre-approval docs recovery
Docs preparation MAY rebuild the same explicitly selected scope when remote main
moves during local preparation, for at most three attempts before returning a
candidate. It SHALL NOT retry conflicts, widen scope or retry any push.

#### Scenario: Main advances during docs replay
- **WHEN** main moves during docs-only preparation before the candidate is returned
- **THEN** preparation may replay the same commits on newly fetched main without touching the source

### Requirement: Exact candidate approval boundary
Human `Invoke-SuperPush` SHALL own preparation, evidence and publication while
allowing only task scope and validation inputs, not repository, ref, force,
credentials or approval bypass inputs. Pi SHALL prepare before native exact-SHA
approval through the exported contract. A detached publication invocation SHALL
NOT rewrite the candidate. Identity-bound local validation receipts SHALL be
frozen along with SHA across repeated checks. Remote, receipt, origin, candidate
or cleanliness drift after preparation/approval SHALL stop publication.

#### Scenario: Prepared candidate enters the fixed broker
- **WHEN** the native-approved detached candidate is invoked through the no-argument broker
- **THEN** it is not cherry-picked, merged, rebased or otherwise rewritten

#### Scenario: Approval-time drift
- **WHEN** the remote, candidate or validation receipt changes
- **THEN** publication stops without rebuilding, broadening authorization or retrying a push

### Requirement: Existing access and recovery boundaries
Publication SHALL retain the fixed main ref, fast-forward guard, one non-force
push, credential isolation, token revocation, sanitized diagnostics and no
uncertain-push retry. Successful candidate worktrees SHALL remain available for
review/recovery with caller-owned cleanup and original caller location restored.
Validation SHALL use local Git remotes and faked publication/provider boundaries;
dotfiles integration, credentials, deployment and real pushes SHALL require
separate scope and authorization.

#### Scenario: Validated implementation handoff
- **WHEN** RickScripts implementation is complete
- **THEN** the exact preparation interface and remaining dotfiles integration gap are reported without claiming deployment or real publication
