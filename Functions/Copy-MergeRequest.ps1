function Copy-MergeRequest {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [int]$SourceMrId,
        
        [Parameter(Mandatory = $true)]
        [string]$NewBranchName
    )

    if ($NewBranchName.Length -gt 50) {
        Write-Error "Branch name cannot be longer than 50 characters. Current length: $($NewBranchName.Length)"
        return
    }

    try {
        $sourceMrJson = glab mr view $SourceMrId --output json 2>$null

        if (-not $sourceMrJson) {
            Write-Error "Could not retrieve merge request $SourceMrId"
            return
        }

        $sourceMr = $sourceMrJson | ConvertFrom-Json

        if (-not $sourceMr) {
            Write-Error "Could not parse merge request payload for $SourceMrId"
            return
        }

        $title = $sourceMr.title
        $description = $sourceMr.description
        $targetBranch = $sourceMr.target_branch
        
        $glabArgs = @(
            "mr",
            "create",
            "--yes",
            "--source-branch",
            $NewBranchName,
            "--target-branch",
            $targetBranch,
            "--title",
            $title,
            "--description",
            $description
        )

        if ($sourceMr.labels -and $sourceMr.labels.Count -gt 0) {
            foreach ($label in $sourceMr.labels) {
                $glabArgs += "--label"
                $glabArgs += $label
            }
        }

        if ($sourceMr.assignees -and $sourceMr.assignees.Count -gt 0) {
            foreach ($assignee in $sourceMr.assignees) {
                $glabArgs += "--assignee"
                $glabArgs += $assignee.username
            }
        }

        if ($sourceMr.reviewers -and $sourceMr.reviewers.Count -gt 0) {
            foreach ($reviewer in $sourceMr.reviewers) {
                $glabArgs += "--reviewer"
                $glabArgs += $reviewer.username
            }
        }

        if ($sourceMr.milestone) {
            $glabArgs += "--milestone"
            $glabArgs += $sourceMr.milestone.title
        }

        if ($sourceMr.should_remove_source_branch -or $sourceMr.force_remove_source_branch -or $sourceMr.remove_source_branch) {
            $glabArgs += "--remove-source-branch"
        }

        if ($sourceMr.squash) {
            $glabArgs += "--squash"
        }

        $commandPreview = "glab " + (
            $glabArgs | ForEach-Object {
                if ($_ -match '"') {
                    '"' + ($_ -replace '"', '\\"') + '"'
                }
                elseif ($_ -match "\s" -or $_ -like "*@*") {
                    '"' + $_ + '"'
                }
                else {
                    $_
                }
            }
        ) -join ' '

        Write-Verbose "Creating merge request with command: $commandPreview"

        if ($PSCmdlet.ShouldProcess($commandPreview)) {
            & glab @glabArgs
        }
    }
    catch {
        Write-Error "Failed to copy merge request: $($_.Exception.Message)"
    }
}

Set-Alias cmr Copy-MergeRequest


