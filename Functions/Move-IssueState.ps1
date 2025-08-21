function Move-IssueState {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$IssueNumber,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("ToDo", "InDev", "AwaitingReview", "Done")]
        [string]$NewState
    )
    
    $stateLabels = @{
        "ToDo"           = "P::TO DO"
        "InDev"          = "P::IN DEV"
        "AwaitingReview" = "P::AWAITING REVIEW"
        "Done"           = "P::DONE"
    }
    
    $allStateLabels = $stateLabels.Values
    
    if (-not $IssueNumber) {
        $currentBranch = git branch --show-current
        if ($currentBranch -match '(\d+)') {
            $IssueNumber = $matches[1]
            Write-Debug "Extracted issue number $IssueNumber from branch: $currentBranch"
        }
        else {
            Write-Error "Could not extract issue number from branch name: $currentBranch"
            Write-Debug "Please specify the issue number manually or ensure your branch name contains the issue number"
            return
        }
    }
    
    $issueJson = glab issue view $IssueNumber --output=json | ConvertFrom-Json
    $currentLabels = $issueJson.labels
    
    Write-Debug "Current issue: #$IssueNumber - $($issueJson.title)"
    Write-Debug "Current labels: $($currentLabels -join ', ')"
    
    $currentStateLabel = $currentLabels | Where-Object { $_ -in $allStateLabels } | Select-Object -First 1
    
    if ($currentStateLabel) {
        Write-Debug "Current state: $currentStateLabel"
    }
    else {
        Write-Debug "No current state label found"
    }
    
    $newLabel = $stateLabels[$NewState]
    
    if ($currentStateLabel -eq $newLabel) {
        Write-Debug "Issue #$IssueNumber is already in state: $NewState"
        return
    }
    
    Write-Debug "Moving issue #$IssueNumber from '$currentStateLabel' to '$NewState'"
    
    $glabArgs = @("issue", "update", $IssueNumber)
    
    if ($currentStateLabel) {
        $glabArgs += "--unlabel"
        $glabArgs += $currentStateLabel
    }
    
    $labelsToAdd = @($newLabel)
    
    if ($NewState -eq "AwaitingReview") {
        $labelsToAdd += "Needs Engineering Approval"
        $labelsToAdd += "Ready for QA"
    }
    
    $existingNonStateLabels = $currentLabels | Where-Object { $_ -notin $allStateLabels }
    $allLabelsToSet = $existingNonStateLabels + $labelsToAdd
    
    foreach ($label in $allLabelsToSet) {
        $glabArgs += "--label"
        $glabArgs += $label
    }
    
    $commandString = "glab " + ($glabArgs -join " ")
    
    Write-Debug "Command to execute: $commandString"
    
    if ($PSCmdlet.ShouldProcess("Issue #$IssueNumber", "Execute: $commandString")) {
        & glab @glabArgs
        
        # Find and update associated MR with the same labels
        try {
            $mrListJson = glab mr list --output=json --search "#$IssueNumber" | ConvertFrom-Json
            $relatedMR = $mrListJson | Where-Object { $_.title -match "#$IssueNumber" -or $_.description -match "#$IssueNumber" } | Select-Object -First 1
            
            if ($relatedMR) {
                Write-Debug "Found related MR: !$($relatedMR.iid) - $($relatedMR.title)"
                
                $mrGlabArgs = @("mr", "update", $relatedMR.iid)
                
                if ($currentStateLabel) {
                    $mrGlabArgs += "--unlabel"
                    $mrGlabArgs += $currentStateLabel
                }
                
                foreach ($label in $allLabelsToSet) {
                    $mrGlabArgs += "--label"
                    $mrGlabArgs += $label
                }
                
                $mrCommandString = "glab " + ($mrGlabArgs -join " ")
                Write-Debug "MR Command to execute: $mrCommandString"
                
                & glab @mrGlabArgs
            }
            else {
                Write-Debug "No related MR found for issue #$IssueNumber"
            }
        }
        catch {
            Write-Debug "Error finding or updating related MR: $($_.Exception.Message)"
        }
    }
}

Set-Alias mis Move-IssueState

