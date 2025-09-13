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
        $sourceMr = glab mr view $SourceMrId --json | ConvertFrom-Json
        
        if (-not $sourceMr) {
            Write-Error "Could not retrieve merge request $SourceMrId"
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
            "`"$title`"",
            "--description",
            "`"$description`""
        )

        if ($sourceMr.labels -and $sourceMr.labels.Count -gt 0) {
            foreach ($label in $sourceMr.labels) {
                $glabArgs += "--label"
                $glabArgs += "`"$label`""
            }
        }

        if ($sourceMr.assignees -and $sourceMr.assignees.Count -gt 0) {
            foreach ($assignee in $sourceMr.assignees) {
                $glabArgs += "--assignee"
                $glabArgs += "@$($assignee.username)"
            }
        }

        if ($sourceMr.reviewers -and $sourceMr.reviewers.Count -gt 0) {
            foreach ($reviewer in $sourceMr.reviewers) {
                $glabArgs += "--reviewer"
                $glabArgs += "@$($reviewer.username)"
            }
        }

        if ($sourceMr.milestone) {
            $glabArgs += "--milestone"
            $glabArgs += "`"$($sourceMr.milestone.title)`""
        }

        if ($sourceMr.draft) {
            $glabArgs += "--draft"
        }

        if ($sourceMr.remove_source_branch) {
            $glabArgs += "--remove-source-branch"
        }

        if ($sourceMr.squash) {
            $glabArgs += "--squash"
        }

        Write-Verbose "Creating merge request with command: glab $($glabArgs -join ' ')"

        if ($PSCmdlet.ShouldProcess("glab $($glabArgs -join ' ')")) {
            Invoke-Expression "glab $($glabArgs -join ' ')"
        }
    }
    catch {
        Write-Error "Failed to copy merge request: $($_.Exception.Message)"
    }
}

Set-Alias cmr Copy-MergeRequest
