function Switch-GitWorktree {
    [CmdletBinding()]
    param(
        [string[]]$Roots = @("~/code"),
        [switch]$RefreshCache
    )

    $currentLocation = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Get-Location).Path)
    $currentLocation = [System.IO.Path]::GetFullPath($currentLocation).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $pathComparison = [System.StringComparison]::Ordinal
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        $pathComparison = [System.StringComparison]::OrdinalIgnoreCase
    }

    $allWorktrees = @(Get-GitWorktrees -Roots $Roots -RefreshCache:$RefreshCache)
    $hiddenWorktreeCount = @($allWorktrees | Where-Object { $_.IsBare -or $_.IsDetached }).Count
    $entries = $allWorktrees |
        Where-Object {
            if ($_.IsBare -or $_.IsDetached) {
                $false
                return
            }

            $worktreePath = [System.IO.Path]::GetFullPath($_.Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $repositoryRoot = [System.IO.Path]::GetFullPath($_.RepositoryRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            -not [string]::Equals($worktreePath, $repositoryRoot, $pathComparison)
        } |
        ForEach-Object {
            [PSCustomObject]@{
                RepositoryName = $_.RepositoryName
                Branch         = $_.Branch
                Path           = $_.Path
                Display        = $null
            }
        }

    if ($hiddenWorktreeCount -gt 0) {
        $hiddenWorktreeSuffix = if ($hiddenWorktreeCount -eq 1) { "" } else { "s" }
        Write-Output ("{0} bare or detached Git worktree{1} hidden." -f $hiddenWorktreeCount, $hiddenWorktreeSuffix)
    }

    if (-not $entries) {
        Write-Output "No selectable Git worktrees found."
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
        Write-Output "No other Git worktrees found."
        return
    }

    $branchColumnWidth = ($entries | ForEach-Object { $_.Branch.Length } | Measure-Object -Maximum).Maximum
    $repositoryColumnWidth = ($entries | ForEach-Object { $_.RepositoryName.Length } | Measure-Object -Maximum).Maximum
    $entries | ForEach-Object {
        $_.Display = "{0}  {1}  {2}" -f $_.Branch.PadRight($branchColumnWidth), $_.RepositoryName.PadRight($repositoryColumnWidth), $_.Path
    }

    if ($PSBoundParameters.ContainsKey('Debug')) {
        Write-Host "Available Git worktrees:"
        $entries | ForEach-Object { Write-Host ("{0} -> {1}" -f $_.Display, $_.Path) }
    }

    $selection = $entries.Display | fzf --prompt 'Pick a Git worktree: '
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
