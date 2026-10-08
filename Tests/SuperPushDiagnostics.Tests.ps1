BeforeAll {
    . "$PSScriptRoot/../Functions/Invoke-SuperPush.ps1"
    $script:ActualSuperPushState = (Get-Command Get-SuperPushState).ScriptBlock
    $script:ActualPush = (Get-Command Invoke-SuperPushGit).ScriptBlock
    $script:ActualNewToken = (Get-Command New-SuperPushToken).ScriptBlock
    $script:ActualCredential = (Get-Command Get-SuperPushAppCredential).ScriptBlock
    function Invoke-DiagnosticOnePasswordStub { throw 'Offline CLI stub was not mocked.' }
    function New-DiagnosticState {
        [pscustomobject]@{ Repository = 'Crisp-Inc/defiant'; Root = '/tmp/defiant'; Origin = 'https://github.com/Crisp-Inc/defiant.git'; TargetRef = 'refs/heads/main'; OldSha = '1' * 40; NewSha = '2' * 40 }
    }
}
Describe 'Super Push retained diagnostics' {
    BeforeEach {
        $script:DiagnosticHost = [Collections.Generic.List[string]]::new()
        $script:DiagnosticFile = $null
        $script:PreviousAutomation = $env:OP_SERVICE_ACCOUNT_TOKEN
        $script:PreviousBiometric = $env:OP_BIOMETRIC_UNLOCK_ENABLED
        $script:PreviousOnePasswordPath = $script:OnePasswordPath
        $env:OP_SERVICE_ACCOUNT_TOKEN = 'fictional-bajor-automation'
        Mock Write-Host {
            param([Parameter(Position = 0, ValueFromRemainingArguments)][object[]]$Object)
            $script:DiagnosticHost.Add(($Object -join ' '))
        }
        Mock Get-SuperPushState { New-DiagnosticState }
        Mock Show-SuperPushEvidence {}
        Mock Test-SuperPushDocumentationOnly { $false }
        Mock Confirm-SuperPush {}
        Mock Get-SuperPushAppCredential { [pscustomobject]@{ ClientId = 'Iv1.defiant'; PrivateKey = 'fictional-defiant-private-key' } }
        Mock New-SuperPushToken {
            [pscustomobject]@{ token = 'fictional-defiant-installation'; expires_at = '2099-01-01T00:00:00Z'; repository_selection = 'selected'; permissions = [pscustomobject]@{ contents = 'write' }; repositories = @([pscustomobject]@{ full_name = 'Crisp-Inc/defiant' }); installation_id = 1701 }
        }
        Mock Invoke-SuperPushGit {}
        Mock Update-SuperPushTrackingRef {}
        Mock Remove-SuperPushToken {}
    }
    AfterEach {
        $env:OP_SERVICE_ACCOUNT_TOKEN = $script:PreviousAutomation
        $env:OP_BIOMETRIC_UNLOCK_ENABLED = $script:PreviousBiometric
        $script:OnePasswordPath = $script:PreviousOnePasswordPath
        foreach ($line in $script:DiagnosticHost) {
            if ($line.StartsWith('Diagnostics: ')) {
                $path = $line.Substring(13)
                Remove-Item -LiteralPath (Split-Path $path) -Recurse -Force
            }
        }
    }
    It 'retains early failures with actual cwd and phase, before credentials' {
        Mock Get-SuperPushState { throw 'fetch failed at Bajor' }
        { Invoke-SuperPush } | Should -Throw '*Phase=preflight*fetch failed at Bajor*'
        Should -Invoke Get-SuperPushAppCredential -Times 0 -Exactly
        $path = @($script:DiagnosticHost | Where-Object { $_.StartsWith('Diagnostics: ') })[0].Substring(13)
        $text = [IO.File]::ReadAllText($path)
        $text | Should -Match ([regex]::Escape((Get-Location).Path))
        $text | Should -Match 'fetch failed at Bajor'
        [IO.File]::GetUnixFileMode($path) | Should -Be ([IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite)
        [IO.File]::GetUnixFileMode((Split-Path $path)) | Should -Be ([IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    }
    It 'retains distinct Git streams and exit code, redacts secrets and still revokes once' {
        Mock Invoke-SuperPushGit {
            param($State, $Token)
            & $script:ActualPush $State $Token
        }
        Mock Invoke-SuperPushGitProcess {
            $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('x-access-token:fictional-defiant-installation'))
            [pscustomobject]@{ ExitCode = 23; Stdout = "Defiant stdout fictional-defiant-installation $basic"; Stderr = 'Bajor stderr fictional-bajor-automation https://sisko:fictional-password@example.test/repo AUTHORIZATION: Bearer fictional-unknown-header' }
        }
        $failure = $null
        try { Invoke-SuperPush } catch { $failure = $_.Exception.Message }
        $failure | Should -Match 'Phase=push'
        $failure | Should -Match 'exit code 23'
        $failure | Should -Match 'Push=not-confirmed'
        Should -Invoke Remove-SuperPushToken -Times 1 -Exactly
        Should -Invoke Invoke-SuperPushGitProcess -Times 1 -Exactly
        $path = @($script:DiagnosticHost | Where-Object { $_.StartsWith('Diagnostics: ') })[0].Substring(13)
        $text = [IO.File]::ReadAllText($path) + $failure + ($script:DiagnosticHost -join "`n")
        $text | Should -Match 'stdout.*Defiant stdout'
        $text | Should -Match 'stderr.*Bajor stderr'
        $text | Should -Match 'Cleanup Phase=git-environment outcome=restored'
        $text | Should -Not -Match 'fictional-defiant-installation|fictional-bajor-automation|fictional-password|fictional-unknown-header'
        $text | Should -Not -Match ([regex]::Escape([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('x-access-token:fictional-defiant-installation'))))
    }
    It 'retains a real preflight fetch/ancestry failure without accessing providers' -ForEach @(
        @{ Operation = 'fetch'; Code = 11; Detail = 'fetch transport failed' },
        @{ Operation = 'merge-base'; Code = 2; Detail = 'ancestry inspection failed' }
    ) {
        $script:FailOperation = $Operation
        $script:FailCode = $Code
        $script:FailDetail = $Detail
        Mock Get-SuperPushState { & $script:ActualSuperPushState }
        Mock Assert-SafeGitEnvironment {}
        Mock Assert-SafeGitConfig {}
        Mock Invoke-SuperPushGitProcess {
            param([string[]]$Arguments)
            if ($Arguments -contains $script:FailOperation) {
                return [pscustomobject]@{ ExitCode = $script:FailCode; Stdout = 'Bajor remote context'; Stderr = $script:FailDetail }
            }
            $stdout = if ($Arguments -contains '--show-toplevel') { '/tmp/defiant' }
                elseif ($Arguments -contains 'config') { 'https://github.com/Crisp-Inc/defiant.git' }
                elseif ($Arguments -contains 'HEAD^{commit}') { '2' * 40 }
                elseif ($Arguments -contains 'refs/remotes/origin/main^{commit}') { '1' * 40 }
                else { '' }
            [pscustomobject]@{ ExitCode = 0; Stdout = $stdout; Stderr = '' }
        }
        { Invoke-SuperPush } | Should -Throw '*Phase=preflight*'
        Should -Invoke Get-SuperPushAppCredential -Times 0 -Exactly
        Should -Invoke Invoke-SuperPushGit -Times 0 -Exactly
        $path = @($script:DiagnosticHost | Where-Object { $_.StartsWith('Diagnostics: ') })[0].Substring(13)
        $text = [IO.File]::ReadAllText($path)
        $text | Should -Match "Git Exit=$Code"
        $text | Should -Match $Detail
        $text | Should -Match 'Bajor remote context'
    }
    It 'omits arbitrary credential-provider exceptions, including unknown secrets' {
        Mock Get-SuperPushAppCredential { throw 'opaque-provider-secret-not-yet-returned' }
        { Invoke-SuperPush } | Should -Throw '*Phase=credential*response text omitted*'
        $path = @($script:DiagnosticHost | Where-Object { $_.StartsWith('Diagnostics: ') })[0].Substring(13)
        ([IO.File]::ReadAllText($path) + ($script:DiagnosticHost -join "`n")) | Should -Not -Match 'opaque-provider-secret'
        Should -Invoke New-SuperPushToken -Times 0 -Exactly
    }
    It 'retains a fixed credential code without provider values' -ForEach @(
        @{ Fault = 'missing-token'; ExpectedCode = 'automation-token-missing' },
        @{ Fault = 'item'; ExpectedCode = 'item-mismatch' },
        @{ Fault = 'vault'; ExpectedCode = 'vault-mismatch' },
        @{ Fault = 'client-missing'; ExpectedCode = 'client-id-invalid' },
        @{ Fault = 'client-duplicate'; ExpectedCode = 'client-id-invalid' },
        @{ Fault = 'client-empty'; ExpectedCode = 'client-id-invalid' },
        @{ Fault = 'key-missing'; ExpectedCode = 'private-key-invalid' },
        @{ Fault = 'key-empty'; ExpectedCode = 'private-key-invalid' },
        @{ Fault = 'key-duplicate'; ExpectedCode = 'private-key-invalid' },
        @{ Fault = 'cli-exit'; ExpectedCode = 'cli-exit' },
        @{ Fault = 'cli-json'; ExpectedCode = 'cli-json-invalid' },
        @{ Fault = 'cli-launch'; ExpectedCode = 'cli-launch-failed' }
    ) {
        $script:CredentialFault = $Fault
        $env:OP_BIOMETRIC_UNLOCK_ENABLED = 'true'
        if ($Fault -eq 'missing-token') { $env:OP_SERVICE_ACCOUNT_TOKEN = $null }
        Mock Get-SuperPushAppCredential { & $script:ActualCredential }
        # Mock the executable, not credential resolution: exercise the real CLI
        # parsing and validation, but never access 1Password or real credentials.
        $script:OnePasswordPath = 'Invoke-DiagnosticOnePasswordStub'
        Mock Invoke-DiagnosticOnePasswordStub {
            $env:OP_BIOMETRIC_UNLOCK_ENABLED | Should -Be 'false'
            if ($script:CredentialFault -eq 'cli-launch') { throw 'opaque-garak-launch-secret' }
            $global:LASTEXITCODE = if ($script:CredentialFault -eq 'cli-exit') { 17 } else { 0 }
            if ($script:CredentialFault -in @('cli-exit', 'cli-json')) { return 'opaque-garak-provider-secret' }
            $item = [pscustomobject]@{
                id = 'elv65z73smxy4uq5jii57djpge'
                vault = [pscustomobject]@{ id = 'bcxp54juyo54olkp6ysoe4lzky' }
                fields = @(
                    [pscustomobject]@{ label = 'client-id'; value = 'opaque-garak-client' },
                    [pscustomobject]@{ label = 'private-key'; value = 'opaque-garak-key' }
                )
            }
            switch ($script:CredentialFault) {
                'item' { $item.id = 'opaque-garak-item' }
                'vault' { $item.vault.id = 'opaque-garak-vault' }
                'client-missing' { $item.fields = @($item.fields[1]) }
                'client-duplicate' { $item.fields += $item.fields[0] }
                'client-empty' { $item.fields[0].value = '' }
                'key-missing' { $item.fields = @($item.fields[0]) }
                'key-empty' { $item.fields[1].value = '' }
                'key-duplicate' { $item.fields += $item.fields[1] }
            }
            ConvertTo-Json -InputObject $item -Depth 5 -Compress
        }
        $failure = $null
        try { Invoke-SuperPush } catch { $failure = $_.Exception.Message }
        $failure | Should -Match 'Phase=credential'
        $failure | Should -Match 'Attempted=False'
        $path = @($script:DiagnosticHost | Where-Object { $_.StartsWith('Diagnostics: ') })[0].Substring(13)
        $evidence = [IO.File]::ReadAllText($path) + $failure + ($script:DiagnosticHost -join "`n")
        $evidence | Should -Match "CredentialFailure Code=$ExpectedCode\b"
        $evidence | Should -Not -Match 'opaque-garak'
        Should -Invoke Invoke-DiagnosticOnePasswordStub -Times $(if ($Fault -eq 'missing-token') { 0 } else { 1 }) -Exactly
        Should -Invoke New-SuperPushToken -Times 0 -Exactly
        Should -Invoke Invoke-SuperPushGit -Times 0 -Exactly
        $env:OP_BIOMETRIC_UNLOCK_ENABLED | Should -Be 'true'
    }
    It 'registers the real token-minting JWT before provider failure' {
        Mock New-SuperPushToken { param($Repository, $ClientId, $PrivateKey) & $script:ActualNewToken $Repository $ClientId $PrivateKey }
        Mock New-GitHubAppJwt { 'fictional-defiant-jwt' }
        Mock Invoke-GitHubApi {
            param($Method, $Path, $Token)
            Add-SuperPushDiagnostic "JWT echo: $Token"
            throw 'opaque-token-provider-response'
        }
        { Invoke-SuperPush } | Should -Throw '*Phase=token*response text omitted*'
        $path = @($script:DiagnosticHost | Where-Object { $_.StartsWith('Diagnostics: ') })[0].Substring(13)
        [IO.File]::ReadAllText($path) | Should -Not -Match 'fictional-defiant-jwt|opaque-token-provider-response'
        [IO.File]::ReadAllText($path) | Should -Match 'JWT echo: \[REDACTED\]'
    }
    It 'does not mask failed push uncertainty if retention fails after cleanup' {
        Mock Invoke-SuperPushGit { throw 'Defiant push failed' }
        Mock Save-SuperPushDiagnostics { throw 'unsafe opaque filesystem text' }
        { Invoke-SuperPush } | Should -Throw '*Phase=push*Revoked=True*retention failed*Push attempt outcome is unknown*'
        Should -Invoke Remove-SuperPushToken -Times 1 -Exactly
        ($script:DiagnosticHost -join "`n") | Should -Not -Match 'opaque filesystem'
    }
    It 'reports success and cleanup outcome without recording confirmation input' {
        Invoke-SuperPush
        $path = @($script:DiagnosticHost | Where-Object { $_.StartsWith('Diagnostics: ') })[0].Substring(13)
        [IO.File]::ReadAllText($path) | Should -Match 'Push=accepted.*Revoked=True'
        [IO.File]::ReadAllText($path) | Should -Not -Match 'Approved|fictional-defiant-private-key|fictional-defiant-installation'
        Should -Invoke Confirm-SuperPush -Times 1 -Exactly
        Should -Invoke Get-SuperPushState -Times 3 -Exactly
    }
    It 'reports revocation failure without raw provider exception text' {
        Mock Remove-SuperPushToken { throw 'provider response with fictional-unregistered-secret' }
        { Invoke-SuperPush } | Should -Throw '*Phase=revocation*Revoked=False*GitHub expiry is 2099-01-01T00:00:00Z*'
        $path = @($script:DiagnosticHost | Where-Object { $_.StartsWith('Diagnostics: ') })[0].Substring(13)
        [IO.File]::ReadAllText($path) | Should -Not -Match 'fictional-unregistered-secret'
        Should -Invoke Remove-SuperPushToken -Times 1 -Exactly
    }
    It 'does not push when the final freshness check fails' {
        $script:Reads = 0
        Mock Get-SuperPushState {
            $script:Reads++
            $state = New-DiagnosticState
            if ($script:Reads -eq 3) { $state.OldSha = '3' * 40 }
            $state
        }
        { Invoke-SuperPush } | Should -Throw '*Phase=pre-push*OldSha*'
        Should -Invoke Invoke-SuperPushGit -Times 0 -Exactly
        Should -Invoke Remove-SuperPushToken -Times 1 -Exactly
    }
}
Describe 'Diagnostic boundaries' {
    BeforeEach {
        $script:SuperPushDiagnostics = @{ Phase = 'test'; Lines = [Collections.Generic.List[string]]::new(); Secrets = [Collections.Generic.List[string]]::new() }
    }
    AfterEach { $script:SuperPushDiagnostics = $null }
    It 'redacts encoded credentials, PEM fragments, URLs and headers on both streams' {
        $key = "-----BEGIN PRIVATE KEY-----`nZmljdGlvbmFsLWRlZmlhbnQ=`n-----END PRIVATE KEY-----"
        Add-SuperPushSecret $key
        Add-SuperPushSecret 'fictional+defiant/secret='
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('fictional+defiant/secret='))
        $text = Protect-SuperPushText "$key $encoded fictional%2Bdefiant%2Fsecret%3D Authorization: Basic arbitrary-header"
        $text | Should -Not -Match 'ZmljdGlvbmFsLWRlZmlhbnQ|fictional|arbitrary-header'
    }
    It 'retains known encoded authorization headers without exposing them' {
        $token = 'fictional-garak-token'
        Add-SuperPushSecret $token
        $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x-access-token:$token"))
        foreach ($header in @("AUTHORIZATION: basic $basic", "Authorization: Bearer $token")) {
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($header))
            (Protect-SuperPushText $encoded) | Should -Be '[REDACTED]'
        }
    }
    It 'omits arbitrary token-sensitive Git configuration values' {
        Mock Invoke-SuperPushGitProcess { [pscustomobject]@{ ExitCode = 0; Stdout = 'http.extraHeader opaque-unknown-secret'; Stderr = '' } }
        Invoke-GitCommand -Arguments @('config', '--get-regexp', 'http.*') | Out-Null
        ($script:SuperPushDiagnostics.Lines -join "`n") | Should -Not -Match 'opaque-unknown-secret'
        ($script:SuperPushDiagnostics.Lines -join "`n") | Should -Match 'configuration values omitted'
    }
    It 'rejects public writable ancestors and nonprivate directories' {
        $parent = Join-Path $TestDrive 'unsafe-parent'
        $child = Join-Path $parent 'private-child'
        [IO.Directory]::CreateDirectory($child) | Out-Null
        [IO.File]::SetUnixFileMode($child, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
        $original = [IO.File]::GetUnixFileMode($parent)
        try {
            [IO.File]::SetUnixFileMode($parent, $original -bor [IO.UnixFileMode]::OtherWrite)
            { Assert-SuperPushDiagnosticDirectory $child } | Should -Throw '*ancestor permissions are unsafe*'
        } finally { [IO.File]::SetUnixFileMode($parent, $original) }
        [IO.File]::SetUnixFileMode($child, $original -bor [IO.UnixFileMode]::OtherRead)
        { Assert-SuperPushDiagnosticDirectory $child } | Should -Throw '*directory is unsafe*'
    }
    It 'records bounded GitHub transport context with no raw response text' {
        Mock 'Microsoft.PowerShell.Utility\Invoke-RestMethod' {
            throw [InvalidOperationException]::new('opaque-garak-provider-secret')
        }
        { Invoke-GitHubApi -Method DELETE -Path '/installation/token' -Token 'fictional-garak-token' } | Should -Throw '*HTTP unknown*'
        Should -Invoke 'Microsoft.PowerShell.Utility\Invoke-RestMethod' -Times 1 -Exactly
        ($script:SuperPushDiagnostics.Lines -join "`n") | Should -Match 'Method=DELETE Path=/installation/token HTTP=unknown'
        ($script:SuperPushDiagnostics.Lines -join "`n") | Should -Not -Match 'opaque-garak-provider-secret|fictional-garak-token'
    }
    It 'captures real native stdout and stderr without shell evaluation' {
        $result = Invoke-SuperPushGitProcess -Arguments @('--defiant-invalid-option')
        $result.ExitCode | Should -Not -Be 0
        $result.Stderr | Should -Match 'unknown option'
        $result.Stdout | Should -Be ''
    }
    It 'rejects a symlink retention destination without writing through it' {
        $target = Join-Path $TestDrive 'bajor'
        $link = Join-Path $TestDrive 'defiant-link'
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        { Assert-SuperPushDiagnosticDirectory -Directory $link } | Should -Throw '*unsafe*'
        @(Get-ChildItem $target).Count | Should -Be 0
    }
}
