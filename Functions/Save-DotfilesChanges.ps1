function Save-DotfilesChanges {
    [CmdletBinding()]
    param(
        [string]$DotfilesPath = "$HOME/code/dotfiles",
        [string]$CommitMessage,
        [switch]$Diff
    )

    if (-not (Test-Path -LiteralPath $DotfilesPath -PathType Container)) {
        Write-Error "Dotfiles path not found: $DotfilesPath"
        return
    }

    Push-Location -LiteralPath $DotfilesPath
    try {
        $gitRoot = (& git rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Not a git repository: $DotfilesPath"
            return
        }

        $snapshotScript = Join-Path $gitRoot 'Save-Dotfiles.ps1'
        if (-not (Test-Path -LiteralPath $snapshotScript -PathType Leaf)) {
            Write-Error "Dotfiles snapshot script not found: $snapshotScript"
            return
        }

        & $snapshotScript

        $status = @(& git status --short)
        if (-not $status) {
            Write-Host "No dotfiles changes."
            return
        }

        Write-Host "Dotfiles: $gitRoot"
        Write-Host ""
        Write-Host "Changed files:"
        $status | ForEach-Object { Write-Host "  $_" }

        Write-Host ""
        Write-Host "Summary:"
        $stat = @(& git diff --stat)
        $stagedStat = @(& git diff --cached --stat)
        $untracked = @(& git ls-files --others --exclude-standard)

        if ($stat) {
            $stat | ForEach-Object { Write-Host $_ }
        }
        if ($stagedStat) {
            Write-Host ""
            Write-Host "Staged:"
            $stagedStat | ForEach-Object { Write-Host $_ }
        }
        if ($untracked) {
            Write-Host ""
            Write-Host "Untracked:"
            $untracked | ForEach-Object { Write-Host "  $_" }
        }

        if ($Diff) {
            Write-Host ""
            Write-Host "Diff:"
            & git diff --patch

            $stagedDiff = @(& git diff --cached --patch)
            if ($stagedDiff) {
                Write-Host ""
                Write-Host "Staged diff:"
                $stagedDiff | ForEach-Object { Write-Host $_ }
            }
        }

        if (-not $CommitMessage) {
            $CommitMessage = 'chore: update dotfiles'
        }

        & git add -A
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git add failed."
            return
        }

        & git commit -m $CommitMessage
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git commit failed."
            return
        }

        & git push
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git push failed."
            return
        }
    }
    finally {
        Pop-Location
    }
}

Set-Alias sdf Save-DotfilesChanges
