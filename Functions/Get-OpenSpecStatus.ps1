function Get-OpenSpecStatus {
    <#
    .SYNOPSIS
    Reports the OpenSpec change associated with the current Git worktree.

    .DESCRIPTION
    Uses an explicit change name or conservatively infers one from dirty OpenSpec paths,
    the current branch, branch changes, the current commit, or branch-name similarity.
    Ambiguous changes are selected with fzf. Artifact status comes from OpenSpec itself.

    .EXAMPLE
    Get-OpenSpecStatus

    Infers the current change and reports its artifact and task progress.

    .EXAMPLE
    Get-OpenSpecStatus -Change add-wormhole-routing

    Reports a specific active change without Git inference.
    #>
    [CmdletBinding()]
    param(
        [string]$Change
    )

    $previousTelemetry = [Environment]::GetEnvironmentVariable('OPENSPEC_TELEMETRY', 'Process')
    $env:OPENSPEC_TELEMETRY = '0'
    try {
    $listOutput = (& openspec list --json | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not list OpenSpec changes: $listOutput" }
    try { $changeList = $listOutput | ConvertFrom-Json }
    catch { throw "Could not parse OpenSpec change list: $($_.Exception.Message)" }

    $changes = @($changeList.changes)
    if (-not $changes) { throw 'No active OpenSpec changes found.' }
    $activeNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $changes | ForEach-Object { [void]$activeNames.Add([string]$_.name) }

    function Get-ActiveChangeNamesFromPaths {
        param([object[]]$Paths)

        $found = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($path in $Paths) {
            foreach ($match in [regex]::Matches([string]$path, 'openspec/changes/([^/]+)/')) {
                $name = $match.Groups[1].Value
                if ($activeNames.Contains($name)) { [void]$found.Add($name) }
            }
        }
        return @($found)
    }

    function Get-MeaningfulTokens {
        param([string]$Name)

        $ignored = @('add', 'and', 'fix', 'for', 'from', 'improve', 'into', 'propose', 'proposal', 'remove', 'replace', 'the', 'use', 'with')
        return @($Name.ToLowerInvariant() -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 3 -and $_ -notin $ignored } | Select-Object -Unique)
    }

    $selected = $null
    if ($Change) {
        $selected = $changes | Where-Object { $_.name -eq $Change } | Select-Object -First 1
        if (-not $selected) { throw "'$Change' is not an active OpenSpec change." }
    }
    else {
        $gitStatus = @(& git status --porcelain=v1 --untracked-files=all)
        if ($LASTEXITCODE -ne 0) { throw 'Could not read Git worktree status.' }
        $dirtyNames = @(Get-ActiveChangeNamesFromPaths -Paths $gitStatus)
        $requiresPicker = $dirtyNames.Count -gt 1
        if ($dirtyNames.Count -eq 1) {
            $selected = $changes | Where-Object { $_.name -eq $dirtyNames[0] } | Select-Object -First 1
            Write-Verbose "Selected '$($selected.name)' from the dirty OpenSpec path."
        }

        if (-not $selected -and -not $requiresPicker) {
            $currentBranch = [Convert]::ToString((& git branch --show-current | Select-Object -First 1)).Trim()
            if ($LASTEXITCODE -ne 0) { throw 'Could not read the current Git branch.' }
            if ($currentBranch) {
                $branchSuffix = ($currentBranch -split '/')[-1]
                $selected = $changes | Where-Object { $_.name -eq $branchSuffix } | Select-Object -First 1
                if ($selected) { Write-Verbose "Selected '$($selected.name)' from the current branch." }

                if (-not $selected) {
                    $originHead = [Convert]::ToString((& git symbolic-ref --quiet --short refs/remotes/origin/HEAD | Select-Object -First 1)).Trim()
                    if ($LASTEXITCODE -eq 0 -and $originHead) {
                        $mergeBase = [Convert]::ToString((& git merge-base HEAD $originHead | Select-Object -First 1)).Trim()
                        if ($LASTEXITCODE -eq 0 -and $mergeBase) {
                            $branchPaths = @(& git diff --name-only $mergeBase HEAD)
                            if ($LASTEXITCODE -eq 0) {
                                $branchNames = @(Get-ActiveChangeNamesFromPaths -Paths $branchPaths)
                                if ($branchNames.Count -eq 1) {
                                    $selected = $changes | Where-Object { $_.name -eq $branchNames[0] } | Select-Object -First 1
                                    Write-Verbose "Selected '$($selected.name)' from the branch diff."
                                }
                            }
                            else { Write-Debug 'Skipping OpenSpec branch-diff inference because git diff failed.' }
                        }
                        else { Write-Debug 'Skipping OpenSpec branch-diff inference because git merge-base failed.' }
                    }
                    else { Write-Debug 'Skipping OpenSpec branch-diff inference because origin/HEAD is unavailable.' }
                }

                if (-not $selected) {
                    $headPaths = @(& git show --format= --name-only HEAD -- openspec/changes ':(exclude)openspec/changes/archive/**')
                    if ($LASTEXITCODE -eq 0) {
                        $headNames = @(Get-ActiveChangeNamesFromPaths -Paths $headPaths)
                        if ($headNames.Count -eq 1) {
                            $selected = $changes | Where-Object { $_.name -eq $headNames[0] } | Select-Object -First 1
                            Write-Verbose "Selected '$($selected.name)' from the current commit."
                        }
                    }
                    else { Write-Debug 'Skipping OpenSpec HEAD inference because git show failed.' }
                }

                if (-not $selected) {
                    $branchTokens = @(Get-MeaningfulTokens -Name $branchSuffix)
                    $ranked = @($changes | ForEach-Object {
                        $name = [string]$_.name
                        $score = @(Get-MeaningfulTokens -Name $name | Where-Object { $_ -in $branchTokens }).Count
                        if ($score -ge 3) { [PSCustomObject]@{ Change = $_; Score = $score } }
                    } | Sort-Object Score -Descending)
                    if ($ranked -and @($ranked | Where-Object { $_.Score -eq $ranked[0].Score }).Count -eq 1) {
                        $selected = $ranked[0].Change
                        Write-Verbose "Selected '$($selected.name)' from branch-name similarity."
                    }
                }
            }
        }

        if (-not $selected) {
            if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
                throw 'Could not determine the current OpenSpec change and fzf is unavailable. Use -Change.'
            }
            $picked = [Convert]::ToString(($changes.name | fzf --prompt 'Pick an OpenSpec change: ' | Select-Object -First 1)).Trim()
            if (-not $picked) { throw 'Could not determine the current OpenSpec change. Use -Change.' }
            $selected = $changes | Where-Object { $_.name -eq $picked } | Select-Object -First 1
            if (-not $selected) { throw "fzf returned unknown OpenSpec change '$picked'." }
        }
    }

    $statusOutput = @(& openspec status --change $selected.name)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not report OpenSpec status for '$($selected.name)': $(($statusOutput | Out-String).Trim())"
    }
    $statusOutput
    "Tasks: $($selected.completedTasks)/$($selected.totalTasks) complete ($($selected.status))"
    }
    finally {
        [Environment]::SetEnvironmentVariable('OPENSPEC_TELEMETRY', $previousTelemetry, 'Process')
    }
}

Set-Alias goss Get-OpenSpecStatus
