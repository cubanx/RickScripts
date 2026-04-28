function Publish-Config {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $configRoot = Join-Path $moduleRoot 'Config'
    $whatIf = $WhatIfPreference

    $configMappings = @(
        @{
            Source      = Join-Path $configRoot 'PowerShell/Microsoft.PowerShell_profile.ps1'
            Destination = "$HOME/.config/powershell"
        },
        @{
            Source      = Join-Path $configRoot 'PowerShell/oh-my-posh-pr.ps1'
            Destination = "$HOME/.config/powershell"
        },
        @{
            Source      = Join-Path $configRoot 'PowerShell/Profile.d'
            Destination = "$HOME/.config/powershell/Profile.d"
        },
        @{
            Source      = Join-Path $configRoot 'PowerShell/powerlevel10k_classic-custom.omp.json'
            Destination = "$HOME"
        },
        @{
            Source      = Join-Path $configRoot 'Claude'
            Destination = "$HOME/.claude"
        },
        @{
            Source      = Join-Path $configRoot 'Codex'
            Destination = "$HOME/.codex"
        }
    )

    foreach ($mapping in $configMappings) {
        $source = $mapping.Source
        $destination = $mapping.Destination

        if ($source -match '[\*\?]') {
            $matchList = Get-ChildItem -Path $source -File -ErrorAction SilentlyContinue
            if (-not $matchList) {
                throw "No matches for source pattern: $source"
            }

            if (-not (Test-Path $destination)) {
                New-Item -ItemType Directory -Force -Path $destination | Out-Null
            }

            foreach ($item in $matchList) {
                $targetPath = Join-Path $destination $item.Name
                if ($whatIf) {
                    Write-Output "WHATIF: Copy $($item.FullName) -> $targetPath"
                }
                if ($PSCmdlet.ShouldProcess($targetPath, "Copy")) {
                    Copy-Item -Path $item.FullName -Destination $targetPath -Force
                }
            }
            continue
        }

        if (Test-Path $source -PathType Container) {
            if (-not (Test-Path $destination)) {
                New-Item -ItemType Directory -Force -Path $destination | Out-Null
            }

            $files = Get-ChildItem -Path $source -File -Recurse -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $relative = $file.FullName.Substring($source.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
                $targetPath = Join-Path $destination $relative
                $targetDir = Split-Path -Parent $targetPath
                if ($targetDir -and -not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
                }
                if ($whatIf) {
                    Write-Output "WHATIF: Copy $($file.FullName) -> $targetPath"
                }
                if ($PSCmdlet.ShouldProcess($targetPath, "Copy")) {
                    Copy-Item -Path $file.FullName -Destination $targetPath -Force
                }
            }
            continue
        }

        if (-not (Test-Path $source -PathType Leaf)) {
            throw "Source config not found: $source"
        }

        if (-not (Test-Path $destination)) {
            New-Item -ItemType Directory -Force -Path $destination | Out-Null
        }

        $targetPath = Join-Path $destination (Split-Path -Leaf $source)
        if ($whatIf) {
            Write-Output "WHATIF: Copy $source -> $targetPath"
        }
        if ($PSCmdlet.ShouldProcess($targetPath, "Copy")) {
            Copy-Item -Path $source -Destination $targetPath -Force
        }
    }
}

