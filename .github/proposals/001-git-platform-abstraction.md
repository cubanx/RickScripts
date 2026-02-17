# Proposal 001: Git Platform Abstraction Layer

**Status**: Proposed
**Author**: Rick Diaz
**Created**: 2026-02-17
**Updated**: 2026-02-17

## Summary

Add a platform abstraction layer to support both GitLab and GitHub, replacing the current hard-coded `glab` CLI dependency with auto-detected platform routing.

## Problem Statement

The RickScripts PowerShell module currently has tight coupling to GitLab through direct `glab` CLI usage in five core functions:

1. `New-MergeRequest` (`nmr`) — Creates MRs with templates and issue linking
2. `Switch-MergeRequest` (`smr`) — Interactive MR selection and checkout
3. `Copy-MergeRequest` (`cmr`) — Duplicates MRs with metadata
4. `Move-IssueState` (`mis`) — Label-based workflow state management
5. `Open-MergeRequest` (`omr`) — Opens MR in browser (partial dual support exists)

This coupling prevents the module from being used in GitHub-based repositories, limiting its utility for polyglot development workflows.

### Current Architecture Issues

- **Hard-coded CLI calls**: Direct `glab mr create`, `glab issue view`, etc.
- **GitLab-specific field names**: `.iid`, `.source_branch`, `.web_url`
- **Platform-specific flags**: `--related-issue`, `--copy-issue-labels`, `--remove-source-branch`
- **Template path assumptions**: `.gitlab/merge_request_templates/`
- **No fallback mechanism**: Functions fail entirely in GitHub repos

## Proposed Solution

### Architecture: Provider Pattern with Auto-Detection

Introduce a three-file abstraction layer in `Common/`:

```
Common/
├── GitProvider.ps1          # Platform detection + routing logic
├── GitProvider.GitLab.ps1   # GitLab-specific implementations
└── GitProvider.GitHub.ps1   # GitHub-specific implementations
```

#### GitProvider.ps1 (Router)

**Responsibilities:**
- Auto-detect platform from `git remote get-url origin`
- Route function calls to appropriate provider
- Normalize return values to unified schema
- Handle errors when CLI tools are missing

**Key Functions:**
```powershell
function Get-GitPlatform {
    # Returns: "github" | "gitlab" | "unknown"
    # Detection logic: Parse remote URL for github.com vs gitlab.com
}

function Get-PullRequest {
    param([int]$Number)
    # Returns normalized object with fields: .number, .sourceBranch, .targetBranch, .title, .url, .labels, .assignees
}

function New-PullRequest {
    param(
        [string]$Title,
        [string]$Body,
        [string]$TargetBranch,
        [switch]$Draft,
        [string[]]$Labels,
        [string[]]$Assignees,
        [string[]]$Reviewers
    )
    # Returns normalized PR/MR object
}

function Update-PullRequest {
    param(
        [int]$Number,
        [string[]]$AddLabels,
        [string[]]$RemoveLabels
    )
}

function Get-Issue {
    param([int]$Number)
    # Returns normalized issue object
}

function Update-Issue {
    param(
        [int]$Number,
        [string[]]$AddLabels,
        [string[]]$RemoveLabels,
        [string]$Assignee
    )
}

function Checkout-PullRequest {
    param([int]$Number)
}

function Get-TemplateDirectory {
    # Returns: ".gitlab/merge_request_templates" or ".github/pull_request_templates"
}

function Get-TemplatePath {
    param([string]$TemplateName = "prospector")
    # Returns full path to template file
}
```

#### GitProvider.GitLab.ps1

Wraps existing `glab` CLI calls:
- `Get-PullRequest` → `glab mr view --output json`
- `New-PullRequest` → `glab mr create` (with GitLab-specific flag mapping)
- Field normalization: `.iid` → `.number`, `.source_branch` → `.sourceBranch`, etc.

#### GitProvider.GitHub.ps1

Implements `gh` CLI equivalents:
- `Get-PullRequest` → `gh pr view --json ...`
- `New-PullRequest` → `gh pr create --draft --title ... --body ...`
- Workarounds for missing features (see Feature Parity Matrix below)

### Normalized Data Model

All provider functions return objects with these standardized fields:

| Field | Type | Description |
|-------|------|-------------|
| `.number` | int | PR/MR number (GitLab `.iid` → `.number`) |
| `.sourceBranch` | string | Head/source branch name |
| `.targetBranch` | string | Base/target branch name |
| `.title` | string | PR/MR title |
| `.url` | string | Web URL (GitLab `.web_url` → `.url`) |
| `.labels` | string[] | Applied labels |
| `.assignees` | string[] | Assigned users |
| `.reviewers` | string[] | Requested reviewers |
| `.milestone` | string | Milestone name |
| `.draft` | bool | Draft/WIP status |

### Function Naming: Dual Aliases

Keep existing `MergeRequest` naming for backward compatibility, add `PullRequest` aliases:

| Function | Existing Alias | New Alias | Notes |
|----------|----------------|-----------|-------|
| `New-MergeRequest` / `New-PullRequest` | `nmr` | `npr` | "NPR!" |
| `Switch-MergeRequest` / `Switch-PullRequest` | `smr` | `spr` | |
| `Copy-MergeRequest` / `Copy-PullRequest` | `cmr` | `cpr` | |
| `Open-MergeRequest` / `Open-PullRequest` | `omr` | `opr` | |

Implementation:
```powershell
# In New-MergeRequest.ps1
Set-Alias -Name nmr -Value New-MergeRequest
Set-Alias -Name npr -Value New-MergeRequest

# In RickScripts.psd1
FunctionsToExport = @('New-MergeRequest', 'New-PullRequest', ...)
AliasesToExport = @('nmr', 'npr', 'smr', 'spr', ...)
```

### Feature Parity Matrix

| Feature | GitLab (`glab`) | GitHub (`gh`) | Workaround |
|---------|----------------|---------------|------------|
| Create PR/MR | `glab mr create` | `gh pr create` | ✅ Direct mapping |
| Draft mode | `--draft` | `--draft` | ✅ Direct mapping |
| Link issue | `--related-issue 123` | N/A | ⚠️ Add `Closes #123` to body |
| Copy issue labels | `--copy-issue-labels` | N/A | ⚠️ Extra API call: `gh issue view --json labels` + `--add-label` |
| Remove source branch | `--remove-source-branch` | N/A | ⚠️ Repo setting, not per-PR |
| Squash commits | `--squash` | N/A | ⚠️ Merge-time setting, not creation |
| Set milestone | `--milestone "v1.0"` | N/A | ⚠️ Use `gh api` after creation |
| Checkout PR/MR | `glab mr checkout 123` | `gh pr checkout 123` | ✅ Direct mapping |
| List with labels | `glab mr list --label "bug"` | `gh pr list --search "label:bug"` | ⚠️ Different syntax |

**Workaround Strategy:**
- **Missing flags**: Implement in provider layer (e.g., `New-PullRequest` reads issue labels via API before creating PR)
- **Body text substitution**: Auto-inject `Closes #<issue>` when `--related-issue` is requested
- **Post-creation updates**: Use `gh api` for milestone setting after PR creation
- **Feature warnings**: Log when GitHub-unsupported features are requested

### Platform Detection Logic

```powershell
function Get-GitPlatform {
    $remote = git remote get-url origin 2>$null
    if (-not $remote) {
        Write-Warning "Not a git repository or no remote configured"
        return "unknown"
    }

    # Handle both HTTPS and SSH formats
    if ($remote -match '(github\.com[:/])') {
        return "github"
    } elseif ($remote -match '(gitlab\.com[:/])') {
        return "gitlab"
    } else {
        Write-Warning "Unknown git platform: $remote"
        return "unknown"
    }
}
```

**Fallback behavior:**
- If platform is `unknown`, prompt user to select platform
- Store selection in `~/.RickScripts/config.json` keyed by repo path
- Future calls in same repo use cached value

## Migration Path

### Phase 1: Infrastructure (Week 1)
1. Create `Common/GitProvider.ps1` with platform detection
2. Create `Common/GitProvider.GitLab.ps1` with existing `glab` wrappers
3. Create `Common/GitProvider.GitHub.ps1` with `gh` equivalents
4. Add provider tests (manual testing in both repo types)

### Phase 2: Function Refactoring (Week 2-3)
Refactor functions one at a time:

1. **`Open-MergeRequest`** (easiest, already has dual support)
   - Replace conditional logic with provider calls
   - Add `Open-PullRequest` alias

2. **`Switch-MergeRequest`**
   - Replace `glab mr list` with `Get-PullRequest`
   - Update label filtering syntax
   - Add `Switch-PullRequest` alias

3. **`Copy-MergeRequest`**
   - Replace `glab mr view/create` with provider calls
   - Implement milestone workaround for GitHub
   - Add `Copy-PullRequest` alias

4. **`Move-IssueState`**
   - Replace `glab issue/mr update` with `Update-Issue`/`Update-PullRequest`
   - Consider GitHub Projects API for native state tracking
   - Keep label-based workflow for compatibility

5. **`New-MergeRequest`** (most complex)
   - Replace template path logic with `Get-TemplatePath`
   - Replace `glab mr create` with `New-PullRequest`
   - Implement all GitHub workarounds (copy labels, link issue)
   - Add `New-PullRequest` alias

### Phase 3: Documentation & Cleanup (Week 4)
1. Update AGENTS.md with provider usage examples
2. Update all function help text to mention dual support
3. Add CLI tool dependency checks (warn if `gh` or `glab` missing)
4. Remove old `glab`-specific comments

## Open Questions

### 1. Default Platform Behavior
**Question**: When remote URL doesn't match `github.com` or `gitlab.com`, what should be the default?

**Options:**
- **A**: Prompt user to select platform (store in config)
- **B**: Default to GitLab (current behavior)
- **C**: Fail with clear error message

**Recommendation**: Option A (prompt + cache)

### 2. Label Conventions
**Question**: Should `P::TO DO`, `P::IN DEV`, etc. labels be platform-agnostic or configurable?

**Options:**
- **A**: Keep as-is (works on both platforms via labels)
- **B**: Add GitHub Projects integration for native state tracking
- **C**: Make label prefixes configurable per-project

**Recommendation**: Option A for Phase 1, Option B for future enhancement

### 3. Template Naming
**Question**: Should GitHub templates mirror GitLab's `prospector.md` naming?

**Options:**
- **A**: Use GitHub default: `pull_request_template.md`
- **B**: Create named template: `prospector.md` in `.github/pull_request_templates/`
- **C**: Make template name configurable

**Recommendation**: Option B (parallel structure)

### 4. CLI Tool Requirements
**Question**: Should functions fail if `gh` (GitHub) or `glab` (GitLab) is not installed?

**Options:**
- **A**: Fail gracefully with installation instructions
- **B**: Attempt to use generic git commands as fallback
- **C**: Require both CLIs to be installed

**Recommendation**: Option A (clear error + docs)

### 5. Testing Strategy
**Question**: How to test dual-platform support without CI/CD?

**Options:**
- **A**: Manual testing in both GitHub and GitLab repos
- **B**: Add Pester tests with mocked CLI responses
- **C**: Create test repos on both platforms

**Recommendation**: Option C (real-world validation) + Option A

## Implementation Checklist

- [ ] Create `Common/GitProvider.ps1`
- [ ] Create `Common/GitProvider.GitLab.ps1`
- [ ] Create `Common/GitProvider.GitHub.ps1`
- [ ] Add platform detection tests
- [ ] Refactor `Open-MergeRequest`
- [ ] Refactor `Switch-MergeRequest`
- [ ] Refactor `Copy-MergeRequest`
- [ ] Refactor `Move-IssueState`
- [ ] Refactor `New-MergeRequest`
- [ ] Add `PullRequest` function aliases
- [ ] Add `npr`/`spr`/`cpr`/`opr` short aliases
- [ ] Update `RickScripts.psd1` exports
- [ ] Create `.github/pull_request_templates/prospector.md`
- [ ] Update AGENTS.md with provider examples
- [ ] Test in GitHub repository
- [ ] Test in GitLab repository
- [ ] Document breaking changes (if any)

## Success Criteria

- [ ] All five MR/PR functions work in both GitHub and GitLab repos
- [ ] Platform is auto-detected from git remote URL
- [ ] Functions use normalized data model (`.number`, `.sourceBranch`, etc.)
- [ ] Both `MergeRequest` and `PullRequest` aliases work
- [ ] Short aliases (`nmr`/`npr`, `smr`/`spr`) work
- [ ] Templates work on both platforms
- [ ] CLI tool detection provides helpful error messages
- [ ] No breaking changes to existing GitLab workflows
- [ ] Documentation updated in AGENTS.md

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking changes to existing GitLab users | High | Maintain backward compatibility via dual aliases |
| GitHub CLI (`gh`) missing features | Medium | Implement workarounds in provider layer |
| Performance regression from abstraction | Low | Provider adds minimal overhead (single function call) |
| Complexity increase | Medium | Clear separation of concerns, well-documented |
| Testing burden | Medium | Focus on real-world testing in both platforms |

## Future Enhancements

- **GitHub Projects API**: Native state tracking instead of label-based workflow
- **Azure DevOps support**: Extend provider pattern to third platform
- **Bitbucket support**: Additional provider implementation
- **Template sync**: CLI tool to sync templates between platforms
- **Config UI**: Interactive setup wizard for platform preferences

## References

- [GitHub CLI Manual](https://cli.github.com/manual/)
- [GitLab CLI Documentation](https://gitlab.com/gitlab-org/cli)
- [PowerShell Module Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/developer/module/writing-a-windows-powershell-module)
- [AGENTS.md](../../AGENTS.md) — RickScripts development guide
