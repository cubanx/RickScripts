#!/bin/bash

get_git_stash() {
    stashes=$(git stash list)
    
    if [[ -z "$stashes" ]]; then
        echo "No stashes found"
        return 0
    fi
    
    selected_stash=$(echo "$stashes" | fzf --height=20 --reverse)
    
    if [[ -n "$selected_stash" ]]; then
        stash_ref=$(echo "$selected_stash" | sed 's/:.*//')
        echo "Popping stash: $stash_ref"
        git stash pop "$stash_ref"
    fi
}

alias ggs='get_git_stash'