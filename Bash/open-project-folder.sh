#!/bin/bash

open_project_folder() {
    selected_folder=$(fd . --type d --exclude node_modules | fzf --height=20 --reverse)
    
    if [[ -n "$selected_folder" ]]; then
        code "$selected_folder"
    fi
}

alias opf='open_project_folder'