#!/bin/bash

# RickScripts Bash Completion
# Auto-completion for all RickScripts functions and their parameters

# Helper function to complete common Git branches
_git_branches() {
    git branch -a 2>/dev/null | sed 's/^[[:space:]]*//' | sed 's/^\*//' | sed 's/^[[:space:]]*//' | grep -v "HEAD"
}

# Helper function to complete issue states
_issue_states() {
    echo "ToDo InDev AwaitingReview Done"
}

# Completion for move_issue_state
_move_issue_state() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="-i --issue -s --state -d --debug -h --help"
    
    case ${prev} in
        -s|--state)
            COMPREPLY=($(compgen -W "$(_issue_states)" -- ${cur}))
            return 0
            ;;
        -i|--issue)
            # Could potentially complete with recent issue numbers, but that's complex
            return 0
            ;;
    esac
    
    if [[ ${cur} == -* ]]; then
        COMPREPLY=($(compgen -W "${opts}" -- ${cur}))
    fi
}

# Completion for new_merge_request
_new_merge_request() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="-i --issue -t --title --template -d --description --how-to-test -h --help"
    
    case ${prev} in
        --template)
            COMPREPLY=($(compgen -f -- ${cur}))
            return 0
            ;;
        -i|--issue|-t|--title|-d|--description|--how-to-test)
            return 0
            ;;
    esac
    
    if [[ ${cur} == -* ]]; then
        COMPREPLY=($(compgen -W "${opts}" -- ${cur}))
    fi
}

# Completion for remove_history_duplicates
_remove_history_duplicates() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="-r --restore -h --help"
    
    if [[ ${cur} == -* ]]; then
        COMPREPLY=($(compgen -W "${opts}" -- ${cur}))
    fi
}

# Generic completion for functions with only help option
_generic_help_only() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    opts="-h --help"
    
    if [[ ${cur} == -* ]]; then
        COMPREPLY=($(compgen -W "${opts}" -- ${cur}))
    fi
}

# Register completions for all functions and their aliases
complete -F _move_issue_state move_issue_state mis
complete -F _new_merge_request new_merge_request nmr
complete -F _remove_history_duplicates remove_history_duplicates rhd
complete -F _generic_help_only remove_history_item rhi
complete -F _generic_help_only clear_node_modules cnm
complete -F _generic_help_only get_git_stash ggs
complete -F _generic_help_only open_project_folder opf
complete -F _generic_help_only remove_local_branches_that_are_merged rlb
complete -F _generic_help_only switch_branch sb
complete -F _generic_help_only switch_merge_request smr

# Also provide basic completion for the main function names
_rick_scripts_functions() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    
    local functions="clear_node_modules get_git_stash move_issue_state new_merge_request open_project_folder remove_history_duplicates remove_history_item remove_local_branches_that_are_merged switch_branch switch_merge_request"
    local aliases="cnm ggs mis nmr opf rhd rhi rlb sb smr"
    
    COMPREPLY=($(compgen -W "${functions} ${aliases}" -- ${cur}))
}

# Enable completion for tab completion of function names in general
complete -F _rick_scripts_functions -o default rick_scripts

echo "RickScripts bash completion loaded!"
echo "Tab completion is now available for all functions and their parameters."