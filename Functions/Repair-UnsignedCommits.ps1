function Repair-UnsignedCommits {
    [CmdletBinding()]
    param(
        [switch]$Push,
        [switch]$DryRun
    )

    function Invoke-GitCommand {
        param(
            [Parameter(Mandatory = $true)]
            [string[]]$Arguments,
            [switch]$AllowFailure
        )

        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE

        if (-not $AllowFailure -and $exitCode -ne 0) {
            $message = if ($output) { ($output | Out-String).Trim() } else { "git $($Arguments -join ' ') failed." }
            throw $message
        }

        return [PSCustomObject]@{
            Output   = $output
            ExitCode = $exitCode
        }
    }

    function Test-GitPath {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        $gitDir = (Invoke-GitCommand -Arguments @('rev-parse', '--git-dir')).Output | Select-Object -First 1
        if (-not $gitDir) {
            return $false
        }

        return Test-Path (Join-Path $gitDir $Path)
    }

    function Get-SigningConfiguration {
        $gpgFormat = (Invoke-GitCommand -Arguments @('config', '--get', 'gpg.format') -AllowFailure).Output | Select-Object -First 1
        $signingKey = (Invoke-GitCommand -Arguments @('config', '--get', 'user.signingkey') -AllowFailure).Output | Select-Object -First 1
        $defaultSshKeyCommand = (Invoke-GitCommand -Arguments @('config', '--get', 'gpg.ssh.defaultKeyCommand') -AllowFailure).Output | Select-Object -First 1
        $commitGpgSign = (Invoke-GitCommand -Arguments @('config', '--bool', '--get', 'commit.gpgsign') -AllowFailure).Output | Select-Object -First 1

        $hasSigningConfig = $false

        if ($signingKey) {
            $hasSigningConfig = $true
        }
        elseif ($gpgFormat -eq 'ssh' -and $defaultSshKeyCommand) {
            $hasSigningConfig = $true
        }
        elseif ($commitGpgSign -eq 'true') {
            $hasSigningConfig = $true
        }

        return [PSCustomObject]@{
            HasSigningConfig     = $hasSigningConfig
            GpgFormat            = $gpgFormat
            SigningKey           = $signingKey
            DefaultSshKeyCommand = $defaultSshKeyCommand
            CommitGpgSign        = $commitGpgSign
        }
    }

    # Refuse to do anything unless we are on a normal branch inside a git worktree.
    $insideWorkTree = Invoke-GitCommand -Arguments @('rev-parse', '--is-inside-work-tree') -AllowFailure
    if ($insideWorkTree.ExitCode -ne 0) {
        Write-Error "Not in a git repository."
        return
    }

    $branchName = (Invoke-GitCommand -Arguments @('branch', '--show-current')).Output | Select-Object -First 1
    if (-not $branchName) {
        Write-Error "HEAD is detached. Check out a branch before running Repair-UnsignedCommits."
        return
    }

    $upstreamLookup = Invoke-GitCommand -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}') -AllowFailure
    $upstreamRef = $upstreamLookup.Output | Select-Object -First 1
    if ($upstreamLookup.ExitCode -ne 0 -or -not $upstreamRef) {
        Write-Error "Current branch '$branchName' does not have an upstream branch."
        return
    }

    # History rewrites are safest from a clean working tree.
    $statusOutput = (Invoke-GitCommand -Arguments @('status', '--porcelain')).Output
    if ($statusOutput) {
        Write-Error "Worktree is dirty. Commit, stash, or discard changes before rewriting history."
        return
    }

    # Avoid colliding with any in-progress history operation.
    if (
        (Test-GitPath -Path 'rebase-merge') -or
        (Test-GitPath -Path 'rebase-apply') -or
        (Test-GitPath -Path 'MERGE_HEAD')
    ) {
        Write-Error "A rebase or merge is already in progress. Finish or abort it before running Repair-UnsignedCommits."
        return
    }

    $signingConfiguration = Get-SigningConfiguration
    if (-not $signingConfiguration.HasSigningConfig) {
        Write-Error "Git signing is not configured. Configure your existing signing setup before rewriting commits."
        return
    }

    # Only inspect commits that exist on the current branch and not on its upstream.
    $aheadCommits = @()
    $aheadLines = (Invoke-GitCommand -Arguments @('log', '--reverse', '--format=%H%x09%G?%x09%P%x09%s', "$upstreamRef..HEAD")).Output

    foreach ($line in $aheadLines) {
        if (-not $line) {
            continue
        }

        $parts = $line -split "`t", 4
        if ($parts.Count -lt 4) {
            continue
        }

        $parents = @()
        if ($parts[2]) {
            $parents = $parts[2] -split ' ' | Where-Object { $_ }
        }

        $aheadCommits += [PSCustomObject]@{
            Sha      = $parts[0]
            Sigil    = $parts[1]
            Parents  = $parents
            Subject  = $parts[3]
            IsMerge  = $parents.Count -gt 1
            Unsigned = $parts[1] -eq 'N'
        }
    }

    $unsignedCommits = $aheadCommits | Where-Object { $_.Unsigned }

    if (-not $aheadCommits) {
        Write-Output "Current branch '$branchName' has no commits ahead of '$upstreamRef'. Nothing to rewrite."
        return
    }

    if (-not $unsignedCommits) {
        Write-Output "No unsigned commits found ahead of '$upstreamRef'."
        Write-Output ""
        Write-Output "Signed status summary:"
        (Invoke-GitCommand -Arguments @('log', '--format=%h %G? %s', "$upstreamRef..HEAD")).Output | Write-Output
        return
    }

    # Rebase from the current merge-base back onto the same merge-base so we preserve
    # the branch's current content while rewriting commit objects and retaining merges.
    $mergeBase = (Invoke-GitCommand -Arguments @('merge-base', 'HEAD', $upstreamRef)).Output | Select-Object -First 1
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupRef = "backup/$branchName-before-resign-$timestamp"

    Write-Output "Branch: $branchName"
    Write-Output "Upstream: $upstreamRef"
    Write-Output "Ahead commits: $($aheadCommits.Count)"
    Write-Output "Unsigned commits: $($unsignedCommits.Count)"
    Write-Output ""
    Write-Output "Unsigned commits to re-sign:"
    foreach ($commit in $unsignedCommits) {
        $commitType = if ($commit.IsMerge) { "merge" } else { "commit" }
        Write-Output "  $($commit.Sha.Substring(0, 8)) [$commitType] $($commit.Subject)"
    }
    Write-Output ""
    Write-Output "Backup branch: $backupRef"

    if ($DryRun) {
        Write-Output "Dry run only. No history was rewritten."
        if ($Push) {
            Write-Output "Dry run note: would push with --force-with-lease after a successful rewrite."
        }
        return
    }

    # git rebase --exec expects a shell command, so we write a tiny temporary helper that
    # only amends commits whose signature status is "N" (no signature).
    $tempScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("fix-unsigned-commits-{0}.sh" -f [System.Guid]::NewGuid().ToString("N"))
    $tempScriptContent = @'
signature_status=$(git show -s --format=%G? HEAD)

if [ "$signature_status" = "N" ]; then
  echo "Re-signing $(git rev-parse --short HEAD)"
  git commit --amend --no-edit -S
fi
'@

    try {
        Set-Content -Path $tempScriptPath -Value $tempScriptContent -NoNewline
        Invoke-GitCommand -Arguments @('branch', $backupRef, 'HEAD') | Out-Null
        Write-Output "Created backup branch '$backupRef'."

        $originalGitSequenceEditor = $env:GIT_SEQUENCE_EDITOR
        $env:GIT_SEQUENCE_EDITOR = ':'
        $execCommand = "sh '$tempScriptPath'"

        try {
            Invoke-GitCommand -Arguments @('rebase', '--rebase-merges', '--onto', $mergeBase, $mergeBase, '--exec', $execCommand)
        }
        finally {
            $env:GIT_SEQUENCE_EDITOR = $originalGitSequenceEditor
        }

        Write-Output ""
        Write-Output "Re-sign complete. Signed status summary:"
        (Invoke-GitCommand -Arguments @('log', '--format=%h %G? %s', "$upstreamRef..HEAD")).Output | Write-Output

        if ($Push) {
            Write-Output ""
            Write-Output "Pushing rewritten history with --force-with-lease..."
            $pushResult = Invoke-GitCommand -Arguments @('push', '--force-with-lease')
            if ($pushResult.Output) {
                $pushResult.Output | Write-Output
            }
        }
    }
    catch {
        Write-Error @(
            $_.Exception.Message
            "Backup branch '$backupRef' points to the pre-rewrite history."
            "If a rebase is still in progress, inspect the repo and use 'git rebase --abort' or reset back to the backup branch if needed."
        ) -join [Environment]::NewLine
    }
    finally {
        if (Test-Path $tempScriptPath) {
            Remove-Item $tempScriptPath -Force
        }
    }
}
