function Edit-Config {
    [CmdletBinding()]
    param(
        [switch]$SkipFzf,
        [string]$Editor = 'code'
    )

    if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
        Write-Error "Required dependency 'rg' was not found in PATH."
        return
    }

    if (-not $SkipFzf) {
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            Write-Error "Required dependency 'fzf' was not found in PATH."
            return
        }

        if (-not (Get-Command $Editor -ErrorAction SilentlyContinue)) {
            Write-Error "Editor command '$Editor' was not found in PATH."
            return
        }
    }

    $roots = @(
        "$HOME/OneDrive/powershell/profile.ps1",
        "$HOME/OneDrive/powershell/profile.macos.ps1",
        "$HOME/OneDrive/powershell/profile.windows.ps1",
        "$HOME/.config/powershell/Microsoft.PowerShell_profile.ps1",
        "$HOME/OneDrive/.mytheme.omp.json",
        "$HOME/.ssh/config",
        "$HOME/.gitconfig",
        "$HOME/.zshrc",
        "$HOME/.zprofile",
        "$HOME/.config",
        "$HOME/.claude",
        "$HOME/.codex",
        "$HOME/.code",
        "$HOME/.ssh",
        "$HOME/OneDrive/powershell"
    ) |
    Where-Object { Test-Path -LiteralPath $_ } |
    Sort-Object -Unique

    $allowedExtensions = @(
        '.json',
        '.jsonc',
        '.yaml',
        '.yml',
        '.toml',
        '.ini',
        '.conf',
        '.config',
        '.cfg',
        '.md',
        '.ps1',
        '.sh',
        '.zsh',
        '.xml',
        '.rules',
        '.txt'
    )

    $allowedFileNames = @(
        'config',
        '.gitconfig',
        '.zshrc',
        '.zprofile',
        '.bashrc',
        '.bash_profile',
        '.npmrc',
        '.editorconfig',
        'known_hosts',
        'authorized_keys'
    )

    $excludedFileNames = @(
        '.codex-global-state.json',
        'auth.json',
        'models_cache.json',
        'version.json'
    )

    $excludedDirectories = @(
        '.git',
        '.hg',
        '.svn',
        '.DS_Store',
        '.cache',
        'cache',
        'Caches',
        'node_modules',
        'dist',
        'build',
        'coverage',
        'debug',
        'tmp',
        'temp',
        'log',
        'logs',
        'plugins',
        'History',
        'sessions',
        'shell_snapshots',
        'state',
        'sqlite',
        'tmpfiles',
        'vendor_imports',
        'skills',
        'memories',
        'log_archive'
    )

    $candidates = foreach ($root in $roots) {
        $item = Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
        if (-not $item) {
            continue
        }

        if ($item.PSIsContainer) {
            Push-Location -LiteralPath $item.FullName
            try {
                $rgArgs = @('--files', '--hidden', '--follow', '--no-ignore')
                foreach ($directory in $excludedDirectories) {
                    $rgArgs += @('-g', "!$directory/**")
                }
                $rgArgs += @('--', '.')

                & rg @rgArgs |
                    ForEach-Object {
                        $candidate = $_.Trim()
                        if ($candidate) {
                            $relative = $candidate -replace '^[.][/\\]', ''
                            Join-Path $item.FullName $relative
                        }
                    }
            }
            finally {
                Pop-Location
            }
        }
        else {
            $item.FullName
        }
    }

    $files = $candidates |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        ForEach-Object { (Get-Item -LiteralPath $_ -Force).FullName } |
        Where-Object {
            $leaf = Split-Path -Leaf $_
            $ext = [System.IO.Path]::GetExtension($leaf).ToLowerInvariant()
            if ($excludedFileNames -contains $leaf) {
                return $false
            }
            ($allowedExtensions -contains $ext) -or
            ($allowedFileNames -contains $leaf) -or
            ($leaf -like '.env*')
        } |
        Sort-Object -Unique

    if ($SkipFzf) {
        $files
        return
    }

    $pick = $files | fzf --prompt 'config file> ' --height 60% --reverse

    if ($pick) {
        & $Editor $pick
    }
}

Set-Alias ec Edit-Config
