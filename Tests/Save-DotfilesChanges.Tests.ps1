BeforeAll {
    . "$PSScriptRoot/../Functions/Save-DotfilesChanges.ps1"

    function Test-Path { return $true }
    function Push-Location {}
    function Pop-Location {}
    function Write-Host {}
    function Write-Error { param([string]$Message) throw $Message }
    function Read-Host { throw 'Save-DotfilesChanges must not prompt by default.' }

    function git {
        $command = $args -join ' '
        $script:Calls += $command
        $global:LASTEXITCODE = 0

        switch ($command) {
            'rev-parse --show-toplevel' { return $script:TestRoot }
            'status --short' {
                if (-not [System.IO.File]::Exists($script:SnapshotMarker)) {
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
}

Describe 'Save-DotfilesChanges' {
    BeforeEach {
        $script:Calls = @()
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "save-dotfiles-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        $script:SnapshotMarker = Join-Path $script:TestRoot 'snapshot-invoked'
        Set-Content -LiteralPath (Join-Path $script:TestRoot 'Save-Dotfiles.ps1') -Value "[System.IO.File]::WriteAllText('$script:SnapshotMarker', 'invoked')"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
    }

    It 'refreshes the snapshot and publishes without showing the full diff' {
        Save-DotfilesChanges -DotfilesPath $script:TestRoot

        [System.IO.File]::Exists($script:SnapshotMarker) | Should -BeTrue
        $script:Calls | Should -Contain 'add -A'
        $script:Calls | Should -Contain 'commit -m chore: update dotfiles'
        $script:Calls | Should -Contain 'push'
        $script:Calls | Should -Not -Contain 'diff --patch'
    }
}
