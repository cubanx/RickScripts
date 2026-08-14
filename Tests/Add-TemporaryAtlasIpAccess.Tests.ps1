BeforeAll {
    . "$PSScriptRoot/../Functions/Add-TemporaryAtlasIpAccess.ps1"

    function atlas {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $script:AtlasCalls += ,$Arguments
        $command = switch ($Arguments[0]) {
            'accessLists' { "$($Arguments[0]) $($Arguments[1])" }
            'api' { "$($Arguments[0]) $($Arguments[1]) $($Arguments[2])" }
        }
        if ($script:AtlasCurrentIpDetectionFailure -and $command -eq 'accessLists create' -and $Arguments -contains '--currentIp') {
            $global:LASTEXITCODE = 1
            'Error: unable to find your public IP address. Specify the public IP address for this command'
            return
        }
        $exitCode = if ($script:AtlasExitCodes.ContainsKey($command)) {
            $script:AtlasExitCodes[$command]
        }
        else {
            $script:AtlasExitCode
        }
        $global:LASTEXITCODE = $exitCode
        if ($exitCode -ne 0) { return }

        switch ($command) {
            'accessLists create' {
                $reportedIp = if ($Arguments -contains '--currentIp') { '203.0.113.42' } else { $Arguments[2] }
                ConvertTo-Json -InputObject @{ results = @(@{ ipAddress = $reportedIp }) } -Compress
            }
            'api serviceAccounts listAccessList' { $script:ServiceAccountListJson }
            'api serviceAccounts createAccessList' {
                $fileIndex = [Array]::IndexOf($Arguments, '--file')
                $script:ServiceAccountRequest = Get-Content -LiteralPath $Arguments[$fileIndex + 1] -Raw
                $script:ServiceAccountCreateJson
            }
        }
    }
}

Describe 'Add-TemporaryAtlasIpAccess' {
    BeforeEach {
        $script:AtlasCalls = @()
        $script:AtlasExitCode = 0
        $script:AtlasExitCodes = @{}
        $script:AtlasCurrentIpDetectionFailure = $false
        $script:ServiceAccountListJson = '{"results":[]}'
        $script:ServiceAccountCreateJson = '{"results":[{"ipAddress":"203.0.113.42","createdAt":"2026-08-08T17:00:00Z"}]}'
        $script:ServiceAccountRequest = $null
        $script:TemporaryAtlasIpAccessStatePath = Join-Path $TestDrive "$([guid]::NewGuid()).json"
        Mock Invoke-RestMethod { throw 'Unexpected public-IP fallback.' }
    }

    It 'targets one explicit project with the current IP for eight hours by default' {
        $startedAt = [DateTimeOffset]::UtcNow

        $result = Add-TemporaryAtlasIpAccess -ProjectId 'project-deep-space-nine'

        $call = $script:AtlasCalls[0]
        @($script:AtlasCalls).Count | Should -Be 1
        Should -Invoke Invoke-RestMethod -Times 0
        @($call).Count | Should -Be 9
        $call[0..3] -join ' ' | Should -Be 'accessLists create --currentIp --deleteAfter'
        $call[5..6] -join ' ' | Should -Be '--projectId project-deep-space-nine'
        $call[7..8] -join ' ' | Should -Be '--output json'
        $call | Should -Not -Contain '--profile'
        $result | Should -Be '203.0.113.42'
        $expiry = [DateTimeOffset]::Parse($call[4])
        ($expiry - $startedAt).TotalMinutes | Should -BeGreaterThan 479
        ($expiry - $startedAt).TotalMinutes | Should -BeLessThan 481
    }

    It 'uses configured hours and forwards the selected Atlas profile' {
        $startedAt = [DateTimeOffset]::UtcNow

        Add-TemporaryAtlasIpAccess -ProjectId 'project-minas-tirith' -Hours 24 -Profile 'gondor-network-admin' | Out-Null

        $call = $script:AtlasCalls[0]
        @($call).Count | Should -Be 11
        $call[5..10] -join ' ' | Should -Be '--projectId project-minas-tirith --output json --profile gondor-network-admin'
        $expiry = [DateTimeOffset]::Parse($call[4])
        ($expiry - $startedAt).TotalMinutes | Should -BeGreaterThan 1439
        ($expiry - $startedAt).TotalMinutes | Should -BeLessThan 1441
    }

    It 'requires a project ID and rejects expiry beyond the Atlas limit before invocation' {
        $projectParameter = (Get-Command Add-TemporaryAtlasIpAccess).Parameters.ProjectId.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }

        $projectParameter.Mandatory | Should -BeTrue
        { Add-TemporaryAtlasIpAccess -ProjectId 'project-deadwood' -Hours 169 } | Should -Throw
        @($script:AtlasCalls).Count | Should -Be 0
    }

    It 'is exported by the module manifest' {
        $manifest = Import-PowerShellDataFile "$PSScriptRoot/../RickScripts.psd1"

        $manifest.FunctionsToExport | Should -Contain 'Add-TemporaryAtlasIpAccess'
    }

    It 'throws an actionable sanitized error when Atlas fails' {
        $script:AtlasExitCode = 23

        try {
            Add-TemporaryAtlasIpAccess -ProjectId 'project-cardassia' -Profile 'federation-network-admin' | Out-Null
            throw 'Expected Add-TemporaryAtlasIpAccess to fail.'
        }
        catch {
            $_.Exception.Message | Should -Match 'project-cardassia'
            $_.Exception.Message | Should -Match 'exit code 23'
            $_.Exception.Message | Should -Match 'authentication'
            $_.Exception.Message | Should -Match 'Project Network Access Manager'
        }

        @($script:AtlasCalls).Count | Should -Be 1
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'adds the Atlas-reported IP to one explicit project service account and records it locally' {
        $clientId = 'mdb_sa_id_0123456789abcdef01234567'

        $result = Add-TemporaryAtlasIpAccess -ProjectId 'project-bajor' -ServiceAccountClientId $clientId -Profile 'federation-access-manager'

        @($script:AtlasCalls).Count | Should -Be 3
        $script:AtlasCalls[1] -join ' ' | Should -Be "api serviceAccounts listAccessList --clientId $clientId --groupId project-bajor --output json --profile federation-access-manager"
        $script:AtlasCalls[2][0..6] -join ' ' | Should -Be "api serviceAccounts createAccessList --clientId $clientId --groupId project-bajor"
        $script:AtlasCalls[2] | Should -Contain '--file'
        $script:AtlasCalls[2][-4..-1] -join ' ' | Should -Be '--output json --profile federation-access-manager'
        $script:ServiceAccountRequest | Should -Be '[{"ipAddress":"203.0.113.42"}]'
        $result | Should -Be '203.0.113.42'

        $record = @(Get-Content -LiteralPath $script:TemporaryAtlasIpAccessStatePath -Raw | ConvertFrom-Json)[0]
        $record.projectId | Should -Be 'project-bajor'
        $record.serviceAccountClientId | Should -Be $clientId
        $record.ipAddress | Should -Be '203.0.113.42'
        ([DateTimeOffset]$record.createdAt).ToUniversalTime() | Should -Be ([DateTimeOffset]::Parse('2026-08-08T17:00:00Z'))
        [DateTimeOffset]::Parse($record.expiresAt) | Should -BeGreaterThan ([DateTimeOffset]::UtcNow.AddHours(7))
        $record.PSObject.Properties.Name | Should -Not -Contain 'credential'
        $record.PSObject.Properties.Name | Should -Not -Contain 'accessToken'
    }

    It 'refuses to adopt an existing service-account IP as temporary' {
        $script:ServiceAccountListJson = '{"results":[{"ipAddress":"203.0.113.42","createdAt":"2025-01-01T00:00:00Z"}]}'

        {
            Add-TemporaryAtlasIpAccess -ProjectId 'project-rivendell' -ServiceAccountClientId 'mdb_sa_id_89abcdef0123456789abcdef'
        } | Should -Throw '*already exists*cannot safely*temporary*'

        @($script:AtlasCalls).Count | Should -Be 2
        Test-Path -LiteralPath $script:TemporaryAtlasIpAccessStatePath | Should -BeFalse
    }

    It 'throws an actionable error and writes no record when service-account creation fails' {
        $script:AtlasExitCodes['api serviceAccounts createAccessList'] = 29

        try {
            Add-TemporaryAtlasIpAccess -ProjectId 'project-cardassia' -ServiceAccountClientId 'mdb_sa_id_fedcba9876543210fedcba98' | Out-Null
            throw 'Expected service-account access creation to fail.'
        }
        catch {
            $_.Exception.Message | Should -Match 'project-cardassia'
            $_.Exception.Message | Should -Match 'exit code 29'
            $_.Exception.Message | Should -Match 'Project Access Manager'
        }

        @($script:AtlasCalls).Count | Should -Be 3
        Test-Path -LiteralPath $script:TemporaryAtlasIpAccessStatePath | Should -BeFalse
    }

    It 'falls back only after Atlas IP detection fails and reuses the validated IP for both access lists' {
        $clientId = 'mdb_sa_id_0123456789abcdef01234567'
        $script:AtlasCurrentIpDetectionFailure = $true
        $script:ServiceAccountCreateJson = '{"results":[{"ipAddress":"8.8.8.8","createdAt":"2026-08-08T17:00:00Z"}]}'
        Mock Invoke-RestMethod { ' 8.8.8.8 ' }

        $result = Add-TemporaryAtlasIpAccess -ProjectId 'project-bajor' -ServiceAccountClientId $clientId -Profile 'federation-access-manager'

        @($script:AtlasCalls).Count | Should -Be 4
        $script:AtlasCalls[0] | Should -Contain '--currentIp'
        $script:AtlasCalls[1][0..5] -join ' ' | Should -Be 'accessLists create 8.8.8.8 --type ipAddress --deleteAfter'
        $script:AtlasCalls[1][7..12] -join ' ' | Should -Be '--projectId project-bajor --output json --profile federation-access-manager'
        $script:AtlasCalls[1][6] | Should -Be $script:AtlasCalls[0][4]
        $script:ServiceAccountRequest | Should -Be '[{"ipAddress":"8.8.8.8"}]'
        $result | Should -Be '8.8.8.8'
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq 'https://api.ipify.org' -and $TimeoutSec -eq 10
        }
    }

    It 'does not retry when the fallback response is not a public IPv4 address' {
        $script:AtlasCurrentIpDetectionFailure = $true
        Mock Invoke-RestMethod { '192.168.1.42' }

        {
            Add-TemporaryAtlasIpAccess -ProjectId 'project-rivendell'
        } | Should -Throw '*api.ipify.org*valid public IPv4*'

        @($script:AtlasCalls).Count | Should -Be 1
    }

    It 'reports an actionable error when the fallback request fails' {
        $script:AtlasCurrentIpDetectionFailure = $true
        Mock Invoke-RestMethod { throw 'the wormhole collapsed' }

        {
            Add-TemporaryAtlasIpAccess -ProjectId 'project-deadwood'
        } | Should -Throw '*api.ipify.org*Check outbound HTTPS access*'

        @($script:AtlasCalls).Count | Should -Be 1
    }
}
