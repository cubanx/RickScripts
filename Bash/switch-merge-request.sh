#!/bin/bash

switch_merge_request() {
    local labels="${1:-${W50_MERGE_REQUEST_LABELS}}"
    
    echo "Fetching merge requests..."
    
    local glab_cmd="glab mr list --output=json"
    if [[ -n "$labels" ]]; then
        glab_cmd+=" --label \"$labels\""
    fi
    
    local json_output
    json_output=$(eval "$glab_cmd")
    
    if [[ -z "$json_output" || "$json_output" == "[]" ]]; then
        echo "No merge requests found"
        return 0
    fi
    
    local mrs
    mrs=$(echo "$json_output" | jq -r '.[] | "\(.iid) \(.title)"')
    
    if [[ -z "$mrs" ]]; then
        echo "No merge requests found"
        return 0
    fi
    
    local selected_mr
    selected_mr=$(echo "$mrs" | fzf --height=20 --reverse)
    
    if [[ -n "$selected_mr" ]]; then
        local mr_id
        mr_id=$(echo "$selected_mr" | cut -d' ' -f1)
        echo "✅ Switching to merge request $mr_id"
        glab mr checkout "$mr_id"
    fi
}

alias smr='switch_merge_request'