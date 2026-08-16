$script:TemporaryAtlasProjects = [ordered]@{
    '6a4d186f4f79ef136f23fc36' = 'internal-apps-preview'
    '6a4e8026f2e81bdf73451a18' = 'internal-apps-production'
}

function Get-TemporaryAtlasIpAccessStatePath {
    if ($script:TemporaryAtlasIpAccessStatePath) {
        return $script:TemporaryAtlasIpAccessStatePath
    }

    Join-Path $HOME '.RickScripts/temporary-atlas-ip-access.json'
}

function Read-TemporaryAtlasIpAccessState {
    $path = Get-TemporaryAtlasIpAccessStatePath
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }

    try {
        $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        @($json | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        throw "RickScripts temporary Atlas IP state at '$path' is unreadable. Repair or remove it before changing service-account access."
    }
}

function Write-TemporaryAtlasIpAccessState {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries)

    $path = Get-TemporaryAtlasIpAccessStatePath
    $directory = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = "$path.tmp"
    $json = ConvertTo-Json -InputObject @($Entries) -Depth 4

    # ponytail: single-operator state file; add locking if concurrent sessions become real.
    [System.IO.File]::WriteAllText($temporaryPath, $json)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
}

function Test-PublicIPv4Address {
    param([Parameter(Mandatory)][string]$Address)

    $parsedAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsedAddress) -or
        $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }

    $bytes = $parsedAddress.GetAddressBytes()
    -not (
        $bytes[0] -eq 0 -or
        $bytes[0] -eq 10 -or
        $bytes[0] -eq 127 -or
        ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) -or
        ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or
        ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and ($bytes[2] -eq 0 -or $bytes[2] -eq 2)) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
        ($bytes[0] -eq 198 -and ($bytes[1] -eq 18 -or $bytes[1] -eq 19)) -or
        ($bytes[0] -eq 198 -and $bytes[1] -eq 51 -and $bytes[2] -eq 100) -or
        ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and $bytes[2] -eq 113) -or
        $bytes[0] -ge 224
    )
}

function Add-TemporaryAtlasIpAccess {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ProjectId,

        [ValidateRange(1, 168)]
        [int]$Hours = 8,

        [ValidatePattern('^mdb_sa_id_[a-fA-F0-9]{24}$')]
        [string]$ServiceAccountClientId,

        [ValidateNotNullOrEmpty()]
        [string]$Profile
    )

    if (-not (Get-Command atlas -ErrorAction SilentlyContinue)) {
        throw "Atlas CLI ('atlas') is required. Install it and authenticate a profile with Project Network Access Manager access."
    }

    if (-not $ProjectId) {
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { throw "Required dependency 'fzf' was not found in PATH." }

        $projectName = $script:TemporaryAtlasProjects.Values | fzf --height 40% --reverse --prompt 'Pick an Atlas project: '
        if (-not $projectName) { return }
        $ProjectId = ($script:TemporaryAtlasProjects.GetEnumerator() | Where-Object Value -eq $projectName).Key
    }

    $deleteAfter = (Get-Date).ToUniversalTime().AddHours($Hours).ToString('o')
    $atlasArguments = @(
        'accessLists', 'create',
        '--currentIp',
        '--deleteAfter', $deleteAfter,
        '--projectId', $ProjectId,
        '--output', 'json'
    )

    if ($Profile) {
        $atlasArguments += '--profile', $Profile
    }

    $atlasOutput = & atlas @atlasArguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $atlasDiagnostic = ($atlasOutput | Out-String).Trim()
        $ipDetectionFailure = $atlasDiagnostic -match '(?is)(?:unable|not able) to find your public IP address\.\s*Specify the public IP address for this command'
        if (-not $ipDetectionFailure) {
            if ($atlasDiagnostic) { Write-Error -Message $atlasDiagnostic -ErrorAction Continue }
            throw "Atlas CLI failed to add temporary IP access to project '$ProjectId' (exit code $exitCode). Verify Atlas CLI authentication and Project Network Access Manager access for that project."
        }

        try {
            $fallbackIp = ([string](Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10 -ErrorAction Stop)).Trim()
        }
        catch {
            throw "Atlas CLI could not detect the public IP and RickScripts could not reach api.ipify.org. Check outbound HTTPS access and retry."
        }
        if (-not (Test-PublicIPv4Address -Address $fallbackIp)) {
            throw "Atlas CLI could not detect the public IP and api.ipify.org did not return a valid public IPv4 address. No explicit-IP Atlas mutation was attempted."
        }

        $fallbackArguments = @(
            'accessLists', 'create', $fallbackIp,
            '--type', 'ipAddress',
            '--deleteAfter', $deleteAfter,
            '--projectId', $ProjectId,
            '--output', 'json'
        )
        if ($Profile) {
            $fallbackArguments += '--profile', $Profile
        }
        $atlasOutput = & atlas @fallbackArguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $atlasDiagnostic = ($atlasOutput | Out-String).Trim()
            if ($atlasDiagnostic) { Write-Error -Message $atlasDiagnostic -ErrorAction Continue }
            throw "Atlas CLI failed to add fallback IP '$fallbackIp' to project '$ProjectId' (exit code $exitCode). Verify Atlas CLI authentication and Project Network Access Manager access for that project."
        }
    }

    try {
        $entry = $atlasOutput | Out-String | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Atlas CLI created temporary IP access for project '$ProjectId' but returned unreadable JSON."
    }

    $ipAddress = @($entry.results)[0].ipAddress
    if (-not $ipAddress) {
        throw "Atlas CLI created temporary IP access for project '$ProjectId' but did not report the IP address."
    }

    if (-not $ServiceAccountClientId) {
        return $ipAddress
    }

    $profileArguments = if ($Profile) { @('--profile', $Profile) } else { @() }
    $listArguments = @(
        'api', 'serviceAccounts', 'listAccessList',
        '--clientId', $ServiceAccountClientId,
        '--groupId', $ProjectId,
        '--output', 'json'
    ) + $profileArguments
    $serviceAccountOutput = & atlas @listArguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Atlas CLI failed to inspect service-account IP access for '$ServiceAccountClientId' in project '$ProjectId' (exit code $exitCode). Verify Atlas CLI authentication and Project Access Manager access."
    }

    try {
        $serviceAccountEntries = @((($serviceAccountOutput | Out-String) | ConvertFrom-Json -ErrorAction Stop).results)
    }
    catch {
        throw "Atlas CLI returned unreadable service-account access-list JSON for '$ServiceAccountClientId' in project '$ProjectId'."
    }

    if ($serviceAccountEntries | Where-Object { $_.ipAddress -eq $ipAddress }) {
        throw "IP address '$ipAddress' already exists for service account '$ServiceAccountClientId' in project '$ProjectId'; RickScripts cannot safely treat that existing entry as temporary."
    }

    $state = @(Read-TemporaryAtlasIpAccessState | Where-Object {
        -not ($_.projectId -eq $ProjectId -and $_.serviceAccountClientId -eq $ServiceAccountClientId -and $_.ipAddress -eq $ipAddress)
    })
    $requestPath = [System.IO.Path]::GetTempFileName()
    try {
        $request = ConvertTo-Json -InputObject @([pscustomobject]@{ ipAddress = $ipAddress }) -Compress
        [System.IO.File]::WriteAllText($requestPath, $request)
        $createArguments = @(
            'api', 'serviceAccounts', 'createAccessList',
            '--clientId', $ServiceAccountClientId,
            '--groupId', $ProjectId,
            '--file', $requestPath,
            '--output', 'json'
        ) + $profileArguments
        $createdOutput = & atlas @createArguments
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Atlas CLI failed to add IP '$ipAddress' to service account '$ServiceAccountClientId' in project '$ProjectId' (exit code $exitCode). Verify Atlas CLI authentication and Project Access Manager access."
        }
    }
    finally {
        Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
    }

    try {
        $createdEntry = @((($createdOutput | Out-String) | ConvertFrom-Json -ErrorAction Stop).results)[0]
    }
    catch {
        throw "Atlas CLI created service-account IP access for '$ServiceAccountClientId' in project '$ProjectId' but returned unreadable JSON. Remove the IP manually because it could not be tracked."
    }
    if (-not $createdEntry.createdAt -or $createdEntry.ipAddress -ne $ipAddress) {
        throw "Atlas CLI created service-account IP access for '$ServiceAccountClientId' in project '$ProjectId' but did not return matching identity metadata. Remove the IP manually because it could not be tracked."
    }

    $state += [pscustomobject]@{
        projectId             = $ProjectId
        serviceAccountClientId = $ServiceAccountClientId
        ipAddress             = $ipAddress
        createdAt             = $createdEntry.createdAt
        expiresAt             = $deleteAfter
    }
    try {
        Write-TemporaryAtlasIpAccessState -Entries $state
    }
    catch {
        throw "Atlas CLI created service-account IP access for '$ServiceAccountClientId' in project '$ProjectId', but RickScripts could not save its cleanup record. Remove IP '$ipAddress' manually. $($_.Exception.Message)"
    }

    $ipAddress
}
