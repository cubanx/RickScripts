# AGENTS.md

This file provides comprehensive guidance for AI agents (Claude Code, GitHub Copilot, etc.) working with the RickScripts PowerShell module.

## Project Overview

**RickScripts** is a personal PowerShell module containing development utilities and Git workflow helpers. It's designed as a portable, dependency-light toolkit for daily developer tasks, with heavy emphasis on interactive CLI workflows powered by `fzf`.

### Core Philosophy
- **No build process** — simple PowerShell module with dot-sourcing
- **Interactive-first** — most functions use `fzf` for selection UI
- **CLI composition** — wraps existing tools (`glab`, `gh`, `jq`, `fd`, `op`) rather than reimplementing
- **Platform-agnostic goal** — currently GitLab-focused, but moving toward dual GitLab/GitHub support

## Module Structure

```
RickScripts/
├── RickScripts.psd1          # Module manifest (exports, aliases, metadata)
├── RickScripts.psm1          # Module loader (dot-sources Common/ + Functions/)
├── Common/                   # Shared utilities
│   ├── Config.ps1            # Project-specific config storage (~/.RickScripts/config.json)
│   ├── DateParser.ps1        # Natural language date parsing
│   └── GoogleCalendarAuth.ps1 # OAuth flow for calendar API
├── Functions/                # All exported functions (one per file)
│   ├── Env/                  # 1Password environment variable helpers
│   └── ClaudeAgents/         # Claude SDK agent generators
├── Config/                   # PowerShell profile and Oh My Posh config
├── Bash/                     # (Unknown — check if used)
└── .gitlab/                  # MR templates (will add .github/ for PR templates)
```

### Loading Mechanism
`RickScripts.psm1` uses this pattern:
1. Dot-source all `.ps1` files in `Common/` (order-independent utilities)
2. Dot-source all `.ps1` files in `Functions/` recursively
3. `Export-ModuleMember -Function * -Alias *`

**Implication:** Every function file must define its own aliases via `Set-Alias` — the manifest only lists them for documentation.

## Function Conventions

### File Structure
Each function lives in `Functions/FunctionName.ps1` with this pattern:

```powershell
function Verb-Noun {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$RequiredParam,

        [Parameter()]
        [switch]$OptionalFlag
    )

    # Implementation
}

# Define aliases in the same file
Set-Alias -Name shortcut -Value Verb-Noun
```

### Naming Rules
- **Functions:** Follow PowerShell `Verb-Noun` convention (`Switch-Branch`, `New-MergeRequest`)
- **Aliases:** Short lowercase abbreviations (2-4 chars: `sb`, `nmr`, `smr`)
- **Internal helpers:** Prefix with `_` if not meant to be exported (though current code exports all)

### Alias Strategy
- Each function should have a short alias for muscle memory
- GitLab MR functions are aliased with both `MergeRequest` and `PullRequest` variants
- Short aliases get both `m` (MR) and `p` (PR) versions: `nmr`/`npr`, `smr`/`spr`

## Key Dependencies

### Required CLI Tools
- **fzf** — Interactive fuzzy finder (core dependency for most functions)
- **glab** — GitLab CLI (currently required for MR/issue functions)
- **gh** — GitHub CLI (planned for dual-platform support)
- **jq** — JSON parsing and manipulation
- **fd** — Fast file finder (alternative to `find`)
- **pnpm** — Node package manager (for `Clear-NodeModules`)
- **op** — 1Password CLI (for Env functions)

### Optional Integrations
- **Google Calendar API** — OAuth-based calendar event creation
- **VSCode** — Used by `Open-ProjectFolder` to launch editors

## Architecture Patterns

### Config Storage
`Common/Config.ps1` provides persistent JSON config at `~/.RickScripts/config.json`:

```powershell
Get-ConfigValue -Section "projectForPath" -Key "MyProject"
Set-ConfigValue -Section "projectForPath" -Key "MyProject" -Value @{labels=@("bug","feature")}
```

**Schema:**
```json
{
  "projectForPath": {
    "FolderName": {
      "labels": ["label1", "label2"]
    }
  }
}
```

### Git Platform Detection
Currently GitLab-only. Planned approach for dual support:
1. Read `git remote get-url origin`
2. Parse hostname (`github.com` vs `gitlab.com`)
3. Route to appropriate CLI (`gh` vs `glab`)
4. Normalize output field names (`.iid` → `.number`, `.source_branch` → `.headRefName`)

### Template Processing
`New-MergeRequest` reads templates from:
- **GitLab:** `.gitlab/merge_request_templates/prospector.md`
- **GitHub (planned):** `.github/pull_request_template.md`

Template replacement tokens:
- `[issue_number_here]` — replaced with issue IID
- `<issue-number>` — replaced with issue IID
- Mobile/environment sections — stripped via regex

## Function Categories & Implementation Notes

### Git Workflow Functions

#### `Switch-Branch` (alias: `sb`)
- Lists local branches via `git branch`
- Pipes to `fzf` for selection
- Checks out selected branch with `git checkout`
- **No platform dependency** — pure git

#### `Switch-MergeRequest` (aliases: `smr`, `spr`)
- **GitLab:** `glab mr list --label "X" | jq | fzf`
- **GitHub (planned):** `gh pr list --search "label:X" --json ... | jq | fzf`
- Uses config from `Switch-MergeRequest.Labels.ps1` to filter by project labels
- Checks out selected MR/PR branch

#### `New-MergeRequest` (aliases: `nmr`, `npr`)
- Most complex function — template processing + GitLab API
- **GitLab:** `glab mr create --related-issue --copy-issue-labels --draft --remove-source-branch`
- **GitHub (planned):** `gh pr create --draft` (missing: related issue, copy labels, remove branch flags)
- Auto-populates issue references from linked issue
- Removes mobile-specific template sections

#### `Copy-MergeRequest` (aliases: `cmr`, `cpr`)
- Duplicates MR/PR with all metadata (labels, assignees, reviewers, milestone)
- **Challenge:** GitHub's `gh pr create` doesn't support `--milestone` flag

#### `Move-IssueState` (alias: `mis`)
- Custom workflow state machine using labels: `P::TO DO`, `P::IN DEV`, `P::AWAITING REVIEW`, `P::DONE`
- Updates both issue and related MR with state labels
- **GitHub consideration:** Projects API offers native state management

#### `Get-GitStash` (alias: `ggs`)
- Lists stashes via `git stash list`
- Interactive selection with `fzf`
- Applies selected stash
- **No platform dependency** — pure git

### Development Utilities

#### `Open-ProjectFolder` (alias: `opf`)
- Uses `fd` to find directories
- `fzf` selection
- Opens in VSCode via `code <path>`

#### `Clear-NodeModules` (alias: `cnm`)
- Removes `node_modules` and lock files
- Reinstalls via `pnpm install`

#### `Invoke-ValidationScript` (alias: `ivs`)
- World50-specific validation runner
- Lists scripts via `fd`, selects with `fzf`, executes

### Environment & Secrets Management

#### `Add-EnvTo1Password` (alias: `ae1p`)
- Parses `.env` files
- Stores in 1Password with hierarchical tags
- Uses `op` CLI

#### `Get-EnvFrom1Password` (alias: `ge1p`)
- Retrieves env vars from 1Password by tag
- Outputs in shell export format

### Productivity Tools

#### `New-CalendarEvent`
- Parses natural language dates via `DateParser.ps1`
- Creates events via Google Calendar API
- OAuth flow via `GoogleCalendarAuth.ps1`

## Git Platform Abstraction (In Progress)

### Current State
All MR/issue functions use `glab` directly. This creates hard coupling to GitLab.

### Planned Architecture
**Provider pattern** with auto-detection:

```
Common/
  GitProvider.ps1          # Platform detection + routing
  GitProvider.GitHub.ps1   # GitHub implementations
  GitProvider.GitLab.ps1   # GitLab implementations
```

**GitProvider.ps1** exposes:
- `Get-GitPlatform` → returns `"github"` or `"gitlab"` based on remote URL
- `Get-PullRequest -Number 123` → calls `gh pr view` or `glab mr view`, normalizes output
- `New-PullRequest -Title "..." -Body "..." -Draft` → maps flags to platform equivalents
- `Get-Issue -Number 456` → normalized issue retrieval
- `Update-Issue -Number 456 -AddLabel "foo"` → label operations
- `Checkout-PullRequest -Number 123` → checkout MR/PR branch

**Normalization layer:**
| GitLab | GitHub | Normalized Field |
|--------|--------|------------------|
| `.iid` | `.number` | `.number` |
| `.source_branch` | `.headRefName` | `.sourceBranch` |
| `.target_branch` | `.baseRefName` | `.targetBranch` |
| `.web_url` | `.url` | `.url` |

### Missing GitHub Features
These GitLab flags have no direct `gh` equivalent:
- `--related-issue` → workaround: parse from body text
- `--copy-issue-labels` → workaround: extra API call to read issue, then `--add-label`
- `--remove-source-branch` → workaround: repo-level setting
- `--squash` on create → GitHub sets this at merge time
- `--milestone` on `gh pr create` → workaround: use `gh api` after creation

## Testing & Validation

**Current state:** No formal tests.

**Manual testing approach:**
1. Load function: `. ./Functions/FunctionName.ps1`
2. Call with `-Verbose` to see debug output
3. Test against real repos (GitLab and GitHub)

**Validation checklist for new code:**
- [ ] Function follows `Verb-Noun` naming
- [ ] Aliases defined with `Set-Alias` in same file
- [ ] Added to `FunctionsToExport` in `RickScripts.psd1`
- [ ] Aliases added to `AliasesToExport` in `RickScripts.psd1`
- [ ] Uses provider layer instead of direct `glab`/`gh` calls
- [ ] Handles errors gracefully (check for CLI tool availability)
- [ ] Works on both GitHub and GitLab remotes

## Code Style Guidelines

### PowerShell Conventions
- **Indentation:** Tabs (existing code uses tabs)
- **Braces:** Opening brace on same line
- **Quotes:** Double quotes for strings, single for literals
- **CmdletBinding:** Use `[CmdletBinding()]` on all functions
- **Parameters:** Use `[Parameter()]` attributes for validation

### Error Handling
Prefer `ErrorAction SilentlyContinue` with explicit checks:
```powershell
$result = SomeCommand -ErrorAction SilentlyContinue
if (-not $result) {
    Write-Error "Command failed"
    return
}
```

### Dependency Checks
Always verify CLI tools before use:
```powershell
if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
    Write-Error "fzf is required but not installed"
    return
}
```

## Common Pitfalls

### JSON Parsing
GitLab and GitHub return different JSON structures. Always normalize:
```powershell
# Bad
$mr = glab mr view 123 --output json | ConvertFrom-Json
$branch = $mr.source_branch

# Good
$pr = Get-PullRequest -Number 123  # Uses provider layer
$branch = $pr.sourceBranch
```

### Label Syntax
GitLab uses `--label "foo"`, GitHub uses `--search "label:foo"`:
```powershell
# GitLab
glab mr list --label "bug"

# GitHub
gh pr list --search "label:bug" --json number,title
```

### Remote URL Parsing
Different remote URL formats exist:
- HTTPS: `https://github.com/user/repo.git`
- SSH: `git@github.com:user/repo.git`
- GitLab: `https://gitlab.com/user/repo.git`, `git@gitlab.com:user/repo.git`

Always handle both formats when detecting platform.

## Development Workflow

### Adding a New Function
1. Create `Functions/NewFunction.ps1`
2. Implement with `[CmdletBinding()]`
3. Add alias with `Set-Alias`
4. Update `RickScripts.psd1`:
   - Add to `FunctionsToExport`
   - Add alias to `AliasesToExport`
5. Test via `. ./Functions/NewFunction.ps1`
6. Import full module: `Import-Module ./RickScripts.psd1 -Force`

### Modifying Existing Functions
1. Read the file first to understand current implementation
2. Preserve existing aliases and behavior
3. Test both GitLab and GitHub remotes if touching MR/PR functions
4. Update this documentation if changing architecture

### Adding Platform Support
When adding GitHub support to a GitLab-only function:
1. Refactor to use `GitProvider` layer instead of direct `glab` calls
2. Add `PullRequest` alias variant
3. Add `p` short alias (e.g., `npr` for `nmr`)
4. Test against GitHub remote
5. Update function documentation

## Release Process

**Current:** No formal releases — direct git usage.

**Installation:** Users clone repo and add to `$env:PSModulePath` or use `Import-Module`.

## Useful References

- [PowerShell Approved Verbs](https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)
- [GitHub CLI (`gh`) Manual](https://cli.github.com/manual/)
- [GitLab CLI (`glab`) Docs](https://gitlab.com/gitlab-org/cli)
- [fzf Usage](https://github.com/junegunn/fzf)

## Questions for Humans

When working on this codebase, consider asking the maintainer about:
- **Preferred default platform:** Should functions default to GitLab or auto-detect?
- **Label conventions:** Are the `P::*` labels mandatory or project-specific?
- **Template locations:** Should GitHub templates mirror GitLab's `prospector.md` naming?
- **Alias preferences:** Any objection to `npr`/`spr`/`cpr` short aliases?
- **Error verbosity:** Should provider layer fail silently or warn loudly when CLI tools are missing?
