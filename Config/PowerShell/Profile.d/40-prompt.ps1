oh-my-posh init pwsh --config ~/powerlevel10k_classic-custom.omp.json | Invoke-Expression

$_PoshPrMrScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'oh-my-posh-pr.ps1'

function Invoke-PoshPrMrContext {
    [CmdletBinding()]
    param([bool]$originalStatus)

    $now = Get-Date
    $cacheKey = $null

    if (git rev-parse --is-inside-work-tree 2>$null) {
        $root = git rev-parse --show-toplevel 2>$null
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
        if ($root -and $branch) {
            $cacheKey = "$root|$branch"
        }
    }

    if ($global:_PoshPrMrCacheKey -eq $cacheKey -and $global:_PoshPrMrCacheTime) {
        $env:POSH_PR_MR = $global:_PoshPrMrCacheValue
        return
    }

    $value = ''
    if ($cacheKey -and (Test-Path $_PoshPrMrScript)) {
        $value = & $_PoshPrMrScript
    }

    $global:_PoshPrMrCacheKey = $cacheKey
    $global:_PoshPrMrCacheTime = $now
    $global:_PoshPrMrCacheValue = $value
    $env:POSH_PR_MR = $value
}

if (Get-Module -Name "oh-my-posh-core") {
    Set-Item -Path Function:oh-my-posh-core\Set-PoshContext -Value ${function:Invoke-PoshPrMrContext}
}
else {
    function global:Set-PoshContext { Invoke-PoshPrMrContext $args }
}

$currentPrompt = (Get-Item Function:prompt).ScriptBlock.ToString()
if ($currentPrompt -notmatch 'Invoke-PoshPrMrContext') {
    $global:_PoshPrMrOriginalPrompt = $function:prompt
    function prompt {
        Invoke-PoshPrMrContext $true
        & $global:_PoshPrMrOriginalPrompt
    }
}

function Clear-PoshPrMrCache {
    $global:_PoshPrMrCacheKey = $null
    $global:_PoshPrMrCacheTime = $null
    $global:_PoshPrMrCacheValue = $null
    $env:POSH_PR_MR = $null
    $env:POSH_PR_MR_LINKS = $null
}

Enable-PoshTooltips
