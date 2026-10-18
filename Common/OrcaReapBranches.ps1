# Private branch cleanup. Capture Git identity while the checkout still exists;
# An absent checkout may use its explicitly inventoried main checkout, never a
# guessed parent directory.
function Get-OrcaReapBranchPlan {
    param($Tree, [int]$TimeoutSeconds = 60, [string]$RepositoryPath = $Tree.path, [switch]$Force)
    $branch = [string]$Tree.branch
    $base = [string]$Tree.baseRef
    if ($branch -cnotmatch '^refs/heads/(.+)$') { throw 'BranchUnverified' }
    $name = $Matches[1]
    if ($name -in @('main', 'master') -or $base -ceq $branch -or
        $base -ceq "refs/remotes/origin/$name") { throw 'BranchProtected' }
    if ((-not $Force -and $base -cnotmatch '^refs/(heads|remotes/origin)/.+$') -or
        $Tree.head -cnotmatch '^[a-f0-9]{40,64}$') { throw 'BranchUnverified' }
    $gitDir = (Invoke-OrcaReapCommand git @('-C', $RepositoryPath, 'rev-parse', '--path-format=absolute', '--git-common-dir') $TimeoutSeconds).Trim()
    if (-not [IO.Path]::IsPathFullyQualified($gitDir)) { throw 'BranchUnverified' }
    $defaultRef = (Invoke-OrcaReapCommand git @('--git-dir', $gitDir, 'for-each-ref', '--format=%(symref)', 'refs/remotes/origin/HEAD') $TimeoutSeconds).Trim()
    if ($defaultRef -ceq "refs/remotes/origin/$name") { throw 'BranchProtected' }
    $baseOid = if ($Force) { '' } else {
        (Invoke-OrcaReapCommand git @('--git-dir', $gitDir, 'rev-parse', '--verify', "$base^{commit}") $TimeoutSeconds).Trim()
    }
    $head = (Invoke-OrcaReapCommand git @('--git-dir', $gitDir, 'rev-parse', '--verify', $branch) $TimeoutSeconds).Trim()
    if ($head -cne $Tree.head -or (-not $Force -and $baseOid -cnotmatch '^[a-f0-9]{40,64}$')) { throw 'BranchUnverified' }
    $originUrl = ''; $originHead = ''; $originReason = ''
    if ($Force) {
        try {
            $remotes = (Invoke-OrcaReapCommand git @('--git-dir', $gitDir, 'remote') $TimeoutSeconds) -split '\r?\n'
            if ($remotes -ccontains 'origin') {
                $originUrl = (Invoke-OrcaReapCommand git @('--git-dir', $gitDir, 'remote', 'get-url', 'origin') $TimeoutSeconds).Trim()
                $refs = (Invoke-OrcaReapCommand git @('--git-dir', $gitDir, 'ls-remote', '--symref', 'origin', 'HEAD', $branch) $TimeoutSeconds) -split '\r?\n'
                foreach ($line in $refs) {
                    if ($line -cmatch '^ref: (refs/heads/.+)\s+HEAD$' -and $Matches[1] -ceq $branch) { throw 'BranchProtected' }
                    if ($line -cmatch "^([a-f0-9]{40,64})\s+$([regex]::Escape($branch))$") { $originHead = $Matches[1] }
                }
            }
        }
        catch {
            if ($_.Exception.Message -eq 'BranchProtected') { throw }
            $originReason = Get-OrcaReapDiagnostic $_
        }
    }
    [pscustomobject]@{
        GitDir=$gitDir; Branch=$branch; Name=$name; Head=$head; Base=$base; BaseOid=$baseOid
        Forced=[bool]$Force; OriginUrl=$originUrl; OriginHead=$originHead; OriginReason=$originReason
    }
}

function Remove-OrcaReapBranches {
    param($Plan, [int]$TimeoutSeconds = 60, [switch]$Force)
    if ($Force -and -not $Plan.Forced) { throw 'BranchUnverified' }
    function Invoke-BranchGit {
        param([string[]]$GitArguments)
        Invoke-OrcaReapCommand git (@('--git-dir', $Plan.GitDir) + $GitArguments) $TimeoutSeconds
    }
    function Test-BranchMerged {
        param([string]$Tip, [string]$BaseTip)
        try { $null = Invoke-BranchGit @('merge-base', '--is-ancestor', $Tip, $BaseTip); return $true }
        catch {
            if ($_.Exception.Message -eq 'CommandExit:1') { return $false }
            throw
        }
    }
    $result = [pscustomobject]@{ Branch=$Plan.Name; Local='Retained'; Origin='Retained'; LocalReason=''; OriginReason='' }
    try {
        $local = (Invoke-BranchGit @('for-each-ref', '--format=%(objectname)', $Plan.Branch)).Trim()
        if (-not $local) { $result.Local = 'Absent' }
        elseif ($local -cne $Plan.Head) { $result.LocalReason = 'BranchChanged' }
        elseif (-not $Force -and -not (Test-BranchMerged $local $Plan.BaseOid)) { $result.LocalReason = 'NotMerged' }
        else {
            # Both modes preserve Git's checked-out-worktree protection. Only an
            # explicitly forced picker plan may bypass the merged check.
            $deleteFlag = if ($Force) { '-D' } else { '-d' }
            $null = Invoke-BranchGit @('branch', $deleteFlag, '--', $Plan.Name)
            $result.Local = 'Deleted'
        }
    }
    catch { $result.Local = 'Failed'; $result.LocalReason = Get-OrcaReapDiagnostic $_ }
    try {
        if ($Force -and $Plan.OriginReason) { $result.OriginReason = $Plan.OriginReason; return $result }
        $remoteBase = ''
        if (-not $Force) {
            if ($Plan.Base -cnotmatch '^refs/remotes/origin/(.+)$') { $result.OriginReason = 'OriginBaseUnverified'; return $result }
            $remoteBase = "refs/heads/$($Matches[1])"
        }
        $remotes = (Invoke-BranchGit @('remote')) -split '\r?\n'
        if ($remotes -cnotcontains 'origin') { $result.Origin = 'Absent'; return $result }
        # Resolve the server's actual tips, not possibly stale tracking refs. Refuse
        # multiple push destinations or a push URL different from the queried origin.
        $fetchUrls = @(Invoke-BranchGit @('remote', 'get-url', '--all', 'origin')) -join "`n"
        $pushUrls = @(Invoke-BranchGit @('remote', 'get-url', '--push', '--all', 'origin')) -join "`n"
        if ($fetchUrls.Trim() -cne $pushUrls.Trim() -or ($pushUrls.Trim() -split '\r?\n').Count -ne 1) { throw 'OriginTargetUnverified' }
        if ($Force -and $fetchUrls.Trim() -cne $Plan.OriginUrl) { $result.OriginReason = 'OriginChanged'; return $result }
        $query = @('ls-remote', '--symref', 'origin', 'HEAD', $Plan.Branch)
        if ($remoteBase) { $query += $remoteBase }
        $refs = (Invoke-BranchGit $query) -split '\r?\n'
        $tips = @{}
        foreach ($line in $refs) {
            if (-not $line) { continue }
            if ($line -cmatch '^ref: (refs/heads/.+)\s+HEAD$') {
                if ($Matches[1] -ceq $Plan.Branch) { throw 'BranchProtected' }
                continue
            }
            if ($line -cmatch '^[a-f0-9]{40,64}\s+HEAD$') { continue }
            if ($line -cnotmatch '^([a-f0-9]{40,64})\s+(refs/heads/.+)$') { throw 'BranchUnverified' }
            $tips[$Matches[2]] = $Matches[1]
        }
        if (-not $tips.ContainsKey($Plan.Branch)) { $result.Origin = 'Absent'; return $result }
        if ($Force) {
            if ($tips[$Plan.Branch] -cne $Plan.OriginHead) { $result.OriginReason = 'BranchChanged'; return $result }
        }
        else {
            if (-not $tips.ContainsKey($remoteBase)) { $result.OriginReason = 'OriginBaseUnverified'; return $result }
            # Fetch objects without changing refs or FETCH_HEAD. A concurrent change
            # makes proof fail or the exact-tip deletion lease reject the operation.
            $null = Invoke-BranchGit @('fetch', '--no-tags', '--no-write-fetch-head', '--refmap=', 'origin', $remoteBase, $Plan.Branch)
            if (-not (Test-BranchMerged $tips[$Plan.Branch] $tips[$remoteBase])) { $result.OriginReason = 'NotMerged'; return $result }
        }
        $null = Invoke-BranchGit @('push', '--porcelain', "--force-with-lease=$($Plan.Branch):$($tips[$Plan.Branch])", 'origin', ":$($Plan.Branch)")
        $result.Origin = 'Deleted'
    }
    catch { $result.Origin = 'Failed'; $result.OriginReason = Get-OrcaReapDiagnostic $_ }
    $result
}
