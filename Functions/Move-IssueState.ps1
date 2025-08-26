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
    
    $labelsToAdd = @($newLabel)
    $labelsToRemove = @()
    
    switch ($NewState) {
        "AwaitingReview" {
            $labelsToAdd += "Needs Engineering Approval"
            $labelsToAdd += "Ready for QA"
        }
        "Done" {
            $labelsToRemove += "Needs Engineering Approval"
            $labelsToRemove += "Ready for QA"
        }
    }
    
    $existingNonStateLabels = $currentLabels | Where-Object { $_ -notin $allStateLabels -and $_ -notin $labelsToRemove }
    $allLabelsToSet = $existingNonStateLabels + $labelsToAdd

    function Update-IssueLabels {
        param($issueNumber, $currentStateLabel, $labelsToRemove, $labelsToAdd)
        
        # Remove labels (including current state label)
        $allLabelsToRemove = @()
        if ($currentStateLabel) {
            $allLabelsToRemove += $currentStateLabel
        }
        $allLabelsToRemove += $labelsToRemove
        
        if ($allLabelsToRemove.Count -gt 0) {
            $removeLabelsString = $allLabelsToRemove -join ","
            $removeArgs = @("issue", "update", $issueNumber, "--unlabel", $removeLabelsString)
            $removeCommandString = "glab " + ($removeArgs -join " ")
            Write-Debug "Remove labels command: $removeCommandString"
            & glab @removeArgs
        }
        
        # Add labels
        if ($labelsToAdd.Count -gt 0) {
            $addLabelsString = $labelsToAdd -join ","
            $addArgs = @("issue", "update", $issueNumber, "--label", $addLabelsString)
            $addCommandString = "glab " + ($addArgs -join " ")
            Write-Debug "Add labels command: $addCommandString"
            & glab @addArgs
        }
    }
    
    if ($PSCmdlet.ShouldProcess("Issue #$IssueNumber", "Update labels")) {
        Update-IssueLabels $IssueNumber $currentStateLabel $labelsToRemove $labelsToAdd
        
        # Find and update associated MR with the same labels
        try {
            $mrListJson = glab mr list --output=json --search "#$IssueNumber" | ConvertFrom-Json
            $relatedMR = $mrListJson | Where-Object { $_.title -match "#$IssueNumber" -or $_.description -match "#$IssueNumber" } | Select-Object -First 1
            
            if ($relatedMR) {
                Write-Debug "Found related MR: !$($relatedMR.iid) - $($relatedMR.title)"
                
                # Update MR labels using the same approach as issues
                function Update-MRLabels {
                    param($mrNumber, $currentStateLabel, $labelsToRemove, $labelsToAdd)
                    
                    # Remove labels (including current state label)
                    $allLabelsToRemove = @()
                    if ($currentStateLabel) {
                        $allLabelsToRemove += $currentStateLabel
                    }
                    $allLabelsToRemove += $labelsToRemove
                    
                    if ($allLabelsToRemove.Count -gt 0) {
                        $removeLabelsString = $allLabelsToRemove -join ","
                        $removeArgs = @("mr", "update", $mrNumber, "--unlabel", $removeLabelsString)
                        $removeCommandString = "glab " + ($removeArgs -join " ")
                        Write-Debug "MR Remove labels command: $removeCommandString"
                        & glab @removeArgs
                    }
                    
                    # Add labels
                    if ($labelsToAdd.Count -gt 0) {
                        $addLabelsString = $labelsToAdd -join ","
                        $addArgs = @("mr", "update", $mrNumber, "--label", $addLabelsString)
                        $addCommandString = "glab " + ($addArgs -join " ")
                        Write-Debug "MR Add labels command: $addCommandString"
                        & glab @addArgs
                    }
                }
                
                Update-MRLabels $relatedMR.iid $currentStateLabel $labelsToRemove $labelsToAdd
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



