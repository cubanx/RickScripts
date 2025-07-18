#!/bin/bash

switch_merge_request() {
    echo "Fetching merge requests..."
    
    mrs=$(glab mr list --output=json | jq -r '.[] | "\(.iid) - \(.title) (by \(.author.name))"')
    
    if [[ -z "$mrs" ]]; then
        echo "No merge requests found"
        return 0
    fi
    
    selected_mr=$(echo "$mrs" | fzf --height=20 --reverse)
    
    if [[ -n "$selected_mr" ]]; then
        mr_id=$(echo "$selected_mr" | cut -d' ' -f1)
        echo "Checking out merge request: $mr_id"
        glab mr checkout "$mr_id"
    fi
}

alias smr='switch_merge_request'