BeforeAll {
    . "$PSScriptRoot/../Functions/Invoke-SuperPush.ps1"
    $script:RealGitCommand = (Get-Command Invoke-GitCommand).ScriptBlock
    function New-DefiantRepository {
        $script:Fixture = Join-Path ([IO.Path]::GetTempPath()) "defiant-rebase-$([guid]::NewGuid())"
        $script:Remote = Join-Path $script:Fixture 'remote.git'
        $script:Local = Join-Path $script:Fixture 'local'
        $script:Other = Join-Path $script:Fixture 'other'
        & git init --quiet --bare --initial-branch=main $script:Remote
        & git clone --quiet $script:Remote $script:Local 2>$null
        & git -C $script:Local config user.name 'Benjamin Sisko'
        & git -C $script:Local config user.email 'sisko@example.test'
        New-Item -ItemType Directory -Path "$script:Local/docs" | Out-Null
        Set-Content "$script:Local/docs/defiant.md" 'warp one'
        Set-Content "$script:Local/engine.txt" 'impulse'
        & git -C $script:Local add .
        & git -C $script:Local commit --quiet -m 'initial'
        & git -C $script:Local push --quiet origin main
        & git clone --quiet $script:Remote $script:Other
        & git -C $script:Other config user.name 'Jadzia Dax'
        & git -C $script:Other config user.email 'dax@example.test'
    }
    function Get-DefiantState {
        & git -C $script:Local fetch --quiet origin
        [pscustomobject]@{
            Root = $script:Local
            OldSha = (& git -C $script:Local rev-parse origin/main)
            NewSha = (& git -C $script:Local rev-parse HEAD)
        }
    }
}
Describe 'docs-only Super Push pull/rebase' {
    BeforeEach { New-DefiantRepository }
    AfterEach { Remove-Item $script:Fixture -Recurse -Force }

    It 'rebases local docs onto remote code without modifying the remote' {
        Set-Content "$script:Local/docs/defiant.md" 'warp nine'
        & git -C $script:Local commit --quiet -am 'docs'
        $before = & git -C $script:Local rev-parse HEAD
        Set-Content "$script:Other/engine.txt" 'warp drive'
        & git -C $script:Other commit --quiet -am 'remote code'
        & git -C $script:Other push --quiet origin main
        $remoteSha = & git -C $script:Other rev-parse HEAD

        Sync-SuperPushDocumentation (Get-DefiantState)

        (& git -C $script:Local rev-parse HEAD) | Should -Not -Be $before
        Test-FastForward $script:Local $remoteSha (& git -C $script:Local rev-parse HEAD) | Should -BeTrue
        Get-Content "$script:Local/docs/defiant.md" | Should -Be 'warp nine'
        Get-Content "$script:Local/engine.txt" | Should -Be 'warp drive'
        (& git --git-dir=$script:Remote rev-parse main) | Should -Be $remoteSha
        (& git -C $script:Local status --porcelain) | Should -BeNullOrEmpty
    }

    It 'runs the cmdlet through rebase and pushes only the rechecked SHA' {
        Set-Content "$script:Local/docs/defiant.md" 'warp nine'
        & git -C $script:Local commit --quiet -am 'docs'
        Set-Content "$script:Other/engine.txt" 'warp drive'
        & git -C $script:Other commit --quiet -am 'remote code'
        & git -C $script:Other push --quiet origin main
        $script:BeforeRebase = & git -C $script:Local rev-parse HEAD
        Mock Get-CrispRepository { 'Crisp-Inc/defiant' }
        Mock Get-SuperPushAppCredential { [pscustomobject]@{ ClientId = 'Iv1.defiant'; PrivateKey = 'fictional-defiant-key' } }
        Mock New-SuperPushToken {
            [pscustomobject]@{ token = 'fictional-defiant-token'; expires_at = '2099-01-01T00:00:00Z'; repository_selection = 'selected'; permissions = [pscustomobject]@{ contents = 'write' }; repositories = @([pscustomobject]@{ full_name = 'Crisp-Inc/defiant' }); installation_id = 1701 }
        }
        Mock Invoke-SuperPushGit {
            param($State)
            $State.NewSha | Should -Not -Be $script:BeforeRebase
            $State.NewSha | Should -Be (& git -C $script:Local rev-parse HEAD)
            Test-FastForward $State.Root $State.OldSha $State.NewSha | Should -BeTrue
        }
        Mock Update-SuperPushTrackingRef {}
        Mock Remove-SuperPushToken {}
        Mock Write-Host {}
        Mock Save-SuperPushDiagnostics { '/tmp/fictional-defiant-diagnostics' }
        Push-Location $script:Local
        try { Invoke-SuperPush } finally { Pop-Location }
        Should -Invoke Invoke-SuperPushGit -Times 1 -Exactly
        Should -Invoke Remove-SuperPushToken -Times 1 -Exactly
    }

    It 'rejects an untracked file before rebase or credential access' {
        Set-Content "$script:Local/docs/defiant.md" 'warp nine'
        & git -C $script:Local commit --quiet -am 'docs'
        Set-Content "$script:Local/quark.txt" 'untracked'
        $before = & git -C $script:Local rev-parse HEAD
        Mock Get-CrispRepository { 'Crisp-Inc/defiant' }
        Mock Get-SuperPushAppCredential {}
        Mock Write-Host {}
        Mock Save-SuperPushDiagnostics { '/tmp/fictional-defiant-diagnostics' }
        Push-Location $script:Local
        try { { Invoke-SuperPush } | Should -Throw '*clean worktree*' } finally { Pop-Location }
        (& git -C $script:Local rev-parse HEAD) | Should -Be $before
        Get-Content "$script:Local/quark.txt" | Should -Be 'untracked'
        Should -Invoke Get-SuperPushAppCredential -Times 0 -Exactly
    }

    It 'stops on mixed docs and code before pulling or changing HEAD' {
        Set-Content "$script:Local/docs/defiant.md" 'warp nine'
        Set-Content "$script:Local/engine.txt" 'warp drive'
        & git -C $script:Local commit --quiet -am 'mixed'
        $state = Get-DefiantState
        Mock Invoke-GitCommand { param($Arguments, $AllowFailure); & $script:RealGitCommand -Arguments $Arguments -AllowFailure:$AllowFailure }
        Mock Invoke-GitCommand { throw 'must not pull' } -ParameterFilter { $Arguments -contains 'pull' }
        { Sync-SuperPushDocumentation $state } | Should -Throw '*contains more than documentation*'
        Should -Invoke Invoke-GitCommand -Times 0 -Exactly -ParameterFilter { $Arguments -contains 'pull' }
        (& git -C $script:Local rev-parse HEAD) | Should -Be $state.NewSha
    }

    It 'does not hide code commits behind a docs-only net diff' {
        Set-Content "$script:Local/engine.txt" 'warp drive'
        & git -C $script:Local commit --quiet -am 'code'
        Set-Content "$script:Local/engine.txt" 'impulse'
        Set-Content "$script:Local/docs/defiant.md" 'warp nine'
        & git -C $script:Local commit --quiet -am 'revert code and add docs'
        { Sync-SuperPushDocumentation (Get-DefiantState) } | Should -Throw '*contains more than documentation*'
    }

    It 'stops on a docs conflict without pushing or accessing credentials' {
        Set-Content "$script:Local/docs/defiant.md" 'warp nine'
        & git -C $script:Local commit --quiet -am 'local docs'
        Set-Content "$script:Other/docs/defiant.md" 'warp seven'
        & git -C $script:Other commit --quiet -am 'remote docs'
        & git -C $script:Other push --quiet origin main
        $remoteSha = & git -C $script:Other rev-parse HEAD
        $state = Get-DefiantState
        Mock Get-SuperPushState { $state }
        Mock Assert-SafeGitEnvironment {}
        Mock Assert-SafeGitConfig {}
        Mock Get-CrispRepository { 'Crisp-Inc/defiant' }
        Mock Get-SuperPushAppCredential { throw 'must not access credentials' }
        Mock Invoke-SuperPushGit { throw 'must not push' }
        Mock Write-Host {}
        Mock Save-SuperPushDiagnostics { '/tmp/fictional-defiant-diagnostics' }
        { Invoke-SuperPush } | Should -Throw '*Phase=docs-rebase*'
        Should -Invoke Get-SuperPushAppCredential -Times 0 -Exactly
        Should -Invoke Invoke-SuperPushGit -Times 0 -Exactly
        (& git --git-dir=$script:Remote rev-parse main) | Should -Be $remoteSha
        (& git -C $script:Local diff --name-only --diff-filter=U) | Should -Be 'docs/defiant.md'
    }

    It 'preserves an already approved detached snapshot without a pull' {
        Set-Content "$script:Local/docs/defiant.md" 'warp nine'
        & git -C $script:Local commit --quiet -am 'docs'
        & git -C $script:Local checkout --quiet --detach
        $state = Get-DefiantState
        Mock Invoke-GitCommand { param($Arguments, $AllowFailure); & $script:RealGitCommand -Arguments $Arguments -AllowFailure:$AllowFailure }
        Mock Invoke-GitCommand { throw 'must not pull' } -ParameterFilter { $Arguments -contains 'pull' }
        Sync-SuperPushDocumentation $state
        Should -Invoke Invoke-GitCommand -Times 0 -Exactly -ParameterFilter { $Arguments -contains 'pull' }
        (& git -C $script:Local rev-parse HEAD) | Should -Be $state.NewSha
    }

    It 'refuses to rebase a stale detached snapshot' {
        Set-Content "$script:Local/docs/defiant.md" 'warp nine'
        & git -C $script:Local commit --quiet -am 'docs'
        & git -C $script:Local checkout --quiet --detach
        Set-Content "$script:Other/engine.txt" 'warp drive'
        & git -C $script:Other commit --quiet -am 'remote code'
        & git -C $script:Other push --quiet origin main
        $state = Get-DefiantState
        { Sync-SuperPushDocumentation $state } | Should -Throw '*detached*'
        (& git -C $script:Local rev-parse HEAD) | Should -Be $state.NewSha
    }
}
