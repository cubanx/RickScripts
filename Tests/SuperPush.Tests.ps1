Describe 'Invoke-SuperPush safety boundary' {
    BeforeAll {
        $functionPath = Join-Path $PSScriptRoot '../Functions/Invoke-SuperPush.ps1'
        Test-Path -LiteralPath $functionPath | Should -BeTrue
        $script:SuperPushSource = Get-Content -LiteralPath $functionPath -Raw
        $module = Import-Module "$PSScriptRoot/../RickScripts.psd1" -Force -PassThru
        $script:ExportedCommands = @($module.ExportedCommands.Keys)
        Remove-Module $module -Force
        . $functionPath
        $script:GitExecutable = '/usr/bin/git'

        function New-TestSuperPushState {
            [pscustomobject]@{
                Repository = 'Crisp-Inc/yoda'
                Root = '/tmp/yoda'
                Origin = 'git@github.com:Crisp-Inc/yoda.git'
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
                repositories = @([pscustomobject]@{ full_name = 'Crisp-Inc/yoda' })
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
        foreach ($helper in 'Get-SuperPushState', 'Get-SuperPushAppCredential', 'New-SuperPushToken', 'Invoke-SuperPushGit', 'Update-SuperPushTrackingRef') {
            $script:ExportedCommands | Should -Not -Contain $helper
        }
    }

    It 'accepts only supported Crisp GitHub origins' {
        Get-CrispRepository 'git@github.com:Crisp-Inc/yoda.git' | Should -Be 'Crisp-Inc/yoda'
        Get-CrispRepository 'https://github.com/Crisp-Inc/data-warehouse.git' | Should -Be 'Crisp-Inc/data-warehouse'
        Get-CrispRepository 'ssh://git@github.com/Crisp-Inc/external-api.git' | Should -Be 'Crisp-Inc/external-api'

        { Get-CrispRepository 'git@github.com:somebody/yoda.git' } | Should -Throw
        { Get-CrispRepository 'https://example.com/Crisp-Inc/yoda.git' } | Should -Throw
    }

    It 'fixes the ref, confirmation, and one non-force push shape' {
        $sha = '0123456789abcdef0123456789abcdef01234567'

        Get-SuperPushConfirmation | Should -Be 'Approved'
        Test-SuperPushConfirmation 'Approved' (Get-SuperPushConfirmation) | Should -BeTrue
        Test-SuperPushConfirmation 'approved' (Get-SuperPushConfirmation) | Should -BeFalse
        Test-SuperPushConfirmation `
            "SUPER PUSH Crisp-Inc/yoda $sha TO refs/heads/main" `
            (Get-SuperPushConfirmation) | Should -BeFalse

        $arguments = Get-SuperPushArguments '/tmp/yoda' 'Crisp-Inc/yoda' $sha
        $arguments | Should -Be @(
            '-C', '/tmp/yoda', 'push', '--porcelain', '--no-verify',
            'https://github.com/Crisp-Inc/yoda.git',
            "$sha`:refs/heads/main"
        )
        ($arguments -join ' ') | Should -Not -Match '(?:^|\s)--force(?:-with-lease)?(?:\s|$)'
    }

    It 'reads confirmation directly from the console' {
        $script:SuperPushSource | Should -Match '\[Console\]::ReadLine\(\)'
        $script:SuperPushSource | Should -Not -Match '\bRead-Host\b'
    }

    It 'accepts only text documentation changed entries' {
        $script:RawEntries = ":100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 M`0docs/defiant.md`0"
        $script:NumstatEntries = "1`t1`tdocs/defiant.md`0"
        Mock Invoke-GitCommand {
            param([string[]]$Arguments)
            $output = if ($Arguments -contains '--raw') { $script:RawEntries } else { $script:NumstatEntries }
            [pscustomobject]@{ ExitCode = 0; Output = @($output) }
        }
        $state = New-TestSuperPushState

        Test-SuperPushDocumentationOnly $state | Should -BeTrue

        foreach ($path in 'openspec/changes/defiant/tasks.md', 'README.md', 'CHANGELOG', 'CONTRIBUTING.rst', 'SECURITY.txt', 'LICENSE-MIT') {
            $script:RawEntries = ":100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 M`0$path`0"
            $script:NumstatEntries = "1`t1`t$path`0"
            Test-SuperPushDocumentationOnly $state | Should -BeTrue
        }
    }

    It 'fails closed for non-doc, ambiguous, or binary changed entries' {
        $state = New-TestSuperPushState
        $script:RawEntries = ":100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 M`0AGENTS.md`0"
        $script:NumstatEntries = "1`t1`tAGENTS.md`0"
        Mock Invoke-GitCommand {
            param([string[]]$Arguments)
            $output = if ($Arguments -contains '--raw') { $script:RawEntries } else { $script:NumstatEntries }
            [pscustomobject]@{ ExitCode = 0; Output = @($output) }
        }

        Test-SuperPushDocumentationOnly $state | Should -BeFalse
        $script:RawEntries = ":100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 M`0docs/AGENTS.md`0"
        $script:NumstatEntries = "1`t1`tdocs/AGENTS.md`0"
        Test-SuperPushDocumentationOnly $state | Should -BeFalse
        $script:RawEntries = ":100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 M`0docs/operating`tmanual.md`0"
        $script:NumstatEntries = "1`t1`tdocs/operating`tmanual.md`0"
        Test-SuperPushDocumentationOnly $state | Should -BeFalse
        $script:RawEntries = ":100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 M`0docs/defiant.md`0:100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 M`0Functions/warp.ps1`0"
        $script:NumstatEntries = "1`t1`tdocs/defiant.md`01`t1`tFunctions/warp.ps1`0"
        Test-SuperPushDocumentationOnly $state | Should -BeFalse
        $script:RawEntries = ":100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 R100`0docs/old.md`0docs/new.md`0"
        $script:NumstatEntries = "1`t1`t`0docs/old.md`0docs/new.md`0"
        Test-SuperPushDocumentationOnly $state | Should -BeFalse
        $script:RawEntries = ":100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 M`0docs/diagram.png`0"
        $script:NumstatEntries = "-`t-`tdocs/diagram.png`0"
        Test-SuperPushDocumentationOnly $state | Should -BeFalse
        $script:RawEntries = ":120000 120000 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 M`0docs/link.md`0"
        $script:NumstatEntries = "1`t1`tdocs/link.md`0"
        Test-SuperPushDocumentationOnly $state | Should -BeFalse
    }

    It 'reads NUL-delimited changed metadata from Git' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) "rickscripts-docs-only-$([guid]::NewGuid())"
        try {
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            & $script:GitExecutable -C $root init --quiet
            [IO.File]::WriteAllText((Join-Path $root 'docs/defiant.md'), "warp one`n")
            & $script:GitExecutable -C $root add docs/defiant.md
            & $script:GitExecutable -C $root -c user.name='Benjamin Sisko' -c user.email='sisko@example.test' commit --quiet -m 'Add Defiant docs'
            $old = & $script:GitExecutable -C $root rev-parse HEAD
            [IO.File]::AppendAllText((Join-Path $root 'docs/defiant.md'), "warp nine`n")
            & $script:GitExecutable -C $root add docs/defiant.md
            & $script:GitExecutable -C $root -c user.name='Benjamin Sisko' -c user.email='sisko@example.test' commit --quiet -m 'Expand Defiant docs'
            $new = & $script:GitExecutable -C $root rev-parse HEAD

            Test-SuperPushDocumentationOnly ([pscustomobject]@{ Root = $root; OldSha = $old; NewSha = $new }) | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'rejects dirty, equal, and drifted state' {
        { Assert-CleanWorktree ' M promenade.txt' } | Should -Throw
        { Assert-DistinctCommits 'same' 'same' } | Should -Throw

        $before = [pscustomobject]@{
            Repository = 'Crisp-Inc/yoda'
            Root = '/tmp/yoda'
            Origin = 'git@github.com:Crisp-Inc/yoda.git'
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

    It 'shows compact immutable evidence and disabled hooks' {
        $script:HostOutput = @()
        $script:EvidenceCommands = @()
        Mock Write-Host {
            param([Parameter(Position = 0, ValueFromRemainingArguments)][object[]]$Object)
            $script:HostOutput += $Object -join ' '
        }
        Mock Invoke-GitCommand {
            param([string[]]$Arguments)
            $command = $Arguments -join ' '
            $script:EvidenceCommands += $command
            if ($command -like '* log *') { return [pscustomobject]@{ ExitCode = 0; Output = @('abc1234 Ready the Defiant') } }
            if ($command -like '* diff --stat *') { return [pscustomobject]@{ ExitCode = 0; Output = @(' promenade.txt | 1 +') } }
            if ($command -like '* diff --name-status *') { return [pscustomobject]@{ ExitCode = 0; Output = @('M promenade.txt') } }
            throw "Unexpected Git command: $command"
        }
        $state = New-TestSuperPushState

        Show-SuperPushEvidence $state

        $output = $script:HostOutput -join "`n"
        foreach ($expected in @(
            $state.Repository, $state.TargetRef, $state.OldSha, $state.NewSha,
            'verified fast-forward', 'Local hooks: disabled',
            'abc1234 Ready the Defiant', 'promenade.txt | 1 +', 'M promenade.txt'
        )) {
            $output | Should -Match ([regex]::Escape($expected))
        }
        $script:EvidenceCommands -join "`n" | Should -Not -Match '\bdiff --no-color\b'
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
            repositories = @([pscustomobject]@{ full_name = 'Crisp-Inc/yoda' })
        }

        { Assert-SuperPushToken $grant 'Crisp-Inc/yoda' } | Should -Not -Throw
        { Assert-SuperPushToken $grant 'Crisp-Inc/data-warehouse' } | Should -Throw '*wrong repository scope*'
        $grant.permissions | Add-Member -NotePropertyName issues -NotePropertyValue write
        { Assert-SuperPushToken $grant 'Crisp-Inc/yoda' } | Should -Throw '*broader permissions*'
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
            Repository = 'Crisp-Inc/yoda'
            Root = '/tmp/yoda'
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
        Test-Path Env:GIT_CONFIG | Should -BeFalse
    }

    It 'refreshes origin/main to the exact pushed SHA' {
        $state = New-TestSuperPushState
        $script:TrackingExpectedSha = $state.NewSha
        $script:TrackingCommands = @()
        Mock Invoke-GitCommand {
            param([string[]]$Arguments)
            $script:TrackingCommands += ,$Arguments
            if ($Arguments -contains 'rev-parse') {
                $output = @($script:TrackingExpectedSha)
            } else {
                $output = @()
            }
            [pscustomobject]@{ ExitCode = 0; Output = $output }
        }

        Update-SuperPushTrackingRef $state

        $script:TrackingCommands[0] | Should -Be @(
            '-C', $state.Root, 'fetch', '--no-tags', '--no-recurse-submodules',
            'origin', 'refs/heads/main:refs/remotes/origin/main'
        )
        $script:TrackingCommands[1] | Should -Be @(
            '-C', $state.Root, 'rev-parse', 'refs/remotes/origin/main^{commit}'
        )
    }

    It 'rejects a post-push tracking ref that does not match the pushed SHA' {
        $state = New-TestSuperPushState
        Mock Invoke-GitCommand {
            param([string[]]$Arguments)
            $output = if ($Arguments -contains 'rev-parse') {
                @('3333333333333333333333333333333333333333')
            } else {
                @()
            }
            [pscustomobject]@{ ExitCode = 0; Output = $output }
        }

        { Update-SuperPushTrackingRef $state } | Should -Throw '*local origin/main*'
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
        $script:TrackingRefreshes = 0
        $script:Revocations = 0
        $state = New-TestSuperPushState
        Mock Get-SuperPushState { $script:StateReads++; $state.PSObject.Copy() }
        Mock Show-SuperPushEvidence {}
        Mock Test-SuperPushDocumentationOnly { $false }
        Mock Confirm-SuperPush {}
        Mock Get-SuperPushAppCredential { [pscustomobject]@{ ClientId = 'Iv1.defiant'; PrivateKey = 'fake-key' } }
        Mock New-SuperPushToken { New-TestSuperPushGrant }
        Mock Invoke-SuperPushGit { $script:Pushes++ }
        Mock Update-SuperPushTrackingRef { $script:TrackingRefreshes++ }
        Mock Remove-SuperPushToken { $script:Revocations++ }
        Mock Write-Host {}

        Invoke-SuperPush

        $script:StateReads | Should -Be 3
        $script:Pushes | Should -Be 1
        $script:TrackingRefreshes | Should -Be 1
        $script:Revocations | Should -Be 1
        Should -Invoke Confirm-SuperPush -Times 1 -Exactly
    }

    It 'skips only the internal confirmation for documentation-only changes' {
        $state = New-TestSuperPushState
        Mock Get-SuperPushState { $state.PSObject.Copy() }
        Mock Show-SuperPushEvidence {}
        Mock Test-SuperPushDocumentationOnly { $true }
        Mock Confirm-SuperPush {}
        Mock Get-SuperPushAppCredential { [pscustomobject]@{ ClientId = 'Iv1.defiant'; PrivateKey = 'fake-key' } }
        Mock New-SuperPushToken { New-TestSuperPushGrant }
        Mock Invoke-SuperPushGit {}
        Mock Update-SuperPushTrackingRef {}
        Mock Remove-SuperPushToken {}
        Mock Write-Host {}

        Invoke-SuperPush

        Should -Invoke Confirm-SuperPush -Times 0 -Exactly
        Should -Invoke Test-SuperPushDocumentationOnly -Times 1 -Exactly
    }

    It 'reports an accepted push when the tracking refresh cannot be confirmed' {
        $state = New-TestSuperPushState
        Mock Get-SuperPushState { $state.PSObject.Copy() }
        Mock Show-SuperPushEvidence {}
        Mock Test-SuperPushDocumentationOnly { $false }
        Mock Confirm-SuperPush {}
        Mock Get-SuperPushAppCredential { [pscustomobject]@{ ClientId = 'Iv1.defiant'; PrivateKey = 'fake-key' } }
        Mock New-SuperPushToken { New-TestSuperPushGrant }
        Mock Invoke-SuperPushGit {}
        Mock Update-SuperPushTrackingRef { throw 'Local origin/main could not be confirmed.' }
        Mock Remove-SuperPushToken {}
        Mock Write-Host {}

        { Invoke-SuperPush } | Should -Throw '*Push=accepted*Revoked=True*local origin/main*'
    }

    It 'never retries a rejected push and still revokes the token' {
        $script:Pushes = 0
        $script:Revocations = 0
        $state = New-TestSuperPushState
        Mock Get-SuperPushState { $state.PSObject.Copy() }
        Mock Show-SuperPushEvidence {}
        Mock Test-SuperPushDocumentationOnly { $false }
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
        Mock Test-SuperPushDocumentationOnly { $false }
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

        { Invoke-SuperPush -Repository 'Crisp-Inc/yoda' } | Should -Throw
        $script:StateReads | Should -Be 0
    }
}
