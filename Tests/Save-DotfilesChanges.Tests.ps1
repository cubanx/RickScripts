$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Functions/Save-DotfilesChanges.ps1"

$script:Calls = @()
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("save-dotfiles-{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$snapshotMarker = Join-Path $testRoot 'snapshot-invoked'
Set-Content -LiteralPath (Join-Path $testRoot 'Save-Dotfiles.ps1') -Value "[System.IO.File]::WriteAllText('$snapshotMarker', 'invoked')"

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
        'rev-parse --show-toplevel' { return $testRoot }
        'status --short' {
            if (-not [System.IO.File]::Exists($snapshotMarker)) {
                throw 'Snapshot must be refreshed before Git status is inspected.'
            }
            return ' M profile.ps1'
        }
        'diff --stat' { return ' profile.ps1 | 1 +' }
        'diff --cached --stat' { return }
        'ls-files --others --exclude-standard' { return }
        'add -A' { return }
        'commit -m chore: update dotfiles' { return }
        'push' { return }
        default { throw "Unexpected git call: $command" }
    }
}

try {
    Save-DotfilesChanges -DotfilesPath $testRoot
    $snapshotInvoked = [System.IO.File]::Exists($snapshotMarker)
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}

if (-not $snapshotInvoked) { throw 'Expected the tracked snapshot to be refreshed before Git inspection.' }

foreach ($expected in @('add -A', 'commit -m chore: update dotfiles', 'push')) {
    if ($script:Calls -notcontains $expected) { throw "Expected git $expected." }
}

if ($script:Calls -contains 'diff --patch') { throw 'Default invocation must not show the full diff.' }
