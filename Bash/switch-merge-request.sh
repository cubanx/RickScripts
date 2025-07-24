#!/bin/bash

get_rickscripts_config() {
    local config_path="$HOME/.RickScripts/config.json"
    local config_dir
    config_dir=$(dirname "$config_path")
    
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir"
    fi
    
    if [[ -f "$config_path" ]]; then
        cat "$config_path"
    else
        echo '{"projectForPath": {}}'
    fi
}

set_rickscripts_config() {
    local config="$1"
    local config_path="$HOME/.RickScripts/config.json"
    echo "$config" > "$config_path"
}

get_project_labels() {
    local folder_name="${1:-$(basename "$PWD")}"
    local config
    config=$(get_rickscripts_config)
    
    if command -v jq >/dev/null 2>&1; then
        echo "$config" | jq -r ".projectForPath[\"$folder_name\"] // empty | if type == \"array\" then .[] else empty end" 2>/dev/null | tr '\n' ','
    fi
}

set_project_labels() {
    local labels_array=("$@")
    local folder_name
    folder_name=$(basename "$PWD")
    local config
    config=$(get_rickscripts_config)
    
    if command -v jq >/dev/null 2>&1; then
        local labels_json
        printf -v labels_json '[%s]' "$(printf '"%s",' "${labels_array[@]}" | sed 's/,$//')"
        config=$(echo "$config" | jq ".projectForPath[\"$folder_name\"] = $labels_json")
        set_rickscripts_config "$config"
        echo "✅ Set labels for folder '$folder_name': $(IFS=', '; echo "${labels_array[*]}")"
    fi
}

remove_project_labels() {
    local folder_name
    folder_name=$(basename "$PWD")
    local config
    config=$(get_rickscripts_config)
    
    if command -v jq >/dev/null 2>&1; then
        config=$(echo "$config" | jq "del(.projectForPath[\"$folder_name\"])")
        set_rickscripts_config "$config"
        echo "✅ Cleared labels for folder '$folder_name'"
    fi
}

switch_merge_request() {
    local set_labels=false
    local reset_labels=false
    local labels_to_set=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --set-project-for-path)
                set_labels=true
                shift
                while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                    labels_to_set+=("$1")
                    shift
                done
                ;;
            --reset-project-for-path)
                reset_labels=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ "$set_labels" == true ]]; then
        set_project_labels "${labels_to_set[@]}"
    fi
    
    if [[ "$reset_labels" == true ]]; then
        remove_project_labels
    fi
    
    local labels
    labels=$(get_project_labels | sed 's/,$//')
    if [[ -z "$labels" ]]; then
        labels="${W50_MERGE_REQUEST_LABELS}"
    fi
    
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
    else
        echo "No merge request selected"
    fi
}

alias smr='switch_merge_request'