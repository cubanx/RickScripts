#!/bin/bash

remove_history_item() {
    local history_file="${HISTFILE:-$HOME/.bash_history}"
    
    if [[ ! -f "$history_file" ]]; then
        echo "Warning: History file not found: $history_file" >&2
        return 1
    fi
    
    if [[ ! -s "$history_file" ]]; then
        echo "No history items found"
        return 0
    fi
    
    # Read all history items into an array
    mapfile -t history_items < "$history_file"
    
    if [[ ${#history_items[@]} -eq 0 ]]; then
        echo "No history items found"
        return 0
    fi
    
    # Create numbered list with most recent first (reverse order)
    local numbered_items=()
    for ((i=${#history_items[@]}-1; i>=0; i--)); do
        numbered_items+=("$(printf "%04d: %s" $((${#history_items[@]}-i)) "${history_items[i]}")")
    done
    
    # Use fzf to select items to delete (allow multiple selection)
    local selected_items
    selected_items=$(printf '%s\n' "${numbered_items[@]}" | fzf --multi --ansi --height 40% --reverse --prompt 'Select history items to delete (Tab for multi-select): ')
    
    if [[ -z "$selected_items" ]]; then
        echo "No items selected"
        return 0
    fi
    
    # Extract the original commands from selected items
    local commands_to_delete=()
    while IFS= read -r item; do
        if [[ "$item" =~ ^[0-9]{4}:[[:space:]](.+)$ ]]; then
            commands_to_delete+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$selected_items"
    
    echo "Selected ${#commands_to_delete[@]} items to delete:"
    for cmd in "${commands_to_delete[@]}"; do
        echo "  $cmd"
    done
    
    read -p "Delete these items? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Create new history without the selected items
        local new_history=()
        for history_item in "${history_items[@]}"; do
            local found=false
            for cmd in "${commands_to_delete[@]}"; do
                if [[ "$history_item" == "$cmd" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == false ]]; then
                new_history+=("$history_item")
            fi
        done
        
        # Write the updated history back to file
        printf '%s\n' "${new_history[@]}" > "$history_file"
        
        echo "Deleted ${#commands_to_delete[@]} items from history"
        echo "Remaining items: ${#new_history[@]}"
    else
        echo "Operation cancelled"
    fi
}

alias rhi='remove_history_item'