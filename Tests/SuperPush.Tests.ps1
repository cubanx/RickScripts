Describe 'Invoke-SuperPush safety boundary' {
    BeforeAll {
        $functionPath = Join-Path $PSScriptRoot '../Functions/Invoke-SuperPush.ps1'
        Test-Path -LiteralPath $functionPath | Should -BeTrue
        $module = Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force -PassThru
        $script:ExportedCommands = @($module.ExportedCommands.Keys)
        Remove-Module $module -Force
        . $functionPath
        $script:GitExecutable = '/usr/bin/git'

        function New-TestSuperPushState {
            [pscustomobject]@{
                Repository = 'Crisp-Inc/internal-apps'
                Root = '/tmp/internal-apps'
                Origin = 'git@github.com:Crisp-Inc/internal-apps.git'
                TargetRef = 'refs/heads/main'
                OldSha = '1111111111111111111111111111111111111111'
                NewSha = '2222222222222222222222222222222222222222'
            }
        }

        function New-TestSuperPushGrant {
            [pscustomobject]@{
                token = 'fake-token'
                expires_at = '2099-01-01T00:00:00Z'
                repository_selection = 'selected'
                permissions = [pscustomobject]@{ contents = 'write' }
                repositories = @([pscustomobject]@{ full_name = 'Crisp-Inc/internal-apps' })
                installation_id = 1701
            }
        }
    }

    It 'exports a no-argument advanced function' {
        $script:ExportedCommands | Should -Contain 'Invoke-SuperPush'
        $command = Get-Command Invoke-SuperPush -CommandType Function
        $command.CmdletBinding | Should -BeTrue
        foreach ($parameter in 'Repository', 'Ref', 'Force', 'Credential', 'Yes', 'Confirm') {
            $command.Parameters.Keys | Should -Not -Contain $parameter
        }
        foreach ($helper in 'Get-SuperPushState', 'Get-SuperPushAppCredential', 'New-SuperPushToken', 'Invoke-SuperPushGit') {
            $script:ExportedCommands | Should -Not -Contain $helper
        }
    }

    It 'accepts only supported Crisp GitHub origins' {
        Get-CrispRepository 'git@github.com:Crisp-Inc/internal-apps.git' | Should -Be 'Crisp-Inc/internal-apps'
        Get-CrispRepository 'https://github.com/Crisp-Inc/data-warehouse.git' | Should -Be 'Crisp-Inc/data-warehouse'
        Get-CrispRepository 'ssh://git@github.com/Crisp-Inc/external-api.git' | Should -Be 'Crisp-Inc/external-api'

        { Get-CrispRepository 'git@github.com:somebody/internal-apps.git' } | Should -Throw
        { Get-CrispRepository 'https://example.com/Crisp-Inc/internal-apps.git' } | Should -Throw
    }

    It 'fixes the ref, confirmation, and one non-force push shape' {
        $sha = '0123456789abcdef0123456789abcdef01234567'

        Get-SuperPushConfirmation 'Crisp-Inc/internal-apps' $sha |
            Should -Be "SUPER PUSH Crisp-Inc/internal-apps $sha TO refs/heads/main"
        Test-SuperPushConfirmation `
            "SUPER PUSH Crisp-Inc/internal-apps $sha TO refs/heads/main" `
            (Get-SuperPushConfirmation 'Crisp-Inc/internal-apps' $sha) | Should -BeTrue
        Test-SuperPushConfirmation `
            "super push Crisp-Inc/internal-apps $sha TO refs/heads/main" `
            (Get-SuperPushConfirmation 'Crisp-Inc/internal-apps' $sha) | Should -BeFalse

        $arguments = Get-SuperPushArguments '/tmp/internal-apps' 'Crisp-Inc/internal-apps' $sha
        $arguments | Should -Be @(
            '-C', '/tmp/internal-apps', 'push', '--porcelain', '--no-verify',
            'https://github.com/Crisp-Inc/internal-apps.git',
            "$sha`:refs/heads/main"
        )
        ($arguments -join ' ') | Should -Not -Match '(?:^|\s)--force(?:-with-lease)?(?:\s|$)'
    }

    It 'rejects dirty, equal, and drifted state' {
        { Assert-CleanWorktree ' M promenade.txt' } | Should -Throw
        { Assert-DistinctCommits 'same' 'same' } | Should -Throw

        $before = [pscustomobject]@{
            Repository = 'Crisp-Inc/internal-apps'
            Root = '/tmp/internal-apps'
            Origin = 'git@github.com:Crisp-Inc/internal-apps.git'
            TargetRef = 'refs/heads/main'
            OldSha = 'old'
            NewSha = 'new'
        }
        $after = $before.PSObject.Copy()
        $after.OldSha = 'moved'
        { Assert-UnchangedState $before $after } | Should -Throw '*OldSha*'
    }

    It 'rejects ambient Git repository and config overrides' {
        $previous = $env:GIT_DIR
        try {
            $env:GIT_DIR = '/tmp/not-the-checkout'
            { Assert-SafeGitEnvironment } | Should -Throw '*GIT_DIR*'
        }
        finally {
            $env:GIT_DIR = $previous
        }
    }

    It 'rejects URL rewrites and token-sensitive HTTP config' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) "rickscripts-super-push-config-$([guid]::NewGuid())"
        try {
            New-Item -ItemType Directory -Path $root | Out-Null
            & $script:GitExecutable -C $root init --quiet
            & $script:GitExecutable -C $root config --local http.extraHeader 'not-a-real-secret'
            { Assert-SafeGitConfig $root } | Should -Throw '*token-sensitive HTTP*'

            & $script:GitExecutable -C $root config --unset-all http.extraHeader
            & $script:GitExecutable -C $root config --local 'url.ssh://example/.insteadOf' 'https://github.com/'
            { Assert-SafeGitConfig $root } | Should -Throw '*URL rewrites*'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'shows immutable raw evidence and disabled hooks' {
        $script:HostOutput = @()
        Mock Write-Host {
            param([Parameter(Position = 0, ValueFromRemainingArguments)][object[]]$Object)
            $script:HostOutput += $Object -join ' '
        }
        Mock Invoke-GitCommand {
            param([string[]]$Arguments)
            $command = $Arguments -join ' '
            if ($command -like '* log *') { return [pscustomobject]@{ ExitCode = 0; Output = @('abc1234 Ready the Defiant') } }
            if ($command -like '* diff --stat *') { return [pscustomobject]@{ ExitCode = 0; Output = @(' promenade.txt | 1 +') } }
            if ($command -like '* diff --no-color *') { return [pscustomobject]@{ ExitCode = 0; Output = @('+raw diff line') } }
            throw "Unexpected Git command: $command"
        }
        $state = New-TestSuperPushState

        Show-SuperPushEvidence $state

        $output = $script:HostOutput -join "`n"
        foreach ($expected in @(
            $state.Repository, $state.TargetRef, $state.OldSha, $state.NewSha,
            'verified fast-forward', 'Local hooks: disabled',
            'abc1234 Ready the Defiant', 'promenade.txt | 1 +', '+raw diff line'
        )) {
            $output | Should -Match ([regex]::Escape($expected))
        }
    }

    It 'uses a temporary local repository to verify ancestry' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) "rickscripts-super-push-$([guid]::NewGuid())"
        try {
            New-Item -ItemType Directory -Path $root | Out-Null
            & $script:GitExecutable -C $root init --quiet
            [IO.File]::WriteAllText((Join-Path $root 'quark.txt'), "latinum`n")
            & $script:GitExecutable -C $root add quark.txt
            & $script:GitExecutable -C $root -c user.name='Benjamin Sisko' -c user.email='sisko@example.test' commit --quiet -m 'Add latinum'
            $old = & $script:GitExecutable -C $root rev-parse HEAD
            [IO.File]::AppendAllText((Join-Path $root 'quark.txt'), "more latinum`n")
            & $script:GitExecutable -C $root add quark.txt
            & $script:GitExecutable -C $root -c user.name='Benjamin Sisko' -c user.email='sisko@example.test' commit --quiet -m 'Add more latinum'
            $new = & $script:GitExecutable -C $root rev-parse HEAD

            Test-FastForward $root $old $new | Should -BeTrue
            Test-FastForward $root $new $old | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'accepts only selected Crisp installations with narrow permissions' {
        $valid = [pscustomobject]@{
            id = 1701
            repository_selection = 'selected'
            account = [pscustomobject]@{ login = 'Crisp-Inc' }
            permissions = [pscustomobject]@{ contents = 'write'; metadata = 'read' }
        }
        { Assert-SuperPushInstallation $valid } | Should -Not -Throw

        foreach ($invalid in @(
            [pscustomobject]@{ id = 1; repository_selection = 'all'; account = $valid.account; permissions = $valid.permissions },
            [pscustomobject]@{ id = 1; repository_selection = 'selected'; account = [pscustomobject]@{ login = 'Other' }; permissions = $valid.permissions },
            [pscustomobject]@{ id = 1; repository_selection = 'selected'; account = $valid.account; permissions = [pscustomobject]@{ contents = 'write'; issues = 'read' } }
        )) {
            { Assert-SuperPushInstallation $invalid } | Should -Throw
        }
    }

    It 'accepts only a token for the one selected repository' {
        $grant = [pscustomobject]@{
            token = 'fake-token'
            expires_at = '2099-01-01T00:00:00Z'
            repository_selection = 'selected'
            permissions = [pscustomobject]@{ contents = 'write' }
            repositories = @([pscustomobject]@{ full_name = 'Crisp-Inc/internal-apps' })
        }

        { Assert-SuperPushToken $grant 'Crisp-Inc/internal-apps' } | Should -Not -Throw
        { Assert-SuperPushToken $grant 'Crisp-Inc/data-warehouse' } | Should -Throw '*wrong repository scope*'
        $grant.permissions | Add-Member -NotePropertyName issues -NotePropertyValue write
        { Assert-SuperPushToken $grant 'Crisp-Inc/internal-apps' } | Should -Throw '*broader permissions*'
    }

    It 'signs an RS256 App JWT with built-in crypto' {
        $rsa = [Security.Cryptography.RSA]::Create(2048)
        try {
            $privateKey = $rsa.ExportRSAPrivateKeyPem()
            $jwt = New-GitHubAppJwt 'Iv1.defiant' $privateKey
            $parts = $jwt.Split('.')

            $parts.Count | Should -Be 3
            $header = ConvertFrom-Base64Url $parts[0] | ConvertFrom-Json
            $payload = ConvertFrom-Base64Url $parts[1] | ConvertFrom-Json
            $header.alg | Should -Be 'RS256'
            $payload.iss | Should -Be 'Iv1.defiant'
            ($payload.exp - $payload.iat) | Should -BeLessOrEqual 600
        }
        finally {
            $rsa.Dispose()
        }
    }

    It 'isolates the token from hooks, helpers, config, redirects, traces, and prompts' {
        $script:PushObservation = $null
        Mock Invoke-GitCommand {
            param([string[]]$Arguments)
            $script:PushObservation = [pscustomobject]@{
                Arguments = $Arguments
                ConfigCount = $env:GIT_CONFIG_COUNT
                ConfigKeys = @(0..([int]$env:GIT_CONFIG_COUNT - 1) | ForEach-Object { [Environment]::GetEnvironmentVariable("GIT_CONFIG_KEY_$_") })
                ConfigValues = @(0..([int]$env:GIT_CONFIG_COUNT - 1) | ForEach-Object { [Environment]::GetEnvironmentVariable("GIT_CONFIG_VALUE_$_") })
                AskPass = $env:GIT_ASKPASS
                TerminalPrompt = $env:GIT_TERMINAL_PROMPT
                Trace = $env:GIT_TRACE
                TraceCurl = $env:GIT_TRACE_CURL
                GlobalConfig = $env:GIT_CONFIG_GLOBAL
                NoSystemConfig = $env:GIT_CONFIG_NOSYSTEM
            }
            [pscustomobject]@{ ExitCode = 0; Output = @('ok') }
        }
        $state = [pscustomobject]@{
            Repository = 'Crisp-Inc/internal-apps'
            Root = '/tmp/internal-apps'
            NewSha = '0123456789abcdef0123456789abcdef01234567'
        }

        Invoke-SuperPushGit $state 'not-a-real-token' | Out-Null

        ($script:PushObservation.Arguments -join ' ') | Should -Not -Match 'not-a-real-token|--force'
        $script:PushObservation.ConfigKeys | Should -Contain 'credential.helper'
        $script:PushObservation.ConfigKeys | Should -Contain 'core.hooksPath'
        $script:PushObservation.ConfigKeys | Should -Contain 'http.followRedirects'
        ($script:PushObservation.ConfigValues -join ' ') | Should -Match 'AUTHORIZATION: basic '
        $script:PushObservation.AskPass | Should -Be '/usr/bin/false'
        $script:PushObservation.TerminalPrompt | Should -Be '0'
        $script:PushObservation.Trace | Should -BeNullOrEmpty
        $script:PushObservation.TraceCurl | Should -BeNullOrEmpty
        $script:PushObservation.GlobalConfig | Should -Be '/dev/null'
        $script:PushObservation.NoSystemConfig | Should -Be '1'
    }

    It 'reads credential metadata only through faked fixed human-account calls' {
        $script:OnePasswordCalls = @()
        Mock Invoke-OnePasswordJson {
            param([string[]]$Arguments)
            $script:OnePasswordCalls += ,$Arguments
            if ($Arguments[0] -eq 'item') {
                return [pscustomobject]@{
                    vault = [pscustomobject]@{ id = 'vault-1701' }
                    fields = @(
                        [pscustomobject]@{ label = 'client-id'; value = 'Iv1.defiant' },
                        [pscustomobject]@{ label = 'private-key'; value = 'fake-private-key' }
                    )
                }
            }
            [pscustomobject]@{ name = 'Human Security' }
        }

        $credential = Get-SuperPushAppCredential

        $credential.ClientId | Should -Be 'Iv1.defiant'
        $credential.PrivateKey | Should -Be 'fake-private-key'
        $calls = $script:OnePasswordCalls | ForEach-Object { $_ -join ' ' }
        $calls.Count | Should -Be 2
        $calls[0] | Should -Match 'item get Super Push GitHub App --account 2KC5FVMXXJGKDG7LGHWF2OJ2N4'
        $calls[1] | Should -Match 'vault get vault-1701 --account 2KC5FVMXXJGKDG7LGHWF2OJ2N4'
    }

    It 'performs three state reads, one push, and one revocation' {
        $script:StateReads = 0
        $script:Pushes = 0
        $script:Revocations = 0
        $state = New-TestSuperPushState
        Mock Get-SuperPushState { $script:StateReads++; $state.PSObject.Copy() }
        Mock Show-SuperPushEvidence {}
        Mock Confirm-SuperPush {}
        Mock Get-SuperPushAppCredential { [pscustomobject]@{ ClientId = 'Iv1.defiant'; PrivateKey = 'fake-key' } }
        Mock New-SuperPushToken { New-TestSuperPushGrant }
        Mock Invoke-SuperPushGit { $script:Pushes++ }
        Mock Remove-SuperPushToken { $script:Revocations++ }
        Mock Write-Host {}

        Invoke-SuperPush

        $script:StateReads | Should -Be 3
        $script:Pushes | Should -Be 1
        $script:Revocations | Should -Be 1
    }

    It 'never retries a rejected push and still revokes the token' {
        $script:Pushes = 0
        $script:Revocations = 0
        $state = New-TestSuperPushState
        Mock Get-SuperPushState { $state.PSObject.Copy() }
        Mock Show-SuperPushEvidence {}
        Mock Confirm-SuperPush {}
        Mock Get-SuperPushAppCredential { [pscustomobject]@{ ClientId = 'Iv1.defiant'; PrivateKey = 'fake-key' } }
        Mock New-SuperPushToken { New-TestSuperPushGrant }
        Mock Invoke-SuperPushGit { $script:Pushes++; throw 'push rejected without secret material' }
        Mock Remove-SuperPushToken { $script:Revocations++ }
        Mock Write-Host {}

        { Invoke-SuperPush } | Should -Throw '*Push=not-confirmed*Revoked=True*'
        $script:Pushes | Should -Be 1
        $script:Revocations | Should -Be 1
    }

    It 'fails with bounded expiry when revocation cannot be confirmed' {
        $state = New-TestSuperPushState
        Mock Get-SuperPushState { $state.PSObject.Copy() }
        Mock Show-SuperPushEvidence {}
        Mock Confirm-SuperPush {}
        Mock Get-SuperPushAppCredential { [pscustomobject]@{ ClientId = 'Iv1.defiant'; PrivateKey = 'fake-key' } }
        Mock New-SuperPushToken { New-TestSuperPushGrant }
        Mock Invoke-SuperPushGit {}
        Mock Remove-SuperPushToken { throw 'sanitized revocation failure' }
        Mock Write-Host {}

        { Invoke-SuperPush } | Should -Throw '*Push=accepted*Revoked=False*GitHub expiry is 2099-01-01T00:00:00Z*'
    }

    It 'rejects parameters before any state or credential access' {
        $script:StateReads = 0
        Mock Get-SuperPushState { $script:StateReads++ }

        { Invoke-SuperPush -Repository 'Crisp-Inc/internal-apps' } | Should -Throw
        $script:StateReads | Should -Be 0
    }
}
