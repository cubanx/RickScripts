#!/bin/bash

switch_branch() {
    echo "Fetching latest changes..."
    git fetch
    
    all_branches=$(git branch -a | sed 's/^[[:space:]]*//' | sed 's/^\*//' | sed 's/^[[:space:]]*//' | grep -v "HEAD" | sort -u)
    
    selected_branch=$(echo "$all_branches" | fzf --height=20 --reverse)
    
    if [[ -n "$selected_branch" ]]; then
        if [[ "$selected_branch" == remotes/origin/* ]]; then
            local_branch=$(echo "$selected_branch" | sed 's|remotes/origin/||')
            echo "Checking out remote branch as local: $local_branch"
            git checkout -b "$local_branch" "$selected_branch"
        else
            echo "Switching to local branch: $selected_branch"
            git checkout "$selected_branch"
        fi
    fi
}

alias sb='switch_branch'