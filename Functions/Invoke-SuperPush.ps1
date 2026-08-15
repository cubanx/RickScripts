#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SuperPushRef = 'refs/heads/main'
$script:SuperPushAccount = '2KC5FVMXXJGKDG7LGHWF2OJ2N4'
$script:SuperPushItem = 'Super Push GitHub App'
$script:GitHubApiVersion = '2026-03-10'
$script:GitPath = '/usr/bin/git'
$script:OnePasswordPath = '/opt/homebrew/bin/op'

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $output = @(& $script:GitPath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Git command failed with exit code $exitCode`: git $($Arguments -join ' ')"
    }

    [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Assert-SafeGitEnvironment {
    $blockedNames = @(
        'GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE',
        'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES',
        'GIT_REPLACE_REF_BASE', 'GIT_SHALLOW_FILE', 'GIT_CEILING_DIRECTORIES',
        'GIT_DISCOVERY_ACROSS_FILESYSTEM', 'GIT_CONFIG', 'GIT_CONFIG_SYSTEM',
        'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_COUNT',
        'GIT_CONFIG_PARAMETERS', 'GIT_EXEC_PATH', 'GIT_SSH', 'GIT_SSH_COMMAND',
        'GIT_PROXY_COMMAND'
    )
    foreach ($name in $blockedNames) {
        if (Test-Path -LiteralPath "Env:$name") {
            throw "Super Push rejects ambient Git override: $name."
        }
    }

    $generatedConfig = Get-ChildItem Env: | Where-Object {
        $_.Name -like 'GIT_CONFIG_KEY_*' -or $_.Name -like 'GIT_CONFIG_VALUE_*'
    } | Select-Object -First 1
    if ($generatedConfig) {
        throw "Super Push rejects ambient Git override: $($generatedConfig.Name)."
    }
}

function Assert-SafeGitConfig {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $unsafe = Invoke-GitCommand -Arguments @(
        '-C', $RepositoryRoot, 'config', '--get-regexp',
        '^(url\..*\.(insteadof|pushinsteadof)|http\.(.*\.)?(extraheader|sslverify|sslcainfo|sslcapath|proxy|followredirects))$'
    ) -AllowFailure
    if ($unsafe.ExitCode -eq 0) {
        throw 'Super Push rejects Git URL rewrites and token-sensitive HTTP configuration.'
    }
    if ($unsafe.ExitCode -ne 1) {
        throw "Git could not inspect safety-sensitive configuration (exit code $($unsafe.ExitCode))."
    }
}

function Get-CrispRepository {
    param([Parameter(Mandatory)][string]$OriginUrl)

    foreach ($pattern in @(
        '^git@github\.com:Crisp-Inc/(?<name>[A-Za-z0-9_.-]+?)(?:\.git)?$',
        '^https://github\.com/Crisp-Inc/(?<name>[A-Za-z0-9_.-]+?)(?:\.git)?$',
        '^ssh://git@github\.com/Crisp-Inc/(?<name>[A-Za-z0-9_.-]+?)(?:\.git)?$'
    )) {
        if ($OriginUrl -cmatch $pattern) {
            return "Crisp-Inc/$($Matches.name)"
        }
    }

    throw 'Super Push accepts only a GitHub origin owned by Crisp-Inc.'
}

function Assert-CleanWorktree {
    param([AllowNull()][object]$Status)

    if (-not [string]::IsNullOrWhiteSpace(($Status -join "`n"))) {
        throw 'Super Push requires a clean worktree.'
    }
}

function Assert-DistinctCommits {
    param(
        [Parameter(Mandatory)][string]$OldSha,
        [Parameter(Mandatory)][string]$NewSha
    )

    if ($OldSha -ceq $NewSha) {
        throw 'Remote main already points to local HEAD; there is nothing to push.'
    }
}

function Test-FastForward {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$OldSha,
        [Parameter(Mandatory)][string]$NewSha
    )

    $result = Invoke-GitCommand -Arguments @(
        '-C', $RepositoryRoot, 'merge-base', '--is-ancestor', $OldSha, $NewSha
    ) -AllowFailure
    if ($result.ExitCode -eq 0) { return $true }
    if ($result.ExitCode -eq 1) { return $false }
    throw "Git could not verify ancestry (exit code $($result.ExitCode))."
}

function Get-SuperPushState {
    Assert-SafeGitEnvironment
    $root = (Invoke-GitCommand -Arguments @('rev-parse', '--show-toplevel')).Output[-1]
    Assert-SafeGitConfig $root
    $origin = (Invoke-GitCommand -Arguments @(
        '-C', $root, 'config', '--get', 'remote.origin.url'
    )).Output[-1]
    $repository = Get-CrispRepository $origin
    Assert-CleanWorktree (Invoke-GitCommand -Arguments @(
        '-C', $root, 'status', '--porcelain=v1', '--untracked-files=normal'
    )).Output

    $newSha = (Invoke-GitCommand -Arguments @(
        '-C', $root, 'rev-parse', 'HEAD^{commit}'
    )).Output[-1]
    Invoke-GitCommand -Arguments @(
        '-C', $root, 'fetch', '--no-tags', '--no-recurse-submodules', 'origin',
        'refs/heads/main:refs/remotes/origin/main'
    ) | Out-Null
    $oldSha = (Invoke-GitCommand -Arguments @(
        '-C', $root, 'rev-parse', 'refs/remotes/origin/main^{commit}'
    )).Output[-1]

    Assert-DistinctCommits $oldSha $newSha
    if (-not (Test-FastForward $root $oldSha $newSha)) {
        throw 'Local HEAD is not a fast-forward of remote main.'
    }

    [pscustomobject]@{
        Repository = $repository
        Root = $root
        Origin = $origin
        TargetRef = $script:SuperPushRef
        OldSha = $oldSha
        NewSha = $newSha
    }
}

function Update-SuperPushTrackingRef {
    param([Parameter(Mandatory)][psobject]$State)

    Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'fetch', '--no-tags', '--no-recurse-submodules', 'origin',
        'refs/heads/main:refs/remotes/origin/main'
    ) | Out-Null
    $trackingSha = (Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'rev-parse', 'refs/remotes/origin/main^{commit}'
    )).Output[-1]
    if ($trackingSha -cne $State.NewSha) {
        throw 'Push was accepted, but local origin/main does not match the pushed SHA.'
    }
}

function Show-SuperPushEvidence {
    param([Parameter(Mandatory)][psobject]$State)

    Write-Host ''
    Write-Host 'SUPER PUSH PREFLIGHT'
    Write-Host "Repository:  $($State.Repository)"
    Write-Host "Target ref:  $($State.TargetRef)"
    Write-Host "Remote SHA:  $($State.OldSha)"
    Write-Host "Candidate:   $($State.NewSha)"
    Write-Host 'Ancestry:    verified fast-forward'
    Write-Host 'Local hooks: disabled for credential isolation'
    Write-Host ''
    Write-Host 'Commits:'
    (Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'log', '--format=%H%x09%s',
        "$($State.OldSha)..$($State.NewSha)"
    )).Output | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host 'Diff stat:'
    (Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'diff', '--stat', '--no-ext-diff',
        $State.OldSha, $State.NewSha
    )).Output | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host 'Changed files:'
    (Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'diff', '--name-status', '--no-ext-diff',
        $State.OldSha, $State.NewSha
    )).Output | ForEach-Object { Write-Host $_ }
    Write-Host ''
}

function Get-SuperPushConfirmation {
    'Approved'
}

function Test-SuperPushConfirmation {
    param(
        [AllowNull()][string]$Actual,
        [Parameter(Mandatory)][string]$Expected
    )

    $Actual -ceq $Expected
}

function Confirm-SuperPush {
    if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) {
        throw 'Super Push requires an interactive terminal; unattended input is forbidden.'
    }

    $expected = Get-SuperPushConfirmation
    Write-Host "Type exactly: $expected"
    Write-Host 'Confirmation: ' -NoNewline
    $actual = [Console]::ReadLine()
    if (-not (Test-SuperPushConfirmation $actual $expected)) {
        throw 'Super Push confirmation did not match.'
    }
}

function Assert-UnchangedState {
    param(
        [Parameter(Mandatory)][psobject]$Before,
        [Parameter(Mandatory)][psobject]$After
    )

    foreach ($property in 'Repository', 'Root', 'Origin', 'TargetRef', 'OldSha', 'NewSha') {
        if ($Before.$property -cne $After.$property) {
            throw "Super Push preflight changed at $property; start a fresh invocation."
        }
    }
}

function Invoke-OnePasswordJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = @(& $script:OnePasswordPath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0) {
        throw "1Password command failed while resolving $script:SuperPushItem."
    }
    try {
        $output -join "`n" | Microsoft.PowerShell.Utility\ConvertFrom-Json -Depth 20
    }
    catch {
        throw "1Password returned malformed metadata for $script:SuperPushItem."
    }
}

function Get-SuperPushAppCredential {
    $env:OP_SERVICE_ACCOUNT_TOKEN = $null
    $env:OP_SESSION = $null
    $env:OP_ACCOUNT = $script:SuperPushAccount
    $env:OP_BIOMETRIC_UNLOCK_ENABLED = 'true'

    $item = Invoke-OnePasswordJson @(
        'item', 'get', $script:SuperPushItem,
        '--account', $script:SuperPushAccount, '--format', 'json', '--reveal'
    )
    $vault = Invoke-OnePasswordJson @(
        'vault', 'get', $item.vault.id,
        '--account', $script:SuperPushAccount, '--format', 'json'
    )
    if ($vault.name -ieq 'Automation') {
        throw 'The Super Push App credential must not be stored in the Automation vault.'
    }

    $clientFields = @($item.fields | Where-Object { $_.label -ceq 'client-id' })
    $keyFields = @($item.fields | Where-Object { $_.label -ceq 'private-key' })
    if ($clientFields.Count -ne 1 -or [string]::IsNullOrWhiteSpace($clientFields[0].value)) {
        throw "The $script:SuperPushItem item requires one client-id field."
    }
    if ($keyFields.Count -ne 1 -or [string]::IsNullOrWhiteSpace($keyFields[0].value)) {
        throw "The $script:SuperPushItem item requires one private-key field."
    }

    [pscustomobject]@{
        ClientId = $clientFields[0].value
        PrivateKey = $keyFields[0].value
    }
}

function ConvertTo-Base64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-Base64Url {
    param([Parameter(Mandatory)][string]$Value)

    $padded = $Value.Replace('-', '+').Replace('_', '/')
    if ($padded.Length % 4) { $padded += '=' * (4 - ($padded.Length % 4)) }
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($padded))
}

function New-GitHubAppJwt {
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$PrivateKey
    )

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes(
        (@{ alg = 'RS256'; typ = 'JWT' } | ConvertTo-Json -Compress)
    ))
    $payload = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes(
        (@{ iat = $now - 60; exp = $now + 540; iss = $ClientId } | ConvertTo-Json -Compress)
    ))
    $unsigned = "$header.$payload"
    $rsa = [Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportFromPem($PrivateKey)
        $signature = $rsa.SignData(
            [Text.Encoding]::UTF8.GetBytes($unsigned),
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    }
    catch {
        throw 'The Super Push GitHub App private key is invalid.'
    }
    finally {
        $rsa.Dispose()
    }

    "$unsigned.$(ConvertTo-Base64Url $signature)"
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Token,
        [AllowNull()][object]$Body
    )

    $parameters = @{
        Method = $Method
        Uri = "https://api.github.com$Path"
        Headers = @{
            Accept = 'application/vnd.github+json'
            Authorization = "Bearer $Token"
            'X-GitHub-Api-Version' = $script:GitHubApiVersion
        }
        UserAgent = 'crisp-super-push'
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Compress -Depth 5
    }

    try {
        Microsoft.PowerShell.Utility\Invoke-RestMethod @parameters
    }
    catch {
        $status = 'unknown'
        if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        throw "GitHub API $Method $Path failed (HTTP $status)."
    }
}

function Assert-SuperPushPermissions {
    param([Parameter(Mandatory)][psobject]$Permissions)

    if ($Permissions.contents -cne 'write') {
        throw 'The Super Push App requires contents write permission.'
    }
    $extra = @($Permissions.PSObject.Properties.Name | Where-Object {
        $_ -notin @('contents', 'metadata')
    })
    if ($extra.Count -ne 0 -or (
        $Permissions.PSObject.Properties.Name -contains 'metadata' -and
        $Permissions.metadata -cne 'read'
    )) {
        throw 'The Super Push App or token has broader permissions than contents write and metadata read.'
    }
}

function Assert-SuperPushInstallation {
    param([Parameter(Mandatory)][psobject]$Installation)

    if ($Installation.repository_selection -cne 'selected') {
        throw 'The Super Push App must use selected-repository installation.'
    }
    if ($Installation.account.login -ine 'Crisp-Inc') {
        throw 'The Super Push App installation is not owned by Crisp-Inc.'
    }
    Assert-SuperPushPermissions $Installation.permissions
}

function Assert-SuperPushToken {
    param(
        [Parameter(Mandatory)][psobject]$Grant,
        [Parameter(Mandatory)][string]$Repository
    )

    if ([string]::IsNullOrWhiteSpace($Grant.token) -or
        [string]::IsNullOrWhiteSpace($Grant.expires_at)) {
        throw 'GitHub returned an incomplete Super Push installation token.'
    }
    if ($Grant.repository_selection -cne 'selected') {
        throw 'GitHub returned a non-selected Super Push token.'
    }
    Assert-SuperPushPermissions $Grant.permissions
    if (@($Grant.repositories).Count -ne 1 -or
        $Grant.repositories[0].full_name -ine $Repository) {
        throw 'GitHub returned a Super Push token for the wrong repository scope.'
    }
}

function New-SuperPushToken {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$PrivateKey
    )

    $jwt = New-GitHubAppJwt $ClientId $PrivateKey
    try {
        $parts = $Repository.Split('/', 2)
        $owner = [Uri]::EscapeDataString($parts[0])
        $name = [Uri]::EscapeDataString($parts[1])
        $installation = Invoke-GitHubApi -Method GET `
            -Path "/repos/$owner/$name/installation" -Token $jwt
        Assert-SuperPushInstallation $installation

        $grant = Invoke-GitHubApi -Method POST `
            -Path "/app/installations/$($installation.id)/access_tokens" `
            -Token $jwt -Body @{
                repositories = @($parts[1])
                permissions = @{ contents = 'write' }
            }
        $grant | Add-Member -NotePropertyName installation_id `
            -NotePropertyValue $installation.id -Force
        $grant
    }
    finally {
        $jwt = $null
    }
}

function Get-SuperPushArguments {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Sha
    )

    @(
        '-C', $RepositoryRoot, 'push', '--porcelain', '--no-verify',
        "https://github.com/$Repository.git",
        "$Sha`:$script:SuperPushRef"
    )
}

function Invoke-SuperPushGit {
    param(
        [Parameter(Mandatory)][psobject]$State,
        [Parameter(Mandatory)][string]$Token
    )

    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x-access-token:$Token"))
    $repositoryUrl = "https://github.com/$($State.Repository).git"
    $config = [ordered]@{
        'http.extraHeader' = ''
        "http.$repositoryUrl.extraHeader" = "AUTHORIZATION: basic $basic"
        'credential.helper' = ''
        'credential.interactive' = 'false'
        'core.hooksPath' = '/dev/null'
        'http.followRedirects' = 'false'
        'http.sslVerify' = 'true'
    }
    $environmentNames = @(
        'GIT_CONFIG', 'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG_GLOBAL',
        'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_COUNT',
        'GIT_ASKPASS', 'GIT_TERMINAL_PROMPT', 'GCM_INTERACTIVE',
        'GIT_TRACE', 'GIT_TRACE_CURL', 'GIT_TRACE_CURL_NO_DATA',
        'GIT_TRACE_PACKET', 'GIT_TRACE_PERFORMANCE', 'GIT_TRACE_SETUP',
        'GIT_TRACE_SHALLOW', 'GIT_TRACE2', 'GIT_TRACE2_EVENT',
        'GIT_TRACE2_PERF', 'GIT_TRACE2_BRIEF', 'GIT_CURL_VERBOSE'
    ) + @(0..($config.Count - 1) | ForEach-Object {
        "GIT_CONFIG_KEY_$_", "GIT_CONFIG_VALUE_$_"
    })
    $previous = @{}
    foreach ($name in $environmentNames) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $null)
    }

    try {
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', '/dev/null')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_SYSTEM', '/dev/null')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT', [string]$config.Count)
        [Environment]::SetEnvironmentVariable('GIT_ASKPASS', '/usr/bin/false')
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0')
        [Environment]::SetEnvironmentVariable('GCM_INTERACTIVE', 'Never')
        $index = 0
        foreach ($entry in $config.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$index", $entry.Key)
            [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$index", $entry.Value)
            $index++
        }

        Invoke-GitCommand -Arguments (Get-SuperPushArguments `
            $State.Root $State.Repository $State.NewSha)
    }
    finally {
        $basic = $null
        foreach ($name in $environmentNames) {
            if ($null -eq $previous[$name]) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($name, $previous[$name])
            }
        }
    }
}

function Remove-SuperPushToken {
    param([Parameter(Mandatory)][string]$Token)

    Invoke-GitHubApi -Method DELETE -Path '/installation/token' -Token $Token | Out-Null
}

function Invoke-SuperPush {
    <#
    .SYNOPSIS
    Performs one deliberately confirmed fast-forward push of local HEAD to Crisp main.

    .DESCRIPTION
    Uses the dedicated selected-repository GitHub App after immutable preflight evidence
    and exact interactive confirmation. The cmdlet accepts no custom parameters.

    .EXAMPLE
    Invoke-SuperPush
    #>
    [CmdletBinding()]
    param()

    $confirmed = Get-SuperPushState
    Show-SuperPushEvidence $confirmed
    Confirm-SuperPush
    $beforeCredential = Get-SuperPushState
    Assert-UnchangedState $confirmed $beforeCredential

    $credential = $null
    $grant = $null
    $failure = $null
    $pushConfirmed = $false
    $revocationConfirmed = $false
    try {
        $credential = Get-SuperPushAppCredential
        $grant = New-SuperPushToken `
            $beforeCredential.Repository $credential.ClientId $credential.PrivateKey
        $credential.PrivateKey = $null
        Assert-SuperPushToken $grant $beforeCredential.Repository

        $beforePush = Get-SuperPushState
        Assert-UnchangedState $confirmed $beforePush
        Invoke-SuperPushGit $beforePush $grant.token | Out-Null
        $pushConfirmed = $true
        Update-SuperPushTrackingRef $beforePush
    }
    catch {
        $failure = $_.Exception.Message
    }
    finally {
        if ($null -ne $credential) {
            $credential.PrivateKey = $null
            $credential.ClientId = $null
        }
        $grantHasToken = $null -ne $grant -and
            $grant.PSObject.Properties.Name -contains 'token' -and
            -not [string]::IsNullOrWhiteSpace($grant.token)
        if ($grantHasToken) {
            try {
                Remove-SuperPushToken $grant.token
                $revocationConfirmed = $true
            }
            catch {
                $expiry = if ($grant.PSObject.Properties.Name -contains 'expires_at') {
                    $grant.expires_at
                } else {
                    'within one hour of minting'
                }
                $revokeFailure = "Token revocation failed; GitHub expiry is $expiry."
                $failure = if ($failure) { "$failure $revokeFailure" } else { $revokeFailure }
            }
            finally {
                $grant.token = $null
            }
        }
    }

    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $installationId = if ($null -ne $grant -and
        $grant.PSObject.Properties.Name -contains 'installation_id') {
        $grant.installation_id
    } else {
        'unknown'
    }
    $pushStatus = if ($pushConfirmed) { 'accepted' } else { 'not-confirmed' }
    $audit = "Repository=$($confirmed.Repository) Ref=$($confirmed.TargetRef) Old=$($confirmed.OldSha) New=$($confirmed.NewSha) Installation=$installationId Push=$pushStatus Revoked=$revocationConfirmed Time=$timestamp"
    if ($failure) {
        throw "Super Push failed. $audit. $failure"
    }

    Write-Host "Super Push succeeded. $audit"
}
