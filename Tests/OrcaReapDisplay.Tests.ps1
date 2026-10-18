BeforeAll {
    . "$PSScriptRoot/../Common/OrcaReapDisplay.ps1"
    function New-DisplaySummary {
        param([string]$Status, [bool]$All = $false)
        $row = [pscustomobject]@{
            PSTypeName='RickScripts.OrcaReapResult'
            Worktree='quark'; Status=$Status; Reason='IdentityChanged'
            Explanation='Worktree changed during validation; inspect the target before retrying.'
            IsMainWorktree=$false; IsLocked=$false; Checks=@{Ready=$false}
        }
        [pscustomobject]@{
            PSTypeName='RickScripts.OrcaReapSummary'
            SpectreRendered=$false; All=$All; InactiveDays=14; Force=$false
            CoverageComplete=$true; CandidateCount=1; DeletedCount=0; SkippedCount=0; FailedCount=1
            Results=@($row); VisibleResults=@($row)
        }
    }
}

Describe 'Orca cleanup outcomes are always visible' {
    It 'shows status, reason code and complete explanation in plain output without All: <Status>' -ForEach @(
        @{Status='Candidate'}; @{Status='Deleted'}; @{Status='Skipped'}; @{Status='Failed'}
    ) {
        Update-FormatData -PrependPath "$PSScriptRoot/../Formats/OrcaReap.format.ps1xml"
        $summary = New-DisplaySummary $Status
        $text = $summary | Out-String -Width 80
        $text | Should -Match "$Status \(IdentityChanged\)"
        ($text -replace '\s+', ' ') | Should -Match ([regex]::Escape($summary.Results[0].Explanation))
    }
    It 'shows status and full escaped reason details in Spectre with or without All: <All>' -ForEach @(
        @{All=$false}; @{All=$true}
    ) -Skip:(-not (Get-Module -ListAvailable PwshSpectreConsole)) {
        Initialize-OrcaReapSpectre
        $summary = New-DisplaySummary 'Failed' $All
        $summary.Results[0].Worktree = 'quark[red]'
        $summary.Results[0].Explanation += ' Literal [green]text[/].'
        Mock 'PwshSpectreConsole\Write-SpectreHost' {}
        Mock 'PwshSpectreConsole\Format-SpectreTable' { [pscustomobject]@{Columns=@()} }
        Mock 'PwshSpectreConsole\Out-SpectreHost' {}
        @(Show-OrcaReapSpectre $summary).Count | Should -Be 0
        Should -Invoke 'PwshSpectreConsole\Format-SpectreTable' -Times 1 -Exactly -ParameterFilter { $Property -contains 'Status' }
        Should -Invoke 'PwshSpectreConsole\Write-SpectreHost' -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'quark[[red]]: Failed (IdentityChanged) — Worktree changed during validation; inspect the target before retrying. Literal [[green]]text[[/]].'
        }
    }
}
