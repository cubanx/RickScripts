$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Functions/Remove-LocalBranchesThatAreMerged.ps1"

$script:FzfInput = @()

function git {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Args
    )

    $command = $Args -join ' '

    switch -Regex ($command) {
        '^fetch --all --prune$' { return }
        '^remote show origin$' { return '  HEAD branch: main' }
        '^branch --show-current$' { return 'current' }
        '^branch --format=%\(refname:short\)$' { return @('main', 'current', 'risky', 'soft') }
        "^log -1 --format=%cI " { return '2026-06-25T12:00:00Z' }
        '^for-each-ref --format=%\(upstream:short\)\|%\(upstream:track\) ' { return 'origin/branch|' }
        '^rev-list --left-right --count main\.\.\.risky$' { return '0 1' }
        '^rev-list --left-right --count main\.\.\.soft$' { return '0 0' }
        '^branch --format=%\(refname:short\) --merged main$' { return @() }
        '^worktree add --quiet --detach ' { return }
        '^-C .+ merge --squash --no-commit risky$' { return }
        '^-C .+ merge --squash --no-commit soft$' { return }
        '^-C .+ status --porcelain$' { return ' M file.txt' }
        '^-C .+ reset --hard HEAD$' { return }
        '^worktree remove --force ' { return }
        '^rev-parse risky$' { return 'risky-sha' }
        '^rev-parse soft$' { return 'soft-sha' }
        '^cherry main risky$' { return '+ risky-sha unique work' }
        '^cherry main soft$' { return '- soft-sha already applied' }
        '^remote prune origin$' { return }
        default { throw "Unexpected git call: $command" }
    }
}

function gh {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Args
    )

    return '[]'
}

function fzf {
    process {
        $script:FzfInput += $_
    }
}

Remove-LocalBranchesThatAreMerged | Out-Null

if (-not ($script:FzfInput -match '^soft\s+candidate\s+-D\s+')) {
    throw 'Expected soft deletion candidate to be selectable.'
}

if ($script:FzfInput -match '^risky\s+') {
    throw 'Risky manual-review branch was selectable.'
}
