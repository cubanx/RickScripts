function Invoke-ValidationScript {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ScriptPath = "~/world50/transmute-platform/scripts/ci/validation.sh",
        
        [ValidateSet("api-client", "authentication-app", "member-api", "member-app", 
            "microsites-api", "monorepo", "prospector-app", "prospector-etl", 
            "prospector-shared", "pulse-app", "react-components", "react-icons", 
            "react-primitives", "theme")]
        [string]$Filter,
        
        [ValidateSet("lint", "prettier", "tsc", "router-typecheck", "jest", "cypress", "vitest")]
        [string]$Command
    )

    Push-Location "~/world50/transmute-platform"

    try {
        $filters = @(
            "api-client",
            "authentication-app", 
            "member-api",
            "member-app",
            "microsites-api",
            "monorepo",
            "prospector-app",
            "prospector-etl", 
            "prospector-shared",
            "pulse-app",
            "react-components",
            "react-icons",
            "react-primitives",
            "theme"
        )

        $commands = @(
            "lint",
            "prettier", 
            "tsc",
            "router-typecheck",
            "jest",
            "cypress",
            "vitest"
        )

        # Commands that run from monorepo root and don't accept filter parameter
        $commandsWithoutFilter = @("lint", "prettier")

        # Handle command selection first
        if ($Command) {
            $selectedCommand = $Command
            Write-Host "Using command: $selectedCommand" -ForegroundColor Green
        }
        else {
            Write-Host "Select a command:" -ForegroundColor Yellow
            $selectedCommand = $commands | fzf --prompt="Command> " --height=40%

            if (-not $selectedCommand) {
                Write-Warning "No command selected. Exiting."
                return
            }
            Write-Host "Selected command: $selectedCommand" -ForegroundColor Green
        }

        Write-Host ""

        # Handle filter selection only if command needs it
        if ($selectedCommand -in $commandsWithoutFilter) {
            Write-Host "Command '$selectedCommand' runs from monorepo root and doesn't require a filter." -ForegroundColor Cyan
            $validationArgs = "--command $selectedCommand"
        }
        else {
            if ($Filter) {
                $selectedFilter = $Filter
                Write-Host "Using filter: $selectedFilter" -ForegroundColor Green
            }
            else {
                Write-Host "Select a filter:" -ForegroundColor Yellow
                $selectedFilter = $filters | fzf --prompt="Filter> " --height=40%
                
                if (-not $selectedFilter) {
                    Write-Warning "No filter selected. Exiting."
                    return
                }
                Write-Host "Selected filter: $selectedFilter" -ForegroundColor Green
            }
            $validationArgs = "--command $selectedCommand --filter $selectedFilter"
        }

        Write-Host ""
        
        if ($selectedCommand -eq "cypress") {
            Write-Host "Cypress selected. You may need to add --testType and --extraCypressOptions manually." -ForegroundColor Yellow
        }

        $fullCommand = "$ScriptPath $validationArgs"
        Write-Host "Executing: $fullCommand" -ForegroundColor Cyan

        if ($PSCmdlet.ShouldProcess($fullCommand)) {
            [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($fullCommand)
            Invoke-Expression $fullCommand
        }
    }
    finally {
        Pop-Location
    }
}

Set-Alias ivs Invoke-ValidationScript


