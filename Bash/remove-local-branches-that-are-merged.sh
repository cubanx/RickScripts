#!/bin/bash

remove_local_branches_that_are_merged() {
    echo "Fetching latest updates..."
    git fetch --prune
    
    echo "Detecting main branch..."
    main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    
    if [[ -z "$main_branch" ]]; then
        echo "Could not detect main branch. Trying common names..."
        if git show-ref --verify --quiet refs/remotes/origin/main; then
            main_branch="main"
        elif git show-ref --verify --quiet refs/remotes/origin/master; then
            main_branch="master"
        else
            echo "Could not determine main branch"
            return 1
        fi
    fi
    
    echo "Using main branch: $main_branch"
    
    echo "Finding merged branches..."
    merged_branches=$(git branch --merged "origin/$main_branch" | grep -v "^\*" | grep -v "^\s*$main_branch$" | sed 's/^[[:space:]]*//')
    
    if [[ -z "$merged_branches" ]]; then
        echo "No merged branches to remove"
        return 0
    fi
    
    echo "Merged branches to remove:"
    echo "$merged_branches"
    
    echo "$merged_branches" | while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            echo "Removing branch: $branch"
            git branch -d "$branch"
        fi
    done
    
    echo "Pruning remote-tracking branches..."
    git remote prune origin
    
    echo "Cleanup complete"
}

alias rlb='remove_local_branches_that_are_merged'