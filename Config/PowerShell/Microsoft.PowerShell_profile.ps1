$profilePartsRoot = Join-Path $PSScriptRoot 'Profile.d'

if (Test-Path $profilePartsRoot) {
    Get-ChildItem -Path $profilePartsRoot -Filter '*.ps1' -File |
        Sort-Object Name |
        ForEach-Object { . $_.FullName }
}
