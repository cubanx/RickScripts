BeforeAll {
    . "$PSScriptRoot/../Functions/Add-TemporaryAtlasIpAccess.ps1"
    . "$PSScriptRoot/../Functions/Remove-TemporaryAtlasIpAccess.ps1"

    function atlas {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $script:AtlasCalls += ,$Arguments
        $command = switch ($Arguments[0]) {
            'accessLists' { "$($Arguments[0]) $($Arguments[1])" }
            'api' { "$($Arguments[0]) $($Arguments[1]) $($Arguments[2])" }
        }
        $exitCode = if ($script:AtlasExitCodes.ContainsKey($command)) { $script:AtlasExitCodes[$command] } else { 0 }
        $global:LASTEXITCODE = $exitCode
        if ($exitCode -ne 0) { return }

        switch ($command) {
            'accessLists list' { $script:DatabaseAccessListJson }
            'api serviceAccounts listAccessList' { $script:ServiceAccountListJson }
        }
    }
}

Describe 'Remove-TemporaryAtlasIpAccess' {
    BeforeEach {
        $script:AtlasCalls = @()
        $script:AtlasExitCodes = @{}
        $script:DatabaseAccessListJson = '{"results":[]}'
        $script:ServiceAccountListJson = '{"results":[]}'
        $script:TemporaryAtlasIpAccessStatePath = Join-Path $TestDrive "$([guid]::NewGuid()).json"
    }

    It 'deletes every native temporary database entry and leaves permanent entries alone' {
        $script:DatabaseAccessListJson = '{"results":[{"cidrBlock":"203.0.113.42/32","deleteAfterDate":"2026-08-09T01:00:00Z"},{"cidrBlock":"198.51.100.8/32","deleteAfterDate":null}]}'

        $result = Remove-TemporaryAtlasIpAccess -ProjectId 'project-deep-space-nine' -Profile 'federation-network-admin'

        @($script:AtlasCalls).Count | Should -Be 2
        $script:AtlasCalls[0] -join ' ' | Should -Be 'accessLists list --projectId project-deep-space-nine --output json --profile federation-network-admin'
        $script:AtlasCalls[1] -join ' ' | Should -Be 'accessLists delete 203.0.113.42/32 --projectId project-deep-space-nine --force --profile federation-network-admin'
        $result | Should -Be '203.0.113.42/32'
        ($script:AtlasCalls -join ' ') | Should -Not -Match '198\.51\.100\.8'
    }

    It 'deletes only a locally tracked service-account entry whose Atlas identity matches' {
        $clientId = 'mdb_sa_id_0123456789abcdef01234567'
        @(
            [pscustomobject]@{ projectId = 'project-bajor'; serviceAccountClientId = $clientId; ipAddress = '203.0.113.42'; createdAt = '2026-08-08T17:00:00Z'; expiresAt = '2026-08-09T01:00:00Z' },
            [pscustomobject]@{ projectId = 'project-minas-tirith'; serviceAccountClientId = 'mdb_sa_id_89abcdef0123456789abcdef'; ipAddress = '198.51.100.8'; createdAt = '2026-08-08T16:00:00Z'; expiresAt = '2026-08-09T00:00:00Z' }
        ) | ConvertTo-Json | Set-Content -LiteralPath $script:TemporaryAtlasIpAccessStatePath
        $script:ServiceAccountListJson = '{"results":[{"ipAddress":"203.0.113.42","createdAt":"2026-08-08T17:00:00Z"},{"ipAddress":"192.0.2.10","createdAt":"2026-08-08T16:30:00Z"}]}'

        $result = Remove-TemporaryAtlasIpAccess -ProjectId 'project-bajor' -ServiceAccountClientId $clientId -Profile 'federation-access-manager'

        @($script:AtlasCalls).Count | Should -Be 3
        $script:AtlasCalls[1] -join ' ' | Should -Be "api serviceAccounts listAccessList --clientId $clientId --groupId project-bajor --output json --profile federation-access-manager"
        $script:AtlasCalls[2] -join ' ' | Should -Be "api serviceAccounts deleteGroupAccessEntry --clientId $clientId --groupId project-bajor --ipAddress 203.0.113.42 --profile federation-access-manager"
        $result | Should -Be '203.0.113.42'
        $remaining = @(Get-Content -LiteralPath $script:TemporaryAtlasIpAccessStatePath -Raw | ConvertFrom-Json)
        $remaining.Count | Should -Be 1
        $remaining[0].projectId | Should -Be 'project-minas-tirith'
    }

    It 'refuses to delete an IP recreated at a different time and retains the record' {
        $clientId = 'mdb_sa_id_0123456789abcdef01234567'
        [pscustomobject]@{ projectId = 'project-bajor'; serviceAccountClientId = $clientId; ipAddress = '203.0.113.42'; createdAt = '2026-08-08T17:00:00Z'; expiresAt = '2026-08-09T01:00:00Z' } |
            ConvertTo-Json | Set-Content -LiteralPath $script:TemporaryAtlasIpAccessStatePath
        $script:ServiceAccountListJson = '{"results":[{"ipAddress":"203.0.113.42","createdAt":"2026-08-08T18:00:00Z"}]}'

        {
            Remove-TemporaryAtlasIpAccess -ProjectId 'project-bajor' -ServiceAccountClientId $clientId
        } | Should -Throw '*creation timestamp*refusing*'

        @($script:AtlasCalls).Count | Should -Be 2
        (Get-Content -LiteralPath $script:TemporaryAtlasIpAccessStatePath -Raw) | Should -Match '203.0.113.42'
    }

    It 'retains the local record when native service-account deletion fails' {
        $clientId = 'mdb_sa_id_0123456789abcdef01234567'
        [pscustomobject]@{ projectId = 'project-bajor'; serviceAccountClientId = $clientId; ipAddress = '203.0.113.42'; createdAt = '2026-08-08T17:00:00Z'; expiresAt = '2026-08-09T01:00:00Z' } |
            ConvertTo-Json | Set-Content -LiteralPath $script:TemporaryAtlasIpAccessStatePath
        $script:ServiceAccountListJson = '{"results":[{"ipAddress":"203.0.113.42","createdAt":"2026-08-08T17:00:00Z"}]}'
        $script:AtlasExitCodes['api serviceAccounts deleteGroupAccessEntry'] = 41

        {
            Remove-TemporaryAtlasIpAccess -ProjectId 'project-bajor' -ServiceAccountClientId $clientId
        } | Should -Throw '*exit code 41*Project Access Manager*'

        (Get-Content -LiteralPath $script:TemporaryAtlasIpAccessStatePath -Raw) | Should -Match '203.0.113.42'
    }

    It 'requires a project ID and is exported by the module manifest' {
        $projectParameter = (Get-Command Remove-TemporaryAtlasIpAccess).Parameters.ProjectId.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        $manifest = Import-PowerShellDataFile "$PSScriptRoot/../RickScripts.psd1"

        $projectParameter.Mandatory | Should -BeTrue
        $manifest.FunctionsToExport | Should -Contain 'Remove-TemporaryAtlasIpAccess'
    }
}
