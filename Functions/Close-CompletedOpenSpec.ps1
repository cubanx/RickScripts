function Close-CompletedOpenSpec {
    [CmdletBinding()]
    param()

    $root = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
        throw 'Close-CompletedOpenSpec must run inside a Git repository.'
    }

    Push-Location -LiteralPath $root
    try {
        $currentBranch = [Convert]::ToString((& git branch --show-current)).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Could not determine the current Git branch.' }
        if ($currentBranch -ne 'main') {
            $mainWorktree = $null
            $worktreePath = $null
            foreach ($line in @(& git worktree list --porcelain)) {
                if ($line -like 'worktree *') { $worktreePath = $line.Substring(9) }
                elseif ($line -eq 'branch refs/heads/main') { $mainWorktree = $worktreePath; break }
            }

            if ($mainWorktree) {
                throw "Run this from the main worktree: Set-Location -LiteralPath '$mainWorktree'; Close-CompletedOpenSpec"
            }
            throw 'Switch to main and rerun: git switch main; git pull --ff-only; Close-CompletedOpenSpec'
        }

        $status = @(& git status --porcelain)
        if ($LASTEXITCODE -ne 0) { throw 'Could not read Git status.' }
        if ($status) { throw 'The main worktree must be clean before closing OpenSpecs.' }

        & git fetch origin main | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not fetch origin/main.' }

        $counts = ((& git rev-list --left-right --count 'origin/main...HEAD') | Select-Object -First 1) -split '\s+'
        if ($LASTEXITCODE -ne 0 -or $counts.Count -ne 2) { throw 'Could not compare main with origin/main.' }
        $behind = [int]$counts[0]
        $ahead = [int]$counts[1]
        if ($behind -gt 0 -and $ahead -gt 0) { throw 'Local main has diverged from origin/main; reconcile it before closing OpenSpecs.' }
        if ($ahead -gt 0) { throw 'Local main is ahead of origin/main; publish or reconcile it before closing OpenSpecs.' }
        if ($behind -gt 0) {
            & git merge --ff-only origin/main | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not fast-forward main to origin/main.' }
        }

        $listOutput = (& openspec list --json | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Could not list OpenSpec changes.' }
        try { $changeList = $listOutput | ConvertFrom-Json -ErrorAction Stop }
        catch { throw "Could not parse OpenSpec change list: $($_.Exception.Message)" }

        $completed = @($changeList.changes | Where-Object { $_.status -eq 'complete' } | Sort-Object lastModified, name)
        if (-not $completed) {
            Write-Host 'No completed OpenSpecs to close.'
            return @()
        }

        $archiveDate = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
        $results = [System.Collections.Generic.List[object]]::new()
        $failures = [System.Collections.Generic.List[object]]::new()
        foreach ($change in $completed) {
            $source = Join-Path $root "openspec/changes/$($change.name)"
            $destination = Join-Path $root "openspec/changes/archive/$archiveDate-$($change.name)"

            $details = if (-not (Test-Path -LiteralPath $source -PathType Container)) {
                "Missing change directory: $source"
            }
            elseif (Test-Path -LiteralPath $destination) {
                "Archive target already exists: $destination"
            }
            else {
                $archiveOutput = @(& openspec archive $change.name -y 2>&1)
                $archiveExitCode = $LASTEXITCODE
                if ($archiveExitCode -ne 0 -or (Test-Path -LiteralPath $source) -or -not (Test-Path -LiteralPath $destination -PathType Container)) {
                    ($archiveOutput | ForEach-Object { [string]$_ }) -join ' '
                }
            }

            if ($null -ne $details) {
                if ([string]::IsNullOrWhiteSpace($details)) { $details = 'OpenSpec did not create the expected archive.' }
                $result = [PSCustomObject]@{ OpenSpec = [string]$change.name; Status = 'Failed'; Details = $details }
                $failures.Add($result)
                $results.Add($result)
                continue
            }

            $results.Add([PSCustomObject]@{ OpenSpec = [string]$change.name; Status = 'Archived'; Details = '' })
        }

        if ($failures.Count -gt 0) {
            $results.ToArray()
            $failureList = ($failures | ForEach-Object { "- $($_.OpenSpec): $($_.Details)" }) -join [Environment]::NewLine
            $prompt = @"
Repair only the failed OpenSpec changes below in repository '$root'. Preserve successful archives already present in the worktree. Resolve the underlying spec conflicts; do not use --skip-specs unless a conflicting spec is proven obsolete. Archive each repaired change, then run openspec validate --changes --strict and openspec validate --specs --strict. Do not commit.

Failures:
$failureList
"@
            try { Set-Clipboard -Value $prompt -ErrorAction Stop }
            catch { throw "Could not copy the LLM repair prompt to the clipboard: $($_.Exception.Message)`n`n$prompt" }
            throw 'One or more completed OpenSpecs could not be archived. Successful archives remain uncommitted. LLM repair prompt copied to the clipboard.'
        }

        $specValidation = @(& openspec validate --specs --strict 2>&1)
        $specValidationExitCode = $LASTEXITCODE
        $changeValidation = @(& openspec validate --changes --strict 2>&1)
        $changeValidationExitCode = $LASTEXITCODE
        if ($specValidationExitCode -ne 0 -or $changeValidationExitCode -ne 0) {
            $details = @($specValidation + $changeValidation | ForEach-Object { [string]$_ }) -join ' '
            throw "Strict OpenSpec validation failed: $details Successful archives remain uncommitted."
        }

        & git @('add', '-A', '--', 'openspec')
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage archived OpenSpecs.' }
        & git -c core.whitespace=-blank-at-eof diff --cached --check
        if ($LASTEXITCODE -ne 0) { throw 'The staged OpenSpec diff failed Git whitespace validation.' }
        $stagedPaths = @(& git diff --cached --name-only)
        if ($LASTEXITCODE -ne 0 -or -not $stagedPaths) { throw 'Archiving produced no staged changes.' }
        if (@($stagedPaths | Where-Object { $_ -notlike 'openspec/*' })) { throw 'Refusing to commit staged paths outside openspec/.' }

        & git commit -m 'chore: Archived completed OpenSpecs'
        if ($LASTEXITCODE -ne 0) { throw 'Could not commit archived OpenSpecs.' }
        $commit = ((& git rev-parse HEAD) | Select-Object -First 1).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Could not read the archive commit SHA.' }

        foreach ($result in $results) {
            $result.Status = 'Committed'
            $result.Details = $commit
        }

        return $results.ToArray()
    }
    finally {
        Pop-Location
    }
}
