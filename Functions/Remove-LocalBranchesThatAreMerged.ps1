function Remove-LocalBranchesThatAreMerged {
    # Fetch the latest updates from the remote repository, including pruning deleted branches
    git fetch --all --prune

    # Get the name of the main branch
    $MAIN_BRANCH = git remote show origin | Select-String -Pattern 'HEAD branch' | ForEach-Object { ($_ -split ': ')[1].Trim() }

    # Get a list of branches merged into MAIN_BRANCH, excluding MAIN_BRANCH itself
    $MERGED_BRANCHES = git branch --merged $MAIN_BRANCH | Where-Object { $_ -notmatch $MAIN_BRANCH } | ForEach-Object { $_.Trim() }

    # Delete each merged branch
    foreach ($branch in $MERGED_BRANCHES) {
        Write-Output "Removing branch <$branch>"
        git branch -d $branch
    }

    # Prune remote-tracking branches that no longer exist on the remote
    git remote prune origin
}

Set-Alias rlb Remove-LocalBranchesThatAreMerged
