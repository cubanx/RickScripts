#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SuperPushRef = 'refs/heads/main'
$script:SuperPushVault = 'bcxp54juyo54olkp6ysoe4lzky'
$script:SuperPushItem = 'Super Push GitHub App'
$script:SuperPushItemId = 'elv65z73smxy4uq5jii57djpge'
$script:GitHubApiVersion = '2026-03-10'
$script:GitPath = '/usr/bin/git'
$script:OnePasswordPath = '/opt/homebrew/bin/op'

$script:SuperPushDiagnostics = $null

# This is a per-invocation buffer, not a transcript. Never include input,
# environment dumps, provider payloads, or ErrorRecord/stack serialization.
function Add-SuperPushSecret {
    param([AllowNull()][string]$Value)

    if ($null -eq $script:SuperPushDiagnostics -or [string]::IsNullOrEmpty($Value)) { return }
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x-access-token:$Value"))
    $values = @($Value, "x-access-token:$Value", "Bearer $Value", "Authorization: Bearer $Value", "AUTHORIZATION: basic $basic")
    if ($Value.Contains("`n")) {
        $values += @($Value -split '\r?\n' | Where-Object { $_ -and $_ -notmatch '^-----' })
    }
    foreach ($part in $values) {
        foreach ($variant in @(
            $part, [Uri]::EscapeDataString($part),
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($part)),
            (ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($part))),
            (ConvertTo-Json -InputObject $part -Compress).Trim('"')
        )) {
            if (-not $script:SuperPushDiagnostics.Secrets.Contains($variant)) {
                $script:SuperPushDiagnostics.Secrets.Add($variant)
            }
        }
    }
}

function Protect-SuperPushText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return '' }
    if ($null -ne $script:SuperPushDiagnostics) {
        foreach ($secret in ($script:SuperPushDiagnostics.Secrets | Sort-Object Length -Descending)) {
            $Text = $Text.Replace($secret, '[REDACTED]')
        }
    }
    $Text = [regex]::Replace($Text, '(?is)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----', '[REDACTED PRIVATE KEY]')
    $Text = [regex]::Replace($Text, '(?im)\b(?:proxy-)?authorization\s*[:=][^\r\n]*', 'Authorization: [REDACTED]')
    $Text = [regex]::Replace($Text, '(?i)\b(?:basic|bearer)\s+[A-Za-z0-9._~+/=-]+', '[REDACTED AUTH]')
    $Text = [regex]::Replace($Text, '(?i)(https?://)[^\s/@]+(?::[^\s/@]*)?@', '$1[REDACTED]@')
    $Text = [regex]::Replace($Text, '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1[REDACTED QUERY]')
    $Text = [regex]::Replace($Text, '\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b', '[REDACTED TOKEN]')
    # Do not permit terminal escape/control sequences to forge evidence.
    [regex]::Replace($Text, '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]', '?')
}

function Add-SuperPushDiagnostic {
    param([string]$Text)

    if ($null -ne $script:SuperPushDiagnostics) {
        $script:SuperPushDiagnostics.Lines.Add((Protect-SuperPushText $Text))
    }
}

function Assert-SuperPushDiagnosticDirectory {
    param([string]$Directory)

    $info = [IO.DirectoryInfo]::new($Directory)
    $private = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute
    if (-not $info.Exists -or $null -ne $info.LinkTarget -or
        [IO.File]::GetUnixFileMode($Directory) -ne $private) {
        throw 'Super Push diagnostic directory is unsafe; no diagnostic file was written.'
    }
    # Refuse destinations beneath other users' directories or non-sticky public
    # writable ancestors. Trusted OS temp symlinks (e.g. /var) may be ancestors,
    # but the actual diagnostic directory itself must never be a symlink.
    $uid = & /usr/bin/id -u
    if ($LASTEXITCODE -ne 0) { throw 'Cannot verify diagnostic ownership.' }
    $ancestor = $info
    while ($null -ne $ancestor) {
        $owner = & /usr/bin/stat -f '%u' $ancestor.FullName 2>$null
        if ($LASTEXITCODE -ne 0 -or $owner -notin @('0', "$uid")) {
            throw 'Super Push diagnostic ancestor ownership is unsafe.'
        }
        $mode = [IO.File]::GetUnixFileMode($ancestor.FullName)
        $publicWrite = [IO.UnixFileMode]::GroupWrite -bor [IO.UnixFileMode]::OtherWrite
        if (($mode -band $publicWrite) -and -not ($mode -band [IO.UnixFileMode]::StickyBit)) {
            throw 'Super Push diagnostic ancestor permissions are unsafe.'
        }
        if ($null -ne $ancestor.LinkTarget) {
            $ancestor = $ancestor.ResolveLinkTarget($true)
        } else { $ancestor = $ancestor.Parent }
    }
}

function Save-SuperPushDiagnostics {
    # .NET creates an unpredictable, exclusively created, current-user-owned
    # directory with mode 0700 (mkdtemp on Unix). No caller-selected destination.
    # Older runtimes without this API fail closed for retention, not for cleanup.
    $directory = [IO.Directory]::CreateTempSubdirectory('rickscripts-super-push-').FullName
    Assert-SuperPushDiagnosticDirectory $directory
    $path = [IO.Path]::Combine($directory, 'diagnostics.txt')
    $options = [IO.FileStreamOptions]::new()
    $options.Mode = [IO.FileMode]::CreateNew
    $options.Access = [IO.FileAccess]::Write
    $options.Share = [IO.FileShare]::None
    $options.UnixCreateMode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
    $stream = [IO.FileStream]::new($path, $options)
    try {
        # Re-redact in case a later phase registered a value present in an
        # earlier Git message. Raw credentials never enter this buffer/file.
        $text = Protect-SuperPushText ($script:SuperPushDiagnostics.Lines -join "`n")
        $bytes = [Text.Encoding]::UTF8.GetBytes($text + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
    $path
}

function Invoke-SuperPushGitProcess {
    param([string[]]$Arguments)

    $start = [Diagnostics.ProcessStartInfo]::new($script:GitPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = (Get-Location).ProviderPath
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        # Drain both pipes concurrently; never deadlock on a full stderr pipe.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout.GetAwaiter().GetResult(); Stderr = $stderr.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $command = Protect-SuperPushText ("git " + ($Arguments -join ' '))
    if ($null -ne $script:SuperPushDiagnostics) {
        Add-SuperPushDiagnostic "Phase=$($script:SuperPushDiagnostics.Phase) Command=$command"
    }
    try { $result = Invoke-SuperPushGitProcess $Arguments }
    catch {
        # Native launch exceptions can contain ambient paths/credentials.
        Add-SuperPushDiagnostic "Git Exit=not-started launch failed: $command"
        throw (Protect-SuperPushText "Git launch failed: $command. $($_.Exception.Message)")
    }
    # Configuration inspection can return unknown credentials; do not retain
    # its values. The command and exit status still identify the rejected gate.
    $sensitiveConfig = $Arguments -contains '--get-regexp'
    $stdout = if ($sensitiveConfig) { '[configuration values omitted]' } else { Protect-SuperPushText $result.Stdout }
    $stderr = Protect-SuperPushText $result.Stderr
    Add-SuperPushDiagnostic "Git Exit=$($result.ExitCode) stdout: $stdout"
    Add-SuperPushDiagnostic "Git Exit=$($result.ExitCode) stderr: $stderr"
    if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
        throw "Git command failed with exit code $($result.ExitCode): $command`nstdout: $stdout`nstderr: $stderr"
    }

    # Only stdout participates in SHA/path parsing. Return the original bytes
    # as text to internal callers; diagnostics and visible evidence are redacted.
    $output = @(
        if ($result.Stdout.Length -ne 0) {
            $result.Stdout.TrimEnd("`n").Split("`n") | ForEach-Object { $_.TrimEnd("`r") }
        }
    )
    [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $output; Stderr = $stderr }
}

function Assert-SafeGitEnvironment {
    $blockedNames = @(
        'GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE',
        'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES',
        'GIT_REPLACE_REF_BASE', 'GIT_SHALLOW_FILE', 'GIT_CEILING_DIRECTORIES',
        'GIT_DISCOVERY_ACROSS_FILESYSTEM', 'GIT_CONFIG', 'GIT_CONFIG_SYSTEM',
        'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM',
        'GIT_CONFIG_PARAMETERS', 'GIT_EXEC_PATH', 'GIT_SSH', 'GIT_SSH_COMMAND',
        'GIT_PROXY_COMMAND'
    )
    foreach ($name in $blockedNames) {
        if (Test-Path -LiteralPath "Env:$name") {
            throw "Super Push rejects ambient Git override: $name."
        }
    }

    # Hosts may disable credential prompts through Git's indexed environment
    # config. Accept only these two unique controls, never arbitrary overrides.
    $allowedNames = @()
    if (Test-Path Env:GIT_CONFIG_COUNT) {
        if ($env:GIT_CONFIG_COUNT -cnotmatch '^[012]$') {
            throw 'Super Push rejects ambient Git override: GIT_CONFIG_COUNT.'
        }
        $seenKeys = @()
        for ($index = 0; $index -lt [int]$env:GIT_CONFIG_COUNT; $index++) {
            $keyName = "GIT_CONFIG_KEY_$index"
            $valueName = "GIT_CONFIG_VALUE_$index"
            $key = [Environment]::GetEnvironmentVariable($keyName)
            $value = [Environment]::GetEnvironmentVariable($valueName)
            if ($key -notin @('credential.interactive', 'credential.guiPrompt') -or $key -in $seenKeys) {
                throw "Super Push rejects ambient Git override: $keyName."
            }
            $disabledValues = @('false', '0')
            if ($key -ieq 'credential.interactive') { $disabledValues += 'never' }
            if ($value -notin $disabledValues) {
                throw "Super Push rejects ambient Git override: $valueName."
            }
            $seenKeys += $key
            $allowedNames += $keyName, $valueName
        }
    }

    $generatedConfig = Get-ChildItem Env: | Where-Object {
        ($_.Name -like 'GIT_CONFIG_KEY_*' -or $_.Name -like 'GIT_CONFIG_VALUE_*') -and
        $_.Name -cnotin $allowedNames
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
    Write-Host "Repository:  $(Protect-SuperPushText $State.Repository)"
    Write-Host "Target ref:  $(Protect-SuperPushText $State.TargetRef)"
    Write-Host "Remote SHA:  $(Protect-SuperPushText $State.OldSha)"
    Write-Host "Candidate:   $(Protect-SuperPushText $State.NewSha)"
    Write-Host 'Ancestry:    verified fast-forward'
    Write-Host 'Local hooks: disabled for credential isolation'
    Write-Host ''
    Write-Host 'Commits:'
    (Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'log', '--format=%H%x09%s',
        "$($State.OldSha)..$($State.NewSha)"
    )).Output | ForEach-Object { Write-Host (Protect-SuperPushText $_) }
    Write-Host ''
    Write-Host 'Diff stat:'
    (Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'diff', '--stat', '--no-ext-diff',
        $State.OldSha, $State.NewSha
    )).Output | ForEach-Object { Write-Host (Protect-SuperPushText $_) }
    Write-Host ''
    Write-Host 'Changed files:'
    (Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'diff', '--name-status', '--no-ext-diff',
        $State.OldSha, $State.NewSha
    )).Output | ForEach-Object { Write-Host (Protect-SuperPushText $_) }
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

function Test-SuperPushDocumentationOnly {
    param([Parameter(Mandatory)][psobject]$State)

    $raw = Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'diff', '--raw', '-z', '--no-abbrev', '--no-ext-diff',
        '--no-renames',
        $State.OldSha, $State.NewSha
    )
    $entries = ($raw.Output -join '').Split([char]0)
    if ($entries.Count -lt 2 -or $entries[-1] -ne '') { return $false }

    $count = 0
    for ($index = 0; $index -lt $entries.Count - 1; $index += 2) {
        $header = $entries[$index]
        $path = $entries[$index + 1]
        if ($header -notmatch '^:(?<oldMode>\d{6}) (?<newMode>\d{6}) [0-9a-f]{40,64} [0-9a-f]{40,64} (?<status>[AMD])$') {
            return $false
        }

        $validMode = switch ($Matches.status) {
            'A' { $Matches.oldMode -ceq '000000' -and $Matches.newMode -ceq '100644' }
            'D' { $Matches.oldMode -ceq '100644' -and $Matches.newMode -ceq '000000' }
            'M' { $Matches.oldMode -ceq '100644' -and $Matches.newMode -ceq '100644' }
        }
        if (-not $validMode -or [string]::IsNullOrWhiteSpace($path) -or
            $path -match '[\x00-\x1F\x7F]' -or $path -imatch '(^|/)AGENTS\.md$') { return $false }

        $documentPath = $path -cmatch '^docs/.+' -or
            $path -cmatch '^openspec/.+' -or
            $path -cmatch '^(README|CHANGELOG|CONTRIBUTING|SECURITY|LICENSE)(?:\.[A-Za-z0-9][A-Za-z0-9._-]*)?(?:-[A-Za-z0-9][A-Za-z0-9._-]*)?$'
        if (-not $documentPath) { return $false }
        $count++
    }
    if ($count -eq 0) { return $false }

    $numstat = Invoke-GitCommand -Arguments @(
        '-C', $State.Root, 'diff', '--numstat', '-z', '--no-ext-diff',
        '--no-renames',
        $State.OldSha, $State.NewSha
    )
    $numstatEntries = ($numstat.Output -join '').Split([char]0)
    if ($numstatEntries.Count -lt 2 -or $numstatEntries[-1] -ne '' -or
        ($numstatEntries.Count - 1) -ne $count) { return $false }
    foreach ($entry in $numstatEntries[0..($numstatEntries.Count - 2)]) {
        if ($entry.StartsWith("-`t-") -or $entry -notmatch '^\d+\t\d+\t') { return $false }
    }

    $true
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
        Add-SuperPushDiagnostic "Provider=1Password Exit=$LASTEXITCODE response text omitted"
        throw "1Password command failed while resolving $script:SuperPushItem."
    }
    try {
        $output -join "`n" | Microsoft.PowerShell.Utility\ConvertFrom-Json -Depth 20
    }
    catch {
        Add-SuperPushDiagnostic 'Provider=1Password metadata=malformed response text omitted'
        throw "1Password returned malformed metadata for $script:SuperPushItem."
    }
}

function Get-SuperPushAppCredential {
    if ([string]::IsNullOrWhiteSpace($env:OP_SERVICE_ACCOUNT_TOKEN)) {
        throw 'Super Push requires Local Automation through OP_SERVICE_ACCOUNT_TOKEN; desktop authentication is not supported.'
    }

    $previousBiometric = $env:OP_BIOMETRIC_UNLOCK_ENABLED
    try {
        $env:OP_BIOMETRIC_UNLOCK_ENABLED = 'false'
        $item = Invoke-OnePasswordJson @(
            'item', 'get', $script:SuperPushItemId,
            '--vault', $script:SuperPushVault, '--format', 'json', '--reveal'
        )
        foreach ($field in $item.fields) {
            if ($field.PSObject.Properties.Name -contains 'value') { Add-SuperPushSecret $field.value }
        }
        if ($item.id -cne $script:SuperPushItemId) {
            throw '1Password did not return the canonical item for Super Push.'
        }
        if ($item.vault.id -cne $script:SuperPushVault) {
            throw 'The Super Push App credential must be stored in the fixed Automation vault.'
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
    finally {
        $env:OP_BIOMETRIC_UNLOCK_ENABLED = $previousBiometric
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
        $responseProperty = $_.Exception.PSObject.Properties['Response']
        if ($null -ne $responseProperty -and $null -ne $responseProperty.Value -and
            $responseProperty.Value.PSObject.Properties.Name -contains 'StatusCode') {
            $status = [int]$responseProperty.Value.StatusCode
        }
        $safePath = if ($Path -cmatch '^/(installation/token|repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/installation|app/installations/[0-9]+/access_tokens)$') { $Path } else { '[unrecognized endpoint]' }
        Add-SuperPushDiagnostic "Provider=GitHub Method=$Method Path=$safePath HTTP=$status response text omitted"
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
    Add-SuperPushSecret $jwt
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
        Add-SuperPushSecret $grant.token
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

    Add-SuperPushSecret $Token
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x-access-token:$Token"))
    Add-SuperPushSecret $basic
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
    }

    try {
        foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $null) }
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
        $restoreFailures = @()
        foreach ($name in $environmentNames) {
            try {
                if ($null -eq $previous[$name]) {
                    if (Test-Path -LiteralPath "Env:$name") { Remove-Item -LiteralPath "Env:$name" -ErrorAction Stop }
                } else { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
            }
            catch {
                # Continue restoring the remaining entries, without including
                # credential-bearing values or arbitrary exception messages.
                $restoreFailures += $name
            }
        }
        if ($restoreFailures.Count) {
            $message = "Git environment cleanup failed for: $($restoreFailures -join ', ')."
            Add-SuperPushDiagnostic $message
            throw $message
        }
        Add-SuperPushDiagnostic 'Cleanup Phase=git-environment outcome=restored'
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
    and exact interactive confirmation. Reads its App credential from the fixed
    Automation vault using OP_SERVICE_ACCOUNT_TOKEN, with no desktop 1Password
    fallback. The cmdlet accepts no custom parameters.

    .EXAMPLE
    Invoke-SuperPush
    #>
    [CmdletBinding()]
    param()

    $previousDiagnostics = $script:SuperPushDiagnostics
    $script:SuperPushDiagnostics = @{
        Phase = 'preflight'
        Lines = [Collections.Generic.List[string]]::new()
        Secrets = [Collections.Generic.List[string]]::new()
    }
    Add-SuperPushSecret $env:OP_SERVICE_ACCOUNT_TOKEN
    $cwd = Protect-SuperPushText (Get-Location).ProviderPath
    Add-SuperPushDiagnostic "InvocationCwd=$cwd Time=$([DateTimeOffset]::UtcNow.ToString('o'))"
    $confirmed = $null
    $credential = $null
    $grant = $null
    $failure = $null
    $failurePhase = $null
    $pushConfirmed = $false
    $pushAttempted = $false
    $revocationConfirmed = $false
    $diagnosticPath = $null
    try {
        $confirmed = Get-SuperPushState
        $script:SuperPushDiagnostics.Phase = 'evidence'
        Show-SuperPushEvidence $confirmed
        $script:SuperPushDiagnostics.Phase = 'confirmation'
        if (-not (Test-SuperPushDocumentationOnly $confirmed)) { Confirm-SuperPush }
        $script:SuperPushDiagnostics.Phase = 'pre-credential'
        $beforeCredential = Get-SuperPushState
        Assert-UnchangedState $confirmed $beforeCredential

        $script:SuperPushDiagnostics.Phase = 'credential'
        $credential = Get-SuperPushAppCredential
        Add-SuperPushSecret $credential.PrivateKey
        $script:SuperPushDiagnostics.Phase = 'token'
        $grant = New-SuperPushToken `
            $beforeCredential.Repository $credential.ClientId $credential.PrivateKey
        Add-SuperPushSecret $grant.token
        $credential.PrivateKey = $null
        $script:SuperPushDiagnostics.Phase = 'token-validation'
        Assert-SuperPushToken $grant $beforeCredential.Repository

        $script:SuperPushDiagnostics.Phase = 'pre-push'
        $beforePush = Get-SuperPushState
        Assert-UnchangedState $confirmed $beforePush
        $script:SuperPushDiagnostics.Phase = 'push'
        $pushAttempted = $true
        Invoke-SuperPushGit $beforePush $grant.token | Out-Null
        $pushConfirmed = $true
        $script:SuperPushDiagnostics.Phase = 'tracking-refresh'
        Update-SuperPushTrackingRef $beforePush
    }
    catch {
        $failurePhase = $script:SuperPushDiagnostics.Phase
        # Provider text may contain a not-yet-returned token/key. Retain phase
        # and exception type only at these boundaries, never arbitrary payloads.
        $failure = if ($failurePhase -in @('credential', 'token')) {
            "Provider operation failed ($($_.Exception.GetType().Name)); response text omitted."
        } else { Protect-SuperPushText $_.Exception.Message }
        Add-SuperPushDiagnostic "Failure Phase=$failurePhase $failure"
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
            $script:SuperPushDiagnostics.Phase = 'revocation'
            try {
                Remove-SuperPushToken $grant.token
                $revocationConfirmed = $true
                Add-SuperPushDiagnostic 'Cleanup Phase=revocation outcome=confirmed'
            }
            catch {
                $expiry = 'within one hour of minting'
                if ($grant.PSObject.Properties.Name -contains 'expires_at' -and
                    $grant.expires_at -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') {
                    $expiry = $grant.expires_at
                }
                $revokeFailure = "Token revocation failed ($($_.Exception.GetType().Name)); response text omitted; GitHub expiry is $expiry."
                Add-SuperPushDiagnostic "Cleanup Phase=revocation outcome=not-confirmed $revokeFailure"
                if (-not $failurePhase) { $failurePhase = 'revocation' }
                $failure = if ($failure) { "$failure $revokeFailure" } else { $revokeFailure }
            }
            finally { $grant.token = $null }
        }
        else { Add-SuperPushDiagnostic 'Cleanup Phase=revocation outcome=no-returned-token' }

        $pushStatus = if ($pushConfirmed) { 'accepted' } else { 'not-confirmed' }
        $phase = if ($failurePhase) { $failurePhase } else { 'complete' }
        $identity = if ($null -ne $confirmed) {
            "Repository=$($confirmed.Repository) Root=$($confirmed.Root) Ref=$($confirmed.TargetRef) Old=$($confirmed.OldSha) New=$($confirmed.NewSha)"
        } else { 'Repository=unknown Ref=refs/heads/main Old=unknown New=unknown' }
        $installationId = if ($null -ne $grant -and
            $grant.PSObject.Properties.Name -contains 'installation_id') { $grant.installation_id } else { 'unknown' }
        $audit = Protect-SuperPushText "Cwd=$cwd Phase=$phase $identity Installation=$installationId Push=$pushStatus Attempted=$pushAttempted Revoked=$revocationConfirmed Time=$([DateTimeOffset]::UtcNow.ToString('o'))"
        Add-SuperPushDiagnostic $audit
        if ($pushAttempted -and -not $pushConfirmed) {
            Add-SuperPushDiagnostic 'Push attempt outcome is unknown; do not retry without fresh reconciliation and approval.'
        }
        try {
            $diagnosticPath = Save-SuperPushDiagnostics
            $diagnosticPath = Protect-SuperPushText $diagnosticPath
            Write-Host "Diagnostics: $diagnosticPath"
        }
        catch {
            # Retention failure must not skip revocation or mask push uncertainty.
            $retentionFailure = "Diagnostic retention failed ($($_.Exception.GetType().Name)); no safe file confirmed."
            Write-Host $retentionFailure
            if (-not $failurePhase) { $audit = $audit.Replace('Phase=complete', 'Phase=retention') }
            $failure = if ($failure) { "$failure $retentionFailure" } else { $retentionFailure }
        }
        finally {
            $script:SuperPushDiagnostics.Secrets.Clear()
            $script:SuperPushDiagnostics = $previousDiagnostics
        }
    }

    if ($failure) {
        $uncertainty = if ($pushAttempted -and -not $pushConfirmed) { ' Push attempt outcome is unknown; fresh reconciliation and approval are required.' } else { '' }
        throw "Super Push failed. $audit. $failure$uncertainty Diagnostics=$diagnosticPath"
    }
    Write-Host "Super Push succeeded. $audit"
}
