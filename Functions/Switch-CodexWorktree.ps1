function Switch-CodexWorktree {
    [CmdletBinding()]
    param(
        [string]$WorktreeRoot = "~/.codex/worktrees"
    )

    $resolvedWorktreeRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorktreeRoot)
    Write-Debug "Scanning Codex worktrees under '$resolvedWorktreeRoot'"

    if (-not (Test-Path -LiteralPath $resolvedWorktreeRoot -PathType Container)) {
        Write-Error "Codex worktree root not found: $resolvedWorktreeRoot"
        return
    }

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
                $branchName = "(detached HEAD)"
            }

            [PSCustomObject]@{
                HexFolder   = $hexFolder.Name
                ProjectName = $repoFolder.Name
                Branch      = $branchName.Trim()
                Path        = $repoFolder.FullName
                Display     = "{0}: {1}" -f $repoFolder.Name, $branchName.Trim()
            }
        } |
        Where-Object { $_ }

    if (-not $entries) {
        Write-Output "No Codex worktrees found in $resolvedWorktreeRoot"
        return
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

Set-Alias scw Switch-CodexWorktree
