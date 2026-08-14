function Remove-TemporaryAtlasIpAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectId,

        [ValidatePattern('^mdb_sa_id_[a-fA-F0-9]{24}$')]
        [string]$ServiceAccountClientId,

        [ValidateNotNullOrEmpty()]
        [string]$Profile
    )

    if (-not (Get-Command atlas -ErrorAction SilentlyContinue)) {
        throw "Atlas CLI ('atlas') is required. Install it and authenticate a profile with the required project access."
    }

    $profileArguments = if ($Profile) { @('--profile', $Profile) } else { @() }
    $listArguments = @('accessLists', 'list', '--projectId', $ProjectId, '--output', 'json') + $profileArguments
    $databaseOutput = & atlas @listArguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Atlas CLI failed to inspect database IP access for project '$ProjectId' (exit code $exitCode). Verify Atlas CLI authentication and Project Network Access Manager access."
    }

    try {
        $databaseEntries = @((($databaseOutput | Out-String) | ConvertFrom-Json -ErrorAction Stop).results)
    }
    catch {
        throw "Atlas CLI returned unreadable database access-list JSON for project '$ProjectId'."
    }

    foreach ($entry in @($databaseEntries | Where-Object { $_.deleteAfterDate })) {
        $identifier = if ($entry.ipAddress) { $entry.ipAddress } elseif ($entry.cidrBlock) { $entry.cidrBlock } else { $entry.awsSecurityGroup }
        if (-not $identifier) {
            throw "Atlas reported a temporary database access-list entry without a removable identifier for project '$ProjectId'."
        }

        $deleteArguments = @('accessLists', 'delete', $identifier, '--projectId', $ProjectId, '--force') + $profileArguments
        & atlas @deleteArguments | Out-Null
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Atlas CLI failed to remove temporary database IP access '$identifier' from project '$ProjectId' (exit code $exitCode). Verify Atlas CLI authentication and Project Network Access Manager access."
        }
        $identifier
    }

    if (-not $ServiceAccountClientId) { return }

    $state = @(Read-TemporaryAtlasIpAccessState)
    $records = @($state | Where-Object {
        $_.projectId -eq $ProjectId -and $_.serviceAccountClientId -eq $ServiceAccountClientId
    })
    if ($records.Count -eq 0) { return }

    $serviceListArguments = @(
        'api', 'serviceAccounts', 'listAccessList',
        '--clientId', $ServiceAccountClientId,
        '--groupId', $ProjectId,
        '--output', 'json'
    ) + $profileArguments
    $serviceOutput = & atlas @serviceListArguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Atlas CLI failed to inspect service-account IP access for '$ServiceAccountClientId' in project '$ProjectId' (exit code $exitCode). Verify Atlas CLI authentication and Project Access Manager access."
    }

    try {
        $serviceEntries = @((($serviceOutput | Out-String) | ConvertFrom-Json -ErrorAction Stop).results)
    }
    catch {
        throw "Atlas CLI returned unreadable service-account access-list JSON for '$ServiceAccountClientId' in project '$ProjectId'."
    }

    $removedRecords = @()
    foreach ($record in $records) {
        if (-not $record.ipAddress -or -not $record.createdAt) {
            throw "RickScripts has an incomplete cleanup record for service account '$ServiceAccountClientId' in project '$ProjectId'; refusing to delete any service-account entry."
        }

        $sameIpEntries = @($serviceEntries | Where-Object { $_.ipAddress -eq $record.ipAddress })
        $matchingEntry = @($sameIpEntries | Where-Object {
            try {
                ([DateTimeOffset]$_.createdAt).ToUniversalTime() -eq ([DateTimeOffset]$record.createdAt).ToUniversalTime()
            }
            catch { $false }
        }) | Select-Object -First 1

        if (-not $matchingEntry) {
            if ($sameIpEntries.Count -gt 0) {
                throw "Service-account IP '$($record.ipAddress)' has a different Atlas creation timestamp; refusing to delete an entry RickScripts cannot prove it created."
            }
            $removedRecords += $record
            continue
        }

        $deleteArguments = @(
            'api', 'serviceAccounts', 'deleteGroupAccessEntry',
            '--clientId', $ServiceAccountClientId,
            '--groupId', $ProjectId,
            '--ipAddress', $record.ipAddress
        ) + $profileArguments
        & atlas @deleteArguments | Out-Null
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Atlas CLI failed to remove tracked service-account IP '$($record.ipAddress)' for '$ServiceAccountClientId' in project '$ProjectId' (exit code $exitCode). Verify Atlas CLI authentication and Project Access Manager access. The local cleanup record was retained."
        }
        $removedRecords += $record
        $record.ipAddress
    }

    if ($removedRecords.Count -gt 0) {
        $remaining = @($state | Where-Object { $removedRecords -notcontains $_ })
        Write-TemporaryAtlasIpAccessState -Entries $remaining
    }
}
