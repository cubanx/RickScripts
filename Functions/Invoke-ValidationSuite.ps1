function Invoke-ValidationSuite {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$WorkspacePath = "~/world50/transmute-platform",

        [Parameter()]
        [string]$Filter = "prospector-app",

        [Parameter()]
        [string[]]$Commands = @("router-typecheck", "lint", "prettier", "vitest"),

        [Parameter()]
        [string]$ValidationScript = "./scripts/ci/validation.sh",

        [Parameter()]
        [string]$ResultsDirectory = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "validation-results"),

        [switch]$StopOnFailure
    )

    $resolvedWorkspace = Resolve-Path -Path $WorkspacePath -ErrorAction Stop
    $resolvedWorkspacePath = $resolvedWorkspace.ProviderPath

    if ([System.IO.Path]::IsPathRooted($ValidationScript)) {
        $scriptCandidate = Resolve-Path -Path $ValidationScript -ErrorAction Stop
        $scriptToInvoke = $scriptCandidate.ProviderPath
    }
    else {
        $joinedScriptPath = Join-Path -Path $resolvedWorkspacePath -ChildPath $ValidationScript
        if (-not (Test-Path -Path $joinedScriptPath)) {
            throw "Validation script not found at '$joinedScriptPath'."
        }
        $scriptToInvoke = (Resolve-Path -Path $joinedScriptPath -ErrorAction Stop).ProviderPath
    }

    if (-not (Test-Path -Path $ResultsDirectory)) {
        New-Item -ItemType Directory -Path $ResultsDirectory -Force | Out-Null
    }

    $sessionDirectoryName = Get-Date -Format "yyyyMMdd-HHmmss"
    $sessionDirectory = Join-Path -Path $ResultsDirectory -ChildPath $sessionDirectoryName
    New-Item -ItemType Directory -Path $sessionDirectory -Force | Out-Null

    $results = @()
    $failureSummaries = @()
    $hasFailure = $false

    Push-Location -Path $resolvedWorkspacePath
    try {
        foreach ($command in $Commands) {
            Write-Host "Running validation: $command" -ForegroundColor Cyan

            $logFileName = ($command -replace "[^\w-.]", "_") + ".log"
            $logFile = Join-Path -Path $sessionDirectory -ChildPath $logFileName
            $scriptArguments = @("--command", $command)
            if ($Filter) {
                $scriptArguments += @("--filter", $Filter)
            }

            $capturedLines = [System.Collections.Generic.List[string]]::new()
            $progressId = [Math]::Abs([Guid]::NewGuid().GetHashCode())
            $progressActivity = "Docker build ($command)"
            $progressInitialized = $false

            & $scriptToInvoke @scriptArguments 2>&1 |
                Tee-Object -FilePath $logFile |
                ForEach-Object {
                    $lineObject = $_
                    $lineText = if ($null -ne $lineObject) { $lineObject.ToString() } else { '' }
                    $capturedLines.Add($lineText) | Out-Null

                    if ($lineText) {
                        if (-not $progressInitialized -and $lineText -match '^Building Docker image') {
                            Write-Progress -Id $progressId -Activity $progressActivity -Status $lineText.Trim() -PercentComplete 0
                            $progressInitialized = $true
                        }

                        $fractionMatch = [regex]::Match($lineText, '(\d+)\s*/\s*(\d+)')
                        if ($fractionMatch.Success) {
                            $currentStep = [int]$fractionMatch.Groups[1].Value
                            $totalSteps = [int]$fractionMatch.Groups[2].Value

                            if ($totalSteps -gt 0) {
                                $percentComplete = [math]::Min(100, [math]::Round(($currentStep / $totalSteps) * 100))
                                $statusLine = $lineText.Trim()
                                if ($statusLine.Length -gt 70) {
                                    $statusLine = $statusLine.Substring(0, 70) + '…'
                                }
                                Write-Progress -Id $progressId -Activity $progressActivity -Status $statusLine -PercentComplete $percentComplete
                                $progressInitialized = $true
                            }
                        }
                    }
                } | Out-Null

            if ($progressInitialized) {
                Write-Progress -Id $progressId -Activity $progressActivity -Completed
            }

            $capturedOutput = $capturedLines.ToArray()
            $exitCode = $LASTEXITCODE

            $resultStatus = if ($exitCode -eq 0) { "Success" } else { "Failed" }
            if ($exitCode -ne 0) {
                $hasFailure = $true
                $failureSummaries += [pscustomobject]@{
                    Command  = $command
                    ExitCode = $exitCode
                    LogFile  = $logFile
                }
                Write-Warning ("FAILED: {0} (see {1})" -f $command, $logFile)
            }
            else {
                Write-Host ("Success: {0}" -f $command) -ForegroundColor Green
            }

            $results += [pscustomobject]@{
                Command  = $command
                Status   = $resultStatus
                ExitCode = $exitCode
                LogFile  = $logFile
                Summary  = ($capturedOutput | Select-Object -Last 5) -join [Environment]::NewLine
            }

            if ($exitCode -ne 0 -and $StopOnFailure) {
                break
            }
        }
    }
    finally {
        Pop-Location
    }

    Write-Host
    Write-Host "Validation results stored in: $sessionDirectory" -ForegroundColor Yellow
    foreach ($result in $results) {
        $color = if ($result.Status -eq "Success") { "Green" } else { "Red" }
        $summaryLine = " - {0}: {1}" -f $result.Command, $result.Status
        if ($result.Status -ne "Success") {
            $summaryLine += " (Exit {0})" -f $result.ExitCode
        }
        Write-Host $summaryLine -ForegroundColor $color

        if ($result.Status -ne "Success") {
            Write-Host ("   Log: {0}" -f $result.LogFile) -ForegroundColor DarkGray
        }
    }

    if ($hasFailure) {
        Write-Host
        Write-Host "Failed validations:" -ForegroundColor Red
        foreach ($failure in $failureSummaries) {
            Write-Host (" - {0}: Exit {1}" -f $failure.Command, $failure.ExitCode) -ForegroundColor Red
            Write-Host ("   Log: {0}" -f $failure.LogFile) -ForegroundColor DarkGray
        }

        Write-Error "One or more validation commands failed. Review the logs under '$sessionDirectory'." -ErrorAction Continue
        return $results | Where-Object { $_.Status -ne "Success" }
    }

    return
}

Set-Alias ivsuite Invoke-ValidationSuite



