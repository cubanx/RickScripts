#!/bin/bash

remove_history_duplicates() {
    local restore_mode=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--restore)
                restore_mode=true
                shift
                ;;
            -h|--help)
                echo "Usage: remove_history_duplicates [OPTIONS]"
                echo "Options:"
                echo "  -r, --restore    Restore from backup instead of removing duplicates"
                echo "  -h, --help       Show this help message"
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done
    
    local history_file="${HISTFILE:-$HOME/.bash_history}"
    local history_dir=$(dirname "$history_file")
    local history_filename=$(basename "$history_file")
    local history_basename="${history_filename%.*}"
    local history_extension="${history_filename##*.}"
    
    if [[ "$history_extension" == "$history_filename" ]]; then
        history_extension=""
    else
        history_extension=".$history_extension"
    fi
    
    if [[ ! -f "$history_file" ]]; then
        echo "Warning: History file not found: $history_file" >&2
        return 1
    fi
    
    if [[ "$restore_mode" == true ]]; then
        # Find available backup files
        local backup_pattern="${history_basename}.backup.*${history_extension}"
        local backup_files=($(find "$history_dir" -name "$backup_pattern" | sort))
        
        if [[ ${#backup_files[@]} -eq 0 ]]; then
            echo "Warning: No backup files found" >&2
            return 1
        fi
        
        # Display available backups with fzf
        local backup_options=()
        for backup in "${backup_files[@]}"; do
            local backup_name=$(basename "$backup")
            local backup_number=$(echo "$backup_name" | cut -d'.' -f3)
            local backup_date=$(stat -c "%Y" "$backup" | xargs -I {} date -d "@{}" "+%Y-%m-%d %H:%M:%S")
            backup_options+=("$backup_number : $backup_date : $backup_name")
        done
        
        local selected_backup
        selected_backup=$(printf '%s\n' "${backup_options[@]}" | fzf --ansi --height 40% --reverse --prompt 'Select backup to restore: ')
        
        if [[ -z "$selected_backup" ]]; then
            echo "No backup selected"
            return 0
        fi
        
        local selected_backup_file=$(echo "$selected_backup" | cut -d' : ' -f3)
        local backup_path="$history_dir/$selected_backup_file"
        
        read -p "Restore backup $selected_backup_file? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp "$backup_path" "$history_file"
            echo "Restored backup: $selected_backup_file"
        else
            echo "Operation cancelled"
        fi
        return 0
    fi
    
    # Read all history items
    if [[ ! -s "$history_file" ]]; then
        echo "No history items found"
        return 0
    fi
    
    mapfile -t history_items < "$history_file"
    local original_count=${#history_items[@]}
    
    if [[ $original_count -eq 0 ]]; then
        echo "No history items found"
        return 0
    fi
    
    echo "Original history contains $original_count items"
    
    # Remove duplicates while preserving order (keeps last occurrence)
    local unique_items=()
    local seen=()
    
    # Process from end to beginning to keep most recent occurrence
    for ((i=original_count-1; i>=0; i--)); do
        local item="${history_items[i]}"
        local found=false
        
        for seen_item in "${seen[@]}"; do
            if [[ "$item" == "$seen_item" ]]; then
                found=true
                break
            fi
        done
        
        if [[ "$found" == false ]]; then
            seen+=("$item")
            unique_items=("$item" "${unique_items[@]}")
        fi
    done
    
    local duplicate_count=$((original_count - ${#unique_items[@]}))
    
    if [[ $duplicate_count -eq 0 ]]; then
        echo "No duplicates found in history"
        return 0
    fi
    
    echo "Found $duplicate_count duplicate items"
    
    read -p "Remove $duplicate_count duplicate history items? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Create backup before making changes
        local backup_number=1
        local backup_file="${history_basename}.backup.${backup_number}${history_extension}"
        local backup_path="$history_dir/$backup_file"
        
        while [[ -f "$backup_path" ]]; do
            ((backup_number++))
            backup_file="${history_basename}.backup.${backup_number}${history_extension}"
            backup_path="$history_dir/$backup_file"
        done
        
        # Create the backup
        cp "$history_file" "$backup_path"
        echo "Created backup: $backup_file"
        
        # Clean up old backups (keep only 10 most recent)
        local all_backups=($(find "$history_dir" -name "${history_basename}.backup.*${history_extension}" | sort -V -r))
        
        if [[ ${#all_backups[@]} -gt 10 ]]; then
            for ((i=10; i<${#all_backups[@]}; i++)); do
                local old_backup="${all_backups[i]}"
                rm -f "$old_backup"
                echo "Deleted old backup: $(basename "$old_backup")"
            done
        fi
        
        # Write the deduplicated history back to file
        printf '%s\n' "${unique_items[@]}" > "$history_file"
        
        echo "Removed $duplicate_count duplicate items from history"
        echo "History now contains ${#unique_items[@]} unique items"
    else
        echo "Operation cancelled"
    fi
}

alias rhd='remove_history_duplicates'