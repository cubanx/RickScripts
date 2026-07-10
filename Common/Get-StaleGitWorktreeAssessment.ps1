function Get-StaleGitWorktreeAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Worktree,

        [Parameter(Mandatory)]
        [object[]]$AllWorktrees
    )

    function Get-NormalizedPath {
        param(
            [string]$Path
        )

        return [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }

    function New-Assessment {
        param(
            [bool]$IsStale,
            [string]$Reason = "",
            [string]$OwnerPath = "",
            [string[]]$Refs = @(),
            [string]$Head = "",
            [string]$ShortHead = ""
        )

        [PSCustomObject]@{
            IsStale   = $IsStale
            Reason    = $Reason
            OwnerPath = $OwnerPath
            Refs      = @($Refs | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            Head      = $Head.Trim()
            ShortHead = $ShortHead.Trim()
        }
    }

    if (-not $Worktree.Path -or -not $Worktree.RepositoryRoot) {
        return New-Assessment -IsStale $false -Reason "Worktree path or repository root is missing."
    }

    if ($Worktree.IsBare) {
        return New-Assessment -IsStale $false -Reason "Worktree is bare."
    }

    $pathComparison = [System.StringComparison]::Ordinal
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        $pathComparison = [System.StringComparison]::OrdinalIgnoreCase
    }

    if (-not $Worktree.IsDetached) {
        return New-Assessment -IsStale $false -Reason "Worktree has a checked-out branch."
    }

    $status = git -C $Worktree.Path status --porcelain=v1 --untracked-files=all 2>$null
    if ($LASTEXITCODE -ne 0) {
        return New-Assessment -IsStale $false -Reason "Could not evaluate worktree cleanliness."
    }

    if ($status) {
        return New-Assessment -IsStale $false -Reason "Worktree has local changes."
    }

    $uniqueCommits = @(git -C $Worktree.Path log --oneline HEAD --not --branches --remotes --tags 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return New-Assessment -IsStale $false -Reason "Could not evaluate unique commit set."
    }

    if ($uniqueCommits) {
        return New-Assessment -IsStale $false -Reason "HEAD has commits not reachable from branches, remotes, or tags."
    }

    $containingRefs = @(git -C $Worktree.Path for-each-ref --contains HEAD --format='%(refname:short)' refs/heads refs/remotes refs/tags 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return New-Assessment -IsStale $false -Reason "Could not evaluate HEAD reachability."
    }

    $cleanRefs = @($containingRefs | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $cleanRefs) {
        return New-Assessment -IsStale $false -Reason "HEAD is not reachable from any branch, remote, or tag."
    }

    $worktreePath = Get-NormalizedPath -Path $Worktree.Path
    $repositoryRoot = Get-NormalizedPath -Path $Worktree.RepositoryRoot
    $ownerPath = @(
        $AllWorktrees |
            Where-Object {
                $thisPath = Get-NormalizedPath -Path $_.Path
                $otherRepositoryRoot = Get-NormalizedPath -Path $_.RepositoryRoot
                [string]::Equals($otherRepositoryRoot, $repositoryRoot, $pathComparison) -and
                -not [string]::Equals($thisPath, $worktreePath, $pathComparison) -and
                -not $_.IsBare
            } |
            ForEach-Object { $_.Path } |
            Select-Object -First 1
    )

    if (-not $ownerPath) {
        return New-Assessment -IsStale $false -Reason "No other worktree found for repository."
    }

    $head = git -C $Worktree.Path rev-parse HEAD 2>$null
    if (-not $head) {
        return New-Assessment -IsStale $false -Reason "Could not resolve HEAD hash."
    }

    $shortHead = git -C $Worktree.Path rev-parse --short HEAD 2>$null
    if (-not $shortHead) {
        return New-Assessment -IsStale $false -Reason "Could not resolve short HEAD hash."
    }

    return New-Assessment -IsStale $true -OwnerPath $ownerPath -Refs $cleanRefs -Head $head -ShortHead $shortHead
}
