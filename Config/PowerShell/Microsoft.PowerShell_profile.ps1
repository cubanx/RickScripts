Import-Module posh-git
Import-Module z
Import-Module PSReadLine
Import-Module PSFzf
# RickScripts module location: /Users/rick.diaz/.local/share/powershell/Modules/RickScripts/
Import-Module RickScripts
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'

Set-PSReadLineKeyHandler -Key Escape -Function RevertLine
Set-PSReadLineKeyHandler -Key Alt+RightArrow -Function ForwardWord
Set-PSReadLineKeyHandler -Key Alt+LeftArrow -Function BackwardWord

Set-PSReadLineOption -PredictionViewStyle ListView

oh-my-posh init pwsh --config ~/powerlevel10k_classic-custom.omp.json | Invoke-Expression

# Load secrets if present (kept outside the repo)
$secretsPath = Join-Path $HOME 'secrets.ps1'
if (Test-Path $secretsPath) {
    . $secretsPath
}

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
    if ($cacheKey) {
        $value = & /Users/rick.diaz/.config/powershell/oh-my-posh-pr.ps1
    }

    $global:_PoshPrMrCacheKey = $cacheKey
    $global:_PoshPrMrCacheTime = $now
    $global:_PoshPrMrCacheValue = $value
    $env:POSH_PR_MR = $value
}

# Override oh-my-posh module hook so it runs inside the module scope.
if (Get-Module -Name "oh-my-posh-core") {
    Set-Item -Path Function:oh-my-posh-core\Set-PoshContext -Value ${function:Invoke-PoshPrMrContext}
}
else {
    # Fallback in case module loads after this profile snippet.
    function global:Set-PoshContext { Invoke-PoshPrMrContext $args }
}

# Ensure the prompt updates POSH_PR_MR before rendering.
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

function Clear-PoshPrMrCache {
    $global:_PoshPrMrCacheKey = $null
    $global:_PoshPrMrCacheTime = $null
    $global:_PoshPrMrCacheValue = $null
    $env:POSH_PR_MR = $null
}

# # Determine the location of the shims directory
# if ($null -eq $ASDF_DATA_DIR -or $ASDF_DATA_DIR -eq '') {
#     $_asdf_shims = "${env:HOME}/.asdf/shims"
# } else {
#     $_asdf_shims = "$ASDF_DATA_DIR/shims"
# }

# Define extra paths to add
$extraPathVariables = @(
    "${env:HOME}/.local/bin",
    "${env:HOME}/Library/pnpm"
)

# Add paths to PATH if they exist
foreach ($path in $extraPathVariables) {
    if ($path -and (Test-Path $path)) {
        $env:PATH = "${path}:${env:PATH}"
    }
}

# Export global variables for package filters
$global:mem = "--filter=@world50/member-app"
$global:gl = "--filter=@world50/group-leader-app"
$global:pro = "--filter=@world50/prospector-app"
$global:auth = "--filter=@world50/authentication-app"
$global:petl = "--filter=@world50/prospector-etl"
$global:psha = "--filter=@world50/prospector-shared"

$env:PNPM_HOME = "${env:HOME}/Library/pnpm"

function tailscale {
    Push-Location "/Applications/Tailscale.app/Contents/MacOS"
    try {
        ./tailscale $args
    }
    finally {
        Pop-Location
    }
}

$env:MISE_SHELL = 'pwsh'
if (-not (Test-Path -Path Env:/__MISE_ORIG_PATH)) {
    $env:__MISE_ORIG_PATH = $env:PATH
}

function mise {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]  # Allow any number of arguments, including none
        [string[]] $arguments
    )

    $previous_out_encoding = $OutputEncoding
    $previous_console_out_encoding = [Console]::OutputEncoding
    $OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

    function _reset_output_encoding {
        $OutputEncoding = $previous_out_encoding
        [Console]::OutputEncoding = $previous_console_out_encoding
    }

    if ($arguments.count -eq 0) {
        & "/opt/homebrew/bin/mise"
        _reset_output_encoding
        return
    }
    elseif ($arguments -contains '-h' -or $arguments -contains '--help') {
        & "/opt/homebrew/bin/mise" @arguments
        _reset_output_encoding
        return
    }

    $command = $arguments[0]
    if ($arguments.Length -gt 1) {
        $remainingArgs = $arguments[1..($arguments.Length - 1)]
    }
    else {
        $remainingArgs = @()
    }

    switch ($command) {
        { $_ -in 'deactivate', 'shell', 'sh' } {
            & "/opt/homebrew/bin/mise" $command @remainingArgs | Out-String | Invoke-Expression -ErrorAction SilentlyContinue
            _reset_output_encoding
        }
        default {
            & "/opt/homebrew/bin/mise" $command @remainingArgs
            $status = $LASTEXITCODE
            if ($(Test-Path -Path Function:\_mise_hook)) {
                _mise_hook
            }
            _reset_output_encoding
            # Pass down exit code from mise after _mise_hook
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                pwsh -NoProfile -Command exit $status
            }
            else {
                powershell -NoProfile -Command exit $status
            }
        }
    }
}

function Global:_mise_hook {
    if ($env:MISE_SHELL -eq "pwsh") {
        & "/opt/homebrew/bin/mise" hook-env $args -s pwsh | Out-String | Invoke-Expression -ErrorAction SilentlyContinue
    }
}

function __enable_mise_chpwd {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        if ($env:MISE_PWSH_CHPWD_WARNING -ne '0') {
            Write-Warning "mise: chpwd functionality requires PowerShell version 7 or higher. Your current version is $($PSVersionTable.PSVersion). You can add `$env:MISE_PWSH_CHPWD_WARNING=0` to your environment to disable this warning."
        }
        return
    }
    if (-not $__mise_pwsh_chpwd) {
        $Global:__mise_pwsh_chpwd = $true
        $_mise_chpwd_hook = [EventHandler[System.Management.Automation.LocationChangedEventArgs]] {
            param([object] $source, [System.Management.Automation.LocationChangedEventArgs] $eventArgs)
            end {
                _mise_hook
            }
        };
        $__mise_pwsh_previous_chpwd_function = $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction;

        if ($__mise_original_pwsh_chpwd_function) {
            $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction = [Delegate]::Combine($__mise_pwsh_previous_chpwd_function, $_mise_chpwd_hook)
        }
        else {
            $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction = $_mise_chpwd_hook
        }
    }
}
__enable_mise_chpwd
Remove-Item -ErrorAction SilentlyContinue -Path Function:/__enable_mise_chpwd

function __enable_mise_prompt {
    if (-not $__mise_pwsh_previous_prompt_function) {
        $Global:__mise_pwsh_previous_prompt_function = $function:prompt
        function global:prompt {
            if (Test-Path -Path Function:\_mise_hook) {
                _mise_hook
            }
            & $__mise_pwsh_previous_prompt_function
        }
    }
}
__enable_mise_prompt
Remove-Item -ErrorAction SilentlyContinue -Path Function:/__enable_mise_prompt

_mise_hook
if (-not $__mise_pwsh_command_not_found) {
    $Global:__mise_pwsh_command_not_found = $true
    function __enable_mise_command_not_found {
        $_mise_pwsh_cmd_not_found_hook = [EventHandler[System.Management.Automation.CommandLookupEventArgs]] {
            param([object] $Name, [System.Management.Automation.CommandLookupEventArgs] $eventArgs)
            end {
                if ([Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems()[-1].CommandLine -match ([regex]::Escape($Name))) {
                    if (& "/opt/homebrew/bin/mise" hook-not-found -s pwsh -- $Name) {
                        _mise_hook
                        if (Get-Command $Name -ErrorAction SilentlyContinue) {
                            $EventArgs.Command = Get-Command $Name
                            $EventArgs.StopSearch = $true
                        }
                    }
                }
            }
        }
        $current_command_not_found_function = $ExecutionContext.SessionState.InvokeCommand.CommandNotFoundAction
        if ($current_command_not_found_function) {
            $ExecutionContext.SessionState.InvokeCommand.CommandNotFoundAction = [Delegate]::Combine($current_command_not_found_function, $_mise_pwsh_cmd_not_found_hook)
        }
        else {
            $ExecutionContext.SessionState.InvokeCommand.CommandNotFoundAction = $_mise_pwsh_cmd_not_found_hook
        }
    }
    __enable_mise_command_not_found
    Remove-Item -ErrorAction SilentlyContinue -Path Function:/__enable_mise_command_not_found
}




