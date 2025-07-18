#!/bin/bash

open_project_folder() {
    # Find directories in apps and packages, show only leaf folder names
    selected_name=$(find apps packages -maxdepth 1 -type d -not -path "apps" -not -path "packages" 2>/dev/null | xargs -I {} basename {} | fzf --height=20 --reverse)
    
    if [[ -n "$selected_name" ]]; then
        # Find the full path for the selected name
        full_path=$(find apps packages -maxdepth 1 -type d -name "$selected_name" 2>/dev/null | head -n1)
        if [[ -n "$full_path" ]]; then
            echo "Opening: $full_path" >&2
            code "$full_path"
        fi
    fi
}

alias opf='open_project_folder'