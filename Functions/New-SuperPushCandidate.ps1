# Preparation never accesses App credentials or pushes. Publication stays in Invoke-SuperPush.
function Test-SuperPushCandidateDocumentationOnly {
    param([Parameter(Mandatory)][psobject]$State)
    if (-not (Test-SuperPushDocumentationOnly $State)) { return $false }
    # A net docs diff can hide code added and reverted in intermediate commits.
    # Classify every commit that publication would introduce, not just the tip.
    $commits = (Invoke-GitCommand -Arguments @('-C', $State.Root, 'rev-list', '--reverse',
        "$($State.OldSha)..$($State.NewSha)")).Output
    if (-not $commits) { return $false }
    foreach ($commit in $commits) {
        $parents = ((Invoke-GitCommand -Arguments @('-C', $State.Root, 'rev-list', '--parents', '-n', '1', $commit)).Output[-1]).Split(' ')
        if ($parents.Count -ne 2) { return $false }
        $change = [pscustomobject]@{ Root = $State.Root; OldSha = $parents[1]; NewSha = $commit }
        if (-not (Test-SuperPushDocumentationOnly $change)) { return $false }
    }
    $true
}

function Get-SuperPushCandidateReceipt {
    param([Parameter(Mandatory)][psobject]$State)
    $gitDirectory = (Invoke-GitCommand -Arguments @('-C', $State.Root, 'rev-parse', '--absolute-git-dir')).Output[-1]
    $path = Join-Path $gitDirectory 'super-push-candidate.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { $receipt = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Super Push candidate validation receipt is malformed.' }
    foreach ($field in 'Root', 'Origin', 'Repository', 'OldSha', 'NewSha') {
        if ($receipt.$field -cne $State.$field) { throw "Super Push candidate receipt changed at $field." }
    }
    if ($receipt.ValidationPassed -ne $true -and -not (Test-SuperPushCandidateDocumentationOnly $State)) {
        throw 'Super Push non-docs candidate requires passing validation.'
    }
    $receipt
}

function Invoke-SuperPushCandidateValidation {
    param([string[]]$Command, [Parameter(Mandatory)][psobject]$State)
    if (-not $Command -or [string]::IsNullOrWhiteSpace($Command[0])) {
        throw 'Super Push non-docs preparation requires an explicit validation command.'
    }
    $executable = Get-Command $Command[0] -CommandType Application -ErrorAction Stop
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $executable.Source
    $start.WorkingDirectory = $State.Root
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @($Command | Select-Object -Skip 1)) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $process.Start() | Out-Null
        # Drain both streams to avoid deadlock. Do not display validator output:
        # a caller's command can emit credentials that Git sanitization cannot know.
        $stdout = $process.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
        $stderr = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        if (-not $process.WaitForExit(600000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'Super Push candidate validation timed out after ten minutes.'
        }
        if (-not [Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout, $stderr)).Wait(10000)) {
            throw 'Super Push candidate validation left output streams open; validation is not confirmed.'
        }
        if ($process.ExitCode -ne 0) { throw "Super Push candidate validation failed (exit $($process.ExitCode)); output omitted." }
    }
    finally { $process.Dispose() }
    Assert-SuperPushCandidate $State
}

function Assert-SuperPushCandidate {
    param([Parameter(Mandatory)][psobject]$State)
    Assert-SafeGitEnvironment
    Assert-SafeGitConfig $State.Root
    $sha = (Invoke-GitCommand -Arguments @('-C', $State.Root, 'rev-parse', 'HEAD^{commit}')).Output[-1]
    if ($sha -cne $State.NewSha) { throw 'Super Push candidate HEAD changed; prepare and validate again.' }
    $branch = Invoke-GitCommand -Arguments @('-C', $State.Root, 'symbolic-ref', '-q', 'HEAD') -AllowFailure
    if ($branch.ExitCode -ne 1) { throw 'Super Push candidate must remain detached.' }
    Assert-CleanWorktree (Invoke-GitCommand -Arguments @('-C', $State.Root, 'status', '--porcelain=v1', '--untracked-files=all')).Output
    $origin = (Invoke-GitCommand -Arguments @('-C', $State.Root, 'config', '--get', 'remote.origin.url')).Output[-1]
    if ($origin -cne $State.Origin) { throw 'Super Push candidate origin changed.' }
    Invoke-GitCommand -Arguments @('-C', $State.Root, 'fetch', '--no-tags', '--no-recurse-submodules', 'origin',
        'refs/heads/main:refs/remotes/origin/main') | Out-Null
    $main = (Invoke-GitCommand -Arguments @('-C', $State.Root, 'rev-parse', 'refs/remotes/origin/main^{commit}')).Output[-1]
    if ($main -cne $State.OldSha) {
        $drift = [InvalidOperationException]::new('Remote main changed; prepare and validate a fresh candidate before approval.')
        $drift.Data['SuperPushRemoteMainDrift'] = $true
        throw $drift
    }
    if (-not (Test-FastForward $State.Root $State.OldSha $State.NewSha)) { throw 'Super Push candidate is not a fast-forward.' }
}

function New-SuperPushCandidate {
    <#
    .SYNOPSIS
    Replays explicitly selected task commits onto current origin/main in a detached worktree.
    .DESCRIPTION
    Does not push or access App credentials. Supply full commit SHAs in oldest-first
    order. Source branches and staged, dirty and untracked files remain untouched.
    Non-docs candidates require a successful external ValidationCommand (executable
    followed by arguments), run in the candidate directory without a shell. Success
    returns Root, OldSha and NewSha for exact-SHA review and native Pi approval.
    The caller owns the retained temporary worktree and its eventual cleanup.
    #>
    [CmdletBinding()]
    param(
        [string]$SourcePath = (Get-Location).ProviderPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$TaskCommit,
        [string[]]$ValidationCommand
    )
    # Only local docs preparation may be retried, before any candidate is exposed
    # for approval. Each failed attempt removes its own isolated worktree.
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            return New-SuperPushCandidateAttempt -SourcePath $SourcePath -TaskCommit $TaskCommit -ValidationCommand $ValidationCommand
        }
        catch {
            if (-not $_.Exception.Data['SuperPushDocsPreparationDrift'] -or $attempt -eq 3) { throw }
            Write-Verbose 'Remote main advanced during docs-only preparation; rebuilding the same selected scope.'
        }
    }
}

function New-SuperPushCandidateAttempt {
    param([string]$SourcePath, [string[]]$TaskCommit, [string[]]$ValidationCommand)
    Assert-SafeGitEnvironment
    $root = (Invoke-GitCommand -Arguments @('-C', $SourcePath, 'rev-parse', '--show-toplevel')).Output[-1]
    Assert-SafeGitConfig $root
    $origin = (Invoke-GitCommand -Arguments @('-C', $root, 'config', '--get', 'remote.origin.url')).Output[-1]
    $repository = Get-CrispRepository $origin
    $sourceSha = (Invoke-GitCommand -Arguments @('-C', $root, 'rev-parse', 'HEAD^{commit}')).Output[-1]
    Invoke-GitCommand -Arguments @('-C', $root, 'fetch', '--no-tags', '--no-recurse-submodules', 'origin',
        'refs/heads/main:refs/remotes/origin/main') | Out-Null
    $oldSha = (Invoke-GitCommand -Arguments @('-C', $root, 'rev-parse', 'refs/remotes/origin/main^{commit}')).Output[-1]
    $seen = @()
    $previous = $null
    foreach ($commit in $TaskCommit) {
        if ($commit -cnotmatch '^[0-9a-f]{40}$') { throw 'Task scope requires each full commit SHA, not refs or ranges.' }
        if ($commit -in $seen) { throw 'Task scope contains a duplicate commit.' }
        if (-not (Test-FastForward $root $commit $sourceSha)) { throw 'Task commit is not part of the source HEAD history.' }
        if (Test-FastForward $root $commit $oldSha) { throw 'Task commit is already on remote main.' }
        $parents = ((Invoke-GitCommand -Arguments @('-C', $root, 'rev-list', '--parents', '-n', '1', $commit)).Output[-1]).Split(' ')
        if ($parents.Count -ne 2) { throw 'Task scope must contain ordinary single-parent commits, not merges or root commits.' }
        if ($previous -and -not (Test-FastForward $root $previous $commit)) { throw 'Task commits must be selected in oldest-first ancestry order.' }
        $seen += $commit
        $previous = $commit
    }
    $container = Join-Path ([IO.Path]::GetTempPath()) "rickscripts-super-push-candidate-$([guid]::NewGuid())"
    $worktree = Join-Path $container 'worktree'
    $added = $false
    $complete = $false
    $state = $null
    try {
        [IO.Directory]::CreateDirectory($container) | Out-Null
        Invoke-GitCommand -Arguments @('-C', $root, '-c', 'core.hooksPath=/dev/null', 'worktree', 'add', '--detach', $worktree, $oldSha) | Out-Null
        $added = $true
        # Git resolves macOS /var and /tmp aliases; bind receipts to its canonical root.
        $worktree = (Invoke-GitCommand -Arguments @('-C', $worktree, 'rev-parse', '--show-toplevel')).Output[-1]
        # Never merge branch history or invoke commit hooks/signing during replay.
        foreach ($commit in $TaskCommit) {
            Invoke-GitCommand -Arguments @('-C', $worktree, '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgSign=false',
                'cherry-pick', '--no-gpg-sign', $commit) | Out-Null
        }
        $newSha = (Invoke-GitCommand -Arguments @('-C', $worktree, 'rev-parse', 'HEAD^{commit}')).Output[-1]
        Assert-DistinctCommits $oldSha $newSha
        $state = [pscustomobject]@{
            Repository = $repository; Root = $worktree; Origin = $origin
            TargetRef = $script:SuperPushRef; OldSha = $oldSha; NewSha = $newSha
            SourceRoot = $root; SourceSha = $sourceSha; TaskCommits = @($seen)
            DocumentationOnly = $false; ValidationPassed = $false
        }
        $state.DocumentationOnly = Test-SuperPushCandidateDocumentationOnly $state
        Assert-SuperPushCandidate $state
        if (-not $state.DocumentationOnly -or $ValidationCommand) {
            Invoke-SuperPushCandidateValidation -Command $ValidationCommand -State $state
            $state.ValidationPassed = $true
        }
        $gitDirectory = (Invoke-GitCommand -Arguments @('-C', $worktree, 'rev-parse', '--absolute-git-dir')).Output[-1]
        $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $gitDirectory 'super-push-candidate.json')
        $complete = $true
        $state
    }
    catch {
        if ($null -ne $state -and $state.DocumentationOnly -and $_.Exception.Data['SuperPushRemoteMainDrift']) {
            $_.Exception.Data['SuperPushDocsPreparationDrift'] = $true
        }
        throw
    }
    finally {
        if (-not $complete) {
            if ($added) {
                # Only this newly allocated isolated worktree is removed on failure.
                Invoke-GitCommand -Arguments @('-C', $root, 'worktree', 'remove', '--force', $worktree) | Out-Null
            }
            if (Test-Path -LiteralPath $container) { Remove-Item -LiteralPath $container -Recurse -Force }
        }
    }
}

function Initialize-SuperPushInvocation {
    param([string[]]$TaskCommit, [string[]]$ValidationCommand)
    Assert-SafeGitEnvironment
    $root = (Invoke-GitCommand -Arguments @('rev-parse', '--show-toplevel')).Output[-1]
    $branch = Invoke-GitCommand -Arguments @('-C', $root, 'symbolic-ref', '-q', 'HEAD') -AllowFailure
    if ($branch.ExitCode -eq 1) {
        if ($TaskCommit) { throw 'A detached candidate cannot be rewritten inside publication; prepare before exact-SHA approval.' }
        return $null
    }
    if ($branch.ExitCode -ne 0) { throw 'Could not determine source branch.' }
    if (-not $TaskCommit) {
        if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) {
            throw 'Task commit scope is required; supply -TaskCommit with full SHAs.'
        }
        Write-Host 'Select only task-owned commits. Enter full SHAs oldest-first, separated by spaces (no default):'
        $selection = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($selection)) { throw 'Task commit scope is required; no branch history is selected automatically.' }
        $TaskCommit = $selection.Trim() -split '\s+'
    }
    New-SuperPushCandidate -SourcePath $root -TaskCommit $TaskCommit -ValidationCommand $ValidationCommand
}

function Assert-SuperPushCandidateValidation {
    param([Parameter(Mandatory)][psobject]$State, [string[]]$ValidationCommand)
    $receipt = Get-SuperPushCandidateReceipt $State
    if ($receipt) { Assert-SuperPushCandidate $State }
    if (-not (Test-SuperPushCandidateDocumentationOnly $State) -and -not $receipt) {
        # Existing detached callers must explicitly validate this exact snapshot;
        # no preparation or rewrite occurs in an approved broker invocation.
        Invoke-SuperPushCandidateValidation -Command $ValidationCommand -State $State
    }
}
