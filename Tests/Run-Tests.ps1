#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.1' }

$ErrorActionPreference = 'Stop'

$result = Invoke-Pester -Path $PSScriptRoot -PassThru
if ($result.FailedCount -gt 0) { exit 1 }
