#!/bin/bash

move_issue_state() {
    local issue_number=""
    local new_state=""
    local debug_mode=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--issue)
                issue_number="$2"
                shift 2
                ;;
            -s|--state)
                new_state="$2"
                shift 2
                ;;
            -d|--debug)
                debug_mode=true
                shift
                ;;
            -h|--help)
                echo "Usage: move_issue_state [OPTIONS]"
                echo "Options:"
                echo "  -i, --issue ISSUE_NUMBER    Issue number to update"
                echo "  -s, --state STATE           New state (ToDo|InDev|AwaitingReview|Done)"
                echo "  -d, --debug                 Enable debug output"
                echo "  -h, --help                  Show this help message"
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done
    
    if [[ -z "$new_state" ]]; then
        echo "Error: New state is required" >&2
        echo "Valid states: ToDo, InDev, AwaitingReview, Done" >&2
        return 1
    fi
    
    case "$new_state" in
        "ToDo")
            new_label="P::TO DO"
            ;;
        "InDev")
            new_label="P::IN DEV"
            ;;
        "AwaitingReview")
            new_label="P::AWAITING REVIEW"
            ;;
        "Done")
            new_label="P::DONE"
            ;;
        *)
            echo "Error: Invalid state '$new_state'" >&2
            echo "Valid states: ToDo, InDev, AwaitingReview, Done" >&2
            return 1
            ;;
    esac
    
    all_state_labels=("P::TO DO" "P::IN DEV" "P::AWAITING REVIEW" "P::DONE")
    
    if [[ -z "$issue_number" ]]; then
        current_branch=$(git branch --show-current)
        if [[ $current_branch =~ ([0-9]+) ]]; then
            issue_number="${BASH_REMATCH[1]}"
            [[ "$debug_mode" == true ]] && echo "Extracted issue number $issue_number from branch: $current_branch" >&2
        else
            echo "Error: Could not extract issue number from branch name: $current_branch" >&2
            [[ "$debug_mode" == true ]] && echo "Please specify the issue number manually or ensure your branch name contains the issue number" >&2
            return 1
        fi
    fi
    
    issue_json=$(glab issue view "$issue_number" --output=json)
    current_labels=$(echo "$issue_json" | jq -r '.labels[]' 2>/dev/null)
    issue_title=$(echo "$issue_json" | jq -r '.title' 2>/dev/null)
    
    [[ "$debug_mode" == true ]] && echo "Current issue: #$issue_number - $issue_title" >&2
    [[ "$debug_mode" == true ]] && echo "Current labels: $(echo "$current_labels" | tr '\n' ',' | sed 's/,$//')" >&2
    
    current_state_label=""
    while IFS= read -r label; do
        for state_label in "${all_state_labels[@]}"; do
            if [[ "$label" == "$state_label" ]]; then
                current_state_label="$label"
                break 2
            fi
        done
    done <<< "$current_labels"
    
    if [[ -n "$current_state_label" ]]; then
        [[ "$debug_mode" == true ]] && echo "Current state: $current_state_label" >&2
    else
        [[ "$debug_mode" == true ]] && echo "No current state label found" >&2
    fi
    
    if [[ "$current_state_label" == "$new_label" ]]; then
        [[ "$debug_mode" == true ]] && echo "Issue #$issue_number is already in state: $new_state" >&2
        return 0
    fi
    
    [[ "$debug_mode" == true ]] && echo "Moving issue #$issue_number from '$current_state_label' to '$new_state'" >&2
    
    glab_args=("issue" "update" "$issue_number")
    
    if [[ -n "$current_state_label" ]]; then
        glab_args+=("--unlabel" "$current_state_label")
    fi
    
    labels_to_add=("$new_label")
    
    if [[ "$new_state" == "AwaitingReview" ]]; then
        labels_to_add+=("Needs Engineering Approval" "Ready for QA")
    fi
    
    existing_non_state_labels=()
    while IFS= read -r label; do
        is_state_label=false
        for state_label in "${all_state_labels[@]}"; do
            if [[ "$label" == "$state_label" ]]; then
                is_state_label=true
                break
            fi
        done
        if [[ "$is_state_label" == false && -n "$label" ]]; then
            existing_non_state_labels+=("$label")
        fi
    done <<< "$current_labels"
    
    for label in "${existing_non_state_labels[@]}" "${labels_to_add[@]}"; do
        glab_args+=("--label" "$label")
    done
    
    command_string="glab ${glab_args[*]}"
    [[ "$debug_mode" == true ]] && echo "Command to execute: $command_string" >&2
    
    glab "${glab_args[@]}"
}

alias mis='move_issue_state'