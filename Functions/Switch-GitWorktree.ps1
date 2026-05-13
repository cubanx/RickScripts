function Switch-GitWorktree {
    [CmdletBinding()]
    param(
        [string]$WorktreeRoot = "~/.codex/worktrees"
    )

    $resolvedWorktreeRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorktreeRoot)
    $currentLocation = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Get-Location).Path)
    $currentLocation = [System.IO.Path]::GetFullPath($currentLocation).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $pathComparison = [System.StringComparison]::Ordinal
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        $pathComparison = [System.StringComparison]::OrdinalIgnoreCase
    }
    Write-Debug "Scanning Codex worktrees under '$resolvedWorktreeRoot'"

    if (-not (Test-Path -LiteralPath $resolvedWorktreeRoot -PathType Container)) {
        Write-Error "Codex worktree root not found: $resolvedWorktreeRoot"
        return
    }

    $detachedWorktreeCount = 0
    $entries = Get-ChildItem -LiteralPath $resolvedWorktreeRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $hexFolder = $_
            Write-Debug "Inspecting worktree folder '$($hexFolder.FullName)'"

            $repoFolder = Get-ChildItem -LiteralPath $hexFolder.FullName -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name |
                Select-Object -First 1

            if (-not $repoFolder) {
                Write-Debug "Skipping '$($hexFolder.FullName)' because it does not contain a project folder"
                return
            }

            $gitMetadataPath = Join-Path $repoFolder.FullName ".git"
            if (-not (Test-Path -LiteralPath $gitMetadataPath)) {
                Write-Debug "Skipping '$($repoFolder.FullName)' because '.git' was not found"
                return
            }

            $branchName = git -C $repoFolder.FullName branch --show-current 2>$null
            if (-not $branchName) {
                $detachedWorktreeCount++
                Write-Debug "Skipping '$($repoFolder.FullName)' because it is detached"
                return
            }

            [PSCustomObject]@{
                HexFolder   = $hexFolder.Name
                ProjectName = $repoFolder.Name
                Branch      = $branchName.Trim()
                Path        = $repoFolder.FullName
                Display     = $null
            }
        } |
        Where-Object { $_ }

    if ($detachedWorktreeCount -gt 0) {
        $detachedWorktreeSuffix = if ($detachedWorktreeCount -eq 1) { "" } else { "s" }
        Write-Output ("{0} detached Codex worktree{1} hidden. Run Remove-StaleCodexWorktree to review." -f $detachedWorktreeCount, $detachedWorktreeSuffix)
    }

    if (-not $entries) {
        Write-Output "No selectable Codex worktrees found in $resolvedWorktreeRoot"
        return
    }

    $entries = $entries | Where-Object {
        $entryPath = [System.IO.Path]::GetFullPath($_.Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $currentIsEntryPath = [string]::Equals($currentLocation, $entryPath, $pathComparison)
        $currentIsUnderEntryPath = $currentLocation.StartsWith(
            $entryPath + [System.IO.Path]::DirectorySeparatorChar,
            $pathComparison
        )

        -not ($currentIsEntryPath -or $currentIsUnderEntryPath)
    }

    if (-not $entries) {
        Write-Output "No other Codex worktrees found in $resolvedWorktreeRoot"
        return
    }

    $branchColumnWidth = ($entries | ForEach-Object { $_.Branch.Length } | Measure-Object -Maximum).Maximum
    $entries | ForEach-Object {
        $_.Display = "{0}  {1}" -f $_.Branch.PadRight($branchColumnWidth), $_.ProjectName
    }

    if ($PSBoundParameters.ContainsKey('Debug')) {
        Write-Host "Available Codex worktrees:"
        $entries | ForEach-Object { Write-Host ("{0} -> {1}" -f $_.Display, $_.Path) }
    }

    $selection = $entries.Display | fzf --prompt 'Pick a Codex worktree: '
    if (-not $selection) {
        Write-Debug "No worktree selected"
        return
    }

    $selectedEntry = $entries | Where-Object { $_.Display -eq $selection } | Select-Object -First 1
    if (-not $selectedEntry) {
        Write-Error "Unable to map selected worktree back to a path."
        return
    }

    Write-Debug "Pushing location to '$($selectedEntry.Path)'"
    Push-Location -LiteralPath $selectedEntry.Path
}

Set-Alias sgw Switch-GitWorktree
