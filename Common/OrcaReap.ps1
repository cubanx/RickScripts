# Private helpers for Remove-OldOrcaWorktree. Raw command output never enters diagnostics.
function Invoke-OrcaReapCommand {
    param([string]$Executable, [string[]]$Arguments, [int]$TimeoutSeconds = 60)
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    # Inherited Git selectors/config injection must not redirect checks to another checkout.
    foreach ($key in @($start.Environment.Keys | Where-Object { $_ -like 'GIT_*' })) {
        $start.Environment.Remove($key) | Out-Null
    }
    $start.Environment['GIT_TERMINAL_PROMPT'] = '0'
    $start.Environment['GCM_INTERACTIVE'] = 'Never'
    $start.Environment['GIT_SSH_COMMAND'] = 'ssh -o BatchMode=yes'
    # A remote target inherited from an interactive session must not redirect local checks.
    $start.Environment.Remove('ORCA_ENVIRONMENT') | Out-Null
    $start.Environment.Remove('ORCA_PAIRING_CODE') | Out-Null
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'CommandTimeout'
        }
        if (-not $stdout.Wait($TimeoutSeconds * 1000) -or -not $stderr.Wait($TimeoutSeconds * 1000)) { throw 'CommandTimeout' }
        $text = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "CommandExit:$($process.ExitCode)" }
        return $text
    }
    finally { $process.Dispose() }
}

function ConvertFrom-OrcaReapResponse {
    param([string]$Text)
    try { $response = ConvertFrom-Json -InputObject $Text -AsHashtable -ErrorAction Stop }
    catch { throw 'MalformedResponse' }
    if ($response -isnot [System.Collections.IDictionary] -or
        $response.ok -isnot [bool] -or -not $response.ok -or
        $response.result -isnot [System.Collections.IDictionary] -or
        [string]::IsNullOrWhiteSpace($response._meta.runtimeId)) { throw 'InvalidResponse' }
    return $response
}

function Test-OrcaReapCoverage {
    param($Result, [string]$Collection)
    if ($Result[$Collection] -isnot [array] -or $Result.truncated -isnot [bool] -or
        $Result.totalCount -isnot [long] -and $Result.totalCount -isnot [int] -or
        $Result.hostScope.hostIds -isnot [array] -or $Result.hostScope.omittedHostIds -isnot [array]) {
        return $false
    }
    return (-not $Result.truncated -and $Result.totalCount -eq $Result[$Collection].Count -and
        $Result.hostScope.omittedHostIds.Count -eq 0 -and
        $Result.hostScope.hostIds.Count -eq 1 -and $Result.hostScope.hostIds[0] -ceq 'local')
}

function Get-OrcaReapDiagnostic {
    param($ErrorRecord)
    # Allow only our fixed reason codes; never copy provider, Git, hook or JSON error text.
    $reason = $ErrorRecord.Exception.Message
    $codes = @('CommandTimeout', 'MalformedResponse', 'InvalidResponse', 'IncompleteCoverage',
        'IdentityUnverified', 'IdentityChanged', 'ProtectedWorktree', 'TimestampInvalid',
        'RecentlyActive', 'ActivityUnverified', 'ActiveResources', 'GitDirty', 'GitUnverified',
        'GitUnmerged', 'GitRemoteStale', 'GitReflogUnmerged', 'RuntimeChanged', 'RemovalUnverified')
    if ($reason -in $codes -or $reason -match '^CommandExit:-?\d+$') { return $reason }
    return "CheckFailed:$($ErrorRecord.Exception.GetType().Name)"
}

function Assert-OrcaReapMetadata {
    param($Tree, $Activity, [int]$InactiveDays, [DateTimeOffset]$Now)
    if ($Tree -isnot [System.Collections.IDictionary] -or
        [string]::IsNullOrWhiteSpace($Tree.id) -or [string]::IsNullOrWhiteSpace($Tree.path) -or
        [string]::IsNullOrWhiteSpace($Tree.repoId) -or [string]::IsNullOrWhiteSpace($Tree.instanceId) -or
        $Tree.id -cne "$($Tree.repoId)::$($Tree.path)" -or
        $Tree.hostId -cne 'local' -or $Tree.identity.executionHostId -cne 'local' -or
        $Tree.identity.instanceId -cne $Tree.instanceId -or
        $Tree.identity.key -cne "wt2:local:$($Tree.instanceId)" -or
        -not [IO.Path]::IsPathFullyQualified($Tree.path)) { throw 'IdentityUnverified' }
    foreach ($key in @('isMainWorktree', 'isPinned', 'isBare')) {
        if ($Tree[$key] -isnot [bool] -or $Tree[$key]) { throw 'ProtectedWorktree' }
    }
    if ($Tree.childWorktreeIds -isnot [array] -or $Tree.childWorktreeIds.Count -ne 0) { throw 'ProtectedWorktree' }
    if ($Tree.lastActivityAt -isnot [long] -and $Tree.lastActivityAt -isnot [int]) { throw 'TimestampInvalid' }
    try { $lastActivity = [DateTimeOffset]::FromUnixTimeMilliseconds($Tree.lastActivityAt) }
    catch { throw 'TimestampInvalid' }
    if ($Tree.lastActivityAt -le 0 -or $lastActivity -gt $Now) { throw 'TimestampInvalid' }
    if ($lastActivity -ge $Now.AddDays(-$InactiveDays)) { throw 'RecentlyActive' }
    if ($Activity -isnot [System.Collections.IDictionary] -or
        $Activity.worktreeId -cne $Tree.id -or $Activity.path -cne $Tree.path -or
        $Activity.worktreeInstanceId -cne $Tree.instanceId -or $Activity.hostId -cne 'local' -or
        ($Activity.lastActivityAt -isnot [long] -and $Activity.lastActivityAt -isnot [int]) -or
        $Activity.lastActivityAt -ne $Tree.lastActivityAt) { throw 'ActivityUnverified' }
    foreach ($key in @('isMainWorktree', 'isPinned', 'hasAttachedPty', 'hasHostSidebarActivity', 'isActive')) {
        if ($Activity[$key] -isnot [bool] -or $Activity[$key]) { throw 'ActiveResources' }
    }
    if ($Activity.status -cne 'inactive' -or
        ($Activity.liveTerminalCount -isnot [int] -and $Activity.liveTerminalCount -isnot [long]) -or
        $Activity.liveTerminalCount -ne 0 -or $Activity.agents -isnot [array] -or
        $Activity.agents.Count -ne 0) { throw 'ActiveResources' }
}

function Get-OrcaReapGitSafety {
    param($Tree, [int]$TimeoutSeconds = 60)
    function Invoke-ReapGit {
        param([string[]]$GitArguments)
        Invoke-OrcaReapCommand -Executable 'git' -Arguments (@('-C', $Tree.path,
            '-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false') + $GitArguments) -TimeoutSeconds $TimeoutSeconds
    }
    $head = (Invoke-ReapGit @('rev-parse', '--verify', 'HEAD')).Trim()
    $branch = (Invoke-ReapGit @('symbolic-ref', '-q', 'HEAD')).Trim()
    $root = (Invoke-ReapGit @('rev-parse', '--show-toplevel')).Trim()
    if ($head -notmatch '^[a-f0-9]{40,64}$' -or $head -cne $Tree.head -or
        $branch -cne $Tree.branch -or $branch -notlike 'refs/heads/*' -or
        [IO.Path]::GetFullPath($root) -cne [IO.Path]::GetFullPath($Tree.path)) { throw 'GitUnverified' }
    # Verify actual Git registration and independently protect the main/locked worktree.
    $registrations = (Invoke-ReapGit @('worktree', 'list', '--porcelain')) -split '(?:\r?\n){2}'
    if ($registrations.Count -lt 2 -or $registrations[0] -match "(?m)^worktree $([regex]::Escape($root))\r?$") { throw 'GitUnverified' }
    $registration = @($registrations | Where-Object { $_ -match "(?m)^worktree $([regex]::Escape($root))\r?$" })
    if ($registration.Count -ne 1 -or $registration[0] -match '(?m)^(locked|prunable|bare|detached)' -or
        $registration[0] -notmatch "(?m)^HEAD $head\r?$" -or
        $registration[0] -notmatch "(?m)^branch $([regex]::Escape($branch))\r?$") { throw 'GitUnverified' }
    # Include ignored files: deletion would lose them too. Do not trust configured submodule ignores.
    $dirty = [bool](Invoke-ReapGit @('status', '--porcelain=v1', '--untracked-files=all', '--ignored=matching', '--ignore-submodules=none')).Trim()
    if ((Invoke-ReapGit @('ls-files', '--stage')) -match '(?m)^160000 ') { throw 'GitUnverified' }
    if ((Invoke-ReapGit @('stash', 'list', '--format=%H')).Trim()) { throw 'GitUnverified' }
    # A local branch/tag or stale cached remote is insufficient proof of published, merged commits.
    if ($Tree.baseRef -notmatch '^refs/remotes/([^/]+)/(.+)$') { throw 'GitUnverified' }
    $remote = $Matches[1]; $remoteBranch = $Matches[2]
    if ($remote.StartsWith('-') -or $remoteBranch.StartsWith('-')) { throw 'GitUnverified' }
    $base = (Invoke-ReapGit @('rev-parse', '--verify', "$($Tree.baseRef)^{commit}")).Trim()
    $advertised = (Invoke-ReapGit @('ls-remote', '--exit-code', '--refs', $remote, "refs/heads/$remoteBranch")).Trim()
    if ($advertised -cne "$base`trefs/heads/$remoteBranch") { throw 'GitRemoteStale' }
    # merge-base exits nonzero when HEAD is not contained in the live remote base.
    Invoke-ReapGit @('merge-base', '--is-ancestor', $head, $base) | Out-Null
    $history = (Invoke-ReapGit @('reflog', 'show', '--format=%H', 'HEAD')).Trim()
    if (-not $history) { throw 'GitUnverified' }
    foreach ($commit in @($history -split '\r?\n' | Select-Object -Unique)) {
        if ($commit -notmatch '^[a-f0-9]{40,64}$') { throw 'GitUnverified' }
        Invoke-ReapGit @('merge-base', '--is-ancestor', $commit, $base) | Out-Null
    }
    # Detect concurrent Git changes during the above checks.
    if ((Invoke-ReapGit @('rev-parse', 'HEAD')).Trim() -cne $head -or
        (Invoke-ReapGit @('symbolic-ref', '-q', 'HEAD')).Trim() -cne $branch) { throw 'GitUnverified' }
    $dirty = $dirty -or [bool](Invoke-ReapGit @('status', '--porcelain=v1', '--untracked-files=all', '--ignored=matching', '--ignore-submodules=none')).Trim()
    return [pscustomobject]@{ HasLocalFiles = $dirty }
}
