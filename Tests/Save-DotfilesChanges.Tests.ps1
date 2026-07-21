$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Functions/Save-DotfilesChanges.ps1"

$script:Calls = @()

function Test-Path { return $true }
function Push-Location { }
function Pop-Location { }
function Write-Host { }
function Write-Error { param([string]$Message) throw $Message }
function Read-Host { throw 'Save-DotfilesChanges must not prompt by default.' }

function git {
    $command = $args -join ' '
    $script:Calls += $command
    $global:LASTEXITCODE = 0

    switch ($command) {
        'rev-parse --show-toplevel' { return '/tmp/dotfiles' }
        'status --short' { return ' M profile.ps1' }
        'diff --stat' { return ' profile.ps1 | 1 +' }
        'diff --cached --stat' { return }
        'ls-files --others --exclude-standard' { return }
        'add -A' { return }
        'commit -m chore: update dotfiles' { return }
        'push' { return }
        default { throw "Unexpected git call: $command" }
    }
}

Save-DotfilesChanges

foreach ($expected in @('add -A', 'commit -m chore: update dotfiles', 'push')) {
    if ($script:Calls -notcontains $expected) { throw "Expected git $expected." }
}

if ($script:Calls -contains 'diff --patch') { throw 'Default invocation must not show the full diff.' }
